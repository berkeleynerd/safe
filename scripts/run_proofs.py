#!/usr/bin/env python3
"""Run the live all-proved-only Safe proof workflow."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

from _lib.proof_eval import (
    ProofToolchain,
    prepare_proof_toolchain,
    run_gnatprove_project,
    run_source_proof,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"

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

EMITTED_PROOF_REGRESSION_FIXTURES = [
    "tests/concurrency/select_with_delay.safe",
    "tests/concurrency/select_with_delay_multiarm.safe",
    "tests/positive/channel_pingpong.safe",
    "tests/positive/channel_pipeline_compute.safe",
    "tests/positive/constant_access_deref_write.safe",
    "tests/positive/constant_shadow_mutable.safe",
    "tests/positive/emitter_surface_proc.safe",
    "tests/positive/emitter_surface_record.safe",
]

EMITTED_PROOF_FIXTURES = (
    PR11_8A_CHECKPOINT_FIXTURES
    + PR11_8B_CHECKPOINT_FIXTURES
    + PR11_8E_CHECKPOINT_FIXTURES
    + PR11_8F_CHECKPOINT_FIXTURES
    + PR11_8G1_CHECKPOINT_FIXTURES
    + PR11_8G2_CHECKPOINT_FIXTURES
    + PR11_8I_CHECKPOINT_FIXTURES
    + EMITTED_PROOF_REGRESSION_FIXTURES
)


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def validate_manifest(
    name: str,
    entries: list[str],
    *,
    allow_missing: bool = False,
) -> None:
    seen: set[str] = set()
    duplicates: list[str] = []
    missing: list[str] = []

    for entry in entries:
        if entry in seen:
            duplicates.append(entry)
        else:
            seen.add(entry)
        if not allow_missing and not (REPO_ROOT / entry).exists():
            missing.append(entry)

    if duplicates:
        raise RuntimeError(f"{name} has duplicate entries: {', '.join(duplicates)}")
    if missing:
        raise RuntimeError(f"{name} has missing entries: {', '.join(missing)}")


def validate_manifests() -> None:
    validate_manifest("PR11.8a checkpoint manifest", PR11_8A_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8b checkpoint manifest", PR11_8B_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8e checkpoint manifest", PR11_8E_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8f checkpoint manifest", PR11_8F_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8g.1 checkpoint manifest", PR11_8G1_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8g.2 checkpoint manifest", PR11_8G2_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8i checkpoint manifest", PR11_8I_CHECKPOINT_FIXTURES)
    validate_manifest("emitted proof regression manifest", EMITTED_PROOF_REGRESSION_FIXTURES)
    validate_manifest("emitted proof manifest", EMITTED_PROOF_FIXTURES)

def run_companion_project(
    *,
    project_dir: Path,
    project_file: str,
    toolchain: ProofToolchain,
) -> tuple[bool, str]:
    return run_gnatprove_project(
        project_dir=project_dir,
        project_file=project_file,
        toolchain=toolchain,
    )


def print_summary(
    *,
    passed: int,
    failures: list[tuple[str, str]],
    title: str | None = None,
    trailing_blank_line: bool = False,
) -> None:
    prefix = f"{title}: " if title is not None else ""
    print(f"{prefix}{passed} proved, {len(failures)} failed")
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")
    if trailing_blank_line:
        print()


def run_fixture_group(
    *,
    fixtures: list[str],
    temp_root: Path,
    toolchain: ProofToolchain,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
) -> tuple[int, list[tuple[str, str]]]:
    passed = 0
    failures: list[tuple[str, str]] = []

    for fixture_rel in fixtures:
        source = REPO_ROOT / fixture_rel
        result = run_source_proof(
            toolchain=toolchain,
            source=source,
            proof_root=temp_root / source.stem,
            run_check=False,
            prove_switches=prove_switches,
            command_timeout=command_timeout,
        )
        if result.passed:
            passed += 1
        else:
            failures.append((fixture_rel, result.detail))

    return passed, failures


def main() -> int:
    try:
        validate_manifests()
        toolchain = prepare_proof_toolchain(env=os.environ.copy())
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_proofs: ERROR: {exc}", file=sys.stderr)
        return 1

    companion_passed = 0
    companion_failures: list[tuple[str, str]] = []
    checkpoint_a_passed = 0
    checkpoint_a_failures: list[tuple[str, str]] = []
    checkpoint_b_passed = 0
    checkpoint_b_failures: list[tuple[str, str]] = []
    checkpoint_e_passed = 0
    checkpoint_e_failures: list[tuple[str, str]] = []
    checkpoint_f_passed = 0
    checkpoint_f_failures: list[tuple[str, str]] = []
    checkpoint_g1_passed = 0
    checkpoint_g1_failures: list[tuple[str, str]] = []
    checkpoint_g2_passed = 0
    checkpoint_g2_failures: list[tuple[str, str]] = []
    regression_passed = 0
    regression_failures: list[tuple[str, str]] = []

    for project_rel, project_file in COMPANION_PROJECTS:
        project_dir = REPO_ROOT / project_rel
        ok, detail = run_companion_project(
            project_dir=project_dir,
            project_file=project_file,
            toolchain=toolchain,
        )
        if ok:
            companion_passed += 1
        else:
            companion_failures.append((project_rel, detail))

    with tempfile.TemporaryDirectory(prefix="safe-proofs-") as temp_root_str:
        temp_root = Path(temp_root_str)
        checkpoint_a_passed, checkpoint_a_failures = run_fixture_group(
            fixtures=PR11_8A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_b_passed, checkpoint_b_failures = run_fixture_group(
            fixtures=PR11_8B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_e_passed, checkpoint_e_failures = run_fixture_group(
            fixtures=PR11_8E_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_f_passed, checkpoint_f_failures = run_fixture_group(
            fixtures=PR11_8F_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_g1_passed, checkpoint_g1_failures = run_fixture_group(
            fixtures=PR11_8G1_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_g2_passed, checkpoint_g2_failures = run_fixture_group(
            fixtures=PR11_8G2_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_i_passed, checkpoint_i_failures = run_fixture_group(
            fixtures=PR11_8I_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        regression_passed, regression_failures = run_fixture_group(
            fixtures=EMITTED_PROOF_REGRESSION_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )

    total_passed = (
        companion_passed
        + checkpoint_a_passed
        + checkpoint_b_passed
        + checkpoint_e_passed
        + checkpoint_f_passed
        + checkpoint_g1_passed
        + checkpoint_g2_passed
        + checkpoint_i_passed
        + regression_passed
    )
    total_failures = (
        companion_failures
        + checkpoint_a_failures
        + checkpoint_b_failures
        + checkpoint_e_failures
        + checkpoint_f_failures
        + checkpoint_g1_failures
        + checkpoint_g2_failures
        + checkpoint_i_failures
        + regression_failures
    )

    print_summary(
        passed=companion_passed,
        failures=companion_failures,
        title="Companion baselines",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_a_passed,
        failures=checkpoint_a_failures,
        title="PR11.8a checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_b_passed,
        failures=checkpoint_b_failures,
        title="PR11.8b checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_e_passed,
        failures=checkpoint_e_failures,
        title="PR11.8e checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_f_passed,
        failures=checkpoint_f_failures,
        title="PR11.8f checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_g1_passed,
        failures=checkpoint_g1_failures,
        title="PR11.8g.1 checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_g2_passed,
        failures=checkpoint_g2_failures,
        title="PR11.8g.2 checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_i_passed,
        failures=checkpoint_i_failures,
        title="PR11.8i checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=regression_passed,
        failures=regression_failures,
        title="Emitted proof regressions",
        trailing_blank_line=True,
    )
    print_summary(passed=total_passed, failures=total_failures)
    return 0 if not total_failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
