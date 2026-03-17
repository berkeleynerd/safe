# PR10.1 Comprehensive Assessment and Refinement Audit

This document is the canonical PR10.1 audit record for the repository state
after `PR10`.

PR10.1 does not broaden the frozen PR10 milestone claim. It verifies the current
claim surfaces against the live repo, corrects audited drift immediately, and
carves only the bounded, evidence-ready follow-on work into `PR10.2+`.

## Audit Truth Baseline

The PR10.1 gate reruns the following authoritative serial baseline:

- `scripts/run_pr08_frontend_baseline.py`
- `scripts/run_pr09_ada_emission_baseline.py`
- `scripts/run_pr10_emitted_baseline.py`
- `scripts/run_emitted_hardening_regressions.py`
- companion GNATprove build, flow, prove, assumption extraction, and diff
- emission-template GNATprove build, flow, prove, assumption extraction, and diff
- `scripts/validate_execution_state.py`

The committed report is
[`execution/reports/pr101-comprehensive-audit-report.json`](../execution/reports/pr101-comprehensive-audit-report.json).

## Findings

### Claim Surfaces and Guard Topology

| ID | Area | Claim source | Observed reality | Evidence | Disposition | Target | Notes |
|----|------|--------------|------------------|----------|-------------|--------|-------|
| `PR101-001` | `tooling` | `scripts/run_pr10_emitted_baseline.py`; `compiler_impl/README.md` | The PR10 umbrella gate correctly proves PR10 completion, but its older “no next tracked milestone” assumption becomes stale once later milestones exist. | PR10 umbrella script; compiler workspace README gate description | `fix-in-pr101` | `scripts/run_pr10_emitted_baseline.py`; `compiler_impl/README.md` | Make PR10 forward-stable like the PR09 baseline: later tracked milestones are allowed as long as PR10 stays done with the canonical evidence list. |
| `PR101-002` | `docs` | `README.md`; `compiler_impl/README.md`; `.github/workflows/ci.yml` | Once PR10.1 exists, the canonical docs and CI summary need an explicit audit link and job description so the post-PR10 story is discoverable. | README doc guide and CI summary; compiler workspace README gate list; workflow job topology | `fix-in-pr101` | `README.md`; `compiler_impl/README.md`; `.github/workflows/ci.yml` | Add the canonical audit doc, gate description, and CI job without changing the frozen PR10 selected-corpus claim. |
| `PR101-045` | `docs` | `docs/tutorial.md` | The tutorial still claims there is no compiler implementation and no compiler yet, which directly contradicts the Ada-native `safec` frontend and emitted-output proof gates that have existed since the PR06 series. | `docs/tutorial.md` line 9; `docs/tutorial.md` line 282; current CLI and proof-tutorial docs | `fix-in-pr101` | `docs/tutorial.md` | Correct the two stale pre-compiler-era statements and point readers to the end-to-end CLI tutorial without changing the bounded-tooling message. |

### Static Evaluation and Numeric Analysis

