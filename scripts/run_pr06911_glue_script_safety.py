#!/usr/bin/env python3
"""Run the PR06.9.11 glue-script safety gate."""

from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    require,
    require_repo_command,
    rerun_report_gate_and_compare,
    run,
    write_report,
)
from validate_execution_state import check_glue_script_safety, glue_script_safety_report


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr06911-glue-script-safety-report.json"

FRONTEND_SMOKE_SCRIPT = REPO_ROOT / "scripts" / "run_frontend_smoke.py"
FRONTEND_SMOKE_REPORT = REPO_ROOT / "execution" / "reports" / "pr00-pr04-frontend-smoke.json"
RUNTIME_BOUNDARY_SCRIPT = REPO_ROOT / "scripts" / "run_pr0693_runtime_boundary.py"
RUNTIME_BOUNDARY_REPORT = REPO_ROOT / "execution" / "reports" / "pr0693-runtime-boundary-report.json"
GATE_QUALITY_SCRIPT = REPO_ROOT / "scripts" / "run_pr0697_gate_quality.py"
GATE_QUALITY_REPORT = REPO_ROOT / "execution" / "reports" / "pr0697-gate-quality-report.json"
BUILD_REPRO_SCRIPT = REPO_ROOT / "scripts" / "run_pr0699_build_reproducibility.py"
BUILD_REPRO_REPORT = REPO_ROOT / "execution" / "reports" / "pr0699-build-reproducibility-report.json"
PORTABILITY_SCRIPT = REPO_ROOT / "scripts" / "run_pr06910_portability_environment.py"
PORTABILITY_REPORT = REPO_ROOT / "execution" / "reports" / "pr06910-portability-environment-report.json"
VALIDATE_EXECUTION_STATE = REPO_ROOT / "scripts" / "validate_execution_state.py"

MONITORED_REPORTS = [
    FRONTEND_SMOKE_REPORT,
    RUNTIME_BOUNDARY_REPORT,
    GATE_QUALITY_REPORT,
    BUILD_REPRO_REPORT,
    PORTABILITY_REPORT,
    DEFAULT_REPORT,
]


def repo_relative_paths(paths: list[Path]) -> list[str]:
    relative_paths: list[str] = []
    for path in paths:
        try:
            relative_paths.append(str(path.relative_to(REPO_ROOT)))
        except ValueError:
            continue
    return relative_paths


def current_dirty_paths(*, git: str, paths: list[Path], env: dict[str, str]) -> list[str]:
    relative_paths = repo_relative_paths(paths)
    if not relative_paths:
        return []
    result = run([git, "status", "--short", "--", *relative_paths], cwd=REPO_ROOT, env=env)
    dirty: list[str] = []
    for line in result["stdout"].splitlines():
        if line.strip():
            dirty.append(line[3:])
    return dirty


def current_dirty_diff(*, git: str, paths: list[Path], env: dict[str, str]) -> str:
    relative_paths = repo_relative_paths(paths)
    if not relative_paths:
        return ""
    return run([git, "diff", "--", *relative_paths], cwd=REPO_ROOT, env=env)["stdout"]


def check_glue_report(report: dict[str, Any]) -> None:
    require(
        not report["subprocess_import_violations"],
        f"subprocess imports remain in audited glue: {report['subprocess_import_violations']}",
    )
    require(
        not report["subprocess_call_violations"],
        f"subprocess calls remain in audited glue: {report['subprocess_call_violations']}",
    )
    require(
        not report["shell_assumption_violations"],
        f"shell usage remains in audited glue: {report['shell_assumption_violations']}",
    )
    require(
        not report["tempdir_violations"],
        f"non-deterministic temp usage remains in audited glue: {report['tempdir_violations']}",
    )
    require(
        not report["report_helper_violations"],
        f"report helper violations remain in audited glue: {report['report_helper_violations']}",
    )
    require(
        not report["command_lookup_violations"],
        f"command lookup violations remain in audited glue: {report['command_lookup_violations']}",
    )
    require(
        not report["unauthorized_safe_source_readers"],
        "unauthorized raw .safe readers remain in audited glue: "
        f"{report['unauthorized_safe_source_readers']}",
    )


