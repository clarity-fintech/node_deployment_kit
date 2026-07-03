#!/usr/bin/env bash
# Deploy Clarity Fortress static site to Cloudflare Pages (dev.clrty.io/labs)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=_toolchain.sh
source "$ROOT/scripts/deploy/_toolchain.sh"
ensure_labs_deps
cd "$ROOT"

PROJECT_NAME="${CF_PAGES_PROJECT:-clrty-labs}"
BRANCH="${CF_PAGES_BRANCH:-main}"
SITE_DIR="$ROOT/frontend/labs"
SHARED_DIR="$ROOT/frontend/shared"

log() { echo "[labs-pages] $*"; }

if [[ ! -d "$SITE_DIR" ]]; then
  echo "MISSING $SITE_DIR" >&2
  exit 1
fi

log "sync manifests"
python3 "$ROOT/scripts/clarity-wallet/generate_labs_manifest.py"

STAGING="$ROOT/var/deploy/labs-pages"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$SITE_DIR/." "$STAGING/"
mkdir -p "$STAGING/shared" "$STAGING/data"
cp "$SHARED_DIR/labs-api.js" "$SHARED_DIR/labs-walkthrough.js" "$SHARED_DIR/labs-wallet-stub.js" "$STAGING/shared/" 2>/dev/null || true
if [[ -f "$ROOT/frontend/investor/data/nano_details_100.json" ]]; then
  cp "$ROOT/frontend/investor/data/nano_details_100.json" "$STAGING/data/"
fi
if [[ -d "$ROOT/monetization-layers/checkout" ]]; then
  mkdir -p "$STAGING/checkout"
  cp -R "$ROOT/monetization-layers/checkout/." "$STAGING/checkout/"
fi
if [[ -f "$ROOT/monetization-layers/products/stripe_portal.json" ]]; then
  cp "$ROOT/monetization-layers/products/stripe_portal.json" "$STAGING/data/"
fi

log "static bundle → $STAGING ($(find "$STAGING" -type f | wc -l | tr -d ' ') files)"

DEPLOY="${LABS_PAGES_DEPLOY:-0}"
for arg in "$@"; do
  [[ "$arg" == "--deploy" ]] && DEPLOY=1
done

if [[ "$DEPLOY" != "1" ]]; then
  log "bundle only (set LABS_PAGES_DEPLOY=1 or --deploy to push to Cloudflare Pages)"
  exit 0
fi

WRANGLER="$(resolve_wrangler)" || {
  log "ERROR: wrangler not found — run: make labs-install-deps"
  exit 1
}

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]] && ! "$WRANGLER" whoami >/dev/null 2>&1; then
  log "ERROR: Cloudflare auth required — export CLOUDFLARE_API_TOKEN or run: wrangler login"
  exit 1
fi

log "deploy Pages project=$PROJECT_NAME (wrangler=$WRANGLER)"
"$WRANGLER" pages deploy "$STAGING" \
  --project-name="$PROJECT_NAME" \
  --branch="$BRANCH" \
  --commit-dirty=true

log "OK — deploy complete; add Pages custom domain labs.clarity-fintech.com in dashboard if needed"