| ID | Area | Claim source | Observed reality | Evidence | Disposition | Target | Notes |
|----|------|--------------|------------------|----------|-------------|--------|-------|
| `PR101-003` | `resolver` | `PR08.3a`; `spec/03-single-file-packages.md` section `3.2.7` | Static evaluation still stops at the narrow constant subset used by PR08.3a; broader declaration-time arithmetic and attribute folding remain open. | Current resolver surface; retained unsupported cases | `retain-in-post-pr10` | `PS-001` | Keep as a retained post-PR10 resolver item. |
| `PR101-004` | `analyzer` | `docs/frontend_architecture_baseline.md` | Fixed-point Rule 5 support remains outside the accepted and proved surface. | Current frontend boundary doc; no fixed-point Rule 5 fixtures in the accepted corpus | `retain-in-post-pr10` | `PS-002` | Retain until the accepted Rule 5 subset is widened deliberately. |
| `PR101-005` | `analyzer` | PR10 review; `docs/emitted_output_verification_matrix.md`; `spec/02-restrictions.md` section `2.8.5` | The broader live accepted Rule 5 positive surface is now closed under a dedicated PR10.2 gate instead of being documented only through the frozen PR10 representative. | `execution/reports/pr102-rule5-boundary-closure-report.json`; PR10.2 tracker acceptance; updated matrix PR10.2 note | `close-as-fixed` | `PR10.2` | PR10.2 merges the historical PR07 Rule 5 positives with the frozen PR10 representative into one explicit non-shrinkable proof target. |
| `PR101-006` | `analyzer` | PR10 review; `spec/02-restrictions.md` section `2.8.5` | The live Rule 5 boundary now distinguishes unsupported float-expression shapes from true overflow-at-narrowing and proves the accepted positive corpus under the emitted GNATprove profile. | `compiler_impl/src/safe_frontend-mir_analyze.adb`; `compiler_impl/tests/mir_analysis/pr102_fp_unsupported_expression_parity.json`; `execution/reports/pr102-rule5-boundary-closure-report.json` | `close-as-fixed` | `PR10.2` | `fp_overflow_at_narrowing` now remains reserved for true narrowing-range failures, while unsupported evaluator shapes use `fp_unsupported_expression_at_narrowing`. |
| `PR101-007` | `analyzer` | PR10 review; GNATprove loop-variant requirements | Convergence-style while loops outside the current derivable Loop_Variant surface are now rejected during `safec check` with a dedicated diagnostic instead of being left to downstream emitted-proof failure. | `compiler_impl/src/safe_frontend-mir_analyze.adb`; `tests/negative/neg_while_variant_not_derivable.safe`; `tests/diagnostics_golden/diag_loop_variant_not_derivable.txt`; `execution/reports/pr102-rule5-boundary-closure-report.json` | `close-as-fixed` | `PR10.2` | PR10.2 mirrors the emitter's current derivable loop-variant surface in MIR analysis and names the boundary explicitly as `loop_variant_not_derivable`. |

### Concurrency, Ownership, and Runtime Model

