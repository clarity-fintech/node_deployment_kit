#!/usr/bin/env bash
# Operational monitor — RPC, REST, tunnel, Alchemy bridge health
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-$ROOT/.env.l1}"
RPC="${CLRTY_L1_RPC_URL:-https://rpc.clarity-fintech.com}"
REST="${CLRTY_L1_REST_URL:-https://api.clrty.dev}"
REPORT="$ROOT/var/launch/monitor_status.json"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

check_jsonrpc() {
  local url="$1" method="$2"
  curl -sf "$url" -X POST -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":[]}" 2>/dev/null || echo ""
}

check_rest() {
  curl -sf "$1" 2>/dev/null || echo ""
}

RPC_RESP="$(check_jsonrpc "$RPC" "getSlot")"
REST_RESP="$(check_rest "$REST/v1/status")"
ORIGIN_RESP=""
[[ -n "${CLRTY_L1_ORIGIN:-}" ]] && ORIGIN_RESP="$(check_rest "${CLRTY_L1_ORIGIN}/v1/status")"

python3 - <<PY
import json
from datetime import datetime, timezone

def ok_rpc(s):
    if not s: return False
    try:
        d = json.loads(s)
        return "result" in d and "error" not in d
    except Exception:
        return False

def ok_rest(s):
    return bool(s) and "error" not in s.lower()[:200]

report = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "chain_id": "clrty-1",
    "checks": {
        "public_rpc": ok_rpc("""$RPC_RESP"""),
        "public_rest": ok_rest("""$REST_RESP"""),
        "tunnel_origin": ok_rest("""$ORIGIN_RESP""") if """${CLRTY_L1_ORIGIN:-}""" else None,
    },
    "endpoints": {
        "rpc": "$RPC",
        "rest": "$REST",
        "origin": """${CLRTY_L1_ORIGIN:-}""",
    },
}
with open("$REPORT", "w") as f:
    json.dump(report, f, indent=2)

failed = [k for k, v in report["checks"].items() if v is False]
if failed:
    print("FAIL:", ", ".join(failed))
    raise SystemExit(1)
print("OK — all checks passed → $REPORT")
PY
