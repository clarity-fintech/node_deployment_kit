#!/usr/bin/env bash
# Day Cycle — Afternoon Hardening + Infrastructure Lock
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CONFIRM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=1 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

OUT="${ROOT}/var/compliance/infrastructure_lock_report.json"
MORNING="${ROOT}/var/compliance/morning_stress_report.json"
mkdir -p "$(dirname "$OUT")"

echo "=== Day Cycle Afternoon ==="

if [[ -f "$MORNING" ]]; then
  echo "Patch queue from morning:"
  python3 -c "import json; m=json.load(open('$MORNING')); print('\n'.join(m.get('patch_queue',[])) or '(empty)')"
fi

CHAIN=()
FAILED=0

run_chain() {
  local name="$1"
  shift
  echo ""
  echo "========== Afternoon: ${name} =========="
  local start end ms status
  start=$(python3 -c 'import time; print(int(time.time()*1000))')
  if "$@"; then
    status="pass"
  else
    status="fail"
    FAILED=$((FAILED + 1))
  fi
  end=$(python3 -c 'import time; print(int(time.time()*1000))')
  ms=$((end - start))
  python3 - <<PY >>"${ROOT}/var/compliance/.afternoon_chain.jsonl"
import json
print(json.dumps({"name": "${name}", "status": "${status}", "duration_ms": ${ms}}))
PY
  echo "${status^^}: ${name}"
}

: > "${ROOT}/var/compliance/.afternoon_chain.jsonl"

run_chain operational_nano_loop bash scripts/launch/operational_nano_loop.sh
run_chain timelock_verify bash scripts/launch/verify_timelock_deployment.sh
run_chain verify_locks bash scripts/audit/verify-locks.sh
run_chain code_freeze bash scripts/code_freeze.sh
run_chain verify_immutability bash scripts/audit/verify_immutability.sh
run_chain listing_compliance bash scripts/audit/generate_listing_compliance_pack.sh

CONFIRM_ARGS=()
[[ "$CONFIRM" -eq 1 ]] && CONFIRM_ARGS+=(--confirm)
run_chain mainnet_readiness bash scripts/launch/check_mainnet_readiness.sh --continue "${CONFIRM_ARGS[@]}"
run_chain collect_red_flags python3 scripts/audit/collect_red_flags.py --root "$ROOT"
run_chain interface_verify bash scripts/test/verify_interface.sh
run_chain handoff_checklist python3 scripts/launch/generate_handoff_checklist.py
run_chain scale_plan bash scripts/launch/scale_high_performers.sh

export ROOT FAILED CONFIRM
python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ["ROOT"])
failed = int(os.environ.get("FAILED", "0"))
chain_path = root / "var/compliance/.afternoon_chain.jsonl"
chain = []
if chain_path.is_file():
    for line in chain_path.read_text().splitlines():
        if line.strip():
            chain.append(json.loads(line))
handoff_path = root / "var/compliance/handoff_checklist.json"
handoff = json.loads(handoff_path.read_text()) if handoff_path.is_file() else {}
handoff_ready = handoff.get("handoff_ready", False)
repo_lock = failed == 0
report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "task": "infrastructure_lock",
    "repo_lock_pass": repo_lock,
    "handoff_ready": handoff_ready,
    "failed_step_count": failed,
    "hardening_chain": chain,
    "confirm_requested": os.environ.get("CONFIRM", "0") == "1",
}
out = root / "var/compliance/infrastructure_lock_report.json"
out.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
if not repo_lock:
    raise SystemExit(1)
PY

echo "Infrastructure lock report: ${OUT}"
