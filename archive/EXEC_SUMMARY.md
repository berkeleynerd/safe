# Executive Summary — Safe Language Specification Draft

## Overview

This document summarises the decisions made during generation of the Safe Language Reference Manual (spec/ directory, 10 files). The specification was generated from SPEC-PROMPT.md following the prescribed workflow order.

---

## Generation Order

Files were generated in the order prescribed by SPEC-PROMPT.md §Workflow:

1. `02-restrictions.md` — Section 2: Restrictions and Modifications
2. `08-syntax-summary.md` — Section 8: Syntax Summary (authoritative BNF)
3. `03-single-file-packages.md` — Section 3: Single-File Packages
4. `04-tasks-and-channels.md` — Section 4: Tasks and Channels
5. `05-assurance.md` — Section 5: Assurance
6. `06-conformance.md` — Section 6: Conformance
7. `07-annex-a-retained-library.md` — Annex A: Retained Library
8. `07-annex-b-impl-advice.md` — Annex B: Implementation Advice
9. `01-base-definition.md` — Section 1: Base Definition
10. `00-front-matter.md` — Section 0: Front Matter

---

## Key Decisions Made During Generation

### 1. Resolving Conditional Retentions

SPEC-PROMPT.md left several features as "retained if part of the SPARK 2022 subset." These were resolved definitively:

- **Declare expressions (§4.5.9):** Retained. Confirmed as part of SPARK subset since SPARK 21.
- **`for E of Array_Name` iteration:** Retained for arrays. SPARK 2022 supports array-of iteration. Container iteration excluded (requires tagged types/generics).
- **Delta aggregates (§4.3.4):** Retained. Confirmed as SPARK 2022 subset; standard replacement for deprecated `Update` attribute.

### 2. Tool Independence

Per ECMA Submission Shaping Constraint 5 and Editorial Convention 7, all normative sections were drafted without naming specific tools, compilers, or provers. Tool-specific guidance (GNAT, GNATprove, Jorvik profile specifics) was placed exclusively in Annex B (informative). §05 (Assurance) and §06 (Conformance) express guarantees as language properties, not tool invocations.

### 3. Ownership Rules — Self-Contained Specification

Per D17's drafting constraint, all ownership and borrowing legality rules are specified directly in Safe terms in §02 (Section 2, §2.3). SPARK RM and UG are cited as informative design precedent only. The Safe LRM is self-contained: a reader does not need to consult SPARK documents to determine Safe's legality rules.

### 4. Conformance — Single Level with Explicit Soundness

Per §06 requirements, a single conformance level is defined. A conforming implementation must enforce D27 Rules 1–5 soundly: the analyses may conservatively reject safe programs (over-approximation) but shall never accept programs with potential runtime errors (under-approximation). Silver follows as a logical consequence of sound rule enforcement — no separate "verification" step is needed. The original Safe/Core vs Safe/Assured split was removed (F24) because it introduced a conceptual distinction without practical difference while creating ambiguity about the soundness obligation.

### 5. Abstract/Limited in Grammar — Revised

The grammar in §08 originally retained `[ 'abstract' ] 'limited'` in `record_type_definition` to avoid diverging from the 8652:2023 production structure. On review, this was inconsistent with the treatment of every other excluded feature (generics, tagged types, exceptions, etc.), whose productions were removed from §08 rather than retained and rejected by legality rules. The production has been corrected to `[ 'limited' ] record_definition`. The `abstract` keyword remains reserved per the all-reserved-words policy, and §02 paragraph 7 continues to reject abstract type declarations.

### 6. Task Non-Termination Strictness

The non-termination legality rule (§04, §4.6) requires an unconditional `loop` as the outermost statement. `while True loop` is not accepted, even though it is theoretically non-terminating, because non-termination is undecidable in general. The unconditional form was chosen as trivially verifiable.

### 7. Delay Until — Revised

`delay until` has been excluded. Both `Ada.Calendar` and `Ada.Real_Time` are excluded, leaving no language-defined time type for absolute delay expressions. Only the relative delay statement (`delay Duration_Expression;`) is retained, which covers periodic task loops and select timeouts. The grammar, §02, §06, and Annex A have been updated accordingly. A future revision may reintroduce `delay until` alongside a minimal monotonic time package if absolute timing proves necessary.

### 8. TBD Register Population

All 14 TBD items from SPEC-PROMPT.md were populated in §00 with owner categories, resolution plans, and target milestones. Owners are assigned to role categories (Language committee, Implementation lead, Concurrency reviewer, Numerics reviewer, Ownership reviewer, Tooling lead) rather than named individuals, as the project does not have named assignees at this stage.

### 9. Annex B — No Named Tools

