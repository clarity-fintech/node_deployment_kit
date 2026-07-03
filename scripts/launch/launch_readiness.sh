#!/usr/bin/env bash
# All-in-one launch readiness — pretest, validation, audits, stress, treasury sync.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CONTINUE=0
SKIP_FOUNDRY=0
WITH_BREAK_IT=0
SKIP_SIM=0
JSON=0
OUT_DIR="${ROOT}/var/launch"
REPORT_JSON="${OUT_DIR}/launch_readiness_report.json"

usage() {
  cat <<'EOF'
Usage: scripts/launch/launch_readiness.sh [OPTIONS]

Options:
  --continue         Run all phases even after failures; exit 1 if any hard fail
  --skip-foundry     Skip Foundry-dependent steps
  --with-break-it    Run scripts/stress/break_it_suite.sh after core battery
  --skip-sim         Skip scripts/sim/run_100_events.sh
  --json             Print launch_readiness_report.json to stdout
  --out-dir PATH     Output directory (default: var/launch)
  -h, --help         Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --continue) CONTINUE=1 ;;
    --skip-foundry) SKIP_FOUNDRY=1 ;;
    --with-break-it) WITH_BREAK_IT=1 ;;
    --skip-sim) SKIP_SIM=1 ;;
    --json) JSON=1 ;;
    --out-dir)
      shift
      OUT_DIR="$1"
      REPORT_JSON="${OUT_DIR}/launch_readiness_report.json"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

mkdir -p "$OUT_DIR"

PHASES=()
STATUSES=()
DETAILS=()
HARD_FAILED=0
START_TS=$(date +%s)

run_phase() {
  local name="$1"
  local hard="${2:-0}"
  shift 2
  echo ""
  echo "=== Phase: $name ==="
  if "$@"; then
    PHASES+=("$name")
    STATUSES+=("pass")
    DETAILS+=("ok")
    echo "PASS: $name"
  else
    PHASES+=("$name")
    STATUSES+=("fail")
    DETAILS+=("command failed")
    echo "FAIL: $name" >&2
    if [[ "$hard" -eq 1 ]]; then
      HARD_FAILED=$((HARD_FAILED + 1))
    fi
    if [[ "$CONTINUE" -eq 0 ]]; then
      write_report
      exit 1
    fi
  fi
}

skip_phase() {
  local name="$1"
  local reason="$2"
  PHASES+=("$name")
  STATUSES+=("skip")
  DETAILS+=("$reason")
  echo "SKIP: $name ($reason)"
}

