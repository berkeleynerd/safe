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
- `tests/positive/rule2_binary_search.safe`
- `tests/positive/rule3_average.safe`
- `tests/positive/rule1_parameter.safe`
- `tests/positive/ownership_move.safe`
- `tests/positive/rule4_linked_list.safe`
- `tests/positive/rule5_normalize.safe`
- `tests/positive/channel_pingpong.safe`
- `tests/positive/channel_pipeline.safe`
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

| Feature Class | Representative Fixtures | Frontend Accepted | Ada Emitted | Compile Validated | GNATprove Flow | GNATprove Prove | Exception-Backed Obligation | Deferred Beyond PR10 |
|---------------|-------------------------|-------------------|-------------|-------------------|----------------|-----------------|-----------------------------|----------------------|
| Rule 1 wide arithmetic subset | `rule1_averaging.safe`, `rule1_parameter.safe` | yes | yes | yes | yes | yes | none | no |
| Rule 2 index-safety subset | `rule2_binary_search.safe` | yes | yes | yes | yes | yes | none | no |
| Rule 3 division-safety subset | `rule3_average.safe` | yes | yes | yes | yes | yes | none | no |
| Rule 4 null-dereference subset | `rule4_linked_list.safe` | yes | yes | yes | yes | yes | none | no |
| Rule 5 floating-point subset | `rule5_normalize.safe` | yes | yes | yes | yes | yes | none | no |
| Sequential ownership move subset | `ownership_move.safe` | yes | yes | yes | yes | yes | none | no |
| Concurrency ping-pong subset | `channel_pingpong.safe` | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof | no |
| Concurrency pipeline subset | `channel_pipeline.safe` | yes | yes | yes | yes | yes | Jorvik/Ravenscar runtime scheduling remains outside direct GNATprove proof | no |
| Select-with-delay subset | `select_with_delay.safe` | yes | yes | yes | yes | yes | Polling latency and wall-clock timing fidelity remain runtime-backed rather than solver-proved | no |
| Other currently emitted sequential fixtures outside the PR10 corpus | current PR09 and PR08 accepted sequential subset | yes | yes | yes | no | no | none | yes |
| Other currently emitted concurrency fixtures outside the PR10 corpus | current PR08 concurrency subset beyond the three PR10 fixtures | yes | yes | yes | no | no | Jorvik/Ravenscar runtime behaviour plus runtime timing remain external | yes |
| I/O seams outside pure emitted packages | runtime wrapper boundaries | n/a | n/a | n/a | no | no | wrapper/runtime mechanisms and interface contracts | yes |

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
