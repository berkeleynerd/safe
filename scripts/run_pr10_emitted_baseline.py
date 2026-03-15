#!/usr/bin/env python3
"""Run the PR10 umbrella emitted-output GNATprove baseline gate."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    require,
    run,
    write_report,
)
from _lib.pr10_emit import REPO_ROOT


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr10-emitted-baseline-report.json"
TRACKER_PATH = REPO_ROOT / "execution" / "tracker.json"
DASHBOARD_PATH = REPO_ROOT / "execution" / "dashboard.md"
FRONTEND_BASELINE_PATH = REPO_ROOT / "docs" / "frontend_architecture_baseline.md"
MATRIX_PATH = REPO_ROOT / "docs" / "emitted_output_verification_matrix.md"
POST_PR10_SCOPE_PATH = REPO_ROOT / "docs" / "post_pr10_scope.md"
README_PATH = REPO_ROOT / "README.md"
COMPILER_README_PATH = REPO_ROOT / "compiler_impl" / "README.md"
SLICE_SCRIPTS = [
    REPO_ROOT / "scripts" / "run_pr10_contract_baseline.py",
    REPO_ROOT / "scripts" / "run_pr10_emitted_flow.py",
    REPO_ROOT / "scripts" / "run_pr10_emitted_prove.py",
]
EXPECTED_EVIDENCE = [
    "execution/reports/pr10-contract-baseline-report.json",
    "execution/reports/pr10-emitted-flow-report.json",
    "execution/reports/pr10-emitted-prove-report.json",
    "execution/reports/pr10-emitted-baseline-report.json",
]


def load_tracker() -> dict[str, object]:
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def require_contains(text: str, snippet: str, label: str) -> None:
    require(snippet in text, f"{label}: expected to contain {snippet!r}")


def generate_report(*, env: dict[str, str]) -> dict[str, object]:
    python = find_command("python3")
    with tempfile.TemporaryDirectory(prefix="pr10-baseline-") as temp_root_str:
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
                    "stdout": completed["stdout"],
                    "report_sha256": payload["report_sha256"],
                    "deterministic": payload["deterministic"],
                }
            )

        tracker = load_tracker()
        task_map = {task["id"]: task for task in tracker["tasks"]}  # type: ignore[index]
        require(task_map["PR10"]["status"] == "done", "PR10 must be marked done")
        require(
            task_map["PR10"]["evidence"] == EXPECTED_EVIDENCE,
            "PR10 evidence must list the committed PR10 reports in order",
        )

        rendered_dashboard = run([python, "scripts/render_execution_status.py"], cwd=REPO_ROOT, env=env)
        dashboard_text = DASHBOARD_PATH.read_text(encoding="utf-8")
        require(
            dashboard_text == rendered_dashboard["stdout"],
            "execution/dashboard.md must match scripts/render_execution_status.py output",
        )
        require_contains(dashboard_text, "| PR10 | done | PR09 | 4 |", "execution/dashboard.md")

        baseline_text = FRONTEND_BASELINE_PATH.read_text(encoding="utf-8")
        require_contains(
            baseline_text,
            "PR10 adds selected emitted-output GNATprove `flow` / `prove` verification on top",
            "docs/frontend_architecture_baseline.md",
        )

        matrix_text = MATRIX_PATH.read_text(encoding="utf-8")
        require_contains(matrix_text, "zero justified checks", "docs/emitted_output_verification_matrix.md")
        require_contains(matrix_text, "zero unproved checks", "docs/emitted_output_verification_matrix.md")

        post_pr10_text = POST_PR10_SCOPE_PATH.read_text(encoding="utf-8")
        require_contains(
            post_pr10_text,
            "Faithful source-level `select ... or delay ...` semantics beyond the current emitted polling-based lowering",
            "docs/post_pr10_scope.md",
        )
        require_contains(post_pr10_text, "PS-018", "docs/post_pr10_scope.md")
        require_contains(post_pr10_text, "PS-019", "docs/post_pr10_scope.md")

        readme_text = README_PATH.read_text(encoding="utf-8")
        require_contains(
            readme_text,
            "the PR10 emitted-output GNATprove contract/flow/prove/baseline jobs",
            "README.md",
        )
        require_contains(
            readme_text,
            "known `codex/pr08...`, `codex/pr09...`, and `codex/pr10...` branches",
            "README.md",
        )

        compiler_readme_text = COMPILER_README_PATH.read_text(encoding="utf-8")
        require_contains(
            compiler_readme_text,
            "The PR10 emitted baseline gate is:",
            "compiler_impl/README.md",
        )
        require_contains(
            compiler_readme_text,
            "later tracked milestones may exist",
            "compiler_impl/README.md",
        )

        return {
            "slice_reports": results,
            "tracker": {
                "next_task_id": tracker["next_task_id"],
                "pr10_status": task_map["PR10"]["status"],
                "pr10_evidence": task_map["PR10"]["evidence"],
            },
            "docs": {
                "dashboard_synced": True,
                "frontend_baseline": display_path(FRONTEND_BASELINE_PATH, repo_root=REPO_ROOT),
                "matrix": display_path(MATRIX_PATH, repo_root=REPO_ROOT),
                "post_pr10_scope": display_path(POST_PR10_SCOPE_PATH, repo_root=REPO_ROOT),
                "readme": display_path(README_PATH, repo_root=REPO_ROOT),
                "compiler_readme": display_path(COMPILER_README_PATH, repo_root=REPO_ROOT),
            },
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env),
        label="PR10 emitted baseline",
    )
    write_report(args.report, report)
    print(f"pr10 emitted baseline: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr10 emitted baseline: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
