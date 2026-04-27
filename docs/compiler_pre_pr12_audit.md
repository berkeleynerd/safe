# Pre-PR12.1 Compiler Audit

Tracking issue: https://github.com/berkeleynerd/safe/issues/332
Project board: https://github.com/users/berkeleynerd/projects/4/views/1
Audit SHA: `5450c30406e5535cab772e511e1ec326217f16f1`
Audit doc ref: `main`
Ripgrep: `ripgrep 15.1.0 (rev af60c2de9d)`
Next action: Phase 1D - GNATprove trust-boundary triage.

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
  - `now`: should be resolved before continuing the relevant workstream. Only
    `soundness` severity plus `now` urgency triggers the audit interrupt rule.
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

## GNAT Tool Adoption Notes

Tracked adoption/evaluation work:

- GNATcoverage (`gnatcov`): #338 tracks a reporting-only CI coverage artifact
  with no initial threshold gate.
- GNATprove `--mode=check`: #339 tracks a fast-fail CI legality step separate
  from the full proof lane.
- `gnatstack`: #340 tracks per-task stack-usage reporting and budget checks in
  the embedded smoke lane.
- CodePeer / GNAT SAS: #341 tracks the commercial-license and scope decision.

Tools considered and not filed as standalone issues:

- GNATcheck: already treated as a separate adoption plan; no duplicate audit
  issue is created here.
- `gnatmetric`: fold baseline numbers into Phase 0 audit scaffolding rather than
  tracking a standalone issue.
- `gnatpp`: skip for now because it overlaps with and may conflict with existing
  `-gnaty*` style rules; calibration cost is not justified.
- `gnatdoc`: skip because Safe has a curated docs structure; generated Ada API
  docs add little value at this stage.
- `gnattest`: skip because Safe already has a fixture-based harness; migration
  cost is not justified.
- `libadalang` / `lal-refactor`: defer until GNATcheck or simpler checks prove
  insufficient for custom walker or exhaustiveness checks.
- Ada Language Server: treat as a developer-environment recommendation, not a
  CI or audit tracking item.

## Baseline Counts

Commands run at `Audit SHA` (each command emits the total reported in the summary).
Check out `Audit SHA` before running the `rg` commands.

```bash
git rev-parse 5450c30406e5535cab772e511e1ec326217f16f1
rg --version
rg -c -g '*.adb' -g '*.ads' 'when others =>' compiler_impl/src compiler_impl/stdlib/ada companion | awk -F: '{sum += $NF} END {print sum + 0}'
rg -c -g '*.adb' -g '*.ads' 'SPARK_Mode \(Off\)' compiler_impl/src compiler_impl/stdlib/ada companion | awk -F: '{sum += $NF} END {print sum + 0}'
rg -c -g '*.adb' -g '*.ads' 'Raise_Unsupported' compiler_impl/src compiler_impl/stdlib/ada companion | awk -F: '{sum += $NF} END {print sum + 0}'
rg -c -g '*.adb' -g '*.ads' 'pragma Assume|pragma Annotate \(GNATprove' compiler_impl/src compiler_impl/stdlib/ada companion | awk -F: '{sum += $NF} END {print sum + 0}'
git ls-tree -r --name-only 5450c30406e5535cab772e511e1ec326217f16f1 samples | awk '/(^|\/)([^\/]*canary[^\/]*\.safe|surface_tour\.safe)$/ {count++} END {print count + 0}'
```

Pin refresh note: Phase 1A intentionally advanced the audit pin from
`e5a57f1d8f3056646634f9a2ff8108926b1452e4` to
`5450c30406e5535cab772e511e1ec326217f16f1` because PR #346 and PR #348
landed the post-sprint walker hardening before the audit sweep began. The
Phase 1A sweep therefore audits current `main`, records those changes as
confirmed/protected, and uses the new static manifest as the durable regression
guard. The `when others =>` count remains Phase 1B input; Phase 1A only gates
walker-relevant fall-throughs and is not expected to eliminate all catch-alls.

Summary:

| Pattern | Total |
| --- | ---: |
| `when others =>` | 172 |
| `SPARK_Mode (Off)` | 36 |
| `Raise_Unsupported` | 38 |
| `pragma Assume` / `pragma Annotate (GNATprove, ...)` | 1 |
| Frozen canaries | 0 |

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
compiler_impl/src/safe_frontend-ada_emit-statements.adb:22
compiler_impl/src/safe_frontend-ada_emit-internal.adb:3
compiler_impl/src/safe_frontend-ada_emit-types.adb:9
compiler_impl/src/safe_frontend-json.adb:1
compiler_impl/src/safe_frontend-check_parse.adb:4
compiler_impl/src/safe_frontend-ada_emit-channels.adb:1
compiler_impl/src/safe_frontend-mir_write.adb:6
compiler_impl/src/safe_frontend-check_resolve.adb:46
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

The baseline commands include tracked Ada sources under
`compiler_impl/stdlib/ada/` and `companion/` via `*.adb` / `*.ads` globs. No
companion Ada source matched the baseline patterns at `Audit SHA`. The
`SPARK_Mode (Off)` count is the only pattern with `compiler_impl/stdlib/ada/`
matches, listed above; `when others =>`, `Raise_Unsupported`, and
`pragma Assume` / `pragma Annotate (GNATprove, ...)` had zero matches in
`compiler_impl/stdlib/ada/` and `companion/` at `Audit SHA`.

## Phase 0 - Scaffold And Baseline

Status: complete.

Deliverables:

