#!/usr/bin/env bash
# Clarity Fortress smoke verification — walkthrough artifacts + optional live RPC
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
check() {
  local name="$1"
  shift
  if "$@"; then
    echo "OK  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name"
    FAIL=$((FAIL + 1))
  fi
}

check "walkthrough steps.json exists" test -f frontend/labs/walkthrough/steps.json
check "labs-api.js exists" test -f frontend/shared/labs-api.js
check "walkthrough has 12 steps" python3 -c "
import json
d=json.load(open('frontend/labs/walkthrough/steps.json'))
assert d.get('chain_id')=='clrty-1'
assert len(d.get('steps',[]))==12
"
check "labs manifest generator" python3 scripts/clarity-wallet/generate_labs_manifest.py
check "boot labs_manifest.json" test -f CLRTY_SUBSTRATE/boot/labs_manifest.json
check "wallet clrty_labs_manifest.json" test -f clarity-wallet/labs/manifests/clrty_labs_manifest.json
check "msd nano tasks (100)" python3 -c "
import json
m=json.load(open('CLRTY_SUBSTRATE/boot/msd_nano_tasks_manifest.json'))
assert len(m['tasks'])==100
"
check "chain spec doc" test -f docs/chain/clrty-1.md

RPC="${CLRTY_L1_RPC:-http://127.0.0.1:8545}"
if curl -sf --max-time 3 "${RPC}/v1/status" >/dev/null 2>&1; then
  check "live /v1/status" curl -sf --max-time 5 "${RPC}/v1/status" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('chain_id','clrty-1')=='clrty-1' or 'status' in d
"
else
  echo "SKIP live RPC (${RPC} not reachable)"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
test "$FAIL" -eq 0
