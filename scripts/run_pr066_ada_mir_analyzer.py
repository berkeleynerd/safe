#!/usr/bin/env python3
"""Run the PR06.6 MIR analyzer parity and delegation gate."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    find_command,
    read_diag_json,
    require,
    run,
    tool_versions,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr066-ada-mir-analyzer-report.json"

FIXTURES = [
    {
        "path": COMPILER_ROOT / "tests" / "mir_validation" / "valid_mir_v2.json",
        "expected_returncode": 0,
        "expected_reason": None,
    },
    {
        "path": COMPILER_ROOT / "tests" / "mir_analysis" / "pr05_division_by_zero.json",
        "expected_returncode": 1,
        "expected_reason": "division_by_zero",
    },
    {
        "path": COMPILER_ROOT / "tests" / "mir_analysis" / "pr06_double_move.json",
        "expected_returncode": 1,
        "expected_reason": "double_move",
    },
]

INVALID_INPUTS = [
    {
        "path": COMPILER_ROOT / "tests" / "mir_validation" / "invalid_scope_id.json",
        "stderr_substring": "unknown scope_id",
    },
    {
        "path": COMPILER_ROOT / "tests" / "mir_validation" / "valid_mir_v1.json",
        "stderr_substring": "analyze-mir requires mir-v2 input",
    },
]

EMITTED_SAMPLES = [
    REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
    REPO_ROOT / "tests" / "positive" / "ownership_borrow.safe",
]

HARNESSES = [
    REPO_ROOT / "scripts" / "run_pr05_d27_harness.py",
    REPO_ROOT / "scripts" / "run_pr06_ownership_harness.py",
]
def run_fixture_checks(safec: Path, env: dict[str, str]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for fixture in FIXTURES:
        result = run(
            [str(safec), "analyze-mir", "--diag-json", str(fixture["path"])],
            cwd=REPO_ROOT,
            env=env,
            expected_returncode=fixture["expected_returncode"],
        )
        payload = read_diag_json(result["stdout"], str(fixture["path"]))
        expected_reason = fixture["expected_reason"]
        if expected_reason is None:
            require(payload["diagnostics"] == [], f"{fixture['path']}: expected no diagnostics")
        else:
            require(payload["diagnostics"], f"{fixture['path']}: expected at least one diagnostic")
            actual_reason = payload["diagnostics"][0]["reason"]
            require(actual_reason == expected_reason, f"{fixture['path']}: expected {expected_reason}, got {actual_reason}")
        results.append(
            {
                "fixture": str(fixture["path"].relative_to(REPO_ROOT)),
                "expected_reason": expected_reason,
                "result": result,
                "diagnostics": payload,
            }
        )
    return results


def run_invalid_input_checks(safec: Path, env: dict[str, str]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for fixture in INVALID_INPUTS:
        result = run(
            [str(safec), "analyze-mir", str(fixture["path"])],
            cwd=REPO_ROOT,
            env=env,
            expected_returncode=1,
        )
        require(
            fixture["stderr_substring"] in result["stderr"],
            f"{fixture['path']}: missing expected stderr text {fixture['stderr_substring']!r}",
        )
        results.append(
            {
                "fixture": str(fixture["path"].relative_to(REPO_ROOT)),
                "stderr_substring": fixture["stderr_substring"],
                "result": result,
            }
        )
    return results


def run_emitted_sample_checks(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for sample in EMITTED_SAMPLES:
        root = temp_root / sample.stem
        emit = run(
            [
                str(safec),
                "emit",
                str(sample),
                "--out-dir",
                str(root / "out"),
                "--interface-dir",
                str(root / "iface"),
            ],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        mir_path = root / "out" / f"{sample.stem.lower()}.mir.json"
        analyze = run(
            [str(safec), "analyze-mir", "--diag-json", str(mir_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        payload = read_diag_json(analyze["stdout"], str(sample))
        require(payload["diagnostics"] == [], f"{sample}: expected no diagnostics after emit")
        results.append(
            {
                "source": str(sample.relative_to(REPO_ROOT)),
                "emit": emit,
                "analyze": analyze,
                "diagnostics": payload,
            }
        )
    return results


def run_harness_checks(env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for harness in HARNESSES:
        result = run(
            ["python3", str(harness)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        results.append(
            {
                "harness": str(harness.relative_to(REPO_ROOT)),
                "result": result,
            }
        )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    safec = COMPILER_ROOT / "bin" / "safec"
    require(safec.exists(), f"expected built compiler at {safec}")

    env = os.environ.copy()

    with tempfile.TemporaryDirectory(prefix="pr066-mir-") as temp_root_str:
        temp_root = Path(temp_root_str)
        report: dict[str, Any] = {
            "tool_versions": tool_versions(python=python, alr=alr),
            "fixtures": run_fixture_checks(safec, env),
            "invalid_inputs": run_invalid_input_checks(safec, env),
            "emitted_samples": run_emitted_sample_checks(safec, env, temp_root),
            "harnesses": run_harness_checks(env, temp_root),
        }

    write_report(args.report, report)
    print(f"pr066 MIR analyzer gate: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr066 MIR analyzer gate: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
