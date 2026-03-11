#!/usr/bin/env python3
"""Run the PR06.9.11 glue-script safety gate."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    require,
    require_repo_command,
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


def load_json(path: Path) -> dict[str, Any]:
    import json

    return json.loads(path.read_text(encoding="utf-8"))


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


def summarize_unittest_run(result: dict[str, Any]) -> dict[str, Any]:
    match = re.search(r"Ran (\d+) tests? in [0-9.]+s", result["stderr"])
    require(match is not None, "PR06.9.11 unittest run: missing test summary")
    return {
        "command": result["command"],
        "cwd": result["cwd"],
        "returncode": result["returncode"],
        "tests_ran": int(match.group(1)),
        "result": "OK" if result["stderr"].rstrip().endswith("OK") else "UNKNOWN",
    }


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


def run_gate_script(*, python: str, script: Path, report_path: Path, env: dict[str, str]) -> dict[str, Any]:
    result = run([python, str(script)], cwd=REPO_ROOT, env=env)
    require(report_path.exists(), f"expected report at {report_path}")
    report = load_json(report_path)
    require(report.get("deterministic") is True, f"{report_path.name}: expected deterministic report")
    require(
        report.get("report_sha256") == report.get("repeat_sha256"),
        f"{report_path.name}: deterministic hashes must match",
    )
    return {
        "run": result,
        "report_path": display_path(report_path, repo_root=REPO_ROOT),
        "report_sha256": report["report_sha256"],
        "repeat_sha256": report["repeat_sha256"],
    }


def generate_report(*, python: str, env: dict[str, str]) -> dict[str, Any]:
    glue_report = glue_script_safety_report()
    check_glue_report(glue_report)
    check_glue_script_safety()

    unit_tests_run = run(
        [python, "-m", "unittest", "discover", "-s", "scripts/tests", "-p", "test_*.py"],
        cwd=REPO_ROOT,
        env=env,
    )
    unit_tests = summarize_unittest_run(unit_tests_run)

    frontend_smoke = run_gate_script(
        python=python,
        script=FRONTEND_SMOKE_SCRIPT,
        report_path=FRONTEND_SMOKE_REPORT,
        env=env,
    )
    require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    runtime_boundary = run_gate_script(
        python=python,
        script=RUNTIME_BOUNDARY_SCRIPT,
        report_path=RUNTIME_BOUNDARY_REPORT,
        env=env,
    )
    gate_quality = run_gate_script(
        python=python,
        script=GATE_QUALITY_SCRIPT,
        report_path=GATE_QUALITY_REPORT,
        env=env,
    )
    build_reproducibility = run_gate_script(
        python=python,
        script=BUILD_REPRO_SCRIPT,
        report_path=BUILD_REPRO_REPORT,
        env=env,
    )
    portability_environment = run_gate_script(
        python=python,
        script=PORTABILITY_SCRIPT,
        report_path=PORTABILITY_REPORT,
        env=env,
    )
    execution_state = run([python, str(VALIDATE_EXECUTION_STATE)], cwd=REPO_ROOT, env=env)

    return {
        "task": "PR06.9.11",
        "status": "ok",
        "glue_script_safety": glue_report,
        "unit_tests": unit_tests,
        "reruns": {
            "frontend_smoke": frontend_smoke,
            "runtime_boundary": runtime_boundary,
            "gate_quality": gate_quality,
            "build_reproducibility": build_reproducibility,
            "portability_environment": portability_environment,
            "validate_execution_state": execution_state,
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
