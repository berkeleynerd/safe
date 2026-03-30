#!/usr/bin/env python3
"""Run the minimal Safe test workflow."""

from __future__ import annotations

import os
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from _lib.embedded_eval import parse_monitor_value
from _lib.harness_common import ensure_sdkroot

REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
SAFEC_PATH = COMPILER_ROOT / "bin" / "safec"
ALR_FALLBACK = Path.home() / "bin" / "alr"
DIAGNOSTIC_EXIT_CODE = 1
SAFE_CLI = REPO_ROOT / "scripts" / "safe_cli.py"
SAFE_REPL = REPO_ROOT / "scripts" / "safe_repl.py"
EMBEDDED_SMOKE = REPO_ROOT / "scripts" / "run_embedded_smoke.py"
VALIDATE_OUTPUT_CONTRACTS = REPO_ROOT / "scripts" / "validate_output_contracts.py"

# These fixtures live in category directories that do not match the
# compiler's current acceptance boundary, so keep the expectations explicit.
NEGATIVE_SUCCESS_FIXTURES = {
    REPO_ROOT / "tests" / "negative" / "neg_chan_empty_recv.safe",
    REPO_ROOT / "tests" / "negative" / "neg_chan_full_send.safe",
}

CONCURRENCY_REJECT_FIXTURES = {
    REPO_ROOT / "tests" / "concurrency" / "channel_access_type.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_ownership_binding.safe",
    REPO_ROOT / "tests" / "concurrency" / "try_send_ownership.safe",
}

INTERFACE_CASES = [
    (
        "types",
        REPO_ROOT / "tests" / "interfaces" / "provider_types.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_types.safe",
        0,
    ),
    (
        "channel",
        REPO_ROOT / "tests" / "interfaces" / "provider_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_channel.safe",
        0,
    ),
    (
        "object",
        REPO_ROOT / "tests" / "interfaces" / "provider_object.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_object.safe",
        0,
    ),
    (
        "constant-range",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_int.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_range.safe",
        0,
    ),
    (
        "constant-capacity",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_int.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_capacity.safe",
        0,
    ),
    (
        "constant-bool",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_bool.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_bool.safe",
        0,
    ),
    (
        "constant-missing-value",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_unsupported.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_missing_value.safe",
        1,
    ),
    (
        "transitive-channel-provider-ceiling",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_provider_ceiling.safe",
        0,
    ),
    (
        "transitive-channel-client-ceiling",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_client_ceiling.safe",
        0,
    ),
    (
        "transitive-global-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_global.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_global_ok.safe",
        1,
    ),
    (
        "imported-global-length-attribute-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_string_object.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_length_attribute_rejected.safe",
        1,
    ),
    (
        "imported-borrow-observe",
        REPO_ROOT / "tests" / "interfaces" / "provider_imported_call_ownership.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_borrow_observe.safe",
        0,
    ),
    (
        "mutual-family",
        REPO_ROOT / "tests" / "interfaces" / "provider_mutual_family.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_mutual_family.safe",
        0,
    ),
    (
        "directional-channel-receive-only",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_receive_only.safe",
        0,
    ),
    (
        "directional-channel-send-contract-violation",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_send_contract_violation.safe",
        1,
    ),
    (
        "binary",
        REPO_ROOT / "tests" / "interfaces" / "provider_binary.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_binary.safe",
        0,
    ),
    (
        "entry-with-clause",
        REPO_ROOT / "tests" / "interfaces" / "provider_types.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_entry_with_clause.safe",
        0,
    ),
    (
        "entry-import-rejected",
        REPO_ROOT / "tests" / "interfaces" / "entry_helper.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_import_entry_rejected.safe",
        1,
    ),
]

STATIC_INTERFACE_CASES = [
    (
        "legacy-channel-unconstrained",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_legacy_transitive_channel_unconstrained.safe",
        0,
    ),
    (
        "legacy-channel-requires-regen",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_receive_only.safe",
        1,
    ),
    (
        "bad-return-flag-type",
        REPO_ROOT / "tests" / "interfaces" / "provider_bad_return_flag.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_bad_return_flag.safe",
        1,
    ),
    (
        "missing-unit-kind",
        REPO_ROOT / "tests" / "interfaces" / "provider_missing_unit_kind.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_missing_unit_kind.safe",
        1,
    ),
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
]

