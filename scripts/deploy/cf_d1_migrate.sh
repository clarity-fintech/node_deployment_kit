#!/usr/bin/env bash
# Apply CLRTY Explorer D1 schema (§3c)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=_toolchain.sh
source "$ROOT/scripts/deploy/_toolchain.sh"
ensure_labs_deps

WR="$(resolve_wrangler)"
SCHEMA="$ROOT/clrty-1/database/schema.sql"
DB_NAME="${D1_DATABASE_NAME:-clrty-explorer}"

cd "$ROOT/cloudflare"
"$WR" d1 execute "$DB_NAME" --file="../clrty-1/database/schema.sql" --env explorer-api --remote
echo "[cf-d1-migrate] OK — $DB_NAME"
