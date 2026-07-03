#!/usr/bin/env bash
# Batch pool ingress from liquidity_pools_manifest.json (native-first)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/CLRTY_SUBSTRATE/boot/liquidity_pools_manifest.json"
REPORT="$ROOT/var/launch/pool_ingress_batch.json"
BATCH_SIZE="${BATCH_SIZE:-10}"
RPC="${CLRTY_L1_RPC_URL:-https://rpc.clarity-fintech.com}"

log() { echo "[pool-ingress-batch] $*"; }
mkdir -p "$(dirname "$REPORT")"

if [[ ! -f "$MANIFEST" ]]; then
  bash "$ROOT/scripts/deploy/liquidity_pool_bootstrap.sh" --dry-run
fi

python3 - <<PY
import json, urllib.request
from datetime import datetime, timezone

manifest_path = "$MANIFEST"
rpc = "$RPC"
batch = int("$BATCH_SIZE")

with open(manifest_path) as f:
    m = json.load(f)

pools = m.get("pools", [])
results = []

def health():
    try:
        req = urllib.request.Request(
            rpc,
            data=json.dumps({"jsonrpc":"2.0","id":1,"method":"getHealth","params":[]}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()).get("result", {}).get("status") == "ok"
    except Exception:
        return False

healthy = health()

for i, pool in enumerate(pools[:batch]):
    entry = {
        "pool_id": pool.get("id"),
        "pair": pool.get("pair"),
        "type": pool.get("type"),
        "status": "queued" if healthy else "deferred_rpc_down",
    }
    results.append(entry)

report = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "chain_id": "clrty-1",
    "batch_size": batch,
    "processed": len(results),
    "rpc_healthy": healthy,
    "pools": results,
}
with open("$REPORT", "w") as f:
    json.dump(report, f, indent=2)
print(f"processed {len(results)} pools → $REPORT")
PY

log "OK"