BUILD_SUCCESS_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_package_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_entry_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_package_pre_task.safe",
        "41\n",
        True,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_field_build.safe",
        "5\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_array_component_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_tick_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_index_build.safe",
        "h\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_array_build.safe",
        "32\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_string_plain_build.safe",
        "hello\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_tuple_string_build.safe",
        "ok\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_string_field_runtime_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_string_array_component_runtime_build.safe",
        "Bob\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_param_runtime_build.safe",
        "7\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_result_runtime_build.safe",
        "2\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_field_runtime_build.safe",
        "20\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_array_component_runtime_build.safe",
        "3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_empty_growable_array_literal_build.safe",
        "0\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_runtime_self_assign_build.safe",
        "Ada\n5\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_for_of_fixed_build.safe",
        "60\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_for_of_growable_build.safe",
        "60\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_for_of_heap_element_build.safe",
        "a\nbc\ndef\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_nested_growable_array_literal_build.safe",
        "4\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_fixed_to_growable_build.safe",
        "25\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_to_fixed_literal_build.safe",
        "40\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_to_fixed_slice_build.safe",
        "16\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_for_of_string_build.safe",
        "5\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_string_order_build.safe",
        "15\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_string_case_build.safe",
        "3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_growable_to_fixed_guard_build.safe",
        "10\n20\n10\n20\ndone\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        "Ada\nBob\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        "1\n2\n9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_tuple_string_channel_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_record_string_channel_build.safe",
        "Ada\nBob\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        "1\nAda\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118e1_mutual_family_build.safe",
        "41\n",
        False,
    ),
]

BUILD_REJECT_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_root_with_clause.safe",
        "safe build: root files with `with` clauses are not supported yet",
    ),
]

RUN_SUCCESS_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_package_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_entry_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_package_pre_task.safe",
        "41\n",
        True,
    ),
]

RUN_REJECT_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_root_with_clause.safe",
        "safe build: root files with `with` clauses are not supported yet",
    ),
]

