#!/usr/bin/env python3
"""Run the PR06.9.7 regression coverage and gate quality checks."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    finalize_deterministic_report,
    find_command,
    require,
    run,
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
        "name": "invalid_safei_wrong_format",
        "expected_error": "sample.safei.json.format must be safei-v1",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_safei_null_channels",
        "expected_error": "sample.safei.json.channels must be a list",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_safei_malformed_params",
        "expected_error": "sample.safei.json.subprograms[0].params[0].type must be an object",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_safei_bad_effect_summaries",
        "expected_error": "sample.safei.json.effect_summaries[0].depends[0].inputs must be a list",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_safei_constant_kind_without_constant",
        "expected_error": "sample.safei.json.objects[0].static_value_kind requires is_constant to be true",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_safei_constant_kind_mismatch",
        "expected_error": "sample.safei.json.objects[0].static_value must be an integer",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_safei_missing_static_value_kind",
        "expected_error": "sample.safei.json.objects[0].static_value_kind is required when static_value is present",
        "source_path": "fixtures/sample.safe",
    },
    {
        "name": "invalid_mir_source_path_mismatch",
        "expected_error": "sample.mir.json.source_path must preserve the exact emit CLI path",
        "source_path": "fixtures/sample.safe",
    },
]

VALID_CONTRACT_CASES = [
    {
        "name": "valid_safei_v1_full",
        "source_path": "fixtures/sample.safe",
    }
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


def run_valid_contract_cases(python: str) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in VALID_CONTRACT_CASES:
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
        )
        results.append({"name": case["name"], "result": result})
    return results


def generate_report(*, python: str) -> dict[str, Any]:
    return {
        "task": "PR06.9.7",
        "status": "ok",
        "unit_tests": run_unittest_suite(python),
        "valid_output_contracts": run_valid_contract_cases(python),
        "negative_output_contracts": run_invalid_contract_cases(python),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    report = finalize_deterministic_report(
        lambda: generate_report(python=python),
        label="PR06.9.7 gate quality",
    )

    write_report(args.report, report)
    print(f"pr0697 gate quality: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
