# PR11.x Series — Proposed Milestone Roadmap

This document records the proposed detailed content for the tracked `PR11.x`
planned milestones.

In this stripped-down branch, it is retained as documentation only: the old
execution tracker/dashboard material was removed, and no milestone described
here is currently wired into CI or committed evidence reports.

Source material: `docs/post_pr10_scope.md` (PS-xxx ledger),
`docs/syntax_proposals.md` (15 syntax proposals),
`docs/frontend_architecture_baseline.md` (current accepted language surface),
and `docs/emitted_output_verification_matrix.md` (current proof coverage).

## Prerequisites

PR10.3, PR10.4, PR10.5, and PR10.6 should complete before any work described
here begins. Those milestones close the ownership proof expansion,
parser/evidence hardening, emitter maintenance hardening, and remaining
sequential proof-corpus expansion respectively. All four descend from PR10.1.
After that, `PR11` should not let the acceptance/proof gap widen unchecked: the
roadmap now stages explicit proof checkpoints plus a parallel concurrency-proof
track rather than deferring all proof work to the end of the series.

Dependency chain:

- PR10.1 → PR10.3 / PR10.4 / PR10.5.
- PR10.6 depends on PR10.3.
- PR11.1 depends on PR10.4, PR10.5, and PR10.6.
- PR11.3a follows PR11.3 (first proof checkpoint).
- PR11.8a depends on both PR11.3a and PR11.8; it cannot land before the first
  proof checkpoint (`PR11.3a`).
- PR11.8b runs as a parallel track after PR10.5 and PR10.6 and must land
  before PR11.8g and `PR11.9`.
- PR11.8b.1 followed PR11.8b and shipped the deferred channel-contract syntax
  work in PR #140; its emitted-proof fixtures were later absorbed into
  `PR11.8g.1` / `PR11.8g.3`.
- PR11.8c follows PR11.8a.
- PR11.8c.1 follows PR11.8c.
- PR11.8c.2 follows PR11.8c.1.
- PR11.8d follows PR11.8c.2.
- PR11.8e follows PR11.8d.
- PR11.8d.1 follows PR11.8e (deferred PR11.8d string/array follow-up; independent of PR11.8g and may land any time before PR11.9).
- PR11.8e.1 follows PR11.8e (mutually recursive record families; may interleave with PR11.8f).
- PR11.8e.2 follows PR11.8e.1 (field-disjoint `mut` alias reasoning).
- PR11.8f follows PR11.8e (lands as PR11.8f-a then PR11.8f-b).
- PR11.8f.1 follows PR11.8f-b (structural traversal emission and task-warning debt retirement).
- PR11.8g depends on both PR11.8f.1 and PR11.8b.
- PR11.8g.1 follows PR11.8g (broad emitted proof-corpus expansion for `PS-018`).
- PR11.8g.2 follows PR11.8g.1 (remove emitted `SPARK_Mode => Off`; standard-library I/O seam).
- PR11.8g.3 follows PR11.8g.2 (Jorvik-backed concurrency-semantics closure).
- PR11.8g.4 follows PR11.8g.2 (shared-runtime generic-contract soundness closure; may interleave with PR11.8g.3).
- PR11.8h follows PR11.8g.3 and PR11.8g.4 (safe prove CLI command).
- PR11.8i follows PR11.8h (user-defined enumerations).
- PR11.8i.1 follows PR11.8i (full emitted proof-corpus closure for admitted surface).
- PR11.8j follows PR11.8i.1 (incremental build for multi-file projects).
- PR11.8k follows PR11.8j (structured error handling and result propagation).
- PR11.9 follows PR11.8k.
- PR11.9a follows PR11.9 (aggregated dispatcher select; eliminates polling).
- PR11.9b follows PR11.9a (fair select with round-robin rotation).
- PR11.9c may interleave with PR11.9a/PR11.9b (FIFO ordering ghost model; eliminates assumption B-02).
- PR11.9d follows PR11.9b (nonblocking send discipline; locked decision: prohibit blocking send).
- PR11.10 follows PR11.9d (built-in parameterized containers — parent milestone).
- PR11.10a follows PR11.9d (optional T — first container wedge; validates type-constructor pipeline).
- PR11.10b follows PR11.10a (list of T — growable ordered sequence).
- PR11.10c follows PR11.10b (map of (K, V) — key-value lookup).
- PR11.10d follows PR11.10c (container proof closure and standard-library proof checkpoint).
- PR11.11 follows PR11.10d (generics, methods, and structural interfaces — parent milestone).
- PR11.11a follows PR11.10d (method syntax — receiver-parameter functions with value.method() call sugar).
- PR11.11b follows PR11.11a (structural interfaces — Go-style named operation contracts with compile-time satisfaction).
- PR11.11c follows PR11.11b (user-defined generics — parameterized types/functions with value-type and interface constraints).
- PR11.12 follows PR11.11c (shared concurrent records — parent milestone).
- PR11.12a follows PR11.11c (shared record field-access wedge).
- PR11.12b follows PR11.12a (whole-record snapshot/update and nested writes for same-unit shared records).
- PR11.12c follows PR11.12b (heap-backed shared-record fields and copy-safe protected-wrapper operations).
- PR11.12d follows PR11.12c (parameterized shared container roots on the shared-wrapper substrate).
- PR11.12e follows PR11.12d (public/imported shared declarations with the full local read/write surface exported across packages).
- PR11.12f follows PR11.12e (exact shared ceiling-priority analysis from cross-package access summaries).
- PR11.12g follows PR11.12f (shared-wrapper proof closure and roadmap/spec alignment).
- PR11.13 follows PR11.12g (user-defined sum types with exhaustive match — parent milestone).
- PR11.13a follows PR11.12g (sum type declaration and variant construction — pipeline validation wedge).
- PR11.13b follows PR11.13a (exhaustive match destructuring with payload bindings).
- PR11.13c follows PR11.13b (cross-package sum types and proof closure checkpoint).
- PR11.22 follows PR11.13c (codebase hygiene — pulled forward to de-risk remaining features).
- PR11.22a follows PR11.13c (CLAUDE.md and documentation refresh).
- PR11.22b follows PR11.22a (abandoned branch cleanup and model enum hygiene).
- PR11.22c follows PR11.22b (emitter monster-function decomposition).
- PR11.22d follows PR11.22c (emitter deduplication and vestigial code removal).
- PR11.22e follows PR11.22d (emitter file split into domain-focused modules).
- PR11.22f follows PR11.22e (resolver cleanup and builtin-resolution consolidation).
- PR11.22i follows PR11.22h (emitter boundary audit and support-surface inventory).
- PR11.22j follows PR11.22i (emitter interface narrowing and boilerplate reduction).
- PR11.22k follows PR11.22j (focused emitter domain validation lanes).
- PR11.23 follows PR11.22k (proof diagnostic mapping — Safe-native proof failure messages with source locations and fix guidance).
- PR11.15 follows PR11.22f (string interpolation — low risk, high usability).
- PR11.16 follows PR11.15 (nominal type aliases — distinct types with no implicit conversion).
- PR11.14 follows PR11.16 (closures — deferred past hygiene to reduce implementation risk).
- PR11.22g follows PR11.14 (test infrastructure modularization).
- PR11.22h follows PR11.22g (shared stdlib contract audit and body-drift check).
- PR11.17–PR11.21 moved to PR14 series (deferred past all existing work; see PR14 below).

---

## PR11.1: Language Evaluation Harness

The first post-10.x milestone. It exists to gather early feedback on language
changes with real programs and repeatable tooling, before parser-completeness
or syntax-iteration work starts. It does not attempt full IDE support and does
not freeze syntax, diagnostics, or artifact formats.

### Deliverables

**`safe build <file.safe>` — one-command compile wrapper.**
Python script calling `safec emit --ada-out-dir` followed by `gprbuild`. Produces
a compiled Ada executable from a single Safe source file. Follows the no-Python-
in-safec-runtime doctrine: this is a separate orchestration tool, not part of
`safec` itself.

**VSCode language grammar — static `.tmLanguage.json`.**
Keyword highlighting, comment and string coloring, bracket matching. Updated
when syntax changes (estimated ~20 minutes per update). No semantic analysis,
no type-aware highlighting.

**Diagnostics LSP shim — thin JSON-RPC process.**
Calls `safec check --diag-json` on save, maps `diagnostics-v0` output to LSP
`publishDiagnostics`. No completion, no hover, no rename, no go-to-definition.
Explicitly disposable — will be replaced by a real LSP server post-v1.0.

**Rosetta/sample corpus gate.**
A living code corpus under `samples/rosetta/` so syntax and parser changes are
evaluated across real programs rather than hand-crafted examples. The initial
gate is `safec check` → `safec emit --ada-out-dir` → `gprbuild` compile only;
it is not a proof-corpus milestone.

### Scope Exclusions

- No formatter
- No file watcher
- No code completion
- No package manager integration
- No full LSP feature set
- No artifact-contract freeze

### Rosetta Feasibility Appendix

The initial twelve Rosetta/sample candidates are classified against the current
frontend surface now, before `PR11.1` is treated as a completed milestone.
`PR11.1` itself is responsible for creating the files and the real gate, but
its acceptance is constrained by this starter-set classification rather than by
an unqualified promise that all twelve programs land immediately.

None of the current twelve candidates require `PR11.2` string/character or
case-statement support. Those surfaces become Rosetta growth items after
`PR11.2`; they are not blockers for `PR11.1`.

| Candidate | Status for `PR11.1` | Notes |
|-----------|----------------------|-------|
| `fibonacci.safe` | starter corpus | Fits the current sequential integer subset. |
| `gcd.safe` | starter corpus | Fits current integer arithmetic and loop surface. |
| `factorial.safe` | starter corpus | Fits current sequential arithmetic subset. |
| `collatz_bounded.safe` | starter corpus | Fits bounded integer/control-flow surface without new parser work. |
| `bubble_sort.safe` | starter corpus | Fits current arrays/loops/indexing subset. |
| `binary_search.safe` | starter corpus | Already aligned with the current Rule 2/frontend baseline style. |
| `bounded_stack.safe` | starter corpus | Fits current records/arrays/procedures without new language work. |
| `producer_consumer.safe` | starter corpus | Fits the accepted local concurrency slice if kept within the current task/channel subset. |
| `linked_list_reverse.safe` | candidate expansion | Validate against the current ownership subset before admission. |
| `prime_sieve_pipeline.safe` | candidate expansion | Validate against the current task/channel/select subset before admission. |
| `trapezoidal_rule.safe` | deferred | Depends on later numeric work; target `PR11.8`. |
| `newton_sqrt_bounded.safe` | deferred | Depends on later numeric/convergence-policy work; target `PR11.8` and possibly post-`PR11.11` float-semantics decisions. |

### Starter Corpus for `PR11.1`

The validated starter corpus that `PR11.1` should actually require is:

**Arithmetic:**
- `fibonacci.safe`
- `gcd.safe`
- `factorial.safe`
- `collatz_bounded.safe`

**Sorting:**
- `bubble_sort.safe`
- `binary_search.safe`

**Data structures:**
- `bounded_stack.safe`

**Concurrency:**
- `producer_consumer.safe`

### Gate and CI

When `PR11.1` is implemented, `scripts/run_rosetta_corpus.py` should validate
the starter corpus as `safec check` → `safec emit --ada-out-dir` → `gprbuild`
compile. It is intentionally a future milestone gate, not part of this
roadmap-materialization change.

### Growth Policy

The corpus grows as the language surface expands. Strings, case statements,
generics, and each new syntax feature unlock additional Rosetta tasks. New
programs are added to the corpus as each milestone lands, and the
candidate-expansion/deferred rows above are the first queued growth items.

### Syntax-Proposal UAT

The corpus enables mechanical syntax-proposal evaluation. When a syntax change
is proposed, the transformation is applied across the current starter corpus and
later growth set, compiled, and reviewed. This replaces ad-hoc example
evaluation with systematic acceptance testing across diverse program
structures.

### Proof-Coverage Staging

`PR11.1` itself is intentionally a compile milestone, not a proof milestone.
Post-`PR10.x` emitted proof expansion now re-enters the roadmap in three
bounded places instead of one late catch-up:

- `PR11.3a` closes proof debt introduced by `PR11.2` and `PR11.3` before the
  syntax-admission phases resume.
- `PR11.8a` closes numeric-model proof debt and revalidates the numeric-
  sensitive proved corpus after `PR11.8`.
- `PR11.8b` runs in parallel after `PR10.5` and `PR10.6` to close the currently
  retained emitted concurrency proof gap before the value-type channel
  milestone and `PR11.9` artifact-contract freeze.
- `PR11.8f` closes the proof debt introduced by the copy-by-default value-type
  model before artifact contracts freeze.

Until `PR11.8g.3`, items outside direct emitted Ada/SPARK package proof remain
outside these checkpoints: faithful source-level select semantics (`PS-007`)
and runtime scheduling/locking obligations (`PS-031`). After `PR11.8g.3`, the
shipped concurrency subset is closed against the blocking Jorvik-backed
evidence lane, and only the broader residuals (`PS-035` / `PS-036`) remain
outside the admitted surface. `PS-035` is then taken up explicitly by
`PR11.9a` / `PR11.9b` and the later concurrency follow-ons, rather than being
left in an unnamed post-freeze bucket, while `PS-036` remains outside the
scheduled `PR11.x` surface. The shared I/O/runtime seam closes under
`PR11.8g.2`.

---

## PR11.2: Parser Completeness Phase 1

Close the first blocking parser gaps that prevent real programs from being
written, without pulling in the larger discriminant/type-system expansion yet.

### Scope

| PS Item | Description | Area |
|---------|-------------|------|
| PS-011 | String and character literals | parser |
| PS-012 | Case statements | parser |

### Deliverables

- Parser extended for each item above.
- Resolver/emitter extended as needed for string/character literal use sites and
  case statements.
- The admitted `case` subset in PR11.2 is strict/Ada-like statement syntax
  only: `case <expr> is`, `when <choice> then ... end when;`, one mandatory
  final `when others then`, and `end case;`. Default-mode/whitespace `case`
  syntax and variant-part `case` remain future work.
- A predefined immutable `string` type is introduced as a convenience for the
  casual-typing style. In PR11.2, `string` lowers directly to Ada `String` for
  the accepted parameter/return/constant/literal use sites; it is not an alias
  to future `string_buffer`. Mutable bounded text storage remains deferred to
  PR11.10. This keeps Go-style code like `function lookup (k : string) returns
  string` available without pulling the bounded-buffer library surface forward.
- Rosetta corpus updated with newly-enabled programs (e.g., string manipulation,
  case-driven dispatch).
- Existing test corpus expanded with positive and negative coverage for each
  new surface.

---

## PR11.3: Discriminated Types, Tuples, and Structured Returns

Close the larger type-system gap after the first parser-completion pass has
landed. This is not just parser work: it extends parsing, resolution, type
modeling, MIR lowering, and Ada emission for a bounded discriminated-record
subset plus the first tuple/structured-return surface. That broader grouping is
intentional: discriminants, tuples, and structured returns solve related data-
modeling problems, and the emitter/ownership/type decisions need to stay
coherent across them.

### Scope

| PS Item | Description | Area |
|---------|-------------|------|
| PS-014 | General discriminants | resolver |
| PS-015 | Discriminant constraints | resolver |
| Tuples | Anonymous tuple types, multiple returns, destructuring | parser / resolver / emitter |
| Error Handling Convention | `(boolean, T)` and builtin `result` conventions | resolver / emitter |

### Accepted Subset

- Record discriminants only. No task, limited, private, interface, or
  class-wide discriminants in this milestone.
- Multiple scalar discriminants are allowed within the accepted subset.
- Discriminant defaults are supported where the accepted type form permits
  unconstrained use.
- Explicit discriminant constraints are supported on object declarations,
  parameter types, and function result types within the accepted subset.
- Variant parts are supported only when they are driven directly by the
  accepted scalar discriminants and can be lowered without introducing
  cross-package view complications.
- **Tuple types and multiple returns.** Anonymous product types written as
  `(boolean, string)` in type position and `(true, "hello")` in expression
  position. Functions may return tuple types: `function lookup (...) returns
  (boolean, string)`. Destructuring bind is supported: `var (found, data) :
  (boolean, string) = lookup (...)`. Tuples are designed alongside
  discriminated records because they solve related problems (structured return
  values) and the type-system, ownership, and emitter decisions must be
  coherent across both. The emitter lowers tuples to Ada records with
  positional field names (`F1`, `F2`, etc.).
- **Builtin `result` and constructors.** PR11.3 also lands a predefined
  compiler-known `result` value type plus `ok` and `fail (String)` constructors
  so `(result, T)` becomes the richer structured-return convention once tuples
  exist. `result` is the only PR11.3 carveout that semantically contains a
  `String` field; ordinary user-declared `String` fields remain deferred.

### Semantic Closure Required

- Constrained versus unconstrained object rules must be explicit for the
  accepted subset.
- Assignment/copy legality between differently constrained objects must be
  defined and enforced.
- Field-selection legality for variant-dependent components must be coherent
  with the resolved discriminant facts available in the current scope.
- Defaulted discriminants and explicit constraints must agree on when an object
  is treated as constrained versus unconstrained.

### Explicit Deferrals

- Access discriminants remain out of scope.
- Private/limited-view and cross-package discriminant-view issues remain out of
  scope.
- Discriminant-constrained dispatch remains out of scope.
- Generic interactions remain out of scope.
- Ownership-specific discriminant extensions are out of scope unless a concrete
  accepted example later proves they are required.
- Nested tuples, access-typed tuple elements, and generic `result (T, E)` stay
  out of scope in PR11.3.

### Deliverables

- Parser support for the accepted discriminated-record subset.
- Resolver/type-model support for general discriminants beyond the current
  boolean result-record subset, including explicit discriminant constraints.
- MIR lowering and emitted Ada support for the accepted discriminant, tuple,
  and structured-return surface.
- A non-shrinkable positive/negative corpus covering:
  - multiple scalar discriminants
  - defaulted discriminants
  - explicit discriminant constraints on objects, parameters, and results
  - accepted variant-part usage
  - tuple returns, destructuring, tuple field access, tuple channels, and the
    builtin `result` conventions
  - rejected out-of-scope forms
- Emitted-structure assertions so the milestone cannot be satisfied by silently
  flattening or erasing discriminant/tuple semantics.
- Rosetta/sample updates once PR11.1 exists, using real examples that depend on
  discriminated records and structured returns rather than synthetic
  micro-fixtures only.

### Evidence Model

- This should be a `check -> emit -> Ada compile` milestone first, not a proof
  milestone.
- The accepted subset should be locked by a dedicated deterministic gate and
  report, following the same non-shrinkable-corpus pattern used in the PR10.x
  series.
- If the scope proves too large, the first split should be variant parts; the
  next split should be builtin `result`, then tuple channels. General
  discriminants/constraints plus tuple returns/destructuring remain the core.

---

## PR11.3a: Proof Checkpoint 1 for Parser, Tuple, and Discriminant Expansion

This is the first deliberate proof catch-up point after `PR10.6`. It exists so
the proof gap created by `PR11.2` and `PR11.3` is closed before syntax-focused
milestones add more admitted-but-unproved surface area.

### Scope

- Prove the full emitted sequential fixture set admitted by `PR11.2`:
  `pr112_character_case.safe`, `pr112_discrete_case.safe`,
  `pr112_string_param.safe`, and `pr112_case_scrutinee_once.safe`.
- Prove the emitted sequential `PR11.3` fixture set:
  `pr113_discriminant_constraints.safe`, `pr113_tuple_destructure.safe`,
  `pr113_structured_result.safe`, and `pr113_variant_guard.safe`.
- Revalidate the already-proved sequential fixtures whose emitted proof shape
  is affected by the PR11.2/PR11.3 parser, tuple, and discriminant work:
  `constant_discriminant_default.safe`, `result_equality_check.safe`, and
  `result_guarded_access.safe`.
- Keep `pr113_tuple_channel.safe` explicitly outside this checkpoint. It
  remains accepted compile-only in `PR11.3`, but its proof debt stays on the
  later concurrency checkpoint `PR11.8b`.

### Deliverables

- A dedicated deterministic proof gate/report/CI job with a non-shrinkable
  named 11-fixture corpus covering the newly admitted `PR11.2` and sequential
  `PR11.3` emitted fixture set, plus the explicit revalidation set.
- All-proved-only compile / `flow` / `prove` closure for that checkpoint
  corpus.
- Matrix/docs wording that distinguishes the completed `PR10.x`
  sequential proof set from the `PR11.3a` parser/discriminant/tuple/result
  checkpoint, and explicitly records the deferred tuple-channel proof debt.

### PS-029 Decision Point

`PS-029` should no longer be treated as a purely post-`PR11.11` concern. For
this checkpoint, the boundary is explicit: `PR11.3a` remains a value-only
sequential proof set, does not pull tuple-channel or broader concurrency cases
forward, and does not broaden deallocation semantics beyond the already-admitted
non-access-bearing sequential corpus. If later milestones widen the admitted
surface past that boundary, they must reopen `PS-029` explicitly rather than
silently inheriting broader proof claims from `PR11.3a`.

---

## PR11.4: Full Syntax Cutover for Signatures, Branches, and Ranges

Front-load the lowest-risk syntax admissions first so the surface can stabilize
early while the more semantic proposals continue to evolve separately.

PR11.4 is a deliberate cutover, not a coexistence milestone. Once it lands, the
legacy spellings `procedure`, signature `return`, `elsif`, and `..` are removed
from the admitted Safe source surface rather than being tolerated in parallel.

### Proposals Included

| Syntax Proposal | Summary |
|-----------------|---------|
| `returns` Keyword | Replace `return` in signatures with `returns` |
| `else if` Keyword | Replace `elsif` with `else if` |
| Unified Function Type | Remove `procedure`; all callables are `function` |
| `to` Range Keyword | Replace `..` with `to` in range expressions |

### Deliverables

- Parser support for the full quartet with cutover-only acceptance: all
  callables use `function`, result-bearing signatures use `returns`,
  conditional chains use `else if`, and source-level inclusive ranges use `to`.
- Mechanical migration of the existing test corpus, Rosetta corpus, docs, and
  editor grammar/docs, including `procedure` → `function`, signature `return`
  → `returns`, `elsif` → `else if`, and `..` → `to`.
- Explicit negative coverage that locks rejection of each removed legacy
  spelling after the cutover lands.
- Deterministic acceptance corpus showing that the features are surface-only and
  do not perturb typing, MIR, `safei`, or emission for already-supported
  programs.
- The emitter maps `function` with no `returns` clause to Ada `procedure`,
  `function` with a `returns` clause to Ada `function`, and `to` ranges to
  Ada `..` ranges, keeping emitted Ada unchanged.

---

## PR11.5: Statement Ergonomics

Admit the next most likely syntax candidates after the basic signature and
control-flow spelling changes have settled.

### Proposals Included

| Syntax Proposal | Summary |
|-----------------|---------|
| Optional Semicolons | Parser-side omitted statement terminators for executable statement sequences |
| `var` Declarations | Statement-local variable declarations (from Statement Labels, Loop Labels, and `var` Declarations proposal) |

### Deliverables

- Parser-side statement terminator handling bounded to executable statement
  sequences, with declaration semicolons and `end when;` arm separators still
  explicit.
- Additive statement-local `var` support plus retained legacy
  `Name : Type [= Expr]` statement-local declarations, with a scoped legality
  model that does not accidentally broaden task or block semantics.
- Corpus migration guidance and Rosetta-side evaluation of readability and
  ambiguity costs.

### Deferred to PR11.8b.1

- Task channel direction constraints as a source-level legality check:
  `sends` and `receives` clauses on task declarations restrict which channel
  operations each task may perform.
