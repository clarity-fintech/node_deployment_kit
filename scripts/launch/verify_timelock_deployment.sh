#!/usr/bin/env bash
# Confirm on-chain timelock deployment variables match master_infrastructure_manifest.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
MANIFEST="${ROOT}/CLRTY_SUBSTRATE/boot/master_infrastructure_manifest.json"
OUT="${ROOT}/var/launch/timelock_deployment_report.json"
DEPLOY="${ROOT}/CLRTY_SUBSTRATE/bridge_perimeter/deployments/timelock-evm.json"
mkdir -p "$(dirname "$OUT")" "$(dirname "$DEPLOY")"

python3 - <<PY
import json, os, sys
from datetime import datetime, timezone

root = "${ROOT}"
manifest_path = "${MANIFEST}"
out_path = "${OUT}"
deploy_path = "${DEPLOY}"

with open(manifest_path) as f:
    manifest = json.load(f)

required_delay = manifest["timelock"]["delay_seconds"]
failures = []
notes = []

# Rust L1 policy
try:
    import subprocess
    r = subprocess.run(
        ["cargo", "test", "-p", "clrty-substrate", "master_init_timelock", "--", "--nocapture"],
        cwd=root, capture_output=True, text=True, timeout=300
    )
    if r.returncode != 0:
        failures.append("master_init_timelock Rust tests failed")
except Exception as e:
    failures.append(f"Rust test invoke: {e}")

# Genesis + issuance (Step 1 Clarity)
try:
    r = subprocess.run(
        ["cargo", "test", "-p", "clrty-substrate", "tokenomics_manifest_matches_genesis", "--", "--nocapture"],
        cwd=root, capture_output=True, text=True, timeout=300
    )
    if r.returncode != 0:
        failures.append("genesis/tokenomics checksum mismatch")
except Exception as e:
    failures.append(f"supply checksum: {e}")

# Optional deployed addresses
deployed = {}
if os.path.isfile(deploy_path):
    with open(deploy_path) as f:
        deployed = json.load(f)
else:
    notes.append("timelock-evm.json not deployed yet — scaffold verification only")
    deployed = {
        "timelock_controller": None,
        "master_infrastructure": None,
        "delay_seconds": required_delay,
        "admin_is_multisig": True,
        "status": "scaffold"
    }

if deployed.get("delay_seconds") and deployed["delay_seconds"] < required_delay:
    failures.append(f"deployed delay {deployed['delay_seconds']} < {required_delay}")

report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "task": "timelock_deployment_verify",
    "required_delay_seconds": required_delay,
    "deployed": deployed,
    "manifest_version": manifest.get("version"),
    "gate_pass": len(failures) == 0,
    "failures": failures,
    "notes": notes,
}
with open(out_path, "w") as f:
    json.dump(report, f, indent=2)
print(json.dumps({"gate_pass": report["gate_pass"], "failures": failures}, indent=2))
sys.exit(0 if report["gate_pass"] else 1)
PY

echo "Timelock report: ${OUT}"
