# Safe Language Reference Manual

**Working Title:** Safe Language Specification

**File Extension:** `.safe`

**Version:** Draft 1.0

---

## Scope

1. This document specifies the Safe programming language, a systems programming language defined subtractively from ISO/IEC 8652:2023 (Ada 2022). Safe is Ada with features removed and a small number of structural reorganizations.

2. Safe is not a new grammar. It is Ada 2022 restricted by the SPARK 2022 subset, with further restrictions (Sections 2.1–2.2), structural changes (Sections 3–4), and language rules guaranteeing automatic formal verification (Section 2.8, Section 5).

3. This specification defines:
   - The restrictions applied to 8652:2023 (Section 2)
   - The single-file package model replacing Ada's specification/body split (Section 3)
   - The static task and channel concurrency model replacing Ada's full tasking (Section 4)
   - The SPARK assurance guarantees: automatic Bronze and Silver verification (Section 5)
   - Conformance requirements for implementations and programs (Section 6)
   - The retained predefined library (Section 7a)
   - Implementation advice (Section 7b)
   - The complete consolidated grammar (Section 8)

> **Compatibility note (non-normative):** Earlier internal drafts required a C emission backend and OpenBSD as a primary target. These requirements are removed. This specification defines Safe as a language; mapping to specific toolchains is described in the reference implementation sections (§6.1.2, §6.4, §6.5).

---

## Normative References

4. The following documents are normative references for this specification:

   - **ISO/IEC 8652:2023** — *Information technology — Programming languages — Ada.* This is the base language from which Safe is defined. All section and paragraph references in this specification refer to this document unless otherwise stated.

5. The following documents are informative references:

   - **SPARK Reference Manual** (AdaCore, version 27.0w) — Documents the SPARK 2022 restriction profile and ownership model that form the starting point for Safe's restrictions.
   - **SPARK User's Guide** (AdaCore, version 27.0w) — Describes SPARK assurance levels, GNATprove usage, and the ownership/borrowing model for access types.

---

## Terms and Definitions

6. For terms not defined below, see 8652:2023 §1.3. The following terms are defined for this specification or have modified meaning:

7. **Safe program** — A program written in the Safe language that conforms to this specification (§6.2).

8. **Conforming implementation** — A compiler that satisfies all requirements in §6.1, including emission of Ada/SPARK source code with automatic SPARK annotations.

9. **Channel** — A typed, bounded-capacity, blocking FIFO queue used for inter-task communication. Declared with the `channel` keyword. Compiled to a protected object in the emitted Ada.

10. **Ownership** — The SPARK 2022 property that each allocated object reachable through access values has exactly one owning variable at any program point. Assignment of an access value transfers ownership (move semantics).

11. **Move** — Transfer of ownership from one access variable to another. The source variable becomes null after the move.

12. **Borrow** — Temporary mutable access to an owned object, obtained by passing an access value as an `in out` parameter. The owner's access is frozen for the duration of the borrow.

13. **Observe** — Temporary read-only access to an owned object, obtained by passing an access value as an `in` parameter. The owner's access is frozen for the duration of the observation.

14. **Symbol file** — A per-package file produced by the compiler containing exported declarations, used for separate compilation of dependent packages.

15. **Wide intermediate arithmetic** — The evaluation model for integer expressions in Safe, where all intermediate results are computed in a 64-bit mathematical integer type with no overflow. Range checks are deferred to narrowing points.

16. **Narrowing point** — A point where a wide intermediate integer result is converted to a target type: assignment, parameter passing, or function return.

17. **Silver-by-construction** — The property that every conforming Safe program, when emitted as Ada/SPARK, passes GNATprove AoRTE (Absence of Runtime Errors) proof without any developer-supplied annotations. Achieved through the D27 language rules.

---

## Method of Description

