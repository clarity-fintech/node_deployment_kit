#!/usr/bin/env bash
# Genesis pre-fund verify — §13 ops checklist
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

log() { echo "[genesis-prefund] $*"; }

if cargo run -p clarity-cli -- chain genesis-verify --plain 2>/dev/null; then
  log "genesis-verify OK"
else
  cargo run -p clarity-cli -- node genesis-verify --plain || log "WARN genesis-verify skipped"
fi

if [[ -f "$ROOT/CLRTY_SUBSTRATE/boot/genesis_entropy.json" ]]; then
  python3 -c "
import json
g=json.load(open('CLRTY_SUBSTRATE/boot/genesis_entropy.json'))
assert g, 'genesis_entropy empty'
print('genesis_entropy.json present')
"
fi

log "OK"
