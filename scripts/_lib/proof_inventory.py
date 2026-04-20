#!/usr/bin/env python3
"""Shared emitted-proof inventory for blocking proof coverage."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class EmittedProofExclusion:
    path: str
    reason: str
    owner: str
    milestone: str


PROOF_COVERAGE_ROOTS = (
    "tests/positive",
    "tests/build",
    "tests/concurrency",
)
# `tests/interfaces` contains provider/client halves and intentional rejection
# fixtures, so proof-bearing interface roots must be enrolled explicitly below.


COMPANION_PROJECTS = [
    ("companion/gen", "companion.gpr"),
    ("companion/templates", "templates.gpr"),
]


PR11_8A_CHECKPOINT_FIXTURES = [
    "tests/positive/rule1_accumulate.safe",
    "tests/positive/rule1_averaging.safe",
    "tests/positive/rule1_conversion.safe",
    "tests/positive/rule1_parameter.safe",
    "tests/positive/rule1_return.safe",
    "tests/positive/rule2_binary_search.safe",
    "tests/positive/rule2_binary_search_function.safe",
    "tests/positive/rule2_iteration.safe",
    "tests/positive/rule2_lookup.safe",
    "tests/positive/rule2_matrix.safe",
    "tests/positive/rule2_slice.safe",
    "tests/positive/rule3_average.safe",
    "tests/positive/rule3_divide.safe",
    "tests/positive/rule3_modulo.safe",
    "tests/positive/rule3_percent.safe",
    "tests/positive/rule3_remainder.safe",
    "tests/positive/rule5_filter.safe",
    "tests/positive/rule5_interpolate.safe",
    "tests/positive/rule5_normalize.safe",
    "tests/positive/rule5_statistics.safe",
    "tests/positive/rule5_temperature.safe",
    "tests/positive/rule5_vector_normalize.safe",
    "tests/positive/constant_range_bound.safe",
    "tests/positive/constant_channel_capacity.safe",
    "tests/positive/constant_task_priority.safe",
    "tests/positive/pr112_character_case.safe",
    "tests/positive/pr112_discrete_case.safe",
    "tests/positive/pr112_string_param.safe",
    "tests/positive/pr112_case_scrutinee_once.safe",
    "tests/positive/pr113_discriminant_constraints.safe",
    "tests/positive/pr113_tuple_destructure.safe",
    "tests/positive/pr113_structured_result.safe",
    "tests/positive/pr113_variant_guard.safe",
    "tests/positive/pr214_enum_variant_guard.safe",
    "tests/positive/constant_discriminant_default.safe",
    "tests/positive/result_equality_check.safe",
    "tests/positive/result_guarded_access.safe",
    "tests/positive/pr118_inline_integer_return.safe",
    "tests/positive/pr118_type_range_equivalent.safe",
]


PR11_8B_CHECKPOINT_FIXTURES = [
    "tests/concurrency/channel_ceiling_priority.safe",
    "tests/positive/channel_pipeline.safe",
    "tests/concurrency/exclusive_variable.safe",
    "tests/concurrency/fifo_ordering.safe",
    "tests/concurrency/multi_task_channel.safe",
    "tests/concurrency/select_delay_local_scope.safe",
    "tests/concurrency/select_priority.safe",
    "tests/concurrency/task_global_owner.safe",
    "tests/concurrency/task_priority_delay.safe",
    "tests/concurrency/try_ops.safe",
    "tests/positive/pr113_tuple_channel.safe",
]


PR11_8E_CHECKPOINT_FIXTURES = [
    "tests/positive/ownership_move.safe",
    "tests/positive/ownership_early_return.safe",
    "tests/positive/pr118e_not_null_self_reference.safe",
    "tests/positive/pr118e1_mutual_record_family.safe",
    "tests/positive/pr118e2_disjoint_mut_borrow_fields.safe",
    "tests/concurrency/pr118c2_pre_task_init.safe",
]


PR11_8F_CHECKPOINT_FIXTURES = [
    "tests/positive/rule4_conditional.safe",
    "tests/positive/rule4_deref.safe",
    "tests/positive/rule4_factory.safe",
    "tests/positive/rule4_linked_list.safe",
    "tests/positive/rule4_linked_list_sum.safe",
    "tests/positive/rule4_optional.safe",
    "tests/positive/ownership_borrow.safe",
    "tests/positive/ownership_observe.safe",
    "tests/positive/ownership_observe_access.safe",
    "tests/positive/ownership_return.safe",
    "tests/positive/ownership_inout.safe",
]


PR11_8G1_CHECKPOINT_FIXTURES = [
    "tests/positive/pr09_emitter_discriminant.safe",
    "tests/positive/pr115_compound_terminators.safe",
    "tests/positive/pr115_declare_terminator.safe",
    "tests/positive/pr115_legacy_local_decl.safe",
    "tests/positive/pr115_multiline_return.safe",
    "tests/positive/pr1162_empty_subprogram_body_followed_by_sibling.safe",
    "tests/positive/pr116_bare_return.safe",
    "tests/positive/pr118c_binary_case_dispatch.safe",
    "tests/positive/pr118d_bounded_string_array_component.safe",
    "tests/positive/pr118d_bounded_string_field.safe",
    "tests/positive/pr118d_string_equality.safe",
    "tests/positive/pr118e1_not_null_mutual_family.safe",
    "tests/positive/pr118e1_three_type_family.safe",
    "tests/concurrency/pr118b1_partial_task_clauses.safe",
    "tests/concurrency/pr118b1_scoped_receive.safe",
    "tests/concurrency/pr118b1_scoped_try_receive.safe",
    "tests/concurrency/pr118b1_transitive_local_task_clause.safe",
    "tests/build/pr118c2_package_pre_task.safe",
    "tests/build/pr118d1_for_of_string_build.safe",
    "tests/build/pr118d1_string_case_build.safe",
    "tests/build/pr118d1_string_order_build.safe",
    "tests/build/pr118d_bounded_string_array_component_build.safe",
    "tests/build/pr118d_bounded_string_index_build.safe",
    "tests/build/pr118d_bounded_string_tick_build.safe",
    "tests/build/pr118d_for_of_fixed_build.safe",
    "tests/build/pr118d_for_of_growable_build.safe",
    "tests/build/pr118d_for_of_heap_element_build.safe",
]


PR11_8G2_CHECKPOINT_FIXTURES = [
    "tests/positive/pr118c1_print.safe",
    "tests/positive/pr118d_bounded_string.safe",
    "tests/positive/pr118d_character_quote_literal.safe",
    "tests/positive/pr118d_growable_array.safe",
    "tests/positive/pr118d_string_length_attribute.safe",
    "tests/positive/pr118d_string_mutable_object.safe",
    "tests/build/pr118d1_growable_to_fixed_guard_build.safe",
    "tests/build/pr118d_bounded_string_build.safe",
    "tests/build/pr118d_bounded_string_field_build.safe",
    "tests/build/pr118d_fixed_to_growable_build.safe",
    "tests/build/pr118d_growable_to_fixed_literal_build.safe",
    "tests/build/pr118d_growable_to_fixed_slice_build.safe",
    "tests/build/pr118g_string_channel_build.safe",
    "tests/build/pr118g_growable_channel_build.safe",
    "tests/build/pr118g_tuple_string_channel_build.safe",
    "tests/build/pr118g_record_string_channel_build.safe",
    "tests/build/pr118g_try_string_channel_build.safe",
]


PR11_8I_CHECKPOINT_FIXTURES = [
    "tests/build/pr118i_enum_build.safe",
]


PR11_8K_CHECKPOINT_FIXTURES = [
    "tests/positive/pr118k_try_propagation.safe",
    "tests/positive/pr118k_match.safe",
    "tests/build/pr118k_try_build.safe",
    "tests/build/pr118k_try_arg_order_build.safe",
]


PR11_10A_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1110a_optional_guarded.safe",
    "tests/build/pr1110a_optional_string_build.safe",
    "tests/build/pr1110a_optional_growable_build.safe",
]


PR11_10B_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1110b_list_basics.safe",
    "tests/positive/pr1110b_disjoint_mut_indices.safe",
    "tests/build/pr1110b_list_build.safe",
    "tests/build/pr1110b_list_string_build.safe",
    "tests/build/pr1110b_list_growable_build.safe",
]


PR11_10C_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1110c_map_basics.safe",
    "tests/build/pr1110c_map_build.safe",
    "tests/build/pr1110c_map_string_build.safe",
    "tests/build/pr1110c_map_list_build.safe",
]


PR11_10D_CHECKPOINT_FIXTURES = (
    PR11_10A_CHECKPOINT_FIXTURES
    + PR11_10B_CHECKPOINT_FIXTURES
    + PR11_10C_CHECKPOINT_FIXTURES
)


PR11_11A_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1111a_method_syntax.safe",
    "tests/positive/pr1111a_method_append_overload.safe",
    "tests/build/pr1111a_builtin_methods_build.safe",
]


PR11_11B_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1111b_interface_local.safe",
    "tests/build/pr1111b_interface_builtin_build.safe",
]


PR11_11C_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1111c_generic_basics.safe",
    "tests/positive/pr1111c_generic_constraint.safe",
    "tests/build/pr1111c_generic_build.safe",
    "tests/build/pr1111c_provider_build.safe",
    "tests/build/pr1111c_imported_build.safe",
    "tests/build/pr1111c_provider_collision_left.safe",
    "tests/build/pr1111c_provider_collision_right.safe",
    "tests/build/pr1111c_provider_alias.safe",
    "tests/build/pr1111c_imported_alias_and_collision_build.safe",
]


PR11_12A_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1112a_shared_field_access.safe",
    "tests/build/pr1112a_shared_task_build.safe",
]


PR11_12B_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1112b_shared_snapshot.safe",
    "tests/build/pr1112b_shared_update_build.safe",
]


PR11_12C_CHECKPOINT_FIXTURES = [
    "tests/build/pr1112c_shared_string_build.safe",
    "tests/build/pr1112c_shared_container_fields_build.safe",
    "tests/build/pr1112c_layered_growable_type_build.safe",
    "tests/build/pr1122f2_shared_bounded_string_field_build.safe",
    "tests/build/pr1122f2_shared_optional_string_none_build.safe",
]


PR11_12D_CHECKPOINT_FIXTURES = [
    "tests/build/pr1112d_shared_list_root_build.safe",
    "tests/build/pr1112d_shared_map_root_build.safe",
    "tests/build/pr1112d_shared_map_indexed_remove_build.safe",
    "tests/build/pr1112d_shared_growable_root_build.safe",
]


PR11_12E_CHECKPOINT_FIXTURES = [
    "tests/build/pr1112e_provider_shared_record.safe",
    "tests/build/pr1112e_provider_shared_list.safe",
    "tests/build/pr1112e_provider_shared_map.safe",
    "tests/build/pr1112e_imported_shared_record_build.safe",
    "tests/build/pr1112e_imported_shared_list_build.safe",
    "tests/build/pr1112e_imported_shared_map_build.safe",
]


PR11_12F_CHECKPOINT_FIXTURES = [
    "tests/build/pr1112f_shared_record_ceiling_build.safe",
    "tests/build/pr1112f_shared_container_ceiling_build.safe",
    "tests/build/pr1112f_mixed_channel_shared_build.safe",
    "tests/interfaces/provider_shared_ceiling.safe",
]


PR11_12_CHECKPOINT_FIXTURES = (
    PR11_12A_CHECKPOINT_FIXTURES
    + PR11_12B_CHECKPOINT_FIXTURES
    + PR11_12C_CHECKPOINT_FIXTURES
    + PR11_12D_CHECKPOINT_FIXTURES
    + PR11_12E_CHECKPOINT_FIXTURES
    + PR11_12F_CHECKPOINT_FIXTURES
)


PR11_13A_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1113a_sum_construction.safe",
    "tests/build/pr1113a_sum_build.safe",
]

PR11_13B_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1113b_sum_match.safe",
    "tests/build/pr1113b_sum_match_build.safe",
]

PR11_13C_CHECKPOINT_FIXTURES = [
    "tests/build/pr1113c_provider_shape.safe",
    "tests/build/pr1113c_provider_message.safe",
    "tests/build/pr1113c_provider_device.safe",
    "tests/build/pr1113c_provider_job.safe",
    "tests/build/pr1113c_imported_sum_build.safe",
    "tests/build/pr1113c_imported_string_sum_build.safe",
    "tests/build/pr1113c_imported_overlap_build.safe",
]

PR11_13_CHECKPOINT_FIXTURES = (
    PR11_13A_CHECKPOINT_FIXTURES
    + PR11_13B_CHECKPOINT_FIXTURES
    + PR11_13C_CHECKPOINT_FIXTURES
)


PR11_16_CHECKPOINT_FIXTURES = [
    "tests/positive/pr1116_nominal_integer.safe",
    "tests/build/pr1116_nominal_integer_build.safe",
    "tests/build/pr1116_provider_nominal.safe",
    "tests/build/pr1116_imported_nominal_build.safe",
]


PR11_8I1_CHECKPOINT_FIXTURES = [
    "tests/positive/pr115_case_terminator.safe",
    "tests/positive/pr115_var_basic.safe",
    "tests/positive/pr1162_empty_select_delay_arm.safe",
    "tests/positive/pr118c1_print_boolean.safe",
    "tests/positive/pr118c1_print_integer.safe",
    "tests/positive/pr118c1_print_string.safe",
    "tests/positive/pr118c2_entry_print.safe",
    "tests/positive/pr118c2_package_print.safe",
    "tests/positive/pr118c_binary_boolean_logic.safe",
    "tests/positive/pr118c_binary_conversion_wrap.safe",
    "tests/positive/pr118c_binary_inline_object.safe",
    "tests/positive/pr118c_binary_named_type.safe",
    "tests/positive/pr118c_binary_param_return.safe",
    "tests/positive/pr118c_binary_shift.safe",
    "tests/positive/pr118d_string_out_param.safe",
    "tests/positive/pr118e2_disjoint_mut_fields.safe",
    "tests/positive/pr118e2_nested_disjoint_fields.safe",
    "tests/positive/pr118i_enum_basics.safe",
    "tests/positive/pr118i_enum_composites.safe",
    "tests/concurrency/pr118c1_task_print.safe",
    "tests/concurrency/pr118g_string_channel.safe",
    "tests/concurrency/pr118g_tuple_string_channel.safe",
    "tests/build/pr118c2_entry_build.safe",
    "tests/build/pr118c2_package_build.safe",
    "tests/build/pr118d_empty_growable_array_literal_build.safe",
    "tests/build/pr118d_growable_array_build.safe",
    "tests/build/pr118d_growable_array_component_runtime_build.safe",
    "tests/build/pr118d_growable_field_runtime_build.safe",
    "tests/build/pr118d_growable_param_runtime_build.safe",
    "tests/build/pr118d_growable_result_runtime_build.safe",
    "tests/build/pr118d_runtime_self_assign_build.safe",
    "tests/build/pr118d_string_array_component_runtime_build.safe",
    "tests/build/pr118d_string_field_runtime_build.safe",
    "tests/build/pr118d_string_plain_build.safe",
    "tests/build/pr118d_tuple_string_build.safe",
    "tests/build/pr118d_nested_growable_array_literal_build.safe",
    "tests/build/pr118e1_mutual_family_build.safe",
    "tests/positive/pr118e1_mutual_move_borrow.safe",
]


# All PR11.23a-i proof-expansion burn-down fixtures accumulate here.
PR11_23_PROOF_EXPANSION_FIXTURES = [
    "tests/build/pr1123a_binary_wraparound_build.safe",
    "tests/build/pr1123b_while_variant_patterns_build.safe",
    "tests/build/pr213_map_entry_build.safe",
    "tests/build/pr1123d_conditional_string_growth_build.safe",
    "tests/build/pr1123e_multi_accumulator_build.safe",
    "tests/build/pr1123f_sum_count_relational_build.safe",
    "tests/build/pr1123g_nested_iteration_build.safe",
    "tests/build/pr1123h_shared_call_argument_snapshot_build.safe",
    "tests/build/pr1123i_clamp_provider.safe",
    "tests/build/pr1123i_exported_postconditions_build.safe",
]


EMITTED_PROOF_REGRESSION_FIXTURES = [
    "tests/concurrency/select_with_delay.safe",
    "tests/concurrency/select_with_delay_multiarm.safe",
    "tests/positive/channel_pingpong.safe",
    "tests/positive/channel_pipeline_compute.safe",
    "tests/positive/constant_access_deref_write.safe",
    "tests/positive/constant_shadow_mutable.safe",
    "tests/positive/emitter_surface_proc.safe",
    "tests/positive/emitter_surface_record.safe",
    "tests/positive/pr222_readonly_global_function.safe",
    "tests/positive/pr1122f1_multi_decl_object.safe",
    "tests/positive/pr331_shared_initializer_alone.safe",
    "tests/positive/pr331_package_initializer_task_pollution.safe",
    "tests/interfaces/provider_transitive_global.safe",
    "tests/build/pr212_string_literal_build.safe",
    "tests/build/pr223_provider_enum.safe",
    "tests/build/pr223_imported_enum_comparison_build.safe",
    "tests/build/pr226_remainder_boolean_build.safe",
    "tests/build/pr227_public_shared_snapshot_order_build.safe",
    "tests/build/pr227_shared_snapshot_order_build.safe",
    "tests/build/pr228_shared_field_condition_build.safe",
    "tests/build/pr228_provider_shared_condition.safe",
    "tests/build/pr228_imported_shared_condition_build.safe",
    "tests/build/pr228_shared_loop_exit_condition_build.safe",
    "tests/build/pr225_maker.safe",
    "tests/build/pr225_imported_string_literal_build.safe",
    "tests/build/pr224_provider_printable.safe",
    "tests/build/pr224_imported_generic_string_aggregate_build.safe",
    "tests/build/pr119d_send_single_eval_build.safe",
    "tests/build/pr230_top_level_select_delay_build.safe",
    "tests/build/pr232_provider_numeric.safe",
    "tests/build/pr232_imported_numeric_elab_build.safe",
    "tests/build/pr331_shared_initializer_effect_pollution_build.safe",
    "tests/positive/pr231_fixed_literal_for_of_sum.safe",
    "tests/positive/pr233_bounded_index_counted_loop.safe",
    "tests/build/pr220_for_of_composite_unroll_build.safe",
    "tests/build/pr1110b_list_empty_build.safe",
    "tests/positive/pr221_for_of_tuple_helper.safe",
    "tests/positive/pr221_for_of_discriminated_helper.safe",
    "tests/interfaces/pr119a_select_delay_receive.safe",
    "tests/interfaces/pr119a_select_delay_timeout.safe",
    "tests/interfaces/pr119a_select_zero_delay_ready.safe",
]


EMITTED_PROOF_FIXTURES = (
    PR11_8A_CHECKPOINT_FIXTURES
    + PR11_8B_CHECKPOINT_FIXTURES
    + PR11_8E_CHECKPOINT_FIXTURES
    + PR11_8F_CHECKPOINT_FIXTURES
    + PR11_8G1_CHECKPOINT_FIXTURES
    + PR11_8G2_CHECKPOINT_FIXTURES
    + PR11_8I_CHECKPOINT_FIXTURES
    + PR11_8I1_CHECKPOINT_FIXTURES
    + PR11_8K_CHECKPOINT_FIXTURES
    + PR11_10A_CHECKPOINT_FIXTURES
    + PR11_10B_CHECKPOINT_FIXTURES
    + PR11_10C_CHECKPOINT_FIXTURES
    + PR11_11A_CHECKPOINT_FIXTURES
    + PR11_11B_CHECKPOINT_FIXTURES
    + PR11_11C_CHECKPOINT_FIXTURES
    + PR11_12A_CHECKPOINT_FIXTURES
    + PR11_12B_CHECKPOINT_FIXTURES
    + PR11_12C_CHECKPOINT_FIXTURES
    + PR11_12D_CHECKPOINT_FIXTURES
    + PR11_12E_CHECKPOINT_FIXTURES
    + PR11_12F_CHECKPOINT_FIXTURES
    + PR11_13A_CHECKPOINT_FIXTURES
    + PR11_13B_CHECKPOINT_FIXTURES
    + PR11_13C_CHECKPOINT_FIXTURES
    + PR11_16_CHECKPOINT_FIXTURES
    + PR11_23_PROOF_EXPANSION_FIXTURES
    + EMITTED_PROOF_REGRESSION_FIXTURES
)


EMITTED_PROOF_EXCLUSIONS = [
    EmittedProofExclusion(
        path="tests/concurrency/channel_access_type.safe",
        reason="reference-bearing channel element; frontend-rejected by value-only channel legality",
        owner="spec-excluded",
        milestone="PR11.8i.1",
    ),
    EmittedProofExclusion(
        path="tests/concurrency/select_ownership_binding.safe",
        reason="reference-bearing channel element; frontend-rejected by value-only channel legality",
        owner="spec-excluded",
        milestone="PR11.8i.1",
    ),
    EmittedProofExclusion(
        path="tests/concurrency/try_send_ownership.safe",
        reason="reference-bearing channel element; frontend-rejected by value-only channel legality",
        owner="spec-excluded",
        milestone="PR11.8i.1",
    ),
    EmittedProofExclusion(
        path="tests/build/pr118c2_root_with_clause.safe",
        reason="intentional tooling reject fixture with missing dependency interface; not an admitted emitted proof target",
        owner="tooling-reject-case",
        milestone="PR11.8i.1",
    ),
]


EXCLUDED_PROOF_PATHS = {entry.path for entry in EMITTED_PROOF_EXCLUSIONS}
EMITTED_PROOF_COVERED_PATHS = set(EMITTED_PROOF_FIXTURES) | EXCLUDED_PROOF_PATHS


def iter_proof_coverage_paths(repo_root: Path) -> list[str]:
    paths: list[str] = []
    for root in PROOF_COVERAGE_ROOTS:
        for path in sorted((repo_root / root).rglob("*.safe")):
            paths.append(str(path.relative_to(repo_root)))
    return paths