18. This specification uses the descriptive conventions of 8652:2023 §1.1.4:

   - **BNF notation:** `::=` for productions, `[ ]` for optional, `{ }` for zero or more, `|` for alternation. Keywords in **bold**, nonterminals in *italic* or `snake_case`.
   - **Section structure:** Each language feature is described with subsections for Syntax, Legality Rules, Static Semantics, Dynamic Semantics, Implementation Requirements, and Examples, as applicable.
   - **Normative voice:** "shall" for requirements on implementations and programs, "should" for recommendations, "may" for permissions.
   - **Paragraph numbering:** Every normative paragraph is numbered sequentially within each section.
   - **Cross-references:** Citations of 8652:2023 use the form "8652:2023 §X.Y(Z)" where X.Y is the section and Z is the paragraph number. This specification does not reproduce 8652:2023 text — it references it.

---

## Design Decisions Summary

19. The following table summarizes the design decisions that govern this specification. Each decision is documented with full rationale in the companion document (SPEC-PROMPT.md).

| Decision | Summary | Spec Section |
|----------|---------|-------------|
| D1 | Subtractive language definition from 8652:2023 | §1 |
| D2 | SPARK 2022 as restriction baseline | §2 |
| D3 | Single-pass recursive descent compiler | §6.3 |
| D4 | Ada/SPARK as sole code generation target | §6.4 |
| D5 | Platform-independent via GNAT | §6.6 |
| D6 | Single source file per package (no .ads/.adb split) | §3 |
| D7 | Flat package structure, purely declarative | §3.2 |
| D8 | Default-private visibility with `public` annotation | §3.2 |
| D9 | Opaque types via `public type T is private record` | §3.2 |
| D10 | Subprogram bodies at point of declaration | §3.1 |
| D11 | Interleaved declarations and statements | §3.1 |
| D12 | No overloading | §2.1.4 |
| D13 | No general use clauses; `use type` retained | §2.1.6 |
| D14 | No exceptions | §2.1.9 |
| D15 | Restricted tasking — static tasks and channels | §4 |
| D16 | No generics | §2.1.10 |
| D17 | Access types with SPARK ownership and borrowing | §2.3 |
| D18 | No tagged types or dynamic dispatch | §2.1.1 |
| D19 | No contracts — `pragma Assert` instead | §2.7 |
| D20 | Dot notation for attributes (no tick) | §2.4.1 |
| D21 | Type annotation syntax replaces qualified expressions | §2.4.2 |
| D22 | SPARK verification aspects excluded from source; auto-generated | §2.2 |
| D23 | Retained Ada features enumerated | §1 |
| D24 | System sublanguage not specified; C FFI excluded | §2.1.12 |
| D25 | Ada/SPARK emission backend | §6.4 |
| D26 | Guaranteed Bronze and Silver SPARK assurance | §5 |
| D27 | Silver-by-construction rules (arithmetic, indexing, division, null) | §2.8 |
| D28 | Static tasks and typed channels | §4 |
| D29 | Compiler written in Silver-level SPARK | §6.8 |

---

## Document Structure

20. This specification is organized as follows:

| Section | Title | Content |
|---------|-------|---------|
| 0 | Front Matter | This section — scope, references, terms, method |
| 1 | Base Definition | Safe as 8652:2023 with stated restrictions and modifications |
| 2 | Restrictions | Every excluded or modified feature, with 8652:2023 citations |
| 3 | Single-File Packages | The package model replacing Ada's spec/body split |
| 4 | Tasks and Channels | The concurrency model replacing Ada's full tasking |
| 5 | SPARK Assurance | Bronze and Silver verification guarantees |
| 6 | Conformance | Implementation and program conformance requirements |
| 7a | Annex A — Retained Library | Status of every 8652:2023 Annex A library unit |
| 7b | Annex B — Implementation Advice | Emitted Ada conventions, symbol files, diagnostics |
| 8 | Syntax Summary | Complete consolidated BNF grammar (~148 productions) |
