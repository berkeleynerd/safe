# Emitted Output Verification Matrix

This document is the canonical coverage statement for emitted Ada/SPARK output.

It answers a narrower question than the Safe language spec as a whole:

- what the frontend currently accepts
- what `safec emit --ada-out-dir` currently emits
- what emitted outputs are only compile-validated
- what emitted outputs are GNATprove-validated at `flow`
- what emitted outputs are GNATprove-validated at `prove`
- what obligations remain outside direct GNATprove proof

PR10 is intentionally a **selected emitted-output** milestone. It does not claim
universal GNATprove proof coverage for every currently emitted Safe program.

PR10.1 keeps that selected corpus frozen, audits the surrounding claim surfaces,
and uses supplemental hardening plus the post-PR10 ledger for everything
beyond it. See [`docs/pr10_refinement_audit.md`](pr10_refinement_audit.md) for
the canonical audit record.

## Status Definitions

| State | Meaning |
|-------|---------|
| `frontend-accepted` | The current Ada-native frontend accepts the Safe source. |
| `Ada-emitted` | `safec emit --ada-out-dir` emits deterministic Ada/SPARK for that source. |
| `compile-validated` | The emitted Ada builds successfully via the emitted-project harness. |
| `GNATprove flow` | The emitted Ada passes `gnatprove --mode=flow --warnings=error`. |
| `GNATprove prove` | The emitted Ada passes `gnatprove --mode=prove --checks-as-errors=on --warnings=error`. |
| `exception-backed` | The residual obligation is met by a named non-GNATprove mechanism. |
| `deferred beyond PR10` | The feature or emitted verification surface remains outside the selected PR10 proof corpus. |

## PR10 Selected Corpus

The PR10 selected emitted corpus is:

- `tests/positive/rule1_averaging.safe`
- `tests/positive/rule2_binary_search_function.safe`
- `tests/positive/rule3_divide.safe`
- `tests/positive/rule1_parameter.safe`
- `tests/positive/ownership_move.safe`
- `tests/positive/rule4_linked_list_sum.safe`
- `tests/positive/rule5_vector_normalize.safe`
- `tests/positive/channel_pingpong.safe`
- `tests/positive/channel_pipeline_compute.safe`
- `tests/concurrency/select_with_delay.safe`

That selected corpus explicitly spans:

- Rule 1
- Rule 2
- Rule 3
- Rule 4
- Rule 5
- ownership
- concurrency

Supplemental hardening fixtures outside the frozen PR10 selected corpus are:

- `tests/positive/ownership_early_return.safe` for emitted early-return capture-before-cleanup ordering
- `tests/concurrency/select_with_delay_multiarm.safe` for supplemental multi-arm `select ... or delay ...` proof coverage

Reference-bearing channel elements and composite channel elements containing
reference-bearing members are spec-excluded. The repo keeps representative
rejection fixtures for that boundary:

- `tests/concurrency/channel_access_type.safe`
- `tests/concurrency/try_send_ownership.safe`
- `tests/concurrency/select_ownership_binding.safe`
- `tests/negative/neg_channel_access_component.safe`
- `tests/negative/neg_pr118g_direct_reference_channel.safe`
- `tests/negative/neg_pr118e_reference_channel.safe`
- `tests/negative/neg_pr118e1_mutual_family_channel.safe`

## Matrix

The repository still contains accepted and emitted samples beyond the frozen
PR10 representative set. PR10.2, PR10.3, PR10.6, PR11.3a, and PR11.8a now
close the retained sequential proof surface in named slices, and PR11.8b closes
the retained emitted concurrency proof surface in its own named slice.
`PR11.8g.3` then closes the admitted concurrency boundary by pairing emitted
GNATprove closure with one blocking STM32F4/Jorvik Renode evidence lane.
Broader fairness, latency, and multi-target runtime claims beyond that admitted
subset remain outside the current surface; see
[`jorvik_concurrency_contract.md`](jorvik_concurrency_contract.md).

