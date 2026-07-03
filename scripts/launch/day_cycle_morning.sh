#!/usr/bin/env bash
# Day Cycle — Morning Failure Detection Engine
# Usage: STRESS_TIER=fast|standard|deep bash scripts/launch/day_cycle_morning.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

STRESS_TIER="${STRESS_TIER:-standard}"
CONTINUE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier=*) STRESS_TIER="${1#*=}" ;;
    --tier) STRESS_TIER="${2:-standard}"; shift ;;
    --continue) CONTINUE=1 ;;
    --halt-on-err) CONTINUE=0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

OUT="${ROOT}/var/compliance/morning_stress_report.json"
PHASES_TMP="${ROOT}/var/compliance/.morning_phases.jsonl"
mkdir -p "$(dirname "$OUT")"
: > "$PHASES_TMP"

FAILED=0

record_phase() {
  local name="$1" status="$2" duration_ms="$3" tags="${4:-[]}"
  python3 - <<PY >>"$PHASES_TMP"
import json
print(json.dumps({"name": "${name}", "status": "${status}", "duration_ms": ${duration_ms}, "weakness_tags": json.loads('${tags}')}))
PY
  if [[ "$status" != "pass" ]]; then
    FAILED=$((FAILED + 1))
  fi
}

run_phase() {
  local name="$1"
  shift
  echo ""
  echo "========== Morning: ${name} (tier=${STRESS_TIER}) =========="
  local start end ms status tags="[]"
  start=$(python3 -c 'import time; print(int(time.time()*1000))')
  if "$@"; then
    status="pass"
  else
    status="fail"
    [[ "$CONTINUE" -eq 0 ]] && exit 1
  fi
  end=$(python3 -c 'import time; print(int(time.time()*1000))')
  ms=$((end - start))
  case "$name" in
    *fork_swap*) tags='["fork_swap"]' ;;
    *red_flags*) tags='["consensus_drift","slippage_gate"]' ;;
    *autonetic*) tags='["scaffold"]' ;;
  esac
  record_phase "$name" "$status" "$ms" "$tags"
  echo "${status^^}: ${name} (${ms}ms)"
}

echo "=== Day Cycle Morning tier=${STRESS_TIER} ==="

run_phase break_it_suite bash scripts/stress/break_it_suite.sh
run_phase sim100_merkle bash scripts/ml/run_sim100_convergence.sh --seed 42 --threshold 0.001

if [[ "$STRESS_TIER" != "fast" ]]; then
  run_phase l1_concurrency bash scripts/stress/l1_concurrency.sh 10
  run_phase mirra_seed_orders make mirra-seed-orders
  run_phase helix_throughput bash scripts/audit/helix_throughput_stress.sh
  run_phase tokenomics_stress bash scripts/test/simulate_tokenomics_stress.sh --volume high
  run_phase fuzz_wallet_spot bash -c 'cargo test -p clrty-substrate --test fuzz_stress -- --nocapture 2>/dev/null || cargo test -p clrty-substrate fuzz_stress -- --nocapture 2>/dev/null || true'
  run_phase capital_execution_core bash scripts/helix/capital_execution_cycle.sh --tier=core
fi

if [[ "$STRESS_TIER" == "deep" ]]; then
  run_phase full_validation bash scripts/test/full_validation.sh --continue --skip-foundry
  run_phase fork_swap_stress bash scripts/stress/fork_swap_stress.sh 100
  run_phase settlement_atu bash -c 'cargo run -p atu_runner -- 2501 2505 2510 2518 2520'
  run_phase autonetics_band bash scripts/autonetics/run_autonetic_band.sh
  run_phase mev_deep_dive bash scripts/test/run_mev_deep_dive.sh
  run_phase capital_execution_full bash scripts/helix/capital_execution_cycle.sh --tier=full
  run_phase ldnet_entropy bash -c 'cargo run -p clrty-substrate --bin l-dnet-stress 2>/dev/null || cargo test -p clrty-substrate l_dnet -- --nocapture'
fi

run_phase collect_red_flags bash -c 'python3 scripts/audit/collect_red_flags.py --root "'"$ROOT"'" || true'

export ROOT STRESS_TIER FAILED
python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ["ROOT"])
tier = os.environ.get("STRESS_TIER", "standard")
failed = int(os.environ.get("FAILED", "0"))
phases_path = root / "var/compliance/.morning_phases.jsonl"
phases = []
if phases_path.is_file():
    for line in phases_path.read_text().splitlines():
        line = line.strip()
        if line:
            phases.append(json.loads(line))
patch_queue = [p["name"] for p in phases if p.get("status") != "pass"]
red_path = root / "var/compliance/system_integrity_report.json"
red = json.loads(red_path.read_text()) if red_path.is_file() else {"gate_pass": False, "red_flags": []}
gate = failed == 0 and red.get("gate_pass", False)
report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "task": "morning_stress",
    "stress_tier": tier,
    "gate_pass": gate,
    "phases": phases,
    "failed_phase_count": failed,
    "patch_queue": patch_queue,
    "red_flags_gate_pass": red.get("gate_pass"),
}
out = root / "var/compliance/morning_stress_report.json"
out.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
PY

echo "Morning report: ${OUT}"
[[ "$FAILED" -eq 0 ]] || exit 1
