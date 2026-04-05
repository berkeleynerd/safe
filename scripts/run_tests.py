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
from _lib.proof_eval import (
    allow_clean_nonzero_gnatprove_exit,
    first_message as proof_eval_first_message,
)
from _lib.proof_inventory import (
    EMITTED_PROOF_COVERED_PATHS,
    EMITTED_PROOF_EXCLUSIONS,
    EMITTED_PROOF_FIXTURES,
    iter_proof_coverage_paths,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
SAFEC_PATH = COMPILER_ROOT / "bin" / "safec"
ALR_FALLBACK = Path.home() / "bin" / "alr"
DIAGNOSTIC_EXIT_CODE = 1
SAFE_CLI = REPO_ROOT / "scripts" / "safe_cli.py"
SAFE_REPL = REPO_ROOT / "scripts" / "safe_repl.py"
EMBEDDED_SMOKE = REPO_ROOT / "scripts" / "run_embedded_smoke.py"
VALIDATE_OUTPUT_CONTRACTS = REPO_ROOT / "scripts" / "validate_output_contracts.py"
VALIDATE_AST_OUTPUT = REPO_ROOT / "scripts" / "validate_ast_output.py"
VSCODE_README = REPO_ROOT / "editors" / "vscode" / "README.md"
VSCODE_PACKAGE_JSON = REPO_ROOT / "editors" / "vscode" / "package.json"
LOCAL_WITH_RE = re.compile(r"^\s*with\s+([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)\s*;\s*$")

EMITTED_GNATPROVE_WARNING_RE = re.compile(
    r"pragma\s+Warnings\s*\(\s*GNATprove\b.*?\);",
    re.IGNORECASE | re.DOTALL,
)
EMITTED_ASSUME_RE = re.compile(
    r"pragma\s+Assume\s*\(.*?\);",
    re.IGNORECASE | re.DOTALL,
)

# These fixtures describe future deadlock-analysis work rather than the
# current accepted PR11.9d boundary, so keep them explicit.
NEGATIVE_SKIPPED_FIXTURES = {
    REPO_ROOT / "tests" / "negative" / "neg_chan_empty_recv.safe",
}

CONCURRENCY_REJECT_FIXTURES = {
    REPO_ROOT / entry.path
    for entry in EMITTED_PROOF_EXCLUSIONS
    if entry.path.startswith("tests/concurrency/")
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
    (
        "enum",
        REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_enum.safe",
        0,
    ),
    (
        "enum-unqualified-import-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_enum_unqualified.safe",
        1,
    ),
    (
        "enum-literal-assign-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_enum_literal_assign.safe",
        1,
    ),
    (
        "optional",
        REPO_ROOT / "tests" / "interfaces" / "provider_optional.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_optional.safe",
        0,
    ),
    (
        "list",
        REPO_ROOT / "tests" / "interfaces" / "provider_list.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_list.safe",
        0,
    ),
    (
        "map",
        REPO_ROOT / "tests" / "interfaces" / "provider_map.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_map.safe",
        0,
    ),
    (
        "list-method",
        REPO_ROOT / "tests" / "interfaces" / "provider_list.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_list_method.safe",
        0,
    ),
    (
        "optional-method",
        REPO_ROOT / "tests" / "interfaces" / "provider_optional.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_optional_method.safe",
        0,
    ),
    (
        "imported-method-observe",
        REPO_ROOT / "tests" / "interfaces" / "provider_imported_call_ownership.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_method_observe.safe",
        0,
    ),
    (
        "imported-interface",
        REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_printable.safe",
        0,
    ),
    (
        "imported-generic",
        REPO_ROOT / "tests" / "interfaces" / "provider_generic.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_generic.safe",
        0,
    ),
    (
        "imported-generic-constraint",
        REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_generic_constraint.safe",
        0,
    ),
]

INTERFACE_REJECT_CASES = [
    (
        "select-public-channel",
        REPO_ROOT / "tests" / "interfaces" / "provider_select_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_select_channel.safe",
        "PR11.9a temporarily admits select arms only on same-unit non-public channels",
    ),
    (
        "ambiguous-imported-method",
        REPO_ROOT / "tests" / "interfaces" / "provider_optional.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_optional_method_ambiguous.safe",
        "ambiguous method call `unwrap_or_zero`",
    ),
    (
        "ambiguous-interface-satisfaction",
        REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_printable_ambiguous.safe",
        "does not satisfy interface",
    ),
    (
        "imported-generic-missing-type-args",
        REPO_ROOT / "tests" / "interfaces" / "provider_generic.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_generic_missing_args.safe",
        "requires explicit type arguments in PR11.11c",
    ),
]

CHECK_SUCCESS_CASES = [
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_prebuffered.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_receive.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_timeout.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_zero_delay_ready.safe",
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


AST_CONTRACT_CASES = [
    REPO_ROOT / "tests" / "positive" / "pr118k_try_propagation.safe",
    REPO_ROOT / "tests" / "positive" / "pr118k_match.safe",
    REPO_ROOT / "tests" / "positive" / "pr1110a_optional_guarded.safe",
    REPO_ROOT / "tests" / "positive" / "pr1110b_list_basics.safe",
    REPO_ROOT / "tests" / "positive" / "pr1110c_map_basics.safe",
    REPO_ROOT / "tests" / "positive" / "pr1111a_method_syntax.safe",
    REPO_ROOT / "tests" / "positive" / "pr1111b_interface_local.safe",
    REPO_ROOT / "tests" / "positive" / "pr1111c_generic_basics.safe",
    REPO_ROOT / "tests" / "positive" / "pr1112a_shared_field_access.safe",
    REPO_ROOT / "tests" / "positive" / "pr1112b_shared_snapshot.safe",
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
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118i_write_enum_literal.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118i_write_enum_literal.txt",
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
        REPO_ROOT / "tests" / "build" / "pr1110a_optional_string_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110a_optional_growable_build.safe",
        "3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_build.safe",
        "40\n3\n30\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_empty_build.safe",
        "0\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_string_build.safe",
        "Bob\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_growable_build.safe",
        "2\n8\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110c_map_build.safe",
        "15\n20\n1\n2\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110c_map_string_build.safe",
        "Bob\nAda\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110c_map_list_build.safe",
        "3\n3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111a_builtin_methods_build.safe",
        "30\n15\n20\n2\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111b_interface_builtin_build.safe",
        "1\n20\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111c_generic_build.safe",
        "3\n9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111c_imported_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111c_imported_alias_and_collision_build.safe",
        "10\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112a_shared_task_build.safe",
        "4\n5\n3\n2\n",
        True,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112b_shared_update_build.safe",
        "4\n7\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_string_build.safe",
        "start\ninner\nworld\nBob\nright\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_container_fields_build.safe",
        "3\nBob\n3\n2\nAda\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112c_layered_growable_type_build.safe",
        "3\n",
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
        REPO_ROOT / "tests" / "build" / "pr119d_send_single_eval_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118e1_mutual_family_build.safe",
        "41\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "interfaces" / "pr169_safe_elaborate_collision.safe",
        "41\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_build.safe",
        "30\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_arg_order_build.safe",
        "1\n",
        False,
    ),
]

BUILD_REJECT_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_root_with_clause.safe",
        "local dependency source not found for package `missing_helper`",
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
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_build.safe",
        "30\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_arg_order_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_empty_build.safe",
        "0\n",
        False,
    ),
]