| Feature Class | Representative Fixtures | Coverage Notes | Frontend Accepted | Ada Emitted | Compile Validated | GNATprove Flow | GNATprove Prove | Exception-Backed Obligation | Deferred Beyond PR10 |
|---------------|-------------------------|----------------|-------------------|-------------|-------------------|----------------|-----------------|-----------------------------|----------------------|
| Rule 1 wide arithmetic subset | `tests/positive/rule1_averaging.safe`, `tests/positive/rule1_parameter.safe` | Loop-carried wide arithmetic with an explicit narrowing return, plus validated narrowing before cross-subprogram parameter passing. | yes | yes | yes | yes | yes | none | no |
| Rule 2 function-return index-safety subset | `tests/positive/rule2_binary_search_function.safe` | Bounded-array binary search as a record-returning function with midpoint indexing and multiple early returns. | yes | yes | yes | yes | yes | none | no |
| Rule 3 division-safety subset | `tests/positive/rule3_divide.safe` | Typed nonzero divisor plus guarded variable-divisor division. | yes | yes | yes | yes | yes | none | no |
| Rule 4 observer-traversal subset | `tests/positive/rule4_linked_list_sum.safe` | Null-guarded linked-list prefix accumulation with dereference plus bounded count and total arithmetic. PR11.8f.1 lowers the admitted self-recursive traversal subset to structural cursor loops with proof-visible accumulator bounds, so the linked-list accumulator representative now proves without emitted `Skip_Proof` scaffolding. | yes | yes | yes | yes | yes | none | no |
| Rule 5 computed-divisor vector subset | `tests/positive/rule5_vector_normalize.safe` | Three-field floating-point record computation with a branch-computed positive divisor derived from all components and a returned normalized component. | yes | yes | yes | yes | yes | none | no |
| Sequential ownership move subset | `tests/positive/ownership_move.safe` | Single-owner move with post-move nulling and target-only dereference. GNATprove `prove` here covers emitted runtime checks; the frontend Silver ownership analysis is the mechanism that prevents use-after-free across the accepted ownership subset. | yes | yes | yes | yes | yes | none within the selected `ownership_move` subset; broader cleanup ordering remains deferred as `PS-029` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Post-PR10 ownership proof-expansion set | `tests/positive/ownership_borrow.safe`, `tests/positive/ownership_observe.safe`, `tests/positive/ownership_observe_access.safe`, `tests/positive/ownership_return.safe`, `tests/positive/ownership_inout.safe`, `tests/positive/ownership_early_return.safe` | Historical PR10.3 expansion set beyond the frozen PR10 `ownership_move` representative. After the PR11.8e source reset, the migrated ownership/reference fixtures are now reclosed under the live PR11.8e plus PR11.8f blocking manifests in `scripts/run_proofs.py`. | yes | yes | yes | yes | yes | frontend Silver ownership analysis still governs legality for the broader admitted surface, but the emitted proof lane is now live and blocking for the named PR11.8e / PR11.8f ownership fixtures. | no |
| Concurrency ping-pong subset | `tests/positive/channel_pingpong.safe` | Two priority-bearing tasks exchanging bounded channel messages in both directions. | yes | yes | yes | yes | yes | Blocking STM32F4/Jorvik Renode evidence covers the admitted fixed-priority task/channel runtime contract; broader timing/fairness claims remain outside the admitted surface in [`docs/jorvik_concurrency_contract.md`](jorvik_concurrency_contract.md). | no |
| Concurrency pipeline compute subset | `tests/positive/channel_pipeline_compute.safe` | Three-task channel pipeline with arithmetic in the filter and consumer task bodies. | yes | yes | yes | yes | yes | Blocking STM32F4/Jorvik Renode evidence covers the admitted fixed-priority task/channel runtime contract; broader timing/fairness claims remain outside the admitted surface in [`docs/jorvik_concurrency_contract.md`](jorvik_concurrency_contract.md). | no |
| Value-type channel elements with heap-backed values | `tests/build/pr118g_string_channel_build.safe`, `tests/build/pr118g_growable_channel_build.safe`, `tests/build/pr118g_tuple_string_channel_build.safe`, `tests/build/pr118g_record_string_channel_build.safe`, `tests/build/pr118g_try_string_channel_build.safe` | PR11.8g.2 closes the heap-backed channel seam by staging clone/free work outside protected channel bodies. PR11.8i.1 then splits the direct sequential single-slot string/growable path onto record-backed channels with explicit `Pre => not Full` / `Pre => Full` contracts, so the sequential subset no longer relies on the receive-side equality bridge. | yes | yes | yes | yes | yes | Blocking STM32F4/Jorvik Renode evidence covers the admitted runtime contract for the shipped channel subset. Any residual receive-side equality `pragma Assume` is now confined to the protected concurrent path; broader timing/fairness claims remain outside the admitted surface in [`docs/jorvik_concurrency_contract.md`](jorvik_concurrency_contract.md). | no |
| Dispatcher-based fair select subset | `tests/concurrency/select_with_delay.safe`, `tests/concurrency/select_with_delay_multiarm.safe`, `tests/concurrency/select_priority.safe` | `PR11.9a` replaces the older emitted polling loop with a package-scope readiness dispatcher, and `PR11.9b` makes plain `select` fair by default on the admitted subset. Channel arms run through one circular `Try_Receive` precheck starting at a persistent per-select `Next_Arm` cursor, while delay arms use one absolute deadline plus a package-scope timing-event wakeup. | yes | yes | yes | yes | yes | Blocking STM32F4/Jorvik Renode evidence covers the admitted fair dispatcher select contract. Broader scheduler-level fairness/latency claims remain outside the admitted surface in [`docs/jorvik_concurrency_contract.md`](jorvik_concurrency_contract.md). | no |
| Reference-bearing channel elements and composites containing them | `tests/concurrency/channel_access_type.safe`, `tests/concurrency/try_send_ownership.safe`, `tests/concurrency/select_ownership_binding.safe`, `tests/negative/neg_channel_access_component.safe`, `tests/negative/neg_pr118g_direct_reference_channel.safe`, `tests/negative/neg_pr118e_reference_channel.safe`, `tests/negative/neg_pr118e1_mutual_family_channel.safe` | Spec-excluded by value-only channel element legality. The frontend rejects these declarations before emit, flow, or prove. | no | no | no | no | no | n/a | no |
| PR11.8g.1 sequential proof-expansion set | `tests/positive/pr09_emitter_discriminant.safe`, `tests/positive/pr115_compound_terminators.safe`, `tests/positive/pr115_declare_terminator.safe`, `tests/positive/pr115_legacy_local_decl.safe`, `tests/positive/pr115_multiline_return.safe`, `tests/positive/pr1162_empty_subprogram_body_followed_by_sibling.safe`, `tests/positive/pr116_bare_return.safe`, `tests/positive/pr118c_binary_case_dispatch.safe`, `tests/positive/pr118d_bounded_string_array_component.safe`, `tests/positive/pr118d_bounded_string_field.safe`, `tests/positive/pr118d_string_equality.safe`, `tests/positive/pr118e1_not_null_mutual_family.safe`, `tests/positive/pr118e1_three_type_family.safe` | PR11.8g.1 adds a new blocking proof-expansion manifest in `scripts/run_proofs.py` for accepted emitted sequential fixtures that prove cleanly today but were previously outside the frozen checkpoint manifests. This is a real widening of the blocking emitted-proof surface, not a regression-only carve-out. | yes | yes | yes | yes | yes | none | no |
| PR11.8g.1 concurrency proof-expansion set | `tests/concurrency/pr118b1_partial_task_clauses.safe`, `tests/concurrency/pr118b1_scoped_receive.safe`, `tests/concurrency/pr118b1_scoped_try_receive.safe`, `tests/concurrency/pr118b1_transitive_local_task_clause.safe` | PR11.8g.1 extends the blocking emitted-proof lane to the proof-friendly post-PR11.8b concurrency surface, and PR11.8g.3 closes the admitted runtime/select boundary for that same surface with blocking Jorvik-backed embedded evidence. | yes | yes | yes | yes | yes | Blocking STM32F4/Jorvik Renode evidence covers the admitted runtime/select contract used by the shipped concurrency surface; broader timing/fairness claims remain outside the admitted surface in [`docs/jorvik_concurrency_contract.md`](jorvik_concurrency_contract.md). | no |
| PR11.8g.1 build-surface proof-expansion set | `tests/build/pr118c2_package_pre_task.safe`, `tests/build/pr118d1_for_of_string_build.safe`, `tests/build/pr118d1_string_case_build.safe`, `tests/build/pr118d1_string_order_build.safe`, `tests/build/pr118d_bounded_string_array_component_build.safe`, `tests/build/pr118d_bounded_string_index_build.safe`, `tests/build/pr118d_bounded_string_tick_build.safe`, `tests/build/pr118d_for_of_fixed_build.safe`, `tests/build/pr118d_for_of_growable_build.safe`, `tests/build/pr118d_for_of_heap_element_build.safe` | PR11.8g.1 also widens the blocking lane across proof-friendly emitted build/package representatives. The live emitted surface now includes a named post-PR11.8d build subset rather than leaving these fixtures in an implicit “accepted but not proved” bucket. | yes | yes | yes | yes | yes | none | no |
| Heap-backed runtime-backed string/growable surface | `tests/positive/pr118d_bounded_string.safe`, `tests/positive/pr118d_character_quote_literal.safe`, `tests/positive/pr118d_growable_array.safe`, `tests/positive/pr118d_string_length_attribute.safe`, `tests/positive/pr118d_string_mutable_object.safe`, `tests/build/pr118d1_growable_to_fixed_guard_build.safe`, `tests/build/pr118d_bounded_string_build.safe`, `tests/build/pr118d_bounded_string_field_build.safe`, `tests/build/pr118d_fixed_to_growable_build.safe`, `tests/build/pr118d_growable_to_fixed_literal_build.safe`, `tests/build/pr118d_growable_to_fixed_slice_build.safe` | PR11.8g.2 moved string/growable runtime support onto the shared proved runtime seam. PR11.8g.4 then made that seam generically honest by weakening shared `Safe_Array_RT` to length-only facts and routing non-heap growable-array component types through the stronger `Safe_Array_Identity_Ops` + `Safe_Array_Identity_RT` path where element-preservation is actually justified. | yes | yes | yes | yes | yes | none | no |
| Fixed-width binary emitted surface | `tests/positive/pr118c_binary_boolean_logic.safe`, `tests/positive/pr118c_binary_conversion_wrap.safe`, `tests/positive/pr118c_binary_inline_object.safe`, `tests/positive/pr118c_binary_named_type.safe`, `tests/positive/pr118c_binary_param_return.safe`, `tests/positive/pr118c_binary_shift.safe` | PR11.8i.1 completes the second emitted-proof expansion pass by absorbing the remaining fixed-width binary fixtures into the blocking proof manifest alongside the earlier case-dispatch representative. The emitted numeric surface is now explicit and fully covered rather than tracked as post-PR11.8g.1 cleanup debt. | yes | yes | yes | yes | yes | none | no |
| Built-in container checkpoint surface | `tests/positive/pr1110a_optional_guarded.safe`, `tests/positive/pr1110b_list_basics.safe`, `tests/positive/pr1110c_map_basics.safe`, plus the build-backed `pr1110a*`, `pr1110b*`, and `pr1110c*` fixtures in `scripts/_lib/proof_inventory.py` | PR11.10a/PR11.10b/PR11.10c close the shipped optional/list/map surface under blocking emitted proof manifests, and PR11.10d ratifies that union as the parent container checkpoint. `tests/build/pr1110b_list_empty_build.safe` and `tests/build/pr213_map_entry_build.safe` now both prove through the emitted lane; PR11.22h.1 closes the former runtime-only container proof gaps. | yes | yes | yes | yes | yes | none | no |
| Shared-wrapper checkpoint surface | `tests/positive/pr1112a_shared_field_access.safe`, `tests/positive/pr1112b_shared_snapshot.safe`, plus the build-backed `pr1112c*`, `pr1112d*`, `pr1112e*`, and `pr1112f*` fixtures in `scripts/_lib/proof_inventory.py` and `tests/interfaces/provider_shared_ceiling.safe` | PR11.12a through PR11.12f close the shipped shared-wrapper surface under blocking emitted proof manifests, and PR11.12g ratifies that union as the parent shared checkpoint. The current shared family carries no named proof exclusions, so the parent checkpoint closes with zero unnamed coverage holes and zero shared-specific exclusion debt. | yes | yes | yes | yes | yes | none | no |
| Sum-type checkpoint surface | `tests/positive/pr1113a_sum_construction.safe`, `tests/positive/pr1113b_sum_match.safe`, plus the build-backed `pr1113c*` fixtures in `scripts/_lib/proof_inventory.py` | PR11.13a, PR11.13b, and PR11.13c close the shipped sum-type surface under blocking emitted proof manifests. The parent `PR11.13 checkpoint` ratifies same-unit and imported constructor/match behavior, including heap-backed imported payloads and overlapping imported variant names resolved by scrutinee type. | yes | yes | yes | yes | yes | none | no |
| Shared `IO` seam representative | `tests/positive/pr118c1_print.safe` | `print` now lowers through the shared standard-library `IO` package instead of per-unit generated wrappers. PR11.8g.2 includes that seam in the blocking emitted-proof lane, so emitted packages no longer rely on excluded `_safe_io` helper bodies. | yes | yes | yes | yes | yes | none | no |

