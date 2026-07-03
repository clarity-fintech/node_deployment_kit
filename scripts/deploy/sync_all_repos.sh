#!/usr/bin/env bash
# Sync and push all CLRTY ecosystem git repos (monorepo + wallet + prism CLI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/bin:$PATH"

PUSH="${PUSH:-1}"
MSG="${MSG:-CLRTY-1 mainnet live: labs portal, clarity-fintech.com edge, products suite, 120 nano details, allocation cap compliance}"

log() { echo "[repo-sync] $*"; }

log "=== regenerate manifests ==="
python3 scripts/investor/generate_nano_details.py
python3 scripts/metrics/sync_sheets_inputs.py 2>/dev/null || true
python3 scripts/metrics/aggregate_data_center.py 2>/dev/null || true
bash scripts/clarity-wallet/sync_labs_wallet_repos.sh
make first-access-export 2>/dev/null || bash scripts/investor/export_first_access_kit.sh

commit_repo() {
  local dir="$1"
  local msg="$2"
  [[ -d "$dir/.git" ]] || { log "skip (not a repo): $dir"; return 0; }
  log "commit: $dir"
  git -C "$dir" add -A
  if git -C "$dir" diff --cached --quiet; then
    log "  nothing to commit"
    return 0
  fi
  git -C "$dir" commit -m "$msg"
  if [[ "$PUSH" == "1" ]]; then
    git -C "$dir" push origin HEAD
    log "  pushed $(git -C "$dir" rev-parse --short HEAD)"
  fi
}

repo_remote() {
  git -C "$1" remote get-url origin 2>/dev/null || true
}

fast_forward_clone() {
  local dir="$1"
  [[ -d "$dir/.git" ]] || return 0
  log "fast-forward: $dir"
  git -C "$dir" fetch origin main
  git -C "$dir" reset --hard origin/main
  log "  at $(git -C "$dir" rev-parse --short HEAD)"
}

# 1. Main monorepo (theangelofwill/-CLRTY)
commit_repo "$ROOT" "$MSG"

# 2. PRISM CLI (clarity-fintech/clarity_prism_cli)
commit_repo "$ROOT/clarity-prism-cli" "labs: clarity-fintech.com API/RPC + clrt labs commands"

# 3. Wallet integration — push once from embedded clone; home clone shares the same remote
WALLET_EMBEDDED="$ROOT/frontend/CLRTY-WALLET-INTEGRATION"
WALLET_HOME="${CLRTY_WALLET_INTEGRATION_HOME:-$HOME/CLRTY-WALLET-INTEGRATION}"
WALLET_MSG="labs: sync AP-LABS-01 manifest, LabsWalletAdapter, clarity-fintech.com endpoints"

commit_repo "$WALLET_EMBEDDED" "$WALLET_MSG"

if [[ -d "$WALLET_HOME/.git" ]]; then
  embedded_remote="$(repo_remote "$WALLET_EMBEDDED")"
  home_remote="$(repo_remote "$WALLET_HOME")"
  if [[ -n "$embedded_remote" && "$embedded_remote" == "$home_remote" ]]; then
    log "wallet home clone shares remote with embedded; skipping duplicate push"
    fast_forward_clone "$WALLET_HOME"
  else
    commit_repo "$WALLET_HOME" "$WALLET_MSG"
  fi
fi

log "=== ALL REPOS SYNCED ==="
log "Main:     https://github.com/theangelofwill/-CLRTY"
log "Wallet:   https://github.com/clarity-fintech/wallet_integration"
log "PRISM:    https://github.com/clarity-fintech/clarity_prism_cli"
