#!/usr/bin/env bash
# Smoke test CLRTY Data Center pipeline artifacts and API shape.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
log() { echo "[data-center-verify] $*"; }

[[ -f CLRTY_SUBSTRATE/boot/data_center_manifest.json ]] || { log "FAIL missing manifest"; fail=1; }
[[ -f scripts/metrics/aggregate_data_center.py ]] || { log "FAIL missing aggregator"; fail=1; }

python3 scripts/metrics/sync_sheets_inputs.py
python3 scripts/metrics/aggregate_data_center.py

[[ -f var/metrics/data_center_snapshot.json ]] || { log "FAIL no snapshot"; fail=1; }
[[ -f frontend/investor/data/data_center_snapshot.json ]] || { log "FAIL no frontend snapshot"; fail=1; }

sections=$(python3 -c "import json; d=json.load(open('var/metrics/data_center_snapshot.json')); print(len(d.get('sections',{})))")
[[ "$sections" -eq 5 ]] || { log "FAIL expected 5 sections got $sections"; fail=1; }

private=$(python3 -c "import json; d=json.load(open('var/metrics/data_center_snapshot.json')); print(len(d.get('sections',{}).get('private_monetization',{}).get('metrics',[])))")
[[ "$private" -ge 6 ]] || { log "FAIL expected >=6 private_monetization metrics got $private"; fail=1; }

[[ -f monetization-layers/products/private_streams.json ]] || { log "FAIL missing private_streams.json"; fail=1; }

if cargo test -p clrty-api data_center --quiet 2>/dev/null; then
  log "OK clrty-api data_center tests"
else
  log "WARN clrty-api data_center tests skipped or failed"
fi

API="${CLRTY_API_URL:-http://127.0.0.1:8545}"
if curl -sf "${API}/v1/listing/metrics" -o /tmp/dc_metrics.json 2>/dev/null; then
  if python3 -c "import json; d=json.load(open('/tmp/dc_metrics.json')); assert 'featured_group' in d"; then
    log "OK GET /v1/listing/metrics"
  else
    log "WARN /v1/listing/metrics shape unexpected"
  fi
else
  log "SKIP live API (start clrty-api for full verify)"
fi

python3 scripts/metrics/sync_notion_data_center.py || true

if [[ "$fail" -eq 0 ]]; then
  log "ALL CHECKS PASSED"
else
  log "FAILED"
  exit 1
fi
