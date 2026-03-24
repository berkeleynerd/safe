#!/usr/bin/env python3
"""Run the PR08 umbrella baseline gate and verify the PR07->PR08 baseline flip."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from _lib.attestation_compression import RETIRED_ARCHIVE_REPORT_PATHS, RETIRED_ARCHIVE_REPORT_RELS
from _lib.harness_common import (
    canonicalize_serialized_child_result,
    display_path,
    finalize_deterministic_report,
    find_command,
    load_pipeline_input,
    load_evidence_policy,
    require,
    require_pipeline_result,
    resolve_generated_path,
    run,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REPORT = RETIRED_ARCHIVE_REPORT_PATHS["pr08_frontend_baseline"]
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
SUBGATE_PIPELINE_IDS = {
    "run_pr081_local_concurrency_frontend.py": "pr081_local_concurrency_frontend",
    "run_pr082_local_concurrency_analysis.py": "pr082_local_concurrency_analysis",
    "run_pr083_interface_contracts.py": "pr083_interface_contracts",
    "run_pr083a_public_constants.py": "pr083a_public_constants",
    "run_pr084_transitive_concurrency_integration.py": "pr084_transitive_concurrency",
}
SUBGATE_REPORTS = {
    "run_pr081_local_concurrency_frontend.py": RETIRED_ARCHIVE_REPORT_PATHS["pr081_local_concurrency_frontend"],
    "run_pr082_local_concurrency_analysis.py": RETIRED_ARCHIVE_REPORT_PATHS["pr082_local_concurrency_analysis"],
    "run_pr083_interface_contracts.py": RETIRED_ARCHIVE_REPORT_PATHS["pr083_interface_contracts"],
    "run_pr083a_public_constants.py": RETIRED_ARCHIVE_REPORT_PATHS["pr083a_public_constants"],
    "run_pr084_transitive_concurrency_integration.py": RETIRED_ARCHIVE_REPORT_PATHS["pr084_transitive_concurrency"],
}
EVIDENCE_POLICY = load_evidence_policy()


def compact_subgate_result(result: dict[str, Any]) -> dict[str, Any]:
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


def parse_task_id(value: object) -> tuple[int, int | None] | None:
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r"PR(\d+)(?:\.(\d+)(?:\.(\d+))?[A-Za-z0-9]*)?", value)
    if match is None:
        return None
    major = int(match.group(1))
    minor = int(match.group(2)) if match.group(2) is not None else None
    return (major, minor)


def next_task_is_at_or_beyond_pr09(value: object) -> bool:
    if value is None:
        return True
    parsed = parse_task_id(value)
    return parsed is not None and parsed[0] >= 9


def run_subgates(*, python: str) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for script in SUBGATE_SCRIPTS:
        result = run([python, script], cwd=REPO_ROOT)
        results[Path(script).name] = compact_subgate_result(canonicalize_serialized_child_result(result))
    return results


def pipeline_subgates(*, pipeline_input: dict[str, Any]) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for script_name, node_id in SUBGATE_PIPELINE_IDS.items():
        results[script_name] = compact_subgate_result(
            canonicalize_serialized_child_result(
                require_pipeline_result(pipeline_input, node_id=node_id),
                committed_report_path=SUBGATE_REPORTS[script_name],
            )
        )
    return results


def generate_report(
    *,
    python: str,
    subgate_results: dict[str, Any],
    generated_root: Path | None,
) -> dict[str, Any]:
    tracker = load_tracker()
    task_map = {task["id"]: task for task in tracker["tasks"]}
    require(next_task_is_at_or_beyond_pr09(tracker.get("next_task_id")), "tracker next_task_id must remain at or beyond PR09 for the PR08 baseline")
    require(task_map["PR08.4"]["status"] == "done", "PR08.4 must be marked done")
    require(task_map["PR08"]["status"] == "done", "PR08 umbrella task must be marked done")
    require(
        RETIRED_ARCHIVE_REPORT_RELS["pr084_transitive_concurrency"]
        in task_map["PR08.4"]["evidence"],
        "PR08.4 evidence must include the transitive integration report",
    )
    require(
        RETIRED_ARCHIVE_REPORT_RELS["pr08_frontend_baseline"] in task_map["PR08"]["evidence"],
        "PR08 umbrella evidence must include the PR08 baseline report",
    )

    rendered_dashboard = run([python, "scripts/render_execution_status.py"], cwd=REPO_ROOT)
    dashboard_text = resolve_generated_path(
        DASHBOARD_PATH,
        generated_root=generated_root,
        policy=EVIDENCE_POLICY,
        repo_root=REPO_ROOT,
    ).read_text(encoding="utf-8")
    require(
        dashboard_text == rendered_dashboard["stdout"],
        "execution/dashboard.md must match scripts/render_execution_status.py output",
    )
    next_task_match = re.search(
        r"- \*\*Next task:\*\* `(PR\d+(?:\.[0-9]+(?:\.[0-9]+)?[A-Za-z0-9]*)?|none)`",
        dashboard_text,
    )
    require(
        next_task_match is not None
        and next_task_is_at_or_beyond_pr09(None if next_task_match.group(1) == "none" else next_task_match.group(1)),
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
    parser.add_argument("--pipeline-input", type=Path)
    parser.add_argument("--generated-root", type=Path)
    args = parser.parse_args()

    python = find_command("python3")
    pipeline_input = load_pipeline_input(args.pipeline_input)
    if pipeline_input:
        subgate_results = pipeline_subgates(pipeline_input=pipeline_input)
    else:
        subgate_results = run_subgates(python=python)
    report = finalize_deterministic_report(
        lambda: generate_report(
            python=python,
            subgate_results=subgate_results,
            generated_root=args.generated_root,
        ),
        label="PR08 frontend baseline",
    )
    write_report(args.report, report)
    print(f"pr08 frontend baseline: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
