#!/usr/bin/env bash
# Shared PATH + local wrangler/alchemy resolution (no global npm / sudo).
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export PATH="$ROOT/bin:$PATH"

ensure_labs_deps() {
  if [[ ! -x "$ROOT/cloudflare/node_modules/.bin/wrangler" ]] \
     || [[ ! -x "$ROOT/bin/wrangler" ]] \
     || { [[ ! -x "$ROOT/bin/alchemy" ]] && [[ ! -x "$ROOT/tools/alchemy-cli/node_modules/.bin/alchemy" ]]; }; then
    bash "$ROOT/scripts/labs/install_deps.sh"
  fi
}

resolve_wrangler() {
  if command -v wrangler >/dev/null 2>&1; then
    echo wrangler
  elif [[ -x "$ROOT/cloudflare/node_modules/.bin/wrangler" ]]; then
    echo "$ROOT/cloudflare/node_modules/.bin/wrangler"
  elif [[ -x "$ROOT/bin/wrangler" ]]; then
    echo "$ROOT/bin/wrangler"
  else
    return 1
  fi
}

resolve_alchemy() {
  if [[ -x "$ROOT/bin/alchemy" ]]; then
    echo "$ROOT/bin/alchemy"
  elif [[ -x "$ROOT/tools/alchemy-cli/node_modules/.bin/alchemy" ]]; then
    echo "$ROOT/tools/alchemy-cli/node_modules/.bin/alchemy"
  elif command -v alchemy >/dev/null 2>&1; then
    echo alchemy
  else
    return 1
  fi
}

sync_cf_account_id() {
  local env_file="${ENV_FILE:-$ROOT/.env.l1}"
  local wrangler_cfg="$ROOT/cloudflare/wrangler.jsonc"
  local acct=""
  if [[ -f "$env_file" ]]; then
    acct="$(grep -E '^CF_ACCOUNT_ID=' "$env_file" | head -1 | cut -d= -f2- | tr -d ' \"')"
  fi
  [[ -z "$acct" ]] && return 0
  if [[ -f "$wrangler_cfg" ]] && grep -q 'YOUR_CLOUDFLARE_ACCOUNT_ID' "$wrangler_cfg" 2>/dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s/YOUR_CLOUDFLARE_ACCOUNT_ID/$acct/g" "$wrangler_cfg"
    else
      sed -i "s/YOUR_CLOUDFLARE_ACCOUNT_ID/$acct/g" "$wrangler_cfg"
    fi
  fi
}