## PR11.13 Sum-Type Checkpoint Corpus

PR11.13 closes the shipped sum-type family as one emitted-proof checkpoint.
`scripts/run_proofs.py` reports the child slices individually and then the
parent `PR11.13 checkpoint`.

The child manifests are:

- `PR11.13a`
  - `tests/positive/pr1113a_sum_construction.safe`
  - `tests/build/pr1113a_sum_build.safe`
- `PR11.13b`
  - `tests/positive/pr1113b_sum_match.safe`
  - `tests/build/pr1113b_sum_match_build.safe`
- `PR11.13c`
  - `tests/build/pr1113c_provider_shape.safe`
  - `tests/build/pr1113c_imported_sum_build.safe`
  - `tests/build/pr1113c_imported_string_sum_build.safe`
  - `tests/build/pr1113c_imported_overlap_build.safe`

The sum-type family currently has no named proof exclusions.

## PR10.2 Rule 5 Boundary Closure

PR10.2 keeps the frozen PR10 Rule 5 row above intact while closing the broader
live accepted Rule 5 positive set under one dedicated gate. That closure set is
the explicit merge of the historical PR07 Rule 5 positives plus the frozen PR10
representative:

- `tests/positive/rule5_filter.safe`
- `tests/positive/rule5_interpolate.safe`
- `tests/positive/rule5_normalize.safe`
- `tests/positive/rule5_statistics.safe`
- `tests/positive/rule5_temperature.safe`
- `tests/positive/rule5_vector_normalize.safe`

