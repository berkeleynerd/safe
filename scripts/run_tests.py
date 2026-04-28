#!/usr/bin/env python3
"""Run the minimal Safe test workflow."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from _lib import (
    test_arithmetic_audit,
    test_cli_workflows,
    test_contracts,
    test_dead_raise_audit,
    test_embedded_listing,
    test_emitted_shape,
    test_fixtures,
    test_gnatprove_trust_audit,
    test_interfaces,
    test_policy_drift,
    test_proof_cli,
    test_proof_diagnostics,
    test_rosetta_inventory,
    test_spark_mode_off_audit,
    test_spec_body_contract_audit,
    test_static_audit,
    test_stdlib_contract_audit,
)
from _lib.test_harness import (
    Failure,
    RunCounts,
    build_compiler,
    print_summary,
)


def main() -> int:
    passed = 0
    skipped = 0
    failures: list[Failure] = []

    def add_counts(counts: RunCounts) -> None:
        nonlocal passed, skipped
        section_passed, section_skipped, section_failures = counts
        passed += section_passed
        skipped += section_skipped
        failures.extend(section_failures)

    add_counts(test_policy_drift.run_policy_drift_checks())
    if failures:
        print_summary(passed=passed, skipped=skipped, failures=failures)
        return 1

    try:
        safec = build_compiler()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_tests: ERROR: {exc}", file=sys.stderr)
        return 1

    add_counts(test_fixtures.run_basic_fixture_checks(safec))
    add_counts(test_static_audit.run_static_audit_checks())
    add_counts(test_arithmetic_audit.run_arithmetic_audit_checks())
    add_counts(test_gnatprove_trust_audit.run_gnatprove_trust_audit_checks())
    add_counts(test_spark_mode_off_audit.run_spark_mode_off_audit_checks())
    add_counts(test_dead_raise_audit.run_dead_raise_audit_checks())
    add_counts(test_spec_body_contract_audit.run_spec_body_contract_audit_checks())
    add_counts(test_stdlib_contract_audit.run_stdlib_contract_audit_checks())
    add_counts(test_proof_cli.run_internal_proof_checks())
    add_counts(test_proof_diagnostics.run_proof_diagnostic_checks())
    add_counts(test_rosetta_inventory.run_rosetta_inventory_checks())

    with tempfile.TemporaryDirectory(prefix="safe-tests-") as temp_root_str:
        temp_root = Path(temp_root_str)
        add_counts(
            test_interfaces.run_interface_checks(
                safec,
                temp_root=temp_root,
            )
        )
        add_counts(test_contracts.run_contract_checks(safec, temp_root=temp_root))
        add_counts(test_cli_workflows.run_target_bits_check_section(safec))
        add_counts(test_contracts.run_mir_type_checks(safec, temp_root=temp_root))
        add_counts(test_emitted_shape.run_emitted_shape_checks(safec, temp_root=temp_root))

    add_counts(test_fixtures.run_diagnostic_golden_checks(safec))
    add_counts(test_cli_workflows.run_build_run_checks())
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
