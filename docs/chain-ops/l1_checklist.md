# CLRTY L1-Only Launch Checklist (Tasks 41–60)

**Scope:** Sovereign CLRTY L1 only — chain `clrty-1`, denom `uclrty`. Bridge (LZ/NTT) and Ethereum Safe settlement are **Deferred — Phase 10**. See [DEFERRED_BRIDGE.md](DEFERRED_BRIDGE.md) and [DEFERRED_SETTLEMENT.md](DEFERRED_SETTLEMENT.md).

**Nexus launch order:** [NEXUS_REPOSITORY.md](../architecture/NEXUS_REPOSITORY.md) · [LAUNCH_STAGES.md](../launch/LAUNCH_STAGES.md) · [NANO_ORGANIZATION_100.md](../launch/NANO_ORGANIZATION_100.md) · `make verify-stage-0` … `make verify-stage-5`

**Federated Nexus scaffold:** [`manifests/nexus_modules.json`](../../manifests/nexus_modules.json) · [`var/launch/readiness.json`](../../var/launch/readiness.json) · [`gates/STAGE_GATES.json`](../../gates/STAGE_GATES.json)

**Legend:** Done | Partial | Deferred | External

| Task | L1 item | Status | Artifact |
|------|---------|--------|----------|
| 41 | Native token standard (`uclrty`, CCR Sets) | Done | `token_core/`, `genesis_entropy.json` |
| 42 | L1 node env (`clarityd`, testnet_manifold) | Partial | [mainnet_environment_provision.md](../omnichain/mainnet_environment_provision.md) |
| 43 | 16M hard cap | Done | `boot/mod.rs`, `constants.rs` |
| 44 | 9 decimals | Done | `global_manifold_state.rs` |
| 45 | No admin mint/blacklist | Done | `genesis_entropy.json`, `genesis_hardening.rs` |
| 46 | L1 compile gate | Done | `cargo test --workspace` |
| 47 | Internal substrate security audit | Partial | `scripts/audit/l1_substrate_audit.sh` |
| 48 | L1 governance + validator set | Partial | `governance_substrate/`, `validator_singularity_set.json` |
| 49 | 48h upgrade timelock | Done | `upgrade_timelock_controller.rs` |
| 50 | Validator bonding / tier weights | Partial | `balance_bonding.rs` |
| 51 | Snapshot governance | Done | `snapshot_voting.rs`, `/v1/governance/vote` |
| 52 | L1 indexer (`ClrtyL1`) | Partial | `indexer_worker.rs`, [indexer_production.md](../omnichain/indexer_production.md) |
| 53 | REST/WebSocket API | Done | `clrty-api` |
| 54 | L1 consensus alerts | Partial | `alerting_infrastructure.rs` |
| 55 | B2B institutional panel | Partial | `frontend/b2b-panel/` |
| 56 | Native CLRTY wallet UI | Partial | `frontend/web3-ui/`, [consumer_wallet_guide.md](../consumer_wallet_guide.md) |
| 57 | L-DNET + `sim-block` stress | Partial | `scripts/stress/l1_concurrency.sh` |
| 58 | L1 API dry-run | Partial | `scripts/integration/sandbox_dry_run.sh` |
| 59 | L1 integration docs | Done | `integration_guide.md`, `master_blueprint.md` |
| 60 | Code freeze + L1 pre-deploy sim | Partial | `scripts/predeploy/l1_launch_simulation.sh` |

## User-added launch gates

| Item | In-repo | External |
|------|---------|----------|
| **Final smart contract audited** | [internal_audit_report.md](../audit/internal_audit_report.md) + `l1_substrate_audit.sh` | Third-party substrate audit PDF |
| **Security audit passed (external firm)** | [SECURITY_AUDIT_COMPLETION_GATES.md](../audit/SECURITY_AUDIT_COMPLETION_GATES.md), [EXTERNAL_AUDIT_REQUIRED.md](../audit/EXTERNAL_AUDIT_REQUIRED.md), [audit_data_room.md](../audit/audit_data_room.md) | Gates 1–5: freeze → audit → remediate → certify → publish |
| **Tokenomics finalized and locked** | [TOKENOMICS_LOCKED.md](../tokenomics/TOKENOMICS_LOCKED.md), `tokenomics_manifest.json` | Board sign-off + genesis seal ceremony |
| **CEX listing config (INF-24)** | [mainnet_listing_config.md](../infrastructure/mainnet_listing_config.md), `mainnet_listing_config.json`, `generate_listing_compliance_pack.sh` | CEX outreach / DDQ attachment |
| **Bridge connection audit (INF-25)** | [bridge_state_verification.md](../infrastructure/bridge_state_verification.md), `verify_bridge_connection_hashes.sh` | Phase 10 bridge activation (deferred) |
| **Full pretest 100 (systemic)** | [full_pretest_100.md](../test/full_pretest_100.md), `full_pretest.sh` | Before Phase 4 / CEX — Zone 1 fail freezes tokenization |
| **Launch readiness (all-in-one)** | [MASS_SECURITY_ARCHITECTURE.md](../security/MASS_SECURITY_ARCHITECTURE.md), `scripts/launch/launch_readiness.sh` | 99.9% gate — pretest + validation + compliance + stress |

## Mainnet contract deployment gates

Verified by `scripts/launch/verify_mainnet_contract_gates.sh` → `var/launch/mainnet_contract_gates.json`:

| Gate | In-repo verification |
|------|----------------------|
| Token contract deployed to mainnet (final version) | L1 native `uclrty` · genesis verify + listing + supply checksum |
| Vesting contracts linked to SAFT allocations | `mainnet_listing_config.json` SAFT tiers + `ecosystem_vesting_escrow` tests |
| Multi-signature custody wallets configured + verified | Safe + Squads manifests · `multisig_config` custody_ready |
| Token distribution schedule encoded + tested | Unlock windows + category allocations · listing/supply tests |
| On-chain verification passes across all contract layers | Listing compliance pack + security layers gate |

```bash
bash scripts/launch/verify_mainnet_contract_gates.sh
bash scripts/investor/build_treasury_data.sh   # sync to investor dashboard
```

## Validation

```bash
bash scripts/launch/launch_readiness.sh --continue --skip-foundry
bash scripts/audit/l1_substrate_audit.sh
cargo run -p clarity-cli -- chain genesis-verify
bash scripts/predeploy/l1_launch_simulation.sh
bash scripts/integration/sandbox_dry_run.sh
bash scripts/stress/l1_concurrency.sh
bash scripts/audit/generate_listing_compliance_pack.sh
bash scripts/audit/verify_bridge_connection_hashes.sh
bash scripts/test/full_pretest.sh --continue --skip-foundry
bash scripts/investor/build_treasury_data.sh
```

## External blockers

See [EXTERNAL_BLOCKERS.md](EXTERNAL_BLOCKERS.md).
