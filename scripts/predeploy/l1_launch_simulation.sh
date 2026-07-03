#!/usr/bin/env bash
# CLRTY L1 pre-deployment simulation (Task 60 — L1-only)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
QUICK=false
for arg in "$@"; do
  if [[ "$arg" == "--quick" ]]; then QUICK=true; fi
done
echo "=== CLRTY L1 launch simulation${QUICK:+ (quick)} ==="
if [[ "$QUICK" == true ]]; then
  cargo test --workspace --lib 2>/dev/null || cargo test --workspace
else
  bash scripts/audit/l1_substrate_audit.sh
fi
cargo run -p clarity-cli --bin clrty -- chain genesis-verify
cargo run -p clrty-substrate --bin clarityd -- genesis-verify
cargo run -p clrty-substrate --bin clarityd -- status
cargo run -p clrty-substrate --bin clarityd -- sim-block
bash scripts/integration/sandbox_dry_run.sh
if [[ "$QUICK" != true ]]; then
  bash scripts/stress/l1_concurrency.sh 20
fi
echo "CLRTY L1 (clrty-1) pre-deployment simulation complete"