RUN_REJECT_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_root_with_clause.safe",
        "local dependency source not found for package `missing_helper`",
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
        "safe deploy: imported roots with leading `with` clauses are not supported for this command yet",
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

PROVE_SINGLE_SUCCESS_SOURCE = REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe"
PROVE_IMPORTED_SUCCESS_SOURCE = REPO_ROOT / "tests" / "interfaces" / "client_types.safe"
PROVE_FAILURE_SOURCE = REPO_ROOT / "tests" / "negative" / "neg_rule2_oob.safe"
PROVE_DIRECTORY_FIXTURES = [
    REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe",
    REPO_ROOT / "tests" / "positive" / "constant_range_bound.safe",
]

OUTPUT_CONTRACT_CASES = [
    REPO_ROOT / "tests" / "positive" / "pr118c2_package_print.safe",
    REPO_ROOT / "tests" / "positive" / "pr118c2_entry_print.safe",
    REPO_ROOT / "tests" / "build" / "pr118d_for_of_growable_build.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_mutual_family.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_generic.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr118k_try_while_contract.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_list.safe",
]

OUTPUT_CONTRACT_REJECT_CASES = [
    (
        "safei-bad-return-flag",
        REPO_ROOT / "tests" / "interfaces" / "provider_binary.safe",
        "subprograms[0].return_is_access_def must be a boolean",
    ),
    (
        "safei-template-source-key-on-non-generic",
        REPO_ROOT / "tests" / "interfaces" / "provider_binary.safe",
        "subprograms[0].template_source is only valid for generic subprograms",
    ),
]

