#!/usr/bin/env bash
# Rank high performers from morning metrics → scale replication plan
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUT="${ROOT}/var/compliance/scale_replication_plan.json"
mkdir -p "$(dirname "$OUT")"

python3 - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path

root = Path("${ROOT}")
morning = root / "var/compliance/morning_stress_report.json"
pretest = root / "var/pretest/full_pretest_report.json"
sim100 = root / "var/compliance/sim100_convergence_report.json"
helix = root / "var/compliance/helix_throughput_report.json"

def load(p):
    return json.loads(p.read_text()) if p.is_file() else {}

m = load(morning)
pt = load(pretest)
s = load(sim100)
h = load(helix)

systems = []

# pretest_runner
pt_pass = pt.get("gate_pass") or pt.get("summary", {}).get("pass_count", 0) >= 95
systems.append({
    "system": "pretest_runner",
    "signal": "full_pretest_report.json",
    "score": 100 if pt_pass else 70,
    "replicas": 4 if pt_pass else 1,
    "ci_matrix": "shard zones 1-5 into parallel jobs",
})

# SIM100
sim_pass = s.get("gate_pass", False) or s.get("converged", False)
systems.append({
    "system": "sim100",
    "signal": "sim100_convergence_report.json",
    "score": 95 if sim_pass else 60,
    "replicas": 3 if sim_pass else 1,
    "ci_matrix": "run seeds 42,77,133 in morning deep tier",
})

# HELIX kernel
helix_pass = h.get("gate_pass", False)
ticks = h.get("ticks_per_sec", 0)
systems.append({
    "system": "helix_kernel",
    "signal": "helix_throughput_report.json",
    "score": min(100, int(ticks)) if helix_pass else 50,
    "replicas": 2 if helix_pass else 1,
    "ci_matrix": "document horizontal helixd in helix_manifest.json",
})

# L-DNET
ldnet_ok = any(p.get("name") == "ldnet_entropy" and p.get("status") == "pass" for p in m.get("phases", []))
systems.append({
    "system": "l_dnet",
    "signal": "morning ldnet_entropy phase",
    "score": 90 if ldnet_ok else 55,
    "replicas": 3 if ldnet_ok else 1,
    "ci_matrix": "validator count parameter for scale sim",
})

# MIRRA order grid
grid = root / "var/helix/order_grid.json"
grid_ok = grid.is_file()
systems.append({
    "system": "mirra_order_grid",
    "signal": "var/helix/order_grid.json",
    "score": 85 if grid_ok else 40,
    "replicas": 1,
    "ci_matrix": "template ladder in matching_grid.rs for N venues",
})

systems.sort(key=lambda x: x["score"], reverse=True)
report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "task": "scale_replication_plan",
    "morning_tier": m.get("stress_tier"),
    "systems": systems,
    "top_performers": [s["system"] for s in systems[:3]],
}
(root / "var/compliance/scale_replication_plan.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
PY

echo "Scale plan: ${OUT}"
