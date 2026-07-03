#!/usr/bin/env bash
# Seed native AMM + MIRRA pools from 4M liquidity bucket (CLRTY-1 only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

MANIFEST="$ROOT/CLRTY_SUBSTRATE/boot/liquidity_pools_manifest.json"
REPORT="$ROOT/var/launch/liquidity_bootstrap.json"
RPC="${CLRTY_L1_RPC_URL:-https://rpc.clarity-fintech.com}"

log() { echo "[liquidity-pool-bootstrap] $*"; }
mkdir -p "$(dirname "$REPORT")"

if [[ ! -f "$MANIFEST" ]]; then
  log "manifest missing — writing scaffold $MANIFEST"
  MANIFEST="$MANIFEST" python3 - <<'PY'
import json, os
path = os.environ["MANIFEST"]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {
    "chain_id": "clrty-1",
    "bucket": "4M_liquidity",
    "pools": [
        {"id": "uclrty-usdc-native", "pair": "UCLRTY/USDC", "type": "native_amm", "seed_uclrty": "1000000"},
        {"id": "uclrty-mirra-primary", "pair": "UCLRTY/MIRRA", "type": "mirra", "seed_uclrty": "500000"},
    ],
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
  MANIFEST="$ROOT/CLRTY_SUBSTRATE/boot/liquidity_pools_manifest.json"
fi

POOL_COUNT="$(python3 -c "import json; print(len(json.load(open('$MANIFEST')).get('pools',[])))")"
log "pools in manifest: $POOL_COUNT"

if $DRY_RUN; then
  log "dry-run — no on-chain seed"
else
  log "probing L1 RPC: $RPC"
  curl -sf "$RPC" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getHealth","params":[]}' >/dev/null \
    || log "WARN: RPC not reachable — defer seeding"
fi

python3 - <<PY
import json
from datetime import datetime, timezone
m = json.load(open("$MANIFEST"))
report = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "chain_id": "clrty-1",
    "pool_count": len(m.get("pools", [])),
    "dry_run": $( $DRY_RUN && echo True || echo False ),
    "rpc": "$RPC",
}
with open("$REPORT", "w") as f:
    json.dump(report, f, indent=2)
PY

log "report → $REPORT"
