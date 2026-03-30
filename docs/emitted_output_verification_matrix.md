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
the retained emitted concurrency proof surface in its own named slice. Faithful
source-level select semantics, I/O seam wrappers, and Jorvik/Ravenscar runtime
obligations still remain outside direct emitted-package GNATprove proof.

| Feature Class | Representative Fixtures | Coverage Notes | Frontend Accepted | Ada Emitted | Compile Validated | GNATprove Flow | GNATprove Prove | Exception-Backed Obligation | Deferred Beyond PR10 |
|---------------|-------------------------|----------------|-------------------|-------------|-------------------|----------------|-----------------|-----------------------------|----------------------|
| Rule 1 wide arithmetic subset | `tests/positive/rule1_averaging.safe`, `tests/positive/rule1_parameter.safe` | Loop-carried wide arithmetic with an explicit narrowing return, plus validated narrowing before cross-subprogram parameter passing. | yes | yes | yes | yes | yes | none | no |
| Rule 2 function-return index-safety subset | `tests/positive/rule2_binary_search_function.safe` | Bounded-array binary search as a record-returning function with midpoint indexing and multiple early returns. | yes | yes | yes | yes | yes | none | no |
| Rule 3 division-safety subset | `tests/positive/rule3_divide.safe` | Typed nonzero divisor plus guarded variable-divisor division. | yes | yes | yes | yes | yes | none | no |
| Rule 4 observer-traversal subset | `tests/positive/rule4_linked_list_sum.safe` | Null-guarded linked-list prefix accumulation with dereference plus bounded count and total arithmetic. PR11.8f.1 lowers the admitted self-recursive traversal subset to structural cursor loops with proof-visible accumulator bounds, so the linked-list accumulator representative now proves without emitted `Skip_Proof` scaffolding. | yes | yes | yes | yes | yes | none | no |
| Rule 5 computed-divisor vector subset | `tests/positive/rule5_vector_normalize.safe` | Three-field floating-point record computation with a branch-computed positive divisor derived from all components and a returned normalized component. | yes | yes | yes | yes | yes | none | no |
| Sequential ownership move subset | `tests/positive/ownership_move.safe` | Single-owner move with post-move nulling and target-only dereference. GNATprove `prove` here covers emitted runtime checks; the frontend Silver ownership analysis is the mechanism that prevents use-after-free across the accepted ownership subset. | yes | yes | yes | yes | yes | none within the selected `ownership_move` subset; broader cleanup ordering remains deferred as `PS-029` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Post-PR10 ownership proof-expansion set | `tests/positive/ownership_borrow.safe`, `tests/positive/ownership_observe.safe`, `tests/positive/ownership_observe_access.safe`, `tests/positive/ownership_return.safe`, `tests/positive/ownership_inout.safe`, `tests/positive/ownership_early_return.safe` | Historical PR10.3 expansion set beyond the frozen PR10 `ownership_move` representative. After the PR11.8e source reset, the migrated ownership/reference fixtures are now reclosed under the live PR11.8e plus PR11.8f blocking manifests in `scripts/run_proofs.py`. | yes | yes | yes | yes | yes | frontend Silver ownership analysis still governs legality for the broader admitted surface, but the emitted proof lane is now live and blocking for the named PR11.8e / PR11.8f ownership fixtures. | no |
| Concurrency ping-pong subset | `tests/positive/channel_pingpong.safe` | Two priority-bearing tasks exchanging bounded channel messages in both directions. | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof; see `PS-031` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Concurrency pipeline compute subset | `tests/positive/channel_pipeline_compute.safe` | Three-task channel pipeline with arithmetic in the filter and consumer task bodies. | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof; see `PS-031` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Value-type channel elements with heap-backed values | `tests/build/pr118g_string_channel_build.safe`, `tests/build/pr118g_growable_channel_build.safe`, `tests/build/pr118g_tuple_string_channel_build.safe`, `tests/build/pr118g_record_string_channel_build.safe`, `tests/build/pr118g_try_string_channel_build.safe` | PR11.8g admits direct string/growable channel elements and definite composites that contain them transitively. The emitted protected-buffer deep-copy path is compile- and runtime-validated here. Blocking emitted `flow`/`prove` closure for the heap-backed helper path is deferred to `PR11.8g.2`, because the current runtime copy/free seam still relies on `SPARK_Mode => Off` support code. | yes | yes | yes | no | no | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof; the heap-backed helper seam also stays deferred to `PR11.8g.2`. | yes |
| Select-with-delay emitted polling subset | `tests/concurrency/select_with_delay.safe`, `tests/concurrency/select_with_delay_multiarm.safe` | Frozen PR10 coverage proves one receive arm plus one delay arm, and supplemental hardening additionally proves a two-channel-arm success-path variant. Both are proved through the emitted polling-based lowering, not source-level blocking fairness or timing semantics. | yes | yes | yes | yes | yes | Polling-based lowering is proved, while source-level blocking fairness, latency, and timing semantics remain deferred as `PS-007` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Reference-bearing channel elements and composites containing them | `tests/concurrency/channel_access_type.safe`, `tests/concurrency/try_send_ownership.safe`, `tests/concurrency/select_ownership_binding.safe`, `tests/negative/neg_channel_access_component.safe`, `tests/negative/neg_pr118g_direct_reference_channel.safe`, `tests/negative/neg_pr118e_reference_channel.safe`, `tests/negative/neg_pr118e1_mutual_family_channel.safe` | Spec-excluded by value-only channel element legality. The frontend rejects these declarations before emit, flow, or prove. | no | no | no | no | no | n/a | no |
| Other currently emitted sequential fixtures outside the PR10 corpus | remaining accepted sequential subset beyond the named checkpoints above | No blanket proof claim: accepted/emitted sequential fixtures outside the frozen PR10 representatives and the named PR10.2, PR11.3a, PR11.8a, PR11.8e, and PR11.8f checkpoints remain feature-by-feature only. Frontend acceptance and Ada emission do not imply live `flow`/`prove` closure unless a fixture is in one of the named blocking manifests in `scripts/run_proofs.py`. | yes | yes | yes | no | no | none | yes |
| Other currently emitted concurrency fixtures outside the PR10 corpus | retained emitted concurrency subset beyond the named concurrency checkpoints and regressions | No blanket proof claim: the live strict suite proves the explicit PR11.8b checkpoint plus the named regression fixtures only. Source-level select semantics, I/O seam wrappers, and runtime scheduling/timing obligations remain external as `PS-007`, `PS-019`, and `PS-031` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | yes | yes | yes | no | no | emitted-package proof remains selective, while source/runtime obligations stay external | yes |
| I/O seams outside pure emitted packages | runtime wrapper boundaries | Wrapper integration obligations are tracked separately from pure emitted-package proof and remain `PS-019` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | n/a | n/a | n/a | no | no | wrapper/runtime mechanisms and interface contracts | yes |

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

Even after this checkpoint, faithful source-level `select ... or delay ...`
semantics, I/O seam wrappers, and Jorvik/Ravenscar runtime scheduling/locking
obligations remain outside direct emitted-package GNATprove proof as `PS-007`,
`PS-019`, and `PS-031` in
[`docs/post_pr10_scope.md`](post_pr10_scope.md).

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
