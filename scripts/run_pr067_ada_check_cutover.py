#!/usr/bin/env python3
"""Run the PR06.7 Ada-native check cutover gate."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    extract_expected_block,
    finalize_deterministic_report,
    find_command,
    normalize_text,
    read_diag_json,
    require,
    require_repo_command,
    run,
    write_report,
)
from migrate_pr116_whitespace import rewrite_safe_source


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr067-ada-check-cutover-report.json"
LEGACY_TOKEN_FIXTURE = REPO_ROOT / "compiler_impl" / "tests" / "legacy_two_char_tokens.safe"

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
        "source": REPO_ROOT / "tests" / "positive" / "channel_pingpong.safe",
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

UNSUPPORTED_CASES: list[Path] = []

HARNESSES = [
    REPO_ROOT / "scripts" / "run_pr05_d27_harness.py",
    REPO_ROOT / "scripts" / "run_pr06_ownership_harness.py",
]
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
                'echo "blocked python3 spawn during PR06.7 harness rerun: $*" >> "$BLOCKED_LOG"',
                'echo "python3 masked for PR06.7 check cutover" >&2',
                "exit 97",
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
            "text": "package Legacy_Begin\n   begin\n      null;\n",
            "message": "legacy block delimiter `begin` is not allowed in package items; covered blocks are closed by indentation",
            "rewrite": False,
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
        source.write_text(
            rewrite_safe_source(case["text"]) if case.get("rewrite", True) else case["text"],
            encoding="utf-8",
        )

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


def run_legacy_token_check(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    fixture_arg = str(LEGACY_TOKEN_FIXTURE.relative_to(REPO_ROOT))
    expected_messages = [
        'legacy token ":=" is not allowed',
        'legacy token "=>" is not allowed',
        'legacy token "/=" is not allowed',
    ]
    diag_json = run(
        [str(safec), "check", "--diag-json", fixture_arg],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(diag_json["stdout"], str(LEGACY_TOKEN_FIXTURE))
    require(
        len(payload["diagnostics"]) == 3,
        f"{LEGACY_TOKEN_FIXTURE}: expected exactly three diagnostics",
    )
    actual_messages = [item["message"] for item in payload["diagnostics"]]
    require(
        actual_messages == expected_messages,
        f"{LEGACY_TOKEN_FIXTURE}: unexpected diagnostic messages {actual_messages}",
    )
    for item in payload["diagnostics"]:
        require(
            item["reason"] == "source_frontend_error",
            f"{LEGACY_TOKEN_FIXTURE}: expected source_frontend_error",
        )
        require(
            item["path"] == fixture_arg,
            f"{LEGACY_TOKEN_FIXTURE}: expected diagnostics path to preserve CLI path",
        )

    human = run(
        [str(safec), "check", fixture_arg],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    require(human["stdout"] == "", f"{LEGACY_TOKEN_FIXTURE}: expected empty stdout")
    require(
        "legacy_two_char_tokens.safe:2:19: error: legacy token \":=\" is not allowed" in human["stderr"],
        f"{LEGACY_TOKEN_FIXTURE}: expected first diagnostic header in stderr",
    )
    require(
        'legacy token "=>"' not in human["stderr"] and 'legacy token "/="' not in human["stderr"],
        f"{LEGACY_TOKEN_FIXTURE}: plain check should render only the first diagnostic",
    )

    return {
        "source": fixture_arg,
        "diag_json": diag_json,
        "diagnostics": payload,
        "human": human,
    }


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


def generate_report(*, safec: Path, python: str) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr067-check-") as temp_root_str:
        temp_root = Path(temp_root_str)
        direct_env, direct_stub_path, direct_blocked_log = make_masked_env(
            python, temp_root, mode="strict"
        )
        harness_env, harness_stub_path, harness_blocked_log = make_masked_env(
            python, temp_root, mode="harness"
        )
        report: dict[str, Any] = {
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
            "legacy_token_check": run_legacy_token_check(safec, direct_env, temp_root),
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
        return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    find_command("alr", Path.home() / "bin" / "alr")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    require(safec.exists(), f"expected built compiler at {safec}")

    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, python=python),
        label="PR06.7 Ada check cutover",
    )
    write_report(args.report, report)
    print(f"pr067 Ada check cutover: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr067 Ada check cutover: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
