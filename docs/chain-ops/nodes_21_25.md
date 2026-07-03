# Infrastructure & Synchronization — INF-21–25

Distinct from **Phase 2 Compliance Tasks 21–25** (legal). These are infrastructure sync deliverables; **VIS-N21–N25** maps the same invariants in [`VIS_CLRITY_PROTOCOL_MAP.md`](../compliance/VIS_CLRITY_PROTOCOL_MAP.md).

| Node | Title | Deliverable | Status |
|------|-------|-------------|--------|
| **INF-21** | Validator mesh sync | [`atmospheric_sync.rs`](../../CLRTY_SUBSTRATE/token_core/blue_code/atmospheric_sync.rs), [`validator_singularity_set.json`](../../CLRTY_SUBSTRATE/boot/validator_singularity_set.json), `scripts/stress/l1_concurrency.sh` | Partial |
| **INF-22** | Indexer ↔ L1 heartbeat | [`indexer_worker.rs`](../../CLRTY_SUBSTRATE/data_lake_pipeline/indexer_worker.rs), [`indexer_production.md`](../omnichain/indexer_production.md), `phase9_integration.rs` | Partial |
| **INF-23** | Gatekeeper ↔ settlement sync | [`clrty-gatekeeper`](../../CLRTY_SUBSTRATE/src/bin/clrty-gatekeeper.rs), [`vis_identity_gatekeeper_ops.md`](../compliance/data_room/technical/vis_identity_gatekeeper_ops.md) | Implemented |
| **INF-24** | Mainnet listing config | [`mainnet_listing_config.json`](../../CLRTY_SUBSTRATE/boot/mainnet_listing_config.json), [`listing_config.rs`](../../CLRTY_SUBSTRATE/settlement/listing_config.rs), [`mainnet_listing_config.md`](mainnet_listing_config.md) | **Done** |
| **INF-25** | Bridge state verification | [`connection_registry.json`](../../CLRTY_SUBSTRATE/bridge_perimeter/connection_registry.json), [`bridge_connection_audit.rs`](../../CLRTY_SUBSTRATE/bridge_perimeter/bridge_connection_audit.rs), [`bridge_state_verification.md`](bridge_state_verification.md) | **Done** |

## VIS sync plane (N21–N25)

| VIS Node | Sync invariant | Verification |
|----------|----------------|--------------|
| N21 | PoC gossip / BFT liveness | `poc_consensus/`, `l1_concurrency.sh` |
| N22 | Indexer head == finalized block | `indexer_worker.rs`, phase9 tests |
| N23 | Consistent λ,H,E,R across API cluster | `/v1/status` smoke |
| N24 | Sim event_hash chain | `/v1/sim/merkle`, Events 21–25 BFT inject |
| N25 | Connection hashes match registry | `verify_bridge_connection_hashes.sh` |

## Verification commands

```bash
cargo test -p clrty-substrate settlement listing_config
cargo test -p clrty-substrate bridge_connection_audit
bash scripts/audit/generate_listing_compliance_pack.sh
bash scripts/audit/verify_bridge_connection_hashes.sh
cargo test -p clarity-cli bridge_status_plain
bash scripts/stress/l1_concurrency.sh
```

## Cross-links

- [`100_task_ledger.md`](../100_task_ledger.md) — Infrastructure & sync section
- [`l1_launch/checklist.md`](../l1_launch/checklist.md) — INF-24 CEX DDQ row
- [`exchange_listing_compliance.md`](../compliance/data_room/technical/exchange_listing_compliance.md) — Task 38 pack
- [`DOCUMENTATION_INDEX.md`](../DOCUMENTATION_INDEX.md)
