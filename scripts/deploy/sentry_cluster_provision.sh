#!/usr/bin/env bash
# Sentry cluster provision scaffold — clrty-api on sentries, tunnel → sentries only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/CLRTY_SUBSTRATE/boot/l1_network_manifest.json"
REPORT="$ROOT/var/launch/sentry_cluster.json"

log() { echo "[sentry-cluster] $*"; }
mkdir -p "$(dirname "$REPORT")"

if [[ ! -f "$MANIFEST" ]]; then
  log "writing scaffold $MANIFEST"
  MANIFEST="$MANIFEST" python3 - <<'PY'
import json, os
path = os.environ["MANIFEST"]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {
    "chain_id": "clrty-1",
    "sentry_count": 3,
    "core_validator_count": 3,
    "block_target_ms": 250,
    "bootnodes": [],
    "sentries": [
        {"id": "sentry-1", "host": "sentry-1.clrty.internal", "clrty_api_port": 8545},
        {"id": "sentry-2", "host": "sentry-2.clrty.internal", "clrty_api_port": 8545},
        {"id": "sentry-3", "host": "sentry-3.clrty.internal", "clrty_api_port": 8545},
    ],
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
  MANIFEST="$ROOT/CLRTY_SUBSTRATE/boot/l1_network_manifest.json"
fi

python3 - <<PY
import json
from datetime import datetime, timezone
m = json.load(open("$MANIFEST"))
report = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "chain_id": "clrty-1",
    "sentry_count": len(m.get("sentries", [])),
    "bootnode_count": len(m.get("bootnodes", [])),
    "note": "Deploy clrty-api systemd units on each sentry; point CLRTY_L1_ORIGIN tunnel to LB",
    "systemd_unit": "clrty-api.service",
}
with open("$REPORT", "w") as f:
    json.dump(report, f, indent=2)
PY

log "manifest: $MANIFEST"
log "report → $REPORT"
log "OK — document DO/AWS layout in docs/omnichain/l1_production_operations.md"