EMITTED_PRAGMA_ALLOWLIST = {
    'pragma Assume (Safe_String_RT.Length (Safe_Channel_Staged_1) = Safe_Channel_Length_1);',
    'pragma Assume (Safe_String_RT.Length (Safe_Channel_Staged_3) = Safe_Channel_Length_3);',
    'pragma Assume (values_RT.Length (Safe_Channel_Staged_3) = Safe_Channel_Length_3);',
    'pragma Warnings (GNATprove, Off, "implicit aspect Always_Terminates", Reason => "shared runtime cleanup termination is accepted");',
    'pragma Warnings (GNATprove, Off, "initialization of", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "initialization of", Reason => "generated local initialization is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "channel results are consumed on the success path only");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "for-of loop item cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "heap-backed channel staging is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "generated timer cancel result is intentionally ignored");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "generated dispatcher wake result is intentionally ignored on no-delay select paths");',
    'pragma Warnings (GNATprove, Off, "has no effect", Reason => "generated package elaboration helper is intentional");',
    'pragma Warnings (GNATprove, Off, "implicit aspect Always_Terminates", Reason => "generated package elaboration helper termination is accepted");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "for-of loop item cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "task-local branching is intentionally isolated");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "task-local state updates are intentionally isolated");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "static for-of string unrolling exposes constant conditions");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "deferred heap-backed package initialization is intentional");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "static for-of unrolling preserves intermediate source assignments");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "task-local state updates are intentionally isolated");',
    'pragma Warnings (GNATprove, Off, "unused initial value of", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, On, "has no effect");',
    'pragma Warnings (GNATprove, On, "implicit aspect Always_Terminates");',
    'pragma Warnings (GNATprove, On, "initialization of");',
    'pragma Warnings (GNATprove, On, "is set by");',
    'pragma Warnings (GNATprove, On, "statement has no effect");',
    'pragma Warnings (GNATprove, On, "unused assignment");',
    'pragma Warnings (GNATprove, On, "unused initial value of");',
}

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
        "string-channel-direct-scalar-no-protected-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        ["protected type text_ch_Channel is", "_Model_Has_Value", "pragma Assume ("],
    ),
    (
        "growable-channel-direct-scalar-no-protected-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        ["protected type data_ch_Channel is", "_Model_Has_Value", "pragma Assume ("],
    ),
    (
        "try-string-channel-direct-scalar-no-protected-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        ["protected type text_ch_Channel is", "_Model_Has_Value", "pragma Assume ("],
    ),
    (
        "heap-send-length-no-source-rerender",
        REPO_ROOT / "tests" / "build" / "pr119d_send_single_eval_build.safe",
        ["Safe_String_RT.Length (next_text)"],
    ),
    (
        "select-delay-no-polling-lowering",
        REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
        [
            "Select_Polls",
            "Select_Iter",
            "if Select_Iter > 0 then",
            "if Select_Start >= Select_Deadline then",
        ],
    ),
    (
        "select-no-delay-no-polling-lowering",
        REPO_ROOT / "tests" / "embedded" / "select_single_ready_result.safe",
        ["Select_Polls", "Select_Iter", "delay 0.001;"],
    ),
    (
        "shared-root-no-raw-package-object",
        REPO_ROOT / "tests" / "positive" / "pr1112a_shared_field_access.safe",
        ["cfg : settings;", "cfg : settings :="],
    ),
    (
        "shared-root-nested-write-no-whole-record-snapshot-temp",
        REPO_ROOT / "tests" / "build" / "pr1112b_shared_update_build.safe",
        ["Safe_Shared_Snapshot_", "Safe_Shared_cfg.Set_All (Safe_Shared_Snapshot_"],
    ),
]

EMITTED_REQUIRED_SHAPE_CASES = [
    (
        "string-channel-direct-scalar-record-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        [
            "type text_ch_Channel is record",
            "Full : Boolean := False;",
            "Stored_Length_Value : Natural := 0;",
            "Pre => text_ch_Well_Formed and then not text_ch.Full",
            "Pre => text_ch_Well_Formed and then text_ch.Full",
        ],
    ),
    (
        "growable-channel-direct-scalar-record-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        [
            "type data_ch_Channel is record",
            "Full : Boolean := False;",
            "Stored_Length_Value : Natural := 0;",
            "Pre => data_ch_Well_Formed and then not data_ch.Full",
            "Pre => data_ch_Well_Formed and then data_ch.Full",
        ],
    ),
    (
        "try-string-channel-direct-scalar-record-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        [
            "type text_ch_Channel is record",
            "Full : Boolean := False;",
            "Stored_Length_Value : Natural := 0;",
            "Pre => text_ch_Well_Formed and then not text_ch.Full",
            "Pre => text_ch_Well_Formed and then text_ch.Full",
        ],
    ),
    (
        "heap-send-stages-before-length-model",
        REPO_ROOT / "tests" / "build" / "pr119d_send_single_eval_build.safe",
        [
            "Safe_Channel_Staged_1 := Safe_String_RT.Clone (next_text);",
            "Safe_Channel_Length_1 := Safe_String_RT.Length (Safe_Channel_Staged_1);",
        ],
    ),
    (
        "select-delay-dispatcher-lowering",
        REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
        [
            "protected type Safe_Select_Dispatcher_",
            "procedure Reset;",
            "procedure Signal;",
            "procedure Signal_Delay (Event : in out Ada.Real_Time.Timing_Events.Timing_Event);",
            "entry Await (Timed_Out : out Boolean);",
            ".Signal;",
            ".Await (Select_Timed_Out);",
            "Ada.Real_Time.Timing_Events.Set_Handler",
            ".Signal_Delay'Access",
            "Select_Delay_Span : constant Ada.Real_Time.Time_Span :=",
            "_Compute_Deadline (Start : in Ada.Real_Time.Time; Delay_Span : in Ada.Real_Time.Time_Span)",
            "Select_Timeout_Observed : Boolean;",
            "Select_Timeout_Observed := Select_Start >= Select_Deadline;",
            "if not Select_Timeout_Observed then",
            "if Select_Timeout_Observed then",
        ],
    ),
    (
        "select-zero-delay-ready-precheck-before-timeout",
        REPO_ROOT / "tests" / "interfaces" / "pr119a_select_zero_delay_ready.safe",
        [
            "Select_Timeout_Observed := Select_Start >= Select_Deadline;",
            "if not Select_Timeout_Observed then",
            "if not Select_Done then",
            "msg_ch.Try_Receive (item, Arm_Success);",
            "if Select_Timeout_Observed then",
        ],
    ),
    (
        "select-no-delay-dispatcher-await",
        REPO_ROOT / "tests" / "embedded" / "select_single_ready_result.safe",
        [
            "protected type Safe_Select_Dispatcher_",
            "_Next_Arm : Positive range 1 .. 2 := 1",
            "for Select_Offset in 0 .. 1 loop",
            "Select_Probe_Ordinal : constant Positive range 1 .. 2 :=",
            "case Select_Probe_Ordinal is",
            "_Next_Arm := 2;",
            "_Next_Arm := 1;",
            ".Signal;",
            ".Await (Select_Timed_Out);",
        ],
    ),
    (
        "shared-root-protected-wrapper-lowering",
        REPO_ROOT / "tests" / "positive" / "pr1112a_shared_field_access.safe",
        [
            "protected type Safe_Shared_cfg_Wrapper with Priority => System.Any_Priority'Last is",
            "function Get_All return settings;",
            "procedure Set_All (Value : in settings);",
            "function Get_count return",
            "procedure Set_count (Value : in",
            "function Get_nested return",
            "procedure Initialize (Value : in settings);",
            "Safe_Shared_cfg : Safe_Shared_cfg_Wrapper;",
        ],
    ),
    (
        "shared-root-snapshot-update-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112b_shared_update_build.safe",
        [
            "Safe_Shared_cfg.Set_All (next);",
            "procedure Set_Path_nested_depth (Value : in counter);",
            "Safe_Shared_cfg.Set_Path_nested_depth (7);",
        ],
    ),
    (
        "shared-root-heap-wrapper-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_string_build.safe",
        [
            "function Get_All return settings is",
            "function Get_text return Safe_String_RT.Safe_String is",
            "Safe_String_RT.Clone (State_Value.text)",
            "Safe_String_RT.Free (State_Value.text);",
            "procedure Set_Path_nested_label (Value : in Safe_String_RT.Safe_String);",
            "Safe_String_RT.Free (State_Value.nested.label);",
        ],
    ),
    (
        "shared-root-container-wrapper-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_container_fields_build.safe",
        [
            "function Get_items return Safe_growable_array_integer is",
            "Result := Safe_growable_array_integer_RT.Clone (State_Value.items);",
            "Safe_growable_array_integer_RT.Free (State_Value.items);",
            "State_Value.items := Safe_growable_array_integer_RT.Clone (Value);",
            "Safe_Shared_cfg_settings_Copy (Result, State_Value);",
            "Safe_Shared_cfg_settings_Free (State_Value);",
            "Safe_Shared_cfg_settings_Copy (State_Value, Value);",
        ],
    ),
]

