#!/usr/bin/env bash
# One-time cloudflared tunnel → api-internal.clarity-fintech.com (uses existing zone, no workers.dev)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env.l1}"
TUNNEL_NAME="${CF_TUNNEL_NAME:-clrty-api}"
TUNNEL_HOST="${CF_TUNNEL_HOST:-api-internal.clarity-fintech.com}"
LOCAL_ORIGIN="${CLRTY_TUNNEL_LOCAL_ORIGIN:-http://127.0.0.1:8545}"
CF_DIR="${HOME}/.cloudflared"
CONFIG="${CF_DIR}/config.yml"

log() { echo "[cf-tunnel-setup] $*"; }

if ! command -v cloudflared >/dev/null 2>&1; then
  log "ERROR: install cloudflared (brew install cloudflared)"
  exit 1
fi

mkdir -p "$CF_DIR"

if [[ ! -f "${CF_DIR}/cert.pem" ]]; then
  if [[ -f "$HOME/Library/Preferences/.wrangler/cert.pem" ]]; then
    cp "$HOME/Library/Preferences/.wrangler/cert.pem" "${CF_DIR}/cert.pem"
  fi
fi

if [[ ! -f "${CF_DIR}/cert.pem" ]]; then
  log "First-time login required — opens browser once"
  cloudflared tunnel login
fi

if ! cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
  log "creating tunnel $TUNNEL_NAME"
  cloudflared tunnel create "$TUNNEL_NAME"
fi

TUNNEL_ID="$(cloudflared tunnel list --output json 2>/dev/null | python3 -c "
import json, sys
name = sys.argv[1]
try:
    rows = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in rows:
    if r.get('name') == name:
        print(r.get('id', ''))
        break
" "$TUNNEL_NAME" 2>/dev/null || true)"
if [[ -z "$TUNNEL_ID" ]]; then
  TUNNEL_ID="$(cloudflared tunnel list 2>/dev/null | awk -v n="$TUNNEL_NAME" '\$2==n {print \$1; exit}')"
fi
CREDS="${CF_DIR}/${TUNNEL_ID}.json"

if [[ -z "$TUNNEL_ID" ]] || [[ ! -f "$CREDS" ]]; then
  log "ERROR: tunnel credentials missing for $TUNNEL_NAME"
  exit 1
fi

log "routing DNS $TUNNEL_HOST → tunnel $TUNNEL_NAME"
cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_HOST" 2>/dev/null || \
  log "WARN: DNS route may already exist"

cat > "$CONFIG" <<YAML
tunnel: ${TUNNEL_ID}
credentials-file: ${CREDS}

ingress:
  - hostname: ${TUNNEL_HOST}
    service: ${LOCAL_ORIGIN}
  - service: http_status:404
YAML

log "wrote $CONFIG"

TUNNEL_ORIGIN="https://${TUNNEL_HOST}"
if [[ -f "$ENV_FILE" ]]; then
  update_env() {
    local k="$1" v="$2"
    if grep -q "^${k}=" "$ENV_FILE"; then
      if [[ "$(uname)" == "Darwin" ]]; then sed -i '' "s|^${k}=.*|${k}=${v}|" "$ENV_FILE"
      else sed -i "s|^${k}=.*|${k}=${v}|" "$ENV_FILE"; fi
    else echo "${k}=${v}" >> "$ENV_FILE"; fi
  }
  update_env "CLRTY_L1_ORIGIN" "$TUNNEL_ORIGIN"
  update_env "CLRTY_L1_REST_URL" "https://api.clarity-fintech.com"
  update_env "CLRTY_L1_RPC_URL" "https://rpc.clarity-fintech.com"
fi

python3 - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path
Path("$ROOT/var/launch").mkdir(parents=True, exist_ok=True)
json.dump({
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "tunnel_name": "$TUNNEL_NAME",
    "tunnel_id": "$TUNNEL_ID",
    "hostname": "$TUNNEL_HOST",
    "origin": "$LOCAL_ORIGIN",
    "tunnel_origin_https": "$TUNNEL_ORIGIN",
    "config": "$CONFIG",
}, open("$ROOT/var/launch/cf_tunnel_report.json", "w"), indent=2)
PY

log "OK — tunnel origin: $TUNNEL_ORIGIN"
log "Start: make cf-tunnel  (keep clrty-api running on :8545)"
