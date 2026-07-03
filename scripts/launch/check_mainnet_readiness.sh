#!/usr/bin/env bash
# Phase IV — mainnet readiness seal + go/no-go gate (includes day-cycle lock chain).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CONFIRM=0
CONTINUE=0
SKIP_FOUNDRY=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=1 ;;
    --continue) CONTINUE=1 ;;
    --with-foundry) SKIP_FOUNDRY=0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

OUT="${ROOT}/var/compliance/mainnet_readiness_gate.json"
CHECKLIST="${ROOT}/var/compliance/mainnet_transition_checklist.json"
LOCK_CHAIN="${ROOT}/var/compliance/readiness_lock_chain.json"
LOCK_TMP="${ROOT}/var/compliance/.readiness_lock_chain.jsonl"
mkdir -p "$(dirname "$OUT")"
: > "$LOCK_TMP"

LOCK_FAILED=0
run_lock() {
  local name="$1"
  shift
  local status="pass"
  if ! "$@"; then
    status="fail"
    LOCK_FAILED=$((LOCK_FAILED + 1))
    [[ "$CONTINUE" -eq 0 ]] && exit 1
  fi
  python3 - <<PY >>"$LOCK_TMP"
import json
print(json.dumps({"name": "${name}", "status": "${status}"}))
PY
}

echo "=== Mainnet readiness check ==="

run_lock operational_nano_loop bash scripts/launch/operational_nano_loop.sh
run_lock timelock_verify bash scripts/launch/verify_timelock_deployment.sh
run_lock verify_locks bash scripts/audit/verify-locks.sh
run_lock code_freeze bash scripts/code_freeze.sh

python3 - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path

root = Path("${ROOT}")
steps = []
for line in Path("${LOCK_TMP}").read_text().splitlines():
    if line.strip():
        steps.append(json.loads(line))
chain = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "steps": steps,
    "gate_pass": ${LOCK_FAILED} == 0,
}
Path("${LOCK_CHAIN}").write_text(json.dumps(chain, indent=2) + "\n")
PY

ARGS=(--continue)
[[ "$SKIP_FOUNDRY" -eq 1 ]] && ARGS+=(--skip-foundry)

bash scripts/launch/launch_readiness.sh "${ARGS[@]}"
bash scripts/launch/verify_mainnet_contract_gates.sh
bash scripts/audit/generate_listing_compliance_pack.sh
cargo run -p clarity-cli --bin clrty -- --plain node genesis-verify

python3 scripts/audit/collect_red_flags.py --root "$ROOT" || true

python3 - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path

root = Path("${ROOT}")
red = json.loads((root / "var/compliance/system_integrity_report.json").read_text()) if (root / "var/compliance/system_integrity_report.json").is_file() else {"gate_pass": False, "red_flags": []}
listing = json.loads((root / "var/compliance/listing_compliance_report.json").read_text()) if (root / "var/compliance/listing_compliance_report.json").is_file() else {}
lock_chain = json.loads((root / "var/compliance/readiness_lock_chain.json").read_text()) if (root / "var/compliance/readiness_lock_chain.json").is_file() else {"gate_pass": False}

gate_pass = red.get("gate_pass", False) and listing.get("genesis_verify_pass", True) and lock_chain.get("gate_pass", False)
report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "task": "mainnet_readiness_gate",
    "gate_pass": gate_pass,
    "red_flags_gate_pass": red.get("gate_pass"),
    "genesis_verify_pass": listing.get("genesis_verify_pass", True),
    "lock_chain_gate_pass": lock_chain.get("gate_pass"),
    "confirm_requested": ${CONFIRM} == 1,
}
(root / "var/compliance/mainnet_readiness_gate.json").write_text(json.dumps(report, indent=2) + "\n")

checklist = {
    "generated_at": report["generated_at"],
    "gate_pass": gate_pass,
    "steps": [
        {"id": 1, "action": "Tag main as TGE_PROD_DEPLOYED", "owner": "external_ops", "automated": False},
        {"id": 2, "action": "Push signed System-Integrity-Report to operator portal", "owner": "portal-sync", "automated": False},
        {"id": 3, "action": "Enable public PRISM RPC nodes", "owner": "infrastructure", "automated": False},
        {"id": 4, "action": "Deploy NeuroTemplate developer portal", "owner": "frontend", "automated": False},
        {"id": 5, "action": "Set mint_authority null on-chain", "owner": "genesis_ceremony", "automated": False},
    ],
}
(root / "var/compliance/mainnet_transition_checklist.json").write_text(json.dumps(checklist, indent=2) + "\n")
print(json.dumps(report, indent=2))
if not gate_pass and ${CONFIRM} == 1:
    raise SystemExit(1)
PY

echo "Gate: ${OUT}"
echo "Checklist: ${CHECKLIST}"
echo "Lock chain: ${LOCK_CHAIN}"
