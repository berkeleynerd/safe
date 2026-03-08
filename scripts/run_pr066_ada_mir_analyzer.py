#!/usr/bin/env python3
"""Run the PR06.6 MIR analyzer parity and delegation gate."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


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


def normalize_text(text: str, *, temp_root: Path | None = None) -> str:
    result = text
    if temp_root is not None:
        result = result.replace(str(temp_root), "$TMPDIR")
    return result.replace(str(REPO_ROOT), "$REPO_ROOT")


def normalize_argv(argv: list[str], *, temp_root: Path | None = None) -> list[str]:
    normalized: list[str] = []
    for item in argv:
        candidate = Path(item)
        if candidate.is_absolute():
            if temp_root is not None and temp_root in candidate.parents:
                normalized.append("$TMPDIR/" + str(candidate.relative_to(temp_root)))
            elif REPO_ROOT in candidate.parents:
                normalized.append(str(candidate.relative_to(REPO_ROOT)))
            else:
                normalized.append(candidate.name)
        else:
            normalized.append(item)
    return normalized


def find_command(name: str, fallback: Path | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def run(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    temp_root: Path | None = None,
    expected_returncode: int = 0,
) -> dict[str, Any]:
    completed = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    result = {
        "command": normalize_argv(argv, temp_root=temp_root),
        "cwd": normalize_text(str(cwd), temp_root=temp_root),
        "returncode": completed.returncode,
        "stdout": normalize_text(completed.stdout, temp_root=temp_root),
        "stderr": normalize_text(completed.stderr, temp_root=temp_root),
    }
    if completed.returncode != expected_returncode:
        raise RuntimeError(json.dumps(result, indent=2))
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def tool_versions(python: str, alr: str) -> dict[str, str]:
    versions: dict[str, str] = {}
    versions["python3"] = subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stdout.strip() or subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stderr.strip()
    versions["alr"] = subprocess.run([alr, "--version"], text=True, capture_output=True, check=False).stdout.strip()
    gprbuild = shutil.which("gprbuild")
    if gprbuild:
        versions["gprbuild"] = subprocess.run([gprbuild, "--version"], text=True, capture_output=True, check=False).stdout.splitlines()[0]
    return versions


def read_diag_json(stdout: str, source: str) -> dict[str, Any]:
    payload = json.loads(stdout)
    require(payload.get("format") == "diagnostics-v0", f"{source}: unexpected diagnostics format")
    require(isinstance(payload.get("diagnostics"), list), f"{source}: diagnostics must be a list")
    return payload


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

    args.report.parent.mkdir(parents=True, exist_ok=True)

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    safec = COMPILER_ROOT / "bin" / "safec"
    require(safec.exists(), f"expected built compiler at {safec}")

    env = os.environ.copy()

    with tempfile.TemporaryDirectory(prefix="pr066-mir-") as temp_root_str:
        temp_root = Path(temp_root_str)
        report: dict[str, Any] = {
            "tool_versions": tool_versions(python, alr),
            "fixtures": run_fixture_checks(safec, env),
            "invalid_inputs": run_invalid_input_checks(safec, env),
            "emitted_samples": run_emitted_sample_checks(safec, env, temp_root),
            "harnesses": run_harness_checks(env, temp_root),
        }

    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"pr066 MIR analyzer gate: OK ({args.report})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr066 MIR analyzer gate: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
