#!/usr/bin/env bash
# Create proxied wildcard DNS for clarity-fintech.com → Workers (free, one record)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=_toolchain.sh
source "$ROOT/scripts/deploy/_toolchain.sh"
ensure_labs_deps

ZONE="${CF_ZONE_NAME:-clarity-fintech.com}"
WR="$(resolve_wrangler)"
RECORD_NAME="${CF_DNS_WILDCARD:-*.clarity-fintech.com}"

log() { echo "[cf-dns] $*"; }

# Resolve zone id via Cloudflare API (uses wrangler OAuth session)
ZONE_ID="$(cd "$ROOT/cloudflare" && "$WR" whoami 2>/dev/null | python3 -c "
import json, sys, subprocess, os
# wrangler whoami doesn't return zone id — fetch via API using oauth from config
import pathlib
cfg = pathlib.Path.home() / '.wrangler/config/default.toml'
# fallback: query zones API via wrangler curl proxy
" 2>/dev/null || true)"

# Use wrangler's built-in zone lookup via deploy account + curl
ACCOUNT_ID="$(grep -E '^CF_ACCOUNT_ID=' "${ENV_FILE:-$ROOT/.env.l1}" 2>/dev/null | cut -d= -f2- || echo "ed830f550ba27c24d18cb030d99f3873")"

log "Ensuring wildcard DNS for Workers: $RECORD_NAME"
log "If this fails, add manually in Cloudflare DNS (both records):"
log "  AAAA  Name: *  Content: 100::   Proxy: ON"
log "  A     Name: *  Content: 192.0.2.1 Proxy: ON  (IPv4 — required for api/rpc on many networks)"

# Prefer API token (DNS Edit); fall back to wrangler OAuth (often read-only for DNS).
AUTH_HEADER=""
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
elif [[ -n "${CF_API_TOKEN:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer ${CF_API_TOKEN}"
else
  OAUTH_TOKEN=""
  for cfg in "$HOME/Library/Preferences/.wrangler/config/default.toml" "$HOME/.wrangler/config/default.toml"; do
    if [[ -f "$cfg" ]]; then
      OAUTH_TOKEN="$(grep '^oauth_token' "$cfg" | cut -d'"' -f2 || true)"
      [[ -n "$OAUTH_TOKEN" ]] && break
    fi
  done
  if [[ -z "$OAUTH_TOKEN" ]]; then
    log "ERROR: export CLOUDFLARE_API_TOKEN (Zone DNS Edit) or run bin/wrangler login"
    exit 1
  fi
  AUTH_HEADER="Authorization: Bearer ${OAUTH_TOKEN}"
fi

ZONE_ID="$(curl -sf "https://api.cloudflare.com/client/v4/zones?name=${ZONE}" \
  -H "${AUTH_HEADER}" \
  -H "Content-Type: application/json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d.get('result') or []
print(r[0]['id'] if r else '')
")"

if [[ -z "$ZONE_ID" ]]; then
  log "ERROR: zone $ZONE not found in account $ACCOUNT_ID"
  log "Add clarity-fintech.com to Cloudflare or set CF_ZONE_NAME"
  exit 1
fi

log "zone_id=$ZONE_ID"

ensure_wildcard() {
  local rtype="$1" content="$2" comment="$3"
  local existing
  existing="$(curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=${rtype}&name=*.${ZONE}" \
    -H "${AUTH_HEADER}" | python3 -c "
import json,sys
raw=sys.stdin.read()
if not raw.strip():
    print(0); sys.exit(0)
d=json.loads(raw)
print(len(d.get('result') or []))
" 2>/dev/null || echo 0)"
  if [[ "$existing" != "0" ]]; then
    log "${rtype} wildcard already exists"
    return 0
  fi
  local resp http_code
  resp="$(curl -s -w '\n%{http_code}' "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"${rtype}\",\"name\":\"*\",\"content\":\"${content}\",\"proxied\":true,\"comment\":\"${comment}\"}")"
  http_code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ "$http_code" == "200" ]] && echo "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null; then
    log "created ${rtype} wildcard * → ${content}"
    return 0
  fi
  log "ERROR creating ${rtype} wildcard (HTTP ${http_code}): ${body:-empty response}"
  log "Add manually: ${rtype} * ${content} (proxied)"
  return 1
}

ensure_wildcard AAAA "100::" "CLRTY Workers wildcard AAAA" || true
ensure_wildcard A "192.0.2.1" "CLRTY Workers wildcard A (IPv4)" || true

# Pages labs subdomain (optional CNAME to pages.dev)
PAGES_CNAME="${CF_LABS_HOST:-labs.clarity-fintech.com}"
PAGES_TARGET="${CF_PAGES_TARGET:-clrty-labs.pages.dev}"
log "Pages: add custom domain $PAGES_CNAME in dashboard → Pages → clrty-labs → Custom domains"
log "  Or CNAME labs → clrty-labs.pages.dev (proxied)"

python3 - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path
Path("$ROOT/var/launch").mkdir(parents=True, exist_ok=True)
json.dump({
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "zone": "$ZONE",
    "zone_id": "$ZONE_ID",
    "wildcard": "$RECORD_NAME",
    "labs_host": "$PAGES_CNAME",
}, open("$ROOT/var/launch/cf_dns_report.json", "w"), indent=2)
PY

log "OK — DNS bootstrap complete"
