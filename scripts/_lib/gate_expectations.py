"""Canonical shared expectations for active repository gates."""

from __future__ import annotations


D27_GOLDEN_CASES = [
    ("tests/negative/neg_rule1_overflow.safe", "tests/diagnostics_golden/diag_overflow.txt"),
    ("tests/negative/neg_rule2_oob.safe", "tests/diagnostics_golden/diag_index_oob.txt"),
    ("tests/negative/neg_rule3_zero_div.safe", "tests/diagnostics_golden/diag_zero_div.txt"),
    ("tests/negative/neg_rule4_null_deref.safe", "tests/diagnostics_golden/diag_null_deref.txt"),
    ("tests/negative/neg_rule5_nan.safe", "tests/diagnostics_golden/diag_rule5_nan.txt"),
]

PR102_DIAGNOSTIC_GOLDEN_CASES = [
    ("tests/negative/neg_rule5_div_zero.safe", "tests/diagnostics_golden/diag_rule5_div_zero.txt"),
    ("tests/negative/neg_rule5_infinity.safe", "tests/diagnostics_golden/diag_rule5_infinity.txt"),
    ("tests/negative/neg_rule5_overflow.safe", "tests/diagnostics_golden/diag_rule5_overflow.txt"),
    ("tests/negative/neg_rule5_uninitialized.safe", "tests/diagnostics_golden/diag_rule5_uninitialized.txt"),
    (
        "tests/negative/neg_while_variant_not_derivable.safe",
        "tests/diagnostics_golden/diag_loop_variant_not_derivable.txt",
    ),
]

OWNERSHIP_GOLDEN_CASES = [
    ("tests/negative/neg_own_double_move.safe", "tests/diagnostics_golden/diag_double_move.txt"),
    ("tests/negative/neg_own_borrow_conflict.safe", "tests/diagnostics_golden/diag_borrow_conflict.txt"),
    ("tests/negative/neg_own_use_after_move.safe", "tests/diagnostics_golden/diag_use_after_move.txt"),
    ("tests/negative/neg_own_lifetime.safe", "tests/diagnostics_golden/diag_lifetime_violation.txt"),
    ("tests/negative/neg_own_observe_mutate.safe", "tests/diagnostics_golden/diag_observe_mutation.txt"),
    ("tests/negative/neg_own_target_not_null.safe", "tests/diagnostics_golden/diag_move_target_not_null.txt"),
    ("tests/negative/neg_own_source_maybe_null.safe", "tests/diagnostics_golden/diag_move_source_not_nonnull.txt"),
    ("tests/negative/neg_own_anon_reassign.safe", "tests/diagnostics_golden/diag_anonymous_access_reassign.txt"),
    (
        "tests/negative/neg_own_anon_reassign_join.safe",
        "tests/diagnostics_golden/diag_anonymous_access_reassign_join.txt",
    ),
    (
        "tests/negative/neg_own_observe_requires_access.safe",
        "tests/diagnostics_golden/diag_observe_requires_access.txt",
    ),
]

RESULT_GOLDEN_CASES = [
    ("tests/negative/neg_result_unguarded.safe", "tests/diagnostics_golden/diag_result_unguarded.txt"),
    ("tests/negative/neg_result_mutated.safe", "tests/diagnostics_golden/diag_result_mutated.txt"),
]

ALL_DIAGNOSTIC_GOLDEN_CASES = [
    *OWNERSHIP_GOLDEN_CASES,
    *D27_GOLDEN_CASES,
    *RESULT_GOLDEN_CASES,
    *PR102_DIAGNOSTIC_GOLDEN_CASES,
]

PR05_POSITIVE_CASES = [
    "tests/positive/rule1_accumulate.safe",
    "tests/positive/rule1_averaging.safe",
    "tests/positive/rule1_conversion.safe",
    "tests/positive/rule1_parameter.safe",
    "tests/positive/rule1_return.safe",
    "tests/positive/rule2_binary_search.safe",
    "tests/positive/rule2_iteration.safe",
    "tests/positive/rule2_lookup.safe",
    "tests/positive/rule2_matrix.safe",
    "tests/positive/rule2_slice.safe",
    "tests/positive/rule3_average.safe",
    "tests/positive/rule3_divide.safe",
    "tests/positive/rule3_modulo.safe",
    "tests/positive/rule3_percent.safe",
    "tests/positive/rule3_remainder.safe",
    "tests/positive/rule4_conditional.safe",
    "tests/positive/rule4_deref.safe",
    "tests/positive/rule4_factory.safe",
    "tests/positive/rule4_linked_list.safe",
    "tests/positive/rule4_optional.safe",
]

