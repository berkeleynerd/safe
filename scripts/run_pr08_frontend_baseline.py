#!/usr/bin/env python3
"""Run the PR08 umbrella baseline gate and verify the PR07->PR08 baseline flip."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    finalize_deterministic_report,
    find_command,
    require,
    run,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr08-frontend-baseline-report.json"
TRACKER_PATH = REPO_ROOT / "execution" / "tracker.json"
DASHBOARD_PATH = REPO_ROOT / "execution" / "dashboard.md"
FRONTEND_BASELINE_PATH = REPO_ROOT / "docs" / "frontend_architecture_baseline.md"
README_PATH = REPO_ROOT / "README.md"
COMPILER_README_PATH = REPO_ROOT / "compiler_impl" / "README.md"
SUBGATE_SCRIPTS = (
    "scripts/run_pr081_local_concurrency_frontend.py",
    "scripts/run_pr082_local_concurrency_analysis.py",
    "scripts/run_pr083_interface_contracts.py",
    "scripts/run_pr083a_public_constants.py",
    "scripts/run_pr084_transitive_concurrency_integration.py",
)


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    compact = dict(result)
    for key in ("stdout", "stderr"):
        text = compact.get(key, "")
        if isinstance(text, str) and len(text) > 400:
            compact[key] = f"<{len(text)} chars>"
    return compact


def load_tracker() -> dict[str, Any]:
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def require_contains(text: str, snippet: str, label: str) -> None:
    require(snippet in text, f"{label}: expected to contain {snippet!r}")


def require_absent(text: str, snippet: str, label: str) -> None:
    require(snippet not in text, f"{label}: did not expect {snippet!r}")


def next_task_is_at_or_beyond_pr09(value: object) -> bool:
    if value is None:
        return True
    if not isinstance(value, str):
        return False
    return value == "PR09" or value.startswith("PR10")


def run_subgates(*, python: str) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for script in SUBGATE_SCRIPTS:
        result = run([python, script], cwd=REPO_ROOT)
        results[Path(script).name] = compact_result(result)
    return results


def generate_report(
    *,
    python: str,
    subgate_results: dict[str, Any],
) -> dict[str, Any]:
    tracker = load_tracker()
    task_map = {task["id"]: task for task in tracker["tasks"]}
    require(next_task_is_at_or_beyond_pr09(tracker.get("next_task_id")), "tracker next_task_id must remain at or beyond PR09 for the PR08 baseline")
    require(task_map["PR08.4"]["status"] == "done", "PR08.4 must be marked done")
    require(task_map["PR08"]["status"] == "done", "PR08 umbrella task must be marked done")
    require(
        "execution/reports/pr084-transitive-concurrency-integration-report.json"
        in task_map["PR08.4"]["evidence"],
        "PR08.4 evidence must include the transitive integration report",
    )
    require(
        "execution/reports/pr08-frontend-baseline-report.json" in task_map["PR08"]["evidence"],
        "PR08 umbrella evidence must include the PR08 baseline report",
    )

    rendered_dashboard = run([python, "scripts/render_execution_status.py"], cwd=REPO_ROOT)
    dashboard_text = DASHBOARD_PATH.read_text(encoding="utf-8")
    require(
        dashboard_text == rendered_dashboard["stdout"],
        "execution/dashboard.md must match scripts/render_execution_status.py output",
    )
    require(
        re.search(r"- \*\*Next task:\*\* `(PR09|PR10(?:\.[0-9]+)?|none)`", dashboard_text) is not None,
        "execution/dashboard.md: expected PR09-or-later as next task until completion, then none",
    )
    require_contains(dashboard_text, "| PR08.4 | done | PR08.3 | 1 |", "execution/dashboard.md")
    require_contains(dashboard_text, "| PR08 | done | PR08.4 | 1 |", "execution/dashboard.md")

    baseline_text = FRONTEND_BASELINE_PATH.read_text(encoding="utf-8")
    require_contains(
        baseline_text,
        "This document is the canonical prose baseline for the Safe compiler frontend after PR08.",
        "docs/frontend_architecture_baseline.md",
    )
    require_contains(
        baseline_text,
        "cross-package task ownership, channel-access, and channel ceiling analysis through imported `safei-v1` summaries",
        "docs/frontend_architecture_baseline.md",
    )
    require_contains(
        baseline_text,
        "imported-call ownership semantics at the call boundary",
        "docs/frontend_architecture_baseline.md",
    )
    require_absent(
        baseline_text,
        "cross-package ownership/channel-ceiling analysis beyond the PR08.3 interface slice",
        "docs/frontend_architecture_baseline.md",
    )

    readme_text = README_PATH.read_text(encoding="utf-8")
    require_contains(
        readme_text,
        "the PR08.4 transitive integration slice for imported-summary consumption plus cross-package ownership/channel-ceiling analysis",
        "README.md",
    )
    require_absent(
        readme_text,
        "PR07 is the milestone that establishes this expanded baseline before PR08.",
        "README.md",
    )

    compiler_readme_text = COMPILER_README_PATH.read_text(encoding="utf-8")
    require_contains(
        compiler_readme_text,
        "the PR08.4 transitive integration slice for imported-summary consumption, cross-package ownership/channel-ceiling analysis, and imported-call ownership semantics",
        "compiler_impl/README.md",
    )
    require_contains(
        compiler_readme_text,
        "the current frontend baseline is now PR08.",
        "compiler_impl/README.md",
    )

    return {
        "task": "PR08",
        "status": "ok",
        "subgates": subgate_results,
        "tracker": {
            "next_task_id": tracker["next_task_id"],
            "pr084_status": task_map["PR08.4"]["status"],
            "pr08_status": task_map["PR08"]["status"],
            "pr084_evidence": task_map["PR08.4"]["evidence"],
            "pr08_evidence": task_map["PR08"]["evidence"],
        },
        "docs": {
            "dashboard_synced": True,
            "frontend_baseline": display_path(FRONTEND_BASELINE_PATH),
            "readme": display_path(README_PATH),
            "compiler_readme": display_path(COMPILER_README_PATH),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    subgate_results = run_subgates(python=python)
    report = finalize_deterministic_report(
        lambda: generate_report(python=python, subgate_results=subgate_results),
        label="PR08 frontend baseline",
    )
    write_report(args.report, report)
    print(f"pr08 frontend baseline: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
