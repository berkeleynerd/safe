# Pre-PR12.1 Compiler Audit

Tracking issue: https://github.com/berkeleynerd/safe/issues/332
Project board: https://github.com/users/berkeleynerd/projects/4/views/1
Audit SHA: `e5a57f1d8f3056646634f9a2ff8108926b1452e4`
Audit doc ref: `main`
Ripgrep: `ripgrep 15.1.0 (rev af60c2de9d)`
Next action: Phase 1A - fail-closed walker fall-through sweep.

This is the canonical working record for the pre-PR12.1 Safe compiler audit.
The code under audit is pinned at `Audit SHA`; this document remains a living
artifact on `main`.

## Operating Rules

- Scope: Ada sources in `compiler_impl/src/`, `compiler_impl/stdlib/ada/`,
  `companion/`, plus Ada-facing docs and fixtures where relevant.
- Non-goals: Python audit, re-proving the emitter, replacing normal PR review,
  and superseding retained PR10.1 ledger items.
- Parent issue checklist links target this living document on `main`.
- CPA source locations use `path:line@AUDIT_SHA`.
- Section headers are frozen after Phase 0. Any rename requires a parent-issue
  checklist update.
- Canary corpus is frozen in Phase 0. New canaries landing mid-audit are handled
  after Phase 4 or in a later cycle.
- "Soundness x now" means a soundness defect in a hot code path that would ship
  to users if not fixed immediately.
- Soundness x now findings interrupt the audit: file a dedicated issue/PR before
  continuing.
- Audit entries may be candidates; GitHub defect issues require confirmation or
  minimized repro.
- Follow-up issues close when their scoped work is documented or fixed as stated,
  not when the entire audit finishes.
- Assignee is set on the parent issue when audit kickoff begins. Phase 2
  deep-dive owners are recorded in each doc section header.
- Deep Audit workflow is not available in this checkout; do not depend on it
  unless a separate workflow is added.

## CPA Entry Format

Use structured entries instead of wide Markdown tables.

```md
### CPA-001 - Short Finding Title
- Area:
- Location: path:line@AUDIT_SHA
- Severity: soundness | correctness | hygiene
- Urgency: now | before-PR12.1 | whenever
- Confidence: candidate | needs-repro | confirmed | not-an-issue
- Outcome: open | promoted | fixed | ledger | rejected
- Enforcement proposal: yes | no | deferred
- Evidence:
- Counterfactual:
- Target:
- Links:
```

### Field Values

- Severity:
  - `soundness`: emits wrong code, crashes on valid input, or falsely admits an
    invariant.
  - `correctness`: accepts invalid input, rejects valid input, or produces an
    incorrect/misleading diagnostic.
  - `hygiene`: duplication, non-behavioral dead code, style, or documentation
    drift.
- Urgency:
  - `now`: blocks active work or is soundness x now.
  - `before-PR12.1`: should land before the PR12.1 rewrite inherits the debt.
  - `whenever`: retain in the ledger without scheduling pressure.
- Confidence:
  - `candidate`: suspicious pattern found, not yet confirmed.
  - `needs-repro`: likely issue but needs a minimized fixture or stronger proof.
  - `confirmed`: evidence is sufficient for a fix, issue, or ledger item.
  - `not-an-issue`: reviewed and intentionally safe or out of scope.
- Outcome:
  - `open`: unresolved audit entry.
  - `promoted`: moved to a GitHub issue or PR.
  - `fixed`: fixed as part of active work.
  - `ledger`: retained for later without immediate implementation.
  - `rejected`: closed as not an issue.

### Valid Confidence/Outcome Pairs

| Confidence | Valid outcomes |
| --- | --- |
| `candidate` | `open` |
| `needs-repro` | `open` |
| `confirmed` | `open`, `promoted`, `fixed`, `ledger` |
| `not-an-issue` | `rejected` |

## Follow-Up Issue Template

Use this template for enforcement-check promotions and confirmed defects.

```md
## Summary

## Audit Evidence

## Proposed Enforcement Mechanism

## Acceptance Criteria

## Links
```

For enforcement proposals, label the follow-up issue `infrastructure` and name
the proposed mechanism, such as grep-based CI, GNAT warning policy, or future
`safec` warning support.