Per the task instructions, Annex B uses "should" voice throughout and describes capabilities rather than products. No specific compiler, prover, or tool version is named in normative or informative text. The DEFERRED-IMPL-CONTENT.md material was incorporated in generalised form.

### 10. UK English

The specification uses UK English throughout per ECMA Submission Shaping Constraint 1: "behaviour", "initialisation", "synchronisation", etc.

---

## Post-Generation Corrections

### D27 Rule 2 Strengthened (F13)

The original Rule 2 ("Strict Index Typing") required only that the index expression's type match the array's index type. This was unsound for constrained arrays with narrower bounds and for unconstrained array parameters with dynamic bounds — the Silver guarantee could be violated. Rule 2 has been replaced with a "Provable Index Safety" rule requiring the implementation to establish that the index is within the array object's actual bounds, either by type containment (the original rule as a fast path) or by sound static range analysis (for narrower-constrained and unconstrained cases). This aligns Rule 2 with the analysis approach already required for Rules 1 and 3.

### D27 Rule 1 Narrowing Points Expanded (F14)

The original Rule 1 defined narrowing points as assignment, parameter passing, and return — a closed list using the word "only." Two retained constructs that introduce range checks were omitted: type conversions (`Positive(B)`) and type annotations (`(Expr : T)`). This created a normative contradiction with Rule 3 condition (c), which relies on conversions being checked, and left type annotation semantics ambiguous. The narrowing-point enumeration has been expanded to five categories: assignment, parameter passing, return, type conversion to a more restrictive type, and type annotation.

### Channel Move Semantics and Evaluation Order (F15)

Channel operations (`send`, `receive`, `try_send`, `try_receive`) had no defined interaction with the ownership model. If a channel's element type was an owning access type, sending a value could create double ownership between the sending task and the channel/receiving task — violating exclusive ownership and potentially the data-race-freedom guarantee. Additionally, `try_send` had no defined behaviour for the payload on failure, and evaluation order was unspecified. Full move semantics have been added: `send` and `receive` perform moves; `try_send` moves only on success (source retains its value on failure); evaluation order is specified (expression evaluated before fullness check). A channel ownership invariant ensures each designated object is owned by exactly one entity at any time. The move triggers list in §2.3.2 has been expanded, and §5.4.1 now explains how channel move semantics extend data-race-freedom to heap objects.

### Null-Before-Move Legality Rule (F16)

The ownership model defined what happens to the source and target of a move, but not what happens to the target's old designated object when the target is already non-null. Since automatic deallocation occurs only at scope exit and `Unchecked_Deallocation` is excluded, overwriting a non-null owning access variable leaks the old designated object. A null-before-move legality rule has been added: the target of any move into an owning access variable must be provably null at that point, verified by flow analysis. This prevents leaks by construction for all ownership moves — assignment, channel receive, and any future move trigger.

### Lifetime Containment, Initialisation-Only Anonymous Access, and Named Access-to-Constant Deallocation (F17)

The ownership model had no explicit lifetime-containment rule for borrows and observes — it relied implicitly on declaration order without stating the requirement. Additionally, anonymous access variables could in principle be assigned after declaration (with interleaved declarations), breaking the lifetime invariant. Finally, named access-to-constant types were exempt from ownership checking but also from automatic deallocation, causing objects allocated through them to leak. Three additions: (1) anonymous access variables restricted to initialisation at declaration only; (2) explicit lifetime-containment legality rule requiring borrower/observer scope ⊆ lender/owner scope, with a normative no-dangling-access-values guarantee; (3) automatic deallocation extended to cover named access-to-constant variables at scope exit.

### Accessibility Rules for `.Access` and General Access Types (F18)

The spec retained `.Access`, `aliased` objects, and general access types (`access all T`) but never specified the rules governing when `.Access` is legal or whether the result can escape the declaring scope. The §05 runtime-check table said only "Simplified by ownership model" without stating the simplified rules. In Safe's simplified type landscape (no tagged types, no anonymous access return types, no access discriminants, `Unchecked_Access` excluded), all Ada accessibility checks reduce to compile-time legality rules — but the spec never stated this. A new §2.3.8 has been added with five paragraphs specifying: `.Access` on heap objects governed by borrow/observe rules; `.Access` on local aliased objects cannot escape the local scope (four specific rejection cases); general access types subject to the same rules; and a normative statement that no runtime accessibility checks exist.

### Cross-Package Ceiling Priority Computation (F19)

The ceiling priority rule (§4.2 paragraph 21) required the implementation to compute each channel's ceiling from the priorities of all tasks that access it, "directly or transitively through subprogram calls." However, the dependency interface information (§3.3.1) included effect summaries only for package-level variables, not for channel access — and channels are explicitly not variables (§4.5 paragraph 50). Without channel-access information in the interface, the implementation could not compute precise ceiling priorities across package boundaries under the separate-compilation model. The dependency interface has been extended with channel-access summaries (§3.3.1 item (i)), and a new paragraph (§4.2 paragraph 21a) specifies how ceiling computation uses these summaries cross-package, mirroring the approach used for task-variable ownership checking.

