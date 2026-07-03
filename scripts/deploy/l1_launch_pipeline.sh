#!/usr/bin/env bash
# Full CLRTY-1 L1 launch pipeline — sources .env.l1, sovereign L1 + Cloudflare edge
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-$ROOT/.env.l1}"
log() { echo "[l1-launch] $*"; }

bash "$ROOT/scripts/deploy/alchemy_bridge_bootstrap.sh"

if [[ ! -f "$ENV_FILE" ]]; then
  log "ERROR: $ENV_FILE missing after bootstrap"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

log "A. genesis verify"
cargo run -p clarity-cli --bin clrty -- chain genesis-verify 2>/dev/null || \
  cargo run -p clarity-cli -- chain genesis-verify

log "B. build workspace"
cargo build --workspace --release

log "C. Cloudflare go-live"
bash "$ROOT/scripts/deploy/cf_go_live.sh"

log "D. Alchemy bridge log tail (background)"
if command -v alchemy >/dev/null 2>&1; then
  nohup alchemy apps:logs --app "${ALCHEMY_BRIDGE_APP_NAME:-CLRTY-1 Bridge Anchor}" \
    >> "$ROOT/var/launch/alchemy_bridge.log" 2>&1 &
  echo $! > "$ROOT/var/launch/alchemy_bridge_logs.pid"
  log "alchemy apps:logs pid $(cat "$ROOT/var/launch/alchemy_bridge_logs.pid")"
fi

log "OK — L1 launch pipeline complete"
