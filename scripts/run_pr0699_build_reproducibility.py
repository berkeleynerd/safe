#!/usr/bin/env python3
"""Run the PR06.9.9 build and reproducibility hardening gate."""

from __future__ import annotations

import argparse
import json
import os
import shutil
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
    stable_binary_sha256,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr0699-build-reproducibility-report.json"

FRONTEND_SMOKE_SCRIPT = REPO_ROOT / "scripts" / "run_frontend_smoke.py"
FRONTEND_SMOKE_REPORT = REPO_ROOT / "execution" / "reports" / "pr00-pr04-frontend-smoke.json"
GATE_QUALITY_SCRIPT = REPO_ROOT / "scripts" / "run_pr0697_gate_quality.py"
GATE_QUALITY_REPORT = REPO_ROOT / "execution" / "reports" / "pr0697-gate-quality-report.json"
LEGACY_CLEANUP_SCRIPT = REPO_ROOT / "scripts" / "run_pr0698_legacy_package_cleanup.py"
LEGACY_CLEANUP_REPORT = REPO_ROOT / "execution" / "reports" / "pr0698-legacy-package-cleanup-report.json"
VALIDATE_EXECUTION_STATE = REPO_ROOT / "scripts" / "validate_execution_state.py"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_relative_report_args(paths: list[Path]) -> list[str]:
    relative_paths: list[str] = []
    for path in paths:
        try:
            relative_paths.append(str(path.relative_to(REPO_ROOT)))
        except ValueError:
            continue
    return relative_paths


def current_dirty_report_paths(*, paths: list[Path], env: dict[str, str]) -> list[str]:
    relative_paths = repo_relative_report_args(paths)
    if not relative_paths:
        return []
    git = find_command("git")
    result = run(
        [git, "status", "--short", "--", *relative_paths],
        cwd=REPO_ROOT,
        env=env,
    )
    dirty: list[str] = []
    for line in result["stdout"].splitlines():
        if not line.strip():
            continue
        dirty.append(line[3:])
    return dirty


def current_dirty_report_diff(*, paths: list[Path], env: dict[str, str]) -> str:
    relative_paths = repo_relative_report_args(paths)
    if not relative_paths:
        return ""
    git = find_command("git")
    result = run(
        [git, "diff", "--", *relative_paths],
        cwd=REPO_ROOT,
        env=env,
    )
    return result["stdout"]


def clean_frontend_build_outputs(safec: Path) -> None:
    shutil.rmtree(COMPILER_ROOT / "obj", ignore_errors=True)
    if safec.exists():
        safec.unlink()
    safec.parent.mkdir(parents=True, exist_ok=True)
    (COMPILER_ROOT / "alire" / "tmp").mkdir(parents=True, exist_ok=True)


def run_build_reproducibility(*, alr: str, safec: Path, env: dict[str, str]) -> dict[str, Any]:
    clean_frontend_build_outputs(safec)
    first_build = run([alr, "build"], cwd=COMPILER_ROOT, env=env)
    require(safec.exists(), f"expected built compiler at {safec}")
    first_binary_sha256 = stable_binary_sha256(safec)

    clean_frontend_build_outputs(safec)
    second_build = run([alr, "build"], cwd=COMPILER_ROOT, env=env)
    require(safec.exists(), f"expected built compiler at {safec}")
    second_binary_sha256 = stable_binary_sha256(safec)
    require(
        first_binary_sha256 == second_binary_sha256,
        "PR06.9.9 build reproducibility: normalized compiler payload changed between clean rebuilds",
    )

    return {
        "command": first_build["command"],
        "cwd": first_build["cwd"],
        "returncodes": [first_build["returncode"], second_build["returncode"]],
        "binary_path": display_path(safec, repo_root=REPO_ROOT),
        "binary_deterministic": True,
    }


def run_gate_script(
    *,
    python: str,
    script: Path,
    report_path: Path,
    env: dict[str, str],
) -> dict[str, Any]:
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


def generate_report(*, python: str, alr: str, safec: Path, env: dict[str, str]) -> dict[str, Any]:
    build_reproducibility = run_build_reproducibility(alr=alr, safec=safec, env=env)
    require_repo_command(safec, "safec")

    frontend_smoke = run_gate_script(
        python=python,
        script=FRONTEND_SMOKE_SCRIPT,
        report_path=FRONTEND_SMOKE_REPORT,
        env=env,
    )
    frontend_smoke_report = load_json(FRONTEND_SMOKE_REPORT)
    require(
        frontend_smoke_report["build"]["binary_deterministic"] is True,
        "frontend smoke report must record a deterministic binary",
    )

    gate_quality = run_gate_script(
        python=python,
        script=GATE_QUALITY_SCRIPT,
        report_path=GATE_QUALITY_REPORT,
        env=env,
    )
    legacy_cleanup = run_gate_script(
        python=python,
        script=LEGACY_CLEANUP_SCRIPT,
        report_path=LEGACY_CLEANUP_REPORT,
        env=env,
    )

    return {
        "task": "PR06.9.9",
        "status": "ok",
        "build_reproducibility": build_reproducibility,
        "delegated_reports": {
            "frontend_smoke": {
                **frontend_smoke,
                "binary_deterministic": frontend_smoke_report["build"]["binary_deterministic"],
            },
            "gate_quality": gate_quality,
            "legacy_package_cleanup": legacy_cleanup,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    env = ensure_sdkroot(os.environ.copy())
    safec = COMPILER_ROOT / "bin" / "safec"
    report_paths = [
        FRONTEND_SMOKE_REPORT,
        GATE_QUALITY_REPORT,
        LEGACY_CLEANUP_REPORT,
        args.report,
    ]
    initial_dirty = current_dirty_report_paths(paths=report_paths, env=env)
    compare_paths = [path for path in report_paths if path != args.report]
    initial_diff = current_dirty_report_diff(paths=compare_paths, env=env)

    report = finalize_deterministic_report(
        lambda: generate_report(python=python, alr=alr, safec=safec, env=env),
        label="PR06.9.9 build reproducibility",
    )
    write_report(args.report, report)

    run([python, str(VALIDATE_EXECUTION_STATE)], cwd=REPO_ROOT, env=env)
    final_dirty = current_dirty_report_paths(paths=report_paths, env=env)
    if initial_dirty:
        final_diff = current_dirty_report_diff(paths=compare_paths, env=env)
        allowed_dirty = set(initial_dirty)
        try:
            allowed_dirty.add(str(args.report.relative_to(REPO_ROOT)))
        except ValueError:
            pass
        require(
            set(final_dirty) <= allowed_dirty,
            "PR06.9.9 evidence files changed further from an already-dirty baseline: "
            f"before={initial_dirty}, after={final_dirty}",
        )
        require(
            final_diff == initial_diff,
            "PR06.9.9 evidence diffs changed further from an already-dirty baseline",
        )
    else:
        relative_paths = repo_relative_report_args(report_paths)
        git = find_command("git")
        run(
            [
                git,
                "diff",
                "--exit-code",
                "--",
                *relative_paths,
            ],
            cwd=REPO_ROOT,
            env=env,
        )
    print(f"pr0699 build reproducibility: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
