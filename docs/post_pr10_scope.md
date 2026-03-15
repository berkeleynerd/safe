# Post-PR10 Scope Ledger

## Purpose

This document is the overflow ledger for work that is intentionally deferred
**beyond PR10**.

Items belong here only if they are:

- still open
- not already tracked by `PR08.4`, `PR09`, or `PR10`
- not already fixed in the current repo
- not explicitly excluded by the current spec unless they remain an active
  future language or specification topic

This is not a general backlog. Future syntax proposals belong primarily in
[`docs/syntax_proposals.md`](syntax_proposals.md), and tracked pre-PR10 work
belongs in [`execution/tracker.json`](../execution/tracker.json).

## How to Add Items

Append a row to the appropriate thematic table using this template:

| Item | Source | Area | Priority |
|------|--------|------|----------|
| *Short description of the deferred item* | *spec section, milestone, review round, or document path* | *See legend* | *See legend* |

Before adding an item, verify that it is not already fixed, not already tracked
before PR10, and not better owned by `docs/syntax_proposals.md`.

## Legend

**Source** — where the deferred item was validated (for example, `PR08.3a`,
`spec/00-front-matter.md` section `0.8`, or a current baseline document).

**Area** — the subsystem or category primarily affected:

| Tag | Meaning |
|-----|---------|
| `parser` | Front-end parsing and AST construction |
| `resolver` | Name resolution and semantic tree building |
| `analyzer` | Static analysis, flow, ownership, or concurrency checks |
| `spec` | Normative language or runtime model work |
| `tooling` | Validators, gates, reports, or build/test infrastructure |
| `language-design` | Future language surface or semantic design work |

**Priority**:

| Tag | Meaning |
|-----|---------|
| `blocking-if-needed` | Required before the relevant deferred capability can ship |
| `nice-to-have` | Valuable precision or UX work, but not a prerequisite for current tracked milestones |
| `long-term` | Intentional post-PR10 deferral; revisit after the current roadmap lands |

---

## Static Evaluation and Numeric Analysis

| Item | Source | Area | Priority |
|------|--------|------|----------|
| Static evaluation beyond the minimal constant-reference subset used by PR08.3a and the still-deferred named-number work, including binary arithmetic and declaration-time dot-attribute references such as `.First` / `.Last` | `PR08.3a`, `spec/03-single-file-packages.md` section `3.2.7`, `compiler_impl/src/safe_frontend-check_resolve.adb` | `resolver` | `blocking-if-needed` |
| Fixed-point Rule 5 support beyond the frozen current subset | `docs/frontend_architecture_baseline.md` | `analyzer` | `blocking-if-needed` |

## Concurrency, Ownership, and Runtime Model

| Item | Source | Area | Priority |
|------|--------|------|----------|
| `try_receive` failure-path precision beyond the current conservative model | `PR08.2` review fallout, `spec/04-tasks-and-channels.md` paragraph 30 | `analyzer` | `nice-to-have` |
| Imported package-qualified writes with sound cross-package mutability rules | `PR08.3` boundary, `compiler_impl/README.md` | `resolver` | `long-term` |
| Channel deadlock analysis (TBD-09) | `spec/00-front-matter.md` section `0.8` | `analyzer` | `long-term` |
| `Constant_After_Elaboration` for concurrency analysis (TBD-06) | `spec/00-front-matter.md` section `0.8` | `analyzer` | `blocking-if-needed` |
| Faithful source-level `select ... or delay ...` semantics beyond the current emitted polling-based lowering | `docs/emitted_output_verification_matrix.md`, `spec/04-tasks-and-channels.md` section `4.4` | `spec` | `long-term` |
| Task-level fault containment and restart intensity | `spec/02-restrictions.md` paragraphs `151a`-`151g` | `spec` | `long-term` |
| Clarify and standardise spec text for constant access objects versus access-to-constant / observe writes through `.all` | `PR08.3a` review fallout, `compiler_impl/src/safe_frontend-check_resolve.adb`, `compiler_impl/src/safe_frontend-mir_analyze.adb` | `spec` | `long-term` |

## Language Surface and Semantic Coverage

