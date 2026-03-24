#!/usr/bin/env python3
"""Run the PR10 umbrella emitted-output GNATprove baseline gate."""

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
    require,
    require_pipeline_report,
    require_pipeline_result,
    resolve_generated_path,
    run,
    write_report,
)
from _lib.pr10_emit import REPO_ROOT


DEFAULT_REPORT = RETIRED_ARCHIVE_REPORT_PATHS["pr10_emitted_baseline"]
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
    RETIRED_ARCHIVE_REPORT_RELS["pr10_contract_baseline"],
    RETIRED_ARCHIVE_REPORT_RELS["pr10_emitted_flow"],
    RETIRED_ARCHIVE_REPORT_RELS["pr10_emitted_prove"],
    RETIRED_ARCHIVE_REPORT_RELS["pr10_emitted_baseline"],
]
SLICE_PIPELINE_IDS = {
    "run_pr10_contract_baseline.py": "pr10_contract_baseline",
    "run_pr10_emitted_flow.py": "pr10_emitted_flow",
    "run_pr10_emitted_prove.py": "pr10_emitted_prove",
}
CI_AUTHORITATIVE_SLICE_IDS = frozenset({"pr10_emitted_flow", "pr10_emitted_prove"})
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


def local_reused_slice_stdout(*, script: Path) -> str:
    label = script.stem
    if label.startswith("run_"):
        label = label[4:]
    return f"{label.replace('_', ' ')}: OK ($TMPDIR/{script.stem}.json)\n"


def load_reused_slice_report(
    *,
    script: Path,
    generated_root: Path | None,
) -> dict[str, object]:
    node_id = SLICE_PIPELINE_IDS[script.name]
    report_path = resolve_generated_path(
        RETIRED_ARCHIVE_REPORT_PATHS[node_id],
        generated_root=generated_root,
        policy=EVIDENCE_POLICY,
        repo_root=REPO_ROOT,
    )
    payload = json.loads(report_path.read_text(encoding="utf-8"))
    require(payload.get("deterministic") is True, f"{display_path(report_path, repo_root=REPO_ROOT)} must be deterministic")
    require(
        payload.get("report_sha256") == payload.get("repeat_sha256"),
        f"{display_path(report_path, repo_root=REPO_ROOT)} report hashes must match",
    )
    return {
        "script": display_path(script, repo_root=REPO_ROOT),
        "stdout": local_reused_slice_stdout(script=script),
        "report_sha256": payload["report_sha256"],
        "deterministic": payload["deterministic"],
    }


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


def build_slice_reports_standalone(
    *,
    env: dict[str, str],
    authority: str,
    generated_root: Path | None,
) -> list[dict[str, object]]:
    python = find_command("python3")
    with tempfile.TemporaryDirectory(prefix="pr10-baseline-") as temp_root_str:
        temp_root = Path(temp_root_str)
        results: list[dict[str, object]] = []
        for script in SLICE_SCRIPTS:
            node_id = SLICE_PIPELINE_IDS[script.name]
            if authority == "local" and node_id in CI_AUTHORITATIVE_SLICE_IDS:
                results.append(load_reused_slice_report(script=script, generated_root=generated_root))
                continue
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
    return results


def generate_report(
    *,
    env: dict[str, str],
    results: list[dict[str, object]],
    generated_root: Path | None,
) -> dict[str, object]:
    python = find_command("python3")
    tracker = load_tracker()
    task_map = {task["id"]: task for task in tracker["tasks"]}  # type: ignore[index]
    require(
        next_task_is_at_or_beyond_pr10(tracker.get("next_task_id")),
        "tracker next_task_id must remain at or beyond PR10 for the PR10 baseline",
    )
    require(task_map["PR10"]["status"] == "done", "PR10 must be marked done")
    require(
        task_map["PR10"]["evidence"] == EXPECTED_EVIDENCE,
        "PR10 evidence must list the committed PR10 reports in order",
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
    parser.add_argument("--pipeline-input", type=Path)
    parser.add_argument("--generated-root", type=Path)
    parser.add_argument("--authority", choices=("local", "ci"), default="local")
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    pipeline_input = load_pipeline_input(args.pipeline_input)
    results = (
        build_slice_reports_from_pipeline(pipeline_input=pipeline_input)
        if pipeline_input
        else build_slice_reports_standalone(
            env=env,
            authority=args.authority,
            generated_root=args.generated_root,
        )
    )
    report = finalize_deterministic_report(
        lambda: generate_report(
            env=env,
            results=results,
            generated_root=args.generated_root,
        ),
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
