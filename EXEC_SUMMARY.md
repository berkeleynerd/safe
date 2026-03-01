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

### 4. Conformance Levels: Safe/Core and Safe/Assured

Per §06 requirements, two conformance levels were defined:
- **Safe/Core:** Legality checking only — accept conforming, reject non-conforming.
- **Safe/Assured:** Core plus verification that the Silver guarantee holds.

This separation preserves flexibility for implementations at different maturity levels while maintaining the safety story.

### 5. Abstract/Limited in Grammar — Revised

The grammar in §08 originally retained `[ 'abstract' ] 'limited'` in `record_type_definition` to avoid diverging from the 8652:2023 production structure. On review, this was inconsistent with the treatment of every other excluded feature (generics, tagged types, exceptions, etc.), whose productions were removed from §08 rather than retained and rejected by legality rules. The production has been corrected to `[ 'limited' ] record_definition`. The `abstract` keyword remains reserved per the all-reserved-words policy, and §02 paragraph 7 continues to reject abstract type declarations.

### 6. Task Non-Termination Strictness

The non-termination legality rule (§04, §4.6) requires an unconditional `loop` as the outermost statement. `while True loop` is not accepted, even though it is theoretically non-terminating, because non-termination is undecidable in general. The unconditional form was chosen as trivially verifiable.

### 7. Delay Until

`delay until` is retained in the grammar and in §04 but the availability of `Ada.Calendar` and `Ada.Real_Time` are noted as excluded in Annex A. The time type for `delay until` is implementation-defined (flagged in TBD register as TBD-10 related).

### 8. TBD Register Population

All 14 TBD items from SPEC-PROMPT.md were populated in §00 with owner categories, resolution plans, and target milestones. Owners are assigned to role categories (Language committee, Implementation lead, Concurrency reviewer, Numerics reviewer, Ownership reviewer, Tooling lead) rather than named individuals, as the project does not have named assignees at this stage.

### 9. Annex B — No Named Tools

Per the task instructions, Annex B uses "should" voice throughout and describes capabilities rather than products. No specific compiler, prover, or tool version is named in normative or informative text. The DEFERRED-IMPL-CONTENT.md material was incorporated in generalised form.

### 10. UK English

The specification uses UK English throughout per ECMA Submission Shaping Constraint 1: "behaviour", "initialisation", "synchronisation", etc.

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
