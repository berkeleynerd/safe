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

Access-typed channel elements and composite channel elements containing
access-type subcomponents are spec-excluded. The repo keeps representative
rejection fixtures for that boundary:

- `tests/concurrency/channel_access_type.safe`
- `tests/concurrency/try_send_ownership.safe`
- `tests/concurrency/select_ownership_binding.safe`
- `tests/negative/neg_channel_access_component.safe`

## Matrix

The repository still contains accepted and emitted samples beyond the frozen
PR10 representative set. PR10.2, PR10.3, and PR10.6 now close the currently
accepted sequential proof surface, while concurrency residuals such as
`tests/positive/channel_pipeline.safe` remain outside the proved corpus.

| Feature Class | Representative Fixtures | Coverage Notes | Frontend Accepted | Ada Emitted | Compile Validated | GNATprove Flow | GNATprove Prove | Exception-Backed Obligation | Deferred Beyond PR10 |
|---------------|-------------------------|----------------|-------------------|-------------|-------------------|----------------|-----------------|-----------------------------|----------------------|
| Rule 1 wide arithmetic subset | `tests/positive/rule1_averaging.safe`, `tests/positive/rule1_parameter.safe` | Loop-carried wide arithmetic with an explicit narrowing return, plus validated narrowing before cross-subprogram parameter passing. | yes | yes | yes | yes | yes | none | no |
| Rule 2 function-return index-safety subset | `tests/positive/rule2_binary_search_function.safe` | Bounded-array binary search as a record-returning function with midpoint indexing and multiple early returns. | yes | yes | yes | yes | yes | none | no |
| Rule 3 division-safety subset | `tests/positive/rule3_divide.safe` | Typed nonzero divisor plus guarded variable-divisor division. | yes | yes | yes | yes | yes | none | no |
| Rule 4 observer-traversal subset | `tests/positive/rule4_linked_list_sum.safe` | Null-guarded linked-list prefix accumulation with dereference plus bounded count and total arithmetic. | yes | yes | yes | yes | yes | none | no |
| Rule 5 computed-divisor vector subset | `tests/positive/rule5_vector_normalize.safe` | Three-field floating-point record computation with a branch-computed positive divisor derived from all components and a returned normalized component. | yes | yes | yes | yes | yes | none | no |
| Sequential ownership move subset | `tests/positive/ownership_move.safe` | Single-owner move with post-move nulling and target-only dereference. GNATprove `prove` here covers emitted runtime checks; the frontend Silver ownership analysis is the mechanism that prevents use-after-free across the accepted ownership subset. | yes | yes | yes | yes | yes | none within the selected `ownership_move` subset; broader cleanup ordering remains deferred as `PS-029` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Post-PR10 ownership proof-expansion set | `tests/positive/ownership_borrow.safe`, `tests/positive/ownership_observe.safe`, `tests/positive/ownership_observe_access.safe`, `tests/positive/ownership_return.safe`, `tests/positive/ownership_inout.safe`, `tests/positive/ownership_early_return.safe` | Accepted ownership fixtures beyond the frozen PR10 `ownership_move` representative. PR10.3 proves this exact six-fixture set as the first post-PR10 sequential expansion without weakening the frozen PR10 claim. | yes | yes | yes | yes | yes | frontend Silver ownership analysis still governs legality, while emitted GNATprove here covers runtime checks and proof obligations for this expanded ownership set; broader cleanup-ordering semantics still remain `PS-029` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Concurrency ping-pong subset | `tests/positive/channel_pingpong.safe` | Two priority-bearing tasks exchanging bounded channel messages in both directions. | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof; see `PS-031` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Concurrency pipeline compute subset | `tests/positive/channel_pipeline_compute.safe` | Three-task channel pipeline with arithmetic in the filter and consumer task bodies. | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof; see `PS-031` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Select-with-delay emitted polling subset | `tests/concurrency/select_with_delay.safe`, `tests/concurrency/select_with_delay_multiarm.safe` | Frozen PR10 coverage proves one receive arm plus one delay arm, and supplemental hardening additionally proves a two-channel-arm success-path variant. Both are proved through the emitted polling-based lowering, not source-level blocking fairness or timing semantics. | yes | yes | yes | yes | yes | Polling-based lowering is proved, while source-level blocking fairness, latency, and timing semantics remain deferred as `PS-007` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | no |
| Access-typed channel elements and composites containing access-type subcomponents | `tests/concurrency/channel_access_type.safe`, `tests/concurrency/try_send_ownership.safe`, `tests/concurrency/select_ownership_binding.safe`, `tests/negative/neg_channel_access_component.safe` | Spec-excluded by channel element legality. The frontend rejects these declarations before emit, flow, or prove. | no | no | no | no | no | n/a | no |
| Other currently emitted sequential fixtures outside the PR10 corpus | remaining PR09 and PR08 accepted sequential subset beyond the ownership set above | The remaining accepted sequential emission beyond the frozen PR10 representatives, the PR10.2 Rule 5 closure, and the PR10.3 ownership expansion is now proved under the dedicated PR10.6 gate. This row remains as the canonical statement that the broader accepted sequential subset is now frontend-accepted, emitted, compile-valid, and GNATprove-proved. | yes | yes | yes | yes | yes | none | no |
| Other currently emitted concurrency fixtures outside the PR10 corpus | current PR08 concurrency subset beyond the three PR10 proof fixtures | Additional accepted concurrency emission remains outside the selected PR10 proof representatives. Broader proof expansion remains retained as `PS-018`, while runtime timing and scheduling obligations remain `PS-031` in [`docs/post_pr10_scope.md`](post_pr10_scope.md). | yes | yes | yes | no | no | Jorvik/Ravenscar runtime behaviour plus runtime timing remain external | yes |
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
