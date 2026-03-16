#!/usr/bin/env python3
"""Run the PR06.9.10 portability and environment assumptions gate."""

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
from validate_execution_state import environment_assumptions_report


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr06910-portability-environment-report.json"
)

RUNTIME_BOUNDARY_SCRIPT = REPO_ROOT / "scripts" / "run_pr0693_runtime_boundary.py"
RUNTIME_BOUNDARY_REPORT = REPO_ROOT / "execution" / "reports" / "pr0693-runtime-boundary-report.json"
NO_PYTHON_SCRIPT = REPO_ROOT / "scripts" / "run_pr068_ada_ast_emit_no_python.py"
NO_PYTHON_REPORT = REPO_ROOT / "execution" / "reports" / "pr068-ada-ast-emit-no-python-report.json"
VALIDATE_EXECUTION_STATE = REPO_ROOT / "scripts" / "validate_execution_state.py"
MONITORED_PATHS = [
    REPO_ROOT / "compiler_impl" / "README.md",
    REPO_ROOT / "release" / "frontend_runtime_decision.md",
    REPO_ROOT / "docs" / "macos_alire_toolchain_repair.md",
    RUNTIME_BOUNDARY_REPORT,
    NO_PYTHON_REPORT,
    REPO_ROOT / "execution" / "reports" / "pr06910-portability-environment-report.json",
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
    result = run([git, "status", "--short", "--", *relative_paths], cwd=REPO_ROOT, env=env)
    dirty: list[str] = []
    for line in result["stdout"].splitlines():
        if not line.strip():
            continue
        dirty.append(line[3:])
    return dirty


def current_dirty_diff(*, git: str, paths: list[Path], env: dict[str, str]) -> str:
    relative_paths = repo_relative_paths(paths)
    return run([git, "diff", "--", *relative_paths], cwd=REPO_ROOT, env=env)["stdout"]


def check_environment_report(report: dict[str, Any]) -> None:
    require(not report["missing_doc_files"], f"missing portability docs: {report['missing_doc_files']}")
    require(
        not report["doc_policy_violations"],
        f"missing portability policy markers: {report['doc_policy_violations']}",
    )
    require(
        not report["runtime_source_violations"],
        f"runtime sources still reference Python invocation patterns: {report['runtime_source_violations']}",
    )
    require(
        not report["portability_module_violations"],
        "portability-sensitive scripts are not sourced from shared assumptions: "
        f"{report['portability_module_violations']}",
    )
    require(
        not report["tempdir_convention_violations"],
        "portability-sensitive scripts must use deterministic TemporaryDirectory prefixes: "
        f"{report['tempdir_convention_violations']}",
    )
    require(
        not report["path_lookup_violations"],
        "portability-sensitive scripts must use PATH-based command discovery: "
        f"{report['path_lookup_violations']}",
    )
    require(
        not report["shell_assumption_violations"],
        "portability-sensitive scripts must remain shell-free: "
        f"{report['shell_assumption_violations']}",
    )


def generate_report(*, python: str, env: dict[str, str]) -> dict[str, Any]:
    environment_report = environment_assumptions_report()
    check_environment_report(environment_report)
    require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    with tempfile.TemporaryDirectory(prefix="pr06910-portability-") as temp_root_str:
        temp_root = Path(temp_root_str)
        runtime_boundary = rerun_report_gate_and_compare(
            python=python,
            script=RUNTIME_BOUNDARY_SCRIPT,
            committed_report_path=RUNTIME_BOUNDARY_REPORT,
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        no_python = rerun_report_gate_and_compare(
            python=python,
            script=NO_PYTHON_SCRIPT,
            committed_report_path=NO_PYTHON_REPORT,
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        execution_state = run([python, str(VALIDATE_EXECUTION_STATE)], cwd=REPO_ROOT, env=env)

    return {
        "task": "PR06.9.10",
        "status": "ok",
        "environment_assumptions": environment_report,
        "reruns": {
            "runtime_boundary": runtime_boundary,
            "ast_emit_no_python": no_python,
            "validate_execution_state": {
                "command": execution_state["command"],
                "cwd": execution_state["cwd"],
                "returncode": execution_state["returncode"],
            },
        },
        "monitored_paths": [display_path(path, repo_root=REPO_ROOT) for path in MONITORED_PATHS],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    git = find_command("git")
    env = ensure_sdkroot(os.environ.copy())
    monitored_paths = [path if path != DEFAULT_REPORT else args.report for path in MONITORED_PATHS]
    initial_dirty = current_dirty_paths(git=git, paths=monitored_paths, env=env)
    compare_paths = [path for path in monitored_paths if path != args.report]
    initial_diff = current_dirty_diff(git=git, paths=compare_paths, env=env)

    report = finalize_deterministic_report(
        lambda: generate_report(python=python, env=env),
        label="PR06.9.10 portability and environment assumptions",
    )
    write_report(args.report, report)

    final_dirty = current_dirty_paths(git=git, paths=monitored_paths, env=env)
    if initial_dirty:
        final_diff = current_dirty_diff(git=git, paths=compare_paths, env=env)
        allowed_dirty = set(initial_dirty)
        allowed_dirty.add(display_path(args.report, repo_root=REPO_ROOT))
        require(
            set(final_dirty) <= allowed_dirty,
            "PR06.9.10 monitored paths changed beyond the allowed local baseline: "
            f"before={initial_dirty}, after={final_dirty}",
        )
        require(
            final_diff == initial_diff,
            "PR06.9.10 monitored diffs changed further from an already-dirty baseline",
        )
    else:
        run([git, "diff", "--exit-code", "--", *repo_relative_paths(monitored_paths)], cwd=REPO_ROOT, env=env)

    print(f"pr06910 portability environment: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
