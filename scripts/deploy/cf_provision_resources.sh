#!/usr/bin/env bash
# Provision KV, D1, R2 and patch cloudflare/wrangler.jsonc (idempotent).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=_toolchain.sh
source "$ROOT/scripts/deploy/_toolchain.sh"
ensure_labs_deps
sync_cf_account_id

WR="$(resolve_wrangler)"
CF_DIR="$ROOT/cloudflare"
WRANGLER_CFG="$CF_DIR/wrangler.jsonc"
REPORT="$ROOT/var/launch/cf_resource_ids.json"
mkdir -p "$(dirname "$REPORT")"

log() { echo "[cf-provision] $*" >&2; }

patch_placeholder() {
  local placeholder="$1" value="$2"
  [[ -z "$value" ]] && return 1
  grep -q "$placeholder" "$WRANGLER_CFG" 2>/dev/null || return 0
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "s/$placeholder/$value/g" "$WRANGLER_CFG"
  else
    sed -i "s/$placeholder/$value/g" "$WRANGLER_CFG"
  fi
}

kv_id_for() {
  local title="$1"
  (cd "$CF_DIR" && "$WR" kv namespace list 2>/dev/null) | python3 -c "
import json, sys
title = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw: sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
for ns in data:
    if ns.get('title') == title:
        print(ns.get('id', ''))
        break
" "$title"
}

ensure_kv() {
  local title="$1" placeholder="$2"
  local id
  id="$(kv_id_for "$title")"
  if [[ -z "$id" ]]; then
    log "creating KV $title"
    CREATE_OUT="$(cd "$CF_DIR" && "$WR" kv namespace create "$title" 2>&1 || true)"
    id="$(echo "$CREATE_OUT" | grep -Eo '[0-9a-f]{32}' | head -1 || true)"
  fi
  [[ -n "$id" ]] || { log "WARN: KV $title failed"; return 1; }
  log "KV $title → $id"
  patch_placeholder "$placeholder" "$id"
  echo "$id"
}

ensure_d1() {
  local name="$1"
  local id
  id="$( (cd "$CF_DIR" && "$WR" d1 list --json 2>/dev/null) | python3 -c "
import json, sys
name = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw: sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
for row in data:
    if row.get('name') == name:
        print(row.get('uuid') or row.get('database_id') or '')
        break
" "$name")"
  if [[ -z "$id" ]]; then
    log "creating D1 $name"
    CREATE_OUT="$(cd "$CF_DIR" && "$WR" d1 create "$name" 2>&1 || true)"
    id="$(echo "$CREATE_OUT" | grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true)"
  fi
  [[ -n "$id" ]] || { log "WARN: D1 $name failed"; return 1; }
  log "D1 $name → $id"
  patch_placeholder "REPLACE_D1_ID" "$id"
  echo "$id"
}

ensure_r2() {
  local bucket="$1"
  if (cd "$CF_DIR" && "$WR" r2 bucket create "$bucket" >/dev/null 2>&1); then
    log "R2 bucket $bucket created"
    return 0
  fi
  if (cd "$CF_DIR" && "$WR" r2 bucket list 2>/dev/null | grep -q "$bucket"); then
    log "R2 bucket $bucket exists"
    return 0
  fi
  log "WARN: enable R2 in dashboard → https://dash.cloudflare.com/?to=/:account/r2/overview"
  return 1
}

log "=== Cloudflare resource provision ==="

RPC_KV="$(ensure_kv "clrty-rpc-rate-limit" "REPLACE_RPC_RATE_LIMIT_KV_ID" || echo "")"
FAUCET_KV="$(ensure_kv "clrty-faucet-rate" "REPLACE_FAUCET_RATE_KV_ID" || echo "")"
D1_ID="$(ensure_d1 "clrty-explorer" || echo "")"
R2_OK=false
ensure_r2 "clrty-labs-assets" && R2_OK=true || true

python3 - <<PY
import json
from datetime import datetime, timezone
json.dump({
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "rpc_rate_limit_kv": "${RPC_KV}",
    "faucet_rate_kv": "${FAUCET_KV}",
    "d1_explorer_id": "${D1_ID}",
    "r2_clrty_labs_assets": $( [[ "$R2_OK" == true ]] && echo True || echo False ),
}, open("$REPORT", "w"), indent=2)
print(json.dumps(json.load(open("$REPORT")), indent=2))
PY

log "report → $REPORT"
log "=== PROVISION COMPLETE ==="
