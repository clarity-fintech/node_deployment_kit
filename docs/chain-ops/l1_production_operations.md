# L1 Production Operations — CLRTY-1

Day-2 operations runbook for **clrty-1** mainnet.

**Provision:** [l1_rpc_provision.md](l1_rpc_provision.md) · **Scope:** [CLRTY1_ONLY_SCOPE.md](../chain/CLRTY1_ONLY_SCOPE.md)

---

## Operator roles

| Role | Responsibility |
|------|----------------|
| **Validator ops** | clarityd uptime, sentry health, slashing avoidance |
| **RPC ops** | clrty-api HA, rate limits, incident response |
| **Security** | MDA/MSD task status, VIS alerts, key rotation |
| **Listing** | CEX metadata, compliance pack refresh |
| **Clarity Fortress** | dev.clrty.io/labs funnel, faucet policy |

---

## Daily checklist

```bash
# 1. Chain health
cargo run -p clarity-cli -- node genesis-verify --plain
curl -s "$CLRTY_L1_RPC/v1/status" | jq '.chain_id, .slot'

# 2. Bridge deferred (expected)
cargo run -p clarity-cli -- bridge status --plain

# 3. Security layers
bash scripts/audit/verify_security_layers.sh

# 4. Clarity Fortress smoke
bash scripts/labs/verify_labs_smoke.sh

# 5. Supply checksum
cargo test -p clrty-substrate supply_checksum -- --nocapture
```

---

## Incident response

| Severity | Trigger | Action |
|----------|---------|--------|
| **P1** | RPC down > 5 min | Failover LB; page RPC ops |
| **P1** | Genesis hash mismatch | Halt all ops; exec immutability audit |
| **P2** | λ spike sustained | Review entropy sink; sentinel broadcast |
| **P2** | Supply checksum drift | Pause listing; compliance review |
| **P3** | Clarity Fortress walkthrough 4xx | Regenerate manifest; redeploy API |
| **P3** | Faucet abuse | Rate-limit; disable on mainnet |

Escalation: Safe monitor → governance timelock (48h) per [OPERATIONAL_NANO_LOOP_12.md](../launch/OPERATIONAL_NANO_LOOP_12.md)

---

## Key rotation

| Secret | Location | Rotation |
|--------|----------|----------|
| `CLRTY_L1_RPC` bearer | Vault | Quarterly |
| Validator keys | HSM | On compromise only |
| `MASTER_COMPLIANCE_PRIVATE_KEY` | HSM | Annual |
| `KYC_WEBHOOK_SECRET` | Vault | On staff change |
| Alchemy API key | `.env.l1` | On exposure |

**Never** commit `.env.l1` — see `.gitignore`.

---

## Deployment cadence

| Artifact | Cadence | Command |
|----------|---------|---------|
| clrty-api | Weekly patch | `cargo build -p clrty-api --release` |
| Clarity Fortress manifest | On walkthrough change | `python3 scripts/clarity-wallet/generate_labs_manifest.py` |
| Listing pack | Pre-CEX milestone | `bash scripts/listing/build_cex_integration_pack.sh` |
| Compliance report | Weekly | `bash scripts/audit/generate_listing_compliance_pack.sh` |

---

## Monitoring targets

| Metric | Target | Source |
|--------|--------|--------|
| RPC p99 latency | < 200 ms | LB metrics |
| `getHealth` success | > 99.9% | Synthetic probe |
| Validator uptime | > 99.5% | sentry dashboard |
| Clarity Fortress smoke | 100% pass | CI + cron |
| MSD-100 launch readiness | partial → implemented | manual gate |

---

## Maintenance windows

- **Preferred:** Tuesday 06:00–08:00 UTC
- Announce 72h ahead on @CLRTY_alerts
- Run full validation before close:

```bash
bash scripts/test/full_validation.sh
```

---

## Phase 10 handoff (future)

When omnichain activates:

1. Re-run bridge connection hash audit
2. Deploy FMA contracts per `production_matrix.clrty`
3. Enable `fma-relayer` producer with HSM keys
4. Update RPC provider tables (bridge column → live)
5. Revise [CLRTY1_ONLY_SCOPE.md](../chain/CLRTY1_ONLY_SCOPE.md) status
