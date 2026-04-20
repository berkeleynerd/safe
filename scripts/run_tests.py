#!/usr/bin/env python3
"""Run the minimal Safe test workflow."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from _lib import (
    test_ceiling_priority,
    test_cli_workflows,
    test_contracts,
    test_embedded_listing,
    test_emitted_shape,
    test_fixtures,
    test_interfaces,
    test_proof_cli,
    test_proof_diagnostics,
)
from _lib.test_harness import (
    Failure,
    RunCounts,
    build_compiler,
    print_summary,
    should_skip_ceiling_tests,
)


def main() -> int:
    try:
        skip_ceiling_tests, ceiling_skip_reason = should_skip_ceiling_tests()
    except ValueError as exc:
        print(f"run_tests: ERROR: {exc}", file=sys.stderr)
        return 1

    try:
        safec = build_compiler()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_tests: ERROR: {exc}", file=sys.stderr)
        return 1

    if skip_ceiling_tests:
        ceiling_fixture_count = len(test_ceiling_priority.CEILING_PRIORITY_FIXTURES)
        ceiling_case_count = (
            test_cli_workflows.ceiling_priority_run_test_case_count()
            + test_interfaces.ceiling_priority_interface_case_count()
        )
        print(
            "Skipping ceiling-priority checks — "
            f"{ceiling_skip_reason}. {ceiling_fixture_count} fixture files listed; "
            f"{ceiling_case_count} ceiling-priority test cases will be skipped. "
            "Set SAFE_SKIP_CEILING_TESTS=never to force run."
        )

    passed = 0
    skipped = 0
    failures: list[Failure] = []

    def add_counts(counts: RunCounts) -> None:
        nonlocal passed, skipped
        section_passed, section_skipped, section_failures = counts
        passed += section_passed
        skipped += section_skipped
        failures.extend(section_failures)

    add_counts(test_fixtures.run_basic_fixture_checks(safec))
    add_counts(test_proof_cli.run_internal_proof_checks())
    add_counts(test_proof_diagnostics.run_proof_diagnostic_checks())

    with tempfile.TemporaryDirectory(prefix="safe-tests-") as temp_root_str:
        temp_root = Path(temp_root_str)
        add_counts(
            test_interfaces.run_interface_checks(
                safec,
                temp_root=temp_root,
                skip_ceiling_tests=skip_ceiling_tests,
            )
        )
        add_counts(test_contracts.run_contract_checks(safec, temp_root=temp_root))
        add_counts(test_cli_workflows.run_target_bits_check_section(safec))
        add_counts(test_contracts.run_mir_type_checks(safec, temp_root=temp_root))
        add_counts(test_emitted_shape.run_emitted_shape_checks(safec, temp_root=temp_root))

    add_counts(test_fixtures.run_diagnostic_golden_checks(safec))
    add_counts(test_cli_workflows.run_build_run_checks(skip_ceiling_tests=skip_ceiling_tests))
    add_counts(test_interfaces.run_interface_target_bits_checks(safec))
    add_counts(test_cli_workflows.run_post_interface_cli_checks())
    add_counts(test_proof_cli.run_safe_prove_success_checks())
    add_counts(test_cli_workflows.run_prove_workflow_checks())
    add_counts(test_proof_cli.run_safe_prove_failure_checks())
    add_counts(test_cli_workflows.run_environment_repl_checks())
    add_counts(test_embedded_listing.run_embedded_checks())

    print_summary(passed=passed, skipped=skipped, failures=failures)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