PR10.2 also fixes the analyzer boundary so unsupported float-evaluator shapes
use `fp_unsupported_expression_at_narrowing` instead of being mislabeled as
`fp_overflow_at_narrowing`, and it locks the committed source-diagnostic
contract for:

- `fp_division_by_zero`
- `infinity_at_narrowing`
- `nan_at_narrowing`
- `fp_overflow_at_narrowing`
- `fp_uninitialized_at_narrowing`

Convergence-style `while` loops outside the emitter's current derivable
`Loop_Variant` shapes are not accepted as downstream emitted-proof targets.
They are rejected during `safec check` with `loop_variant_not_derivable`.

Fixed-point Rule 5 support and the broader spec-level floating-point semantics
question remain open as `PS-002` and `PS-026` in
[`docs/post_pr10_scope.md`](post_pr10_scope.md).

## PR11.3a Sequential Checkpoint Corpus

PR11.3a adds a distinct post-PR10 sequential proof checkpoint for the parser,
text, discriminant, tuple, and structured-return surfaces admitted by PR11.2
and PR11.3.

That checkpoint corpus is exactly:

- `tests/positive/pr112_character_case.safe`
- `tests/positive/pr112_discrete_case.safe`
- `tests/positive/pr112_string_param.safe`
- `tests/positive/pr112_case_scrutinee_once.safe`
- `tests/positive/pr113_discriminant_constraints.safe`
- `tests/positive/pr113_tuple_destructure.safe`
- `tests/positive/pr113_structured_result.safe`
- `tests/positive/pr113_variant_guard.safe`
- `tests/positive/constant_discriminant_default.safe`
- `tests/positive/result_equality_check.safe`
- `tests/positive/result_guarded_access.safe`

