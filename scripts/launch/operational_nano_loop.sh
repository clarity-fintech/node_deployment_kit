#!/usr/bin/env bash
# 12-Step Operational Nano Loop — token launch day discipline
# Usage: operational_nano_loop.sh [--purge-sandboxes]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
OUT="${ROOT}/var/launch/operational_nano_loop_report.json"
PURGE="${1:-}"
mkdir -p "$(dirname "$OUT")" "${ROOT}/var/sandbox"

python3 - <<PY
import json, os, subprocess, hashlib, re, sys
from datetime import datetime, timezone
from pathlib import Path

root = Path("${ROOT}")
purge = "${PURGE}" == "--purge-sandboxes"
steps = []
failures = []

def step(num, name, fn):
    try:
        detail, ok = fn()
        steps.append({"step": num, "name": name, "status": "pass" if ok else "fail", "detail": detail})
        if not ok:
            failures.append(f"{num}:{name}")
    except Exception as e:
        steps.append({"step": num, "name": name, "status": "error", "detail": str(e)})
        failures.append(f"{num}:{name}")

# 1 Clarity — verify total coin issuance limits
def s1():
    genesis = json.loads((root / "CLRTY_SUBSTRATE/boot/genesis_entropy.json").read_text())
    cap = genesis.get("total_supply", 0)
    ok = cap == 16_000_000 and genesis.get("mint_authority") is None
    return f"total_supply={cap} mint_authority={genesis.get('mint_authority')}", ok

# 2 Audit — profile byte configs of frozen repositories
def s2():
    attrs = (root / ".gitattributes").read_text() if (root / ".gitattributes").is_file() else ""
    modules = (root / "manifests/nexus_modules.json").read_text() if (root / "manifests/nexus_modules.json").is_file() else "{}"
    ok = "filter=lfs" in attrs and "nexus_modules" in modules
    return f"gitattributes_lfs={('filter=lfs' in attrs)} nexus_modules={('nexus_modules' in modules)}", ok

# 3 Filter — flag non-critical developer test scripts (report only)
def s3():
    scripts = list((root / "scripts").rglob("*test*.sh"))
    critical = {"full_pretest.sh", "full_validation.sh", "operational_nano_loop.sh", "verify_timelock_deployment.sh"}
    non_critical = [str(p.relative_to(root)) for p in scripts if p.name not in critical]
    return f"non_critical_test_scripts={len(non_critical)} (report-only)", True

# 4 Simplify — strip floating-point from target math contracts
def s4():
    math_dirs = [
        root / "CLRTY_SUBSTRATE/economic_engine",
        root / "CLRTY_SUBSTRATE/governance_substrate",
        root / "CLRTY_SUBSTRATE/bridge_perimeter/fma/contracts/src",
    ]
    float_hits = []
    for d in math_dirs:
        if not d.is_dir():
            continue
        for p in d.rglob("*"):
            if p.suffix not in (".rs", ".sol"):
                continue
            text = p.read_text(errors="ignore")
            if p.suffix == ".rs" and re.search(r"\bf32\b|\bf64\b", text):
                float_hits.append(str(p.relative_to(root)))
            elif p.suffix == ".sol" and re.search(r"\b(fixed|ufixed)\d*", text):
                float_hits.append(str(p.relative_to(root)))
    ok = len(float_hits) == 0
    return f"float_patterns_in_target={len(float_hits)}", ok

# 5 Define — confirm parameters inside genesis_entropy.json
def s5():
    genesis = json.loads((root / "CLRTY_SUBSTRATE/boot/genesis_entropy.json").read_text())
    required = ["chain_id", "denom", "total_supply", "decimals", "allocations"]
    missing = [k for k in required if k not in genesis]
    ok = not missing and genesis["chain_id"] == "clrty-1"
    return f"missing={missing or 'none'} chain_id={genesis.get('chain_id')}", ok

