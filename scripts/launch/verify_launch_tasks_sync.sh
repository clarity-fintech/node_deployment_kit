#!/usr/bin/env bash
# Verify launch task snapshot and optional Notion sync prerequisites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SNAP="$ROOT/var/launch/launch_tasks_snapshot.json"

if [[ ! -f "$SNAP" ]]; then
  echo "[verify-launch-tasks] ERROR: missing $SNAP — run make launch-tasks-build"
  exit 1
fi

python3 - <<'PY'
import json, sys
from pathlib import Path
snap = json.loads(Path("var/launch/launch_tasks_snapshot.json").read_text())
tasks = snap.get("tasks", [])
tracks = {t.get("track") for t in tasks}
completed = snap.get("completed_work", [])
rollup = snap.get("rollup", {})
if len(tracks) < 3:
    print(f"[verify-launch-tasks] ERROR: expected >=3 tracks, got {tracks}")
    sys.exit(1)
done_count = rollup.get("by_status", {}).get("done", 0)
if done_count != len(completed):
    print(f"[verify-launch-tasks] WARN: rollup done={done_count} vs completed_work={len(completed)}")
print(f"[verify-launch-tasks] OK tasks={len(tasks)} tracks={len(tracks)} completed={len(completed)}")
PY

python3 scripts/metrics/sync_notion_launch_tasks.py || true

echo "[verify-launch-tasks] done"
