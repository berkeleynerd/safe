#!/usr/bin/env python3
"""Run the PR06.7 Ada-native check cutover gate."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr067-ada-check-cutover-report.json"

DIRECT_CASES = [
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule1_accumulate.safe",
        "expected_returncode": 0,
        "expected_reason": None,
        "golden": None,
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "ownership_move.safe",
        "expected_returncode": 0,
        "expected_reason": None,
        "golden": None,
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe",
        "expected_returncode": 1,
        "expected_reason": "intermediate_overflow",
        "golden": REPO_ROOT / "tests" / "diagnostics_golden" / "diag_overflow.txt",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_own_double_move.safe",
        "expected_returncode": 1,
        "expected_reason": "double_move",
        "golden": REPO_ROOT / "tests" / "diagnostics_golden" / "diag_double_move.txt",
    },
]

UNSUPPORTED_CASES = [
    REPO_ROOT / "tests" / "positive" / "rule5_normalize.safe",
    REPO_ROOT / "tests" / "positive" / "result_guarded_access.safe",
    REPO_ROOT / "tests" / "positive" / "channel_pingpong.safe",
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
    versions["python3"] = (
        subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stdout.strip()
        or subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stderr.strip()
    )
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


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"Expected diagnostic output:\n-+\n(.*)\n-+\n", text, flags=re.DOTALL)
    require(match is not None, f"could not extract expected block from {path}")
    return match.group(1).rstrip() + "\n"


def make_masked_env(real_python: str, temp_root: Path, *, mode: str) -> tuple[dict[str, str], Path, Path]:
    require(mode in {"strict", "harness"}, f"unsupported mask mode: {mode}")
    stub_dir = temp_root / f"python-mask-{mode}"
    stub_dir.mkdir(parents=True, exist_ok=True)
    blocked_log = temp_root / f"blocked-{mode}-python.log"
    stub_path = stub_dir / "python3"
    script_lines = [
        "#!/bin/sh",
        'REAL_PYTHON="$PR067_REAL_PYTHON3"',
        'BLOCKED_LOG="$PR067_BLOCKED_LOG"',
        'case "$1" in',
        '  --version|"")',
        '    exec "$REAL_PYTHON" "$@"',
        "    ;;",
        "esac",
    ]
    if mode == "strict":
        script_lines.extend(
            [
                'echo "blocked python3 spawn during direct safec check: $*" >> "$BLOCKED_LOG"',
                'echo "python3 masked for PR06.7 direct safec check" >&2',
                "exit 97",
            ]
        )
    else:
        script_lines.extend(
            [
                'case "$1" in',
                '  *pr05_backend.py)',
                '    if [ "$2" = "check" ]; then',
                '      echo "blocked python3 backend spawn for safec check: $*" >> "$BLOCKED_LOG"',
                '      echo "python3 masked for PR06.7 check cutover" >&2',
                "      exit 97",
                "    fi",
                "    ;;",
                "esac",
                'exec "$REAL_PYTHON" "$@"',
            ]
        )
    script_lines.append("")
    stub_path.write_text("\n".join(script_lines), encoding="utf-8")
    stub_path.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = str(stub_dir) + os.pathsep + env.get("PATH", "")
    env["PR067_REAL_PYTHON3"] = real_python
    env["PR067_BLOCKED_LOG"] = str(blocked_log)
    return env, stub_path, blocked_log


def run_source_frontend_checks(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    cases = [
        {
            "name": "package_end_mismatch.safe",
            "text": "package Package_End_Mismatch is\nend Different_Name;\n",
            "message": "package end name must match declared package name",
        },
        {
            "name": "oversized_integer_literal.safe",
            "text": (
                "package Oversized_Integer_Literal is\n"
                "   Value : Integer = 999999999999999999999999999999999999999;\n"
                "end Oversized_Integer_Literal;\n"
            ),
            "message": "integer literal is out of range",
        },
    ]
    results: list[dict[str, Any]] = []

    for case in cases:
        source = temp_root / case["name"]
        source.write_text(case["text"], encoding="utf-8")

        diag_json = run(
            [str(safec), "check", "--diag-json", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        payload = read_diag_json(diag_json["stdout"], str(source))
        require(payload["diagnostics"], f"{source}: expected at least one diagnostic")
        require(
            payload["diagnostics"][0]["reason"] == "source_frontend_error",
            f"{source}: expected source_frontend_error",
        )
        require(
            payload["diagnostics"][0]["path"] == normalize_text(str(source), temp_root=temp_root),
            f"{source}: expected diagnostics path to preserve CLI path",
        )

        human = run(
            [str(safec), "check", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        require(source.name in human["stderr"], f"{source}: expected basename in stderr")
        require(
            case["message"] in human["stderr"],
            f"{source}: expected {case['message']!r} in stderr",
        )

        results.append(
            {
                "source": f"$TMPDIR/{case['name']}",
                "diag_json": diag_json,
                "diagnostics": payload,
                "human": human,
            }
        )

    return results


def run_direct_checks(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in DIRECT_CASES:
        source = case["source"]
        diag_json = run(
            [str(safec), "check", "--diag-json", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=case["expected_returncode"],
        )
        payload = read_diag_json(diag_json["stdout"], str(source))
        if case["expected_reason"] is None:
            require(payload["diagnostics"] == [], f"{source}: expected no diagnostics")
        else:
            require(payload["diagnostics"], f"{source}: expected at least one diagnostic")
            actual_reason = payload["diagnostics"][0]["reason"]
            require(
                actual_reason == case["expected_reason"],
                f"{source}: expected {case['expected_reason']}, got {actual_reason}",
            )

        human = run(
            [str(safec), "check", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=case["expected_returncode"],
        )
        if case["golden"] is None:
            require(human["stdout"] == "", f"{source}: expected empty stdout")
            require(human["stderr"] == "", f"{source}: expected empty stderr")
        else:
            expected = normalize_text(extract_expected_block(case["golden"]), temp_root=temp_root)
            require(human["stderr"] == expected, f"{source}: golden mismatch")

        results.append(
            {
                "source": str(source.relative_to(REPO_ROOT)),
                "expected_reason": case["expected_reason"],
                "diag_json": diag_json,
                "diagnostics": payload,
                "human": human,
                "golden": None if case["golden"] is None else str(case["golden"].relative_to(REPO_ROOT)),
            }
        )
    return results


def run_unsupported_checks(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for source in UNSUPPORTED_CASES:
        diag_json = run(
            [str(safec), "check", "--diag-json", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        payload = read_diag_json(diag_json["stdout"], str(source))
        require(payload["diagnostics"], f"{source}: expected at least one diagnostic")
        require(
            payload["diagnostics"][0]["reason"] == "unsupported_source_construct",
            f"{source}: expected unsupported_source_construct",
        )
        human = run(
            [str(safec), "check", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        require(source.name in human["stderr"], f"{source}: expected basename in stderr")
        results.append(
            {
                "source": str(source.relative_to(REPO_ROOT)),
                "diag_json": diag_json,
                "diagnostics": payload,
                "human": human,
            }
        )
    return results


def run_masked_harnesses(env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for harness in HARNESSES:
        report_path = temp_root / f"{harness.stem}.json"
        result = run(
            [sys.executable, str(harness), "--report", str(report_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        require(report_path.exists(), f"{harness}: expected report at {report_path}")
        results.append(
            {
                "harness": str(harness.relative_to(REPO_ROOT)),
                "report_path": normalize_text(str(report_path), temp_root=temp_root),
                "result": result,
            }
        )
    return results


def read_blocked_log(blocked_log: Path, temp_root: Path) -> list[str]:
    if not blocked_log.exists():
        return []
    return [
        normalize_text(line.rstrip(), temp_root=temp_root)
        for line in blocked_log.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    args.report.parent.mkdir(parents=True, exist_ok=True)

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    safec = COMPILER_ROOT / "bin" / "safec"
    require(safec.exists(), f"expected built compiler at {safec}")

    with tempfile.TemporaryDirectory(prefix="pr067-check-") as temp_root_str:
        temp_root = Path(temp_root_str)
        direct_env, direct_stub_path, direct_blocked_log = make_masked_env(
            python, temp_root, mode="strict"
        )
        harness_env, harness_stub_path, harness_blocked_log = make_masked_env(
            python, temp_root, mode="harness"
        )
        report: dict[str, Any] = {
            "tool_versions": tool_versions(python, alr),
            "python_mask": {
                "direct_stub_path": normalize_text(str(direct_stub_path), temp_root=temp_root),
                "direct_blocked_log_path": normalize_text(
                    str(direct_blocked_log), temp_root=temp_root
                ),
                "harness_stub_path": normalize_text(str(harness_stub_path), temp_root=temp_root),
                "harness_blocked_log_path": normalize_text(
                    str(harness_blocked_log), temp_root=temp_root
                ),
            },
            "direct_checks": run_direct_checks(safec, direct_env, temp_root),
            "unsupported_subset_rejections": run_unsupported_checks(safec, direct_env, temp_root),
            "source_frontend_rejections": run_source_frontend_checks(safec, direct_env, temp_root),
            "masked_harnesses": run_masked_harnesses(harness_env, temp_root),
        }
        direct_blocked_attempts = read_blocked_log(direct_blocked_log, temp_root)
        harness_blocked_attempts = read_blocked_log(harness_blocked_log, temp_root)
        require(
            not direct_blocked_attempts,
            f"unexpected python spawns during direct check: {direct_blocked_attempts}",
        )
        require(
            not harness_blocked_attempts,
            f"unexpected backend python spawns for check: {harness_blocked_attempts}",
        )
        report["python_mask"]["direct_blocked_attempts"] = direct_blocked_attempts
        report["python_mask"]["harness_blocked_attempts"] = harness_blocked_attempts

    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"pr067 Ada check cutover: OK ({args.report})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr067 Ada check cutover: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
