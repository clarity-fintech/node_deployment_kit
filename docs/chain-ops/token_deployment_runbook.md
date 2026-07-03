# CLRTY Token Deployment Runbook

**Launch model:** L1-only. The authoritative $CLRTY token is the **native L1 coin** (`uclrty` on chain `clrty-1`), minted entirely at genesis — not an EVM ERC-20 deploy.

EVM (`ClrtyOFTv2`, `ClrtyImmutableToken`) and Solana SPL mirrors are **Phase 10 deferred** — do not deploy for L1 launch. See [DEFERRED_BRIDGE.md](../l1_launch/DEFERRED_BRIDGE.md).

---

## Which contract is "final"?

| Asset | Role | Deploy for L1? | Path |
|-------|------|----------------|------|
| **L1 native `uclrty`** | Primary listing token | **Yes** | `boot/genesis_entropy.json` + genesis seal |
| `ClrtyOFTv2.sol` | LayerZero omnichain mirror | No (Phase 10) | `bridge_perimeter/fma/contracts/` |
| `ClrtyImmutableToken.sol` | Fixed-supply EVM reference | No (Phase 10) | same |
| `clrty_spl_token` (Anchor) | Solana mirror | No (Phase 10) | `bridge_perimeter/programs/` |

---

## Deployment status (this audit)

| Item | Result |
|------|--------|
| **Network deployed** | None — no mainnet or public testnet live |
| **Transaction hash** | N/A |
| **Blockers** | See [§ External blockers](#external-blockers) |

Preflight validation **passed** locally (genesis verify, listing config, compliance pack). Deployment was **not executed** — production keys, RPC, and board GO are absent.

---

## Preflight (run now — no keys required)

```bash
cd "$(git rev-parse --show-toplevel)"

# 1. Metadata + listing alignment
cargo test -p clrty-substrate listing_config
cargo test -p clrty-substrate supply_checksum

# 2. Genesis checksum
cargo run -p clarity-cli -- chain genesis-verify
cargo run -p clrty-substrate --bin clarityd -- genesis-verify

# 3. Listing compliance pack
bash scripts/audit/generate_listing_compliance_pack.sh

# 4. Full L1 simulation (omit --quick for full audit)
bash scripts/predeploy/l1_launch_simulation.sh --quick
```

Review scorecard: [`listing_readiness_scorecard.md`](listing_readiness_scorecard.md).

---

## L1 genesis deploy sequence (operators — when blockers cleared)

### Prerequisites

- [ ] Board tokenomics sign-off (`tokenomics_manifest.json` `sign_off` filled)
- [ ] Third-party audit complete ([`EXTERNAL_AUDIT_REQUIRED.md`](../audit/EXTERNAL_AUDIT_REQUIRED.md))
- [ ] Production `clarityd` + validator set provisioned
- [ ] HSM-held validator keys
- [ ] GO authorization ([`go_sequence.md`](../launch/go_sequence.md))

### Steps

```bash
# 1. Release build
cargo build --workspace --release

# 2. Final genesis verification on production config
cargo run -p clarity-cli -- chain genesis-verify

# 3. Genesis seal ceremony (production state — board witness required)
#    Uses token_core/blue_code/genesis_hardening.rs apply_final_seal
#    ATU phase p56/p64 validates seal integrity in CI

# 4. Bootstrap genesis block
cargo run -p clrty-substrate --bin clarityd -- genesis-verify
# Output includes genesis block from genesis_block_builder

# 5. Start validator(s)
export CLRTY_L1_RPC=https://rpc.clrty.network   # production URL
cargo run -p clrty-substrate --release --bin clarityd -- status

# 6. Start operator API
cargo run -p clrty-api --release

# 7. Post-deploy verification
curl "${CLRTY_L1_RPC}/v1/status"
curl "${CLRTY_L1_RPC}/v1/indexer/clrty-l1"
bash scripts/audit/generate_listing_compliance_pack.sh
```

Record genesis state root, seal hash, and block height in the data room.

---

## Existing deploy scripts (reference)

| Script | Purpose | L1 launch? |
|--------|---------|------------|
| `scripts/predeploy/l1_launch_simulation.sh` | Pre-GO simulation | Preflight only |
| `scripts/fma/deploy_mainnet.sh` | Foundry build + placeholder deployment JSON | Phase 10 EVM |
| `CLRTY_SUBSTRATE/bridge_perimeter/scripts/deploy_checklist.sh` | LZ OFT checklist | Phase 10 |
| `scripts/multisig/deploy_custody.sh` | Safe custody | Deferred settlement |

`scripts/fma/deploy_mainnet.sh` builds contracts and writes placeholder files under `fma/contracts/deployments/` — it does **not** broadcast mainnet transactions without `forge` + `PRIVATE_KEY` + RPC.

---

## Phase 10 EVM deploy (deferred — do not run at L1 GO)

When bridge phase activates and `EXTERNAL_BLOCKERS` for bridge are cleared:

```bash
# Requires: forge, ETH_RPC_URL, DEPLOYER_PRIVATE_KEY (HSM)
cd CLRTY_SUBSTRATE/bridge_perimeter/fma/contracts
forge build && forge test -vv

# ClrtyOFTv2 — per chain (example Ethereum EID 30101)
forge create src/ClrtyOFTv2.sol:ClrtyOFTv2 \
  --constructor-args <LZ_ENDPOINT> 30101 <OWNER_MULTISIG> \
  --rpc-url "$ETH_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY"

# Record address in deployments/fma-ethereum.json
bash scripts/fma/deploy_mainnet.sh   # refresh artifact stubs after live deploy
```

Local Anvil smoke (no mainnet keys):

```bash
anvil &
export ETH_RPC_URL=http://127.0.0.1:8545
export DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge create src/ClrtyImmutableToken.sol:ClrtyImmutableToken \
  --constructor-args 16000000000000000 \
  --rpc-url "$ETH_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY"
```

---

## External blockers

From [`EXTERNAL_BLOCKERS.md`](../l1_launch/EXTERNAL_BLOCKERS.md):

| Blocker | Blocks |
|---------|--------|
| Third-party security audit | Exchange + mainnet GO |
| Board tokenomics sign-off | Genesis seal on production |
| Production `clarityd` networking | Live chain |
| Public mainnet RPC + validators | Any deployment |
| HSM key custody | Validator / deploy keys |
| KYC / SAFT / GO authorization | TGE |

---

## Post-deploy documentation updates

After live L1 genesis:

1. Fill contract address field in scorecard (native: chain `clrty-1`, denom `uclrty`)
2. Add block explorer URL to [`listing_readiness_scorecard.md`](listing_readiness_scorecard.md)
3. Regenerate `var/compliance/listing_compliance_report.json`
4. Update [`investor_kit.md`](../investor_kit.md) with live RPC + genesis height