| ID | Area | Claim source | Observed reality | Evidence | Disposition | Target | Notes |
|----|------|--------------|------------------|----------|-------------|--------|-------|
| `PR101-008` | `analyzer` | `PR08.2` review fallout; `spec/04-tasks-and-channels.md` paragraph `30` | The repo now uses leave-unchanged `try_receive` failure semantics, but success-sensitive analyzer precision is still conservative. | Current emitted `Try_Receive (Value : in out T; Success : out Boolean)` contract; retained analyzer limitation | `retain-in-post-pr10` | `PS-003` | Precision improvement is optional hardening, not a correctness blocker. |
| `PR101-009` | `resolver` | `PR08.3` boundary; `compiler_impl/README.md` | Cross-package package-qualified writes remain out of scope for the imported-summary path. | Current imported-resolution documentation and tests | `retain-in-post-pr10` | `PS-004` | Retain as a long-term resolver item. |
| `PR101-010` | `analyzer` | `spec/00-front-matter.md` section `0.8` | Deadlock analysis remains outside the current Bronze/Silver concurrency story. | Spec TBD register; no frontend or emitted deadlock gate | `retain-in-post-pr10` | `PS-005` | Keep as a long-term analysis item. |
| `PR101-011` | `analyzer` | `spec/00-front-matter.md` section `0.8` | `Constant_After_Elaboration` is still not modelled in the current concurrency analysis. | Spec TBD register; no current PR08/PR10 coverage | `retain-in-post-pr10` | `PS-006` | Blocking-if-needed for future concurrency widening. |
| `PR101-012` | `spec` | `docs/emitted_output_verification_matrix.md`; `spec/04-tasks-and-channels.md` section `4.4` | The emitted select proof is explicitly for the polling-based lowering, not for faithful source-level blocking semantics. | Matrix select row; current emitted lowering | `retain-in-post-pr10` | `PS-007` | Keep the semantic gap open instead of overstating the proof claim. |
| `PR101-013` | `tooling` | PR10 review; `docs/emitted_output_verification_matrix.md` | The richer success-path select proof fixture now exists and is enforced by the supplemental hardening gate. | `tests/concurrency/select_with_delay_multiarm.safe`; `scripts/run_emitted_hardening_regressions.py` | `close-as-fixed` | `n/a` | Remove the older missing-success-path regression request from the retained ledger. |
| `PR101-014` | `analyzer` | PR10 review; `tests/positive/ownership_early_return.safe`; `TBD-11` | The emitted early-return capture-before-cleanup ordering regression now exists and is enforced structurally. | `scripts/run_emitted_hardening_regressions.py`; emitted ownership regression | `close-as-fixed` | `n/a` | Narrow `TBD-11` to the broader deallocation-ordering surface beyond this covered case. |
| `PR101-015` | `docs` | PR10 review; `docs/emitted_output_verification_matrix.md` | Ownership proof messaging needed to say explicitly that GNATprove covers emitted runtime checks while frontend Silver ownership analysis prevents use-after-free. | Ownership matrix row before audit; ownership move proof surface; `Ada.Unchecked_Deallocation` boundary | `fix-in-pr101` | `docs/emitted_output_verification_matrix.md` | Correct the wording now instead of leaving a misleading implication in the matrix. |
| `PR101-016` | `spec` | `spec/02-restrictions.md` paragraphs `151a`-`151g` | Task-level fault containment and restart intensity remain outside the implemented runtime/analysis story. | Spec clauses; no frontend or emitted proof coverage | `retain-in-post-pr10` | `PS-008` | Long-term runtime-model work. |
| `PR101-017` | `spec` | `PR08.3a` review fallout; `check_resolve` and `mir_analyze` semantics | Constant access-object mutability wording is still not standardised across the spec and implementation docs. | Current review fallout notes; retained spec ambiguity | `retain-in-post-pr10` | `PS-009` | Keep as a spec-clarification item. |

### Language Surface and Semantic Coverage

| ID | Area | Claim source | Observed reality | Evidence | Disposition | Target | Notes |
|----|------|--------------|------------------|----------|-------------|--------|-------|
| `PR101-018` | `resolver` | `spec/03-single-file-packages.md` section `3.3.1`; roadmap after `PR08.3a` | Named numbers remain outside the current ordinary-constant interface/value path. | PR08.3a docs and retained resolver boundary | `retain-in-post-pr10` | `PS-010` | Long-term language-surface expansion. |
| `PR101-019` | `parser` | `PR03`; `compiler_impl/src/safe_frontend-check_parse.adb` | String and character literals are still unsupported on the live parser path. | Current unsupported diagnostics and docs | `retain-in-post-pr10` | `PS-011` | Blocking-if-needed if the supported language subset widens here. |
| `PR101-020` | `parser` | `spec/02-restrictions.md` paragraph `28` | Case statements remain unsupported. | Current parser boundary and unsupported diagnostics | `retain-in-post-pr10` | `PS-012` | Blocking-if-needed. |
| `PR101-021` | `resolver` | `PR08.1` boundary | Task declarative parts remain limited to object declarations in the accepted local concurrency subset. | Current PR08 acceptance and parser/resolver behaviour | `retain-in-post-pr10` | `PS-013` | Long-term surface widening. |
| `PR101-022` | `language-design` | `docs/syntax_proposals.md`; `spec/02-restrictions.md` paragraph `28` | The `goto` and statement-label question is already carried in the syntax-proposals process rather than the live post-PR10 implementation ledger. | Existing syntax proposals doc; no live implementation claim depends on it | `close-as-pretracked` | `docs/syntax_proposals.md` | Remove from the retained post-PR10 implementation ledger. |
| `PR101-023` | `resolver` | `docs/frontend_architecture_baseline.md` | General discriminants remain outside the supported frontend baseline. | Frontend baseline docs; current parser/resolver surface | `retain-in-post-pr10` | `PS-014` | Blocking-if-needed. |
| `PR101-024` | `resolver` | `docs/frontend_architecture_baseline.md` | Discriminant constraints remain outside the supported frontend baseline. | Frontend baseline docs; current parser/resolver surface | `retain-in-post-pr10` | `PS-015` | Blocking-if-needed. |

