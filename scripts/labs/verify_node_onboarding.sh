#!/usr/bin/env bash
# Smoke test dev node registration + heartbeat against local or production API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

API="${CLRTY_API_BASE:-http://127.0.0.1:8545}"
NODE_ID="verify-node-$(date +%s)"

echo "[node-onboarding] API=$API node_id=$NODE_ID"

REG=$(curl -sf -X POST "$API/v1/monetization/node/register" \
  -H 'Content-Type: application/json' \
  -d "{\"node_id\":\"$NODE_ID\",\"tier\":\"node_free\"}")

echo "$REG" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('registered') is True, d; print('register OK', d.get('persisted'))"

HB=$(curl -sf -X POST "$API/v1/monetization/node/heartbeat" \
  -H 'Content-Type: application/json' \
  -d "{\"node_id\":\"$NODE_ID\",\"version\":\"1.0.0\",\"uptime_secs\":60}")

echo "$HB" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok') is True, d; print('heartbeat OK')"

curl -sf "$API/v1/monetization/node/registry" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('count',0)>=1; print('registry count', d['count'])"

echo "[node-onboarding] PASS"