PR11.3a proves that exact set through emitted Ada compile, GNATprove `flow`,
and GNATprove `prove` under the same all-proved-only policy used by the earlier
sequential checkpoints.

`tests/positive/pr113_tuple_channel.safe` remained outside PR11.3a itself
because it is a concurrency fixture, but it is now part of the dedicated
PR11.8b concurrency checkpoint below rather than being left as residual
compile-only coverage.

## PR11.8a Numeric Revalidation Checkpoint

PR11.8a revalidates the numeric-sensitive retained proof surface under the
single-`integer` model admitted by PR11.8.

That checkpoint corpus is exactly:

- `tests/positive/rule1_accumulate.safe`
- `tests/positive/rule1_averaging.safe`
- `tests/positive/rule1_conversion.safe`
- `tests/positive/rule1_parameter.safe`
- `tests/positive/rule1_return.safe`
- `tests/positive/rule2_binary_search.safe`
- `tests/positive/rule2_binary_search_function.safe`
- `tests/positive/rule2_iteration.safe`
- `tests/positive/rule2_lookup.safe`
- `tests/positive/rule2_matrix.safe`
- `tests/positive/rule2_slice.safe`
- `tests/positive/rule3_average.safe`
- `tests/positive/rule3_divide.safe`
- `tests/positive/rule3_modulo.safe`
- `tests/positive/rule3_percent.safe`
- `tests/positive/rule3_remainder.safe`
- `tests/positive/rule5_filter.safe`
- `tests/positive/rule5_interpolate.safe`
- `tests/positive/rule5_normalize.safe`
- `tests/positive/rule5_statistics.safe`
- `tests/positive/rule5_temperature.safe`
- `tests/positive/rule5_vector_normalize.safe`
- `tests/positive/constant_range_bound.safe`
- `tests/positive/constant_channel_capacity.safe`
- `tests/positive/constant_task_priority.safe`
- `tests/positive/pr112_character_case.safe`
- `tests/positive/pr112_discrete_case.safe`
- `tests/positive/pr112_string_param.safe`
- `tests/positive/pr112_case_scrutinee_once.safe`
- `tests/positive/pr113_discriminant_constraints.safe`
- `tests/positive/pr113_tuple_destructure.safe`
- `tests/positive/pr113_structured_result.safe`
- `tests/positive/pr113_variant_guard.safe`
- `tests/positive/constant_discriminant_default.safe`
- `tests/positive/result_equality_check.safe`
- `tests/positive/result_guarded_access.safe`
- `tests/positive/pr118_inline_integer_return.safe`
- `tests/positive/pr118_type_range_equivalent.safe`

This exact manifest is mirrored in `scripts/run_proofs.py` and is treated as
non-shrinkable. PR11.8a keeps the same all-proved-only policy as the earlier
checkpoints: emitted Ada compile, GNATprove `flow`, and GNATprove `prove` must
all succeed with zero justified and zero unproved checks.

The companion proof baselines in `companion/gen` and `companion/templates`
continue to run under the same `python3 scripts/run_proofs.py` command and the
same CI `prove` job, but they are baseline regressions rather than members of
the frozen PR11.8a checkpoint corpus.

Concurrency fixtures that still prove under the live suite remain outside the
PR11.8a milestone claim. Their broader proof expansion continues to be tracked
as `PR11.8b`.

Fixed-point Rule 5 support and broader floating-point semantics remain deferred
after this checkpoint as `PS-002` and `PS-026` in
[`docs/post_pr10_scope.md`](post_pr10_scope.md).

## PR11.8b Concurrency Checkpoint Corpus

The live `scripts/run_proofs.py` lane keeps a reduced PR11.8b checkpoint for
the subset that is currently green under the strict all-proved-only policy. It
is still a proof-only checkpoint, not a syntax expansion milestone.

That live checkpoint corpus is exactly:

- `tests/concurrency/channel_ceiling_priority.safe`
- `tests/positive/channel_pipeline.safe`
- `tests/concurrency/exclusive_variable.safe`
- `tests/concurrency/fifo_ordering.safe`
- `tests/concurrency/multi_task_channel.safe`
- `tests/concurrency/select_delay_local_scope.safe`
- `tests/concurrency/select_priority.safe`
- `tests/concurrency/task_global_owner.safe`
- `tests/concurrency/task_priority_delay.safe`
- `tests/concurrency/try_ops.safe`
- `tests/positive/pr113_tuple_channel.safe`

This exact manifest is mirrored in `scripts/run_proofs.py` and is treated as
the current live checkpoint. PR11.8b keeps the same all-proved-only policy as
the earlier checkpoints: emitted Ada compile, GNATprove `flow`, and GNATprove
`prove` must all succeed with zero justified and zero unproved checks.

The already-proved concurrency baselines
`tests/positive/channel_pingpong.safe`,
`tests/positive/channel_pipeline_compute.safe`,
`tests/concurrency/select_with_delay.safe`, and
`tests/concurrency/select_with_delay_multiarm.safe` continue to run as live
proof regressions outside the frozen PR11.8b checkpoint manifest.

Spec-excluded fixtures such as `tests/concurrency/channel_access_type.safe`,
`tests/concurrency/try_send_ownership.safe`, and
`tests/concurrency/select_ownership_binding.safe` remain outside the proof debt
entirely because the frontend rejects them before emit.

