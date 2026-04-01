# Post-PR10 Scope Ledger

This ledger records the residual work that remains open **after PR10** and
**after the PR10.1 comprehensive audit**.

It intentionally excludes items that the PR10.1 audit:

- fixed directly in the repo,
- promoted into a new tracked `PR10.2+` milestone,
- closed as duplicates or already-tracked work,
- or removed because the current spec now excludes them.

The canonical disposition record is
[`docs/pr10_refinement_audit.md`](pr10_refinement_audit.md).

PR10.2 closes the live accepted Rule 5 narrowing boundary and the
check-time convergence-loop rejection policy. The remaining floating-point
residuals here are the still-deferred fixed-point extension in `PS-002` and
the broader spec-level semantics question in `PS-026`.

PR11.8a revalidates the retained numeric-sensitive emitted proof corpus under
the single-`integer` model without widening the fixed-point or floating-point
claim. After that checkpoint, `PS-002` and `PS-026` remain deferred, and
PR11.8b closes the retained emitted concurrency checkpoint without widening the
language surface. After that concurrency checkpoint, `PS-018` no longer
denotes backlog inside the current retained emitted corpus; the remaining open
concurrency obligations were source/runtime concerns such as `PS-007`,
`PS-019`, and `PS-031`. `PR11.8g.3` closes `PS-007` and `PS-031` for the
shipped STM32F4/Jorvik-backed subset; the remaining open concurrency/runtime
residuals are the broader-than-admitted follow-ons `PS-019`, `PS-035`, and
`PS-036`.

## Legend

| Priority | Meaning |
|----------|---------|
| `blocking-if-needed` | Implement before claiming broader language or proof coverage in that area |
| `nice-to-have` | Useful hardening or ergonomics work, but not a prerequisite for the current roadmap |
| `long-term` | Intentional post-PR10 deferral; revisit after the current roadmap lands |

## Static Evaluation and Numeric Analysis

| ID | Item | Source | Area | Priority |
|----|------|--------|------|----------|
| `PS-001` | Static evaluation beyond the minimal PR08.3a constant-reference subset and the still-deferred named-number work, including binary arithmetic and declaration-time dot-attribute references such as `.First` and `.Last` | `PR08.3a`; `spec/03-single-file-packages.md` section `3.2.7`; `compiler_impl/src/safe_frontend-check_resolve.adb` | `resolver` | `blocking-if-needed` |
| `PS-002` | Fixed-point Rule 5 support beyond the frozen current subset; still explicitly deferred after `PR11.8a` | `docs/frontend_architecture_baseline.md` | `analyzer` | `blocking-if-needed` |

## Concurrency, Ownership, and Runtime Model

| ID | Item | Source | Area | Priority |
|----|------|--------|------|----------|
| `PS-003` | Success-sensitive `try_receive` analyzer precision beyond the current leave-unchanged failure contract | `PR08.2` review fallout; `spec/04-tasks-and-channels.md` paragraph `30` | `analyzer` | `nice-to-have` |
| `PS-004` | Imported package-qualified writes with sound cross-package mutability rules | `PR08.3` boundary; `compiler_impl/README.md` | `resolver` | `long-term` |
| `PS-005` | Channel deadlock analysis `TBD-09` | `spec/00-front-matter.md` section `0.8` | `analyzer` | `long-term` |
| `PS-006` | `Constant_After_Elaboration` for concurrency analysis `TBD-06` | `spec/00-front-matter.md` section `0.8` | `analyzer` | `blocking-if-needed` |
| `PS-008` | Task-level fault containment and restart intensity | `spec/02-restrictions.md` paragraphs `151a`-`151g` | `spec` | `long-term` |
| `PS-009` | Clarify and standardise spec text for constant access objects versus access-to-constant and observe writes through `.all` | `PR08.3a` review fallout; `compiler_impl/src/safe_frontend-check_resolve.adb`; `compiler_impl/src/safe_frontend-mir_analyze.adb` | `spec` | `long-term` |
| `PS-035` | Broader `select ... or delay ...` fairness and latency semantics beyond the admitted source-order dispatcher contract shipped after `PR11.9a` | `docs/jorvik_concurrency_contract.md`; `spec/04-tasks-and-channels.md` section `4.4` | `spec` | `long-term` |

## Language Surface and Semantic Coverage