- Scoped-binding `receive` and `try_receive`: inline declaration form
  (`receive ch, msg : T`) that declares the variable at the receive point,
  scoped to the enclosing block.

---

## PR11.6: Meaningful Whitespace Blocks

The product decision has been made: meaningful whitespace ships before 1.0 as
the admitted block-structuring surface for covered constructs. `pragma Strict`
is deferred to a post-1.0 design track rather than competing with the shipped
whitespace cutover in this milestone.

### Proposals Included

| Syntax Proposal | Summary |
|-----------------|---------|
| Whitespace-Significant Blocks | Indentation-defined block structure for covered constructs |

### Deliverables

- The lexer and parser ship deterministic indentation structure: spaces only,
  fixed 3-space steps, and no accidental mixed-syntax acceptance.
- A mechanical migration path plus deterministic corpus and Rosetta evidence
  demonstrate the shipped whitespace surface.
- PR11.6 ships the whitespace block cutover; the follow-on PR11.6.2 cleanup removes statement-level `declare`, `declare_expression`, source `null`, named `exit`, `goto`, `aliased`, and legacy representation-clause syntax from the admitted surface.
- `pragma Strict` is recorded as post-1.0 deferred work, not an in-flight
  competing syntax mode.

---

## PR11.7: Lowercase Identifier Convention ~~(was: Reference-Surface Experiments)~~

**Status: WON'T FIX (original scope).** The original PR11.7 proposals —
Capitalisation as Reference Signal and Implicit Dereference — are redundant.
The PR11.8 value-type revolution eliminates explicit `access` types from the
language surface entirely, removing the need for a visual signal distinguishing
reference-typed from value-typed bindings. Implicit dereference becomes moot
when there are no user-visible access types to dereference through.

**Replacement scope:** PR11.7 becomes a simple compiler-enforced lowercase
convention for all Safe source spellings.

### Rule

All Safe source spellings — package names, function names, type names, subtype
names, variable names, parameter names, record field names, channel names,
task names, reserved words, predefined names, attribute selectors, and admitted
aspect / pragma names — must be fully lowercase with underscores as word
separators for multiword spellings. The compiler rejects any source spelling
containing an uppercase letter.

### Rationale

- Safe's syntax is now indentation-structured with no Ada-style closing
  keywords. Mixed-case Ada identifiers (`My_Package`, `Get_Value`,
  `Node_Ptr`) are a visual holdover from a language surface that no longer
  exists.
- A uniform lowercase convention makes the source surface predictable and
  eliminates case-related ambiguity without encoding semantic information
  (ownership, visibility) in casing.
- The convention is enforceable mechanically with a single lexer check and a
  straightforward migrator.

### Deliverables

- Compiler enforcement: the lexer rejects any uppercase Safe source spelling,
  with a targeted diagnostic and lowercase rewrite hint.
- A mechanical migrator that lowercases all Safe source spellings across the
  corpus.
- Migration of the test corpus, Rosetta samples, and documentation.

### Explicitly Closed (WON'T FIX)

- Capitalisation as Reference Signal — redundant after PR11.8e removes
  explicit access types.
- Capitalisation as Export Signal — not scheduled; `public` keyword remains
  the visibility mechanism.
- Implicit Dereference — moot after PR11.8e; no user-visible access types
  to dereference.
- `move` keyword — not scheduled.

---

## PR11.8: Unified Integer Type

Replace all predefined integer types with a single `integer` type.

### Scope

- A single predefined `integer` type replaces all other predefined integer
  types (`Integer`, `Natural`, `Long_Long_Integer`, `Short`, `Byte`, etc.).
  It is 64-bit signed with full range by default.
- `integer (A to B)` provides inline range constraints at binding sites for
  parameters, fields, locals, and returns. `subtype` provides named range aliases:
  `subtype index is integer (1 to 256)`.
- Existing `type X is range A to B` becomes equivalent to
  `subtype X is integer (A to B)`.
- Wide-intermediate lifting (`Safe_Runtime.Wide_Integer`) is removed — the
  default integer is already 64-bit. Every integer arithmetic result must be
  statically provable within the signed 64-bit range.
- Integer literals have type `integer` with no conversion required.
- Array index types must be constrained (bounded).
- PS-028 (TBD-10) is resolved: there is one integer type with a minimum
  64-bit range.
- PS-030 (TBD-12) is deferred to PR11.8c (binary arithmetic).

### Migration

- Most explicit type conversions between integer types disappear.
- Rosetta corpus and test fixtures updated for the single integer model.

---

## PR11.8a: Proof Checkpoint 2 for Numeric-Model Revalidation

This is the second deliberate proof catch-up point. It prevents numeric-model
changes from invalidating or outpacing the previously proved emitted corpus.

### Scope

- Freeze a non-shrinkable PR11.8a checkpoint manifest inside
  `scripts/run_proofs.py`.
- Prove the emitted fixtures added or materially changed by `PR11.8`.
- Revalidate the previously proved numeric-sensitive corpus from `PR10`,
  `PR10.2`, `PR10.6`, and `PR11.3a` under the new integer-model surface.
- Treat the exact fixture list recorded in
  `docs/emitted_output_verification_matrix.md` as the canonical checkpoint
  claim.
- Keep fixed-point Rule 5 and broader floating-point semantics explicit rather
  than letting them drift into the proof claim implicitly.

### Deliverables

- The existing `python3 scripts/run_proofs.py` workflow and CI `prove` job
  report a dedicated PR11.8a checkpoint result with a non-shrinkable numeric
  proof corpus; no additional workflow or report infrastructure is added.
- All-proved-only compile / `flow` / `prove` closure for that corpus plus the
  required numeric-sensitive revalidation set.
- An explicit decision record for what remains deferred after the checkpoint,
  especially `PS-002`, `PS-018`, and `PS-026`.

---

## PR11.8b: Concurrency Proof Checkpoint

This milestone runs as a parallel track after `PR10.5` and `PR10.6` and should
complete before `PR11.8g` and `PR11.9`. It closes the bounded set of currently
accepted emitted concurrency fixtures that were outside the named proved
corpus, but it does so as a proof-only checkpoint rather than as a combined
proof-plus-syntax milestone.

### Scope

The originally intended proof corpus is the currently accepted emitted
concurrency subset beyond the frozen PR10 representatives and the already-
proved supplemental hardening fixture:

- `channel_ceiling_priority.safe`
- `exclusive_variable.safe`
- `fifo_ordering.safe`
- `multi_task_channel.safe`
- `select_delay_local_scope.safe`
- `select_priority.safe`
- `task_global_owner.safe`
- `task_priority_delay.safe`
- `try_ops.safe`
- `pr113_tuple_channel.safe`
- `channel_pipeline.safe`

Spec-excluded fixtures such as `channel_access_type.safe`,
`try_send_ownership.safe`, and `select_ownership_binding.safe` are not proof
debt and should remain excluded instead of being restated as missing coverage.

### Deliverables

- The existing `python3 scripts/run_proofs.py` workflow and CI `prove` job
  report a dedicated PR11.8b checkpoint result for the currently green
  concurrency subset. Any accepted/emitted fixtures that remain outside the
  live strict manifest must stay explicit and continuously monitored in
  `scripts/run_proofs.py` and
  [`docs/emitted_output_verification_matrix.md`](emitted_output_verification_matrix.md)
  rather than being treated as silently proved coverage. Those carried-forward
  monitors may use a bounded non-blocking prove profile until PR11.8f restores
  them to the hard checkpoint.
- All-proved-only compile / `flow` / `prove` closure for the admitted emitted
  concurrency corpus.
- Matrix/docs language that keeps the real retained concurrency gaps
  explicit: source-level select semantics (`PS-007`) and Jorvik/Ravenscar
  runtime obligations (`PS-031`) remain open even after emitted concurrency
  fixture proof expands. The shared I/O/runtime seam closes later in
  `PR11.8g.2`.

---

## PR11.8b.1: Channel Direction and Scoped-Binding Receive

Completed in PR #140.

This follow-on milestone carried the deferred concurrency-surface syntax work
separately from the PR11.8b proof checkpoint so parser/legality work did not
block proof closure and proof closure did not gate syntax admission. Its
representative fixtures were later absorbed into the blocking emitted-proof
lane in `PR11.8g.1`, with the admitted runtime/select closure landing in
`PR11.8g.3`.

### Scope

- Task channel direction constraints: `sends` / `receives` clauses on task
  declarations that restrict which channel operations each task may perform.
- Scoped-binding `receive` / `try_receive`: inline declaration form
  (`receive ch, msg : T`) that binds the received value at the receive point.

### Deliverables

- Parser, legality, and lowering support for task `sends` / `receives`
  clauses and scoped-binding `receive` / `try_receive`.
- No AST / typed / MIR schema change: scoped-binding receive lowers to the
  existing receive statement forms before artifact emission.
- Additive `safei-v1` evolution only: exported channel-access summaries retain
  the existing `channels` union and add directional `sends` / `receives`
  arrays for transitive channel-use checking across package boundaries.
- Corpus, docs, sample, and tooling updates that define the admitted syntax
  boundary without altering PR11.8b's checkpoint scope retroactively.

---

## PR11.8c: Binary Arithmetic

Complete the numeric-model follow-through after `PR11.8a` by admitting a
fixed-width binary arithmetic surface for bitwise operations, protocol
encoding, and hash computation.

### Scope

- `binary (N)` is the sole fixed-width binary type, wrapping at `2^N` for
  the standard widths `8`, `16`, `32`, and `64`. The name reflects the
  underlying reality: this is a fixed-width binary machine word where
  arithmetic wraps because that is what binary hardware does.
- `binary (N)` may appear inline at any type-spec site (parameters, fields,
  locals, returns) or in named declarations (`subtype crc is binary (32)`,
  `type hash_word is binary (32)`), mirroring the `integer (a to b)` inline
  constraint style.
- Explicit conversion is required between `integer` and `binary`; there is
  no implicit mixing.
- Bitwise operations `and`, `or`, `xor`, `not` are admitted for both
  `binary` and `boolean` operands. The type of the operands determines the
  semantics: single-bit logical for `boolean`, N-bit bitwise for `binary`.
- Shift operators `<<` and `>>` are admitted for `binary` operands only.
  They are infix: `hash << 5`, `value >> 3`. `>>` is a logical zero-fill
  right shift.
- `binary` operations carry no overflow proof obligations because
  wraparound is defined behavior.

### Deliverables

- `PS-030` is resolved with a stable wraps-at-`2^N` rule and explicit
  boundary conversion policy.
- Tests, samples, and emission rules admit the `binary` surface without
  silently broadening ordinary-integer semantics.
- The emitter maps `binary (8|16|32|64)` to Ada's
  `Interfaces.Unsigned_8|_16|_32|_64` and `<<`/`>>` to
  `Interfaces.Shift_Left`/`Interfaces.Shift_Right`.
- `and`, `or`, `xor`, `not` emit as the corresponding Ada operators for
  both boolean and Ada unsigned modular types.

---

## PR11.8c.1: Built-In Print

Add a built-in `print` statement so Safe code can produce visible output
without handwritten Ada printing logic once invoked by the existing driver
model.

### Scope

- `print` is a built-in statement that accepts `integer`, `string`, or
  `boolean` and writes one normalized line to standard output.
- No new I/O library or I/O type model. `print` is a single opaque
  built-in, not a user-extensible I/O surface.
- `print` is a statement, not an expression — it does not return a value.
- `integer` output is normalized without Ada `'Image` leading spaces,
  `boolean` prints as lowercase `true` / `false`, and `string` prints its
  contents directly.
- The emitter lowers `print` calls through the shared standard-library `IO`
  package rather than per-unit generated wrappers.
    - Emitted package bodies `with` `IO` directly and call its `Put_Line`
      procedure with the same normalized integer/boolean formatting used by the
      original PR11.8c surface.
    - The shared `IO` seam is included in the normal emitted proof/build
      workflow after `PR11.8g.2`; emitted packages no longer rely on generated
      `_safe_io` units or local `SPARK_Mode => Off` fences.
- Programs that use `print` still pass `python3 scripts/run_proofs.py`, and
  after `PR11.8g.2` they do so through the shared proved runtime seam rather
  than by excluding per-unit I/O helpers from proof.
- `safe build` remains unchanged in this milestone. Natural package-level
  execution semantics are still deferred to `PR11.8c.2`.
- A future I/O architecture based on persistent service tasks and channels
  (see `docs/vision.md`) may replace the current shared `IO` seam without
  changing the Safe source surface.

### Deliverables

- Parser, resolver, and emitter support for `print (expr)`.
- Shared `IO` seam support for emitted `print` calls.
- Positive fixtures demonstrating `print` with each accepted argument type.
- A negative fixture confirming `print` rejects unsupported argument types.
- A proof-bearing fixture that uses `print` and still passes GNATprove
  flow and prove through the shared `IO` seam.
- Updated tutorial and sample showing `print` in use.
- VS Code keyword highlighting for `print`.

---

## PR11.8c.2: Package-Level Statements and Single-File Entry Execution

Allow executable statements at unit scope so single-file Safe programs have a
natural entry point without requiring a handwritten Ada driver.

### Scope

- Executable statements are admitted at unit scope after all declarations.
  They run in source order before any tasks declared in the same unit start.
- Unit-scope statements use the same parsing, resolution, and lowering paths as
  function body statements. No new statement kinds are introduced.
- The emitter lowers unit-scope statements in explicit package units into the
  Ada package body's elaboration section (`begin ... end Package_Name;`).
- The `package` declaration is optional. If the first significant token after
  leading `with` clauses is not `package`, the file is treated as a packageless
  entry unit. The compiler infers the unit name from the filename stem
  (`hello.safe` becomes `hello`).
- Packageless entry units are executable roots, not libraries. They may not
  contain `public` declarations, and imports of entry-unit interfaces are
  rejected.
- `safe build <file.safe>` stays single-file only in this milestone:
  - packageless entry roots build through an emitted Ada `procedure Main`
  - explicit-package roots still build through the generated minimal driver
  - roots with leading `with` clauses are rejected and directed to the
    existing `safec emit` plus manual `gprbuild` flow
- Multi-file `safe build` remains future work rather than part of this
  milestone.

### Deliverables

- Parser change to accept statements after declarations at package scope.
- Parser change to accept files without a leading `package` declaration,
  inferring the unit name from the filename.
- Resolver and lowering support for unit-scope statements in the enclosing
  unit's visible scope.
- Emitter support for the Ada `begin` elaboration block in package bodies and
  for generating an Ada `procedure Main` from packageless entry files.
- Positive fixtures demonstrating unit-scope `print`, computation, pre-task
  initialization, and packageless entry files.
- Negative fixtures covering declaration-after-statement, invalid entry-unit
  filename stems, `public` in entry units, and rejected imports of entry-unit
  interfaces.
- Updated tutorial and CLI tutorial showing the single-file `safe build` flow
  and the retained manual multi-file `safec emit` plus `gprbuild` path.
- Update Rosetta samples that compute printable results to add top-level
  `print` calls demonstrating their output. Eligible samples: factorial
  (`print (compute (5))`), fibonacci (`print (nth (10))`), gcd
  (`print (compute (48, 18))`), collatz_bounded (`print (steps (27))`),
  grade_message (`print (render ('A'))`), and opcode_dispatch
  (`print (render (opcode (1)))`). Samples that return tuples, records,
  or arrays remain print-free until those types gain `print` support.
- A `safe repl` prototype (`scripts/safe_repl.py`) that accumulates
  declarations and statements into a packageless entry buffer, compiles
  and runs on each input line, and shows compiler diagnostics (including
  proof rejections) interactively. Tasks are not supported in REPL mode.

---

## PR11.8d: Value-Type String and Growable Arrays

Replace the earlier provisional text model with first-class string and array
value types that match the copy-by-default direction of the `PR11.8` series.

Implementation status: PR11.8d is complete for the planned non-channel scope.
Today:

- `string (N)` is the bounded stack-backed string form
- plain `string` is buildable in locals, params/results, tuple
  elements, record fields, and fixed-array components
- `array of T` is buildable in locals, params/results, record fields, and
  fixed-array components
- `for item of values` is implemented for array and string object names
- fixed -> growable array conversion works through target typing
- growable -> fixed narrowing works for bracket literals, static
  name-based slices, and direct guarded exact-length object names
- string iteration, string `case`, and string ordering are now shipped as
  part of `PR11.8d.1`
- string discriminants remain deferred
- string/growable channel elements now ship in `PR11.8g` as value-only
  channel elements
- the Rosetta corpus now includes bounded-string, growable-array, and
  fixed/growable conversion samples

### Scope: String

- `string` becomes a first-class value type: heap-backed, growable, copied on
  assignment, and freed on scope exit.
- `character` is removed as a separate type; character literals like `'A'`
  produce single-character strings. A character is a string of length 1.
- String literals construct `string` values directly, and `&` concatenates to a
  new owned string value.
- `string (N)` provides a compile-time-bounded stack-allocated variant.
- Built-ins include `.length`, indexing `s(3)`, slicing `s(1 to 5)`, and value
  equality `==`.
- ordinary parameters borrow without copying; `mut` parameters borrow
  mutably; assignment copies.

### Scope: Growable Arrays

- Arrays gain a growable form alongside the existing fixed-size form:
  - Fixed: `array (integer (1 to 256)) of integer` — size known at compile
    time, stack-allocated, prover verifies all indexing statically.
  - Growable: `array of integer` — no size constraint, heap-backed, length
    tracked at runtime, prover verifies index bounds against `.length`.
- `var items : array of integer = [1, 2, 3]` constructs a growable array.
- Concatenation with `&` returns a new array.
- `.length`, indexing `items(3)`, and slicing `items(1 to 5)` work for both
  fixed and growable forms.
- Array iteration is currently `for item of values` for array and string
  object names.
- The compiler decides the representation: constrained arrays are stack-
  allocated; unconstrained arrays are heap-backed. Both are value types
  that copy on assignment and free on scope exit.
- Array literals like `[90, 85, 72]` construct growable arrays by default.
- Assignment to a constrained binding narrows to fixed size only when the RHS
  length is syntactically exact at the conversion site.

### Migration and Deferred Items

- The corpus, samples, and documentation migrate to the unified string model
  instead of treating PR11.2 strings as the final shape.
- Array-heavy fixtures gain growable variants where appropriate.
- The following items are intentionally deferred beyond the shipped
  PR11.8d/PR11.8d.1 surface: broader proof-fact exact-length narrowing and
  string discriminants. Value-type string/growable channel elements ship
  separately in `PR11.8g`.

---

## PR11.8d.1: Deferred String Surface and Guarded Exact-Length Narrowing

Shipped on top of PR11.8d as the deferred string/array follow-up. This
milestone stayed independent of PR11.8g and completed the remaining
non-channel PR11.8d language surface.

### Scope

- **String `case`**: literal choices only. `case s` with string/tick literal
  `when` choices plus `others`, lowered as an `if`/`elsif` equality chain.
  Named constants and general expressions in choices are out of scope.
- **String iteration** (`for ch of s`): name-only iterable (must be a string
  object name, not a call/slice/concat expression). Each loop item is a
  `string (1)` — a one-character bounded string, mirroring how array
  `for ... of` yields the component type.
- **String ordering** (`<`, `<=`, `>`, `>=`): lexicographic comparison on
  string values, emitted as Ada string relational operators.