### Authoritative Grammar Missing Anonymous Access Productions (F20)

The authoritative BNF grammar in §08 defined `access_definition` and used it for record component definitions, but omitted it from `object_declaration`, `parameter_specification`, `function_specification`, and `extended_return_statement`. This made the entire borrow/observe mechanism syntactically illegal: local borrows (`Y : access T := X;`), anonymous access parameters, and anonymous access return types were all unparseable despite being required by the ownership model prose in §02 §2.3 and by SPEC-PROMPT.md D17. The `access_definition` alternative has been added to all four productions, matching Ada 2022 (8652:2023 §3.3.1, §6.1, §6.5).

### Annex A "MODIFIED" Library Units Reclassified (F21)

Three character-handling library units (`Ada.Characters.Handling`, `Ada.Characters.Conversions`, `Ada.Wide_Characters.Handling` / `Ada.Wide_Wide_Characters.Handling`) carried "MODIFIED" status with vague recovery language about "default values" and implementation choices for exception paths. Audit against 8652:2023 found that no function in any of these packages raises an exception — classification functions return `Boolean`, conversion functions use `Substitute` parameters, and widening conversions cannot fail. All three units have been reclassified from "MODIFIED" to "RETAINED" with precise justification for totality. The vague "default value" wording has been removed entirely, eliminating the portability and security risks it created.

### Silver Guarantee Scoped to Exclude Resource Exhaustion (F22)

The Silver normative statement (§5.3.1 paragraph 12) claimed every conforming Safe program is "free of runtime errors," but the runtime check table listed allocation as "Implementation-defined (see TBD register)" — the only entry without a discharge mechanism. Allocation failure depends on the execution environment, not program text, and cannot be statically discharged. A new scoping paragraph (12a) explicitly excludes resource exhaustion (allocation failure, stack overflow) from Silver scope, consistent with SPARK 2022's AoRTE. Behaviour when resource exhaustion occurs is defined (abort, per paragraph 103a) but is outside static reasoning. TBD-03 remains open for future static allocation bounding that could tighten this boundary.

### Conformance Split Collapsed to Single Level (F24)

The spec defined two conformance levels — Safe/Core (legality checking) and Safe/Assured (legality checking plus Silver verification). The spec itself acknowledged this was "a distinction without practical difference," but the wording of paragraph 13 could be misread as weakening the soundness obligation for Core, and paragraph 14(c) contradicted paragraph 13 by implying programs could pass Core but fail Assured. The two levels have been collapsed into one. A new §6.4 "Soundness" section explicitly requires all D27 analyses to be sound (over-approximation permitted, under-approximation prohibited) and states that Silver follows as a logical consequence — not as a separate verification step.

### Floating-Point Exceptional Behaviour Integrated into Silver (F23)

The four original D27 rules were all integer-specific or inapplicable to floating-point. Rule 1's wide intermediate model covered only integers; Rule 3's nonzero divisor proofs didn't address float division by zero; range check discharge cited integer-only machinery; and Ada's `Machine_Overflows` was inherited as implementation-defined, leaving float overflow and division by zero as potential runtime error sources. The §5.3.8 runtime check table had no rows for floating-point checks. A new Rule 5 has been added requiring IEEE 754 non-trapping arithmetic (`Machine_Overflows = False`): float overflow produces ±infinity, division by zero produces ±infinity, and invalid operations produce NaN — all defined values, not exceptions. Float range checks at narrowing points are discharged by static range analysis; NaN and infinity cannot survive narrowing. The runtime check table has been expanded with four float-specific rows. TBD-04 is partially resolved; remaining items are IEEE 754 revision mandate, float range analysis precision, and strict reproducibility mode.

---

## Statistics

| File | Approximate Paragraphs | Key Content |
|------|----------------------|-------------|
| 00-front-matter.md | 29 | Scope, references, terms, TBD register |
| 01-base-definition.md | 6 | Base definition, cross-reference table |
| 02-restrictions.md | 144 | Exclusions, ownership, Silver rules, inventories |
| 03-single-file-packages.md | 50 | Package model, legality, examples |
| 04-tasks-and-channels.md | 60 | Tasks, channels, select, ownership, examples |
| 05-assurance.md | 43 | Bronze, Silver, concurrency, examples |
| 06-conformance.md | 25 | Conformance levels, compilation model |
| 07-annex-a-retained-library.md | 76 | Library unit inventory |
| 07-annex-b-impl-advice.md | 27 | Implementation guidance |
| 08-syntax-summary.md | ~148 productions | Authoritative BNF grammar |