### Emitter Implementation Quality and Open Review Debt

| ID | Area | Claim source | Observed reality | Evidence | Disposition | Target | Notes |
|----|------|--------------|------------------|----------|-------------|--------|-------|
| `PR101-046` | `emitter` | PR54 review; `compiler_impl/src/safe_frontend-ada_emit.adb` | `Join_Names` still catches `Constraint_Error` broadly and maps it to a generic internal failure instead of letting the concrete malformed-state cause surface more narrowly. | `safe_frontend-ada_emit.adb` `Join_Names` exception handler | `promote-to-pr10x` | `PR10.5` | Track as emitter-maintenance hardening rather than silently carrying the review debt forward. |
| `PR101-047` | `emitter` | PR54 review; `compiler_impl/src/safe_frontend-ada_emit.adb` | Both `Render_Cleanup` overloads still catch `Constraint_Error` broadly and collapse distinct malformed-declaration failures into the same generic internal error path. | `safe_frontend-ada_emit.adb` `Render_Cleanup` overload exception handlers | `promote-to-pr10x` | `PR10.5` | Keep the two cleanup overloads in scope together so the maintenance task closes the whole pattern. |
| `PR101-048` | `emitter` | PR54 review; `compiler_impl/src/safe_frontend-ada_emit.adb` | The emitter still contains unreachable fallback returns after `Raise_Unsupported`, which adds dead code noise to unsupported paths and obscures intent during review. | `safe_frontend-ada_emit.adb` `Render_Type_Decl`; `Render_Expr`; similar unsupported-path returns | `promote-to-pr10x` | `PR10.5` | Treat as deterministic cleanup work within the emitter-maintenance milestone. |
| `PR101-049` | `emitter` | PR54 review; `compiler_impl/src/safe_frontend-ada_emit.adb`; `docs/emitted_output_verification_matrix.md` | `Is_Integer_Type` still treats every subtype descriptor as integer, which is too coarse for a name that is used to drive emitted numeric lowering decisions. | `safe_frontend-ada_emit.adb` `Is_Integer_Type (Info)` implementation | `promote-to-pr10x` | `PR10.5` | This is maintenance debt unless and until it produces a user-visible mis-lowering; track it explicitly now. |
| `PR101-050` | `emitter` | PR54 review; `compiler_impl/src/safe_frontend-ada_emit.adb` | Name-based type rendering still duplicates lookup paths, and the resolved/non-resolved `Render_Object_Decl_Text` overloads still carry near-identical bodies. | `safe_frontend-ada_emit.adb` `Is_Integer_Type (Name)`; `Render_Type_Name (Name)`; duplicated `Render_Object_Decl_Text` bodies | `promote-to-pr10x` | `PR10.5` | Track the lookup unification and object-declaration rendering consolidation together as one refactor surface. |
| `PR101-052` | `emitter` | PR58 review; `compiler_impl/src/safe_frontend-ada_emit.adb` | Alias-postcondition `'Old` insertion still relies on string-based rewriting, which is too fragile for a safety-critical emitter and risks false matches as the emitted expression surface grows. | `safe_frontend-ada_emit.adb` `Render_Access_Param_Postcondition`; string-based target substitution | `promote-to-pr10x` | `PR10.5` | Close this in the same emitter-maintenance milestone as the surrounding Ada emission refactors rather than splitting a second micro-milestone. |

### Tooling, Interface UX, and Assurance

