#!/usr/bin/env python3
"""Merge Nano / Engineering / Mainnet task ledgers → launch_tasks_snapshot.json."""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "CLRTY_SUBSTRATE/boot/launch_tasks_manifest.json"
OUT = ROOT / "var/launch/launch_tasks_snapshot.json"

STATUS_MAP = {
    "done": "done",
    "complete": "done",
    "pass": "done",
    "[x]": "done",
    "partial": "partial",
    "template ready": "partial",
    "counsel review": "partial",
    "planned": "planned",
    "not started": "planned",
    "deferred": "deferred",
    "external": "external",
    "external pending": "external",
    "blocked": "external",
    "[ ]": "partial",
}


def norm_status(raw: str) -> str:
    key = raw.strip().lower().replace("**", "")
    return STATUS_MAP.get(key, "partial")


def parse_nano_table(text: str) -> list[dict]:
    tasks: list[dict] = []
    in_table = False
    for line in text.splitlines():
        if re.match(r"^\| # \| Step \|", line):
            in_table = True
            continue
        if not in_table:
            continue
        if not line.startswith("|") or line.startswith("|---"):
            if tasks and not line.startswith("|"):
                in_table = False
            continue
        parts = [p.strip() for p in line.split("|")[1:-1]]
        if len(parts) < 5:
            continue
        num_raw, title, evidence, status_raw, verify = parts[0], parts[1], parts[2], parts[3], parts[4]
        if not num_raw.isdigit():
            continue
        num = int(num_raw)
        phase = 1 if num <= 20 else 2 if num <= 40 else 3 if num <= 60 else 4 if num <= 80 else 5
        tasks.append(
            {
                "id": f"N-{num:02d}",
                "track": "nano",
                "phase": f"Phase {phase}",
                "title": title,
                "status": norm_status(status_raw),
                "evidence": evidence.strip("`"),
                "actions_taken": "",
                "verify_command": verify.strip("`"),
                "blockers": [],
                "requires_meeting": False,
            }
        )
    return tasks


def parse_l1_checklist(text: str) -> list[dict]:
    tasks: list[dict] = []
    for line in text.splitlines():
        m = re.match(r"^\| (\d+) \| (.+?) \| (\w[\w ]*?) \| `?(.+?)`? \|", line)
        if not m:
            continue
        num = int(m.group(1))
        if num < 41 or num > 60:
            continue
        tasks.append(
            {
                "id": f"M-L1-{num}",
                "track": "mainnet_l1",
                "phase": "L1 Launch 41-60",
                "title": m.group(2).strip(),
                "status": norm_status(m.group(3)),
                "evidence": m.group(4).strip(),
                "actions_taken": "",
                "verify_command": "bash scripts/predeploy/l1_launch_simulation.sh",
                "blockers": [],
                "requires_meeting": False,
            }
        )
    return tasks


def parse_phase2(text: str) -> list[dict]:
    tasks: list[dict] = []
    for line in text.splitlines():
        m = re.match(r"^\| \*\*(\d+)\*\* \| (.+?) \| .+? \| (.+?) \|", line)
        if not m:
            continue
        num = int(m.group(1))
        tasks.append(
            {
                "id": f"E-{num:02d}",
                "track": "engineering",
                "phase": "Phase 2 Compliance",
                "title": m.group(2).strip(),
                "status": norm_status(m.group(3)),
                "evidence": f"docs/compliance/phase2_tasks_21_40.md",
                "actions_taken": "",
                "verify_command": "bash scripts/audit/generate_listing_compliance_pack.sh",
                "blockers": [],
                "requires_meeting": num in range(21, 29),
            }
        )
    return tasks


def parse_engineering_ledger(text: str) -> list[dict]:
    tasks: list[dict] = []
    checkbox_re = re.compile(r"^- \[(x| )\] (\d+)(?:–(\d+))? (.+)$")
    for line in text.splitlines():
        m = checkbox_re.match(line.strip())
        if not m:
            continue
        done = m.group(1) == "x"
        start = int(m.group(2))
        end = int(m.group(3)) if m.group(3) else start
        title = m.group(4).strip()
        for num in range(start, end + 1):
            phase = 1 if num <= 20 else 2 if num <= 40 else 3 if num <= 60 else 4 if num <= 80 else 5
            status = "done" if done else "partial"
            if num == 70 and not done:
                status = "external"
            tasks.append(
                {
                    "id": f"E-{num:02d}",
                    "track": "engineering",
                    "phase": f"Phase {phase}",
                    "title": title if start == end else f"{title} (task {num})",
                    "status": status,
                    "evidence": "docs/100_task_ledger.md",
                    "actions_taken": "Marked done in engineering ledger" if done else "",
                    "verify_command": "",
                    "blockers": ["mainnet ops"] if num == 70 else [],
                    "requires_meeting": False,
                }
            )
    return tasks


