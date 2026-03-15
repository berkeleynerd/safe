#!/usr/bin/env python3
"""Run the PR09 umbrella Ada-emission baseline gate."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    normalize_text,
    require,
    run,
    write_report,
)
from _lib.pr09_emit import REPO_ROOT


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr09-ada-emission-baseline-report.json"
TRACKER_PATH = REPO_ROOT / "execution" / "tracker.json"
DASHBOARD_PATH = REPO_ROOT / "execution" / "dashboard.md"
FRONTEND_BASELINE_PATH = REPO_ROOT / "docs" / "frontend_architecture_baseline.md"
README_PATH = REPO_ROOT / "README.md"
COMPILER_README_PATH = REPO_ROOT / "compiler_impl" / "README.md"
RETIRED_SNAPSHOTS = [
    REPO_ROOT / "tests" / "golden" / "golden_sensors.ada",
    REPO_ROOT / "tests" / "golden" / "golden_ownership.ada",
    REPO_ROOT / "tests" / "golden" / "golden_pipeline.ada",
]
SLICE_SCRIPTS = [
    REPO_ROOT / "scripts" / "run_pr09a_emitter_surface.py",
    REPO_ROOT / "scripts" / "run_pr09a_emitter_mvp.py",
    REPO_ROOT / "scripts" / "run_pr09b_sequential_semantics.py",
    REPO_ROOT / "scripts" / "run_pr09b_concurrency_output.py",
    REPO_ROOT / "scripts" / "run_pr09b_snapshot_refresh.py",
]
EXPECTED_EVIDENCE = [
    "execution/reports/pr09a-emitter-surface-report.json",
    "execution/reports/pr09a-emitter-mvp-report.json",
    "execution/reports/pr09b-sequential-semantics-report.json",
    "execution/reports/pr09b-concurrency-output-report.json",
    "execution/reports/pr09b-snapshot-refresh-report.json",
    "execution/reports/pr09-ada-emission-baseline-report.json",
]


def load_tracker() -> dict[str, object]:
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def require_contains(text: str, snippet: str, label: str) -> None:
    require(snippet in text, f"{label}: expected to contain {snippet!r}")


def next_task_is_at_or_beyond_pr10(value: object) -> bool:
    if value is None:
        return True
    if not isinstance(value, str):
        return False
    return value == "PR10" or value.startswith("PR10.")


def generate_report(*, env: dict[str, str]) -> dict[str, object]:
    python = find_command("python3")
    with tempfile.TemporaryDirectory(prefix="pr09-baseline-") as temp_root_str:
        temp_root = Path(temp_root_str)
        results: list[dict[str, object]] = []
        for script in SLICE_SCRIPTS:
            report_path = temp_root / f"{script.stem}.json"
            completed = run(
                [python, str(script), "--report", str(report_path)],
                cwd=REPO_ROOT,
                env=env,
                temp_root=temp_root,
            )
            payload = json.loads(report_path.read_text(encoding="utf-8"))
            results.append(
                {
                    "script": display_path(script, repo_root=REPO_ROOT),
                    "stdout": normalize_text(completed["stdout"], temp_root=temp_root, repo_root=REPO_ROOT),
                    "report_sha256": payload["report_sha256"],
                    "deterministic": payload["deterministic"],
                }
            )
        tracker = load_tracker()
        task_map = {task["id"]: task for task in tracker["tasks"]}
        require(next_task_is_at_or_beyond_pr10(tracker.get("next_task_id")), "tracker next_task_id must remain at or beyond PR10 for the PR09 baseline")
        require(task_map["PR09"]["status"] == "done", "PR09 must be marked done")
        require(
            task_map["PR09"]["evidence"] == EXPECTED_EVIDENCE,
            "PR09 evidence must list the committed PR09 reports in order",
        )

        rendered_dashboard = run([python, "scripts/render_execution_status.py"], cwd=REPO_ROOT, env=env)
        dashboard_text = DASHBOARD_PATH.read_text(encoding="utf-8")
        require(
            dashboard_text == rendered_dashboard["stdout"],
            "execution/dashboard.md must match scripts/render_execution_status.py output",
        )
        require(
            re.search(r"- \*\*Next task:\*\* `(PR10(?:\.[0-9]+)?|none)`", dashboard_text) is not None,
            "execution/dashboard.md: expected PR10-or-later as next task until milestone completion, then none",
        )
        require_contains(dashboard_text, "| PR09 | done | PR08 | 6 |", "execution/dashboard.md")

        baseline_text = FRONTEND_BASELINE_PATH.read_text(encoding="utf-8")
        require_contains(
            baseline_text,
            "PR09 adds deterministic Ada/SPARK emission on top of that PR08 frontend baseline through `safec emit --ada-out-dir`, without widening the accepted frontend-analysis subset.",
            "docs/frontend_architecture_baseline.md",
        )
        require(
            "broader proof-ready Ada/SPARK emission work beyond the current PR09 subset" in baseline_text
            or "emitted-output GNATprove coverage beyond the selected PR10 corpus" in baseline_text,
            "docs/frontend_architecture_baseline.md: expected the PR09 baseline scope boundary text",
        )

        readme_text = README_PATH.read_text(encoding="utf-8")
        require_contains(
            readme_text,
            "`safec emit --ada-out-dir` can now additionally write deterministic Ada/SPARK artifacts",
            "README.md",
        )
        require_contains(
            readme_text,
            "Unknown milestone branches fail closed until the mapping is updated.",
            "README.md",
        )

        compiler_readme_text = COMPILER_README_PATH.read_text(encoding="utf-8")
        require_contains(
            compiler_readme_text,
            "`safec emit <file.safe> --out-dir <dir> --interface-dir <dir> [--ada-out-dir <dir>] [--interface-search-dir <dir>]...`",
            "compiler_impl/README.md",
        )
        require_contains(
            compiler_readme_text,
            "PR09 layers deterministic Ada/SPARK emission on top of that frontend baseline through the optional `--ada-out-dir` path.",
            "compiler_impl/README.md",
        )

        for retired in RETIRED_SNAPSHOTS:
            require(not retired.exists(), f"retired snapshot still present: {display_path(retired, repo_root=REPO_ROOT)}")

        return {
            "slice_reports": results,
            "tracker": {
                "next_task_id": tracker["next_task_id"],
                "pr09_status": task_map["PR09"]["status"],
                "pr09_evidence": task_map["PR09"]["evidence"],
            },
            "docs": {
                "dashboard_synced": True,
                "frontend_baseline": display_path(FRONTEND_BASELINE_PATH, repo_root=REPO_ROOT),
                "readme": display_path(README_PATH, repo_root=REPO_ROOT),
                "compiler_readme": display_path(COMPILER_README_PATH, repo_root=REPO_ROOT),
            },
            "retired_snapshots_absent": [
                display_path(path, repo_root=REPO_ROOT) for path in RETIRED_SNAPSHOTS
            ],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env),
        label="PR09 baseline",
    )
    write_report(args.report, report)
    print(f"pr09 ada-emission baseline: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr09 ada-emission baseline: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
