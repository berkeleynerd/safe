#!/usr/bin/env python3
"""Render execution/dashboard.md from execution/tracker.json."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List


REPO_ROOT = Path(__file__).resolve().parent.parent
TRACKER_PATH = REPO_ROOT / "execution" / "tracker.json"
DASHBOARD_PATH = REPO_ROOT / "execution" / "dashboard.md"


def load_tracker(path: Path = TRACKER_PATH) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _task_rows(tasks: List[Dict[str, Any]]) -> List[str]:
    rows = [
        "| Task | Status | Depends On | Evidence |",
        "|------|--------|------------|----------|",
    ]
    for task in tasks:
        deps = ", ".join(task["depends_on"]) if task["depends_on"] else "--"
        evidence = str(len(task["evidence"]))
        rows.append(f"| {task['id']} | {task['status']} | {deps} | {evidence} |")
    return rows


def render_dashboard(tracker: Dict[str, Any]) -> str:
    tests = tracker["repo_facts"]["tests"]
    active = tracker.get("active_task_id") or "none"
    nxt = tracker.get("next_task_id") or "none"
    tasks = tracker["tasks"]

    lines = [
        "# Execution Dashboard",
        "",
        f"- **Schema version:** `{tracker['schema_version']}`",
        f"- **Frozen spec SHA:** `{tracker['frozen_spec_sha']}`",
        f"- **Active task:** `{active}`",
        f"- **Next task:** `{nxt}`",
        f"- **Updated at:** `{tracker['updated_at']}`",
        "",
        "## Repo Facts",
        "",
        f"- `tests/positive`: {tests['positive']}",
        f"- `tests/negative`: {tests['negative']}",
        f"- `tests/golden`: {tests['golden']}",
        f"- `tests/concurrency`: {tests['concurrency']}",
        f"- `tests/diagnostics_golden`: {tests['diagnostics_golden']}",
        f"- **Total test files:** {tests['total']}",
        "",
        "## Task Ledger",
        "",
    ]
    lines.extend(_task_rows(tasks))
    lines.extend(
        [
            "",
            "## Acceptance Snapshot",
            "",
        ]
    )
    for task in tasks:
        lines.append(f"### {task['id']} — {task['title']}")
        lines.append("")
        lines.append(f"- **Status:** `{task['status']}`")
        lines.append(f"- **Depends on:** {', '.join(task['depends_on']) if task['depends_on'] else '--'}")
        if task["blockers"]:
            lines.append(f"- **Blockers:** {', '.join(task['blockers'])}")
        else:
            lines.append("- **Blockers:** none")
        lines.append("- **Acceptance:**")
        for criterion in task["acceptance"]:
            lines.append(f"  - {criterion}")
        if task["evidence"]:
            lines.append("- **Evidence:**")
            for entry in task["evidence"]:
                lines.append(f"  - `{entry}`")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tracker", type=Path, default=TRACKER_PATH)
    parser.add_argument("--write", action="store_true", help="Write the rendered dashboard to execution/dashboard.md")
    args = parser.parse_args()

    tracker = load_tracker(args.tracker)
    rendered = render_dashboard(tracker)

    if args.write:
        DASHBOARD_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
