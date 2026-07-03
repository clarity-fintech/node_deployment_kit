#!/usr/bin/env bash
# Idempotent Alchemy bridge bootstrap → .env.l1 → wrangler ALCHEMY_BRIDGE_RPC secret
# CLRTY-1 L1 truth remains clrty/clarityd — Alchemy is ETH bridge read-only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=_toolchain.sh
source "$ROOT/scripts/deploy/_toolchain.sh"
ensure_labs_deps
sync_cf_account_id

ENV_FILE="${ENV_FILE:-$ROOT/.env.l1}"
EXAMPLE="$ROOT/.env.l1.example"
DEFAULT_APP_NAME="CLRTY-1 Bridge Anchor"
REPORT="$ROOT/var/launch/alchemy_bridge.json"

mkdir -p "$(dirname "$REPORT")"
log() { echo "[alchemy-bridge-bootstrap] $*"; }

ALCHEMY_CMD="$(resolve_alchemy)" || {
  log "ERROR: alchemy CLI missing — run: make labs-install-deps"
  exit 1
}

if [[ ! -f "$ENV_FILE" ]] && [[ -f "$EXAMPLE" ]]; then
  cp "$EXAMPLE" "$ENV_FILE"
  log "created $ENV_FILE from template"
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

APP_NAME="${ALCHEMY_BRIDGE_APP_NAME:-$DEFAULT_APP_NAME}"
APP_ID=""

alchemy_authed() {
  "$ALCHEMY_CMD" auth status 2>/dev/null | grep -q '"authenticated"[[:space:]]*:[[:space:]]*true'
}

update_env() {
  local key="$1" val="$2"
  [[ -f "$ENV_FILE" ]] || touch "$ENV_FILE"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
      sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    fi
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

extract_api_key() {
  "$ALCHEMY_CMD" config get api-key --reveal 2>/dev/null | python3 -c '
import json, sys, re
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
    print(data.get("value") or data.get("apiKey") or data.get("api_key") or "")
except json.JSONDecodeError:
    m = re.search(r"alch_[a-zA-Z0-9]+", raw)
    print(m.group(0) if m else raw.strip())
'
}

find_app_id() {
  local name="$1"
  "$ALCHEMY_CMD" app list --json 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
apps = data if isinstance(data, list) else data.get("apps") or data.get("data") or []
if isinstance(apps, dict):
    apps = list(apps.values())
for a in apps:
    if not isinstance(a, dict):
        continue
    if a.get("name") == name or a.get("appName") == name:
        print(a.get("id") or a.get("appId") or "")
        break
' "$name"
}

create_app_id() {
  local name="$1"
  "$ALCHEMY_CMD" app create --name "$name" --networks ETH_MAINNET --json 2>/dev/null | python3 -c '
import json, sys, re
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
    print(data.get("id") or data.get("appId") or data.get("app_id") or "")
except json.JSONDecodeError:
    m = re.search(r"app_[a-zA-Z0-9]+", raw)
    print(m.group(0) if m else "")
'
}

# --- Path A: API key already in .env.l1 ---
if [[ -n "${ALCHEMY_API_KEY:-}" ]]; then
  log "using ALCHEMY_API_KEY from $ENV_FILE"
elif alchemy_authed; then
  log "alchemy auth OK — resolving app + API key"
  APP_ID="$(find_app_id "$APP_NAME" || true)"
  if [[ -z "$APP_ID" ]]; then
    log "creating Alchemy app: $APP_NAME"
    APP_ID="$(create_app_id "$APP_NAME" || true)"
  fi
  ALCHEMY_API_KEY="$(extract_api_key || true)"
else
  log "ERROR: Alchemy not configured."
  log "  Option 1 — set ALCHEMY_API_KEY in $ENV_FILE (https://dashboard.alchemy.com/)"
  log "  Option 2 — run: bin/alchemy auth login"
  log "         then: make alchemy-bridge-bootstrap"
  exit 1
fi

if [[ -z "${ALCHEMY_API_KEY:-}" ]]; then
  log "WARN: ALCHEMY_API_KEY still empty — add to $ENV_FILE manually"
else
  ETH_MAINNET_BRIDGE_RPC="https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
  log "ETH mainnet bridge RPC configured"
fi

update_env "ALCHEMY_BRIDGE_APP_NAME" "$APP_NAME"
[[ -n "${ALCHEMY_API_KEY:-}" ]] && update_env "ALCHEMY_API_KEY" "$ALCHEMY_API_KEY"
[[ -n "${ETH_MAINNET_BRIDGE_RPC:-}" ]] && update_env "ETH_MAINNET_BRIDGE_RPC" "$ETH_MAINNET_BRIDGE_RPC"

WRANGLER="$(resolve_wrangler 2>/dev/null || true)"
if [[ -n "${ETH_MAINNET_BRIDGE_RPC:-}" ]] && [[ -n "$WRANGLER" ]]; then
  log "syncing ALCHEMY_BRIDGE_RPC to bridge-readonly worker"
  (cd "$ROOT/cloudflare" && echo "$ETH_MAINNET_BRIDGE_RPC" | "$WRANGLER" secret put ALCHEMY_BRIDGE_RPC --env bridge-readonly) \
    || log "WARN: wrangler secret put failed (check CF auth)"
fi

python3 - <<PY
import json, os
from datetime import datetime, timezone
report = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "app_name": os.environ.get("ALCHEMY_BRIDGE_APP_NAME", "$APP_NAME"),
    "app_id": "${APP_ID:-}",
    "chain": "clrty-1",
    "role": "eth_mainnet_bridge_readonly",
    "api_key_configured": bool("${ALCHEMY_API_KEY:-}"),
}
with open("$REPORT", "w") as f:
    json.dump(report, f, indent=2)
PY

log "OK — .env.l1 updated, report → $REPORT"
