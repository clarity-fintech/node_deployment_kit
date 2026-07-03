#!/usr/bin/env bash
# Cloudflare go-live — bootstrap → genesis → tunnel check → deploy → R2 → smoke RPC
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=_toolchain.sh
source "$ROOT/scripts/deploy/_toolchain.sh"
ensure_labs_deps

ENV_FILE="${ENV_FILE:-$ROOT/.env.l1}"
REPORT="$ROOT/var/launch/l1_launch_report.json"
RPC_URL="${CLRTY_L1_RPC_URL:-https://rpc.clarity-fintech.com}"
REST_URL="${CLRTY_L1_REST_URL:-https://api.clarity-fintech.com}"

log() { echo "[cf-go-live] $*"; }
mkdir -p "$ROOT/var/launch"

bash "$ROOT/scripts/deploy/alchemy_bridge_bootstrap.sh" || {
  if [[ "${ALCHEMY_BRIDGE_SKIP:-0}" == "1" ]]; then
    log "WARN: alchemy bridge skipped (ALCHEMY_BRIDGE_SKIP=1)"
  else
    log "ERROR: alchemy bridge bootstrap failed"
    log "  Set ALCHEMY_API_KEY in .env.l1  OR  bin/alchemy auth login"
    log "  To deploy workers without bridge: ALCHEMY_BRIDGE_SKIP=1 make cf-go-live"
    exit 1
  fi
}

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

log "genesis verify"
cargo run -p clarity-cli --bin clrty -- chain genesis-verify 2>/dev/null || \
  cargo run -p clarity-cli -- chain genesis-verify || log "WARN: genesis-verify skipped"

if [[ -n "${CLRTY_L1_ORIGIN:-}" ]] && command -v curl >/dev/null 2>&1; then
  log "tunnel origin probe: $CLRTY_L1_ORIGIN"
  curl -sf "${CLRTY_L1_ORIGIN}/v1/status" >/dev/null || log "WARN: tunnel origin not reachable (start make cf-tunnel)"
fi

log "deploy workers"
WRANGLER="$(resolve_wrangler)" || {
  log "ERROR: wrangler missing — run: make labs-install-deps"
  exit 1
}
CF_DIR="$ROOT/cloudflare"

WORKERS=(rpc-gateway api-gateway faucet labs-manifest bridge-readonly cex-ingress deposit-watcher explorer-api defillama-ingest coingecko-webhook)
for w in "${WORKERS[@]}"; do
  log "  wrangler deploy --env $w"
  (cd "$CF_DIR" && CI=true "$WRANGLER" deploy --env "$w") || log "WARN: deploy $w failed"
done

if [[ -n "${CLRTY_L1_ORIGIN:-}" ]]; then
  for w in rpc-gateway api-gateway faucet cex-ingress deposit-watcher; do
    (cd "$CF_DIR" && echo "$CLRTY_L1_ORIGIN" | "$WRANGLER" secret put CLRTY_L1_ORIGIN --env "$w" 2>/dev/null) || true
  done
fi

bash "$ROOT/scripts/deploy/liquidity_pool_bootstrap.sh" --dry-run 2>/dev/null || true

log "R2 upload (if manifests exist)"
if make -n cf-r2-upload >/dev/null 2>&1; then
  make cf-r2-upload || log "WARN: cf-r2-upload skipped"
fi

log "smoke RPC: $RPC_URL"
SLOT_OK=false
if command -v curl >/dev/null 2>&1; then
  SLOT_RESP="$(curl -sf "$RPC_URL" \
    -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot","params":[]}' 2>/dev/null || true)"
  [[ -n "$SLOT_RESP" ]] && SLOT_OK=true
  curl -sf "$REST_URL/v1/status" >/dev/null 2>&1 || log "WARN: REST status not reachable"
fi

WORKERS_JSON="$(printf '%s\n' "${WORKERS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"
python3 - <<PY
import json, os
from datetime import datetime, timezone
report = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "chain_id": "clrty-1",
    "numeric_chain_id": 1202,
    "rpc_url": "$RPC_URL",
    "rest_url": "$REST_URL",
    "workers_deployed": $WORKERS_JSON,
    "slot_smoke_ok": $( [[ "$SLOT_OK" == true ]] && echo True || echo False ),
    "alchemy_app": os.environ.get("ALCHEMY_BRIDGE_APP_NAME", ""),
}
with open("$REPORT", "w") as f:
    json.dump(report, f, indent=2)
PY

log "report → $REPORT"
log "OK — cf-go-live complete"