write_report() {
  local end_ts duration
  end_ts=$(date +%s)
  duration=$((end_ts - START_TS))

  python3 - <<PY
import json, os

phases = $(printf '%s\n' "${PHASES[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
statuses = $(printf '%s\n' "${STATUSES[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
details = $(printf '%s\n' "${DETAILS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')

pretest_zone1_fail = False
pretest_l1_pulse = None
validation_fail = False
compliance_fail = False

pretest_readiness = os.path.join("$ROOT", "var/pretest/systemic_readiness.json")
if os.path.isfile(pretest_readiness):
    with open(pretest_readiness) as f:
        sr = json.load(f)
    pretest_l1_pulse = sr.get("l1_pulse")
    z1 = sr.get("zones", {}).get("1", {})
    pretest_zone1_fail = z1.get("fail", 0) > 0 or sr.get("l1_pulse") == "red"

validation_report = os.path.join("$ROOT", "var/full_test/report.json")
if os.path.isfile(validation_report):
    with open(validation_report) as f:
        vr = json.load(f)
    validation_fail = vr.get("summary", {}).get("failed", 0) > 0

listing_report = os.path.join("$ROOT", "var/compliance/listing_compliance_report.json")
if os.path.isfile(listing_report):
    with open(listing_report) as f:
        lr = json.load(f)
    keys = [
        "immutability_audit_pass",
        "verify_immutability_pass",
        "genesis_verify_pass",
        "listing_config_test_pass",
        "supply_checksum_test_pass",
        "metadata_crosscheck_pass",
    ]
    compliance_fail = any(not lr.get(k, False) for k in keys)

security_report = os.path.join("$ROOT", "var/compliance/security_layers_report.json")
security_coverage = None
if os.path.isfile(security_report):
    with open(security_report) as f:
        sec = json.load(f)
    security_coverage = sec.get("summary", {}).get("documented_pct")

sovereign_report = os.path.join("$ROOT", "var/compliance/sovereign_protocols_report.json")
sovereign_documented_pct = None
atomic_defense_pct = None
sovereign_gate_pass = None
helix_documented_pct = None
if os.path.isfile(sovereign_report):
    with open(sovereign_report) as f:
        spr = json.load(f)
    ssum = spr.get("summary", {})
    sovereign_documented_pct = ssum.get("documented_pct")
    atomic_defense_pct = ssum.get("atomic_600_pct")
    sovereign_gate_pass = ssum.get("gate_pass")

helix_report = os.path.join("$ROOT", "var/compliance/helix_components_report.json")
helix_gate_pass = None
if os.path.isfile(helix_report):
    with open(helix_report) as f:
        hx = json.load(f)
    hsum = hx.get("summary", {})
    helix_documented_pct = hsum.get("helix_documented_pct", hsum.get("documented_pct"))
    helix_gate_pass = hsum.get("gate_pass")

passed = statuses.count("pass")
failed = statuses.count("fail")
skipped = statuses.count("skip")
scored = passed + failed
readiness_pct = round(100 * passed / scored, 1) if scored else 0.0

launch_ready = (
    not pretest_zone1_fail
    and not validation_fail
    and not compliance_fail
    and $HARD_FAILED == 0
)

report = {
    "generated_at": $end_ts,
    "summary": {
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "hard_failed": $HARD_FAILED,
        "duration_seconds": $duration,
        "readiness_pct": readiness_pct,
        "launch_ready": launch_ready,
        "pretest_l1_pulse": pretest_l1_pulse,
        "pretest_zone1_fail": pretest_zone1_fail,
        "validation_fail": validation_fail,
        "compliance_fail": compliance_fail,
        "security_layers_documented_pct": security_coverage,
        "sovereign_documented_pct": sovereign_documented_pct,
        "atomic_defense_pct": atomic_defense_pct,
        "sovereign_gate_pass": sovereign_gate_pass,
        "helix_documented_pct": helix_documented_pct,
        "helix_gate_pass": helix_gate_pass,
    },
    "phases": [
        {"name": n, "status": s, "detail": d}
        for n, s, d in zip(phases, statuses, details)
    ],
}
with open("$REPORT_JSON", "w") as f:
    json.dump(report, f, indent=2)
print(json.dumps(report["summary"], indent=2))
PY
}

echo "CLRTY Launch Readiness Runner"
echo "Root: $ROOT"
echo "Output: $OUT_DIR"

PRET_ARGS=(--continue --skip-foundry)
VAL_ARGS=(--skip-foundry)
[[ "$CONTINUE" -eq 1 ]] && VAL_ARGS+=(--continue)

run_phase "pretest" 1 bash scripts/test/full_pretest.sh "${PRET_ARGS[@]}"
run_phase "validation" 1 bash scripts/test/full_validation.sh "${VAL_ARGS[@]}"
run_phase "system_check" 0 bash scripts/test/system_check.sh
run_phase "l1_substrate_audit" 0 bash scripts/audit/l1_substrate_audit.sh
run_phase "listing_compliance_pack" 1 bash scripts/audit/generate_listing_compliance_pack.sh
run_phase "mainnet_contract_gates" 1 bash scripts/launch/verify_mainnet_contract_gates.sh
run_phase "bridge_connection_hashes" 0 bash scripts/audit/verify_bridge_connection_hashes.sh
run_phase "security_layers_audit" 0 bash scripts/audit/verify_security_layers.sh
run_phase "sovereign_protocols_audit" 0 bash scripts/audit/verify_sovereign_protocols.sh
run_phase "helix_components_audit" 0 bash scripts/audit/verify_helix_components.sh
run_phase "arbitrage_core_tests" 0 cargo test -p arbitrage_core
run_phase "quant_stack_tests" 0 cargo test -p quant_stack
run_phase "signal_bridge_tests" 0 cargo test -p clrty-signal-bridge

if [[ -f scripts/stress/fork_swap_stress.sh ]]; then
  run_phase "fork_swap_stress" 0 bash scripts/stress/fork_swap_stress.sh 100
else
  skip_phase "fork_swap_stress" "script not found"
fi

if [[ "$SKIP_SIM" -eq 0 ]] && [[ -f scripts/sim/run_100_events.sh ]]; then
  run_phase "sim_100_events" 0 bash scripts/sim/run_100_events.sh 42
else
  skip_phase "sim_100_events" "skipped (--skip-sim or script missing)"
fi

run_phase "treasury_dashboard_sync" 0 bash scripts/investor/build_treasury_data.sh

if [[ "$WITH_BREAK_IT" -eq 1 ]] && [[ -f scripts/stress/break_it_suite.sh ]]; then
  run_phase "break_it_suite" 0 bash scripts/stress/break_it_suite.sh
else
  skip_phase "break_it_suite" "pass --with-break-it to enable"
fi

write_report

echo ""
echo "=== Launch Readiness Summary ==="
echo "Report: $REPORT_JSON"

if [[ "$JSON" -eq 1 ]]; then
  cat "$REPORT_JSON"
fi

if [[ "$HARD_FAILED" -gt 0 ]]; then
  exit 1
fi

python3 -c "
import json, sys
with open('$REPORT_JSON') as f:
    s = json.load(f)['summary']
if not s.get('launch_ready'):
    sys.exit(1)
"

exit 0