After `PR11.8g.3`, the admitted concurrency surface is no longer carried with
open `PS-007` / `PS-031` caveats. The shipped contract now rests on emitted
GNATprove closure plus the blocking STM32F4/Jorvik embedded lane documented in
[`docs/jorvik_concurrency_contract.md`](jorvik_concurrency_contract.md). Only
broader fairness, latency, and multi-target runtime claims remain outside the
admitted surface.

## PR11.8e Ownership / Inferred-Reference Checkpoint Corpus

PR11.8e adds a dedicated live checkpoint for the inferred-reference reset and
task-body restriction.

That live checkpoint corpus is exactly:

- `tests/positive/ownership_move.safe`
- `tests/positive/ownership_early_return.safe`
- `tests/positive/pr118e_not_null_self_reference.safe`
- `tests/concurrency/pr118c2_pre_task_init.safe`

This exact manifest is mirrored in `scripts/run_proofs.py` and is treated as
the current live ownership/reference checkpoint under the same all-proved-only
policy.

PR11.8f then closes the carried-forward sequential ownership/reference debt
that remained outside the smaller PR11.8e checkpoint.

## PR11.8f Sequential Ownership / Recursive-Reference Checkpoint Corpus

PR11.8f promotes the previously carried-forward sequential ownership and Rule 4
recursive-reference fixtures into a blocking emitted-proof checkpoint.

That live checkpoint corpus is exactly:

- `tests/positive/rule4_conditional.safe`
- `tests/positive/rule4_deref.safe`
- `tests/positive/rule4_factory.safe`
- `tests/positive/rule4_linked_list.safe`
- `tests/positive/rule4_linked_list_sum.safe`
- `tests/positive/rule4_optional.safe`
- `tests/positive/ownership_borrow.safe`
- `tests/positive/ownership_observe.safe`
- `tests/positive/ownership_observe_access.safe`
- `tests/positive/ownership_return.safe`
- `tests/positive/ownership_inout.safe`

This exact manifest is mirrored in `scripts/run_proofs.py` and is treated as
the live PR11.8f checkpoint. The set is fully reclosed under the same
all-proved-only policy as the earlier checkpoints, including the linked-list
observer and accumulator traversal representatives after PR11.8f.1's
structural cursor-loop lowering.

## PR11.10 Container Checkpoint Corpus

PR11.10d closes the parent container milestone as the explicit union of the
three shipped container wedges:

- `PR11.10a` optional checkpoint:
  - `tests/positive/pr1110a_optional_guarded.safe`
  - `tests/build/pr1110a_optional_string_build.safe`
  - `tests/build/pr1110a_optional_growable_build.safe`
- `PR11.10b` list checkpoint:
  - `tests/positive/pr1110b_list_basics.safe`
  - `tests/positive/pr1110b_disjoint_mut_indices.safe`
  - `tests/build/pr1110b_list_build.safe`
  - `tests/build/pr1110b_list_string_build.safe`
  - `tests/build/pr1110b_list_growable_build.safe`
- `PR11.10c` map checkpoint:
  - `tests/positive/pr1110c_map_basics.safe`
  - `tests/build/pr1110c_map_build.safe`
  - `tests/build/pr1110c_map_string_build.safe`
  - `tests/build/pr1110c_map_list_build.safe`

This exact parent checkpoint is mirrored in `scripts/_lib/proof_inventory.py`
and summarized by `python3 scripts/run_proofs.py` as `PR11.10d checkpoint`.

The parent checkpoint is closed under the same all-proved-only policy as the
earlier emitted checkpoints. `tests/build/pr1110b_list_empty_build.safe` now
proves through the emitted lane after generated `pop_last` trim branches gained
narrow warning suppressions for GNATprove's static-length false positives.
`tests/build/pr213_map_entry_build.safe` now also proves after generated
composite growable `for of` loops gained conservative accumulator headroom
invariants. No container-family runtime-only proof gap remains.

## PR11.12 Shared Wrapper Checkpoint Corpus

PR11.12g closes the parent shared-wrapper milestone as the explicit union of
the six shipped shared wedges:

- `PR11.12a` field-access checkpoint:
  - `tests/positive/pr1112a_shared_field_access.safe`
  - `tests/build/pr1112a_shared_task_build.safe`
- `PR11.12b` snapshot/update checkpoint:
  - `tests/positive/pr1112b_shared_snapshot.safe`
  - `tests/build/pr1112b_shared_update_build.safe`
- `PR11.12c` heap-backed field checkpoint:
  - `tests/build/pr1112c_shared_string_build.safe`
  - `tests/build/pr1112c_shared_container_fields_build.safe`
  - `tests/build/pr1112c_layered_growable_type_build.safe`
- `PR11.12d` shared container-root checkpoint:
  - `tests/build/pr1112d_shared_list_root_build.safe`
  - `tests/build/pr1112d_shared_map_root_build.safe`
  - `tests/build/pr1112d_shared_map_indexed_remove_build.safe`
  - `tests/build/pr1112d_shared_growable_root_build.safe`