- **Guarded exact-length growable-to-fixed narrowing**: guarded syntax only. Accept
  narrowing when the narrowing site is immediately dominated by
  `if values.length == N` where `N` matches the target fixed-array
  cardinality. This is a syntactic pattern match in the resolver, not a
  proof-engine query. Broader proof-fact integration (consulting the MIR
  analyzer's interval state) is deferred to a later milestone.

### Notes

- This shipped as a feature follow-up to PR11.8d, not a proof checkpoint.
- String/growable-array channel elements ship separately in `PR11.8g`.
- String discriminants remain deferred separately because strings are not
  discrete.

---

## PR11.8e: Inferred Reference Types and Copy-Only Values

Eliminate explicit access types from the language surface. The compiler infers
reference semantics from the type graph; the programmer never writes `access`,
`ref`, `new`, `.all`, or `.access`.

### Scope

- All types are value types by default: assignment copies, with no ownership
  tracking or move semantics for pure values.
- The compiler infers reference semantics automatically for direct
  self-recursive record types in this milestone. Full mutually recursive record
  families are deferred to PR11.8e.1.
- No `access`, `ref`, or `?` annotation remains in the user-facing language
  surface. The programmer writes `next : node`; the compiler infers the heap
  indirection, nullability, and ownership requirements.
- All Safe source spellings are lowercase (enforced by PR11.7). No
  casing-based reference signal is needed because the language has no
  user-visible reference/value distinction at the identifier level.
- `null` is valid only for bindings whose type the compiler infers as
  reference-typed. Value-typed bindings cannot be null.
- Assignment of reference-typed bindings moves and nulls the source; assignment
  of value-typed bindings copies.
- Parameter modes simplify to two: unmarked (immutable borrow) and `mut`
  (mutable borrow). `in`, `in out`, and `out` are removed from Safe source;
  `out` parameters are replaced by tuple returns. The emitter maps `mut` to
  Ada `in out` for the same pass-by-reference efficiency.
- `new` is removed from the source surface. Construction of reference-typed
  values uses the record constructor directly, and allocation is compiler-
  managed.
- `.all` remains removed from source. Implicit dereference is the only access
  path, and `.access` / `.Access` also disappear from the source surface.
- The ownership model (move, borrow, observe, scope-exit deallocation) applies
  only to inferred reference-typed bindings.
- Records and arrays that contain no reference-typed fields, directly or
  transitively, remain pure value types with no ownership, no null, and no move
  semantics.
- The compiler rejects `mut` parameter aliasing at call sites: if two `mut`
  parameters in the same call could refer to the same variable, the call is
  rejected with a diagnostic. This prevents order-of-evaluation footguns
  where aliased mutable borrows produce implementation-defined results.
- Task bodies cannot access package-scope variables directly. Tasks see only
  their own locals and channels. All inter-task communication and result
  reporting goes through channels exclusively. This eliminates shared mutable
  state between tasks entirely — no single-writer rule is needed because
  there is nothing to share. Package-scope variables remain visible to
  ordinary function bodies (which run within a single task's context), but
  task body scope is restricted to locals plus channels. The existing
  concurrency corpus migrates from global-variable patterns to channel-based
  result reporting.

### Deliverables

- The admitted Safe source, grammar, and documentation remove explicit
  access-surface constructs: `access`, `ref`, named access types, `new`,
  `.access` / `.Access`, explicit access parameter modes (`in`, `in out`,
  `out`), explicit deallocation, and value-typed `null`. The sole mutable
  parameter annotation is `mut`. These removals remain emitter-internal Ada
  implementation details only.
- Diagnostics explain why a type was inferred as reference-typed when the
  nullability rules reject a use site.
- Diagnostics reject `mut` aliasing at call sites and task-body access to
  package-scope variables.

---

## PR11.8e.1: Mutually Recursive Record Families

Extend the reference-type inference admitted in PR11.8e from direct self-recursive
record types to full mutually recursive record families.

PR11.8e admits only the single-type cycle case — a record whose own field graph
contains a direct back-edge to itself. That covers the common patterns (linked
lists, trees, single-node graphs). This follow-up admits the general case.

### Scope

- Compute strongly-connected components (SCCs) across the fully resolved named-type
  graph after type resolution.
- Any SCC whose members are all record types is treated as a reference family: every
  member is inferred as reference-typed under the same ownership rules as PR11.8e
  single-type reference roots.
- SCCs that contain non-record types (arrays, tuples, scalars) remain rejected with
  a diagnostic explaining the cycle cannot be inferred as a reference family.
- Move-on-assignment, scope-exit deallocation, null-legality, and channel-element
  rejection extend to all members of an admitted reference family.
- Diagnostics explain which types form the cycle when a use site triggers a
  reference-family inference rule.

### Deliverables

- SCC-based type-graph analysis pass added after type resolution.
- Positive fixtures for two-type mutual recursion (e.g., `expr`/`stmt` tree) and
  three-or-more-type families.
- Negative fixtures for SCCs with non-record members.
- Schema, MIR, and safei versions unchanged from PR11.8e (no new surface syntax).

### Dependency

Follows PR11.8e. May land before or after PR11.8f depending on proof-corpus impact.

### Explicitly deferred

- **Field-disjoint mut alias reasoning** moves to `PR11.8e.2`. PR11.8e and
  PR11.8e.1 keep the conservative same-root rule for `mut` parameters.

- **Negative fixture coverage bookkeeping**: PR11.8e's removed-syntax and
  access-mode rejections remain intentionally covered by legacy-named negatives
  (`neg_own_anon_reassign`, `neg_own_anon_reassign_join`,
  `neg_own_observe_requires_access`, `neg_pr114_legacy_procedure`, and related
  ownership/task fixtures). Dedicated `neg_pr118e_*` fixtures cover the
  PR11.8e-specific gaps.

---

## PR11.8e.2: Field-Disjoint `mut` Alias Reasoning

Follow PR11.8e.1 by relaxing the conservative same-root `mut` alias rule only
for statically disjoint record-field actuals. This closes the original
PR11.8e body of work.

### Scope

- Extend call-site alias analysis from root-object equality to normalized field
  access paths.
- Admit same-root calls when at least one actual is `mut` and the two actuals
  are statically disjoint named record-field paths.
- Continue rejecting overlapping paths, whole-object-plus-descendant paths, and
  any case that cannot be proven disjoint statically.
- Keep tuple slots, discriminants, array indices, and container element paths
  out of scope in this milestone.
- Keep schema, MIR, and safei versions unchanged.

### Dependency

Follows PR11.8e.1.

---

## PR11.8f: Proof Checkpoint for Value-Type Model

Catch proof debt immediately after the copy-by-default value-type shift so the
artifact contract freeze does not inherit a second unbounded semantic gap.

PR11.8f lands as two staged PRs.

### PR11.8f-a: Concurrency Flow Cleanup and Proof Helper Foundation

- Clear the 9 carried-forward concurrency flow-warning monitors by fixing
  task/select lowering so GNATprove no longer sees redundant initializations as
  dead or effect-free.
- Preferred fix: stop emitting default initializers for scratch locals and
  temporaries when a dominating assignment exists before first read.
- Only if Ada definite-assignment rules force an initializer that GNATprove still
  flags, emit a localized `pragma Annotate (GNATprove, Intentional, ...)` in
  generated Ada, not source fixtures or harness suppressions.
- Replace inline inferred-reference `new` and local `Unchecked_Deallocation`
  patterns with synthesized package-level helper subprograms in emitted Ada:
  allocator/constructor helpers with proof-visible `Global` / `Depends` and
  non-null result contracts; free helpers with postconditions that null/reset the
  reference after deallocation; clone/move helpers where the emitter currently
  relies on raw access assignment.
- Apply the helper path to the pointer-dereference and resource-leak failures
  that the helper layer naturally resolves: `rule4_factory`, `ownership_observe`,
  `ownership_observe_access`, `ownership_return`.
- Acceptance: all 9 `PR11_8B_MONITORED_FIXTURES` green; the four helper-resolved
  fixtures green or reduced to timeout-only.

### PR11.8f-b: Sequential Proof Closure and Manifest Promotion

- Close the remaining sequential ownership/rule4 monitor failures:
  `rule4_linked_list`, `rule4_linked_list_sum`, and any timeout-only leftovers.
- Use emitter-side proof structure first: strengthen generated recursion/loop
  contracts so the reachable suffix / current cursor relationship is explicit;
  remove dead temporaries that generate flow noise before adding new invariants;
  add small emitted lemma/helper subprograms when they reduce prover search.
- For recursive self-reference traversals where the emitter currently produces
  a while-pointer-chase loop, use a narrow body-only `Skip_Proof` annotation.
  The annotation must include a generated comment recording: what the traversal
  does, why termination holds (the runtime structure is acyclic by construction
  from the allocator helper), and what would remove the annotation (bounded
  traversal emission in PR11.8f.1).
- Do not use `Skip_Proof` or false-positive suppressions for missing dereference
  safety facts or missing ownership/free postconditions.
- Once green, promote manifests:
  - move the 9 concurrency monitors back into the blocking PR11.8b checkpoint
  - introduce a blocking PR11.8f manifest containing the PR11.8e checkpoint plus
    the carried-forward sequential ownership/reference fixtures
  - remove or empty the temporary monitored groups so `run_proofs.py` no longer
    carries second-tier proof debt

### Scope

- This is an emitted-Ada / proof-hardening milestone only: no Safe syntax
  changes, no AST / typed / MIR / safei version bumps, no PR11.8e.1
  mutual-recursion work.
- Contracts and invariants first; GNATprove annotations allowed only for
  timeout-only leftovers and, in PR11.8f-b only, the explicitly tracked
  traversal `Skip_Proof`.
- All Safe code proves except IO. The traversal `Skip_Proof` in PR11.8f-b is
  temporary scaffolding retired by PR11.8f.1, not permanent debt.

### Deliverables

- A deterministic proof gate for the value-type model with a non-shrinkable
  revalidation corpus.
- An explicit decision record for what remains deferred after the checkpoint,
  especially generics, fixed-point, and broader floating-point semantics.
- Zero blocking failures and no residual failing monitor groups in
  `run_proofs.py`.

---

## PR11.8f.1: Structural Traversal Emission and Task-Warning Debt Retirement

Remove the temporary proof scaffolding left by PR11.8f-b by changing the
emitter so that the direct self-recursive traversal subset lowers to
structural cursor loops with proof-visible bounds, and retire the broad
task-body warning suppression debt in favor of targeted GNATprove warning
filters on the specific generated task-local diagnostics.

### Scope

- The compiler already knows the inferred reference structure is acyclic for
  the admitted direct self-recursive record subset. That knowledge is lowered
  into emitted Ada as structural `while Cursor /= null loop` traversals with
  proof-visible loop variants and accumulator bounds, not recursive helpers or
  compiler-invented bounded `for` caps.
- Once the emitter produces these structural traversal loops, GNATprove proves
  the linked-list traversal subset without the PR11.8f-b body-only
  `Skip_Proof` scaffolding.
- The task-body path no longer relies on region-wide `pragma Warnings (Off);`
  fences. Remaining concurrency flow-noise is handled by narrow
  `pragma Warnings (GNATprove, Off, ...)` regions on the specific generated
  task-local initialization, assignment, and receive/try-receive patterns.
- Update `docs/emitted_output_verification_matrix.md` to record that recursive
  traversal is now fully proved, not deferred.

### Removal condition

The remaining proof-scaffolding debt from PR11.8f-b is deleted when and only when:

1. The emitter produces structural cursor loops for every direct
   self-recursive traversal that previously used a recursive helper with
   `Skip_Proof`.
2. GNATprove proves those structural loops without body-only proof deferral.
3. The task-body warning path uses only targeted `GNATprove` warning filters,
   not blanket task-wide warning suppression.
4. The affected fixtures (`rule4_linked_list`, `rule4_linked_list_sum`, and the
   restored PR11.8b concurrency checkpoint) pass the blocking proof gate.

### Dependency

Follows PR11.8f-b. Must land before PR11.8g so that value-type channel element
proofs do not inherit the traversal gap.

---

## PR11.8g: Value-Type Channel Elements

Finish the recovered `PR11.8` series by reconciling channels with the value-type
model: channels carry values, not ownership-bearing references.

### Scope

- Channel element types must be value types. The compiler now admits direct
  `string`, `string (N)`, and growable-array channel element types, plus
  definite tuples, records, and fixed arrays that transitively contain those
  value types.
- The compiler rejects channel declarations whose element type is
  reference-typed, directly or transitively.
- `send` copies the value into the channel buffer and `receive` copies it out.
  There is no ownership transfer, move semantics, or null-before-receive rule
  for channel elements.
- Diagnostics for rejected channel element types explain why the type is
  reference-typed and suggest flattening it to a value representation.
- Existing concurrency fixtures that rely on ownership transfer through channels
  must migrate to value-typed element forms.
- The prover no longer needs to reason about cross-task ownership transfer
  through channels.
- Channel direction constraints from `PR11.8b.1` remain valid and unchanged; they
  restrict which tasks may send or receive independently of element type.

### Deliverables

- Compile and runtime closure for the admitted value-only channel corpus,
  including direct `string` / growable and transitive composite channel
  elements.
- Blocking emitted `flow` / `prove` closure for the heap-backed channel-helper
  path is deferred to `PR11.8g.2`, where the runtime seam moves off the current
  `SPARK_Mode => Off` support layer.
- Updated concurrency docs, fixtures, and emitter rules that make value-only
  channel elements explicit before `PR11.9` freezes artifact contracts.

---

## PR11.8g.1: Emitted Proof-Corpus Expansion

Close the remaining `PS-018` gap between "named checkpoint fixtures prove" and
"all emitted proof-bearing Safe code proves" by widening the blocking proof
corpus after PR11.8g lands.

### Scope

- Expand `scripts/run_proofs.py` beyond the current checkpoint-only manifests
  so accepted emitted fixtures outside the frozen PR10 representatives and the
  named PR11.3a / PR11.8a / PR11.8b / PR11.8e / PR11.8f checkpoints are either:
  - absorbed into blocking proof manifests, or
  - explicitly excluded with a named reason tracked outside direct emitted Ada
    proof.
- Absorb any currently emitted numeric fixtures and regressions that still sit
  outside the named checkpoints. If a numeric form is admitted and emitted in
  the live compiler, it belongs in the blocking proof corpus by the end of this
  milestone.
- Add a new blocking `PR11.8g.1` manifest in `scripts/run_proofs.py` rather
  than rewriting the historical checkpoint manifests. The historical manifests
  remain as frozen milestone checkpoints; the new manifest is the wider
  post-PR11.8g emitted-proof expansion set.
- Shrink or remove the "Other currently emitted sequential fixtures outside the
  PR10 corpus" and "Other currently emitted concurrency fixtures outside the
  PR10 corpus" uncovered rows in
  `docs/emitted_output_verification_matrix.md`.
- Remove the residual emitter body-only `Skip_Proof` fallback for recursive
  helper patterns. If a pattern remains admitted and emitted by the live
  compiler, it must either:
  - prove under the blocking manifests, or
  - be excluded from emission/admission with an explicit tracked reason.
- Keep the already external proof-boundary items external:
  - `PS-007` source-level `select ... or delay ...` semantics
  - `PS-019` I/O seam wrapper obligations
  - `PS-031` Jorvik/Ravenscar runtime scheduling, locking, and timing
    obligations
- Do not add new Safe syntax or change AST / typed / MIR / safei versions in
  this milestone. This is coverage expansion, not language work.

### Deliverables

- A broader blocking proof corpus that covers the admitted emitted proof-bearing
  surface, not just the current named checkpoint subsets, with a dedicated
  blocking `PR11.8g.1` manifest.
- Updated `docs/emitted_output_verification_matrix.md` so any remaining
  uncovered emitted-fixture categories are narrow, named, and intentional
  rather than catch-all rows. The live residual categories after PR11.8g.1 are:
  - heap-backed channel helper proof closure (`PR11.8g.2`)
  - heap-backed runtime-backed string/growable helper closure (`PR11.8g.2`)
  - I/O seam wrapper obligations (`PR11.8g.2`)
  - source/runtime concurrency semantics (`PR11.8g.3`)
  - any still-unproved fixed-width binary outliers, tracked explicitly in the
    verification matrix instead of as a generic “other emitted fixtures” bucket
- No residual compiler-emitted body-only `Skip_Proof` fallback for admitted
  emitted patterns.
- A numeric-proof story where the currently emitted numeric subset is either
  proved under the live manifests or explicitly excluded from emission.
- A proof story solid enough for `PR11.8h` to expose as a user-facing
  `safe prove` command without overstating what is proved.

### Dependency

Follows PR11.8g. Must land before PR11.8h so the CLI surface sits on top of a
broader emitted-proof corpus rather than checkpoint-only coverage.

---

## PR11.8g.2: Proofable Runtime and I/O Seam Consolidation

Remove the remaining emitted `SPARK_Mode => Off` debt and consolidate all I/O
through one proof-bounded standard-library seam before `safe prove` becomes a
public contract.

### Scope

- Eliminate all compiler-emitted `pragma SPARK_Mode (Off)` / `with SPARK_Mode => Off`
  from generated packages and helpers.
- Close blocking emitted `flow` / `prove` for the heap-backed value-channel
  element paths admitted in `PR11.8g`, including direct string/growable
  channels and transitive composite helper paths.
- Replace the current per-unit `<unit>_safe_io` wrapper generation with one
  standard-library package that owns the I/O seam for the language surface.
- Move generated helper/runtime logic that still depends on unproved bodies
  onto one of two paths:
  - fully SPARK-visible generated code that proves as emitted, or
  - a standard-library package with a proved SPARK-facing contract and a single,
    named seam boundary.
- Make `run_proofs.py` and the emitted verification matrix treat those support
  units as part of the normal proved surface rather than as excluded wrappers.
- Keep this milestone emitter/runtime/library-focused only. No Safe syntax or
  artifact-version changes.

### Deliverables

- No emitted `SPARK_Mode => Off` remains in compiler output for the admitted
  surface.
- Heap-backed channel element proof closure is green and blocking for the
  admitted `PR11.8g` value-channel surface, rather than remaining an incidental
  side effect of runtime seam cleanup.
- A single standard-library I/O seam package replaces per-unit generated I/O
  wrappers.
- Repo-generated build/proof helper projects include emitted sources and the
  shared stdlib source dir in one flat project; `safe_stdlib.gpr` remains a
  manual integration artifact rather than the default validation shape.
- The emitted proof story no longer depends on excluding wrapper/helper bodies
  from proof.

### Dependency

Follows PR11.8g.1. Must land before PR11.8g.3 and PR11.8h.

---

## PR11.8g.3: Jorvik-Backed Concurrency Semantics Closure

Close the remaining concurrency-proof boundary by aligning the admitted source
semantics with evidence that can be justified against the Jorvik/Ravenscar
runtime model.

### Scope

- Reconcile the admitted Safe concurrency subset with the actual guarantees we
  can rely on from Jorvik/Ravenscar, instead of treating that runtime evidence
  as an external post-v1.0 caveat.
- Close the current gap between proved emitted dispatcher/channel lowering and the
  intended source-level concurrency story for the admitted subset.
- Resolve `PS-007` and `PS-031` for the shipped concurrency surface:
  - source-level `select ... or delay ...` semantics
  - runtime scheduling, locking, and timing obligations used by channels/tasks
- Add one blocking STM32F4/Jorvik Renode evidence lane so the admitted
  concurrency story does not depend on local-only tooling.
- Refile any broader fairness, latency, or multi-target runtime aspirations as
  new residual scope items instead of leaving `PS-007` / `PS-031` straddling
  admitted and non-admitted behavior.
- Keep the dependency explicit: concurrency claims beyond the Jorvik-backed
  subset remain out of the admitted surface rather than silently trusted.

### Deliverables

- A documented, bounded concurrency semantics story that is justified by the
  Jorvik/Ravenscar runtime model for the admitted subset.
- A blocking embedded evidence lane (`scripts/run_embedded_smoke.py --target
  stm32f4 --suite concurrency`) wired into CI for the admitted subset.
- Updated proof/docs language so emitted concurrency code is no longer carried
  with open `PS-007` / `PS-031` caveats for the admitted forms.
- New residual scope items only for broader-than-admitted concurrency/runtime
  aspirations, not for the shipped subset itself.
- A proof-verification basis strong enough for `safe prove` to report the
  emitted concurrency subset as fully proved.

### Dependency

Follows PR11.8g.2. Must land before PR11.8h.

---

## PR11.8g.4: Shared Runtime Generic Contract Soundness Closure

Close the remaining shared-runtime contract debt exposed by `PR11.8g.2` before
`safe prove` and the PR11.9 artifact freeze turn those stdlib proof contracts
into a long-lived public assurance boundary.

Historical note: this milestone is closed on the `PR11.8g.4` branch by the
weak-base/strong-instance split recorded in
[`docs/pr118g4-proof-journal.md`](pr118g4-proof-journal.md).

### Scope

- Redesign the shared clone-based runtime contracts so they do not overclaim
  semantic equality facts that are not guaranteed by their generic formals.
- Start with the currently exposed `Safe_Array_RT` seam:
  - `From_Array`
  - `Element`
  - `Clone`
  - any related helper contracts that currently rely on `Clone_Element`
    preserving ordinary `=`
- Replace the current “generic contract is stronger than the generic semantics
  justify” shape with one of the following explicit designs:
  - an instance-provided semantic equality / preservation relation, or
  - a weaker generic base contract plus stronger instance-local wrappers where
    the stronger facts are actually justified
- Keep the current `PR11.8g.2` proof corpus green while doing this, especially
  the `fixed_to_growable` and heap-backed runtime fixtures that currently rely
  on element-level facts from `Safe_Array_RT.From_Array`.
- Update emitted/runtime/docs language so the shared stdlib proof story is
  honest at both the generic and instantiated levels.

### Deliverables

- No shared-runtime generic contract relies on an unstated assumption that a
  clone helper preserves ordinary Ada `=`.
- The current emitted proof corpus remains green after the redesign.
- The emitted verification matrix, roadmap, and shared-runtime notes all state
  the resulting contract boundary without overclaiming generic soundness.
- `safe prove` and later artifact-freeze work sit on top of a shared-runtime
  contract surface that is sound in the generic sense, not only in today's
  useful instantiations.

### Resolution

- `Safe_Array_RT` is now the weak generic base runtime:
  - `From_Array` preserves result length only
  - `Clone` / `Copy` preserve length only
- Stronger element-preservation facts are restored only on the
  identity-preserving path:
  - `Safe_Array_Identity_Ops`
  - `Safe_Array_Identity_RT`
- The emitter selects that stronger path only for growable arrays whose
  component type has no recursive heap value type.
- Validation on the closing branch:
  - `436 passed, 0 failed`
  - `18 passed, 0 failed`
  - `120 proved, 0 failed`

### Dependency

Follows PR11.8g.2. May interleave with PR11.8g.3. Must land before PR11.8h and
PR11.9.

---

## PR11.8h: `safe prove` CLI Command

Give developers a single command to answer "is my emitted Ada fully proved?"
without requiring knowledge of GNATprove flags, proof manifests, or runner
scripts.

### Scope

- Add `safe prove` as a first-class subcommand of `scripts/safe_cli.py`.
- `safe prove` compiles the Safe source, emits Ada, then runs GNATprove at
  silver level against the emitted output and reports a clear pass/fail
  verdict.
- The exit code is 0 when all emitted Ada proves with zero unproved VCs and
  zero justified checks, non-zero otherwise.
- Output shows: fixture name, prove/flow result, VC counts, and a summary
  line. No GNATprove log noise unless `--verbose` is passed.
- `safe prove` uses the same proof switches and timeout budget as
  `scripts/run_proofs.py` so results are reproducible between the CLI and CI.
- `safe build` remains the fast compilation path and does not invoke GNATprove.
  `safe prove` is opt-in for when developers want proof assurance on the
  current source.
- For multi-file packages with imported interfaces, `safe prove` proves the
  client package against the provider's `.safei.json` contract, the same way
  `run_proofs.py` does.

### Deliverables

- `safe prove <file.safe>` works for a single Safe source file.
- `safe prove` with no arguments proves all files in the current directory
  that have emitted proof-bearing output.
- Clear human-readable output: per-fixture pass/fail, overall summary with
  proved/unproved/justified counts, and a final one-line verdict.
- `--verbose` flag for full GNATprove output when debugging a proof failure.
- Documentation in `docs/tutorial.md` and `docs/safec_end_to_end_cli_tutorial.md`
  showing the `safe prove` workflow.

### Dependency

Follows PR11.8g.3 and PR11.8g.4.

---

## PR11.8i: User-Defined Enumerations

Add user-defined enumeration types to the Safe source surface. This is the
single biggest expressiveness gap after the PR11.8 value-type series: every
domain that needs a named finite set currently encodes it as a subtype of
integer, losing the type safety Safe is supposed to provide.

### Scope

- `type color is (red, green, blue)` declares a discrete enumeration type.
- Enumeration values are first-class: they can be used in `case` scrutinees
  and choices, equality/inequality comparisons, record fields, array index
  types, function parameters, and tuple elements.
- Ordering on enumeration values follows declaration order.
- `.first` and `.last` attributes return the first and last enumerators.
- Emitted Ada uses a direct Ada enumeration type. GNATprove handles
  enumeration proofs natively.
- Enumeration types are value types (copy on assignment, no ownership).
- Enumeration types are discrete and can be used as discriminants, unlike
  strings.

### Deliverables

- Parser, resolver, MIR, and emitter support for enumeration type
  declarations and enumeration literal expressions.
- Positive fixtures for enumeration declarations, case dispatch, ordering,
  field/parameter/index use, and proof.
- Negative fixtures for duplicate enumerators, non-enumeration uses where
  discrete types are required, and mixed-type comparisons.
- Tutorial and spec updates.

### Dependency

Follows PR11.8h.

---

## PR11.8i.1: Full Emitted Proof-Corpus Closure

Run the second emitted-proof expansion pass after shipped `PR11.8g.1`,
closing the remaining admitted-but-unproved emitted fixtures and replacing the
last implicit coverage bucket with one shared blocking inventory.

After `PR11.8g.1` widened the proof corpus once and `PR11.8g.2` / `PR11.8g.4`
closed the shared runtime/channel seams, 42 admitted fixtures in
`tests/positive/`, `tests/build/`, and `tests/concurrency/` still sat outside
any blocking proof manifest. `PR11.8i.1` completes that second expansion pass:
proof inventory ownership now lives in `scripts/_lib/proof_inventory.py`, both
`run_proofs.py` and `run_tests.py` enforce exhaustive coverage, and the full
blocking emitted-proof lane is green again.

### Scope

- **Shared proof inventory**: define one authoritative emitted-proof manifest
  and one explicit exclusion inventory in `scripts/_lib/proof_inventory.py`,
  then import that inventory from both `run_proofs.py` and `run_tests.py`.
- **No unnamed bucket**: make the test suite fail if any `.safe` fixture under
  `tests/positive/`, `tests/build/`, or `tests/concurrency/` is in neither the
  blocking manifest nor the explicit exclusion list.
- **Second expansion pass**: absorb the remaining admitted print, enum,
  binary, runtime-backed string/growable, mutual-family, and build fixtures
  into the blocking proof manifest.
- **Sequential channel debt closure**: re-emit sequential-only single-slot
  string/growable channels as record-backed channels with explicit
  `Pre => not Full` / `Pre => Full` contracts, removing the sequential
  receive-side `pragma Assume` from the emitted Ada.

### Deliverables

- The in-scope emitted proof inventory is exhaustive: all `161` admitted
  fixtures under the three covered roots are named in the shared inventory.
- `157` fixtures are blocking members of `EMITTED_PROOF_FIXTURES`.
- Only `4` fixtures remain in `EMITTED_PROOF_EXCLUSIONS`:
  - `tests/concurrency/channel_access_type.safe`
  - `tests/concurrency/select_ownership_binding.safe`
  - `tests/concurrency/try_send_ownership.safe`
  - `tests/build/pr118c2_root_with_clause.safe`
- The first three exclusions remain spec-excluded by value-only channel
  legality; `pr118c2_root_with_clause.safe` remains an intentional tooling
  reject fixture with a missing dependency interface and is therefore not an
  admitted emitted-proof target.
- The sequential channel receive-side `pragma Assume` is eliminated.

### Dependency

Follows PR11.8i. Must land before PR11.8j so that incremental build operates
on a fully inventoried emitted proof surface rather than a partial one.

---

## PR11.8j: Incremental Build for Multi-File Projects

The repo-local `safe` CLI now supports incremental root-file builds and proofs
for local multi-file projects.

### Delivered

- Shared per-project cache under `PROJECT/.safe-build/` for emitted Ada,
  interfaces, and incremental state.
- `safe build <root.safe>` and `safe run <root.safe>` now accept local imported
  roots with leading `with` clauses when sibling dependency sources are
  present.
- `safe prove [file.safe]` reuses the same shared cache and skips unchanged
  reproves.
- `safe build --clean <root.safe>` clears the shared project cache plus the
  selected root's `obj/<stem>` workdirs before rebuilding.
- Dependency invalidation is keyed off source hashes and consumed dependency
  interface hashes; imported-interface changes re-emit dependent clients.
- The model remains root-file based, not workspace mode.
- `safe deploy` remains out of scope and still rejects imported roots.

### Dependency

Follows PR11.8i.1 and lands before PR11.9 so that the contract freeze applies
to the incremental root-file build system developers now use day to day.

---

## PR11.8k: Structured Error Handling and Result Propagation

Safe now has first-class sugar for the existing fallible tuple convention, so
fallible operations compose without nested `if result.ok` blocks.

### Delivered

- `try <expr>` is admitted only for expressions of type `(result, T)`.
- `try` may appear in executable expression positions inside functions that
  themselves return `(result, U)`.
- On success, `try` yields the unwrapped `T`; on failure, it returns early from
  the enclosing function with the original `result` value plus the default `U`.
- `match <expr>` is admitted as a statement with exactly two arms, in either
  order:
  - `when ok (value)`
  - `when fail (err)`
- `match` works on both stable names and non-stable scrutinees by lowering
  through a compiler-generated temporary when needed.
- The admitted carrier remains the existing `(result, T)` tuple surface.
  `try` and `match` are parser/resolver sugar only; MIR and emitted Ada still
  see ordinary tuple access, `if`, declarations, and returns.
- Multiple `try` expressions in one statement preserve left-to-right source
  evaluation order by hoisting synthetic preludes in argument order.
- `try` is intentionally rejected in the right operand of `and then` / `or else`
  in this milestone; that form needs branch-local lowering instead of a simple
  statement-prefix prelude.

### Deliverables

- Parser, resolver, AST emission, and Ada emission support for `try` and
  statement-form `match`.
- Positive fixtures for `try` propagation chains, `match` on stable and
  non-stable scrutinees, and left-to-right `try` argument ordering.
- Negative fixtures for non-`(result, T)` carriers, non-executable `try`,
  and malformed `match` arm sets.
- A build/proof fixture showing `try` propagation remains fully provable under
  the current emitted-Ada GNATprove policy.

### Dependency

Follows PR11.8j. Must land before PR11.9 so that the standard library
design in PR11.10 can use the error model from day one.

---

## PR11.9: Artifact Contract Stabilization

Machine-interface stability for ecosystem consumers.

### Scope

- Compatibility policy for `diagnostics-v0`, `typed-v4`, `safei-v3`, and `mir-v4`.
- Documented bump rules: what changes require a version increment, what changes
  are additive-only, what changes are breaking.
- Resolves PS-021 (TBD-08): stabilize and document interchange-format policy.
- Add `--target-bits 32|64` flag to `safe build`, `safe run`, `safe prove`,
  and to `safec ast` / `safec check` / `safec emit`. Safe source remains
  target-independent — no `integer_32` vs `integer_64` in source.
- `typed-v4`, `mir-v4`, and `safei-v3` now require top-level
  `target_bits: 32 | 64`.
- Shared `.safe-build/` state and root build/prove workdirs are partitioned by
  target width so `32`-bit and `64`-bit artifacts coexist cleanly.
- The normative contract source is [`artifact_contract.md`](./artifact_contract.md).

### Numeric Boundary

- Default target width is `64`.
- Builtin `integer` range becomes `-(2**31) .. 2**31 - 1` for `32` and the
  current `Long_Long_Integer` range for `64`.
- Emitted arithmetic stays on the existing `Safe_Runtime.Wide_Integer` model in
  this milestone. `target_bits` changes builtin integer bounds and emitted
  narrowing/range checks, not the intermediate arithmetic runtime model.

### Significance

This is the "tooling-ready contract freeze." After this milestone, external
tools can build against stable interfaces with documented compatibility
guarantees. The diagnostics LSP shim from PR11.1, for instance, can move from
"explicitly disposable" to "stable interface consumer."

---

## PR11.9a: Aggregated Dispatcher Select

Replace the current polling-based `select ... or delay` lowering with a
single aggregated dispatcher protected object per select site, eliminating
polling entirely.

Ada does not provide a native construct for multiplexing entry calls across
multiple protected objects. The current polling loop exists because of this
language gap. The aggregated dispatcher solves it by combining all channel
readiness state into one protected object with one entry whose barrier
opens when any arm is ready.

### Scope

- For each `select` referencing N channels, emit a single dispatcher
  protected object. The selecting task makes one blocking entry call and
  blocks on the barrier with zero polling.
- The admitted `PR11.9a` subset is intentionally narrower than the full
  source surface:
  - select channel arms must target same-unit, non-public channels
  - select statements are emitted only from unit-scope statements and direct
    task bodies
  - selects on imported/public channels and selects inside subprogram bodies
    remain temporary resolver rejects in this milestone
- Each referenced channel gains a generated forwarding procedure called by the
  emitted Ada `Send` / `Try_Send` paths to notify the dispatcher.
- The `or delay` arm maps to one timed wait on the single dispatcher entry,
  rather than the old fixed-quantum polling loop.
- Channel-arm dequeue still uses the existing emitted Ada `Try_Receive` path;
  standalone Safe `try_receive` statements remain unchanged.

### Proof impact

- Eliminates assumptions D-01 (polling conformance) and T-01 (deadline
  faithfulness)
- The dispatcher is a single protected object with one entry — fully
  Jorvik-compliant
- GNATprove proves barrier conditions and protected-body correctness
- PS-035 retired or narrowed for the admitted subset

### Dependency

Follows PR11.9.

---

## PR11.9b: Fair Select with Round-Robin Rotation

Make plain `select` fair by default by rotating the starting arm after each
successful channel-arm dispatch.

### Scope

- No syntax changes. There is no `fair select` qualifier and no
  priority-ordered escape hatch in this milestone.
- Maintain a per-select `Next_Arm` index that rotates after each
  successful channel-arm dispatch, starting from `Next_Arm` and wrapping
  modulo the channel-arm count.
- Plain `select` now probes channel arms exactly once in circular order
  starting at `Next_Arm`.
- After a successful channel-arm receive, `Next_Arm` advances to the
  successor of the winning arm.
- Delay arms remain fallback-only and do not participate in the rotation.
- The admitted surface stays the same as `PR11.9a`:
  - same-unit, non-public channels only
  - unit-scope statements and direct task bodies only
- Fairness property (each arm eventually selected if its channel is
  non-empty) is an informative behavioral claim, not a formal proof
  obligation

### Proof impact

- Rotation index bounded by static arm count; GNATprove proves range
- No new `pragma Assume` or proof suppressions
- The dispatcher latch, wakeup mechanism, and absolute-deadline delay path
  from `PR11.9a` remain in place; only winner selection changes.

### Dependency

Follows PR11.9a.

---

## PR11.9c: FIFO Ordering Ghost Model

Extend the companion ghost model to prove FIFO ordering of channel
elements, eliminating assumption B-02.

### Scope

- Add an ordered logical FIFO prefix to `Channel_State`
- Prove `After_Append` and `After_Remove` ghost transitions:
  - Append: new tail element equals sent value; prior elements unchanged
  - Remove: returned element equals old head; remaining elements shift
- Tie `template_channel_fifo` to that ordered model through a concrete
  circular-buffer refinement proof
- B-02 becomes a proved property of the ghost model
- A-04 (channel serialization) remains but FIFO is no longer part of its
  trusted surface

### Proof impact

- Eliminates assumption B-02
- No emitter or runtime changes — companion-model-only

### Dependency

May interleave with PR11.9a/PR11.9b. Companion-layer work.

---

## PR11.9d: Nonblocking Send Discipline

**Locked decision: Option B (prohibit blocking send).**

Remove the blocking two-argument `send` from admitted source. The shipped
send form is `send ch, value, success` with explicit full-channel handling.
Tasks can only block on `receive`.

### Why

A blocking send on a full bounded channel with no concurrent receiver is
already a latent deadlock. Option B turns that latent hang into a compile
error: the programmer must handle the full-channel case. This is strictly
safer.

This milestone does **not** add a real receive-only deadlock analyzer.
It narrows the admitted surface and defers any graph-based deadlock
analysis to later work.

### Scope

- `send ch, value;` becomes a compile error. The compiler rejects it with
  a diagnostic directing the programmer to use `send ch, value, success;`.
- `send ch, value, success` is the only admitted send form. The
  programmer must handle the `not success` case.
- `try_send ch, value, success` is rejected with a targeted rename
  diagnostic that directs the programmer to `send ch, value, success`.
- Blocking `receive ch, target` stays. A task waiting for data cannot
  deadlock by itself.
- `try_receive ch, target, success` stays unchanged.
- Unit-scope elaboration operations on imported public channels remain
  rejected until the cross-package elaboration path can be proved by
  construction.
- `select` arms stay receive-only (already the case).
- The standard library (PR11.10) is designed within this constraint from
  day one — no library pattern depends on blocking send.

### Migration

Every existing `try_send ch, value, ok` becomes `send ch, value, ok`, and
every existing blocking `send ch, value` becomes `send ch, value, ok`
with an explicit failure path. The migration is mechanical. The intended
Safe idiom uses PR11.8k's `try` propagation:

```safe
function produce returns result of integer
   send data_ch, value, ok
   if not ok
      return fail ("channel full")
   return ok (0)
```

### Proof impact

- Zero effect on Bronze or Silver — this is a frontend legality rule
  that narrows the accepted program space
- Partially resolves TBD-09 from the spec register

### Deliverables

- Frontend rejection of legacy two-argument `send`
- Frontend rejection of legacy `try_send`
- Migration of all existing channel fixtures to three-argument `send`
- Updated spec §4.4, tutorial, and concurrency contract documentation
- Negative fixtures for legacy `send` / `try_send` rejection

### Dependency

Follows PR11.9b. Must land before PR11.10 so the standard library
design respects the nonblocking-send discipline from day one.

---

## PR11.10: Built-In Parameterized Containers

Ship the standard container types that eliminate the need for user-defined
self-referential types in ordinary Safe programs.

### Scope

- The language ships built-in parameterized container types with compiler-
  driven instantiation: `list of T`, `map of (K, V)`, and `optional T`.
- Container types are value types: assignment copies, scope exit frees, no
  ownership visible to the programmer.
- `list of T` provides a growable ordered sequence with `.length`, indexing,
  slicing, concatenation with `&`, iteration, `append(items, value)`, and
  `pop_last(items)`.
- `map of (K, V)` provides key-value lookup with insertion, membership test,
  and iteration.
- `optional T` provides a present-or-absent value with `.present` and `.value`
  access; replaces `null` for value-typed optionality.
- Container element types must be value types. Reference-typed elements are
  rejected.
- The compiler instantiates each `list of T` / `map of (K, V)` /
  `optional T` use site into a monomorphic concrete type. No runtime generics.
- The `list of T` syntax is sugar over the existing growable-array
  specialization pipeline — the programmer writes `list of integer` and the
  compiler resolves it to the same monomorphic internal type as `array of
  integer`, without requiring user-written generic instantiation.
- This milestone also owns the follow-on expansion of `mut` alias reasoning
  beyond PR11.8e.2 record fields to statically disjoint indexed/container
  element paths, because those paths depend on the built-in container identity
  model.

### Standard Library Architecture

- The standard library is implemented in Ada/SPARK with a Safe-visible
  interface. The Ada implementation uses the full Ada language internally
  (access types, controlled types, generics). The Safe interface hides all
  implementation detail behind value-type semantics.
- The SPARK proof layer on the Ada implementation verifies key properties:
  no buffer overflow, no null dereference, no use-after-free. This is
  optional but valuable — a formally verified standard library extends
  Safe's guarantees through the library, not just around it.
- Ada's controlled types (`Adjust` / `Finalize`) provide the copy-on-
  assignment and free-on-scope-exit semantics. This is the one place where
  the implementation crosses the SPARK boundary (SPARK does not support
  `Ada.Finalization`), handled by a thin unproved wrapper around a SPARK-
  proved core.

### Rationale

After this milestone, the standard container types eliminate the primary
use case for user-defined self-referential types. The programmer never
encounters reference types, move semantics, or ownership in ordinary Safe
code.

### Phasing

PR11.10 lands as four sub-milestones:

- **PR11.10a** — `optional T` (validates the type-constructor pipeline)
- **PR11.10b** — `list of T` (growable ordered sequence)
- **PR11.10c** — `map of (K, V)` (key-value lookup)
- **PR11.10d** — container proof closure and standard-library proof checkpoint

---

## PR11.10a: Built-In `optional T`

First container wedge. Introduces the `optional T` type constructor with
`some(expr)` and contextual `none` construction, `.present` and guarded
`.value` access.

### Scope

- `optional T` as a built-in type constructor, resolved to a synthetic
  discriminated record with `present : boolean` discriminant and a
  `value : T` variant field.
- `some(expr)` constructs a present optional; `none` constructs an absent
  one. `none` is context-typed from the expected `optional T` type;
  explicit ascription `(none as optional integer)` is available when
  context is insufficient.
- `.present` returns the discriminant boolean. `.value` is legal only when
  `.present = true` is established by a guard, reusing the existing
  discriminant-guard machinery.
- Admitted element types: scalars, enums, bounded strings, plain strings,
  growable arrays, fixed arrays, records, and tuples — all value types.
  Inferred reference families are rejected.
- No typed/MIR/safei version bump. The synthetic specialization uses
  existing record/discriminant descriptors.

### Why this first

`optional T` is the smallest container that exercises the full
type-constructor pipeline end to end: parser, resolver, MIR, emitter,
proof, and interface contracts. If the pipeline has a problem, finding it
on the simplest container is better than finding it while also debugging
list or map semantics.

### Dependency

Follows PR11.9d.

---

## PR11.10b: Built-In `list of T`

Growable ordered sequence. This slice keeps the existing growable-array
runtime and exposes `list of T` as the user-facing alias surface with
list-specific builtins.

### Scope

- `list of T` as a built-in type constructor anywhere subtype indications are
  admitted.
- `list of T` is type-identical to the existing growable `array of T`
  specializations. `array of T` remains supported in this milestone.
- Construction: `[expr1, expr2, ...]` bracket literals (same syntax as the
  existing growable-array path, disambiguated by target type).
- Operations: `.length`, indexing `items(N)`, slicing `items(M to N)`,
  `for item of items` iteration, concatenation with `&`, plus the contextual
  builtins `append(items, value)` and `pop_last(items)`.
- `append(items, value)` mutates a writable list in place.
- `pop_last(items)` returns `none` on empty and `some(last)` on success,
  shortening the list in place.
- Value-type semantics: assignment copies, scope exit frees.
- Admitted element types: same as `optional T` — value types only.
- This slice also extends `mut` alias reasoning from record fields to
  statically singleton, provably disjoint indexed paths over fixed arrays and
  growable/list values. Non-static or overlapping indexed paths still reject
  conservatively.

### Dependency

Follows PR11.10a.

---

## PR11.10c: Built-In `map of (K, V)`

Key-value lookup container. The third container type.

### Locked decisions

- **No brace literal** in this slice. Maps are constructed from an empty
  default value and populated via `set`. Brace literal syntax is deferred
  to avoid new lexer tokens and disambiguation work before real usage
  patterns are established.
- **Free builtins**, not selector methods: `contains(m, k)`, `get(m, k)`,
  `set(m, k, v)`, `remove(m, k)`. These become `m.contains(k)` etc.
  automatically when PR11.11a method syntax ships.
- **`remove` returns `optional V`**: `some(old_value)` if the key existed,
  `none` if not. Consistent with `pop_last` returning `optional T`.
- **Iteration order is unspecified**: `for entry of m` visits every entry
  exactly once; the order is deterministic for a given map state but is
  not guaranteed to be insertion order or key order.

### Scope

- `map of (K, V)` as a built-in type constructor.
- Construction: empty default initialization; populated via `set(m, k, v)`.
- Operations (free builtins):
  - `contains(m, k)` returns `boolean`
  - `get(m, k)` returns `optional V`
  - `set(m, k, v)` — statement-only; `m` must be writable
  - `remove(m, k)` returns `optional V` — expression-only; `m` must be writable
  - `.length` as a selector
  - `for entry of m` iteration yielding `(K, V)` tuples
- Key types must support equality (`==`). Admitted key types: scalars,
  enums, bounded strings, plain strings.
- Value types: same as `optional T` — value types only.
- Value-type semantics: assignment copies, scope exit frees.
- Internally, `map of (K, V)` reuses the growable-container pipeline as an
  unsorted sequence of synthetic `(K, V)` tuples.
- `set` does a linear scan and replaces an existing value in place when the
  key is present; otherwise it appends a new entry.
- `remove` does a linear scan and uses swap-with-last removal, so iteration
  order remains intentionally unspecified in this slice.

### Dependency

Follows PR11.10b.

---

## PR11.10d: Container Proof Closure

Standard-library proof checkpoint for the container surface.

### Scope

- Ratify the parent container checkpoint as the explicit union of the
  proof-backed `PR11.10a`, `PR11.10b`, and `PR11.10c` manifests.
- Treat those shipped fixtures as the authoritative proof-backed
  coverage for the admitted `optional`, `list`, and `map` surface,
  including the D27 obligations they already exercise.
- Allow named documented runtime-only exclusions when GNATprove still
  rejects an admitted witness for tool-specific reasons, but keep zero
  unnamed uncovered fixtures in the proof inventory.
- Update the proof runner, verification matrix, and proof inventory so
  the parent checkpoint and its named exclusions are stated explicitly.
- Leave the companion/template side unchanged unless a concrete
  container modeling gap is discovered while refreshing the checkpoint.

### Dependency

Follows PR11.10c. This is the checkpoint that closes the PR11.10 parent
milestone.

---

## PR11.11: Generics, Methods, and Structural Interfaces

Enable Go-style type-safe polymorphism: method syntax on record types,
structural interfaces as named operation contracts, and user-defined
parameterized types and functions. All three features monomorphize at
compile time — no dynamic dispatch, no runtime type checks, no vtables.

### Scope

#### Method syntax

- Functions may be declared with a receiver parameter:
  `function (self : my_type) do_thing` is sugar for
  `function do_thing (self : my_type)`.
- `mut` receivers are supported: `function (self : mut my_type) update`.
- Methods are resolved statically from the receiver type. No dynamic
  dispatch. GNATprove sees a normal subprogram with the receiver as
  the first parameter.
- Method call syntax: `value.do_thing()` desugars to `do_thing(value)`.

#### Structural interfaces

- An interface is a named set of function/method signatures:
  `type printable is interface; function (self : printable) to_string returns string`.
- A type satisfies an interface if it has matching functions — structural
  typing, not explicit `implements` declarations (Go-style).
- The compiler checks interface satisfaction at the use site (function
  parameter, generic constraint) and monomorphizes. No vtable, no
  dynamic dispatch, no runtime type check.
- GNATprove proves each concrete instantiation, not an abstract interface.
- Interfaces are value-typed constraints, not reference-typed base classes.
  No inheritance, no subclassing, no type extension.

#### User-defined generics

- Safe-native declarations use `of ...` syntax rather than Ada `generic`
  units:
  - `type pair of (l, r) is record ...`
  - `function identity of t (value : t) returns t`
  - `function max of t with t: orderable (a : t; b : t) returns t`
- Use sites spell explicit type arguments:
  - `identity of integer (value)`
  - `pair of (integer, string)`
- Public generic declarations cross package boundaries and may be
  instantiated in importing units.
- The compiler instantiates user-defined generics monomorphically at each
  use site — generic instantiation produces monomorphic Ada code at emit
  time rather than requiring Ada-side generic machinery.
- User-defined self-referential types are not admitted in the 1.0 source
  surface. The built-in containers from PR11.10 cover the standard data-
  structure use cases (`list of T`, `map of (K, V)`, `optional T`).
  User-defined generics enable domain-specific parameterized types and
  algorithms without reintroducing reference types or ownership complexity.

#### Composition model

- Composition via record fields, not inheritance. A record containing
  another record as a field is the standard reuse pattern.
- No type extension, no class hierarchies, no `is new` derivation in the
  user-facing language surface.
- Promoted field access (accessing an embedded record's fields directly
  through the outer record, Go-style) may be considered as syntactic
  sugar but is not required for this milestone.

### Proof impact

- Method syntax: zero impact. Methods desugar to ordinary functions before
  MIR. GNATprove never sees the method form.
- Structural interfaces: zero runtime impact. Satisfaction is checked at
  compile time and monomorphized. The proof surface is identical to
  non-generic code.
- Generics: each instantiation is proved independently as concrete
  monomorphic Ada. No generic-level proof obligations. Public contracts bump
  to `typed-v6` / `safei-v5`, while `mir-v4` remains unchanged because all
  specializations lower away before MIR.

### Rationale

This milestone gives Safe the Go-style object model: structs with methods,
interfaces as contracts, and composition over inheritance. Combined with
the built-in containers from PR11.10, Safe programs have both standard and
custom parameterized types — all value-typed, all statically dispatched,
all copy-on-assignment, all formally verifiable. No feature in this
milestone introduces dynamic dispatch, runtime type information, or
inheritance.

### Phasing

PR11.11 lands as three sub-milestones:

- **PR11.11a** — method syntax (receiver-parameter functions)
- **PR11.11b** — structural interfaces (Go-style operation contracts)
- **PR11.11c** — user-defined generics (parameterized types/functions)

---

## PR11.11a: Method Syntax

Add receiver-parameter function declarations and `value.method()` call
syntax as desugaring over ordinary functions.

### Scope

- Functions may be declared with a receiver parameter:
  `function (self : my_type) do_thing` is sugar for
  `function do_thing (self : my_type)`.
- `mut` receivers: `function (self : mut my_type) update`.
- Method call syntax is broad in this slice:
  `value.do_thing(args)` desugars to `do_thing(value, args)` for any
  visible compatible first-parameter function.
- Imported public functions participate too, so `value.method()` may resolve
  to `pkg.method(value)` across package boundaries.
- Existing container builtins gain selector-call sugar automatically:
  `items.append(v)`, `items.pop_last()`, `m.contains(k)`, `m.get(k)`,
  `m.set(k, v)`, and `m.remove(k)`.
- Methods are resolved statically from the receiver type. No dynamic
  dispatch.
- Methods desugar before MIR. GNATprove sees ordinary subprograms.
- No interface/generics/composition surface ships in `PR11.11a`; this is
  declaration sugar plus selector-call desugaring only.

### Proof impact

Zero. Methods desugar to ordinary functions before MIR.

### Dependency

Follows PR11.10d.

---

## PR11.11b: Structural Interfaces

Add Go-style named operation contracts as a compile-time-only structural
constraint surface. A type satisfies an interface if it has matching functions
or methods; there is no explicit `implements`.

### Scope

- Interface syntax is `type name is interface` with an indented suite of
  signature-only members.
- Every member must use receiver syntax, and the receiver type must be the
  enclosing interface name.
- Interface types are admitted only in parameter positions in `PR11.11b`.
- Same-unit/private interface-constrained subprogram bodies are specialized to
  ordinary concrete functions before MIR.
- Public interface declarations cross package boundaries now, and imported
  public concrete functions participate in structural satisfaction.
- Public interface-constrained subprogram bodies remain deferred to
  `PR11.11c`; `PR11.11b` rejects them with a subset diagnostic.
- No vtable, no dynamic dispatch, no runtime type check, no inheritance.

### Proof impact

Zero runtime impact. Satisfaction is checked at compile time and local/private
interface-constrained bodies are monomorphized before MIR, so the proof
surface remains ordinary concrete code.

### Dependency

Follows PR11.11a.

---

## PR11.11c: User-Defined Generics

Enable programmers to define parameterized types and functions with
value-type and optional interface constraints.

### Scope

- Parameterized types: `type stack of T is record ...`.
- Parameterized functions: `function max of T (a : T; b : T) returns T`.
- Constraints via interfaces: `function max of T with orderable (a : T; b : T)`.
- The compiler instantiates each use site monomorphically — no Ada-side
  generic machinery exposed.
- Value-type parameters only; no reference-type, access-type, or
  trait-bounded parameters beyond the interface constraints.
- Each instantiation is proved independently as concrete monomorphic Ada.

### Proof impact

No generic-level proof obligations. Each instantiation is proved
independently.

### Dependency

Follows PR11.11b.

---

## PR11.12: Shared Concurrent Records

Close the expressiveness gap between Safe's channel-only concurrency model
and Jorvik's protected-object query/update pattern by lowering admitted
`shared` declarations to compiler-generated protected wrappers.

### Scope

- Package-level `shared` roots lower to hidden protected wrappers rather
  than raw mutable package objects.
- The full family covers per-field access, whole-value snapshot/update,
  admitted heap-backed payloads, parameterized shared containers,
  cross-package shared declarations, exact ceiling analysis, and final
  proof closure.
- Shared state remains copy-based throughout the family. Reference-bearing
  payloads remain excluded.

### Rationale

The feature is intentionally split the same way as the container family:
first prove out the smallest same-unit wedge, then extend payload breadth,
then expose the stabilized surface across packages, then close the runtime
and proof story. That keeps each slice independently shippable and avoids
freezing an incomplete public shared-state contract.

### Phasing

- **PR11.12a** — shared record field-access wedge
- **PR11.12b** — whole-record snapshot/update and nested writes
- **PR11.12c** — heap-backed shared-record fields
- **PR11.12d** — parameterized shared container roots
- **PR11.12e** — public and imported shared declarations
- **PR11.12f** — exact shared ceiling analysis
- **PR11.12g** — shared-wrapper proof closure

---

## PR11.12a: Shared Record Field-Access Wedge

First shared-state slice. Adds same-unit package-level `shared` record
declarations lowered to protected wrappers with direct top-level field
read/write syntax.

### Scope

- Admit `shared name : record_type [= expr];` for package-level
  declarations only.
- Generate one protected getter and setter per top-level field and rewrite
  `cfg.field` / `cfg.field := expr` to those operations.
- Limit the admitted field subset to non-discriminated, non-heap,
  non-reference-bearing record payloads.
- Use the conservative wrapper ceiling `System.Any_Priority'Last`.
- Defer whole-record snapshot/update, nested writes, public/imported
  shared declarations, heap-backed fields, shared container roots, exact
  ceilings, and proof closure.

### Why this ordering

This is the smallest useful wedge: it proves the parser, legality,
normalization, and protected-wrapper emission path without freezing the
whole-record or cross-package contract too early.

### Implementation changes

- Parser/model: add `shared` as a package-level object-declaration flag
  and reject local, `public`, `constant`, and multi-name shared
  declarations.
- Resolver: admit only non-public non-discriminated record roots whose
  fields stay inside the narrow scalar/value subset.
- Lowering/emitter: track shared names in the package environment and
  emit one hidden protected wrapper with per-field getter/setter
  operations at `System.Any_Priority'Last`.
- Docs/proof: update the shared-state restrictions text and add emitted
  proof fixtures for per-field access.

### Test coverage

- Positive: implicit/default init, explicit initializer, task writes plus
  ordinary reads, bounded-string/optional-free scalar-style fields,
  chained reads through copied nested subrecords.
- Negative: `public shared`, local/body `shared`, multi-name or `constant`
  shared declarations, non-record or discriminated-record shared roots,
  bare shared-root expressions, whole-record assignment, nested writes,
  and use of `cfg.field` as a writable or `mut` actual.
- Proof: emitted-shape fixtures proving the generated protected wrapper
  and per-field accessors exist and replace raw mutable package state.

### Dependency

Follows PR11.11c.

---

## PR11.12b: Whole-Record Snapshot and Nested Writes

Complete the same-unit shared-record read/write surface by admitting
whole-record snapshot/update and using that machinery to support nested
field writes.

### Scope

- Admit bare shared-root reads as copy-returning snapshot expressions.
- Admit whole-record assignment `cfg := value` as an atomic protected
  update.
- Admit nested writes such as `cfg.nested.field := value` by lowering them
  through snapshot-update.
- Keep the `PR11.12a` field subset: non-heap, non-reference-bearing
  record payloads only.
- Defer heap-backed fields, shared container roots, public/imported
  shared declarations, exact ceilings, and final proof closure.

### Why this ordering

Whole-record snapshot/update is the missing same-unit substrate for
nested writes and later heap-backed copy-in/copy-out semantics, so it
should land before payload expansion or cross-package export.

### Implementation changes

- Resolver: stop rejecting bare shared-root reads and whole-record
  assignments while still rejecting transfer/move-style uses.
- Normalization: rewrite whole-record reads/writes and nested writes to
  hidden wrapper `Get_All` / `Set_All` operations before MIR.
- Emitter: extend the generated protected wrapper with whole-record
  snapshot and update operations.
- Docs/proof: revise the `PR11.12a` “field-only” wording and add emitted
  proof fixtures for whole-record copy/update lowering.

### Test coverage

- Positive: snapshot into a local record, whole-record update, nested
  write on a nested record field, passing a shared snapshot by value to an
  ordinary subprogram, explicit initializer followed by a full update.
- Negative: using a shared root as a `mut` actual, sending/passing the live
  shared root itself, unsupported nested writable paths, discriminated
  shared roots still rejected.
- Proof: emitted proof fixtures for `Get_All` / `Set_All` generation and
  nested-write desugaring.

### Dependency

Follows PR11.12a.

---

## PR11.12c: Heap-Backed Shared Record Fields

Extend same-unit shared records to heap-backed value payloads while
preserving copy-based protected-wrapper semantics.

### Scope

- Admit heap-backed shared-record fields for plain `string`, growable
  arrays, `list of T`, `map of (K, V)`, and `optional T` when `T` is also
  admitted.
- Extend per-field access, whole-record snapshot/update, and nested writes
  to those heap-backed payloads.
- Keep shared roots restricted to records in this slice.
- Defer shared container roots, public/imported shared declarations,
  exact ceilings, and final proof closure.

### Why this ordering

The whole-record machinery from `PR11.12b` is the prerequisite for
copy-safe nested heap updates. Heap-backed fields also need to land
before shared container roots, per the locked ordering.

### Implementation changes

- Resolver: broaden the admitted shared-field predicate from the narrow
  `PR11.12a` subset to the explicit heap-backed value subset while keeping
  reference-bearing composites rejected.
- Emitter/runtime: make protected getters/setters and whole-record
  operations clone, copy, and free heap-backed payloads exactly once.
- Lowering: keep direct field and whole-record rewrites from `PR11.12b`,
  and extend the dedicated protected nested-setter path so heap-backed
  leaf updates remain atomic without routing through outer snapshot/update.
- Docs/proof: document copy-based heap semantics and add emitted
  proof/runtime witnesses for clone/free safety.

### Test coverage

- Positive: shared `string` field read/write, shared `list`/`map` field
  update, shared growable-array field update, nested write through a
  heap-backed subrecord, whole-record snapshot/update of a heap-backed
  record.
- Negative: fields with reference-bearing composites, interfaces,
  channels, tasks, or other unsupported heap forms.
- Proof: emitted proof fixtures for setter/update clone/free behavior and
  preserved value semantics after snapshot/update.

### Dependency

Follows PR11.12b.

---

## PR11.12d: Parameterized Shared Container Roots

Reuse the shared-wrapper substrate for built-in parameterized container
roots such as lists, maps, and growable arrays.

### Scope

- Admit `shared` on built-in container roots:
  `list of T`, `map of (K, V)`, and growable `array of T`.
- Add whole-value snapshot/update for shared container roots.
- Forward the existing container operation surface through protected
  wrapper calls: `.length`, `append`, `pop_last`, `contains`, `get`,
  `set`, and `remove`.
- Keep iteration and direct indexed mutation on a live shared root
  deferred; callers may snapshot first for pure value operations.
- Defer public/imported shared declarations, exact ceilings, and final
  proof closure.

### Why this ordering

Shared container roots depend on the heap-safe copy/free wrapper logic
from `PR11.12c`. Landing them as a separate slice keeps “heap-backed
fields first, parameterized shared containers second.”

### Implementation changes

- Resolver: broaden shared-root admission from records to the built-in
  parameterized container subset.
- Normalization: rewrite shared-container builtin/method calls to hidden
  protected operations on the wrapper rather than direct container
  mutation.
- Emitter: generate protected APIs for shared container roots plus
  whole-value snapshot/update.
- Docs/proof: describe live shared-container operations versus snapshot
  value operations and add representative emitted-proof fixtures.

### Test coverage

- Positive: `shared values : list of integer`, `shared cache : map of
  (string, integer)`, shared growable-array `.length`/append/pop, and
  whole-value snapshot of a shared container root.
- Negative: unsupported shared root types, direct indexed mutation on a
  live shared root, unsupported live iteration, disallowed element/key/
  value payloads.
- Proof: emitted proof fixtures for protected forwarding of list/map
  operations and snapshot consistency.

### Dependency

Follows PR11.12c.

---

## PR11.12e: Public and Imported Shared Declarations

Export the completed shared read/write surface across package boundaries.

### Scope

- Admit `public shared` declarations for the shared root kinds stabilized
  by `PR11.12b` through `PR11.12d`.
- Import public shared declarations with the same client-visible field,
  whole-value, and shared-container operation surface as local shared
  roots.
- Keep the conservative ceiling model from `PR11.12a` through
  `PR11.12e`.
- Defer only exact ceiling analysis and final proof closure.

### Why this ordering

The export contract needs the full local read/write surface first, so
cross-package shared declarations must come after whole-record access,
heap-backed fields, and parameterized shared container roots.

### Implementation changes

- Parser/resolver: stop rejecting `public shared` and import shared
  declarations as first-class package items.
- Contract emission/import: extend the public interface artifacts with
  shared-root metadata, admitted operations, and any wrapper identity
  needed for client-side rewrites.
- Normalization: allow imported client code to rewrite shared reads,
  writes, snapshots, updates, and shared-container operations onto the
  imported contract.
- Docs/proof: update the language and artifact-contract docs to include
  public shared declarations.

### Test coverage

- Positive: provider/client field access, imported whole-record
  snapshot/update, imported nested write, imported shared list/map root
  operations, provider-private code using its own public shared state.
- Negative: malformed shared contracts, unsupported imported shared root
  kinds, illegal transfer or `mut` use of imported shared roots.
- Proof: emitted multi-unit fixtures proving imported shared rewrites use
  the same protected-wrapper semantics as local code.

### Dependency

Follows PR11.12d.

---

## PR11.12f: Exact Shared Ceiling Analysis

Replace the conservative wrapper ceiling with exact access-based ceiling
computation across local and imported shared declarations.

### Scope

- Compute each private closed-world shared wrapper ceiling from the
  actual set of accessing tasks/subprograms rather than
  `System.Any_Priority'Last`.
- Extend that analysis across imported/public shared declarations by
  exporting additive shared `required_ceiling` metadata while keeping
  public or otherwise open-ended shared roots conservative.
- Make no new source-surface changes.
- Defer only final proof closure.

### Why this ordering

Exact shared ceilings need the cross-package shared-declaration contract
from `PR11.12e`, so this is intentionally a later runtime/emission slice
rather than part of the initial surface wedge.

### Implementation changes

- Analysis: extend the existing channel-style access-summary machinery to
  track shared-root accesses and compute per-root shared ceilings.
- Contract layer: export/import additive `required_ceiling` metadata on
  public shared objects and reuse existing effect summaries for
  transitive shared access.
- Emitter: replace the fixed conservative priority with the computed
  exact ceiling on private closed-world shared wrappers, while retaining
  `System.Any_Priority'Last` for public/environment-open cases.
- Docs/proof: retire the blanket conservative-ceiling wording and add
  emitted checks for both exact and fallback protected priorities.

### Test coverage

- Positive: local exact-ceiling case, multi-task access case, imported
  shared contract case, and mixed channel/shared access case.
- Negative: missing or malformed shared `required_ceiling` metadata is
  rejected rather than silently defaulting to an unsafe value.
- Proof: emitted proof and shape checks that wrapper priorities match the
  analyzed ceiling for private shared roots and remain conservative for
  public/open-ended roots; embedded smoke should include at least one
  shared wrapper target.

### Dependency

Follows PR11.12e.

---

## PR11.12g: Shared Wrapper Proof Closure

Close the `PR11.12` family as a checkpoint and ledger milestone.

### Scope

- Add a parent `PR11.12` checkpoint manifest as the union of the
  proof-backed shared fixtures from `PR11.12a` through `PR11.12f`.
- Report that parent union in `run_proofs.py` as `PR11.12 checkpoint`
  while keeping the child `PR11.12a` through `PR11.12f` summaries intact.
- Refresh the verification matrix, roadmap, and restrictions/spec text so
  the shipped shared-wrapper surface is represented as one closed family.
- Allow named runtime-only exclusions only when they remain explicit and
  justified; keep zero unnamed uncovered shared fixtures and zero
  shared-specific exclusions unless a real unavoidable proof gap appears.
- Leave the companion/template side unchanged unless the shipped shared
  wrapper surface exposes a real repeated proof-model gap.

### Why this ordering

Proof closure only makes sense once the shared syntax, payload surface,
cross-package contract, and exact ceiling behavior are all stable. This
matches the `PR11.10d` parent-checkpoint model.

### Implementation changes

- Proof inventory/runner: add a parent `PR11.12` checkpoint summary over
  the shared-wrapper fixture family.
- Docs/ledgers: update the verification matrix and shared-state roadmap/
  restrictions text so the family is closed explicitly rather than left as
  an implicit post-feature proof debt.
- Companion/proof model: add at most one focused shared-wrapper template
  only if the fixture-only checkpoint exposes a real recurring gap.

### Test coverage

- Positive/proof checkpoint axes: same-unit field access, whole-record
  snapshot/update, heap-backed fields, shared container roots, imported
  shared declarations, and exact ceiling emission.
- Negative: zero unnamed uncovered shared fixtures under the proof
  inventory roots.
- Proof: `run_proofs.py` prints a dedicated `PR11.12` checkpoint summary;
  any retained runtime-only exclusion is named and justified.

### Dependency

Follows PR11.12f.

---

## PR11.15: String Interpolation

Add `f"..."` string interpolation syntax.

### Scope

- `f"count: {n}"` desugars to `"count: " & to_string(n)`.
- `to_string` is a standard interface method that scalar types, enums,
  strings, and optionals satisfy by default.
- User-defined types can satisfy `to_string` through the existing
  method/interface machinery from PR11.11a-b.
- Interpolation expressions must be printable (satisfy `to_string`).
  Complex expressions are allowed: `f"total: {a + b}"`.
- No format specifiers in the first slice (no `{n:04d}`). Formatting
  is post-v1.0 work.

### Proof impact

Zero. Pure desugaring to existing concatenation and `to_string` calls.

### Dependency

Follows PR11.22f (resolver cleanup). Moved earlier in the series
because it is pure syntactic sugar with zero proof impact.

---

## PR11.16: Nominal Type Aliases

Add distinct nominal types that prevent accidental mixing.

### Scope

- `type user_id is new integer (0 to 1000000)` creates a distinct type
  with the same representation as its parent but no implicit conversion.
- `user_id` and `integer` are incompatible in assignment, comparison,
  and parameter passing without an explicit conversion.
- Explicit conversion: `user_id (42)` and `integer (my_id)`.
- Nominal types inherit the parent's operations (arithmetic, comparison)
  but the result type is the nominal type, not the parent.
- Nominal types are value types with the same proof surface as their
  parent — range checks, overflow, and indexing all work identically.

### Proof impact

Zero new proof model. The nominal type has the same range and operations
as its parent. GNATprove proves the same VCs.

### Dependency

Follows PR11.15.

---

## PR11.14: Closures

Add value-capture-only first-class functions.

### Scope

- Anonymous function syntax: `fn (x : integer) returns integer => x + 1`
- Closures capture enclosing variables by value (copy at capture time),
  not by reference. No mutable upvalue captures.
- A closure is internally a record of captured values plus a function
  pointer. The function pointer is statically known at each use site
  through monomorphization via an interface constraint (e.g., a standard
  `callable` interface).
- Closure types are value types: copy on assignment, free on scope exit.
- No dynamic dispatch — every closure call site is monomorphized.
- Enables functional patterns: `items.filter(fn (x) => x > 0)`,
  `items.map(fn (x) => x * 2)`, callback parameters.

### Proof impact

Zero new proof model. The closure body is proved as an ordinary function.
Captured values are record fields with known types. The monomorphized
call is a concrete function call that GNATprove handles natively.

### Dependency

Follows PR11.16 (nominal type aliases). Deferred past the PR11.22c–e
emitter hygiene pass so the monomorphization implementation lands in a
clean, decomposed emitter rather than the current 19.7K-line monolith.

---

## PR11.17–PR11.21: Moved to PR14 Series

The following milestones were moved out of the PR11 series on 2026-04-06
to focus implementation effort on the highest-value features and codebase
hygiene before adding new language surface:

- **PR11.17 → PR14.1:** User-Defined Iteration Protocol
- **PR11.18 → PR14.2:** Nested Packages / Module Hierarchy
- **PR11.19 → PR14.3:** Async/Await via State-Machine Coroutines
- **PR11.20 → PR14.4:** Bounded User-Managed Allocation Pools
- **PR11.21 → PR14.5:** Compile-Time Derive

These items are deferred past all existing work (PR11, PR12, PR13).
See the PR14 section below for the preserved milestone definitions.

---

## PR11.13: User-Defined Sum Types

Add user-defined tagged unions with exhaustive `match` destructuring.
Lands as three sub-milestones.

### Phasing

- **PR11.13a** — Declaration and variant construction (pipeline wedge)
- **PR11.13b** — Exhaustive match destructuring with payload bindings
- **PR11.13c** — Cross-package export/import and proof closure

---

## PR11.13a: Sum Type Declaration and Construction

First sum-type wedge. Introduces the type declaration syntax and
positional variant constructors.

### Scope

- Admit sum type declarations:
  `type shape is circle (radius : integer) or rectangle (width : integer; height : integer)`
- Each variant has a name and zero or more named typed payload fields.
- Variant names are unique within the sum type.
- Payload field types must be admitted value types (same admission
  rules as record fields, optional payloads, and container elements).
- Positional variant constructors: `circle (5)` and
  `rectangle (3, 4)` produce sum-type values.
- Sum types are value types: copy on assignment, free on scope exit.
- Internally lowered to a discriminated record with a compiler-
  generated enum discriminant and variant parts, reusing existing
  discriminated-record infrastructure.
- No `match` destructuring in this slice — variant construction
  only. The value can be assigned, passed, returned, and compared
  using the existing whole-value equality surface.
- Same-unit only in this slice; public/imported deferred to PR11.13c.
- No typed/MIR/safei version bump.

### Why this first

This validates the type-declaration pipeline, the internal lowering
to discriminated records, and the construction/emission path. If the
pipeline has a problem, finding it on construction alone is simpler
than also debugging match destructuring.

### Proof impact

Zero. The lowered discriminated record uses existing proof machinery.

### Dependency

Follows PR11.12g.

---

## PR11.13b: Exhaustive Match on Sum Types

The payoff slice. Extends `match` from `(result, T)` tuples to
user-defined sum types with payload bindings.

### Scope

- Extend `match` to accept sum-type scrutinees:
  ```
  match value
     when circle (r)
        -- r : integer is bound here
     when rectangle (w, h)
        -- w : integer, h : integer are bound here
  ```
- Exhaustiveness: every variant must have exactly one arm. Missing
  variants and duplicate variants are rejected at compile time.
- Payload bindings are immutable locals scoped to the arm body.
- Zero-payload variants use bare `when variant_name` (no parentheses).
- `match` on sum types remains statement-only (same as PR11.8k
  `match` on results).
- The compiler desugars sum-type `match` to an `if`/`elsif` chain
  on the hidden enum discriminant with variant-field access in each
  arm, reusing the existing `match` lowering path from PR11.8k.
- Same-unit only in this slice.
- No typed/MIR/safei version bump.

### Proof impact

Zero. The desugared `if`/`elsif` chain is ordinary control flow.
Variant-field access uses the existing discriminant-guard machinery
that GNATprove already proves.

### Dependency

Follows PR11.13a.

---

## PR11.13c: Cross-Package Sum Types and Proof Closure

Close the PR11.13 parent milestone with public/imported sum types
and a proof checkpoint.

### Scope

- Admit `public type shape is circle (...) or rectangle (...)` for
  cross-package export.
- Export sum-type metadata (variant names, payload fields, internal
  discriminant identity) through safei contracts.
- Imported constructor expressions are package-qualified, such as
  `shapes.circle (5)` and `shapes.idle`.
- Imported sum `match` keeps bare `when variant` arms resolved by the
  scrutinee type, so imported sums do not inject bare constructor
  names into client scope.
- Imported sum types support the full construction + match surface
  in client units.
- Add PR11.13c checkpoint fixtures covering:
  - Local sum type construction and match
  - Cross-package imported sum type construction and match
  - Sum type with heap-backed payload fields (string, list)
  - Proof that the emitted discriminated record proves clean
- Update verification matrix and proof inventory.
- Artifact version bump if the safei contract requires new required
  fields for sum-type metadata; additive optional fields do not
  require a bump.

### Proof impact

Zero new proof model. Each fixture proves as an ordinary
discriminated-record program.

### Dependency

Follows PR11.13b. This is the checkpoint that closes the PR11.13
# PR11.22: Codebase Hygiene

Clean up accumulated technical debt, decompose oversized files, remove
vestigial code paths, and harden the codebase before the tooling series
begins. This is maintenance work, not feature work — no language surface
changes.

The audit identified these priorities from a comprehensive code scan:

- `safe_frontend-ada_emit.adb`: 19.7K lines, 477 functions, 11 functions
  over 200 lines (largest: `Render_Statements` at 3,194 lines)
- `safe_frontend-check_resolve.adb`: 13.8K lines, 282 functions
- `scripts/run_tests.py`: 3.2K lines absorbing every test category
- 14 abandoned local branches from shipped milestones
- CLAUDE.md stale (missing CLI commands, stdlib, proof inventory)
- Vestigial `Stmt_Try_Send` emitter paths (12 references)
- Channel emission triplication (protected/record-backed/ghost-model)
- Generic actual type validation gap (top-level-only, not deep)
- Shared stdlib body drift risk between `Safe_Array_RT` and
  `Safe_Array_Identity_RT`

---

## PR11.22a: Documentation and Configuration Refresh

Bring CLAUDE.md, repo documentation references, and developer guidance
up to date with the current toolchain state.

### Scope

- Update CLAUDE.md to reflect:
  - `safe build`, `safe run`, `safe prove`, `safe deploy` CLI commands
  - Incremental build system (`.safe-build/`)
  - Shared stdlib (`compiler_impl/stdlib/`)
  - Embedded evidence lane and Renode concurrency suite
  - Proof inventory (`scripts/_lib/proof_inventory.py`)
  - Roadmap file renamed to `docs/roadmap.md`
- Verify no broken internal anchor links in `docs/roadmap.md`
- Move `docs/pr118g2-proof-journal.md` to `docs/archive/` with a
  historical header
- Clean up `~/tmp/` working documents (backups, superseded inventories)

### Dependency

Follows PR11.13c. Zero risk — documentation only.

---

## PR11.22b: Branch Cleanup and Model Enum Hygiene

Delete abandoned local branches and audit the check model for vestigial
enum variants.

### Scope

- Delete 14+ stale local branches from shipped milestones (pr114, pr115,
  pr116, pr117, pr1161, pr1162, pr134, root-archive-cleanup,
  safe-wrapper-build-output, embedded-smoke-stm32f4, revert-pr117-*,
  pr-125)
- Delete stale remote branches that were merged but not cleaned up
- Audit `Stmt_Try_Send` in `safe_frontend-check_model.ads`:
  - Keep the enum variant for migration-diagnostic purposes (parser
    creates it, resolver rejects it with a helpful message)
  - Document the decision in a code comment

### Dependency

Follows PR11.22a. Zero risk — branch deletion and documentation.

---

## PR11.22c: Emitter Monster-Function Decomposition

Split the largest functions in `safe_frontend-ada_emit.adb` into
focused per-kind helpers.

### Scope

Priority targets (>500 lines each):

| Function | Lines | Split strategy |
|----------|-------|---------------|
| `Render_Statements` | 3,194 | Extract per-statement-kind procedures |
| `Emit` (top-level) | 1,071 | Split into type/channel/subprogram/init phases |
| `Render_Channel_Body` | 885 | Split heap/non-heap and protected/record paths |
| `Render_Expr` | 695 | Extract per-expression-kind helpers |
| `Render_Subprogram_Body` | 672 | Extract traversal lowering, variant detection, warning infrastructure |
| `Render_Type_Decl` | 512 | Split record/enum/array/access paths |

- Each split must preserve exact emitted-Ada output (diff the emitted
  output of every proof fixture before and after)
- No behavioral changes — pure structural refactoring

### Dependency

Follows PR11.22b. Medium effort, medium risk. Full `run_proofs.py`
required before and after.

---

## PR11.22d: Emitter Deduplication and Vestigial Code Removal

Remove dead code paths and factor shared patterns in the emitter.

### Scope

- Remove or `Raise_Internal` the vestigial `Stmt_Try_Send` emission
  paths (6 sites in `ada_emit.adb`) — the resolver already rejects
  `try_send`, so these paths are unreachable
- Audit and remove `pragma Unreferenced` sites that indicate dead
  helper functions with unused parameters (15 sites)
- Factor shared channel-emission helpers: the three channel models
  (protected concurrent, record-backed sequential, ghost-model scalar)
  share buffer management, index arithmetic, and element staging
  patterns that should be common helpers
- Consolidate redundant warning-suppression helpers (10+ pairs that
  differ only in reason strings)
- Unify type-name sanitization functions if redundant implementations
  exist

### Dependency

Follows PR11.22c. The function splits make deduplication easier to
identify and verify.

---

## PR11.22e: Emitter File Split

Decompose `safe_frontend-ada_emit.adb` (19.7K lines) into focused
domain modules.

### Scope

Split into approximately 5 child packages:

| File | Domain | Approximate content |
|------|--------|-------------------|
| `ada_emit-types.adb` | Type declaration emission | Record, enum, array, access, synthetic types |
| `ada_emit-channels.adb` | Channel and dispatcher emission | Protected/record/ghost channel specs and bodies |
| `ada_emit-statements.adb` | Statement emission | The per-kind helpers from PR11.22c |
| `ada_emit-expressions.adb` | Expression rendering | Per-expression-kind helpers |
| `ada_emit-proofs.adb` | Proof infrastructure | Warning suppression, static-fact emission, pragma helpers |

- The parent `ada_emit.adb` becomes a thin dispatcher that calls into
  child packages
- Ada child-package visibility rules mean the split is structurally
  enforced, not just organizational
- Same verification requirement: emitted Ada must be unchanged for
  every proof fixture

### Dependency

Follows PR11.22d. Large effort but mechanical — each child package
takes a well-defined subset of the existing function bodies.

---

## PR11.22f: Resolver Cleanup and Builtin Consolidation

Clean up the resolver's accumulated builtin-recognition sprawl and
close the generic actual type gap.

### Scope

- Fix the generic actual type validation gap: add deep reference-bearing
  check (`Contains_Channel_Reference_Subcomponent`) to
  `Is_Generic_Actual_Type_Allowed` (one-line fix identified during
  PR #201 review)
- Audit builtin recognition for `append`, `pop_last`, `contains`, `get`,
  `set`, `remove`, `some`, `none` — verify no duplicated lookup patterns
  and consistent precedence (user names win over builtins)
- Consolidate the resolver's dominant duplication patterns identified
  by mechanical clone analysis:
  - R-A: Extract a local `Desugar_Checked` helper to replace the
    repeated 12-argument Desugar+Normalize call sequences (~2,000
    lines recoverable)
  - R-B: Extract `Build_Shared_Setter_Call` for the duplicated
    shared-field write validation chain (~500 lines)
  - R-C: Consider bundling the resolver environment into a record to
    reduce the `Normalize_Statement_List` parameter signature
    (~200 lines; medium risk because it changes internal API)
  - R-D: Extract `Register_One_Imported_Type` for duplicated import
    registration (~150 lines)
  - R-E: Consolidate the repeated method/interface satisfaction checks
    where the same compatibility pattern is repeated over different
    target types (~150 lines; lower priority than R-A through R-D)
  - R-F: Finish the remaining sum-match arm constrained-name and
    payload-prefix dedup now that imported sum metadata is settled
    (~200 lines; smaller follow-on cleanup)
  - R-G: Extract `Validate_And_Contextualize_Value` for duplicated
    value validation chains (~200 lines)
- Consolidate `mir_bronze.adb` parameter-forwarding duplication:
  - B-A+B-B: Bundle the walk state into a record and thread it through
    `Walk_Expr` / `Walk_Statements` recursion (~1,200 lines recoverable;
    highest-duplication-ratio file at 56%)
  - B-C: Fold the remaining `Sanitize_Type_Name_Component` call-site
    cleanup onto `Safe_Frontend.Name_Utils` after the shared utility
    lands in PR11.22d
- Consolidate `check_lower.adb` assignment-construction duplication:
  - L-A: Extract `Build_Assignment_Op` for repeated assignment
    operation construction (~150 lines)
  - L-B: Reduce default-initializer boilerplate (~100 lines)
- Consolidate `check_emit.adb` public-subprogram iteration:
  - E-A: Extract `For_Each_Public_Subprogram` callback pattern
    (~80 lines)
- Unify the remaining `Sanitize_Type_Name_Component` copies that were
  migrated to `Safe_Frontend.Name_Utils` in PR11.22d but may still
  have call-site cleanup needed
- Remove dead `Stmt_Try_Send` normalization/lowering paths if any exist
  beyond the intentional rejection diagnostic
- Identify functions >200 lines and split by kind where beneficial

### Dependency

Follows PR11.22e. The emitter split reduces coupling so resolver changes
are lower risk.

---

## PR11.22g: Test Infrastructure Modularization

Split `scripts/run_tests.py` (3.2K lines) into focused modules.

### Scope

Split into:

| Module | Contents |
|--------|----------|
| `run_tests.py` | Main entry point and summary reporting only |
| `_lib/test_negative.py` | Negative fixture runner |
| `_lib/test_build.py` | Build/run fixture runner |
| `_lib/test_interface.py` | Interface pair runner |
| `_lib/test_emitted_shape.py` | Emitted-shape regression runner |
| `_lib/test_incremental.py` | Incremental build/prove regressions |
| `_lib/test_proof_coverage.py` | Proof inventory coverage gate |
| `_lib/test_fixtures.py` | Data declarations (case lists, expected outputs) |

- Test output format and exit codes must not change
- CI integration must not change — `python3 scripts/run_tests.py`
  remains the entry point

### Dependency

Follows PR11.22f. Medium effort, low risk.

---

## PR11.22h: Shared Stdlib Contract Audit

Verify contract completeness and body consistency across the shared
stdlib packages.

### Scope

- Verify every shared stdlib function spec has:
  - `Global => null` (or appropriate global annotation)
  - `Depends` where applicable
  - `Always_Terminates` on terminating procedures
  - Consistent length/element postconditions across `Safe_Array_RT`
    and `Safe_Array_Identity_RT`
- Check for body drift between `Safe_Array_RT` and
  `Safe_Array_Identity_RT` — both have `From_Array`, `Clone`, `Copy`,
  `Free`, `Element`, `Slice`, `Concat`, `Replace_Element` and the
  identity variant adds elementwise equality postconditions. Bug fixes
  in one must be mirrored in the other.
- Verify `Safe_String_RT` contract completeness
- Verify `Safe_Bounded_Strings` expression-function completions are
  consistent with their spec contracts

### Dependency

Follows PR11.22g. Safety-critical audit — medium effort, high value.

---

## PR11.22i: Emitter Boundary Audit and Support-Surface Inventory

Investigate the remaining architectural tax after the emitter split and
separate unavoidable Ada child-package ceremony from removable design
debt.

### Scope

- Audit the actual `with` dependencies between `Internal`, `Types`,
  `Expressions`, `Statements`, `Channels`, and `Proofs`:
  - remove any accidental maximal-envelope dependencies
  - document the intended acyclic graph in the child specs with short
    ownership/dependency headers
- Inventory `safe_frontend-ada_emit-internal.ads` exports and the child
  package entrypoints by consumer set:
  - parent-only
  - single-child
  - multi-child
- Identify helpers that can move down out of `Internal` into a narrower
  domain package without recreating dependency cycles
- Measure the remaining boilerplate introduced by the child-package
  split:
  - repeated `AI.*` rename slabs
  - repeated `with` clauses
  - child-spec exports that exist only to support the split
- Produce a concrete keep/trim inventory for `PR11.22j` rather than
  doing ad hoc cleanup

### Dependency

Follows PR11.22h. Investigation and boundary classification only — low
risk, no behavioral change.

---

## PR11.22j: Emitter Interface Narrowing and Boilerplate Reduction

Use the `PR11.22i` inventory to remove avoidable ceremony from the split
emitter without undoing the architectural gains.

### Scope

- Narrow `safe_frontend-ada_emit-internal.ads` to helpers that are truly
  shared across multiple emitter domains
- Move domain-local helpers down into `Types`, `Expressions`,
  `Statements`, `Channels`, or `Proofs` where the dependency graph
  allows it
- Remove child-package exports that are only consumed inside one domain
  and can become body-local again
- Reduce duplicated `AI.*` rename slabs and `with` lists in child
  bodies where the split introduced avoidable boilerplate
- Keep the package graph acyclic and preserve emitted Ada byte-for-byte
  across the snapshot corpus
- Explicitly accept the Ada child-package boilerplate that is
  structural, and remove only the ceremony that the audit shows is
  optional

### Dependency

Follows PR11.22i. Structural cleanup only — medium effort, medium risk.

---

## PR11.22k: Focused Emitter Domain Validation Lanes

Add fast, domain-focused validation helpers so emitter maintenance does
not always require paying for the full end-to-end suite during local
iteration.

### Scope

- Add focused emitter-domain validation helpers for:
  - `Types`
  - `Expressions`
  - `Statements`
  - `Channels`
  - `Proofs`
- Keep `python3 scripts/run_tests.py`, `python3 scripts/run_proofs.py`,
  and `python3 scripts/snapshot_emitted_ada.py` as the authoritative
  gates; the new helpers are confidence lanes, not replacements
- Define a minimal per-domain fixture map so contributors and AI agents
  know which lane to run first for a given change
- Ensure each validation lane reports the owned domain clearly and
  stays aligned with the child-package ownership introduced in
  `PR11.22e`
- Prefer simple wrappers over a new heavyweight test framework; the goal
  is iteration speed and orientation, not another generalized harness

### Dependency

Follows PR11.22j. Medium effort, low risk.

---

## PR11.23: Proof Diagnostic Mapping

Map GNATprove proof failures back to Safe source locations with
classified fix guidance, so users and AI agents receive actionable
Safe-native diagnostics instead of raw emitted-Ada error messages.

### Why now

With proof-on-build integrated, `safe build` rejects unproved code by
default. Users will see proof failures for the first time as build
errors. Without source mapping and fix guidance, those failures
reference emitted `.adb` files and GNATprove internals that Safe
programmers have no context for. This is the highest-friction point
in the AI-first workflow: the agent gets an error it cannot act on.

### Scope

**Source location mapping:**

- The emitter annotates emitted Ada with Safe source locations via
  line-mapping comments (`-- safe:file:line`) or a sidecar JSON map.
- The mapping must survive through GNATprove — the proof tool
  preserves source locations from the Ada it analyzes, so the
  annotations need only be present in the emitted `.adb`/`.ads`.
- The mapping covers: statements, expressions, declarations,
  subprogram boundaries, and loop headers — the sites where proof
  failures originate.

**Diagnostic classification catalog:**

A finite catalog of known proof failure patterns, each with:
- A GNATprove message pattern (regex or substring match)
- A Safe-native diagnostic message template
- A specific fix suggestion in Safe terms

Initial catalog entries (expand as real failures surface):

| GNATprove pattern | Safe diagnostic | Fix guidance |
|---|---|---|
| `range check might fail` | `value may exceed type range at conversion` | Use a wider type, add a guard (`if value >= lo and then value <= hi`), or use `for` instead of `while` |
| `overflow check might fail` | `arithmetic may overflow` | Use a wider accumulator type or restructure to avoid bounded-type accumulation in loops |
| `assertion might fail, cannot prove` | `generated proof assertion could not be verified` | Check that all variables used in the expression are initialized and in range at this point |
| `loop should mention .* in a loop invariant` | `prover cannot establish loop body safety without additional facts` | Restructure the loop to use bounded iteration (`for item of`) or a wider accumulator type |
| `call to a volatile function in interfering context` | `shared reads in compound conditions must be snapshot first` | Read the shared value into a local variable before using it in `and then` / `or else` |
| `cannot write .* during elaboration` | `imported state cannot be modified at unit scope` | Move the operation into a task body or subprogram |
| `uninitialized` | `variable may be uninitialized on this path` | Ensure the variable is assigned before use on all code paths |
| `precondition might fail` | `precondition of called function may not hold` | Add a guard ensuring the precondition before the call |

**Rewriting layer:**

- A post-processor in the `safe build` proof path that intercepts
  GNATprove output before display.
- For each GNATprove diagnostic line:
  1. Extract the emitted-Ada file path and line number.
  2. Look up the Safe source location from the mapping.
  3. Match the message against the classification catalog.
  4. Emit the Safe-native diagnostic with source location and fix.
  5. If no catalog match, emit a generic diagnostic with the mapped
     source location and the original GNATprove message.
- The raw GNATprove output remains available via `--verbose` for
  debugging.

**Structured output for AI agents:**

- When `safe build` or `safe prove` fails, emit a JSON diagnostic
  array to a sidecar file (`.safe-build/diagnostics.json`) with
  fields: `file`, `line`, `column`, `severity`, `message`, `fix`,
  `raw_gnatprove_message`.
- AI agents can parse this file directly instead of scraping stderr.
- The sidecar file is written on proof failure and removed on proof
  success.

### Out of scope

- Expression-level source mapping (statement-level is sufficient for
  the first slice).
- Custom GNATprove prover strategies or lemma injection.
- Gold-level functional correctness contracts or specifications.
- Interactive proof integration (Coq/Lean export).

### Proof impact

Zero. This is a diagnostic/UX milestone. The proof surface is
unchanged.

### Dependency

Follows PR11.22k. Deferred until after the extended hygiene series so the
mapping lands on a cleaned emitter and stabilized proof/build surface.

---

# PR12: Tooling and Developer Ergonomics

The PR11 series delivers a language that is safe by construction. The PR12
series makes it usable day-to-day by replacing prototype tooling with
production-grade infrastructure.

Without this series, Safe is a language with strong guarantees that nobody
can comfortably use — the CLI is a Python wrapper, there is no formatter,
no real LSP, no workspace mode, and no package management. PR12 closes
that gap before the claims-hardening work begins.

## Dependency Chain

- PR12.1 follows PR11.23 (compiled native `safe` CLI binary).
- PR12.2 follows PR12.1 (single-archive distribution).
- PR12.3 follows PR12.2 (`safe fmt` — code formatter).
- PR12.4 follows PR12.3 (full LSP server).
- PR12.5 follows PR12.4 (workspace mode — multi-package project discovery).
- PR12.5a follows PR12.5 (complete VS Code extension).
- PR12.6 follows PR12.5a (package management and dependency resolution).
- PR12.7 follows PR12.6 (standard serialization library — protobuf, JSON; format-agnostic derive integration deferred to PR14.5).
- PR12.8 follows PR12.7 (standard I/O library — file, stdin/stdout, arguments, with task-based I/O seams).
- PR12.9 follows PR12.8 (`safe test` — built-in test framework and runner).
- PR12.10 follows PR12.9 (`safe doc` — documentation generation from source).
- PR12.11 follows PR12.10 (cross-compilation and target management).
- PR12.12 follows PR12.11 (multi-error compiler recovery for IDE and AI agent workflows).
- PR12.13 follows PR12.12 (source-level debugger integration).
- PR12.14 follows PR12.13 (Rosetta Code completeness — Safe implementation of every Rosetta Code task in the corpus).
- v1.0 tag follows PR12.14.

---

## PR12.1: Compiled Native `safe` CLI

Replace the Python prototype CLI (`scripts/safe_cli.py`) with a compiled
native binary.

### Scope

- Rewrite the `safe` CLI in Ada (or eventually in Safe itself) as a
  native binary that ships without a Python runtime dependency.
- All existing commands (`build`, `run`, `prove`, `deploy`) must work
  identically.
- The incremental build cache (`.safe-build/`) and proof cache must
  transfer from the Python implementation to the native one.
- Performance target: `safe build` on a no-change 20-file project
  completes in under 1 second (vs. current Python startup overhead).

### Why first

Every subsequent tooling milestone builds on the CLI. A native binary
eliminates the Python runtime dependency, reduces startup latency, and
makes the distribution self-contained.

### Dependency

Follows PR11.22h.

---

## PR12.2: Single-Archive Distribution

Ship Safe as one downloadable archive containing everything needed to
write, build, prove, and run Safe programs.

### Scope

- One archive per supported platform (Linux x86-64, Linux ARM64).
- Contents: `safe` CLI binary, `safec` compiler binary, GNAT, gprbuild,
  GNATprove, SMT solvers (Z3, CVC5, Alt-Ergo), shared stdlib, proved
  standard library.
- No Python in the distribution. No Alire in the distribution.
- Install is: extract the archive, add the `bin/` directory to `PATH`.
- `safe build` and `safe prove` work immediately after extraction with
  no additional setup.

### Why second

The native CLI must exist before it can be packaged. The distribution
model determines how all subsequent tooling (formatter, LSP, package
manager) is delivered.

### Dependency

Follows PR12.1.

---

## PR12.3: `safe fmt` — Code Formatter

Add a deterministic code formatter that enforces Safe's style conventions.

### Scope

- `safe fmt <file.safe>` reformats a Safe source file in place.
- `safe fmt --check <file.safe>` exits nonzero if the file is not
  already formatted (for CI gating).
- Formatting rules: consistent indentation, normalized whitespace,
  canonical keyword casing (already lowercase-only), aligned record
  fields, and consistent spacing around operators.
- The formatter must be idempotent: formatting an already-formatted
  file produces identical output.
- The formatter is a standalone tool, not integrated into `safe build`.

### Why third

Formatter support is a prerequisite for a healthy contributor ecosystem
and for AI agents that generate Safe code — formatted output is more
reviewable.

### Dependency

Follows PR12.2 (ships in the distribution archive).

---

## PR12.4: Full LSP Server

Replace the current diagnostics-only LSP shim with a full Language
Server Protocol implementation.

### Scope

- Go-to-definition for functions, types, variables, and imported names.
- Hover for type information and documentation.
- Completion for visible names, record fields, methods, and builtins.
- Diagnostics on save (already exists in the current shim).
- Find all references.
- Rename symbol (local scope).
- The LSP server ships as a native binary in the distribution archive.
- Supported editors: VS Code (primary), any LSP-compatible editor.

### Why fourth

A real LSP server is what turns Safe from "a compiler you invoke from
the terminal" into "a language you write in an IDE." This is the single
biggest developer-experience improvement after the distribution.

### Dependency

Follows PR12.3 (ships in the distribution archive alongside the
formatter).

---

## PR12.5: Workspace Mode

Add multi-package project discovery so `safe build` can operate on a
project root directory rather than requiring a specific source file.

### Scope

- `safe build` with no arguments discovers all `.safe` files in the
  current directory tree, resolves their dependency graph, and builds
  them in topological order.
- A `safe.project` or equivalent manifest file defines project-level
  settings: name, version, source roots, dependencies, build options.
- The incremental cache operates per-project rather than per-directory.
- `safe prove` with no arguments proves all admitted fixtures in the
  project.
- `safe run` with no arguments runs the project's entry point if one
  is defined.

### Why fifth

Workspace mode is the prerequisite for real multi-package projects and
for the package manager. Without it, every build requires naming a
specific root file.

### Dependency

Follows PR12.4.

---

## PR12.5a: Complete VS Code Extension

Ship a production-quality VS Code extension that surfaces the full Safe
toolchain through the editor.

### Scope

- **LSP client wiring:** connect to the PR12.4 LSP server for
  diagnostics, go-to-definition, hover, completion, find references,
  and rename.
- **Syntax highlighting:** complete TextMate grammar covering all
  shipped Safe syntax including `optional`, `list of`, `map of`,
  `some`/`none`, `try`/`match`, `fair select`, interfaces, generics,
  `shared`, method syntax, and receiver declarations.
- **Snippets:** common patterns (function, record, enum, task, channel,
  select, match, for-of, interface, generic type/function).
- **Problem matchers:** parse `safec` and `safe build` / `safe prove`
  output so errors appear in the Problems panel with correct source
  locations.
- **Build tasks:** `safe build`, `safe run`, `safe prove`, `safe fmt`
  as VS Code tasks with keyboard shortcuts.
- **Debug launch:** launch configuration for `safe run` output binaries
  via GDB/LLDB.
- **Extension marketplace:** publish to the VS Code marketplace (or
  Open VSX) so installation is one click.
- The extension ships the LSP server binary or discovers it from the
  distribution's `PATH`.

### Why here

The LSP server (PR12.4) is the backend; the VS Code extension is the
frontend that makes it usable. Without the extension, developers must
configure the LSP client manually. With it, Safe works out of the box
in the most popular editor.

### Dependency

Follows PR12.5 (workspace mode), because the extension's project
discovery and multi-file support should reflect workspace mode
semantics.

---

## PR12.6: Package Management and Dependency Resolution

Add a package manager so Safe projects can declare and resolve external
dependencies.

### Scope

- `safe.project` gains a `dependencies` section listing required
  packages and version constraints.
- `safe get` fetches dependencies from a registry or source repository.
- `safe build` automatically resolves and builds dependencies before
  the root project.
- Dependency resolution is deterministic and reproducible (lockfile).
- The package registry may be a simple git-based or filesystem-based
  registry for v1.0; a full hosted registry is post-v1.0 work.
- Dependencies must be Safe packages. Wrapping Ada or C libraries is
  out of scope for v1.0.

### Why last in PR12

Package management depends on workspace mode, which depends on the
distribution, which depends on the native CLI. Each layer builds on the
previous one.

### Dependency

Follows PR12.5.

---

## PR12.7: Standard Serialization Library

Ship format-specific serialization libraries that consume the
`serializable` interface from PR11.21's `derive` mechanism.

### Scope

- **Protobuf library:** `safe_protobuf` package providing `to_protobuf`
  and `from_protobuf` functions that encode/decode any type satisfying
  the `serializable` interface to/from protobuf binary wire format.
  Schema generation from Safe type definitions (`.proto` output).
- **JSON library:** `safe_json` package providing `to_json` and
  `from_json` for human-readable interchange. No streaming parser in
  the first slice — full document parse/emit only.
- Both libraries consume the format-agnostic field-visitor interface
  that `derive serializable` generates. The compiler does not know
  about protobuf or JSON — the libraries do.
- Both libraries are written in Safe, proved at Bronze/Silver, and
  shipped in the standard distribution.
- Error handling uses `result of T` throughout: `from_json(text)`
  returns `result of my_type`, not a bare value.

### Why here

Serialization is the most common use case that reflection solves in
other languages. In this first slice, the serialization libraries operate
on explicit field-accessor functions that the user (or AI agent) writes.
When `derive serializable` ships in PR14.5, the libraries will also
consume the auto-generated visitor interface, eliminating that
boilerplate. The libraries are designed so the derive integration is
additive — no breaking changes.

### Dependency

Follows PR12.6 (package management). The serialization libraries are
the first standard-library packages that ship through the package
manager.

---

## PR12.8: Standard I/O Library

Ship a standard I/O library with task-based I/O seams for maximum
assurance.

### Design principle: I/O through tasks

All I/O operations are mediated by dedicated persistent service tasks
that own the I/O resources. User code communicates with I/O tasks
through channels, never touching file descriptors or OS handles directly.
This means:

- User code remains fully provable (no `SPARK_Mode => Off` in user code)
- I/O errors surface as `result of T` values through channels
- The `SPARK_Mode => Off` boundary is isolated to the I/O task bodies,
  which the programmer never declares or sees
- Concurrent I/O from multiple tasks is serialized through channels —
  no interleaving, no race conditions on file handles
- The I/O seam architecture from `docs/vision.md` is realized here

### Scope

- **File I/O:** `file_read(path)` returns `result of string`,
  `file_write(path, content)` returns `result of boolean`,
  `file_lines(path)` returns `result of list of string`.
  Internally, a persistent file-service task handles all file
  operations.
- **Stdin/stdout:** `read_line()` returns `result of string`.
  `print` remains the existing builtin for output. A persistent
  stdin-service task reads lines and sends them through an internal
  channel.
- **Command-line arguments:** `arguments()` returns `list of string`.
  Arguments are captured at program startup and served as a pure
  value — no task needed.
- **Environment variables:** `env(name)` returns `optional string`.
  Captured at startup, same as arguments.
- All I/O functions return `result of T` for error handling through
  `try`/`match`.
- The library is written in Safe. The I/O task bodies wrap Ada's
  `Ada.Text_IO`, `Ada.Directories`, and `Ada.Command_Line` behind
  `SPARK_Mode => Off` boundaries. All user-facing code is proved.

### Dependency

Follows PR12.7 (serialization). File I/O is needed before Rosetta
Code completeness (PR12.14).

---

## PR12.9: `safe test` — Built-In Test Framework

Add a test framework and runner so users can write and execute tests
for their own Safe code.

### Scope

- `safe test [file.safe]` discovers and runs test functions in the
  specified file or in all `.safe` files in the current project.
- Test functions are ordinary functions with a naming convention
  (e.g., `function test_addition`) or a `test` attribute/annotation.
- Assertions: `assert(condition)` and `assert_equal(expected, actual)`
  as builtins that report source location on failure.
- Test output: per-test pass/fail with source location, summary line
  with total passed/failed counts, nonzero exit code on any failure.
- `safe test --verbose` shows assertion failure details.
- Test functions are not included in the built binary for `safe build`
  / `safe run` — they are test-only.
- Tests are proved the same way user code is proved: `safe prove` on
  a test file verifies the test code is memory-safe and free of
  runtime errors.

### Dependency

Follows PR12.8 (I/O library). Tests often need file I/O for fixture
data.

---

## PR12.10: `safe doc` — Documentation Generation

Generate API documentation from Safe source files.

### Scope

- `safe doc [file.safe | directory]` generates HTML documentation from
  public type, function, and interface declarations.
- Documentation comments use a simple convention: `--- ` triple-dash
  comments preceding a declaration are treated as documentation.
- Output includes: type signatures, function signatures with parameter
  names and types, interface member listings, and cross-references
  between types and functions.
- Generated documentation is static HTML suitable for hosting.
- `safe doc` is included in the distribution.

### Dependency

Follows PR12.9 (test framework).

---

## PR12.11: Cross-Compilation and Target Management

Add a target abstraction so `safe build --target <name>` works without
board-specific deploy incantations.

### Scope

- `safe build --target stm32f4` compiles for the STM32F4 target using
  the appropriate GNAT cross-compiler and runtime.
- `safe build --target riscv32` compiles for RISC-V (when the verified
  backend exists).
- Target definitions live in the distribution as declarative
  configuration files specifying: compiler, runtime, linker script,
  and default stack/heap sizes.
- `safe deploy` becomes sugar over `safe build --target <board>` plus
  flash/simulate.
- `safe prove --target <name>` uses the target's integer width and
  runtime model for proof.
- User-defined target configurations are supported via project-level
  target files.

### Dependency

Follows PR12.10 (documentation generation).

---

## PR12.12: Multi-Error Compiler Recovery

Make the compiler recover from errors and report multiple diagnostics
per compilation, instead of rejecting on the first error.

### Scope

- The parser, resolver, and type checker continue after encountering
  an error, collecting diagnostics into a list rather than aborting.
- The compiler reports up to N diagnostics (configurable, default 20)
  per compilation unit.
- Each diagnostic includes source location, error message, and fix
  suggestion (where available).
- The LSP server (PR12.4) benefits directly: the editor shows all
  errors in a file, not just the first one.
- AI agents benefit directly: one compilation attempt surfaces all
  issues, enabling batch fixes rather than one-at-a-time iteration.
- Error recovery must not produce false-positive diagnostics —
  secondary errors caused by recovery from an earlier error should
  be suppressed or clearly marked.

### Dependency

Follows PR12.11 (cross-compilation).

---

## PR12.13: Source-Level Debugger Integration

Add Safe-to-Ada source mapping so a debugger can show Safe source lines
while stepping through the emitted Ada binary.

### Scope

- The emitter generates DWARF debug information that maps emitted Ada
  line numbers back to Safe source line numbers.
- When debugging with GDB or LLDB, the debugger shows Safe source
  lines, not Ada source lines.
- Variable names in the debugger reflect Safe source names, not
  emitted Ada mangled names.
- The VS Code extension (PR12.5a) integrates with this mapping so
  breakpoints set on Safe source lines work correctly.
- This requires the emitter to carry a source-location mapping table
  through emission and to generate appropriate debug pragmas or
  DWARF annotations in the emitted Ada.

### Dependency

Follows PR12.12 (multi-error recovery).

---

## PR12.14: Rosetta Code Completeness

Implement every task in the Rosetta Code corpus in Safe, proving that the
language is practically expressive enough for real-world programming at
least to that standard.

### Scope

- Port every task in the Rosetta Code task list
  (https://rosettacode.org/wiki/Category:Programming_Tasks) that is
  implementable within Safe's admitted surface.
- Each implementation must:
  - compile under `safe build`
  - run correctly under `safe run` (where applicable)
  - prove under `safe prove` (where the emitted Ada is within the
    blocking proof surface)
- Tasks that are fundamentally outside Safe's model (require reflection,
  raw pointer arithmetic, OS-specific APIs, GUI, or networking beyond
  the standard library) are documented as excluded with a reason, not
  silently skipped.
- All implementations live under `samples/rosetta/` organized by task
  category, extending the existing Rosetta sample corpus.
- This milestone is the practical expressiveness gate for v1.0: if a
  common programming task cannot be written in Safe, that is either a
  language gap to be filed or an honest exclusion to be documented.

### Why before v1.0

Rosetta Code is the closest thing to a universal "can this language do
X?" benchmark. Completing the corpus before the v1.0 tag means:
- Every expressiveness gap is discovered and either fixed or documented
  before the language is declared stable
- AI agents generating Safe code have a reference implementation for
  every common programming pattern
- The language's practical limitations are known and public, not
  discovered by early adopters after release

### Categories

The Rosetta corpus spans:
- String manipulation, sorting, searching, mathematical computation
- Data structures (lists, maps, trees, graphs)
- File I/O, text processing, parsing
- Concurrency patterns (producer-consumer, dining philosophers, etc.)
- Combinatorics, number theory, cryptographic primitives
- Simple games, simulations, and interactive programs

Each category exercises different parts of the Safe surface. Gaps
discovered during implementation feed back into deferred-items tracking
or late PR11/PR12 patches.

### Acceptance criteria

- Every Rosetta task is either implemented and passing or explicitly
  excluded with a documented reason
- Zero unnamed "we just did not get to it" gaps
- The excluded list is published alongside the implementations so the
  language's practical boundaries are transparent

### Dependency

Follows PR12.13 (debugger integration). The full language, tooling,
I/O library, test framework, and documentation surface must be available
before attempting comprehensive coverage.

---

## v1.0 Tag

After PR12.14, the Safe toolchain is:

- A compiled native CLI with build, run, prove, test, doc, deploy, and
  fmt commands
- A single-archive distribution with no external dependencies
- A full LSP server for IDE integration with multi-error diagnostics
- A complete VS Code extension with syntax highlighting, snippets, problem
  matchers, build tasks, debug launch, and one-click marketplace install
- Source-level debugger integration (Safe source lines in GDB/LLDB)
- Workspace mode with multi-package project support
- A package manager with deterministic dependency resolution
- Cross-compilation and target management (`--target stm32f4`, etc.)
- Standard I/O library with task-based I/O seams for maximum assurance
- Standard serialization libraries (protobuf + JSON) consuming the
  `derive serializable` interface
- Built-in test framework with assertions, discovery, and runner
- Documentation generation from source
- Complete Rosetta Code corpus coverage with every task implemented or
  explicitly excluded with a documented reason
- A language that is safe by construction for memory, concurrency, and
  absence of runtime errors

This is the v1.0 baseline. The claims-hardening series (PR13) follows.

---

# PR13: Claims Hardening Series

The PR11 series delivers a language that is safe by construction for the
categories it covers: memory safety, concurrency safety, and absence of
runtime errors. The PR13 series closes the gaps — the properties that Safe
does not yet prove but could, using the existing architecture.

PR13 milestones are ordered by addressability: the easiest wins first,
the hardest deferred to later in the series.

## Dependency Chain

- PR13.1 follows v1.0 / PR12.6 (receive-dependency deadlock analysis).
- PR13.2 follows PR13.1 (non-task termination checking).
- PR13.3 follows PR13.2 (stack depth bounding).
- PR13.4 follows PR13.3 (channel capacity exhaustion analysis).
- PR13.5 follows PR13.4 (optional Gold-level functional correctness surface).
- PR13.6 follows PR13.5 (numeric precision: fixed-point and float hardening).
- PR13.7 follows PR13.6 (timing and scheduling evidence expansion).
- PR13.8 follows PR13.7 (information flow analysis).

---

## PR13.1: Receive-Dependency Deadlock Analysis

Add a static receive-dependency graph analysis to the frontend that rejects
programs with circular blocking dependencies among receive-side operations.

### Scope

- Build a task-channel dependency graph from the resolved unit where edges
  represent blocking operations (`receive` and `select` channel arms).
- Reject programs where the graph contains a cycle of blocking receive
  dependencies. Two tasks each waiting to receive from a channel the other
  produces into — with no data flowing — is the target pattern.
- This is a frontend legality rule: it narrows the accepted program space,
  not a proof obligation. The soundness argument is graph-theoretic
  (acyclicity), not SMT-based.
- Cross-package analysis uses conservative channel-access summaries from
  imported `.safei` contracts.

### What this eliminates

After PR11.9d (nonblocking send) and PR12.1, the combined deadlock story
becomes: "send never blocks (by language rule), and receive-only circular
dependencies are rejected at compile time (by static analysis). Deadlock
freedom holds for all acyclic receive-dependency topologies."

### Dependency

Follows v1.0 (PR12.6).

---

## PR13.2: Non-Task Termination Checking

Prove that ordinary (non-task) functions terminate. Task bodies are
intentionally non-terminating (`loop` forever) and are excluded.

### Scope

- Reject or warn on non-task functions that contain unbounded loops
  without a provable termination argument.
- Safe already lowers most self-recursive patterns to structural loops
  (PR11.8f.1). Verify that no admitted non-task function body can diverge.
- Bounded loops (`for i of items`, `while` with a decreasing variant)
  are already provable. The gap is `while` loops with no obvious bound
  and any remaining recursive call patterns not caught by structural
  lowering.
- This is a frontend/MIR analysis pass, not an SMT proof obligation.

### What this eliminates

"Every non-task function in a Safe program that the compiler accepts is
guaranteed to terminate."

### Dependency

Follows PR13.1.

---

## PR13.3: Stack Depth Bounding

Prove that the runtime stack usage of every task and every non-task call
chain is statically bounded.

### Scope

- Compute worst-case stack depth from the static call graph with known
  frame sizes for each function.
- Safe's non-recursive admitted surface (after PR11.8f.1 structural
  lowering and PR12.2 termination checking) means the call graph is
  acyclic for non-task code. Stack depth is the sum of frame sizes along
  the longest call chain.
- For tasks, stack depth is the longest call chain reachable from the
  task body.
- Report the computed stack depth per task and per entry point. Optionally
  reject programs that exceed a configurable stack budget.
- This may use GNATstack or a custom analysis pass over the emitted Ada.

### What this eliminates

"Stack overflow cannot occur in a Safe program that the compiler accepts,
given the reported stack budget."

### Dependency

Follows PR13.2 (termination checking ensures the call graph is acyclic
for non-task code).

---

## PR13.4: Channel Capacity Exhaustion Analysis

Analyze whether channel capacity exhaustion is handled on all execution
paths.

### Scope

- For every `send ch, value, ok` call site, verify that the `not ok`
  path is handled — either by retrying, propagating an error, or taking
  an explicit recovery action.
- "Handled" means the `ok` variable is checked before the next observable
  operation on the same execution path. Unchecked send-failure results
  are rejected or warned.
- This is a flow-analysis extension in the MIR analyzer, not an SMT proof.
- It does not prove that channels never fill — that would require
  capacity/rate analysis. It proves that the programmer handles the case
  where they do fill.

### What this eliminates

"Every channel send in a Safe program either succeeds or the failure is
explicitly handled by the programmer."

### Dependency

Follows PR13.3.

---

## PR13.5: Optional Gold-Level Functional Correctness Surface

Add an optional annotation surface for functional correctness
specifications, so programmers who want to prove "the program computes the
right answer" can do so without leaving Safe.

### Scope

- Add optional `ensures` clauses on function return types:
  `function add (a : integer; b : integer) returns integer ensures result == a + b`
- Add optional `requires` clauses on function parameters:
  `function divide (a : integer; b : integer (1 to 100)) returns integer requires b > 0`
- These are **optional** — Safe programs compile and prove safe without
  them. They add Gold-level correctness proofs for functions that carry
  them.
- The emitter lowers `ensures` to Ada postconditions and `requires` to
  Ada preconditions. GNATprove proves them the same way it proves any
  SPARK contract.
- This changes Safe's identity from "zero-annotation safety" to
  "zero-annotation safety with optional correctness annotations." The
  safety guarantee remains annotation-free; the correctness guarantee
  is opt-in.

### What this enables

Programmers and AI agents can state what a function should compute, and
the compiler proves it. This is the path to a standard library proved at
Gold level.

### Dependency

Follows PR13.4.

---

## PR13.6: Numeric Precision Hardening

Close the floating-point and fixed-point gaps.

### Scope

- **Fixed-point support (PS-002):** add fixed-point types to the admitted
  surface with Rule 5 coverage for non-trapping arithmetic.
- **Floating-point semantic policy (PS-026):** define and enforce a
  precision model beyond "inheriting Ada's defaults." Specify rounding
  mode, NaN/infinity handling, and cross-platform reproducibility.
- Both require emitter and proof-surface changes to generate the
  appropriate Ada types and GNATprove contracts.

### What this eliminates

"Numeric arithmetic in Safe programs is fully specified and proved for
integer, fixed-point, and floating-point types."

### Dependency

Follows PR13.5.

---

## PR13.7: Timing and Scheduling Evidence Expansion

Extend the runtime evidence base beyond the admitted STM32F4/Jorvik
subset.

### Scope

- Add additional Renode evidence lanes for other ARM targets (e.g.,
  Cortex-M7, Cortex-A53).
- Integrate WCET analysis tooling (aiT, Rapita, or equivalent) so
  worst-case execution time is reported per function and per task.
- Integrate Rate Monotonic Analysis so schedulability is verified for
  the admitted task set under the Jorvik priority model.
- This is evidence-expansion work, not language-feature work. The
  language surface does not change.

### What this eliminates

"The admitted concurrency surface is backed by timing and scheduling
evidence beyond a single target, with worst-case execution time and
schedulability analysis for the task set."

### Dependency

Follows PR13.6.

---

## PR13.8: Information Flow Analysis

Track which data flows to which output and reject programs that violate
a declared information-flow policy.

### Scope

- Add optional `classification` annotations on types or bindings:
  `secret : classified integer = 42`
- Add flow rules: classified data cannot flow to unclassified outputs
  (print, channels to unclassified tasks, public function returns).
- The analysis is a frontend/MIR flow pass, not an SMT obligation.
- This is the most speculative item in the PR12 series. It may be
  descoped or redesigned based on real usage feedback.

### What this eliminates

"Safe programs that use classification annotations are guaranteed to
not leak classified data to unclassified outputs."

### Dependency

Follows PR13.7. This is the last item in the PR12 series and the most
likely to be descoped or deferred to a post-PR12 series.

---

## Proposal Incubation and Branch Strategy

The numbered PR11.x milestones should be admission milestones, not dumping
grounds for unresolved language experiments.

### Working Rule

- Long-running proposal exploration can happen on independent proposal
  branches.
- Those branches should track Rosetta deltas, migration notes, readability
  observations, and parser/emitter experiments without claiming roadmap
  admission.
- Numbered PR11.x milestones should only absorb proposals that have reached a
  bounded, decision-complete state.

### Admission Criteria

- A proposal branch must have a coherent migration story against main.
- Rosetta and sample evidence must show the proposal improves readability or
  ergonomics on real programs, not just synthetic cases.
- Parser and tooling consequences must be understood well enough to define a
  deterministic acceptance corpus.
- If multiple experiments compete, they should evolve independently and only the
  most credible candidate should graduate into the next numbered milestone.

### Sync Strategy

- Proposal branches should merge or rebase from main regularly to stay aligned
  with accepted language changes.
- Mainline milestone branches should not depend on unresolved proposal-branch
  behavior.
- In this stripped-down branch, accepted milestone state lives in the roadmap
  docs rather than tracker/dashboard files; proposal branches can carry
  exploratory notes and Rosetta diffs without pretending to be canonical
  roadmap state.
- Tracked milestone branches should use `codex/pr111-...` through
  `codex/pr1111-...`.
- Experimental proposal branches should use `codex/proposal-<slug>`.

---

## Post-PR11.11: Spec v1.0 Baseline

After PR11.11, the spec can be baselined. This is not a single milestone but a
gate condition.

### Decisions Required

- Resolve or defer all remaining TBDs with explicit version targets.
- Case sensitivity final decision.
- Discriminant-constrained dispatch decision (Discriminant-Constrained Dispatch
  proposal from `docs/syntax_proposals.md`).
- Freeze grammar, type system, and emission rules.

### Scope Ledger Items for v1.0 Resolution

| PS Item | Description |
|---------|-------------|
| PS-024 | Target platform constraints (TBD-01) |
| PS-025 | Memory model constraints (TBD-03) |
| PS-026 | Floating-point semantics (TBD-04) |
| PS-027 | Abort handler behaviour (TBD-07) |
| PS-029 | Automatic deallocation semantics (TBD-11) |

---

## Tooling Phases (Post-v1.0)

Not detailed here. Listed as horizons for future planning:

- Full LSP server (diagnostics, go-to-definition, hover, completion)
- `safe fmt` (formatter with `--default` and `--strict` modes)
- `safe build` workspace mode (multi-file projects)
- Alire crate distribution
- Standard library elaboration

---

## Ordering Rationale

**Evaluation harness before syntax** — PR11.1 delivers `safe build`, syntax
highlighting, diagnostics-on-save, and the first Rosetta/sample corpus so that
syntax proposals are evaluated with real tooling feedback across real programs,
not just command-line-only compilation or hand-crafted examples.

**Parser completeness in two steps** — PR11.2 adds strings and case
statements, which unlock more realistic programs quickly. PR11.3 then tackles
general discriminants, tuples, and structured returns as a separate, larger
type-system expansion before syntax transformation begins.

**Proof checkpoint before syntax churn** — PR11.3a closes the proof debt from
PR11.2 and PR11.3 before PR11.4 through PR11.7 add more admitted syntax
surface. This keeps the emitter/proof story from drifting too far behind the
accepted language.

**Admit likely syntax winners first** — PR11.4 and PR11.5 front-load the
lowest-risk syntax changes (`returns`, `else if`, optional semicolons, and
possibly `var`) so the most plausible admissions stabilize early.

**Whitespace cutover after lower-risk sugar** — PR11.6 lands indentation-based
block structure after PR11.4 and PR11.5, once the lower-risk spelling and
separator changes have already stabilized.

**Lowercase convention after the surface settles** — PR11.7 enforces an
all-lowercase Safe source convention now that the language surface is
indentation-structured and the original reference-signal proposals are
redundant (access types are removed in PR11.8e).

**Value-type revolution after syntax** — PR11.8 through PR11.8g follow the
syntax-admission phases because the unified integer type, value-type string,
growable arrays, copy-only semantics, and inferred reference types
collectively reshape the type system and proof model. They build on the
stable syntax surface established by PR11.4 through PR11.7.

**Numeric proof checkpoint before artifact freeze** — PR11.8a revalidates the
numeric-sensitive proved corpus immediately after PR11.8, rather than leaving a
large numeric proof backlog to the end of the series.

**Concurrency proof in parallel before artifact freeze** — PR11.8b runs as a
parallel proof track after PR10.5 and PR10.6 and should complete before
PR11.8g and PR11.9 so artifact contracts freeze against a broader proved
concurrency surface rather than only the frozen PR10 subset.

**Deferred channel-contract syntax after the proof checkpoint** — PR11.8b.1
kept task direction clauses and scoped-binding receive separate from PR11.8b
so parser/interface work did not block the concurrency proof closure; that
split shipped in PR #140 and the resulting fixtures were later reclosed under
`PR11.8g.1` / `PR11.8g.3`.

**Value-type semantic reset after the numeric reset** — PR11.8c, PR11.8d, and
PR11.8e deliberately continue the `PR11.8` rethink into binary arithmetic, a
copying string type, and copy-by-default value/reference semantics rather than
freezing the roadmap at the older ownership-first model.

**Value-type proof before contract freeze** — PR11.8f revalidates the proved
corpus after the copy-by-default shift so the artifact freeze does not inherit
unbounded value-model proof debt.

**Value-only channels before contract freeze** — PR11.8g applies the recovered
value-type model to channels after the concurrency proof baseline lands, so the
artifact contract freeze sees a coherent concurrency and ownership story.

**Broader emitted proof coverage before the prove CLI** — PR11.8g.1 expands
`PS-018` from named checkpoints toward the admitted emitted proof-bearing
surface before `safe prove` becomes the public proof entry point.

**Proofable runtime and one I/O seam before the prove CLI** — PR11.8g.2 removes
the remaining emitted `SPARK_Mode => Off` debt and consolidates I/O behind a
single standard-library package.

**Jorvik-backed concurrency evidence before the prove CLI** — PR11.8g.3 closes
the admitted source-level concurrency gap against the Jorvik/Ravenscar model
before `safe prove` claims the emitted concurrency surface is fully proved.

**Artifact contracts after proof checkpoints** — PR11.9 stabilizes machine
interfaces only after the sequential, concurrency, and value-type proof
checkpoints have landed. Library consumers need stable interfaces and a stable
proof story.

**Monomorphic library before generics** — PR11.10 ships useful bounded
containers sooner, and the concrete implementations serve as test cases for the
generic design in PR11.11.

**Generics before spec freeze** — PR11.11 introduces generics, which affect the
type system. The spec cannot be baselined until the type system is complete.

**Proposal branches before roadmap admission** — experiments that need heavy
tire-kicking should live on independent proposal branches until they have enough
Rosetta, migration, and tooling evidence to justify admission into a numbered
milestone.

---

## Relationship to Post-PR10 Scope Ledger

Mapping of `docs/post_pr10_scope.md` items to tracked `PR11.x` milestones.

Historical note: `PR11.8g.3` closes `PS-007` and `PS-031` for the shipped
concurrency subset and refiles only the broader residual aspirations as
`PS-035` / `PS-036`.

| PS Item | Description | Proposed Milestone |
|---------|-------------|--------------------|
| PS-001 | Static evaluation beyond PR08.3a subset | Not scheduled |
| PS-002 | Fixed-point Rule 5 | PR11.8 / PR11.8a decision point; support itself still not scheduled |
| PS-003 | `try_receive` analyzer precision | Not scheduled |
| PS-004 | Imported package-qualified writes | Not scheduled |
| PS-005 | Channel deadlock analysis (TBD-09) | PR11.9d |
| PS-006 | `Constant_After_Elaboration` (TBD-06) | Not scheduled |
| PS-008 | Task-level fault containment | Not scheduled |
| PS-009 | Constant access objects clarification | Not scheduled |
| PS-010 | Named-number declarations | Not scheduled |
| PS-011 | String and character literals | PR11.2 |
| PS-012 | Case statements | PR11.2 |
| PS-013 | Task declarative parts | Not scheduled |
| PS-014 | General discriminants | PR11.3 |
| PS-015 | Discriminant constraints | PR11.3 |
| PS-016 | Selective interface search-dir scanning | Not scheduled |
| PS-017 | Ada-side Bronze regression harness | Not scheduled |
| PS-018 | Emitted-output GNATprove coverage | PR11.8b (concurrency) plus the sequential checkpoints PR11.3a / PR11.8a / PR11.8f, then PR11.8g.1 for broader emitted-corpus expansion |
| PS-019 | I/O seam wrapper obligations | PR11.8g.2 |
| PS-020 | Diagnostic catalogue (TBD-05) | Not scheduled |
| PS-021 | Interchange-format policy (TBD-08) | PR11.9 |
| PS-022 | Performance targets (TBD-02) | Not scheduled |
| PS-023 | SPARK container library compatibility | Not scheduled |
| PS-024 | Target platform constraints (TBD-01) | Post-PR11.11 (v1.0 baseline) |
| PS-025 | Memory model constraints (TBD-03) | Post-PR11.11 (v1.0 baseline) |
| PS-026 | Floating-point semantics (TBD-04) | PR11.8g.1 for the currently emitted numeric proof subset; broader semantic policy remains Post-PR11.11 (v1.0 baseline) |
| PS-027 | Abort handler behaviour (TBD-07) | Post-PR11.11 (v1.0 baseline) |
| PS-028 | Numeric model ranges (TBD-10) | PR11.8 |
| PS-029 | Deallocation semantics (TBD-11) | PR11.3 / PR11.3a decision point; otherwise Post-PR11.11 (v1.0 baseline) |
| PS-030 | Binary wrapping semantics (TBD-12) | PR11.8c |
| PS-032 | Limited/private type views (TBD-13) | Not scheduled |
| PS-033 | Partial initialisation facility (TBD-14) | Not scheduled |
| PS-034 | Shared-runtime generic contract soundness for clone-based helpers | PR11.8g.4 |
| PS-035 | Broader `select ... or delay` fairness/latency beyond the admitted dispatcher contract | PR11.9a / PR11.9b |
| PS-036 | Broader runtime-model guarantees beyond the admitted STM32F4/Jorvik subset | Not scheduled |

Items marked "Not scheduled" retain their priority from the scope ledger
(`blocking-if-needed`, `nice-to-have`, or `long-term`) and will be assigned to
milestones as the roadmap is refined.

### Trigger Policy for Unscheduled Blocking-If-Needed Items

- `PR11.1`: if a Rosetta candidate needs an unscheduled
  `blocking-if-needed` item, exclude it from the starter corpus and tag it with
  that `PS-xxx` dependency rather than silently broadening `PR11.1`.
- `PR11.2`: do not absorb `PS-001` or `PS-010`; examples needing richer
  constant evaluation or named numbers stay deferred.
- `PR11.3`: do not absorb access discriminants or `PS-032`; narrow the
  accepted subset instead. If the admitted discriminant corpus would force
  broader deallocation-ordering semantics, resolve or explicitly bound
  `PS-029` before `PR11.3a`.
- `PR11.3a`: do not broaden proof claims beyond the PR11.2/PR11.3 checkpoint
  corpus; concurrency proof debt stays on `PR11.8b`.
- `PR11.4` through `PR11.7`: any syntax proposal that needs an unscheduled
  `blocking-if-needed` semantic item stays on proposal branches and does not
  enter the milestone.
- `PR11.8`: do not absorb `PS-002` or `PS-026`; keep numeric-model work
  limited to the planned integer/TBD-10/TBD-12 scope.
- `PR11.8a`: if `PR11.8` activates fixed-point or broader floating-point proof
  obligations, version them explicitly or defer them; do not carry silent
  numeric proof debt past the checkpoint.
- `PR11.8b`: keep `PS-007`, `PS-019`, and `PS-031` open even if the emitted
  concurrency fixture corpus becomes fully proved.
- `PR11.8b.1`: if task direction clauses or scoped-binding receive require AST
  or interface evolution, version that work explicitly rather than treating it
  as a proof-only checkpoint detail.
- `PR11.8c` through `PR11.8e`: keep the value-type transition bounded to the
  admitted binary, string, and inferred-reference surface; do not silently
  absorb generics, containers, or broader runtime model claims.
- `PR11.8f`: if the value-type model expands proof obligations beyond the
  bounded checkpoint corpus, either version them explicitly or defer them; do
  not push silent proof debt into `PR11.9`.
- `PR11.8g`: keep channel restrictions value-only even if broader ownership-
  bearing concurrency designs remain attractive; cross-task ownership transfer
  stays out of the admitted channel model.
- `PR11.8g.1`: close `PS-018` across the emitted sequential/concurrency/numeric
  subset that the live compiler admits; if a numeric form still cannot prove,
  either exclude it from emission or version that debt explicitly. The same
  rule applies to any residual emitter `Skip_Proof` fallback: admitted emitted
  patterns must prove or be removed from the admitted surface.
- `PR11.8g.2`: remove emitted `SPARK_Mode => Off` debt and consolidate I/O in a
  single standard-library seam package; do not freeze the toolchain while
  generated wrappers remain outside proof.
- `PR11.8g.3`: close the admitted concurrency story against Jorvik-backed
  evidence; do not carry `PS-007` or `PS-031` past the point where `safe prove`
  claims the emitted concurrency surface is fully proved.
- `PR11.9` through `PR11.11`: if tooling, library, or generic claims require
  `PS-024`, `PS-025`, or `PS-027`, record them as post-`PR11.11`
  v1-baseline dependencies rather than silently claiming them early.

---

## Relationship to Syntax Proposals

Mapping of each proposal in `docs/syntax_proposals.md` to the milestone where it
would be implemented.

| Syntax Proposal | Proposed Milestone |
|-----------------|--------------------|
| Whitespace-Significant Blocks | PR11.6 |
| Record Field Encapsulation | Not scheduled |
| `returns` Keyword | PR11.4 |
| `pragma Strict` | Post-PR11.x (post-1.0 deferred) |
| Statement Labels, Loop Labels, and `var` Declarations | PR11.5 (`var` declarations); labels not scheduled |
| Bounded String Buffer | Superseded by PR11.8d value-type `string` and `string (N)` |
| Bounded Container Types | Superseded by PR11.10 built-in `list of T`, `map of (K, V)`, `optional T` |
| Default Capacity Policy | PR11.10 (container implementation detail) |
| safe.toml (build configuration) | Post-PR11.x (unscheduled) |
| Emitter-Based Container Instantiation | PR11.10 (compiler-driven instantiation) and PR11.11 (user-defined generics) |
| Unified Integer Type | PR11.8 (single `integer` with inline range constraints, replaces three-tier model) |
| Discriminant-Constrained Dispatch | Post-PR11.11 (v1.0 baseline decision) |
| Optional Semicolons | PR11.5 |
| `else if` Keyword | PR11.4 |
| Simplified Predefined Type Names | Superseded by PR11.8 unified `integer`; `short` and `byte` are not admitted |
| Capitalisation as Reference Signal | WON'T FIX — redundant after PR11.8e eliminates explicit access types |
| Implicit Dereference | WON'T FIX — moot after PR11.8e removes user-visible access types |
| `to` Range Keyword | PR11.4 |
| Capitalisation as Export Signal | Post-PR11.11 (unscheduled) |
| Unified Function Type | PR11.4 |
| Task Channel Direction Constraints | PR11.8b.1 |
| Scoped-Binding `receive` | PR11.8b.1 |
| Predefined immutable `string` Type | PR11.2 |
| Tuple Types and Multiple Returns | PR11.3 |
| Error Handling Convention | PR11.3 (`(boolean, T)` tuples + predefined `result` type); PR11.11 (generic `result (T, E)`) |
| User-Defined Generics | PR11.11 (value-type parameters only; no user-defined self-referential types in 1.0) |

---

## Open Questions

Still-open design questions within the tracked roadmap:

1. **Should post-1.0 `pragma Strict` survive as a compatibility/profile mode
   once meaningful whitespace ships, or be dropped entirely?** PR11.6 no
   longer treats it as a pre-1.0 competing syntax mode, but the deferred design
   still needs an explicit keep-or-drop decision later.

2. **How much Rosetta/sample coverage should each proof checkpoint absorb?**
   The roadmap now stages proof at `PR11.3a`, `PR11.8a`, `PR11.8b`, and
   `PR11.8f`, but it still needs a crisp rule for when a newly admitted Rosetta
   program becomes mandatory proof debt versus compile-only evaluation
   coverage.

3. **What is the v1.0 target date (if any)?** The milestone sequence is defined
   but no timeline is attached. A target date would help prioritize "not
   scheduled" items and resolve the TBD register.

---

# PR14: Language Expansion Series

The PR14 series contains language features originally planned for PR11
that were deferred on 2026-04-06 to focus implementation effort on
shipping a clean, well-proved, well-tooled language before adding more
surface area. These features are valuable but none were blocking real
programs or the AI-first value proposition at the time of deferral.

PR14 follows the completion of PR11, PR12, and PR13. The milestone
definitions are preserved from their original PR11 positions so the
scope and rationale remain clear.

## Dependency Chain

- PR14.1 follows PR13.8 (user-defined iteration protocol).
- PR14.2 follows PR14.1 (nested packages / module hierarchy).
- PR14.3 follows PR14.2 (async/await via state-machine coroutines).
- PR14.4 follows PR14.3 (bounded user-managed allocation pools).
- PR14.5 follows PR14.4 (compile-time derive).

---

## PR14.1: User-Defined Iteration Protocol

*Moved from PR11.17.*

Add a standard `iterable` interface so user-defined types can participate
in `for item of x`.

### Scope

- Define a standard `iterable of T` interface with `has_next` and `next`
  methods (or equivalent cursor-based protocol).
- `for item of x` desugars to the protocol methods when `x` satisfies
  `iterable of T`.
- Built-in containers (`list`, `map`) already satisfy the protocol
  through their existing iteration lowering.
- User-defined types that implement the protocol gain `for ... of`
  support automatically.

### Proof impact

Zero new proof model. The desugared loop body uses existing method calls
and bounded iteration. GNATprove proves the concrete instantiation.

### Dependency

Follows PR13.8. Requires interfaces (PR11.11b) and generics (PR11.11c).

---

## PR14.2: Nested Packages / Module Hierarchy

*Moved from PR11.18.*

Add nested package declarations for structural code organization.

### Scope

- `package outer; package inner; ... end inner; end outer` allows
  hierarchical namespacing.
- Nested packages can be `public` or private.
- Name resolution follows lexical scoping: inner packages see outer
  declarations; outer code accesses inner declarations via
  `inner.name`.
- Import via `with outer.inner` brings the nested package into scope.
- No new runtime behavior — namespacing is a compile-time concern only.

### Proof impact

Zero. Name resolution only. GNATprove sees the same flat Ada packages
after emission.

### Dependency

Follows PR14.1.

---

## PR14.3: Async/Await via State-Machine Coroutines

*Moved from PR11.19.*

Add `async` functions and `await` expressions for structured concurrency
within a single task.

### Scope

- `async function fetch_data returns result of string` declares an
  async function that can suspend and resume.
- `value = await fetch_data()` suspends the current coroutine until the
  async function completes.
- The compiler lowers async functions to state-machine enums with
  explicit state transitions — no hidden stack allocation, no dynamic
  task creation.
- Coroutine frames are bounded and statically sized.
- `await` is legal only inside `async` functions.
- Async functions integrate with the `result` error model: an async
  function returning `result of T` can use `try` to propagate failures
  across `await` boundaries.

### Proof impact

The state machine is sequential code with explicit transitions.
GNATprove proves each state transition as an ordinary function body.
No new proof model — the emitted Ada is a `case` dispatch over an
enum discriminant.

### Dependency

Follows PR14.2. Requires sum types (PR11.13) for the state-machine
enum representation.

---

## PR14.4: Bounded User-Managed Allocation Pools

*Moved from PR11.20.*

Add fixed-capacity allocation pools for domain-specific data structures
that the built-in containers do not cover.

### Scope

- `type node_pool is pool of node capacity 256` declares a fixed-size
  pool of pre-allocated nodes.
- `allocate(pool)` returns `optional node` — `some` if capacity remains,
  `none` if full.
- `deallocate(pool, item)` returns the item to the pool.
- Pool lifetime is scope-bounded: all outstanding allocations are
  reclaimed when the pool goes out of scope.
- No unbounded heap allocation. The pool capacity is a compile-time
  constant.
- Pools are value types at the pool level (the pool itself copies/moves
  as a unit) but items allocated from a pool are references within that
  pool's storage.

### Proof impact

Pool capacity is static. Allocation failure surfaces as `optional`,
which is already proved. Deallocation is scope-bounded. GNATprove can
prove that indexing into pool storage is within bounds and that the pool
count stays within capacity.

### Dependency

Follows PR14.3.

---

## PR14.5: Compile-Time Derive

*Moved from PR11.21.*

Add a `derive` directive that auto-generates interface implementations
for record and sum types at compile time, replacing the need for runtime
reflection.

### Scope

- `type sensor_reading is record derive printable, serializable`
  instructs the compiler to generate implementations of the named
  interfaces for the type.
- The compiler reads the type's field list (names, types, order) at
  compile time and emits concrete method bodies that satisfy each
  derived interface.
- Standard derivable interfaces in this milestone:
  - `printable` — generates `to_string` that concatenates field names
    and values
  - `equatable` — generates `==` that compares fields structurally
  - `serializable` — generates a field-visitor method that a
    format-specific encoder can consume
- `derive` works on records, discriminated records, and sum types
  (PR11.13). It does not work on scalars, enums, or containers (which
  already satisfy standard interfaces through builtins).
- The `serializable` interface is format-agnostic: it exposes
  field-by-field traversal (name, type tag, value) through a standard
  visitor pattern. The actual encoding (protobuf, JSON, etc.) is a
  library-level concern, not a compiler concern.
- Derived implementations are ordinary generated functions that
  GNATprove proves the same way it proves any other function. No
  runtime type information, no dynamic field access.
- Once shipped, PR12.7 (standard serialization library) gains the
  auto-generated visitor integration that was deferred from its
  initial delivery.

### Why this exists

Without reflection, every type that needs serialization, printing, or
equality must have hand-written implementations for each interface.
`derive` eliminates that boilerplate while keeping the proof story
intact — the compiler generates the code, not the programmer, and
the generated code is proved.

### Proof impact

Zero new proof model. Derived method bodies are ordinary functions
over known field types. GNATprove proves them identically to
hand-written implementations.

### Dependency

Follows PR14.4. Requires interfaces (PR11.11b), generics (PR11.11c),
and sum types (PR11.13).

---

## Consolidated Deferred Items

Everything explicitly deferred across the current roadmap, with its current
home milestone or holding status and the reason it was deferred. This section
exists so that no deferred item drifts without a name.

### Shipped in PR11.8d.1

| Item | Shipped rule |
|------|--------------|
| String `case` | Literal choices only; lowered as `if`/`elsif` equality chains |
| String iteration (`for ch of s`) | Name-only iterable; each item is `string (1)` |
| String ordering (`<`, `<=`, `>`, `>=`) | Lexicographic comparison via Ada string relational operators |
| Guarded growable-to-fixed narrowing | Direct `.length == N` guard on the same growable object name |

### Deferred to PR11.8e.1 (shipped)

| Item | Status |
|------|--------|
| Mutually recursive record families | Done (PR #155) |

### Deferred to PR11.8e.2 (shipped)

| Item | Status |
|------|--------|
| Field-disjoint `mut` alias reasoning (record fields) | Done (PR #156) |

### Deferred to PR11.8f.1 (shipped)

| Item | Status |
|------|--------|
| Structural traversal emission (remove `Skip_Proof` scaffolding) | Done (PR #154) |
| Task-body blanket warning suppression retirement | Done (PR #154) |

### Shipped in PR11.8g

| Item | Status |
|------|--------|
| String as channel element type | Done (PR11.8g) |
| Growable array as channel element type | Done (PR11.8g) |

### Deferred to later PR11.9 follow-ons

| Item | Why deferred |
|------|-------------|
| Imported/public-channel `select` | `PR11.9a` intentionally narrows the admitted `select` surface to same-unit, non-public channels |
| `select` inside subprogram bodies | `PR11.9a` admits only unit-scope statements and direct task bodies |
| `priority select` | `PR11.9b` makes plain `select` fair by default and does not ship a priority-ordered escape hatch |
| Receive-only deadlock analysis | `PR11.9d` narrows the send surface but does not add graph-based deadlock analysis |
| `try_send` keyword retirement | `PR11.9d` keeps `try_send` reserved for targeted migration diagnostics for one milestone |
| Concurrent-channel receive-side `pragma Assume` retirement | The sequential path closed in `PR11.8g.2`; the broader concurrent/protected-object path remains deferred to later concurrency hardening |
| Broader runtime-model guarantees beyond the admitted STM32F4/Jorvik subset (PS-036) | The shipped runtime contract remains intentionally narrower than the broader target/runtime space |

### Deferred to PR11.9

| Item | Why deferred |
|------|-------------|
| `--target-bits 32\|64` flag | Build-time emitter parameterization; part of artifact contract freeze |

### Deferred to PR11.10

| Item | Why deferred |
|------|-------------|
| Static-index disjoint `mut` alias reasoning | Depends on built-in container identity model |
| Container-element-path disjoint `mut` alias reasoning | Same dependency |

### Deferred to PR11.11+

| Item | Why deferred |
|------|-------------|
| Generic interactions with discriminants | Out of scope before user-defined generics; depends on `PR11.11` |

### Deferred pending concrete use case

| Item | Why deferred |
|------|-------------|
| Character-literal enumerators (`'a'`, `'b'`) | `PR11.8i` shipped identifier-only enums; the spec narrowed to match the admitted surface |
| Enum range-constrained subtypes (`subtype primary is color (red to green)`) | Requires resolver/MIR enum-subrange bound tracking |
| `try` in `and then` / `or else` RHS | Short-circuit evaluation makes prelude hoisting conditional; the correct lowering needs branch-local rewriting rather than a simple statement-prefix prelude |
| Expression-form `match` | Statement-form `match` shipped first; expression-form needs type-flow and emission work across both arms |
| Ownership-specific discriminant extensions | No accepted example currently requires them in the admitted surface |

### Deferred from PR11.10b

| Item | Why deferred | Future home |
|------|-------------|-------------|
| Non-static / non-singleton indexed `mut` alias paths | PR11.10b ships only statically provable singleton disjoint indices; broader container-element alias reasoning deferred | Post-PR11.10; scope after real usage patterns emerge |
| Empty-list `pop_last` proof closure | `pr1110b_list_empty_build.safe` is a runtime-only witness; static empty-length lowering triggers GNATprove ineffectual-branch warnings | Proof exclusion with documented reason; revisit if GNATprove improves branch-elimination handling |

### Deferred from PR11.10c

| Item | Why deferred | Future home |
|------|-------------|-------------|
| Brace literal for map construction (`{k: v, ...}`) | Requires new lexer tokens and parser productions; deferred to avoid syntax design before real usage patterns | Post-PR11.11 or standalone syntax slice when brace semantics are clear |
| Guaranteed map iteration order (insertion or key order) | Constrains internal implementation; unspecified-but-deterministic is sufficient for the first slice | Add as `sorted_map of (K, V)` or explicit `sorted_keys(m)` if ordered iteration is needed |

### Deferred indefinitely / not scheduled

| Item | Why |
|------|-----|
| Access discriminants | Out of scope in `PR11.3`; no known admitted-surface use case |
| Discriminant-constrained dispatch | Out of scope in `PR11.3`; not scheduled independently |
| `pragma Strict` as a compatibility/profile mode | `PR11.6` no longer treats it as pre-1.0; the keep-or-drop decision remains post-1.0 work |
| Capitalisation as Export Signal | `public` remains the export mechanism; no scheduled competing syntax track |
| `move` keyword | Not scheduled |
| Mutable bounded text storage (`string_buffer`) | Deferred future text-storage work; not needed for the admitted `string` surface |
| Variant-part `case` syntax extensions | Future work; current admitted variant surface is intentionally narrower |
| Ordinary user-declared `String` record fields | Only compiler-generated `String` fields are admitted today |
| Fixed-point Rule 5 support (PS-002) | Deferred beyond the current numeric proof subset |
| Broader floating-point semantic policy (PS-026) | The current admitted subset stops at the shipped float surface; broader policy remains unscheduled/post-v1.0 work |
| Broader cleanup ordering (PS-029) | The representative ownership/deallocation subset shipped first; broader cleanup ordering remains deferred |
| String discriminants | Strings are not discrete; no known use case |
| MIR lint pass for Copy/Free completeness | Useful but not blocking; standalone CI check |
| Valgrind/AddressSanitizer leak checking | Manual validation step, not a repo dependency |
| Broader proof-fact narrowing (MIR interval queries for growable-to-fixed) | Guarded syntax covers the practical case; deeper integration deferred until needed |
