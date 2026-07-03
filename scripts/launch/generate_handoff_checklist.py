#!/usr/bin/env python3
"""Generate handoff_checklist.json for external multi-sig / genesis / TGE gates."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "var/compliance/handoff_checklist.json"


def step_status(artifact: Path, *, ready_if_exists: bool = False) -> str:
    if artifact.is_file():
        try:
            data = json.loads(artifact.read_text())
            if data.get("complete") or data.get("gate_pass"):
                return "complete"
        except json.JSONDecodeError:
            pass
        return "ready" if ready_if_exists else "pending"
    return "pending"


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    timelock = ROOT / "deployments/timelock-evm.json"
    infra = ROOT / "var/compliance/infrastructure_lock_report.json"
    repo_lock = False
    if infra.is_file():
        repo_lock = json.loads(infra.read_text()).get("repo_lock_pass", False)

    steps = [
        {
            "id": 1,
            "owner": "ops",
            "action": "Deploy FmaTimelockController + schedule init ops",
            "artifact": "deployments/timelock-evm.json",
            "status": step_status(timelock, ready_if_exists=True),
        },
        {
            "id": 2,
            "owner": "safe_3_of_5",
            "action": "Execute lockConfiguration after 48h timelock",
            "artifact": "var/compliance/timelock_deployment_report.json",
            "status": step_status(ROOT / "var/compliance/timelock_deployment_report.json"),
        },
        {
            "id": 3,
            "owner": "custody",
            "action": "HSM genesis key ceremony",
            "artifact": "genesis_ceremony_attestation.json",
            "status": step_status(ROOT / "genesis_ceremony_attestation.json"),
        },
        {
            "id": 4,
            "owner": "board",
            "action": "Sign TOKENOMICS_LOCKED.md",
            "artifact": "docs/tokenomics/TOKENOMICS_LOCKED.md",
            "status": "pending",
        },
        {
            "id": 5,
            "owner": "release",
            "action": "Tag TGE_PROD_DEPLOYED on frozen commit",
            "artifact": "git tag TGE_PROD_DEPLOYED",
            "status": "pending",
        },
        {
            "id": 6,
            "owner": "automation",
            "action": "Enable scheduled system_integrity.yml + disable human override keys",
            "artifact": "var/compliance/automation_boundary.json",
            "status": step_status(ROOT / "var/compliance/automation_boundary.json"),
        },
        {
            "id": 7,
            "owner": "external_mm",
            "action": "External MM quotes + custody ingestion for capital stack",
            "artifact": "var/trading/capital_execution_report.json",
            "status": step_status(ROOT / "var/trading/capital_execution_report.json", ready_if_exists=True),
        },
    ]

    external_complete = all(s["status"] == "complete" for s in steps)
    handoff_ready = repo_lock and external_complete

    report = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "task": "handoff_checklist",
        "repo_lock_pass": repo_lock,
        "handoff_ready": handoff_ready,
        "steps": steps,
    }
    OUT.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