## Baseline Counts

Commands run at `Audit SHA`:

```bash
git rev-parse HEAD
rg --version
rg -c 'when others =>' compiler_impl/src compiler_impl/stdlib/ada
rg -c 'SPARK_Mode \(Off\)' compiler_impl/src compiler_impl/stdlib/ada
rg -c 'Raise_Unsupported' compiler_impl/src
rg -c 'pragma Assume|pragma Annotate \(GNATprove' compiler_impl/src compiler_impl/stdlib/ada
find samples \( -name '*canary*.safe' -o -name 'surface_tour.safe' \) -print | sort
```

Summary:

| Pattern | Total |
| --- | ---: |
| `when others =>` | 183 |
| `SPARK_Mode (Off)` | 36 |
| `Raise_Unsupported` | 38 |
| `pragma Assume` / `pragma Annotate (GNATprove, ...)` | 1 |
| Frozen canaries | 1 |

### Baseline Details

`when others =>`:

```text
compiler_impl/src/safe_frontend-mir_bronze.adb:3
compiler_impl/src/safe_frontend-mir_validate.adb:1
compiler_impl/src/safe_frontend-ada_emit-proofs.adb:15
compiler_impl/src/safe_frontend-ada_emit.adb:5
compiler_impl/src/safe_frontend-ada_emit-expressions.adb:13
compiler_impl/src/safe_frontend-check_lower.adb:5
compiler_impl/src/safe_frontend-mir_json.adb:1
compiler_impl/src/safe_frontend-mir_analyze.adb:19
compiler_impl/src/safe_frontend-driver.adb:7
compiler_impl/src/safe_frontend-check_emit.adb:11
compiler_impl/src/safe_frontend-ada_emit-statements.adb:31
compiler_impl/src/safe_frontend-ada_emit-internal.adb:3
compiler_impl/src/safe_frontend-ada_emit-types.adb:9
compiler_impl/src/safe_frontend-json.adb:1
compiler_impl/src/safe_frontend-check_parse.adb:4
compiler_impl/src/safe_frontend-ada_emit-channels.adb:1
compiler_impl/src/safe_frontend-mir_write.adb:6
compiler_impl/src/safe_frontend-check_resolve.adb:48
```

`SPARK_Mode (Off)`:

```text
compiler_impl/stdlib/ada/safe_array_rt.ads:1
compiler_impl/stdlib/ada/safe_string_rt.ads:2
compiler_impl/stdlib/ada/safe_ownership_rt.adb:1
compiler_impl/stdlib/ada/safe_string_rt.adb:2
compiler_impl/stdlib/ada/safe_array_rt.adb:1
compiler_impl/stdlib/ada/safe_array_identity_rt.adb:1
compiler_impl/stdlib/ada/safe_array_identity_rt.ads:1
compiler_impl/src/safe_frontend-ada_emit.adb:1
compiler_impl/src/safe_frontend-ada_emit-channels.adb:26
```

`Raise_Unsupported`:

```text
compiler_impl/src/safe_frontend-ada_emit-expressions.adb:18
compiler_impl/src/safe_frontend-ada_emit-internal.adb:2
compiler_impl/src/safe_frontend-ada_emit-statements.adb:13
compiler_impl/src/safe_frontend-ada_emit-types.adb:3
compiler_impl/src/safe_frontend-ada_emit-internal.ads:2
```

`pragma Assume` / `pragma Annotate (GNATprove, ...)`:

```text
compiler_impl/src/safe_frontend-ada_emit-statements.adb:1
```

## Phase 0 - Scaffold And Baseline

Status: complete locally; commit/push pending.

Deliverables:

- Audit document scaffold.
- Baseline counts.
- CPA entry template and value definitions.
- Follow-up issue template.
- Frozen canary corpus.
- Worked Phase 2 permutation example.

## Phase 1A - Fail-Closed Walker Fall-Through

Enforcement default: likely yes.

Findings:

None yet.

## Phase 1B - When-Others Exhaustiveness

Enforcement default: likely yes.

Findings:

None yet.

## Phase 1C - Wide Integer Arithmetic Safety

