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

from _lib.attestation_compression import RETIRED_ARCHIVE_REPORT_PATHS, RETIRED_ARCHIVE_REPORT_RELS
from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    load_pipeline_input,
    load_evidence_policy,
    normalize_text,
    require,
    require_pipeline_report,
    require_pipeline_result,
    resolve_generated_path,
    run,
    write_report,
)
from _lib.pr09_emit import REPO_ROOT


DEFAULT_REPORT = RETIRED_ARCHIVE_REPORT_PATHS["pr09_ada_emission_baseline"]
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
    RETIRED_ARCHIVE_REPORT_RELS["pr09a_emitter_surface"],
    RETIRED_ARCHIVE_REPORT_RELS["pr09a_emitter_mvp"],
    RETIRED_ARCHIVE_REPORT_RELS["pr09b_sequential_semantics"],
    RETIRED_ARCHIVE_REPORT_RELS["pr09b_concurrency_output"],
    RETIRED_ARCHIVE_REPORT_RELS["pr09b_snapshot_refresh"],
    RETIRED_ARCHIVE_REPORT_RELS["pr09_ada_emission_baseline"],
]
SLICE_PIPELINE_IDS = {
    "run_pr09a_emitter_surface.py": "pr09a_emitter_surface",
    "run_pr09a_emitter_mvp.py": "pr09a_emitter_mvp",
    "run_pr09b_sequential_semantics.py": "pr09b_sequential_semantics",
    "run_pr09b_concurrency_output.py": "pr09b_concurrency_output",
    "run_pr09b_snapshot_refresh.py": "pr09b_snapshot_refresh",
}
EVIDENCE_POLICY = load_evidence_policy()


def load_tracker() -> dict[str, object]:
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def require_contains(text: str, snippet: str, label: str) -> None:
    require(snippet in text, f"{label}: expected to contain {snippet!r}")


def parse_task_id(value: object) -> tuple[int, int | None] | None:
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r"PR(\d+)(?:\.(\d+)(?:\.(\d+))?[A-Za-z0-9]*)?", value)
    if match is None:
        return None
    major = int(match.group(1))
    minor = int(match.group(2)) if match.group(2) is not None else None
    return (major, minor)


def next_task_is_at_or_beyond_pr10(value: object) -> bool:
    if value is None:
        return True
    parsed = parse_task_id(value)
    return parsed is not None and parsed[0] >= 10


def canonicalize_pipeline_slice_stdout(*, script: Path, node_id: str, stdout: str) -> str:
    normalized = stdout.replace(f"$TMPDIR/{node_id}.json", f"$TMPDIR/{script.stem}.json")
    return re.sub(r"\$TMPDIR/[^\s)]+\.json", f"$TMPDIR/{script.stem}.json", normalized)


def build_slice_reports_from_pipeline(*, pipeline_input: dict[str, object]) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for script in SLICE_SCRIPTS:
        node_id = SLICE_PIPELINE_IDS[script.name]
        result = require_pipeline_result(pipeline_input, node_id=node_id)
        payload = require_pipeline_report(pipeline_input, node_id=node_id)
        results.append(
            {
                "script": display_path(script, repo_root=REPO_ROOT),
                "stdout": canonicalize_pipeline_slice_stdout(
                    script=script,
                    node_id=node_id,
                    stdout=result["stdout"],
                ),
                "report_sha256": payload["report_sha256"],
                "deterministic": payload["deterministic"],
            }
        )
    return results


def build_slice_reports_standalone(*, env: dict[str, str]) -> list[dict[str, object]]:
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
    return results


def generate_report(
    *,
    env: dict[str, str],
    results: list[dict[str, object]],
    generated_root: Path | None,
) -> dict[str, object]:
    python = find_command("python3")
    tracker = load_tracker()
    task_map = {task["id"]: task for task in tracker["tasks"]}
    require(next_task_is_at_or_beyond_pr10(tracker.get("next_task_id")), "tracker next_task_id must remain at or beyond PR10 for the PR09 baseline")
    require(task_map["PR09"]["status"] == "done", "PR09 must be marked done")
    require(
        task_map["PR09"]["evidence"] == EXPECTED_EVIDENCE,
        "PR09 evidence must list the committed PR09 reports in order",
    )

    rendered_dashboard = run([python, "scripts/render_execution_status.py"], cwd=REPO_ROOT, env=env)
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
        and next_task_is_at_or_beyond_pr10(
            None if next_task_match.group(1) == "none" else next_task_match.group(1)
        ),
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
    parser.add_argument("--pipeline-input", type=Path)
    parser.add_argument("--generated-root", type=Path)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    pipeline_input = load_pipeline_input(args.pipeline_input)
    results = (
        build_slice_reports_from_pipeline(pipeline_input=pipeline_input)
        if pipeline_input
        else build_slice_reports_standalone(env=env)
    )
    report = finalize_deterministic_report(
        lambda: generate_report(
            env=env,
            results=results,
            generated_root=args.generated_root,
        ),
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
