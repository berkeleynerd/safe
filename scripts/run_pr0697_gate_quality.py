#!/usr/bin/env python3
"""Run the PR06.9.7 regression coverage and gate quality checks."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    find_command,
    require,
    run,
    serialize_report,
    sha256_text,
    tool_versions,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr0697-gate-quality-report.json"
OUTPUT_CONTRACT_FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "output_contracts"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"

INVALID_CONTRACT_CASES = [
    {
        "name": "invalid_typed_missing_package_end_name",
        "expected_error": "sample.typed.json.package_end_name is required",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_safei_missing_public_declarations",
        "expected_error": "sample.safei.json.public_declarations is required",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_mir_source_path_mismatch",
        "expected_error": "sample.mir.json.source_path must preserve the exact emit CLI path",
        "source_path": "fixtures/sample.safe",
    },
]


def normalize_unittest_output(text: str) -> str:
    return re.sub(r"Ran (\d+) tests in [0-9.]+s", r"Ran \1 tests in <elapsed>", text)


def run_unittest_suite(python: str) -> dict[str, Any]:
    result = run(
        [python, "-m", "unittest", "discover", "-s", "scripts/tests", "-p", "test_*.py"],
        cwd=REPO_ROOT,
    )
    return {
        **result,
        "stdout": normalize_unittest_output(result["stdout"]),
        "stderr": normalize_unittest_output(result["stderr"]),
    }


def run_invalid_contract_cases(python: str) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in INVALID_CONTRACT_CASES:
        fixture_dir = OUTPUT_CONTRACT_FIXTURES / case["name"]
        result = run(
            [
                python,
                str(OUTPUT_VALIDATOR),
                "--ast",
                str(fixture_dir / "sample.ast.json"),
                "--typed",
                str(fixture_dir / "sample.typed.json"),
                "--mir",
                str(fixture_dir / "sample.mir.json"),
                "--safei",
                str(fixture_dir / "sample.safei.json"),
                "--source-path",
                case["source_path"],
            ],
            cwd=REPO_ROOT,
            expected_returncode=1,
        )
        require(
            case["expected_error"] in result["stderr"],
            f"{case['name']}: expected stderr to contain {case['expected_error']!r}",
        )
        results.append(
            {
                "name": case["name"],
                "expected_error": case["expected_error"],
                "result": result,
            }
        )
    return results


def generate_report(*, python: str, alr: str | None) -> dict[str, Any]:
    return {
        "task": "PR06.9.7",
        "status": "ok",
        "tool_versions": tool_versions(python=python, alr=alr),
        "unit_tests": run_unittest_suite(python),
        "negative_output_contracts": run_invalid_contract_cases(python),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    try:
        alr = find_command("alr", Path.home() / "bin" / "alr")
    except FileNotFoundError:
        alr = None

    report = generate_report(python=python, alr=alr)
    repeat_report = generate_report(python=python, alr=alr)

    serialized = serialize_report(report)
    repeat_serialized = serialize_report(repeat_report)
    report_sha256 = sha256_text(serialized)
    repeat_sha256 = sha256_text(repeat_serialized)
    require(serialized == repeat_serialized, "PR06.9.7 report generation is non-deterministic")

    report["deterministic"] = True
    report["report_sha256"] = report_sha256
    report["repeat_sha256"] = repeat_sha256

    write_report(args.report, report)
    print(f"pr0697 gate quality: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
