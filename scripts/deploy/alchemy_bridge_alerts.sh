#!/usr/bin/env bash
# Stream Alchemy bridge logs; alert on low ETH bridge contract balance patterns
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-$ROOT/.env.l1}"
THRESHOLD_ETH="${BRIDGE_BALANCE_THRESHOLD_ETH:-0.1}"
ALERT_LOG="$ROOT/var/launch/alchemy_bridge_alerts.log"

log() { echo "[alchemy-bridge-alerts] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$ALERT_LOG"; }

if [[ ! -f "$ENV_FILE" ]]; then
  log "ERROR: $ENV_FILE missing — run make alchemy-bridge-bootstrap"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if ! command -v alchemy >/dev/null 2>&1; then
  log "ERROR: alchemy CLI not installed"
  exit 1
fi

APP="${ALCHEMY_BRIDGE_APP_NAME:-CLRTY-1 Bridge Anchor}"
log "tailing apps:logs for $APP (threshold ${THRESHOLD_ETH} ETH)"

alchemy apps:logs --app "$APP" 2>&1 | while IFS= read -r line; do
  echo "$line" >> "$ALERT_LOG"
  if echo "$line" | grep -qiE 'insufficient|revert|balance.*below|out of gas'; then
    log "ALERT: $line"
  fi
  if echo "$line" | grep -qiE 'bridge.*balance'; then
  log "metric: $line"
  fi
done