- Audit document scaffold.
- Baseline counts.
- CPA entry template and value definitions.
- Follow-up issue template.
- Frozen canary corpus.
- Worked Phase 2 permutation example.

## Phase 1A - Fail-Closed Walker Fall-Through

Status: complete.

Enforcement default: yes.

Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`.

Mechanism:

- Regex-based V1 manifest over audited `case <expr>.Kind is` walker blocks.
- Permissive V1 semantics: only entries named in `AUDITED_WALKER_CASES` are
  enforced. New walkers must be added to the manifest by review discipline until
  a stricter discovery gate is justified.
- The gate is syntactic. It prevents audited walkers from regressing to silent
  `when others => null`, `return False`, `return 0`, or `Empty_Vector`
  fall-throughs, but fixture snapshots and proof checks remain the behavioral
  regression guard.
- The gate currently covers case-block walkers. If a future audited walker
  dispatches on kind with an `if` / `elsif` ladder, extend the gate before
  manifesting that walker.

Findings:

- Phase 1A confirmed and locked in the post-pin walker hardening from PR #346
  and PR #348.
- Phase 1A also hardened additional audited walkers that still had silent
  defaults or incomplete traversal after the pin refresh.
- The two remaining silent defaults in the manifest are intentional and carry
  explicit reasons below.
- The audit baseline `when others =>` count remains the Phase 1B input at the
  refreshed `Audit SHA`; Phase 1A only resolves walker-relevant fall-throughs
  and does not re-baseline the global catch-all count.
- The post-Phase-1A worktree has fewer catch-alls because resolved walker
  defaults were removed; Phase 1B should reconcile those against the manifest
  before sweeping the remaining global catch-alls.

### Phase 1A Manifest Summary

| Manifest entry | Outcome |
| --- | --- |
| `emit-statements.invalidate-mutated-call-actual-lengths.visit` | Confirmed prior hardening; manifest-gated. |
| `emit-statements.expr-uses-name` | Confirmed PR #346 hardening; manifest-gated. |
| `emit-statements.statement-uses-name` | Confirmed PR #346 hardening; manifest-gated. |
| `emit-statements.statement-blocks-overwrite-scan` | Confirmed post-pin hardening; manifest-gated. |
| `emit-statements.statement-overwrites-name-before-read` | Confirmed PR #348 hardening; manifest-gated. |
| `emit-statements.walk-statement-structure.statement` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.walk-statement-structure.select-arm` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.statements-declare-name` | Confirmed PR #346 hardening; manifest-gated. |
| `emit-statements.expr-mutating-call-count` | Confirmed PR #346 hardening; manifest-gated. |
| `emit-statements.statement-write-count` | Confirmed PR #346 hardening; manifest-gated. |
| `emit-statements.counted-while-expr-contains-call` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.counted-while-analyze-statement` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.counted-while-select-arm` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.shared-condition-needs-snapshot` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.shared-condition-collect-snapshots` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.analyze-accumulator-statement` | Confirmed PR #346 hardening; manifest-gated. |
| `emit-statements.collect-growable-accumulators` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.analyze-string-growth-statement` | Confirmed post-pin hardening; manifest-gated. |
| `emit-statements.collect-string-growth-accumulators` | Hardened in Phase 1A; manifest-gated. |
| `emit-statements.collect-string-accumulators` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.subprogram-uses-global-name.statements` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.subprogram-uses-global-name.select-arm` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.render-global-aspect.expr` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.render-global-aspect.statements` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.render-global-aspect.select-arm` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.access-param-precondition.expr-special-case` | Allowed silent default; generic child traversal follows for every expression field. |
| `emit-proofs.access-param-precondition.statements` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.access-param-precondition.select-arm` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.recursive-variant.expr` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.recursive-variant.statements` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.recursive-variant.select-arm-expression` | Hardened in Phase 1A; manifest-gated. |
| `emit-proofs.structural-traversal-accumulator.statements` | Allowed silent default; `return False` disables structural traversal lowering. |
| `emit.public-shared-helper.expr-local` | Hardened in Phase 1A; manifest-gated. |
| `emit.public-shared-helper.expr` | Hardened in Phase 1A; manifest-gated. |
| `emit.public-shared-helper.statements` | Hardened in Phase 1A; manifest-gated. |
| `emit.public-shared-helper.select-arm` | Hardened in Phase 1A; manifest-gated. |
| `emit-internal.statement-contains-exit` | Hardened in Phase 1A; manifest-gated. |
| `emit-internal.statement-falls-through` | Hardened in Phase 1A; manifest-gated. |
| `mir-bronze.walk-expr` | Hardened in Phase 1A; manifest-gated. |
| `mir-bronze.summary-for-op` | Hardened in Phase 1A; manifest-gated. |
| `mir-bronze.summary-for-terminator` | Hardened in Phase 1A; manifest-gated. |
| `mir-bronze.summary-for-select-arm` | Hardened in Phase 1A; manifest-gated. |

## Phase 1B - When-Others Exhaustiveness

Enforcement default: yes for scoped parser/resolver unblockers; likely yes for
the remaining full sweep after false-positive review.

Per-slice conventions:

- Any pass whose direct or downstream output lands in a serialized artifact
  captured by the standard manifests, including Ada source, MIR JSON,
  AST/typed/interface JSON, and line maps, requires explicit pre/post artifact
  diff; analyzer, driver, and utility slices rely on the standard gate plus
  `snapshot_emitted_ada.py --check`.
- JSON serializer slices record each converted fallback variant and its emitted
  output shape; Ada emitter slices record the helper-category behavior
  invariants they preserve.
- PR bodies for Phase 1B slices include preflight counts, raw baseline movement,
  artifact-diff result when applicable, proof-cache hit rate, and
  behavior-preservation confirmation.

Scoped parser/resolver unblocker:

- Status: complete for the PR12.1 grammar-overhaul dependency surface; full
  Phase 1B remains open.
- Scope: production parser/resolver Ada sources matching
  `compiler_impl/src/safe_frontend-check_(parse|resolve)*.adb`. The sweep
  excludes `compiler_impl/tests/`, emitter, MIR, driver, JSON, and stdlib
  sources.
- Baseline at this pass: 50 scoped `when others =>` sites
  (`safe_frontend-check_parse.adb`: 4, `safe_frontend-check_resolve.adb`: 46).
- Outcome: 42 enum-dispatch sites converted to explicit arms; 8 retained
  catch-alls remain for open numeric domains or cleanup/re-raise paths.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked parser/resolver `when others =>` in the scoped files.
- Retained catch-alls must be multiline and begin the branch with
  `--  when-others-ok: <specific rationale>`.
- Full remaining compiler source baseline after this unblocker: 101
  `when others =>` sites outside the completed parser/resolver conversions.

MIR analyzer slice:

- Status: complete for `compiler_impl/src/safe_frontend-mir_analyze.adb`;
  full Phase 1B remains open.
- Starting baseline at this pass: 19 raw `when others =>` sites in
  `safe_frontend-mir_analyze.adb`; 101 raw sites compiler-wide under
  `compiler_impl/src/`.
- Outcome: 15 closed-enum dispatch sites converted to explicit arms; 4
  retained catch-alls remain for exception-wrapping or best-effort probe paths.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked `when others =>` in the MIR analyzer.
- Retained catch-alls must be multiline and begin the branch with
  `--  when-others-ok: <specific rationale>`.
- Raw compiler-wide baseline after this slice: 86 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites
  still count until the full Phase 1B closeout switches to an unaudited-only
  progress metric.

Ada emit expressions slice:

- Status: complete for
  `compiler_impl/src/safe_frontend-ada_emit-expressions.adb`; full Phase 1B
  remains open.
- Starting baseline at this pass: 13 raw `when others =>` sites in
  `safe_frontend-ada_emit-expressions.adb`; 86 raw sites compiler-wide under
  `compiler_impl/src/`.
- Outcome: 13 closed-enum dispatch sites converted to explicit arms; 0
  retained catch-alls remain in this file.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked `when others =>` in the Ada expression emitter.
- Raw compiler-wide baseline after this slice: 73 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites
  still count until the full Phase 1B closeout switches to an unaudited-only
  progress metric.
- Files producing serialized output artifacts, including Ada source, JSON
  outputs, line maps, and interface manifests, require explicit pre/post
  artifact diff; analyzer, driver, and utility slices rely on the standard
  gate plus `snapshot_emitted_ada.py --check`.

Check emit slice:

- Status: complete for `compiler_impl/src/safe_frontend-check_emit.adb`;
  full Phase 1B remains open.
- Starting baseline at this pass: 11 raw `when others =>` sites in
  `safe_frontend-check_emit.adb`; 73 raw sites compiler-wide under
  `compiler_impl/src/`.
- Outcome: 11 closed-enum dispatch sites converted to explicit arms; 0
  retained catch-alls remain in this file.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked `when others =>` in the check JSON emitter.
- Raw compiler-wide baseline after this slice: 62 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites
  still count until the full Phase 1B closeout switches to an unaudited-only
  progress metric.
- Pre/post JSON artifact manifest comparison is required for this slice because
  it emits serialized AST, typed, and interface contract artifacts.

Ada emit types slice:

- Status: complete for `compiler_impl/src/safe_frontend-ada_emit-types.adb`;
  full Phase 1B remains open.
- Starting baseline at this pass: 9 raw `when others =>` hits in
  `safe_frontend-ada_emit-types.adb`; 62 raw sites compiler-wide under
  `compiler_impl/src/`.
- Outcome: 8 closed-enum dispatch sites converted to explicit arms; 0 retained
  catch-alls remain in this file. One raw hit remains because the file emits a
  generated Ada `when others =>` string literal, not a syntactic case arm.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked syntactic `when others =>` arm in the Ada type emitter.
- The marker gate uses a start-of-line syntactic-arm regex, so embedded generated
  Ada `when others =>` strings are gate-safe when they do not appear as Ada arms.
- Raw compiler-wide baseline after this slice: 54 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites and
  generated-source string hits still count until the full Phase 1B closeout
  switches to an unaudited-only progress metric.
- Pre/post emitted-Ada artifact manifest comparison is required for this slice
  because it emits Ada source and line-map artifacts.

Ada emit statements slice:

- Status: complete for
  `compiler_impl/src/safe_frontend-ada_emit-statements.adb`; full Phase 1B
  remains open.
- Starting baseline at this pass: 11 raw `when others =>` hits in
  `safe_frontend-ada_emit-statements.adb`, of which 10 were syntactic arms; 54
  raw sites compiler-wide under `compiler_impl/src/`.
- Outcome: 10 closed-enum dispatch sites converted to explicit arms; 0 retained
  catch-alls remain in this file. One raw hit remains because the file emits a
  generated Ada `when others =>` string literal, not a syntactic case arm.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked syntactic `when others =>` arm in the Ada statement
  emitter.
- The marker gate uses a start-of-line syntactic-arm regex, so embedded
  generated Ada `when others =>` strings are gate-safe when they do not appear
  as Ada arms.
- Raw compiler-wide baseline after this slice: 44 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites and
  generated-source string hits still count until the full Phase 1B closeout
  switches to an unaudited-only progress metric.
- Pre/post emitted-Ada artifact manifest comparison is required for this slice
  because it emits Ada source and line-map artifacts.

MIR writer slice:

- Status: complete for `compiler_impl/src/safe_frontend-mir_write.adb`; full
  Phase 1B remains open.
- Starting baseline at this pass: 6 raw `when others =>` hits in
  `safe_frontend-mir_write.adb`; 44 raw sites compiler-wide under
  `compiler_impl/src/`.
- Outcome: 6 closed-enum dispatch sites converted to explicit arms; 0 retained
  catch-alls remain in this file.
- Preserved JSON fallback shapes: `Scalar_Value_None` emits `"kind":"none"`;
  `Expr_Unknown` emits only the existing base expression fields;
  `Select_Arm_Unknown` emits `"<unknown>"` in the kind expression and the
  span-only fallback select-arm object; `Op_Unknown` and `Terminator_Unknown`
  emit only their existing base `kind`/`span` fields.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked syntactic `when others =>` arm in the MIR writer.
- Raw compiler-wide baseline after this slice: 38 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites and
  generated-source string hits still count until the full Phase 1B closeout
  switches to an unaudited-only progress metric.
- Pre/post MIR JSON artifact manifest comparison is required for this slice
  because it emits serialized MIR output.
- This closes the current direct emit/serialization writer family. Downstream
  passes whose output feeds captured artifacts still use artifact-diff
  verification when audited.

Check lower slice:

- Status: complete for `compiler_impl/src/safe_frontend-check_lower.adb`;
  full Phase 1B remains open.
- Starting baseline at this pass: 5 raw `when others =>` hits in
  `safe_frontend-check_lower.adb`; 38 raw sites compiler-wide under
  `compiler_impl/src/`.
- Outcome: 5 closed-enum dispatch sites converted to explicit arms; 0 retained
  catch-alls remain in this file.
- Preserved lowering behavior: unsupported expression kinds still map to
  `GM.Expr_Unknown` or receive no extra MIR fields; unknown/return terminators
  still have no reachable successor edges; non-stable case scrutinees still
  return `False`; unknown/match statements still return the current block id.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked syntactic `when others =>` arm in check lowering.
- Raw compiler-wide baseline after this slice: 33 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites and
  generated-source string hits still count until the full Phase 1B closeout
  switches to an unaudited-only progress metric.
- Pre/post MIR JSON artifact manifest comparison is required for this slice
  because lowering output feeds serialized MIR.

Ada emit proofs slice:

- Status: complete for
  `compiler_impl/src/safe_frontend-ada_emit-proofs.adb`; full Phase 1B remains
  open.
- Starting baseline at this pass: 5 raw `when others =>` hits in
  `safe_frontend-ada_emit-proofs.adb`; 33 raw sites compiler-wide under
  `compiler_impl/src/`.
- Outcome: 5 closed-enum dispatch sites converted to explicit arms; 0 retained
  catch-alls remain in this file.
- Preserved proof-emitter behavior: proof precondition expression collection
  still ignores non-index/select expressions before recursive descent; alias
  postcondition collection still ignores non-assignment, non-control-flow
  statements; safe-condition and safe-return predicates retain their symmetric
  accepted expression kinds and default-false behavior; structural accumulator
  rendering still rejects statement kinds outside assignment and simple `if`.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked syntactic `when others =>` arm in the Ada proof
  emitter.
- Raw compiler-wide baseline after this slice: 28 `when others =>` sites under
  `compiler_impl/src/`. This is a raw syntactic count; retained marked sites and
  generated-source string hits still count until the full Phase 1B closeout
  switches to an unaudited-only progress metric.
- Pre/post emitted-Ada artifact manifest comparison is required for this slice
  because the proof emitter contributes generated Ada assertions and helper
  logic.
- Remaining Phase 1B tail classes are retained audited parser/resolver/MIR
  analyzer sites, driver cleanup handlers, JSON/parser helpers, and small
  Ada-emitter utility files.

Driver marker slice:

- Status: complete for `compiler_impl/src/safe_frontend-driver.adb`; full
  Phase 1B remains open.
- Starting baseline at this pass: 7 bare `when others =>` handlers and 6 named
  `when Error : others =>` handlers in `safe_frontend-driver.adb`; 31 syntactic
  bare-or-named catch-alls compiler-wide under `compiler_impl/src/`.
- Outcome: 13 retained driver exception handlers annotated with
  `when-others-ok:` rationale markers; 0 closed-enum dispatch sites converted.
- Preserved driver behavior: file writes still close and reraise on failure;
  best-effort cleanup still suppresses cleanup exceptions; rollback paths still
  preserve the original replace failure; command boundaries still convert
  unexpected internal exceptions to existing diagnostic/internal-exit results;
  emit still removes partial Ada artifacts before reraising the original emit
  failure.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now recognizes both bare `when others =>` and named handlers such as
  `when Error : others =>`, ignores generated-source string literals and
  commented-out examples, and fails any unmarked retained catch-all in the
  driver.
- Raw historical baseline after this slice remains 28 bare `when others =>`
  hits under `compiler_impl/src/`; retained markers do not change syntax. The
  operational bare-or-named unaudited count drops from 19 to 6 because the
  driver handlers are now marker-audited.
- Phase 1B slice convention: conversion slices enumerate closed variants and
  rely on compiler exhaustiveness; marker slices annotate defensive cleanup or
  command-boundary catch-alls with rationale comments.
- Local level-2 convention: run local `--no-cache --level 2` for executable Ada
  or proof-input changes. Marker/audit-script slices may rely on CI's no-cache
  Prove gate after local cached proofs pass.
- Remaining Phase 1B tail shape is now split between JSON/parser helper marker
  work and small Ada-emitter utility conversion work; already-retained audited
  parser/resolver/MIR analyzer sites are accounting noise rather than new
  implementation work.

JSON/MIR helper slice:

- Status: complete for `compiler_impl/src/safe_frontend-json.adb`,
  `compiler_impl/src/safe_frontend-mir_json.adb`, and
  `compiler_impl/src/safe_frontend-mir_validate.adb`; full Phase 1B remains
  open.
- Starting baseline at this pass: 3 target-file syntactic catch-alls; 31
  syntactic bare-or-named catch-alls compiler-wide under `compiler_impl/src/`;
  28 raw historical `when others =>` hits under `compiler_impl/src/`.
- Outcome: 1 retained JSON character-default arm annotated with a
  `when-others-ok:` rationale marker; 2 closed-enum MIR select-arm dispatches
  converted to explicit `Select_Arm_Unknown` arms.
- Preserved helper behavior: JSON escaping still preserves non-special
  characters verbatim; MIR JSON loading still leaves unknown select-arm kinds
  as `Select_Arm_Unknown`; MIR validation still rejects unknown select-arm
  kinds with the existing unsupported-kind diagnostic text.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked syntactic `when others =>` arm in these files.
  `safe_frontend-mir_json.adb` and `safe_frontend-mir_validate.adb` have zero
  retained markers and are included as future-regression guards.
- Raw historical baseline after this slice: 26 `when others =>` hits under
  `compiler_impl/src/`. The syntactic bare-or-named count is 29, and the
  operational bare-or-named unaudited count is 3.
- No artifact manifest diff is required for this slice: `json.adb` provides
  JSON escaping primitives, `mir_json.adb` loads MIR JSON via `Load_File`, and
  `mir_validate.adb` validates loaded MIR. Serialized writers live in
  `mir_write.adb`, `check_emit.adb`, and `ada_emit-*`.
- Hybrid Phase 1B slices, mixing marker retention with conversion, are allowed
  when the file set is small and each per-file action is unambiguous from the
  site shape. Larger or ambiguous sets should split into marker-only and
  conversion-only PRs.
- Phase 1B is complete when the operational unaudited count reaches 0;
  retained marked sites remain as documented residual syntax.

Final Ada-emitter utility slice:

- Status: complete for `compiler_impl/src/safe_frontend-ada_emit.adb` and
  `compiler_impl/src/safe_frontend-ada_emit-internal.adb`; Phase 1B operational
  closeout is complete.
- Starting baseline at this pass: 3 target-file syntactic catch-alls; 29
  syntactic bare-or-named catch-alls compiler-wide under `compiler_impl/src/`;
  26 raw historical `when others =>` hits under `compiler_impl/src/`.
- Outcome: 2 retained bare Ada-emitter exception handlers annotated with
  `when-others-ok:` rationale markers; 1 closed-enum `Expr_Kind` dispatch
  converted to explicit arms.
- Preserved utility behavior: synthetic dependency resolution failures still
  raise the existing internal diagnostic; growable dependency probe failures
  still raise the existing internal diagnostic; `Root_Name` still returns the
  resolved root for identifiers, selects, resolved indexes, and annotations,
  and returns the empty string for all other expression kinds.
- Gate: `scripts/_lib/test_static_audit.py`, run by `scripts/run_tests.py`,
  now fails any unmarked syntactic `when others =>` arm in these files.
  `safe_frontend-ada_emit-internal.adb` has zero retained markers and is
  included as a future-regression guard.
- Raw historical baseline after this slice: 25 `when others =>` hits under
  `compiler_impl/src/`. The syntactic bare-or-named count is 28, and the
  operational bare-or-named unaudited count is 0.
- Pre/post emitted-Ada artifact manifest comparison is required for this slice
  because both target files are emitter-adjacent and the standard snapshot
  checker may skip when the compiler hash does not match the committed
  snapshot.

### Phase 1B Conventions

#### Artifact-Grounded Manifest Diffs

Any pass whose direct or downstream output lands in a serialized artifact
captured by the standard manifest requires pre/post artifact diff with
`compiler_hash` normalized. `snapshot_emitted_ada.py --check` may skip when
the local compiler hash does not match the committed snapshot, so the per-slice
manifest diff is the authoritative regression guard for emitter-adjacent
slices.

#### Local Level-2 Skip Rule

Local `--no-cache --level 2` is required when a slice changes executable Ada
or proof inputs. Comment-only marker slices and audit-script-only slices may
rely on CI's no-cache level-2 Prove gate after local cached proofs pass.

#### Slice Taxonomy

Conversion slices replace closed-enum catch-alls with explicit arms. Marker
slices annotate defensive, cleanup, or broad-domain catch-alls with a
`--  when-others-ok:` rationale. Hybrid slices mix both actions only when the
file set is small and each per-file action is obvious from the enum or site
shape.

#### Hybrid Eligibility

Hybrid slices are allowed when the file set is no more than three files and
each file has an unambiguous action. Larger or ambiguous sets split into
marker-only and conversion-only PRs.

#### End State

Phase 1B is complete when the operational unaudited count reaches zero.
Retained marked sites remain as documented residual syntax; raw historical and
syntactic bare-or-named counts stabilize at the residual marker and
generated-string counts.

PR12.1 overlap evidence:

- Expression-kind walkers and classifiers in the resolver no longer silently
  absorb new call/argument AST shapes; `Expr_Apply`, `Expr_Call`, and every
  terminal expression kind are named explicitly where they are relevant.
- Statement, select-arm, and match-arm validators in the parser/resolver now
  name `Stmt_Unknown`, `Select_Arm_Unknown`, and `Match_Arm_Unknown`
  explicitly instead of hiding future grammar additions behind catch-all arms.
- Any future named-argument representation added for #362 must update the
  parser/resolver dispatch arms intentionally or fail compilation/static audit.

Findings:

None yet.

## Phase 1C - Wide Integer Arithmetic Safety

Status: complete; baseline-allowlist gate active.

Enforcement default: yes. `scripts/run_tests.py` fails when the live arithmetic
scan reports a fingerprint outside the accepted baseline.

Gate baseline:

- Script: `scripts/audit_arithmetic.py`.
- Machine baseline: `audit/phase1c_arithmetic_baseline.json`.
- Current baseline entries: 244 hits: 0 candidates and
  244 accepted-with-rationale hits.

Commands:

```bash
python3 scripts/audit_arithmetic.py
python3 scripts/audit_arithmetic.py --json
python3 scripts/audit_arithmetic.py --summary
```

Baseline counts:

| Category | Entries | Current classification |
| --- | ---: | --- |
| `emitted-wide` | 19 | `accepted-with-rationale` |
| `host-wide-arithmetic` | 0 | none |
| `model-domain` | 70 | `accepted-with-rationale` |
| `overflow-check-path` | 50 | `accepted-with-rationale` |
| `stdlib-length` | 9 | `accepted-with-rationale` |
| `target-bits` | 96 | `accepted-with-rationale` |

Scanner notes:

- The scanner is line-oriented and strips Ada `--` comments outside string
  literals, then ignores matches whose start offset is inside a same-line string
  literal. Multi-line generated-string edge cases may still need triage.
- Baseline fingerprints are derived from category, path, pattern name, and the
  normalized source line. Line numbers are display-only; entries are grouped by
  fingerprint, and `multiplicity` records the number of scanner matches, not
  source lines, that contributed to that grouped entry. One source line can
  contribute multiple matches when more than one alternation branch matches it,
  and multiple source lines can share one fingerprint when their normalized text
  is identical.
- The original target-bits scanner required `Integer_Type\s*\(`, which missed
  parameterless Ada calls such as `BT.Integer_Type`. The
  `bt-integer-type-parameterless` pattern catches those default calls without
  overlapping explicit-argument calls.
- Scanner coverage gaps surfaced during triage get a scan-extension PR before
  repro or fix work, so triage, coverage expansion, and behavior changes remain
  separately reviewable.
- `scripts/run_tests.py` runs the scanner and prints summary counts. It fails if
  the scanner crashes, emits invalid JSON, the baseline cannot be read, the
  closed baseline contains an open classification, or a live fingerprint appears
  outside the baseline.

Working with the baseline:

- New live fingerprints fail the gate because they may indicate untriaged
  arithmetic safety risk.
- Missing baseline fingerprints are reported by the scanner summary but do not
  fail the gate. Missing entries usually mean code was refactored or removed;
  this is benign baseline drift that can be cleaned up in a dedicated
  maintenance PR without coupling cleanup to feature work.
- A future hit qualifies as a local obvious addition only when it appears in
  code added or modified by the same PR, is covered by existing classification
  rules in this section, and has concrete accepted-with-rationale text in the
  baseline.
- Broader pattern surfaces, novel classification rules, or hits in unrelated
  code use a scan-extension/triage cycle before any behavior-changing fix.

### Classification Rules

#### Target-bits

- CLI, driver, resolver, lowering, and artifact-boundary target-bits hits are
  accepted when they only parse, normalize, validate, store, serialize, or
  forward the selected target width.
- Builtin integer construction hits are accepted when they route through
  `BT.Integer_Type (Target_Bits)`, `BT.Integer_Type (Document.Target_Bits)`, or
  `BT.Is_Valid_Target_Bits`; those are the central 32/64-bit target-width
  contract points. Explicit `BT.Integer_Type (64)` is accepted only for legacy
  `long_long_integer` emitter fallback paths whose source-level use is rejected
  upstream and whose Ada width must remain `Long_Long_Integer`. Parameterless
  `BT.Integer_Type` calls default to 64-bit; the scanner keeps tracking them as
  a regression guard and they should not appear in the current baseline.
- `Is_Integer_Type` and `Is_Wide_Integer_Type` hits are accepted when they only
  inspect resolved descriptors that already carry target-width bounds.
- Artifact writers/readers are accepted when the hit is the `target_bits`
  metadata field, not a place where arithmetic bounds are invented.
- Entries that do not fit the rules above default to `needs-repro` with a
  concrete unmatched-pattern rationale. Do not invent new acceptance rules
  during triage; surface substantial new clusters and plan them separately.
- Triage PRs are classification-only. Even tiny confirmed defects move into the
  follow-up queue instead of being fixed in the same PR.
- Phase 1C defect-fix PRs follow the scan/triage/fix cycle: a scan-extension PR
  adds coverage and surfaces hits, triage classifies them, then a fix PR
  resolves the entries while leaving scanner coverage in place as a regression
  guard.
- A fix PR may classify scanner hits introduced directly by its own defensive
  helper code when the hit and its rationale are local to that fix. Broader new
  scanner surfaces still require a separate triage PR.

#### MIR Interval

- `Wide_Integer`, `INT64_LOW`/`INT64_HIGH`, interval helpers, sentinel
  full-range intervals, and overflow-check plumbing are accepted as the
  intentional MIR analysis domain.
- Arithmetic routed through `Overflow_Checked` is accepted when `Wide_Integer`
  is the checked intermediate domain.
- Suspected MIR arithmetic defects are classified and queued, not fixed in the
  same triage PR.
- Analyzer scaling shortcuts outside `Overflow_Checked` must fail closed and
  fall back to the baseline sampled analysis when scaling cannot stay within the
  signed-64 model.

#### Non-Emitter Model Domain

- `safe_frontend-check_model.ads` uses `Wide_Integer` as the check-model
  integer-literal carrier. These hits are accepted as the intentional internal
  source-literal domain, not emitted or runtime width.
- `safe_frontend-check_lower.adb` hits are accepted when they preserve resolved
  target integer bounds for typed/static loop ranges. `INT64_LOW`/`INT64_HIGH`
  sentinels are fallback source-integer literals for otherwise unbounded
  internal lowered ranges, not hidden target-width selection.
- `safe_frontend-check_resolve.adb` hits are accepted when they are static
  source-integer checks for literal bounds, scalar constraints, binary wrap
  helpers, static lengths, or shift-bound validation, with compatibility checks
  gating results before they become resolved target values.

#### Emitter

- `ada_emit` `emitted-wide` hits are accepted when they render already-resolved
  static, proof, runtime, or source-integer values into Ada text through
  `Trim_Wide_Image` or `Safe_Runtime.Wide_Integer`; these sites do not select
  target width. The scanner also matches `Trim_Wide_Image` declarations,
  renames, and `end` lines; those infrastructure hits are accepted as scanner
  false positives, not render sites.
- `ada_emit` `model-domain` hits are accepted when statement helpers use
  `CM.Wide_Integer` as a static source-integer or proof/invariant arithmetic
  domain. Those values must come from resolved bounds/literals or fail-closed
  helper paths before narrowing or emitting runtime facts.

#### Runtime and Stdlib

- `safe_runtime.ads` uses `Wide_Integer` as the intentional runtime
  intermediate integer type for emitted Safe arithmetic. It mirrors the
  compiler/emitter wide arithmetic domain and is not hidden target-width
  selection.
- `Long_Long_Integer (Length (...))` hits in stdlib concat postconditions are
  accepted when they are contract-only widening of `Length` operands before
  equality arithmetic. The widening prevents Ada/SPARK postcondition expression
  overflow before the equality is evaluated; it does not change runtime storage
  or concat allocation semantics.

Gate promotion outcome:

- A false positive is a scanner hit reviewed and classified as
  `accepted-with-rationale` in the machine baseline.
- Phase 1C used the classified-baseline promotion path: every current hit is
  classified and the gate fails only newly unclassified hits.
- Phase 1C is complete: no `candidate`, `needs-repro`, or `confirmed-defect`
  entries remain in the baseline.

Follow-up work queue:

No open Phase 1C follow-up work remains after runtime/stdlib length-contract
triage.

Findings:

- The 96 target-bits baseline entries are classified as
  `accepted-with-rationale`. They are target-width propagation, artifact
  metadata, builtin integer construction, or integer-family predicate checks.
- No target-bits `needs-repro` or `confirmed-defect` entries remain.
- The target-bits default-constructor fix threaded `Document.Target_Bits` through
  4 emitter fallback source lines. The `integer` paths now use
  `Document.Target_Bits`; the legacy `long_long_integer` fallbacks use explicit
  `64` to preserve their Ada `Long_Long_Integer` width without relying on the
  default constructor.
- MIR interval arithmetic triage classified all 50 `overflow-check-path`
  entries as accepted MIR analysis plumbing.
- The MIR-resident, non-emitter compiler, emitter, and runtime portions of
  `model-domain` are triaged: all 70 entries are accepted.
- The `emitted-wide` category is fully triaged: all 19 entries are accepted as
  intentional emitter rendering of resolved static, proof, runtime, or
  source-integer values.
- The `stdlib-length` category is fully triaged: all 9 entries are accepted as
  contract-only widening in stdlib concat postconditions.
- No `candidate`, `needs-repro`, or `confirmed-defect` entries remain in the
  Phase 1C baseline.
- The `host-wide-arithmetic` category is fully resolved: the previous
  division-bound scaling hit was replaced by fail-closed scaling in the MIR
  analyzer.
- The `Phase 1C MIR division-bound scaling repro/fix` work is complete. The
  regression fixtures demonstrate the previous false rejection and the
  one-sided-bound mixed-sign over-narrowing risk; the analyzer now falls back to
  sampled division when relational-bound scaling cannot stay within the
  signed-64 model and only applies one-sided division facts as upper-bound
  refinements.
- Phase 1C surfaced two real defects, the division-bound scaling pair fixed in
  #394, out of 244 audited entries. The phase's primary durable artifact is the
  scanner, classification baseline, and classification rules library, which
  serve as the regression guard for arithmetic safety in subsequent work.
- The former flat classification-rules sections are consolidated under one
  parent heading with per-context children: target-bits, MIR interval,
  non-emitter model-domain, emitter, and runtime/stdlib.
- Phase 1C closeout promoted the scanner from reporting-only to an active
  baseline-allowlist gate. The live scanner now blocks new unclassified
  arithmetic fingerprints while reporting missing baseline fingerprints as
  non-failing drift.

## Phase 1D - GNATprove Trust Boundaries

Status: inventory established; reporting-only baseline active.

Enforcement default: reporting first. Promote only after triage/classification.

Reporting baseline:

- Script: `scripts/audit_gnatprove_trust.py`.
- Machine baseline: `audit/phase1d_gnatprove_trust_baseline.json`.
- Current baseline entries: 5 hits: 5 candidates.

Commands:

```bash
python3 scripts/audit_gnatprove_trust.py
python3 scripts/audit_gnatprove_trust.py --json
python3 scripts/audit_gnatprove_trust.py --summary
```

Baseline counts:

| Category | Entries | Current classification |
| --- | ---: | --- |
| `assume-pragma` | 1 | `candidate` |
| `gnatprove-annotate` | 1 | `candidate` |
| `gnatprove-warning-suppression` | 3 | `candidate` |
| `skip-proof-marker` | 0 | none |

Scanner notes:

- Scope: Ada sources under `compiler_impl/src/`,
  `compiler_impl/stdlib/ada/`, and `companion/`. `SPARK_Mode (Off)` islands
  remain Phase 1E and are intentionally out of scope here.
- The scanner strips Ada `--` comments outside string literals but scans inside
  string literals. This differs from scanners where generated strings are noise:
  Phase 1D targets trust-boundary pragmas, and several current entries are
  generated as string literals in the Ada emitter.
- `pragma Assume`, `pragma Annotate`, and `pragma Warnings (GNATprove, Off,
  ...)` entries are matched from their pragma start through the statement
  semicolon with string-aware scanning. Semicolons or parentheses inside string
  literal arguments are part of the fingerprint instead of truncating the
  matched text.
- Baseline fingerprints are derived from category, path, pattern name, and the
  normalized matched text. For multi-line entries, the matched text is joined
  with whitespace collapsed; `line` records the first source line and
  `first_line_text` provides a display anchor.
- `pragma Warnings (GNATprove, On, ...)` restore lines are excluded by the
  warning-suppression pattern, which only matches `Off`.
- Phase 1D's scanner deliberately follows Phase 1C's standalone scanner shape.
  Cross-scanner abstraction is deferred until at least Phase 1E provides a
  third use case and clearer shared boundaries.
- Even small-surface phases keep inventory and triage separate. This inventory
  PR records the five candidates; the next Phase 1D PR classifies them.

Follow-up work queue:

| Work item | Entries | Evidence | Acceptance |
| --- | ---: | --- | --- |
| Phase 1D GNATprove trust-boundary triage | 5 | Generated `Assume` in `safe_frontend-ada_emit-statements.adb`, generated `Warnings (GNATprove, Off, ...)` in `safe_frontend-ada_emit-statements.adb` and `safe_frontend-ada_emit-internal.adb`, and companion `Annotate (GNATprove, Intentional, ...)` in `companion/spark/safe_po.adb` | Classify each baseline entry as accepted-with-rationale, needs-repro, or confirmed-defect; decide whether a future closeout should promote a baseline gate. |

Findings:

- Inventory found 5 candidate GNATprove trust-boundary entries: one generated
  `Assume`, one companion `Annotate (GNATprove, Intentional, ...)`, and three
  generated warning suppressions.
- No `Skip_Proof` or `False_Positive` markers were found. The category remains
  in the scanner as a regression guard.
- Phase 1D's surface is small relative to Phase 1C's 244 arithmetic entries, so
  the expected cadence is shorter: inventory, triage, optional fix if triage
  confirms a defect, and closeout/gate decision.

## Phase 1E - SPARK Mode Off Islands

Enforcement default: likely yes.

Seed notes for sweep:

- `compiler_impl/src/safe_frontend-ada_emit-channels.adb` contributes 26 of
  the 36 `SPARK_Mode (Off)` hits and also has a `when others =>` arm. Join
  this with Phase 1B findings before the Phase 2 channels deep dive.

Findings:

None yet.

## Phase 1F - Dead Code After Unconditional Raise

Enforcement default: likely yes.

Findings:

None yet.

## Phase 1G - Spec Body Contract Drift

Enforcement default: decide during sweep.

Seed notes for sweep:

- `compiler_impl/src/safe_frontend-ada_emit-internal.ads` contributes two
  `Raise_Unsupported` hits. Treat spec-file raises as contract-drift candidates
  rather than only as Phase 1F dead-code-after-raise body findings.

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
| Case/match/select | exhaustive, defaulted, unsupported arm shape | missing branch; non-stable scrutinee; channel readiness | emit explicit branch lowering or reject before emission |
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

### safe_frontend-ada_emit-proofs.adb

Owner: TBD.

Findings:

None yet.

## Phase 3 - Canary And Cross-Cutting Replay

Replay only the Phase 0 frozen canary corpus. This pinned audit cycle has an
empty canary corpus, so the canary replay sub-scope is explicitly empty. Do not
retroactively promote ordinary samples into canaries. Phase 3 still runs the
arithmetic and classification replay below. Promote replay defect issues only
after minimized repros confirm distinct root causes.

### Frozen Canary Corpus

Captured at `Audit SHA`:

```text
No tracked canary files matched at `Audit SHA`.
```

A future showcase sample such as `surface_tour.safe` was not present at
`Audit SHA`, so it is not part of this pinned replay corpus. If such a sample
lands later, audit it after Phase 4 or in the next cycle.

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
git log 5450c30406e5535cab772e511e1ec326217f16f1..main -- compiler_impl/src/ compiler_impl/stdlib/ada/ companion/ docs/ tests/ samples/
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