| ID | Item | Source | Area | Priority |
|----|------|--------|------|----------|
| `PS-010` | Named-number declarations and imported named-number values through `safei-v1`, beyond the ordinary-constant subset shipped in PR08.3a | `spec/03-single-file-packages.md` section `3.3.1`; roadmap decision after `PR08.3a` | `resolver` | `long-term` |
| `PS-011` | String and character literals | `PR03`; `compiler_impl/src/safe_frontend-check_parse.adb` | `parser` | `blocking-if-needed` |
| `PS-012` | Case statements | `spec/02-restrictions.md` paragraph `28`; current unsupported surface | `parser` | `blocking-if-needed` |
| `PS-013` | Task declarative parts beyond object declarations | `PR08.1` boundary | `resolver` | `long-term` |
| `PS-014` | General discriminants | `docs/frontend_architecture_baseline.md` | `resolver` | `blocking-if-needed` |
| `PS-015` | Discriminant constraints | `docs/frontend_architecture_baseline.md` | `resolver` | `blocking-if-needed` |

## Tooling, Interface UX, and Assurance

| ID | Item | Source | Area | Priority |
|----|------|--------|------|----------|
| `PS-016` | Selective interface search-dir scanning or scoped tolerance for unrelated malformed `.safei.json` files | `PR08.3` review fallout | `tooling` | `nice-to-have` |
| `PS-017` | Ada-side Bronze regression harness independent of Python evidence re-derivation | `PR08.2` review fallout | `tooling` | `nice-to-have` |
| `PS-018` | Emitted-output GNATprove coverage beyond the selected PR10 concurrency corpus and the named sequential checkpoints; after `PR11.8b`, the retained emitted concurrency corpus is closed and this item remains only as a placeholder for any future proof-bearing admitted surface beyond the current checkpoints | `docs/emitted_output_verification_matrix.md`; `docs/PR11.x-series-proposed.md` | `tooling` | `long-term` |
| `PS-019` | I/O seam wrapper obligations beyond direct emitted-package proof | `docs/emitted_output_verification_matrix.md` | `tooling` | `long-term` |
| `PS-020` | Diagnostic catalogue and localisation `TBD-05` | `spec/00-front-matter.md` section `0.8` | `tooling` | `long-term` |
| `PS-021` | Stabilise and document interchange-format policy for existing `safei-v1` and `mir-v2` artifacts, including compatibility and what is normative versus implementation-defined `TBD-08` | `spec/00-front-matter.md` section `0.8`; `compiler_impl/src/safe_frontend-interfaces.adb`; `compiler_impl/src/safe_frontend-mir_analyze.adb` | `tooling` | `long-term` |
| `PS-022` | Performance targets `TBD-02` | `spec/00-front-matter.md` section `0.8` | `tooling` | `long-term` |
| `PS-023` | SPARK container library compatibility gaps | `docs/spark_container_compatibility.md` | `tooling` | `long-term` |

## Spec and Language TBDs

Historical note: `PS-034` is closed by `PR11.8g.4`; see
[`docs/pr118g4-proof-journal.md`](pr118g4-proof-journal.md).

| ID | Item | Source | Area | Priority |
|----|------|--------|------|----------|
| `PS-024` | Target platform constraints beyond “Ada compiler exists” `TBD-01` | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| `PS-025` | Memory model constraints: stack, heap, and static allocation bounds `TBD-03` | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| `PS-026` | Floating-point semantics beyond inheriting Ada's defaults `TBD-04`; still explicitly deferred after `PR11.8a` | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| `PS-027` | Abort handler behaviour `TBD-07` | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| `PS-028` | Numeric model: required ranges for predefined integer types `TBD-10` | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| `PS-029` | Automatic deallocation semantics and ordering at scope exit beyond the covered nested early-return capture-ordering regression `TBD-11` | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| `PS-036` | Runtime-model claims beyond the admitted STM32F4/Jorvik-backed concurrency subset, including broader scheduling, ceiling-locking, and polling-timing guarantees across unsupported targets or runtimes | `docs/jorvik_concurrency_contract.md`; `docs/emitted_output_verification_matrix.md`; `spec/04-tasks-and-channels.md` | `spec` | `long-term` |
| `PS-032` | Limited/private type views across packages `TBD-13` | `spec/00-front-matter.md` section `0.8` | `language-design` | `long-term` |
| `PS-033` | Partial initialisation facility `TBD-14` | `spec/00-front-matter.md` section `0.8` | `language-design` | `long-term` |

## Summary Counts

| Priority | Count |
|----------|------:|
| `blocking-if-needed` | 14 |
| `nice-to-have` | 3 |
| `long-term` | 16 |
| **Total** | **33** |

See [`docs/pr10_refinement_audit.md`](pr10_refinement_audit.md) for the full
PR10.1 disposition record, including promoted `PR10.2+` work and items closed
as fixed, duplicate, spec-excluded, or already tracked elsewhere.