Enforcement default: likely yes or deferred depending on false-positive rate.

Findings:

None yet.

## Phase 1D - GNATprove Trust Boundaries

Enforcement default: decide during sweep.

Findings:

None yet.

## Phase 1E - SPARK Mode Off Islands

Enforcement default: likely yes.

Findings:

None yet.

## Phase 1F - Dead Code After Unconditional Raise

Enforcement default: likely yes.

Findings:

None yet.

## Phase 1G - Spec Body Contract Drift

Enforcement default: decide during sweep.

Findings:

None yet.

## Phase 1H - Stdlib Runtime Trust Boundaries

Enforcement default: decide during sweep.

Baseline: `docs/pr1122h-stdlib-contract-audit.md`.

Findings:

None yet.

## Phase 1I - Docs And Fixture Drift

Enforcement default: decide during sweep.

Findings:

None yet.

## Phase 2 - Large-File Deep Dives

Use this section for permutation-based file audits. Record owner in each
subsection header when assigned. `safe_frontend-ada_emit-statements.adb` and
`safe_frontend-check_resolve.adb` require an interim checkpoint at roughly 50%.

### Worked Permutation Example

Example target: statement emission in
`compiler_impl/src/safe_frontend-ada_emit-statements.adb@AUDIT_SHA`.

Matrix shape:

| Statement family | Output classification | Boundary permutations | Expected fail mode |
| --- | --- | --- | --- |
| Assignment | scalar, heap-backed, shared-root, indexed target | local vs global root; same-root alias; empty slice | emit proof-safe assignment or explicit unsupported diagnostic |
| Procedure call | pure observer, local mutator, package/global effect, unknown | value actual vs `mut` actual; imported vs local callee | preserve effect summary or fail closed with source diagnostic |
| Loop | static range, dynamic range, while variant | empty range; one element; max/min integer bounds | emit variant/invariant or reject before emission |
| Case/match/select | exhaustive, defaulted, unsupported arm shape | missing branch; nonstable scrutinee; channel readiness | emit explicit branch lowering or reject before emission |
| Raise_Unsupported path | unsupported node kind | every fallback after unconditional raise | no dead code after raise; diagnostic preserves source context |

Each deep dive should list:

- Dispatchers/functions examined.
- Node/type/effect families considered.
- Boundary permutations simulated.
- CPA entries for findings or an explicit no-finding rationale.

### safe_frontend-ada_emit-statements.adb

Owner: TBD.

Findings:

None yet.

### safe_frontend-check_resolve.adb

Owner: TBD.

Findings:

None yet.

### safe_frontend-mir_analyze.adb

Owner: TBD.

Findings:

None yet.

### safe_frontend-ada_emit-types.adb

Owner: TBD.

Findings:

None yet.

### safe_frontend-ada_emit-expressions.adb

Owner: TBD.

Findings:

None yet.

### safe_frontend-check_emit.adb

Owner: TBD.

Findings:

None yet.

### safe_frontend-ada_emit-channels.adb

Owner: TBD.

Findings:

None yet.

## Phase 3 - Canary And Cross-Cutting Replay

Replay only the Phase 0 frozen canary corpus. Classify failures into existing
CPA entries or create new confirmed entries. Promote canary defect issues only
after minimized repros confirm distinct root causes.

### Frozen Canary Corpus

Captured at `Audit SHA`:

```text
samples/showcase/surface_tour.safe
```

### Arithmetic And Classification Replay

Focus areas:

- Division/mod/rem lattice operations near zero and type extremes.
- Static-length fast-path stale reads.
- Classification helper over- and under-invalidation.
- Sibling files affected by findings from Phase 2.

Findings:

None yet.

## Phase 4 - Triage Drift Delta Ledger Sign-Off

Run:

```bash
git log e5a57f1d8f3056646634f9a2ff8108926b1452e4..main -- compiler_impl/src/ compiler_impl/stdlib/ada/ companion/
```

Classify each changed path as:

- `addresses-existing-finding`
- `invalidates-finding`
- `new-code-needs-mini-sweep`

Promoted PRs:

None yet.

Ledger:

None yet.

Sign-off:

Pending.