DEPLOY_REJECT_ARGV_CASES = [
    (
        [
            "deploy",
            "--simulate",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--board",
    ),
    (
        [
            "deploy",
            "--board",
            "not-a-board",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "invalid choice",
    ),
    (
        [
            "deploy",
            "--target",
            "bogus",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "requires target 'stm32f4', got 'bogus'",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "tests/build/pr118c2_root_with_clause.safe",
        ],
        "safe deploy: root files with `with` clauses are not supported yet",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "--expect-value",
            "42",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--watch-symbol and --expect-value must be provided together",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "--watch-symbol",
            "entry_integer_result__result",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--watch-symbol and --expect-value must be provided together",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--watch-symbol",
            "entry_integer_result__result",
            "--expect-value",
            "42",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--watch-symbol is currently supported only with --simulate",
    ),
]

OUTPUT_CONTRACT_CASES = [
    REPO_ROOT / "tests" / "positive" / "pr118c2_package_print.safe",
    REPO_ROOT / "tests" / "positive" / "pr118c2_entry_print.safe",
    REPO_ROOT / "tests" / "build" / "pr118d_for_of_growable_build.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_mutual_family.safe",
]

OUTPUT_CONTRACT_REJECT_CASES = [
    (
        "safei-bad-return-flag",
        REPO_ROOT / "tests" / "interfaces" / "provider_binary.safe",
        "subprograms[0].return_is_access_def must be a boolean",
    ),
]

EMITTED_SHAPE_CASES = [
    (
        "linked-list-sum-no-skip-proof",
        REPO_ROOT / "tests" / "positive" / "rule4_linked_list_sum.safe",
        ["Skip_Proof"],
    ),
    (
        "select-delay-no-blanket-warning-suppression",
        REPO_ROOT / "tests" / "concurrency" / "select_delay_local_scope.safe",
        ["pragma Warnings (Off);", "pragma Warnings (On);"],
    ),
    (
        "string-case-no-ada-case",
        REPO_ROOT / "tests" / "build" / "pr118d1_string_case_build.safe",
        ["case word is", "case mark is"],
    ),
    (
        "print-no-local-io-suppressions",
        REPO_ROOT / "tests" / "positive" / "pr118c1_print.safe",
        ["SPARK_Mode => Off", "Skip_Flow_And_Proof", "_safe_io"],
    ),
    (
        "value-channel-no-local-suppressions",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        ["SPARK_Mode => Off", "Skip_Flow_And_Proof", "_safe_io"],
    ),
    (
        "string-channel-direct-scalar-no-length-plumbing",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        ["Stored_Length"],
    ),
    (
        "growable-channel-direct-scalar-no-length-plumbing",
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        ["Stored_Length"],
    ),
    (
        "try-string-channel-direct-scalar-no-length-plumbing",
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        ["Stored_Length"],
    ),
]

EMITTED_REQUIRED_SHAPE_CASES = [
    (
        "string-channel-direct-scalar-ghost-model",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        [
            "text_ch_Model_Has_Value : Boolean := False;",
            "text_ch_Model_Length : Natural := 0;",
        ],
    ),
    (
        "growable-channel-direct-scalar-ghost-model",
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        [
            "data_ch_Model_Has_Value : Boolean := False;",
            "data_ch_Model_Length : Natural := 0;",
        ],
    ),
    (
        "try-string-channel-direct-scalar-ghost-model",
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        [
            "text_ch_Model_Has_Value : Boolean := False;",
            "text_ch_Model_Length : Natural := 0;",
        ],
    ),
]

EMITTED_PROTECTED_BODY_SHAPE_CASES = [
    (
        "string-channel-protected-body-no-heap-runtime",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        "text_ch_Channel",
        ["Safe_String_RT.Clone", "Safe_String_RT.Copy", "Safe_String_RT.Free"],
    ),
    (
        "growable-channel-protected-body-no-heap-runtime",
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        "data_ch_Channel",
        ["values_RT.Clone", "values_RT.Copy", "values_RT.Free"],
    ),
    (
        "tuple-channel-protected-body-no-heap-runtime",
        REPO_ROOT / "tests" / "build" / "pr118g_tuple_string_channel_build.safe",
        "pair_ch_Channel",
        [
            "pair_ch_Copy_Value",
            "pair_ch_Free_Value",
            "Safe_String_RT.Clone",
            "Safe_String_RT.Copy",
            "Safe_String_RT.Free",
        ],
    ),
    (
        "record-channel-protected-body-no-heap-runtime",
        REPO_ROOT / "tests" / "build" / "pr118g_record_string_channel_build.safe",
        "data_ch_Channel",
        [
            "data_ch_Copy_Value",
            "data_ch_Free_Value",
            "Safe_String_RT.Clone",
            "Safe_String_RT.Copy",
            "Safe_String_RT.Free",
        ],
    ),
]

SOURCE_SHAPE_CASES = [
    (
        "ada-emit-no-skip-proof-fallback",
        REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-ada_emit.adb",
        ["Skip_Proof"],
    ),
    (
        "ada-emit-no-channel-proof-suppression",
        REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-ada_emit.adb",
        ["Skip_Flow_And_Proof"],
    ),
    (
        "run-proofs-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "run_proofs.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "pr09-emit-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "_lib" / "pr09_emit.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "pr111-eval-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "_lib" / "pr111_language_eval.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "embedded-eval-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "_lib" / "embedded_eval.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "run-samples-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "run_samples.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
]

REPL_CASES = [
    (
        "repl-prints",
        "value : integer = 41;\nprint (value + 1)\n",
        "42\n",
        None,
    ),
    (
        "repl-rejects-bad-line",
        "value : integer = 41;\nprint (missing_name)\nprint (value + 1)\n",
        "42\n",
        "missing_name",
    ),
    (
        "repl-rejects-task",
        "task worker\n",
        "",
        "task declarations are not supported in repl mode",
    ),
]

EMBEDDED_SMOKE_CASES = [
    "binary_shift_result",
    "delay_scope_result",
    "entry_integer_result",
    "package_integer_result",
    "producer_consumer_result",
    "scoped_receive_result",
    "select_priority_result",
    "string_channel_result",
]

EMBEDDED_SMOKE_CONCURRENCY_CASES = [
    "delay_scope_result",
    "producer_consumer_result",
    "scoped_receive_result",
    "select_priority_result",
    "string_channel_result",
]

EMBEDDED_SMOKE_SUITES = [
    "all",
    "concurrency",
]


def run_ensure_sdkroot_case() -> tuple[bool, str]:
    calls: list[tuple[list[str], dict[str, str]]] = []

    def fake_xcrun_runner(
        argv: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if kwargs.get("text") is not True or kwargs.get("capture_output") is not True or kwargs.get("check") is not False:
            raise AssertionError("unexpected xcrun runner flags")
        probe_env = kwargs.get("env")
        if not isinstance(probe_env, dict):
            raise AssertionError("missing xcrun env")
        calls.append((argv, probe_env))
        return subprocess.CompletedProcess(argv, 0, stdout="/fake/sdk\n", stderr="")

    env = {
        "PATH": "/usr/bin",
        "SDKROOT": "/stale/sdk",
        "MACOSX_DEPLOYMENT_TARGET": "16.0",
    }
    updated = ensure_sdkroot(env, platform_name="darwin", xcrun_runner=fake_xcrun_runner)
    if len(calls) != 1:
        return False, f"unexpected xcrun calls {calls!r}"
    argv, probe_env = calls[0]
    if argv != ["xcrun", "--sdk", "macosx", "--show-sdk-path"]:
        return False, f"unexpected xcrun argv {argv!r}"
    if probe_env.get("PATH") != env["PATH"]:
        return False, f"unexpected xcrun PATH {probe_env.get('PATH')!r}"
    if "MACOSX_DEPLOYMENT_TARGET" in probe_env:
        return False, "xcrun env should not include MACOSX_DEPLOYMENT_TARGET"
    if updated.get("SDKROOT") != "/fake/sdk":
        return False, f"unexpected SDKROOT {updated.get('SDKROOT')!r}"
    if "MACOSX_DEPLOYMENT_TARGET" in updated:
        return False, "MACOSX_DEPLOYMENT_TARGET should be removed on darwin"
    if updated.get("PATH") != env["PATH"]:
        return False, f"PATH changed unexpectedly to {updated.get('PATH')!r}"
    if env.get("SDKROOT") != "/stale/sdk" or env.get("MACOSX_DEPLOYMENT_TARGET") != "16.0":
        return False, "ensure_sdkroot mutated the input environment"
    return True, ""


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def find_command(name: str, fallback: Path | None = None) -> str:
    resolved = shutil.which(name)
    if resolved:
        return resolved
    if fallback is not None and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def run_command(
    argv: list[str],
    *,
    cwd: Path,
    input_text: str | None = None,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=os.environ.copy(),
        text=True,
        input=input_text,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def first_message(completed: subprocess.CompletedProcess[str]) -> str:
    for stream in (completed.stderr, completed.stdout):
        for line in stream.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped
    return f"exit code {completed.returncode}"


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    marker = "Expected diagnostic output:\n------------------------------------------------------------------------\n"
    start = text.index(marker) + len(marker)
    end = text.index("\n------------------------------------------------------------------------\n", start)
    return text[start:end]


def build_compiler() -> Path:
    alr = find_command("alr", ALR_FALLBACK)
    completed = run_command([alr, "build"], cwd=COMPILER_ROOT)
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    if not SAFEC_PATH.exists():
        raise FileNotFoundError(f"missing safec binary at {SAFEC_PATH}")
    return SAFEC_PATH


def check_fixture(
    safec: Path,
    source: Path,
    *,
    expected_returncode: int,
    extra_args: list[str] | None = None,
) -> tuple[bool, str]:
    argv = [str(safec), "check", repo_rel(source), *(extra_args or [])]
    completed = run_command(argv, cwd=REPO_ROOT)
    ok = completed.returncode == expected_returncode
    return ok, first_message(completed)


def run_interface_case(
    safec: Path,
    *,
    label: str,
    provider: Path,
    client: Path,
    expected_returncode: int,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / label
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
        [
            str(safec),
            "emit",
            repo_rel(provider),
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
            "--ada-out-dir",
            str(ada_dir),
        ],
        cwd=REPO_ROOT,
    )
    if emit.returncode != 0:
        return False, f"provider emit failed: {first_message(emit)}"

    safei_path = iface_dir / f"{provider.stem.lower()}.safei.json"
    if not safei_path.exists():
        return False, f"provider emit missing {safei_path.name}"

    completed = run_command(
        [
            str(safec),
            "check",
            repo_rel(client),
            "--interface-search-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != expected_returncode:
        expectation = str(expected_returncode)
        return False, f"expected exit {expectation}, got {completed.returncode}: {first_message(completed)}"
    return True, ""


def run_static_interface_case(
    safec: Path,
    *,
    label: str,
    safei: Path,
    client: Path,
    expected_returncode: int,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / label
    iface_dir = case_root / "iface"
    iface_dir.mkdir(parents=True, exist_ok=True)

    safei_target = iface_dir / safei.name
    shutil.copyfile(safei, safei_target)

    completed = run_command(
        [
            str(safec),
            "check",
            repo_rel(client),
            "--interface-search-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != expected_returncode:
        expectation = str(expected_returncode)
        return False, f"expected exit {expectation}, got {completed.returncode}: {first_message(completed)}"
    return True, ""


def run_diagnostic_golden(safec: Path, source: Path, golden: Path) -> tuple[bool, str]:
    completed = run_command([str(safec), "check", repo_rel(source)], cwd=REPO_ROOT)
    if completed.returncode != DIAGNOSTIC_EXIT_CODE:
        return False, f"expected exit {DIAGNOSTIC_EXIT_CODE}, got {completed.returncode}"
    expected = extract_expected_block(golden)
    if completed.stderr.rstrip("\n") != expected.rstrip("\n"):
        return False, f"stderr mismatch against {repo_rel(golden)}"
    return True, ""


def print_summary(*, passed: int, failures: list[tuple[str, str]]) -> None:
    print(f"{passed} passed, {len(failures)} failed")
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")


def executable_name() -> str:
    return "main.exe" if os.name == "nt" else "main"


def safe_build_executable(source: Path) -> Path:
    return source.parent / "obj" / source.stem / executable_name()


def run_safe_build_case(
    source: Path,
    expected_stdout: str,
    *,
    allow_timeout: bool,
) -> tuple[bool, str]:
    build = run_command(
        [sys.executable, str(SAFE_CLI), "build", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if build.returncode != 0:
        return False, f"build failed: {first_message(build)}"

    executable = safe_build_executable(source)
    if not executable.exists():
        return False, f"missing executable {executable}"
    expected_banner = f"safe build: OK ({repo_rel(executable)})\n"
    if build.stdout != expected_banner:
        return False, f"unexpected build stdout {build.stdout!r}"
    if build.stderr:
        return False, f"unexpected build stderr {build.stderr!r}"

    try:
        run = run_command(
            [str(executable)],
            cwd=executable.parent,
            timeout=0.3 if allow_timeout else None,
        )
    except subprocess.TimeoutExpired as exc:
        if not allow_timeout:
            return False, "executable timed out"
        stdout = exc.stdout or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if not stdout.startswith(expected_stdout):
            return False, f"unexpected stdout before timeout {stdout!r}"
        return True, ""

    if run.returncode != 0:
        return False, f"executable failed: {first_message(run)}"
    if allow_timeout:
        if not run.stdout.startswith(expected_stdout):
            return False, f"unexpected stdout {run.stdout!r}"
    elif run.stdout != expected_stdout:
        return False, f"unexpected stdout {run.stdout!r}"
    return True, ""


def run_safe_build_reject_case(source: Path, expected_message: str) -> tuple[bool, str]:
    build = run_command(
        [sys.executable, str(SAFE_CLI), "build", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if build.returncode == 0:
        return False, "build unexpectedly succeeded"
    output = build.stderr or build.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""


def run_safe_run_case(
    source: Path,
    expected_stdout: str,
    *,
    allow_timeout: bool,
) -> tuple[bool, str]:
    argv = [sys.executable, str(SAFE_CLI), "run", repo_rel(source)]
    if not allow_timeout:
        completed = run_command(argv, cwd=REPO_ROOT)
        if completed.returncode != 0:
            return False, f"safe run failed: {first_message(completed)}"
        if completed.stdout != expected_stdout:
            return False, f"unexpected stdout {completed.stdout!r}"
        if completed.stderr:
            return False, f"unexpected stderr {completed.stderr!r}"
        if "safe build: OK (" in completed.stdout:
            return False, f"unexpected build banner in stdout {completed.stdout!r}"
        return True, ""

    build = run_command(
        [sys.executable, str(SAFE_CLI), "build", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if build.returncode != 0:
        return False, f"safe build failed: {first_message(build)}"

    executable = safe_build_executable(source)
    if not executable.exists():
        return False, f"missing executable {executable}"

    try:
        run = run_command(
            [str(executable)],
            cwd=executable.parent,
            timeout=0.3,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if not stdout.startswith(expected_stdout):
            return False, f"unexpected stdout before timeout {stdout!r}"
        return True, ""
    if run.returncode != 0:
        return False, f"executable failed: {first_message(run)}"
    stdout = run.stdout
    if not stdout.startswith(expected_stdout):
        return False, f"unexpected stdout before timeout {stdout!r}"
    if "safe build: OK (" in stdout:
        return False, f"unexpected build banner in stdout {stdout!r}"
    return True, ""


def run_safe_run_reject_case(source: Path, expected_message: str) -> tuple[bool, str]:
    completed = run_command(
        [sys.executable, str(SAFE_CLI), "run", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if completed.returncode == 0:
        return False, "safe run unexpectedly succeeded"
    output = completed.stderr or completed.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""


def run_safe_cli_help_case(argv: list[str], expected_snippets: list[str]) -> tuple[bool, str]:
    completed = run_command([sys.executable, str(SAFE_CLI), *argv], cwd=REPO_ROOT)
    if completed.returncode != 0:
        return False, f"help command failed: {first_message(completed)}"
    text = completed.stdout + completed.stderr
    for snippet in expected_snippets:
        if snippet not in text:
            return False, f"missing help snippet {snippet!r}"
    return True, ""


def run_safe_deploy_reject_case(argv: list[str], expected_message: str) -> tuple[bool, str]:
    completed = run_command([sys.executable, str(SAFE_CLI), *argv], cwd=REPO_ROOT)
    if completed.returncode == 0:
        return False, "safe deploy unexpectedly succeeded"
    output = completed.stderr or completed.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""


def run_output_contract_case(
    safec: Path,
    source: Path,
    *,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / source.stem
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
        [
            str(safec),
            "emit",
            repo_rel(source),
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
            "--ada-out-dir",
            str(ada_dir),
        ],
        cwd=REPO_ROOT,
    )
    if emit.returncode != 0:
        return False, f"emit failed: {first_message(emit)}"

    stem = source.stem.lower()
    validate = run_command(
        [
            sys.executable,
            str(VALIDATE_OUTPUT_CONTRACTS),
            "--ast",
            str(out_dir / f"{stem}.ast.json"),
            "--typed",
            str(out_dir / f"{stem}.typed.json"),
            "--mir",
            str(out_dir / f"{stem}.mir.json"),
            "--safei",
            str(iface_dir / f"{stem}.safei.json"),
            "--source-path",
            repo_rel(source),
        ],
        cwd=REPO_ROOT,
    )
    if validate.returncode != 0:
        return False, first_message(validate)
    return True, ""


def run_output_contract_reject_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    expected_message: str,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / f"{source.stem}-{label}"
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
        [
            str(safec),
            "emit",
            repo_rel(source),
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
            "--ada-out-dir",
            str(ada_dir),
        ],
        cwd=REPO_ROOT,
    )
    if emit.returncode != 0:
        return False, f"emit failed: {first_message(emit)}"

    stem = source.stem.lower()
    safei_path = iface_dir / f"{stem}.safei.json"
    payload = json.loads(safei_path.read_text(encoding="utf-8"))
    subprograms = payload.get("subprograms")
    if not isinstance(subprograms, list) or not subprograms:
        return False, "emitted safei has no subprograms to mutate"
    subprograms[0]["return_is_access_def"] = "bad"
    safei_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    validate = run_command(
        [
            sys.executable,
            str(VALIDATE_OUTPUT_CONTRACTS),
            "--ast",
            str(out_dir / f"{stem}.ast.json"),
            "--typed",
            str(out_dir / f"{stem}.typed.json"),
            "--mir",
            str(out_dir / f"{stem}.mir.json"),
            "--safei",
            str(safei_path),
            "--source-path",
            repo_rel(source),
        ],
        cwd=REPO_ROOT,
    )
    if validate.returncode == 0:
        return False, "validate_output_contracts unexpectedly succeeded"
    output = validate.stderr or validate.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""


def run_emitted_shape_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    forbidden_snippets: list[str],
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        _, emitted_text = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    for snippet in forbidden_snippets:
        if snippet in emitted_text:
            return False, f"found forbidden emitted snippet {snippet!r}"
    return True, ""


def emit_case_ada_text(
    safec: Path,
    *,
    label: str,
    source: Path,
    temp_root: Path,
) -> tuple[Path, str]:
    case_root = temp_root / f"{source.stem}-{label}"
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
        [
            str(safec),
            "emit",
            repo_rel(source),
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
            "--ada-out-dir",
            str(ada_dir),
        ],
        cwd=REPO_ROOT,
    )
    if emit.returncode != 0:
        raise RuntimeError(f"emit failed: {first_message(emit)}")

    emitted_text = ""
    ada_file_found = False
    for path in sorted(ada_dir.iterdir()):
        if path.suffix in {".adb", ".ads"}:
            ada_file_found = True
            emitted_text += path.read_text(encoding="utf-8")

    if not ada_file_found:
        raise RuntimeError(f"emit produced no Ada sources in {ada_dir}")

    return ada_dir, emitted_text


def run_emitted_required_shape_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    required_snippets: list[str],
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        _, emitted_text = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    for snippet in required_snippets:
        if snippet not in emitted_text:
            return False, f"missing required emitted snippet {snippet!r}"
    return True, ""


def run_emitted_protected_body_shape_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    protected_name: str,
    forbidden_snippets: list[str],
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        ada_dir, _ = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    body_pattern = re.compile(
        rf"protected body {re.escape(protected_name)} is(.*?)end {re.escape(protected_name)};",
        re.DOTALL,
    )

    for path in sorted(ada_dir.iterdir()):
        if path.suffix != ".adb":
            continue
        emitted_text = path.read_text(encoding="utf-8")
        match = body_pattern.search(emitted_text)
        if not match:
            continue
        protected_body = match.group(1)
        for snippet in forbidden_snippets:
            if snippet in protected_body:
                return (
                    False,
                    f"found forbidden protected-body snippet {snippet!r} in {path.name}",
                )
        return True, ""

    return False, f"missing protected body {protected_name!r} in emitted Ada sources"


def run_source_shape_case(
    *,
    source: Path,
    forbidden_snippets: list[str],
) -> tuple[bool, str]:
    source_text = source.read_text(encoding="utf-8")
    for snippet in forbidden_snippets:
        if snippet in source_text:
            return False, f"found forbidden source snippet {snippet!r}"
    return True, ""


def run_repl_case(
    *,
    label: str,
    input_text: str,
    expected_stdout: str,
    expected_stderr_substring: str | None,
) -> tuple[bool, str]:
    completed = run_command(
        [sys.executable, str(SAFE_REPL)],
        cwd=REPO_ROOT,
        input_text=input_text,
    )
    if completed.returncode != 0:
        return False, f"repl failed: {first_message(completed)}"
    if completed.stdout != expected_stdout:
        return False, f"unexpected stdout {completed.stdout!r}"
    if expected_stderr_substring is not None and expected_stderr_substring not in completed.stderr:
        return False, f"missing expected stderr {expected_stderr_substring!r}"
    return True, ""


def run_embedded_case_listing(
    *,
    suite_name: str,
    expected_cases: list[str],
) -> tuple[bool, str]:
    completed = run_command(
        [sys.executable, str(EMBEDDED_SMOKE), "--list-cases", "--suite", suite_name],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        return False, f"embedded case listing failed for {suite_name}: {first_message(completed)}"
    expected = "".join(f"{name}\n" for name in expected_cases)
    if completed.stdout != expected:
        return False, f"unexpected embedded case list for {suite_name} {completed.stdout!r}"
    if completed.stderr:
        return False, f"unexpected embedded case stderr for {suite_name} {completed.stderr!r}"
    return True, ""


def run_embedded_suite_listing() -> tuple[bool, str]:
    completed = run_command(
        [sys.executable, str(EMBEDDED_SMOKE), "--list-suites"],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        return False, f"embedded suite listing failed: {first_message(completed)}"
    expected = "".join(f"{name}\n" for name in EMBEDDED_SMOKE_SUITES)
    if completed.stdout != expected:
        return False, f"unexpected embedded suite list {completed.stdout!r}"
    if completed.stderr:
        return False, f"unexpected embedded suite stderr {completed.stderr!r}"
    return True, ""


def run_embedded_monitor_parsing_checks() -> tuple[bool, str]:
    cases = [
        ("renode-hex", "0x00000001\n", 1),
        ("openocd-mdw", "0x20000000: 00000001 \n", 1),
        ("openocd-mdw-hex", "0x20000000: 0x00000002\n", 2),
    ]
    for label, text, expected in cases:
        actual = parse_monitor_value(text)
        if actual != expected:
            return False, f"{label} parsed as {actual}, expected {expected}"
    return True, ""


def main() -> int:
    try:
        safec = build_compiler()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_tests: ERROR: {exc}", file=sys.stderr)
        return 1

    passed = 0
    failures: list[tuple[str, str]] = []

    positive_fixtures = sorted((REPO_ROOT / "tests" / "positive").glob("*.safe"))
    negative_fixtures = sorted((REPO_ROOT / "tests" / "negative").glob("*.safe"))
    concurrency_fixtures = sorted((REPO_ROOT / "tests" / "concurrency").glob("*.safe"))

    for fixture in positive_fixtures:
        ok, detail = check_fixture(safec, fixture, expected_returncode=0)
        if ok:
            passed += 1
        else:
            failures.append((repo_rel(fixture), detail))

    for fixture in negative_fixtures:
        expected_returncode = 0 if fixture in NEGATIVE_SUCCESS_FIXTURES else DIAGNOSTIC_EXIT_CODE
        ok, detail = check_fixture(safec, fixture, expected_returncode=expected_returncode)
        if ok:
            passed += 1
        else:
            failures.append((repo_rel(fixture), detail))

    for fixture in concurrency_fixtures:
        expected_returncode = DIAGNOSTIC_EXIT_CODE if fixture in CONCURRENCY_REJECT_FIXTURES else 0
        ok, detail = check_fixture(safec, fixture, expected_returncode=expected_returncode)
        if ok:
            passed += 1
        else:
            failures.append((repo_rel(fixture), detail))

    with tempfile.TemporaryDirectory(prefix="safe-tests-") as temp_root_str:
        temp_root = Path(temp_root_str)
        for label, provider, client, expected_returncode in INTERFACE_CASES:
            ok, detail = run_interface_case(
                safec,
                label=label,
                provider=provider,
                client=client,
                expected_returncode=expected_returncode,
                temp_root=temp_root,
            )
            pair_label = f"{repo_rel(provider)} -> {repo_rel(client)}"
            if ok:
                passed += 1
            else:
                failures.append((pair_label, detail))

        for label, safei, client, expected_returncode in STATIC_INTERFACE_CASES:
            ok, detail = run_static_interface_case(
                safec,
                label=label,
                safei=safei,
                client=client,
                expected_returncode=expected_returncode,
                temp_root=temp_root,
            )
            pair_label = f"{repo_rel(safei)} -> {repo_rel(client)}"
            if ok:
                passed += 1
            else:
                failures.append((pair_label, detail))

        for source in OUTPUT_CONTRACT_CASES:
            ok, detail = run_output_contract_case(safec, source, temp_root=temp_root)
            label = f"contracts:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((label, detail))

        for label, source, expected_message in OUTPUT_CONTRACT_REJECT_CASES:
            ok, detail = run_output_contract_reject_case(
                safec,
                label=label,
                source=source,
                expected_message=expected_message,
                temp_root=temp_root,
            )
            case_label = f"contracts-reject:{label}:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((case_label, detail))

        for label, source, forbidden_snippets in EMITTED_SHAPE_CASES:
            ok, detail = run_emitted_shape_case(
                safec,
                label=label,
                source=source,
                forbidden_snippets=forbidden_snippets,
                temp_root=temp_root,
            )
            case_label = f"emitted-shape:{label}:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((case_label, detail))

        for label, source, required_snippets in EMITTED_REQUIRED_SHAPE_CASES:
            ok, detail = run_emitted_required_shape_case(
                safec,
                label=label,
                source=source,
                required_snippets=required_snippets,
                temp_root=temp_root,
            )
            case_label = f"emitted-required-shape:{label}:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((case_label, detail))

        for label, source, protected_name, forbidden_snippets in EMITTED_PROTECTED_BODY_SHAPE_CASES:
            ok, detail = run_emitted_protected_body_shape_case(
                safec,
                label=label,
                source=source,
                protected_name=protected_name,
                forbidden_snippets=forbidden_snippets,
                temp_root=temp_root,
            )
            case_label = f"emitted-protected-shape:{label}:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((case_label, detail))

        for label, source, forbidden_snippets in SOURCE_SHAPE_CASES:
            ok, detail = run_source_shape_case(
                source=source,
                forbidden_snippets=forbidden_snippets,
            )
            case_label = f"source-shape:{label}:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((case_label, detail))

    for source, golden in DIAGNOSTIC_GOLDEN_CASES:
        ok, detail = run_diagnostic_golden(safec, source, golden)
        label = f"{repo_rel(source)} -> {repo_rel(golden)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for source, expected_stdout, allow_timeout in BUILD_SUCCESS_CASES:
        ok, detail = run_safe_build_case(source, expected_stdout, allow_timeout=allow_timeout)
        label = f"safe build {repo_rel(source)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for source, expected_message in BUILD_REJECT_CASES:
        ok, detail = run_safe_build_reject_case(source, expected_message)
        label = f"safe build {repo_rel(source)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for source, expected_stdout, allow_timeout in RUN_SUCCESS_CASES:
        ok, detail = run_safe_run_case(source, expected_stdout, allow_timeout=allow_timeout)
        label = f"safe run {repo_rel(source)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for source, expected_message in RUN_REJECT_CASES:
        ok, detail = run_safe_run_reject_case(source, expected_message)
        label = f"safe run {repo_rel(source)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for argv, expected in (
        (["--help"], ["safe deploy", "safe run"]),
        (["deploy", "--help"], ["--board", "--simulate", "--watch-symbol", "--expect-value"]),
    ):
        ok, detail = run_safe_cli_help_case(argv, expected)
        label = f"safe cli help {' '.join(argv)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for argv, expected_message in DEPLOY_REJECT_ARGV_CASES:
        ok, detail = run_safe_deploy_reject_case(argv, expected_message)
        label = f"safe {' '.join(argv)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    ok, detail = run_ensure_sdkroot_case()
    if ok:
        passed += 1
    else:
        failures.append(("ensure_sdkroot darwin normalization", detail))

    for label, input_text, expected_stdout, expected_stderr_substring in REPL_CASES:
        ok, detail = run_repl_case(
            label=label,
            input_text=input_text,
            expected_stdout=expected_stdout,
            expected_stderr_substring=expected_stderr_substring,
        )
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    ok, detail = run_embedded_suite_listing()
    if ok:
        passed += 1
    else:
        failures.append(("embedded smoke suite listing", detail))

    ok, detail = run_embedded_case_listing(
        suite_name="all",
        expected_cases=EMBEDDED_SMOKE_CASES,
    )
    if ok:
        passed += 1
    else:
        failures.append(("embedded smoke case listing", detail))

    ok, detail = run_embedded_case_listing(
        suite_name="concurrency",
        expected_cases=EMBEDDED_SMOKE_CONCURRENCY_CASES,
    )
    if ok:
        passed += 1
    else:
        failures.append(("embedded smoke concurrency listing", detail))

    ok, detail = run_embedded_monitor_parsing_checks()
    if ok:
        passed += 1
    else:
        failures.append(("embedded monitor parsing", detail))

    print_summary(passed=passed, failures=failures)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