| ID | Area | Claim source | Observed reality | Evidence | Disposition | Target | Notes |
|----|------|--------------|------------------|----------|-------------|--------|-------|
| `PR101-025` | `tooling` | `PR08.3` review fallout | Interface search-dir scanning still fails closed on unrelated malformed `.safei.json` files. | Existing review fallout; current interface loading behaviour | `retain-in-post-pr10` | `PS-016` | Nice-to-have ergonomics hardening. |
| `PR101-026` | `tooling` | `PR08.2` review fallout | Ada-side Bronze regression derivation still depends on Python-driven evidence refresh. | Current gate stack and report generation | `retain-in-post-pr10` | `PS-017` | Nice-to-have tooling hardening. |
| `PR101-027` | `tooling` | `docs/emitted_output_verification_matrix.md`; `execution/tracker.json` | Sequential emitted proof coverage beyond the frozen PR10 representatives is still an open bounded follow-on task after the ownership-specific PR10.3 closure. | Matrix “Other currently emitted sequential fixtures” row; frozen PR10 claim; completed ownership-specific proof set | `promote-to-pr10x` | `PR10.6` | Retarget the remaining non-ownership sequential proof expansion into its own milestone now that PR10.3 closes the six-fixture ownership set. |
| `PR101-028` | `tooling` | `docs/emitted_output_verification_matrix.md`; `execution/tracker.json` | Concurrency emitted proof coverage beyond the frozen PR10 subset remains open, but the runtime-model boundary makes it less decision-complete than the sequential expansion. | Matrix concurrency residual row; retained runtime obligations | `retain-in-post-pr10` | `PS-018` | Keep retained until a narrower concurrency proof task is decision-complete. |
| `PR101-029` | `tooling` | `docs/emitted_output_verification_matrix.md` | I/O seam wrapper obligations remain outside direct emitted-package proof and need separate wrapper/runtime mechanisms. | Matrix I/O seam row | `retain-in-post-pr10` | `PS-019` | Long-term assurance boundary. |
| `PR101-030` | `tooling` | PR10 review; `scripts/_lib/pr10_emit.py`; downstream PR06.9.x report churn | The GNATprove parser is now stricter and tested, but the repo still relies on textual summary parsing instead of a dedicated hardened evidence path, and several deterministic parent reports still churn when child report hashes change for unrelated reasons. | Current parser tests; text-summary dependency remains; PR06.9.10/11/13 rollup behavior | `promote-to-pr10x` | `PR10.4` | Promote the remaining tooling hardening into its own bounded milestone: audit-parser regression tests, explicit `gnat.adc` sentinels, proof-repeatability policy, and report-topology de-cascading so parent evidence stays stable when only child report hashes move. |
| `PR101-031` | `tooling` | `spec/00-front-matter.md` section `0.8` | Diagnostic catalogue and localisation remain unimplemented. | Spec TBD register | `retain-in-post-pr10` | `PS-020` | Long-term tooling item. |
| `PR101-032` | `tooling` | `spec/00-front-matter.md` section `0.8`; interface and MIR code | The repo has stable `safei-v1` and `mir-v2` artifacts, but not a fully stabilised normative interchange-format policy. | Existing artifacts plus retained normative-policy gap | `retain-in-post-pr10` | `PS-021` | Long-term documentation/policy work. |
| `PR101-033` | `tooling` | `spec/00-front-matter.md` section `0.8` | Performance targets are still intentionally undefined. | Spec TBD register | `retain-in-post-pr10` | `PS-022` | Long-term. |
| `PR101-034` | `tooling` | `docs/spark_container_compatibility.md` | SPARK container compatibility gaps remain open. | Existing compatibility memo | `retain-in-post-pr10` | `PS-023` | Long-term. |
| `PR101-051` | `tooling` | `docs/emitted_output_verification_matrix.md`; `execution/tracker.json`; ownership fixtures under `tests/positive/` | The ownership follow-on proof surface is now explicit, non-shrinkable, and proved as its own six-fixture post-PR10 expansion set. | `execution/reports/pr103-sequential-proof-expansion-report.json`; ownership expansion row in the matrix; updated tracker text | `close-as-fixed` | `PR10.3` | PR10.3 closes the ownership-specific proof-expansion gap without collapsing the remaining non-ownership sequential backlog. |

