"""Fixture and diagnostic-golden checks for ``scripts/run_tests.py``."""

from __future__ import annotations

from pathlib import Path

from _lib.proof_inventory import EMITTED_PROOF_EXCLUSIONS
from _lib.test_harness import (
    DIAGNOSTIC_EXIT_CODE,
    REPO_ROOT,
    RunCounts,
    check_fixture,
    extract_expected_block,
    record_result,
    repo_rel,
    run_command,
)

NEGATIVE_SKIPPED_FIXTURES = {
    REPO_ROOT / "tests" / "negative" / "neg_chan_empty_recv.safe",
}

CONCURRENCY_REJECT_FIXTURES = {
    REPO_ROOT / entry.path
    for entry in EMITTED_PROOF_EXCLUSIONS
    if entry.path.startswith("tests/concurrency/")
}

CHECK_SUCCESS_CASES = [
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_prebuffered.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_receive.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_timeout.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_zero_delay_ready.safe",
]

DIAGNOSTIC_GOLDEN_CASES = [
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_double_move.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_double_move.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_borrow_conflict.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_borrow_conflict.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_use_after_move.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_use_after_move.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_lifetime.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_lifetime_violation.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_observe_mutate.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_observe_mutation.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_target_not_null.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_move_target_not_null.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_source_maybe_null.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_move_source_not_nonnull.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_anon_reassign.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_anonymous_access_reassign.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_anon_reassign_join.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_anonymous_access_reassign_join.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_observe_requires_access.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_observe_requires_access.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_overflow.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule2_oob.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_index_oob.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule3_zero_div.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_zero_div.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule4_null_deref.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_null_deref.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_nan.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_nan.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_result_unguarded.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_result_unguarded.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_result_mutated.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_result_mutated.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr222_global_mutating_function.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr222_global_mutating_function.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr222_projected_global_output_function.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr222_projected_global_output_function.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr222_shared_read_function.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr222_shared_read_function.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr222_shared_mutating_function.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr222_shared_mutating_function.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr222_transitive_mutating_function.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr222_transitive_mutating_function.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_div_zero.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_div_zero.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_infinity.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_infinity.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_overflow.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_overflow.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_uninitialized.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_uninitialized.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_while_variant_not_derivable.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_loop_variant_not_derivable.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_while_variant_length_bound.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_while_variant_length_bound.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_while_variant_array_length_drain.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_while_variant_array_length_drain.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_while_variant_mutable_bound.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_while_variant_mutable_bound.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr117_uppercase_identifier.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_lowercase_spelling.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118_removed_natural.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118_removed_natural.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118b1_send_contract.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118b1_send_contract.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_invalid_binary_width.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_invalid_binary_width.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_implicit_integer_binary_mix.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_implicit_integer_binary_mix.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_shift_count_out_of_range.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_shift_count_out_of_range.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_binary_to_integer_oob.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_binary_to_integer_oob.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_mixed_logical_operators.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_mixed_logical_operators.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_string_concat_type_mismatch.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_string_concat_type_mismatch.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c1_print_expression.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c1_print_expression.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c1_print_bare_identifier.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c1_print_bare_identifier.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c1_print_unsupported_type.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c1_print_unsupported_type.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118i_write_enum_literal.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118i_write_enum_literal.txt",
    ),
]

def run_diagnostic_golden(safec: Path, source: Path, golden: Path) -> tuple[bool, str]:
    completed = run_command([str(safec), "check", repo_rel(source)], cwd=REPO_ROOT)
    if completed.returncode != DIAGNOSTIC_EXIT_CODE:
        return False, f"expected exit {DIAGNOSTIC_EXIT_CODE}, got {completed.returncode}"
    expected = extract_expected_block(golden)
    if completed.stderr.rstrip("\n") != expected.rstrip("\n"):
        return False, f"stderr mismatch against {repo_rel(golden)}"
    return True, ""



def run_basic_fixture_checks(safec: Path) -> RunCounts:
    passed = 0
    skipped = 0
    failures: list[tuple[str, str]] = []

    positive_fixtures = sorted((REPO_ROOT / "tests" / "positive").glob("*.safe"))
    negative_fixtures = sorted((REPO_ROOT / "tests" / "negative").glob("*.safe"))
    concurrency_fixtures = sorted((REPO_ROOT / "tests" / "concurrency").glob("*.safe"))

    for fixture in positive_fixtures:
        passed += record_result(
            failures,
            repo_rel(fixture),
            check_fixture(safec, fixture, expected_returncode=0),
        )

    for fixture in negative_fixtures:
        if fixture in NEGATIVE_SKIPPED_FIXTURES:
            skipped += 1
            continue
        passed += record_result(
            failures,
            repo_rel(fixture),
            check_fixture(safec, fixture, expected_returncode=DIAGNOSTIC_EXIT_CODE),
        )

    for fixture in concurrency_fixtures:
        expected_returncode = DIAGNOSTIC_EXIT_CODE if fixture in CONCURRENCY_REJECT_FIXTURES else 0
        passed += record_result(
            failures,
            repo_rel(fixture),
            check_fixture(safec, fixture, expected_returncode=expected_returncode),
        )

    for fixture in CHECK_SUCCESS_CASES:
        passed += record_result(
            failures,
            repo_rel(fixture),
            check_fixture(safec, fixture, expected_returncode=0),
        )

    return passed, skipped, failures


def run_diagnostic_golden_checks(safec: Path) -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    for source, golden in DIAGNOSTIC_GOLDEN_CASES:
        passed += record_result(
            failures,
            f"{repo_rel(source)} -> {repo_rel(golden)}",
            run_diagnostic_golden(safec, source, golden),
        )
    return passed, 0, failures