| Item | Source | Area | Priority |
|------|--------|------|----------|
| Named-number declarations and imported named-number values through `safei-v1`, beyond the ordinary-constant subset shipped in PR08.3a | `spec/03-single-file-packages.md` section `3.3.1`, roadmap decision after `PR08.3a` | `resolver` | `long-term` |
| String and character literals | `PR03`, `compiler_impl/src/safe_frontend-check_parse.adb` | `parser` | `blocking-if-needed` |
| Case statements | `spec/02-restrictions.md` paragraph 28, current unsupported surface | `parser` | `blocking-if-needed` |
| Task declarative parts beyond object declarations | `PR08.1` boundary | `resolver` | `long-term` |
| Decide whether `goto` and statement labels remain retained or are formally excluded from the future language surface; implement only if the spec keeps them | `docs/syntax_proposals.md`, `spec/02-restrictions.md` paragraph 28, `compiler_impl/src/safe_frontend-check_parse.adb` | `language-design` | `long-term` |
| General discriminants | `docs/frontend_architecture_baseline.md` | `resolver` | `blocking-if-needed` |
| Discriminant constraints | `docs/frontend_architecture_baseline.md` | `resolver` | `blocking-if-needed` |

## Tooling, Interface UX, and Assurance

| Item | Source | Area | Priority |
|------|--------|------|----------|
| Selective interface search-dir scanning or scoped tolerance for unrelated malformed `.safei.json` files | `PR08.3` review fallout | `tooling` | `nice-to-have` |
| Ada-side Bronze regression harness independent of Python evidence re-derivation | `PR08.2` review fallout | `tooling` | `nice-to-have` |
| Emitted-output GNATprove coverage beyond the selected PR10 sequential corpus | `docs/emitted_output_verification_matrix.md`, `execution/tracker.json` | `tooling` | `long-term` |
| Emitted-output GNATprove coverage beyond the selected PR10 concurrency corpus | `docs/emitted_output_verification_matrix.md`, `execution/tracker.json` | `tooling` | `long-term` |
| I/O seam wrapper obligations beyond direct emitted-package proof | `docs/emitted_output_verification_matrix.md` | `tooling` | `long-term` |
| Diagnostic catalogue and localisation (TBD-05) | `spec/00-front-matter.md` section `0.8` | `tooling` | `long-term` |
| Stabilise and document interchange-format policy for existing `safei-v1` and `mir-v2` artifacts, including compatibility and what is normative versus implementation-defined (TBD-08) | `spec/00-front-matter.md` section `0.8`, `compiler_impl/src/safe_frontend-interfaces.adb`, `compiler_impl/src/safe_frontend-mir_analyze.adb` | `tooling` | `long-term` |
| Performance targets (TBD-02) | `spec/00-front-matter.md` section `0.8` | `tooling` | `long-term` |
| SPARK container library compatibility gaps | `docs/spark_container_compatibility.md` | `tooling` | `long-term` |

## Spec and Language TBDs

| Item | Source | Area | Priority |
|------|--------|------|----------|
| Target platform constraints beyond "Ada compiler exists" (TBD-01) | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| Memory model constraints: stack, heap, and static allocation bounds (TBD-03) | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| Floating-point semantics beyond inheriting Ada's defaults (TBD-04) | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| Abort handler behaviour (TBD-07) | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| Numeric model: required ranges for predefined integer types (TBD-10) | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| Automatic deallocation semantics and ordering at scope exit (TBD-11) | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| Modular arithmetic wrapping semantics (TBD-12) | `spec/00-front-matter.md` section `0.8` | `spec` | `blocking-if-needed` |
| Jorvik/Ravenscar runtime scheduling, ceiling-locking, and polling-timing obligations beyond direct emitted-package proof | `docs/emitted_output_verification_matrix.md`, `spec/04-tasks-and-channels.md` | `spec` | `long-term` |
| Limited/private type views across packages (TBD-13) | `spec/00-front-matter.md` section `0.8` | `language-design` | `long-term` |
| Partial initialisation facility (TBD-14) | `spec/00-front-matter.md` section `0.8` | `language-design` | `long-term` |

## Summary Counts

| Priority | Count |
|----------|------:|
| `blocking-if-needed` | 14 |
| `nice-to-have` | 3 |
| `long-term` | 18 |
| **Total** | **35** |

See [`docs/post_pr10_scope_audit.md`](post_pr10_scope_audit.md) for the audit
record that removed fixed items, pre-PR10 tracked work, spec-excluded rows, and
syntax-proposal duplicates from the original draft.