def generate_report(*, python: str, env: dict[str, str]) -> dict[str, Any]:
    glue_report = glue_script_safety_report()
    check_glue_report(glue_report)
    check_glue_script_safety()
    require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    with tempfile.TemporaryDirectory(prefix="pr06911-glue-safety-") as temp_root_str:
        temp_root = Path(temp_root_str)
        runtime_boundary = rerun_report_gate_and_compare(
            python=python,
            script=RUNTIME_BOUNDARY_SCRIPT,
            committed_report_path=RUNTIME_BOUNDARY_REPORT,
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        gate_quality = rerun_report_gate_and_compare(
            python=python,
            script=GATE_QUALITY_SCRIPT,
            committed_report_path=GATE_QUALITY_REPORT,
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        portability_environment = rerun_report_gate_and_compare(
            python=python,
            script=PORTABILITY_SCRIPT,
            committed_report_path=PORTABILITY_REPORT,
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        frontend_smoke = rerun_report_gate_and_compare(
            python=python,
            script=FRONTEND_SMOKE_SCRIPT,
            committed_report_path=FRONTEND_SMOKE_REPORT,
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        build_reproducibility = rerun_report_gate_and_compare(
            python=python,
            script=BUILD_REPRO_SCRIPT,
            committed_report_path=BUILD_REPRO_REPORT,
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        execution_state = run([python, str(VALIDATE_EXECUTION_STATE)], cwd=REPO_ROOT, env=env)

    return {
        "task": "PR06.9.11",
        "status": "ok",
        "glue_script_safety": glue_report,
        "reruns": {
            "runtime_boundary": runtime_boundary,
            "gate_quality": gate_quality,
            "portability_environment": portability_environment,
            "validate_execution_state": {
                "command": execution_state["command"],
                "cwd": execution_state["cwd"],
                "returncode": execution_state["returncode"],
            },
        },
        "referenced_deterministic_reports": {
            "frontend_smoke": frontend_smoke,
            "build_reproducibility": build_reproducibility,
        },
        "monitored_reports": [display_path(path, repo_root=REPO_ROOT) for path in MONITORED_REPORTS],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    git = find_command("git")
    env = ensure_sdkroot(os.environ.copy())
    monitored_paths = [path if path != DEFAULT_REPORT else args.report for path in MONITORED_REPORTS]
    initial_dirty = current_dirty_paths(git=git, paths=monitored_paths, env=env)
    compare_paths = [path for path in monitored_paths if path != args.report]
    initial_diff = current_dirty_diff(git=git, paths=compare_paths, env=env)

    report = finalize_deterministic_report(
        lambda: generate_report(python=python, env=env),
        label="PR06.9.11 glue script safety",
    )
    write_report(args.report, report)

    final_dirty = current_dirty_paths(git=git, paths=monitored_paths, env=env)
    if initial_dirty:
        final_diff = current_dirty_diff(git=git, paths=compare_paths, env=env)
        allowed_dirty = set(initial_dirty)
        allowed_dirty.add(display_path(args.report, repo_root=REPO_ROOT))
        require(
            set(final_dirty) <= allowed_dirty,
            "PR06.9.11 monitored reports changed beyond the allowed local baseline: "
            f"before={initial_dirty}, after={final_dirty}",
        )
        require(
            final_diff == initial_diff,
            "PR06.9.11 monitored evidence diffs changed further from an already-dirty baseline",
        )
    else:
        run(
            [git, "diff", "--exit-code", "--", *repo_relative_paths(monitored_paths)],
            cwd=REPO_ROOT,
            env=env,
        )

    print(f"pr06911 glue script safety: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