### Spec and Language TBDs

| ID | Area | Claim source | Observed reality | Evidence | Disposition | Target | Notes |
|----|------|--------------|------------------|----------|-------------|--------|-------|
| `PR101-035` | `spec` | `spec/00-front-matter.md` section `0.8` | Target-platform constraints remain under-specified beyond requiring an Ada compiler. | Spec TBD register | `retain-in-post-pr10` | `PS-024` | Blocking-if-needed. |
| `PR101-036` | `spec` | `spec/00-front-matter.md` section `0.8` | Memory-model constraints remain open. | Spec TBD register | `retain-in-post-pr10` | `PS-025` | Blocking-if-needed. |
| `PR101-037` | `spec` | `spec/00-front-matter.md` section `0.8` | The spec-level floating-point semantics question remains broader than the concrete PR10.2 proof-boundary work. | Spec TBD register; retained wider semantic question | `retain-in-post-pr10` | `PS-026` | Keep the wider semantic TBD even while PR10.2 closes the narrower implementation boundary. |
| `PR101-038` | `spec` | `spec/00-front-matter.md` section `0.8` | Abort-handler behaviour remains unspecified. | Spec TBD register | `retain-in-post-pr10` | `PS-027` | Blocking-if-needed. |
| `PR101-039` | `spec` | `spec/00-front-matter.md` section `0.8` | Required integer-range guarantees remain open. | Spec TBD register | `retain-in-post-pr10` | `PS-028` | Blocking-if-needed. |
| `PR101-040` | `spec` | `spec/00-front-matter.md` section `0.8` | Automatic deallocation semantics remain only partially covered even after the nested early-return regression was added. | `TBD-11`; hardening regression narrows but does not close the whole scope | `retain-in-post-pr10` | `PS-029` | Keep the broader scope-exit/deallocation semantics item open. |
| `PR101-041` | `spec` | `spec/00-front-matter.md` section `0.8` | Modular arithmetic semantics remain unspecified. | Spec TBD register | `retain-in-post-pr10` | `PS-030` | Blocking-if-needed. |
| `PR101-042` | `spec` | `docs/emitted_output_verification_matrix.md`; `spec/04-tasks-and-channels.md` | Jorvik/Ravenscar scheduling, ceiling-locking, and polling timing remain outside direct emitted-package proof. | Matrix concurrency exception notes; retained runtime-model boundary | `retain-in-post-pr10` | `PS-031` | Long-term runtime and assurance boundary. |
| `PR101-043` | `language-design` | `spec/00-front-matter.md` section `0.8` | Limited/private type views across packages remain outside the current design and implementation surface. | Spec TBD register | `retain-in-post-pr10` | `PS-032` | Long-term. |
| `PR101-044` | `language-design` | `spec/00-front-matter.md` section `0.8` | Partial initialisation remains outside the current language and proof model. | Spec TBD register | `retain-in-post-pr10` | `PS-033` | Long-term. |

## Promoted Follow-on Milestones

The PR10.1 audit carved the following evidence-ready follow-on tasks:

- `PR10.2` — Rule 5 proof-boundary closure and loop-termination diagnostics (completed)
- `PR10.3` — Ownership emitted proof-corpus expansion beyond the frozen PR10 `ownership_move` representative (completed)
- `PR10.4` — GNATprove evidence and parser hardening, including audit-parser regression tests, explicit `gnat.adc` sentinels, proof-repeatability policy, and deterministic report de-cascading (completed)
- `PR10.5` — Ada emitter maintenance hardening (completed)
- `PR10.6` — Remaining sequential emitted proof-corpus expansion beyond the completed ownership set (completed)

The live tracker now records `PR10.6` as done, and `next_task_id` advances to `PR11.1`.

## Supersession Note

[`docs/post_pr10_scope_audit.md`](post_pr10_scope_audit.md) remains as the
earlier scope-cleanup memo, but PR10.1 supersedes it as the canonical
repo-wide post-PR10 audit record.