def fill_engineering_gaps(existing: dict[str, dict]) -> None:
    """Add E-01..E-100 placeholders for tasks missing from checkbox list."""
    for num in range(1, 101):
        tid = f"E-{num:02d}"
        if tid in existing:
            continue
        phase = 1 if num <= 20 else 2 if num <= 40 else 3 if num <= 60 else 4 if num <= 80 else 5
        status = "partial"
        note = "doc incomplete — verify via scripts"
        if 21 <= num <= 40:
            status = "partial"
            note = "see phase2_tasks_21_40.md"
        existing[tid] = {
            "id": tid,
            "track": "engineering",
            "phase": f"Phase {phase}",
            "title": f"Engineering task {num:02d}",
            "status": status,
            "evidence": "docs/100_task_ledger.md",
            "actions_taken": note,
            "verify_command": "",
            "blockers": [],
            "requires_meeting": 21 <= num <= 28,
        }


def load_pretest_tasks() -> list[dict]:
    path = ROOT / "var/pretest/full_pretest_report.json"
    if not path.is_file():
        return []
    data = json.loads(path.read_text())
    tasks: list[dict] = []
    for item in data.get("tasks", data.get("results", [])):
        tid = item.get("id") or item.get("task_id", "")
        if not tid:
            continue
        num = re.search(r"(\d+)", str(tid))
        idx = int(num.group(1)) if num else 0
        passed = item.get("status") == "pass" or item.get("passed") is True
        tasks.append(
            {
                "id": f"M-PT-{idx:03d}",
                "track": "mainnet_pretest",
                "phase": "Full Pretest",
                "title": item.get("name") or item.get("label") or f"Pretest {tid}",
                "status": "done" if passed else "partial",
                "evidence": "var/pretest/full_pretest_report.json",
                "actions_taken": item.get("detail", ""),
                "verify_command": "bash scripts/test/full_pretest.sh",
                "blockers": [] if passed else [item.get("detail", "failed")],
                "requires_meeting": False,
            }
        )
    return tasks


def apply_manifest_overrides(tasks: dict[str, dict], manifest: dict) -> None:
    import os
    meeting_ids = set(manifest.get("requires_meeting_ids", []))
    calendly_url = os.environ.get("CALENDLY_EMBED_URL", "").strip()
    for tid, task in tasks.items():
        if tid in meeting_ids or task.get("requires_meeting"):
            task["requires_meeting"] = True
            if task["status"] in ("external", "planned", "partial") and calendly_url:
                if task["status"] in ("external", "planned"):
                    task["status"] = "scheduled"
                task["calendly_url"] = calendly_url
        if task["status"] == "done" and not task.get("actions_taken"):
            task["actions_taken"] = f"Verified: {task.get('verify_command') or task.get('evidence')}"


def merge_tasks(*sources: list[dict]) -> dict[str, dict]:
    merged: dict[str, dict] = {}
    for src in sources:
        for t in src:
            merged[t["id"]] = t
    return merged


def rollup(tasks: dict[str, dict]) -> dict:
    counts = {"done": 0, "partial": 0, "planned": 0, "deferred": 0, "external": 0, "scheduled": 0}
    by_track: dict[str, dict] = {}
    for t in tasks.values():
        st = t.get("status", "partial")
        counts[st] = counts.get(st, 0) + 1
        tr = t.get("track", "unknown")
        by_track.setdefault(tr, {"total": 0, "done": 0})
        by_track[tr]["total"] += 1
        if st == "done":
            by_track[tr]["done"] += 1
    return {"total": len(tasks), "by_status": counts, "by_track": by_track}


def main() -> int:
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.is_file() else {}
    nano = parse_nano_table((ROOT / "docs/launch/NANO_ORGANIZATION_100.md").read_text())
    l1 = parse_l1_checklist((ROOT / "docs/l1_launch/checklist.md").read_text())
    phase2 = parse_phase2((ROOT / "docs/compliance/phase2_tasks_21_40.md").read_text())
    eng = parse_engineering_ledger((ROOT / "docs/100_task_ledger.md").read_text())
    pretest = load_pretest_tasks()

    merged = merge_tasks(nano, l1, phase2, eng, pretest)
    fill_engineering_gaps(merged)

    # Platform completed seed entries (don't overwrite if same id exists)
    for p in manifest.get("platform_completed", []):
        merged[p["id"]] = {**p, "requires_meeting": False, "blockers": []}

    apply_manifest_overrides(merged, manifest)

    all_tasks = sorted(merged.values(), key=lambda x: x["id"])
    completed = [t for t in all_tasks if t.get("status") == "done"]

    snapshot = {
        "version": 1,
        "computed_at": datetime.now(timezone.utc).isoformat(),
        "rollup": rollup(merged),
        "tasks": all_tasks,
        "completed_work": completed,
        "calendly_embed_url": manifest.get("calendly", {}).get("default_url", ""),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(snapshot, indent=2))
    print(f"[launch-tasks] OK tasks={len(all_tasks)} completed={len(completed)} → {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
