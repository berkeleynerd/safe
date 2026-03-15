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

## Matrix

The following accepted and emitted samples remain in the repository but are not
PR10 proof representatives: `rule2_binary_search.safe`, `rule3_average.safe`,
`rule4_linked_list.safe`, `rule5_normalize.safe`, and `channel_pipeline.safe`.

| Feature Class | Representative Fixtures | Coverage Notes | Frontend Accepted | Ada Emitted | Compile Validated | GNATprove Flow | GNATprove Prove | Exception-Backed Obligation | Deferred Beyond PR10 |
|---------------|-------------------------|----------------|-------------------|-------------|-------------------|----------------|-----------------|-----------------------------|----------------------|
| Rule 1 wide arithmetic subset | `rule1_averaging.safe`, `rule1_parameter.safe` | Loop-carried wide arithmetic with an explicit narrowing return, plus validated narrowing before cross-subprogram parameter passing. | yes | yes | yes | yes | yes | none | no |
| Rule 2 function-return index-safety subset | `rule2_binary_search_function.safe` | Bounded-array binary search as a record-returning function with midpoint indexing and multiple early returns. | yes | yes | yes | yes | yes | none | no |
| Rule 3 division-safety subset | `rule3_divide.safe` | Typed nonzero divisor plus guarded variable-divisor division. | yes | yes | yes | yes | yes | none | no |
| Rule 4 observer-traversal subset | `rule4_linked_list_sum.safe` | Null-guarded linked-list prefix accumulation with dereference plus bounded count and total arithmetic. | yes | yes | yes | yes | yes | none | no |
| Rule 5 computed-divisor vector subset | `rule5_vector_normalize.safe` | Three-field floating-point record computation with a branch-computed positive divisor derived from all components and a returned normalized component. | yes | yes | yes | yes | yes | none | no |
| Sequential ownership move subset | `ownership_move.safe` | Single-owner move with post-move nulling and target-only dereference. | yes | yes | yes | yes | yes | none | no |
| Concurrency ping-pong subset | `channel_pingpong.safe` | Two priority-bearing tasks exchanging bounded channel messages in both directions. | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof | no |
| Concurrency pipeline compute subset | `channel_pipeline_compute.safe` | Three-task channel pipeline with arithmetic in the filter and consumer task bodies. | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof | no |
| Select-with-delay emitted polling subset | `select_with_delay.safe` | One receive arm plus one delay arm proved through the emitted polling-based lowering, not source-level blocking fairness or timing semantics. | yes | yes | yes | yes | yes | Polling-based lowering is proved, while source-level blocking fairness, latency, and timing semantics remain runtime-backed rather than solver-proved. | no |
| Channel access-type compile-only subset | `channel_access_type.safe` | Channel element defaults and access-typed channel bodies are compile-validated only. | yes | yes | yes | no | no | Jorvik/Ravenscar runtime behaviour plus channel-body proof coverage remain external to PR10. | yes |
| Other currently emitted sequential fixtures outside the PR10 corpus | current PR09 and PR08 accepted sequential subset | Additional accepted sequential emission remains outside the selected PR10 proof representatives. | yes | yes | yes | no | no | none | yes |
| Other currently emitted concurrency fixtures outside the PR10 corpus | current PR08 concurrency subset beyond the three PR10 proof fixtures | Additional accepted concurrency emission remains outside the selected PR10 proof representatives. | yes | yes | yes | no | no | Jorvik/Ravenscar runtime behaviour plus runtime timing remain external | yes |
| I/O seams outside pure emitted packages | runtime wrapper boundaries | Wrapper integration obligations are tracked separately from pure emitted-package proof. | n/a | n/a | n/a | no | no | wrapper/runtime mechanisms and interface contracts | yes |

## PR10 Assurance Policy

Inside the selected emitted corpus, PR10 uses an **all-proved-only** policy:

- zero warnings
- zero justified checks
- zero unproved checks

Outside that selected corpus, this matrix is authoritative. If a feature is not
marked `GNATprove prove = yes`, it must not be described as emitted-output
Silver/Bronze verified.

## Residual Ownership

Residual items after PR10 are tracked in
[`docs/post_pr10_scope.md`](post_pr10_scope.md).
