#!/usr/bin/env python3
"""Run the PR06.9.7 regression coverage and gate quality checks."""

from __future__ import annotations

import argparse
import os
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
REPORTS_ROOT_REL = Path("execution") / "reports"
OUTPUT_CONTRACT_FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "output_contracts"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"
EXPECTED_TEST_MODULES = (
    "scripts.tests.test_dual_mode_canonicalization",
    "scripts.tests.test_gate_manifest",
    "scripts.tests.test_harness_common",
    "scripts.tests.test_migrate_pr114_syntax",
    "scripts.tests.test_migrate_pr115_syntax",
    "scripts.tests.test_migrate_pr116_whitespace",
    "scripts.tests.test_pr06912_performance_scale_sanity",
    "scripts.tests.test_pr0694_output_contract_stability",
    "scripts.tests.test_pr0697_gate_quality",
    "scripts.tests.test_pr0699_build_reproducibility",
    "scripts.tests.test_pr09_emit",
    "scripts.tests.test_pr101_audit_hardening",
    "scripts.tests.test_pr101_verification",
    "scripts.tests.test_pr10_emit",
    "scripts.tests.test_pr111_language_eval",
    "scripts.tests.test_pr112_parser_completeness_phase1",
    "scripts.tests.test_pr113_discriminated_types_tuples_structured_returns",
    "scripts.tests.test_pr113a_proof_checkpoint1",
    "scripts.tests.test_pr114_signature_control_flow_syntax",
    "scripts.tests.test_pr115_statement_ergonomics",
    "scripts.tests.test_pr116_meaningful_whitespace",
    "scripts.tests.test_proof_report",
    "scripts.tests.test_render_execution_status",
    "scripts.tests.test_run_frontend_smoke",
    "scripts.tests.test_run_gate_pipeline",
    "scripts.tests.test_run_local_pre_push",
    "scripts.tests.test_validate_execution_state",
    "scripts.tests.test_validate_output_contracts",
)

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
    {
        "name": "invalid_mir_malformed_externals",
        "expected_error": "sample.mir.json.externals[0].effect_summary.reads must be a list",
        "source_path": "fixtures/sample.safe",
    },
]

VALID_CONTRACT_CASES = [
    {
        "name": "valid_safei_v1_full",
        "source_path": "fixtures/sample.safe",
    }
]

UNITTEST_SUCCESS_RE = re.compile(
    r"^(?P<dots>\.+)\n-+\nRan (?P<count>\d+) test(?:s)? in <elapsed>\n\nOK\n$"
)
UNITTEST_COUNT_RE = re.compile(r"Ran (?P<count>\d+) test(?:s)? in <elapsed>")


def canonical_unittest_success_output(*, count: int) -> str:
    test_word = "test" if count == 1 else "tests"
    return (
        "." * count
        + "\n----------------------------------------------------------------------\n"
        + f"Ran {count} {test_word} in <elapsed>\n\nOK\n"
    )


def normalize_unittest_output(text: str) -> str:
    normalized = re.sub(
        r"Ran (\d+) test(?:s)? in [0-9.]+s",
        lambda match: (
            f"Ran {match.group(1)} {'test' if match.group(1) == '1' else 'tests'} in <elapsed>"
        ),
        text,
    )
    match = UNITTEST_SUCCESS_RE.fullmatch(normalized)
    if match is not None:
        return canonical_unittest_success_output(count=int(match.group("count")))
    return normalized


def extract_observed_test_count(*, stdout: str, stderr: str) -> int:
    for text in (stderr, stdout):
        match = UNITTEST_COUNT_RE.search(text)
        if match is not None:
            return int(match.group("count"))
    stderr_excerpt = stderr[:200]
    stdout_excerpt = stdout[:200]
    raise RuntimeError(
        "unable to determine observed unittest count: "
        f"no match for pattern {UNITTEST_COUNT_RE.pattern!r} found in stderr or stdout. "
        f"stderr length={len(stderr)}, stdout length={len(stdout)}. "
        f"stderr excerpt={stderr_excerpt!r}, stdout excerpt={stdout_excerpt!r}"
    )


def infer_generated_root(*, report_path: Path) -> Path | None:
    if not report_path.is_absolute():
        return None
    try:
        report_path.relative_to(REPO_ROOT)
        return None
    except ValueError:
        pass
    report_rel = DEFAULT_REPORT.relative_to(REPO_ROOT)
    if report_path.parts[-len(report_rel.parts):] != report_rel.parts:
        return None
    return report_path.parents[len(REPORTS_ROOT_REL.parts)]


def run_unittest_suite(python: str, *, generated_root: Path | None = None) -> dict[str, Any]:
    env = None
    if generated_root is not None:
        env = os.environ.copy()
        env["SAFE_GENERATED_ROOT"] = str(generated_root)
    result = run(
        [python, "-m", "unittest", *EXPECTED_TEST_MODULES],
        cwd=REPO_ROOT,
        env=env,
    )
    normalized_stdout = normalize_unittest_output(result["stdout"])
    normalized_stderr = normalize_unittest_output(result["stderr"])
    return {
        **result,
        "stdout": normalized_stdout,
        "stderr": normalized_stderr,
        "modules": list(EXPECTED_TEST_MODULES),
        "observed_count": extract_observed_test_count(
            stdout=normalized_stdout,
            stderr=normalized_stderr,
        ),
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


def generate_report(*, python: str, generated_root: Path | None) -> dict[str, Any]:
    return {
        "task": "PR06.9.7",
        "status": "ok",
        "unit_tests": run_unittest_suite(python, generated_root=generated_root),
        "valid_output_contracts": run_valid_contract_cases(python),
        "negative_output_contracts": run_invalid_contract_cases(python),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    generated_root = infer_generated_root(report_path=args.report)
    report = finalize_deterministic_report(
        lambda: generate_report(python=python, generated_root=generated_root),
        label="PR06.9.7 gate quality",
    )

    write_report(args.report, report)
    print(f"pr0697 gate quality: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