EMITTED_PROTECTED_BODY_SHAPE_CASES = [
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
    (
        "shared-root-heap-protected-body-no-raw-state-assignments",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_string_build.safe",
        "Safe_Shared_cfg_Wrapper",
        [
            "return State_Value;",
            "State_Value := Value;",
            "return State_Value.text;",
            "State_Value.text := Value;",
            "return State_Value.nested;",
            "State_Value.nested := Value;",
            "State_Value.nested.label := Value;",
        ],
    ),
    (
        "shared-root-container-protected-body-no-raw-state-assignments",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_container_fields_build.safe",
        "Safe_Shared_cfg_Wrapper",
        [
            "return State_Value;",
            "return State_Value.items;",
            "State_Value.items := Value;",
            "return State_Value.names;",
            "State_Value.names := Value;",
            "return State_Value.data;",
            "State_Value.data := Value;",
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
        "ada-emit-no-select-polling-lowering",
        REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-ada_emit.adb",
        ["Select_Poll_Quantum_Seconds", "Select_Polls : constant Positive :=", "for Select_Iter in 0 .. Select_Polls loop"],
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
    "select_single_ready_result",
    "select_timeout_cursor_result",
    "string_channel_result",
]

EMBEDDED_SMOKE_CONCURRENCY_CASES = [
    "delay_scope_result",
    "producer_consumer_result",
    "scoped_receive_result",
    "select_priority_result",
    "select_single_ready_result",
    "select_timeout_cursor_result",
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


def run_interface_reject_case(
    safec: Path,
    *,
    label: str,
    provider: Path,
    client: Path,
    expected_message: str,
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
    if completed.returncode != DIAGNOSTIC_EXIT_CODE:
        return False, f"expected exit {DIAGNOSTIC_EXIT_CODE}, got {completed.returncode}: {first_message(completed)}"
    output = completed.stderr or completed.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
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


def print_summary(*, passed: int, skipped: int, failures: list[tuple[str, str]]) -> None:
    summary = f"{passed} passed"
    if skipped:
        summary += f", {skipped} skipped"
    summary += f", {len(failures)} failed"
    print(summary)
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")


def executable_name() -> str:
    return "main.exe" if os.name == "nt" else "main"


def safe_build_executable(source: Path, *, target_bits: int = 64) -> Path:
    return source.parent / "obj" / source.stem / f"target-{target_bits}" / executable_name()


def safe_prove_summary_path(source: Path, *, target_bits: int = 64) -> Path:
    return source.parent / "obj" / source.stem / f"prove-{target_bits}" / "obj" / "gnatprove" / "gnatprove.out"


def clear_project_artifacts(source: Path) -> None:
    shutil.rmtree(source.parent / ".safe-build", ignore_errors=True)
    shutil.rmtree(source.parent / "obj" / source.stem, ignore_errors=True)


def run_safe_build_case(
    source: Path,
    expected_stdout: str,
    *,
    allow_timeout: bool,
) -> tuple[bool, str]:
    clear_project_artifacts(source)
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
    clear_project_artifacts(source)
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
    clear_project_artifacts(source)
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
    clear_project_artifacts(source)
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


def run_safe_run_mutated_iterable_case() -> tuple[bool, str]:
    source_text = """package mutated_iterable_runtime

   plain : string = "Ada";
   total : integer = 0;

   function rewrite (value : mut string)
      value = "Bob";

   rewrite (plain);

   for ch of plain
      if ch == "B" or ch == "o" or ch == "b"
         total = total + 1;

   print (total)
"""

    with tempfile.TemporaryDirectory(prefix="safe-run-mutated-iterable-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "mutated_iterable_runtime.safe"
        source.write_text(source_text, encoding="utf-8")
        completed = run_command(
            [sys.executable, str(SAFE_CLI), "run", source.name],
            cwd=temp_root,
        )
        if completed.returncode != 0:
            return False, f"safe run failed: {first_message(completed)}"
        if completed.stdout != "3\n":
            return False, f"unexpected stdout {completed.stdout!r}"
        if completed.stderr:
            return False, f"unexpected stderr {completed.stderr!r}"
        if "safe build: OK (" in completed.stdout:
            return False, f"unexpected build banner in stdout {completed.stdout!r}"
    return True, ""


def run_safe_build_incremental_case() -> tuple[bool, str]:
    provider_text = """package provider_answer

   public subtype count is integer (0 to 100);
"""
    client_text = """with provider_answer;

subtype answer_count is provider_answer.count;
value : answer_count = 42;
print (value)
"""
    updated_provider_text = provider_text.replace("100", "50")

    with tempfile.TemporaryDirectory(prefix="safe-build-incremental-") as temp_root_str:
        temp_root = Path(temp_root_str)
        provider = temp_root / "provider_answer.safe"
        client = temp_root / "client_answer.safe"
        provider.write_text(provider_text, encoding="utf-8")
        client.write_text(client_text, encoding="utf-8")

        build = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build.returncode != 0:
            return False, f"initial build failed: {first_message(build)}"

        executable = temp_root / "obj" / "client_answer" / "target-64" / executable_name()
        emitted_client = temp_root / ".safe-build" / "target-64" / "ada" / "client_answer.adb"
        if not emitted_client.exists():
            return False, f"missing cached emitted unit {emitted_client}"
        if not executable.exists():
            return False, f"missing executable {executable}"

        run = run_command([str(executable)], cwd=executable.parent)
        if run.returncode != 0:
            return False, f"built executable failed: {first_message(run)}"
        if run.stdout != "42\n":
            return False, f"unexpected initial stdout {run.stdout!r}"

        emitted_mtime = emitted_client.stat().st_mtime_ns
        executable_mtime = executable.stat().st_mtime_ns

        build_cached = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build_cached.returncode != 0:
            return False, f"cached build failed: {first_message(build_cached)}"
        if emitted_client.stat().st_mtime_ns != emitted_mtime:
            return False, "cached build rewrote emitted Ada"
        if executable.stat().st_mtime_ns != executable_mtime:
            return False, "cached build rewrote executable"

        cached_text = emitted_client.read_text(encoding="utf-8")
        emitted_client.write_text("corrupted emitted Ada\n", encoding="utf-8")
        build_corrupt = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build_corrupt.returncode != 0:
            return False, f"artifact-recovery build failed: {first_message(build_corrupt)}"
        if emitted_client.read_text(encoding="utf-8") != cached_text:
            return False, "corrupted emitted Ada was not regenerated"

        provider.write_text(updated_provider_text, encoding="utf-8")
        build_updated = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build_updated.returncode != 0:
            return False, f"dependency-invalidated build failed: {first_message(build_updated)}"
        if emitted_client.stat().st_mtime_ns == emitted_mtime:
            return False, "dependency interface change did not re-emit client"
        run_updated = run_command([str(executable)], cwd=executable.parent)
        if run_updated.returncode != 0:
            return False, f"updated executable failed: {first_message(run_updated)}"
        if run_updated.stdout != "42\n":
            return False, f"unexpected updated stdout {run_updated.stdout!r}"

        clean_build = run_command([sys.executable, str(SAFE_CLI), "build", "--clean", client.name], cwd=temp_root)
        if clean_build.returncode != 0:
            return False, f"clean build failed: {first_message(clean_build)}"
        if not (temp_root / ".safe-build" / "target-64" / "state.json").exists():
            return False, "clean build did not recreate project cache"

    return True, ""

def run_safe_prove_incremental_case() -> tuple[bool, str]:
    provider_text = """package provider_constant

   public subtype count is integer (0 to 10);
   public max_count : constant count = 4;
"""
    client_text = """with provider_constant;

package client_constant

   subtype index is integer (0 to provider_constant.max_count);
"""
    updated_provider_text = provider_text.replace("4", "5")

    with tempfile.TemporaryDirectory(prefix="safe-prove-incremental-") as temp_root_str:
        temp_root = Path(temp_root_str)
        provider = temp_root / "provider_constant.safe"
        client = temp_root / "client_constant.safe"
        provider.write_text(provider_text, encoding="utf-8")
        client.write_text(client_text, encoding="utf-8")

        prove = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove.returncode != 0:
            return False, f"initial prove failed: {first_message(prove)}"
        if "safe prove: PASS" not in prove.stdout:
            return False, f"missing PASS verdict in initial prove {prove.stdout!r}"

        summary_path = safe_prove_summary_path(client, target_bits=64)
        if not summary_path.exists():
            return False, f"missing proof summary {summary_path}"
        summary_mtime = summary_path.stat().st_mtime_ns

        prove_cached = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove_cached.returncode != 0:
            return False, f"cached prove failed: {first_message(prove_cached)}"
        if summary_path.stat().st_mtime_ns != summary_mtime:
            return False, "cached prove reran GNATprove"

        proof_root = temp_root / "obj" / "client_constant" / "prove-64"
        shutil.rmtree(proof_root)
        prove_missing_artifacts = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove_missing_artifacts.returncode != 0:
            return False, f"artifact-recovery prove failed: {first_message(prove_missing_artifacts)}"
        if not summary_path.exists():
            return False, "proof cache miss did not recreate GNATprove summary"
        recreated_summary_mtime = summary_path.stat().st_mtime_ns
        if recreated_summary_mtime == summary_mtime:
            return False, "missing proof artifacts did not rerun GNATprove"
        summary_mtime = recreated_summary_mtime

        provider.write_text(updated_provider_text, encoding="utf-8")
        prove_updated = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove_updated.returncode != 0:
            return False, f"dependency-invalidated prove failed: {first_message(prove_updated)}"
        if summary_path.stat().st_mtime_ns == summary_mtime:
            return False, "dependency change did not rerun GNATprove"

    return True, ""


def run_target_bits_check_case(safec: Path) -> tuple[bool, str]:
    source_text = """subtype over is integer (0 to 2147483648);
"""

    with tempfile.TemporaryDirectory(prefix="safe-target-bits-check-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_check.safe"
        source.write_text(source_text, encoding="utf-8")

        check64 = run_command(
            [str(safec), "check", "--target-bits", "64", source.name],
            cwd=temp_root,
        )
        if check64.returncode != 0:
            return False, f"64-bit check failed: {first_message(check64)}"

        check32 = run_command(
            [str(safec), "check", "--target-bits", "32", source.name],
            cwd=temp_root,
        )
        if check32.returncode == 0:
            return False, "32-bit check unexpectedly succeeded"

    return True, ""


def run_target_bits_emit_contract_case(safec: Path) -> tuple[bool, str]:
    source_text = """package target_bits_emit

   public max_value : constant integer = 2147483647;
"""

    with tempfile.TemporaryDirectory(prefix="safe-target-bits-emit-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_emit.safe"
        source.write_text(source_text, encoding="utf-8")

        for bits in (32, 64):
            case_root = temp_root / f"emit-{bits}"
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
                    "--target-bits",
                    str(bits),
                    source.name,
                    "--out-dir",
                    str(out_dir),
                    "--interface-dir",
                    str(iface_dir),
                    "--ada-out-dir",
                    str(ada_dir),
                ],
                cwd=temp_root,
            )
            if emit.returncode != 0:
                return False, f"emit {bits}-bit failed: {first_message(emit)}"

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
                    source.name,
                ],
                cwd=REPO_ROOT,
            )
            if validate.returncode != 0:
                return False, f"validate_output_contracts failed for {bits}-bit emit: {first_message(validate)}"

            typed_payload = json.loads((out_dir / f"{stem}.typed.json").read_text(encoding="utf-8"))
            mir_payload = json.loads((out_dir / f"{stem}.mir.json").read_text(encoding="utf-8"))
            safei_payload = json.loads((iface_dir / f"{stem}.safei.json").read_text(encoding="utf-8"))
            if typed_payload.get("target_bits") != bits:
                return False, f"typed target_bits mismatch for {bits}-bit emit: {typed_payload.get('target_bits')!r}"
            if mir_payload.get("target_bits") != bits:
                return False, f"mir target_bits mismatch for {bits}-bit emit: {mir_payload.get('target_bits')!r}"
            if safei_payload.get("target_bits") != bits:
                return False, f"safei target_bits mismatch for {bits}-bit emit: {safei_payload.get('target_bits')!r}"

    return True, ""


def run_output_contract_target_bits_reject_case(safec: Path) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-target-bits-contract-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_contract.safe"
        source.write_text("print (0)\n", encoding="utf-8")
        out_dir = temp_root / "out"
        iface_dir = temp_root / "iface"
        ada_dir = temp_root / "ada"
        out_dir.mkdir(parents=True, exist_ok=True)
        iface_dir.mkdir(parents=True, exist_ok=True)
        ada_dir.mkdir(parents=True, exist_ok=True)

        emit = run_command(
            [
                str(safec),
                "emit",
                source.name,
                "--out-dir",
                str(out_dir),
                "--interface-dir",
                str(iface_dir),
                "--ada-out-dir",
                str(ada_dir),
            ],
            cwd=temp_root,
        )
        if emit.returncode != 0:
            return False, f"emit failed: {first_message(emit)}"

        stem = source.stem.lower()
        mir_path = out_dir / f"{stem}.mir.json"
        mir_payload = json.loads(mir_path.read_text(encoding="utf-8"))
        mir_payload["target_bits"] = 16
        mir_path.write_text(json.dumps(mir_payload, indent=2) + "\n", encoding="utf-8")

        validate = run_command(
            [
                sys.executable,
                str(VALIDATE_OUTPUT_CONTRACTS),
                "--ast",
                str(out_dir / f"{stem}.ast.json"),
                "--typed",
                str(out_dir / f"{stem}.typed.json"),
                "--mir",
                str(mir_path),
                "--safei",
                str(iface_dir / f"{stem}.safei.json"),
                "--source-path",
                source.name,
            ],
            cwd=REPO_ROOT,
        )
        if validate.returncode == 0:
            return False, "validate_output_contracts unexpectedly succeeded for invalid target_bits"
        output = validate.stderr or validate.stdout
        if "mir.json.target_bits must be 32 or 64" not in output:
            return False, f"missing target_bits validation message in {output!r}"

    return True, ""


def run_interface_target_bits_case(safec: Path) -> tuple[bool, str]:
    provider = REPO_ROOT / "tests" / "interfaces" / "provider_types.safe"
    client = REPO_ROOT / "tests" / "interfaces" / "client_types.safe"
    legacy_safei = REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safei.json"
    legacy_client = REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_receive_only.safe"

    with tempfile.TemporaryDirectory(prefix="safe-interface-target-bits-") as temp_root_str:
        temp_root = Path(temp_root_str)

        mismatch_root = temp_root / "mismatch"
        out_dir = mismatch_root / "out"
        iface_dir = mismatch_root / "iface"
        ada_dir = mismatch_root / "ada"
        out_dir.mkdir(parents=True, exist_ok=True)
        iface_dir.mkdir(parents=True, exist_ok=True)
        ada_dir.mkdir(parents=True, exist_ok=True)

        emit = run_command(
            [
                str(safec),
                "emit",
                "--target-bits",
                "64",
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
            return False, f"64-bit provider emit failed: {first_message(emit)}"

        mismatch = run_command(
            [
                str(safec),
                "check",
                "--target-bits",
                "32",
                repo_rel(client),
                "--interface-search-dir",
                str(iface_dir),
            ],
            cwd=REPO_ROOT,
        )
        if mismatch.returncode != DIAGNOSTIC_EXIT_CODE:
            return False, f"32-bit imported-interface mismatch unexpectedly returned {mismatch.returncode}: {first_message(mismatch)}"
        mismatch_output = mismatch.stderr or mismatch.stdout
        expected = "imported interface `provider_types` target_bits 64 does not match current target_bits 32"
        if expected not in mismatch_output:
            return False, f"missing target_bits mismatch diagnostic in {mismatch_output!r}"

        legacy_root = temp_root / "legacy"
        legacy_iface_dir = legacy_root / "iface"
        legacy_iface_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(legacy_safei, legacy_iface_dir / legacy_safei.name)

        legacy = run_command(
            [
                str(safec),
                "check",
                "--target-bits",
                "32",
                repo_rel(legacy_client),
                "--interface-search-dir",
                str(legacy_iface_dir),
            ],
            cwd=REPO_ROOT,
        )
        if legacy.returncode != DIAGNOSTIC_EXIT_CODE:
            return False, f"32-bit legacy interface unexpectedly returned {legacy.returncode}: {first_message(legacy)}"
        legacy_output = legacy.stderr or legacy.stdout
        expected_legacy = "imported interface `provider_transitive_channel` target_bits 64 does not match current target_bits 32"
        if expected_legacy not in legacy_output:
            return False, f"missing legacy target_bits mismatch diagnostic in {legacy_output!r}"

    return True, ""


def run_safe_build_target_bits_case() -> tuple[bool, str]:
    source_text = """value : integer = 7;
print (value)
"""

    with tempfile.TemporaryDirectory(prefix="safe-build-target-bits-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_build.safe"
        source.write_text(source_text, encoding="utf-8")

        for bits in (32, 64):
            build = run_command(
                [sys.executable, str(SAFE_CLI), "build", "--target-bits", str(bits), source.name],
                cwd=temp_root,
            )
            if build.returncode != 0:
                return False, f"{bits}-bit build failed: {first_message(build)}"
            executable = safe_build_executable(source, target_bits=bits)
            if not executable.exists():
                return False, f"missing {bits}-bit executable {executable}"
            run = run_command([str(executable)], cwd=executable.parent)
            if run.returncode != 0:
                return False, f"{bits}-bit executable failed: {first_message(run)}"
            if run.stdout != "7\n":
                return False, f"unexpected {bits}-bit stdout {run.stdout!r}"
            state_path = temp_root / ".safe-build" / f"target-{bits}" / "state.json"
            if not state_path.exists():
                return False, f"missing {bits}-bit project cache state {state_path}"

    return True, ""


def run_safe_prove_target_bits_case() -> tuple[bool, str]:
    source_text = """package target_bits_prove

   subtype count is integer (0 to 2147483647);
   value : constant count = 2147483647;
"""

    with tempfile.TemporaryDirectory(prefix="safe-prove-target-bits-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_prove.safe"
        source.write_text(source_text, encoding="utf-8")

        for bits in (32, 64):
            prove = run_command(
                [sys.executable, str(SAFE_CLI), "prove", "--target-bits", str(bits), source.name],
                cwd=temp_root,
            )
            if prove.returncode != 0:
                return False, f"{bits}-bit prove failed: {first_message(prove)}"
            summary_path = safe_prove_summary_path(source, target_bits=bits)
            if not summary_path.exists():
                return False, f"missing {bits}-bit proof summary {summary_path}"

        summary32 = safe_prove_summary_path(source, target_bits=32)
        mtime32 = summary32.stat().st_mtime_ns
        prove_cached = run_command(
            [sys.executable, str(SAFE_CLI), "prove", "--target-bits", "32", source.name],
            cwd=temp_root,
        )
        if prove_cached.returncode != 0:
            return False, f"cached 32-bit prove failed: {first_message(prove_cached)}"
        if summary32.stat().st_mtime_ns != mtime32:
            return False, "cached 32-bit prove reran GNATprove"

    return True, ""


def run_safe_prove_single_case(source: Path) -> tuple[bool, str]:
    clear_project_artifacts(source)
    completed = run_command(
        [sys.executable, str(SAFE_CLI), "prove", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        return False, f"safe prove failed: {first_message(completed)}"
    line = f"PASS {repo_rel(source)} ("
    if line not in completed.stdout:
        return False, f"missing PASS line {line!r}"
    if "flow total=" not in completed.stdout or "prove total=" not in completed.stdout:
        return False, f"missing proof summary in stdout {completed.stdout!r}"
    if "safe prove: PASS" not in completed.stdout:
        return False, f"missing final PASS verdict in stdout {completed.stdout!r}"
    if completed.stderr:
        return False, f"unexpected stderr {completed.stderr!r}"
    return True, ""


def run_safe_prove_directory_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-prove-dir-") as temp_root_str:
        temp_root = Path(temp_root_str)
        for source in PROVE_DIRECTORY_FIXTURES:
            shutil.copy2(source, temp_root / source.name)
        completed = run_command(
            [sys.executable, str(SAFE_CLI), "prove"],
            cwd=temp_root,
        )
        if completed.returncode != 0:
            return False, f"safe prove directory failed: {first_message(completed)}"
        lines = [line for line in completed.stdout.splitlines() if line.startswith("PASS ")]
        expected = [
            f"PASS {source.name} ("
            for source in sorted(PROVE_DIRECTORY_FIXTURES, key=lambda path: path.name)
        ]
        if len(lines) != len(expected):
            return False, f"unexpected PASS lines {lines!r}"
        for line, prefix in zip(lines, expected):
            if not line.startswith(prefix):
                return False, f"unexpected PASS order {lines!r}"
        if "2 passed, 0 failed" not in completed.stdout:
            return False, f"missing directory summary in stdout {completed.stdout!r}"
        if "safe prove: PASS" not in completed.stdout:
            return False, f"missing final PASS verdict in stdout {completed.stdout!r}"
        if completed.stderr:
            return False, f"unexpected stderr {completed.stderr!r}"
    return True, ""


def run_safe_prove_failure_case(*, verbose: bool) -> tuple[bool, str]:
    argv = [sys.executable, str(SAFE_CLI), "prove"]
    if verbose:
        argv.append("--verbose")
    argv.append(repo_rel(PROVE_FAILURE_SOURCE))
    completed = run_command(argv, cwd=REPO_ROOT)
    if completed.returncode == 0:
        return False, "safe prove unexpectedly succeeded"
    expected_stage = f"FAIL {repo_rel(PROVE_FAILURE_SOURCE)} [check]"
    if expected_stage not in completed.stdout:
        return False, f"missing stage line {expected_stage!r}"
    if "safe prove: FAIL" not in completed.stdout:
        return False, f"missing final FAIL verdict in stdout {completed.stdout!r}"
    if verbose:
        if "--- check output ---" not in completed.stderr:
            return False, f"missing verbose failure header in stderr {completed.stderr!r}"
        if PROVE_FAILURE_SOURCE.name not in completed.stderr:
            return False, f"missing failing source name in verbose stderr {completed.stderr!r}"
    elif completed.stderr:
        return False, f"unexpected stderr {completed.stderr!r}"
    return True, ""


def run_safe_prove_no_sources_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-prove-empty-") as temp_root_str:
        completed = run_command(
            [sys.executable, str(SAFE_CLI), "prove"],
            cwd=Path(temp_root_str),
        )
        if completed.returncode == 0:
            return False, "safe prove unexpectedly succeeded without sources"
        if "safe prove: no .safe files found in the current directory" not in completed.stderr:
            return False, f"missing empty-directory error in stderr {completed.stderr!r}"
        if completed.stdout:
            return False, f"unexpected stdout {completed.stdout!r}"
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


def run_vscode_surface_docs_case() -> tuple[bool, str]:
    readme = VSCODE_README.read_text(encoding="utf-8")
    metadata = json.loads(VSCODE_PACKAGE_JSON.read_text(encoding="utf-8"))

    if "PR11.8c.1 compiler surface" in readme:
        return False, "VS Code README still advertises the stale PR11.8c.1 surface"
    if "syntax-only" not in readme:
        return False, "VS Code README no longer states the syntax-only boundary"
    if "post-v1.0 language server" not in readme:
        return False, "VS Code README no longer states the disposable-language-server boundary"
    if "PR11.8i" not in readme:
        return False, "VS Code README no longer names the current shipped milestone surface"

    description = str(metadata.get("description", ""))
    if "PR11.8c.1" in description:
        return False, "VS Code package.json description still advertises PR11.8c.1"
    if "PR11.8i" not in description:
        return False, "VS Code package.json description no longer names the current shipped surface"
    return True, ""


def run_safe_deploy_reject_case(argv: list[str], expected_message: str) -> tuple[bool, str]:
    completed = run_command([sys.executable, str(SAFE_CLI), *argv], cwd=REPO_ROOT)
    if completed.returncode == 0:
        return False, "safe deploy unexpectedly succeeded"
    output = completed.stderr or completed.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""


def run_ast_contract_case(
    safec: Path,
    source: Path,
    *,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / f"ast-{source.stem}"
    case_root.mkdir(parents=True, exist_ok=True)
    ast_path = case_root / f"{source.stem.lower()}.ast.json"

    ast = run_command([str(safec), "ast", repo_rel(source)], cwd=REPO_ROOT)
    if ast.returncode != 0:
        return False, f"ast failed: {first_message(ast)}"
    ast_path.write_text(ast.stdout, encoding="utf-8")

    validate = run_command([sys.executable, str(VALIDATE_AST_OUTPUT), str(ast_path)], cwd=REPO_ROOT)
    if validate.returncode != 0:
        return False, first_message(validate)
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
    if label == "safei-bad-return-flag":
        subprograms[0]["return_is_access_def"] = "bad"
    elif label == "safei-template-source-key-on-non-generic":
        subprograms[0]["template_source"] = None
    else:
        return False, f"unknown output contract reject case {label}"
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
    def local_dependency_sources(root: Path) -> list[Path]:
        found: list[Path] = []
        seen: set[Path] = set()
        pending = [root]

        while pending:
            current = pending.pop()
            try:
                text = current.read_text(encoding="utf-8")
            except OSError:
                continue

            for line in text.splitlines():
                match = LOCAL_WITH_RE.match(line)
                if match is None:
                    continue
                candidate = current.parent / f"{match.group(1).split('.')[-1]}.safe"
                if candidate == root or not candidate.exists() or candidate in seen:
                    continue
                seen.add(candidate)
                found.append(candidate)
                pending.append(candidate)

        return found

    case_root = temp_root / f"{source.stem}-{label}"
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    dependencies = local_dependency_sources(source)
    for dependency in dependencies:
        dep_emit = run_command(
            [
                str(safec),
                "emit",
                repo_rel(dependency),
                "--out-dir",
                str(out_dir),
                "--interface-dir",
                str(iface_dir),
                "--interface-search-dir",
                str(iface_dir),
            ],
            cwd=REPO_ROOT,
        )
        if dep_emit.returncode != 0:
            raise RuntimeError(
                f"dependency emit failed for {repo_rel(dependency)}: "
                f"{first_message(dep_emit)}"
            )

    emit_args = [
        str(safec),
        "emit",
        repo_rel(source),
        "--out-dir",
        str(out_dir),
        "--interface-dir",
        str(iface_dir),
        "--ada-out-dir",
        str(ada_dir),
    ]
    if dependencies:
        emit_args.extend(["--interface-search-dir", str(iface_dir)])

    emit = run_command(emit_args, cwd=REPO_ROOT)
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


def normalize_snippet_whitespace(text: str) -> str:
    return " ".join(text.split())


def emitted_allowlisted_pragmas(ada_dir: Path) -> dict[str, set[str]]:
    occurrences: dict[str, set[str]] = {}

    for path in sorted(ada_dir.iterdir()):
        if path.suffix not in {".adb", ".ads"}:
            continue
        emitted_text = path.read_text(encoding="utf-8")
        for match in EMITTED_GNATPROVE_WARNING_RE.findall(emitted_text):
            snippet = normalize_snippet_whitespace(match)
            occurrences.setdefault(snippet, set()).add(path.name)
        for match in EMITTED_ASSUME_RE.findall(emitted_text):
            snippet = normalize_snippet_whitespace(match)
            occurrences.setdefault(snippet, set()).add(path.name)

    return occurrences


def run_emitted_pragma_allowlist_case(
    safec: Path,
    *,
    label: str,
    source: Path,
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

    occurrences = emitted_allowlisted_pragmas(ada_dir)
    unexpected = sorted(set(occurrences) - EMITTED_PRAGMA_ALLOWLIST)
    if not unexpected:
        return True, ""

    details = []
    for snippet in unexpected:
        files = ", ".join(sorted(occurrences[snippet]))
        details.append(f"{snippet!r} in {files}")
    return False, "unexpected emitted pragma(s): " + "; ".join(details)


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


def run_proof_inventory_coverage_case() -> tuple[bool, str]:
    covered = set(EMITTED_PROOF_COVERED_PATHS)
    uncovered = [
        entry
        for entry in iter_proof_coverage_paths(REPO_ROOT)
        if entry not in covered
    ]
    if uncovered:
        return (
            False,
            "fixtures under proof coverage roots missing from proof inventory: "
            + ", ".join(uncovered),
        )
    return True, ""


def run_proof_eval_message_priority_case() -> tuple[bool, str]:
    completed = subprocess.CompletedProcess(
        args=["dummy"],
        returncode=1,
        stdout="tool: error: real failure\n",
        stderr="wrapper warning: noisy wrapper prefix\n",
    )
    detail = proof_eval_first_message(completed)
    if detail != "tool: error: real failure":
        return False, f"unexpected prioritized detail {detail!r}"
    return True, ""


def run_proof_eval_clean_nonzero_case() -> tuple[bool, str]:
    completed = subprocess.CompletedProcess(
        args=["dummy"],
        returncode=1,
        stdout="",
        stderr="unit.ads:1:1: info: assertion proved\n",
    )
    total_row = {
        "total": {"count": 1, "detail": ""},
        "flow": {"count": 0, "detail": ""},
        "provers": {"count": 1, "detail": ""},
        "justified": {"count": 0, "detail": ""},
        "unproved": {"count": 0, "detail": ""},
    }
    if not allow_clean_nonzero_gnatprove_exit(completed, total_row):
        return False, "expected info-only nonzero GNATprove exit to be accepted"
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
    skipped = 0
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
        if fixture in NEGATIVE_SKIPPED_FIXTURES:
            skipped += 1
            continue
        expected_returncode = DIAGNOSTIC_EXIT_CODE
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

    for fixture in CHECK_SUCCESS_CASES:
        ok, detail = check_fixture(safec, fixture, expected_returncode=0)
        if ok:
            passed += 1
        else:
            failures.append((repo_rel(fixture), detail))

    ok, detail = run_proof_inventory_coverage_case()
    if ok:
        passed += 1
    else:
        failures.append(("proof-inventory-coverage", detail))

    ok, detail = run_proof_eval_message_priority_case()
    if ok:
        passed += 1
    else:
        failures.append(("proof-eval-message-priority", detail))

    ok, detail = run_proof_eval_clean_nonzero_case()
    if ok:
        passed += 1
    else:
        failures.append(("proof-eval-clean-nonzero", detail))

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

        for label, provider, client, expected_message in INTERFACE_REJECT_CASES:
            ok, detail = run_interface_reject_case(
                safec,
                label=label,
                provider=provider,
                client=client,
                expected_message=expected_message,
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


        for source in AST_CONTRACT_CASES:
            ok, detail = run_ast_contract_case(safec, source, temp_root=temp_root)
            label = f"ast-contract:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((label, detail))

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

        ok, detail = run_output_contract_target_bits_reject_case(safec)
        if ok:
            passed += 1
        else:
            failures.append(("contracts-reject:target-bits", detail))

        ok, detail = run_target_bits_emit_contract_case(safec)
        if ok:
            passed += 1
        else:
            failures.append(("target-bits emit contract", detail))

        ok, detail = run_target_bits_check_case(safec)
        if ok:
            passed += 1
        else:
            failures.append(("target-bits check", detail))

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

        for fixture in EMITTED_PROOF_FIXTURES:
            source = REPO_ROOT / fixture
            ok, detail = run_emitted_pragma_allowlist_case(
                safec,
                label="pragma-allowlist",
                source=source,
                temp_root=temp_root,
            )
            case_label = f"emitted-pragma-allowlist:{repo_rel(source)}"
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

    ok, detail = run_safe_run_mutated_iterable_case()
    if ok:
        passed += 1
    else:
        failures.append(("safe run mutated iterable", detail))

    ok, detail = run_safe_build_incremental_case()
    if ok:
        passed += 1
    else:
        failures.append(("safe build incremental", detail))

    ok, detail = run_interface_target_bits_case(safec)
    if ok:
        passed += 1
    else:
        failures.append(("interface target_bits", detail))

    ok, detail = run_safe_build_target_bits_case()
    if ok:
        passed += 1
    else:
        failures.append(("safe build target bits", detail))

    for argv, expected in (
        (["--help"], ["safe build [--clean]", "--target-bits", "safe deploy", "safe run", "safe prove"]),
        (["deploy", "--help"], ["--board", "--simulate", "--watch-symbol", "--expect-value"]),
    ):
        ok, detail = run_safe_cli_help_case(argv, expected)
        label = f"safe cli help {' '.join(argv)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    ok, detail = run_vscode_surface_docs_case()
    if ok:
        passed += 1
    else:
        failures.append(("vscode surface docs", detail))

    for argv, expected_message in DEPLOY_REJECT_ARGV_CASES:
        ok, detail = run_safe_deploy_reject_case(argv, expected_message)
        label = f"safe {' '.join(argv)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for source in (PROVE_SINGLE_SUCCESS_SOURCE, PROVE_IMPORTED_SUCCESS_SOURCE):
        ok, detail = run_safe_prove_single_case(source)
        label = f"safe prove {repo_rel(source)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    ok, detail = run_safe_prove_incremental_case()
    if ok:
        passed += 1
    else:
        failures.append(("safe prove incremental", detail))

    ok, detail = run_safe_prove_target_bits_case()
    if ok:
        passed += 1
    else:
        failures.append(("safe prove target bits", detail))

    for label, verbose in (
        ("safe prove current directory", False),
        ("safe prove failure stage", False),
        ("safe prove verbose failure", True),
    ):
        if label == "safe prove current directory":
            ok, detail = run_safe_prove_directory_case()
        else:
            ok, detail = run_safe_prove_failure_case(verbose=verbose)
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    ok, detail = run_safe_prove_no_sources_case()
    if ok:
        passed += 1
    else:
        failures.append(("safe prove empty directory", detail))

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

    print_summary(passed=passed, skipped=skipped, failures=failures)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