- `PR11.12e` public/imported shared checkpoint:
  - `tests/build/pr1112e_provider_shared_record.safe`
  - `tests/build/pr1112e_provider_shared_list.safe`
  - `tests/build/pr1112e_provider_shared_map.safe`
  - `tests/build/pr1112e_imported_shared_record_build.safe`
  - `tests/build/pr1112e_imported_shared_list_build.safe`
  - `tests/build/pr1112e_imported_shared_map_build.safe`
- `PR11.12f` exact-ceiling checkpoint:
  - `tests/build/pr1112f_shared_record_ceiling_build.safe`
  - `tests/build/pr1112f_shared_container_ceiling_build.safe`
  - `tests/build/pr1112f_mixed_channel_shared_build.safe`
  - `tests/interfaces/provider_shared_ceiling.safe`

This exact parent checkpoint is mirrored in `scripts/_lib/proof_inventory.py`
and summarized by `python3 scripts/run_proofs.py` as `PR11.12 checkpoint`.

The parent checkpoint is closed under the same all-proved-only policy as the
earlier emitted checkpoints. Unlike the container family, it currently carries
no named proof exclusions. Shared-wrapper proof coverage therefore closes with
zero unnamed holes and zero shared-specific exclusion inventory.
`tests/build/pr228_shared_loop_exit_condition_build.safe` also proves through
the regression lane after PR11.22h.1b preserved dynamic guards on
variant-bearing loops with shared exit-condition snapshots. The same emission
change intentionally refreshes snapshot hashes for existing simple
variant-bearing loops whose guards were previously static-folded.

## Emitted GNATprove Warning Suppression Inventory

The emitter generates narrowly scoped `pragma Warnings (GNATprove, Off, "<pattern>")` /
`pragma Warnings (GNATprove, On, "<pattern>")` pairs around specific generated Ada
constructs. Each suppression covers a known false-positive GNATprove flow warning
produced by a generated code shape that is structurally correct. This inventory must
be updated whenever a suppression is added or removed.

### Emitted `pragma Assume` (proof debt)

| Fact | Emission site | Scope | Justification | Fragility |
|------|--------------|-------|---------------|-----------|
| `Length(Staged) = Value_Length` after protected channel Receive / Try_Receive | Ordinary receive, try_receive success path, select-arm try_receive success path (2 forms) | Capacity-1 string/growable channels on the protected concurrent path | The protected body stores `Value` and `Value_Length` in corresponding slots atomically; the fact is true by construction but unprovable because GNATprove's modular protected-type analysis does not support invariants relating distinct private components | Permanent until GNATprove supports protected-type state invariants or the protected concurrent path is reworked |

### Emitted warning suppressions

| Pattern | Reason string | Generated construct | Why the warning is a false positive | What would invalidate it |
|---------|--------------|--------------------|------------------------------------|------------------------|
| `"initialization of"` | "generated local initialization is intentional" | Scratch locals with default initializers where the first executable statement unconditionally assigns the real value | The emitter generates default initializers to satisfy Ada definite-assignment rules; the value is always overwritten before first read | If the emitter generated a code path that read the scratch local before the first assignment |
| `"unused initial value of"` | "generated local cleanup is intentional" | Cleanup locals that are assigned and then freed | GNATprove sees the initial value as unused because the cleanup path overwrites it; the initial value exists only to satisfy Ada elaboration | Same as above |
| `"unused assignment"` | "generated local cleanup is intentional" / "task-local state updates are intentionally isolated" | Cleanup locals and task-body state updates | For cleanup: the assignment is consumed by the subsequent `Free` call. For task locals: the assignment is consumed by later task-body statements, but GNATprove's modular task analysis cannot trace the connection | If the emitter generated a cleanup local whose value was never consumed, or a task-local assignment that was genuinely dead |
| `"is set by"` | "generated local cleanup is intentional" | Cleanup locals set by runtime `Free` / `Copy` calls | GNATprove warns that the local "is set by" a procedure call that might not always execute; the emitter's generated cleanup path always executes the call unconditionally | If the emitter generated a conditional cleanup path where the `Free` call was not unconditional |
| `"is set by"` | "heap-backed channel staging is intentional" | Staged value locals around heap-backed channel `Receive` / `Try_Receive` calls | The `out` parameter is set by the protected operation; GNATprove warns because the parameter might not be set on the failure path, but the emitter always guards usage with the success flag | If the emitter used the staged value without checking the success flag |
| `"is set by"` | "channel results are consumed on the success path only" | Task-body channel `Receive` / `Try_Receive` calls | Same as above but inside task bodies, where GNATprove's modular analysis is more conservative | Same as above |
| `"statement has no effect"` | "generated local cleanup is intentional" / "task-local state updates are intentionally isolated" / "task-local branching is intentionally isolated" | Cleanup paths, task-body assignments, and task-body `if` statements | GNATprove's modular task analysis sees task-local state updates and branches as effect-free because the results do not flow to a visible output in the protected-call model; the effects are real and consumed by subsequent task-body statements | If the emitter generated genuinely dead task-body code |
| `"unused assignment"` / `"statement has no effect"` | "generated pop_last trim branch is guarded by static length facts" | Synthetic `pop_last` trim branches generated after the list length has been captured | GNATprove can statically fold some empty-list witnesses and report the guarded trim assignments as effect-free, but the branches are required for non-empty lists and are protected by the captured length fact | If the desugaring emitted the suppression outside the two generated trim branches or if the list value could be read from a stale length fact |
| `"implicit aspect Always_Terminates"` | "shared runtime cleanup termination is accepted" | Constant-value cleanup blocks that copy a constant into a mutable local and call `Free` | The shared runtime `Free` procedures carry `Always_Terminates` on their specs; GNATprove cannot connect that contract through the generated mutable-copy block | **Fragile:** if a shared runtime `Free` ever lost its `Always_Terminates` aspect, this suppression would silently hide a real termination gap. Hardening improvement tracked: the emitter should verify the target `Free` carries `Always_Terminates` before emitting the suppression |

