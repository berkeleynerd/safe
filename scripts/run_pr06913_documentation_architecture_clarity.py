#!/usr/bin/env python3
"""Run the PR06.9.13 documentation and architecture clarity gate."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    reference_committed_report,
    require,
    run,
    write_report,
)
from validate_execution_state import (
    check_documentation_architecture_clarity,
    documentation_architecture_clarity_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr06913-documentation-architecture-clarity-report.json"
)

RUNTIME_BOUNDARY_SCRIPT = REPO_ROOT / "scripts" / "run_pr0693_runtime_boundary.py"
RUNTIME_BOUNDARY_REPORT = REPO_ROOT / "execution" / "reports" / "pr0693-runtime-boundary-report.json"
LEGACY_CLEANUP_SCRIPT = REPO_ROOT / "scripts" / "run_pr0698_legacy_package_cleanup.py"
LEGACY_CLEANUP_REPORT = REPO_ROOT / "execution" / "reports" / "pr0698-legacy-package-cleanup-report.json"
PORTABILITY_SCRIPT = REPO_ROOT / "scripts" / "run_pr06910_portability_environment.py"
PORTABILITY_REPORT = REPO_ROOT / "execution" / "reports" / "pr06910-portability-environment-report.json"
GATE_QUALITY_SCRIPT = REPO_ROOT / "scripts" / "run_pr0697_gate_quality.py"
GATE_QUALITY_REPORT = REPO_ROOT / "execution" / "reports" / "pr0697-gate-quality-report.json"
GLUE_SAFETY_SCRIPT = REPO_ROOT / "scripts" / "run_pr06911_glue_script_safety.py"
GLUE_SAFETY_REPORT = REPO_ROOT / "execution" / "reports" / "pr06911-glue-script-safety-report.json"
SCALE_SANITY_SCRIPT = REPO_ROOT / "scripts" / "run_pr06912_performance_scale_sanity.py"
SCALE_SANITY_REPORT = REPO_ROOT / "execution" / "reports" / "pr06912-performance-scale-sanity-report.json"
VALIDATE_EXECUTION_STATE = REPO_ROOT / "scripts" / "validate_execution_state.py"

MONITORED_PATHS = [
    REPO_ROOT / "README.md",
    REPO_ROOT / "compiler_impl" / "README.md",
    REPO_ROOT / "release" / "frontend_runtime_decision.md",
    REPO_ROOT / "docs" / "frontend_architecture_baseline.md",
    REPO_ROOT / "docs" / "frontend_scale_limits.md",
    REPO_ROOT / "execution" / "tracker.json",
    REPO_ROOT / "execution" / "dashboard.md",
    DEFAULT_REPORT,
]


def repo_relative_paths(paths: list[Path]) -> list[str]:
    return [str(path.relative_to(REPO_ROOT)) for path in paths if path.is_relative_to(REPO_ROOT)]


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


def build_report(
    *,
    clarity_report: dict[str, Any],
    validate_execution_state_run: dict[str, Any] | None,
    runtime_boundary: dict[str, Any],
    legacy_cleanup: dict[str, Any],
    portability_environment: dict[str, Any],
    gate_quality: dict[str, Any],
    glue_script_safety: dict[str, Any],
    performance_scale_sanity: dict[str, Any],
) -> dict[str, Any]:
    report = {
        "task": "PR06.9.13",
        "status": "ok",
        "documentation_architecture_clarity": clarity_report,
        "reruns": {
            "runtime_boundary": runtime_boundary,
            "legacy_package_cleanup": legacy_cleanup,
            "portability_environment": portability_environment,
            "gate_quality": gate_quality,
            "glue_script_safety": glue_script_safety,
            "performance_scale_sanity": performance_scale_sanity,
        },
        "monitored_paths": [display_path(path, repo_root=REPO_ROOT) for path in MONITORED_PATHS],
    }
    if validate_execution_state_run is not None:
        report["reruns"]["validate_execution_state"] = validate_execution_state_run
    return report


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

    clarity_report = documentation_architecture_clarity_report()
    check_documentation_architecture_clarity()

    runtime_boundary = reference_committed_report(
        script=RUNTIME_BOUNDARY_SCRIPT,
        committed_report_path=RUNTIME_BOUNDARY_REPORT,
    )
    legacy_cleanup = reference_committed_report(
        script=LEGACY_CLEANUP_SCRIPT,
        committed_report_path=LEGACY_CLEANUP_REPORT,
    )
    portability_environment = reference_committed_report(
        script=PORTABILITY_SCRIPT,
        committed_report_path=PORTABILITY_REPORT,
    )
    gate_quality = reference_committed_report(
        script=GATE_QUALITY_SCRIPT,
        committed_report_path=GATE_QUALITY_REPORT,
    )
    glue_script_safety = reference_committed_report(
        script=GLUE_SAFETY_SCRIPT,
        committed_report_path=GLUE_SAFETY_REPORT,
    )
    performance_scale_sanity = reference_committed_report(
        script=SCALE_SANITY_SCRIPT,
        committed_report_path=SCALE_SANITY_REPORT,
    )

    validate_execution_state_run = run([python, str(VALIDATE_EXECUTION_STATE)], cwd=REPO_ROOT, env=env)

    final_report = finalize_deterministic_report(
        lambda: build_report(
            clarity_report=clarity_report,
            validate_execution_state_run=validate_execution_state_run,
            runtime_boundary=runtime_boundary,
            legacy_cleanup=legacy_cleanup,
            portability_environment=portability_environment,
            gate_quality=gate_quality,
            glue_script_safety=glue_script_safety,
            performance_scale_sanity=performance_scale_sanity,
        ),
        label="PR06.9.13 documentation and architecture clarity",
    )
    write_report(args.report, final_report)

    final_dirty = current_dirty_paths(git=git, paths=monitored_paths, env=env)
    if initial_dirty:
        final_diff = current_dirty_diff(git=git, paths=compare_paths, env=env)
        allowed_dirty = set(initial_dirty)
        allowed_dirty.add(display_path(args.report, repo_root=REPO_ROOT))
        require(
            set(final_dirty) <= allowed_dirty,
            "PR06.9.13 monitored docs changed beyond the allowed local baseline: "
            f"before={initial_dirty}, after={final_dirty}",
        )
        require(
            final_diff == initial_diff,
            "PR06.9.13 monitored doc diffs changed further from an already-dirty baseline",
        )
    else:
        run(
            [git, "diff", "--exit-code", "--", *repo_relative_paths(monitored_paths)],
            cwd=REPO_ROOT,
            env=env,
        )

    print(
        "pr06913 documentation and architecture clarity: OK "
        f"({display_path(args.report, repo_root=REPO_ROOT)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