PR05_NEGATIVE_CASES = [
    "tests/negative/neg_rule1_index_fail.safe",
    "tests/negative/neg_rule1_narrow_fail.safe",
    "tests/negative/neg_rule1_overflow.safe",
    "tests/negative/neg_rule1_param_fail.safe",
    "tests/negative/neg_rule1_return_fail.safe",
    "tests/negative/neg_rule2_dynamic.safe",
    "tests/negative/neg_rule2_empty.safe",
    "tests/negative/neg_rule2_negative.safe",
    "tests/negative/neg_rule2_off_by_one.safe",
    "tests/negative/neg_rule2_oob.safe",
    "tests/negative/neg_rule3_expression.safe",
    "tests/negative/neg_rule3_variable.safe",
    "tests/negative/neg_rule3_zero_div.safe",
    "tests/negative/neg_rule3_zero_mod.safe",
    "tests/negative/neg_rule3_zero_rem.safe",
    "tests/negative/neg_rule4_freed.safe",
    "tests/negative/neg_rule4_maybe_null.safe",
    "tests/negative/neg_rule4_moved.safe",
    "tests/negative/neg_rule4_null_deref.safe",
    "tests/negative/neg_rule4_uninitialized.safe",
]

PR06_POSITIVE_CASES = [
    "tests/positive/ownership_move.safe",
    "tests/positive/ownership_borrow.safe",
    "tests/positive/ownership_observe.safe",
    "tests/positive/ownership_observe_access.safe",
    "tests/positive/ownership_return.safe",
    "tests/positive/ownership_inout.safe",
]

PR06_NEGATIVE_CASES = [
    "tests/negative/neg_own_double_move.safe",
    "tests/negative/neg_own_borrow_conflict.safe",
    "tests/negative/neg_own_use_after_move.safe",
    "tests/negative/neg_own_lifetime.safe",
    "tests/negative/neg_own_observe_mutate.safe",
    "tests/negative/neg_own_target_not_null.safe",
    "tests/negative/neg_own_source_maybe_null.safe",
    "tests/negative/neg_own_anon_reassign.safe",
    "tests/negative/neg_own_anon_reassign_join.safe",
    "tests/negative/neg_own_observe_requires_access.safe",
    "tests/negative/neg_own_observe_move.safe",
    "tests/negative/neg_own_return_move.safe",
    "tests/negative/neg_own_inout_move.safe",
]

PR07_RULE5_POSITIVE_CASES = [
    "tests/positive/rule5_filter.safe",
    "tests/positive/rule5_interpolate.safe",
    "tests/positive/rule5_normalize.safe",
    "tests/positive/rule5_statistics.safe",
    "tests/positive/rule5_temperature.safe",
]

PR07_RULE5_NEGATIVE_CASES = [
    "tests/negative/neg_rule5_div_zero.safe",
    "tests/negative/neg_rule5_infinity.safe",
    "tests/negative/neg_rule5_nan.safe",
    "tests/negative/neg_rule5_overflow.safe",
    "tests/negative/neg_rule5_uninitialized.safe",
]

PR102_RULE5_POSITIVE_CASES = [
    *PR07_RULE5_POSITIVE_CASES,
    "tests/positive/rule5_vector_normalize.safe",
]

PR102_RULE5_NEGATIVE_CASES = [
    *PR07_RULE5_NEGATIVE_CASES,
]

PR102_LOOP_NEGATIVE_CASES = [
    "tests/negative/neg_while_variant_not_derivable.safe",
]

PR07_RESULT_CASES = [
    "tests/positive/result_guarded_access.safe",
    "tests/negative/neg_result_unguarded.safe",
    "tests/negative/neg_result_mutated.safe",
]

PR07_RESULT_POSITIVE_CASES = [
    "tests/positive/result_guarded_access.safe",
]

PR07_RESULT_NEGATIVE_CASES = [
    "tests/negative/neg_result_unguarded.safe",
    "tests/negative/neg_result_mutated.safe",
]

REPRESENTATIVE_EMIT_SAMPLES = [
    "tests/positive/rule2_binary_search.safe",
    "tests/positive/rule4_conditional.safe",
]