### SPARK_Mode Off Boundary Inventory

GNATprove reasons through visible spec contracts for these units but does not
analyze the implementation bodies or private access-type representation. This
is an explicit trust boundary tracked as assumption A-06 in
[`companion/assumptions.yaml`](../companion/assumptions.yaml), except for the
I/O wrapper, which is a separate proof-model boundary.

| File / scope | Visible contract surface | Trusted implementation behavior | If wrong |
|--------------|--------------------------|---------------------------------|----------|
| `safe_string_rt.ads` private section + `safe_string_rt.adb` | String length, conversion, clone/free, concatenation, indexing, and equality contracts | Heap allocation, copying, deallocation, and `Equal` implementing `To_String (Left) = To_String (Right)` | String value facts, lifetime cleanup, or equality proof obligations could be unsound |
| `safe_array_rt.ads` private section + `safe_array_rt.adb` | Length-only contracts for heap-backed array/list/map storage | Heap allocation, element clone/free calls, append/concat, and length tracking | Container length facts or value-semantics cleanup could be unsound |
| `safe_array_identity_rt.ads` private section + `safe_array_identity_rt.adb` | Length plus element-preserving contracts for identity-clone element types | Same representation as `Safe_Array_RT`, with stronger reliance on identity-preserving element operations | Element-preservation facts for simple arrays could be unsound |
| `safe_ownership_rt.adb` | Allocate/free/dispose specs for ownership runtime helpers | Single-object allocation and deallocation | Ownership cleanup could leak, double-free, or invalidate lifetime assumptions |
| `io.adb` | `Put_Line` has `Global => null` and `Always_Terminates` | `Ada.Text_IO.Put_Line` writes to stdout and is assumed to return | I/O ordering, blocking, or side effects are outside the proof model |

### Array Runtime Contract Tiers

The emitter chooses an array runtime tier from the element type. This distinction
is load-bearing for proofs that involve clone/copy operations.

| Tier | Runtime | Applies to | Proved to callers | Trusted / not proved |
|------|---------|------------|-------------------|----------------------|
| Identity tier | `Safe_Array_Identity_RT` via `Safe_Array_Identity_Ops` | Simple value-identity elements such as integers, booleans, and enums | Length and element equality after clone/copy, including the wrapper-level fact that `Clone_Element'Result = Source` | The `SPARK_Mode Off` body plus correctness of tier selection and wrapper emission |
| Base tier | `Safe_Array_RT` | Heap-backed elements such as strings, nested containers, maps, and records containing reference-backed fields | Length preservation and bounds facts | Element contents, clone independence, and deep-free behavior beyond the visible length contracts |

Generated `Clone_Element` and `Free_Element` functions are the seam between
emitted Safe types and these runtimes. For the identity tier, generated clone
functions route through wrappers whose `Clone'Result = Source` postcondition is
proved to callers; the remaining trust boundary is the `SPARK_Mode Off` runtime
body together with correct tier selection/emission. For the base tier,
generated clone/free functions are trusted to implement the value-semantics
contract required by the runtime body, but callers only receive the runtime
spec's length-level facts.

### Cleanup Termination Trust Chain

The emitter suppresses generated cleanup warnings for calls to shared runtime
`Free` operations because those specs carry `Always_Terminates`. The bodies are
`SPARK_Mode Off`, so GNATprove cannot prove that the implementations terminate.
The current safety argument is manual: each `Free` body follows a bounded
cleanup/deallocation/nulling pattern and the suppression is scoped to generated
cleanup blocks. If a runtime `Free` lost `Always_Terminates` or stopped
terminating, the suppression would hide a real termination gap.

### I/O Proof-Model Boundary

`IO.Put_Line` deliberately exposes `Global => null` even though its body writes
to stdout through `Ada.Text_IO`. Safe currently proves memory/value safety and
absence of runtime errors, not I/O ordering or external effects. Future I/O
operations with stateful preconditions, file handles, or blocking behavior must
revisit this model rather than copying the `Put_Line` contract blindly.

## PR10 Assurance Policy

Inside the selected emitted corpus, PR10 uses an **all-proved-only** policy:

- zero warnings
- zero justified checks
- zero unproved checks

Outside that selected corpus, this matrix is authoritative. If a feature is not
marked `GNATprove prove = yes`, it must not be described as emitted-output
Silver/Bronze verified.

## Residual Ownership

Residual items after PR10 and the supplemental hardening regressions are tracked
in [`docs/post_pr10_scope.md`](post_pr10_scope.md), with the full disposition
record in [`docs/pr10_refinement_audit.md`](pr10_refinement_audit.md).