# 6 Prioritise — Phase 1 math validation scripts
def s6():
    r = subprocess.run(
        ["cargo", "test", "-p", "clrty-substrate", "initial_float_control", "--", "--nocapture"],
        cwd=root, capture_output=True, text=True, timeout=300
    )
    ok = r.returncode == 0
    return "initial_float_control tests", ok

# 7 Reduce — consolidate multi-chain development keys
def s7():
    custody = root / "CLRTY_SUBSTRATE/bridge_perimeter/deployments"
    evm = custody / "custody-evm.json"
    svm = custody / "custody-svm.json"
    if not evm.is_file():
        subprocess.run(["bash", "scripts/multisig/deploy_custody.sh"], cwd=root, check=False)
    ok = evm.is_file() and svm.is_file()
    return f"evm={evm.is_file()} svm={svm.is_file()}", ok

# 8 Structure — map addresses inside 100-tier index framework
def s8():
    mapper = root / "CLRTY_SUBSTRATE/entropy_sink_engine/set_dynamics/binary_index_mapper.rs"
    doc = root / "docs/governance/BINARY_INDEX_CONSENSUS_MAP.md"
    ok = mapper.is_file() and doc.is_file()
    return f"binary_index_mapper={mapper.is_file()} consensus_map={doc.is_file()}", ok

# 9 Stabilise — deploy baseline multi-sig nodes (Safe / Squads)
def s9():
    r = subprocess.run(
        ["cargo", "test", "-p", "clrty-substrate", "multisig_config", "--", "--nocapture"],
        cwd=root, capture_output=True, text=True, timeout=300
    )
    ok = r.returncode == 0
    return "multisig_config custody_ready tests", ok

# 10 Confirm — verify timelock deployment variables
def s10():
    r = subprocess.run(
        ["bash", "scripts/launch/verify_timelock_deployment.sh"],
        cwd=root, capture_output=True, text=True, timeout=600
    )
    ok = r.returncode == 0
    return "verify_timelock_deployment.sh", ok

# 11 Lock — freeze master infrastructure configurations
def s11():
    manifest = root / "CLRTY_SUBSTRATE/boot/master_infrastructure_manifest.json"
    ok = manifest.is_file()
    if ok:
        data = json.loads(manifest.read_text())
        lock_step = any(m.get("step") == "lockConfiguration" for m in data.get("master", {}).get("init_methods", []))
        ok = lock_step and data["timelock"]["delay_seconds"] == 172800
    return f"master_infrastructure_manifest lockConfiguration+48h", ok

# 12 Reset — purge developer sandboxes
def s12():
    sandbox = root / "var/sandbox"
    sandbox.mkdir(parents=True, exist_ok=True)
    purged = 0
    if purge:
        for p in sandbox.iterdir():
            if p.name == ".gitkeep":
                continue
            if p.is_file():
                p.unlink()
                purged += 1
            elif p.is_dir():
                import shutil
                shutil.rmtree(p)
                purged += 1
    return f"purge={purge} purged_items={purged}", True

for i, (n, fn) in enumerate([
    (1, "Clarity", s1), (2, "Audit", s2), (3, "Filter", s3), (4, "Simplify", s4),
    (5, "Define", s5), (6, "Prioritise", s6), (7, "Reduce", s7), (8, "Structure", s8),
    (9, "Stabilise", s9), (10, "Confirm", s10), (11, "Lock", s11), (12, "Reset", s12),
], 1):
    step(i, n, fn)

report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "task": "operational_nano_loop_12",
    "steps": steps,
    "gate_pass": len(failures) == 0,
    "failures": failures,
}
out = root / "var/launch/operational_nano_loop_report.json"
out.write_text(json.dumps(report, indent=2))
print(json.dumps({"gate_pass": report["gate_pass"], "passed": sum(1 for s in steps if s["status"]=="pass"), "total": 12}, indent=2))
sys.exit(0 if report["gate_pass"] else 1)
PY

echo "Operational nano loop report: ${OUT}"
