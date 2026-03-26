# Section 1 — Base Definition

**This section is normative.**

1. The Safe language is defined as ISO/IEC 8652:2023 (Ada 2022), as restricted by Section 2 and modified by Sections 3–4 of this document.

2. All syntax, legality rules, static semantics, dynamic semantics, and implementation requirements of 8652:2023 apply to Safe programs except where explicitly excluded or modified by this specification.

3. Safe source spellings are case-sensitive and lowercase-only. This overrides
   Ada's case-insensitive source convention for identifiers, reserved words,
   predefined names, admitted attribute selectors, and admitted aspect / pragma
   names. Uppercase `E` in exponents and uppercase `A` .. `F` in based numerals
   remain permitted as part of numeric literal syntax.

4. A construct that appears in 8652:2023 but is not mentioned in Section 2 (Restrictions and Modifications) is retained in Safe with its 8652:2023 semantics, subject to the notation changes specified in Section 2, §2.4 (dot notation for attributes, type annotation syntax) and the lowercase source-spelling rule above.

5. **Retained feature set summary.** The following features of 8652:2023 are explicitly retained and form the core of the Safe language:

   (a) All four numeric type families: signed integer, modular integer, floating point, fixed point.

   (b) Subtypes with static and dynamic constraints.

   (c) Records including discriminated records with discrete discriminants.

   (d) Arrays including unconstrained array types.

   (e) Access-to-object types with the SPARK 2022 ownership and borrowing model (Section 2, §2.3).

   (f) Allocators with automatic deallocation on scope exit for all pool-specific access objects.

   (g) Static tasks and typed channels (Section 4).

   (h) Expression functions.

   (i) Renaming declarations.

   (j) Separate body stubs (`is separate`).

   (k) Child and hierarchical packages.

   (l) `use type` clauses.

   (m) Delta aggregates.

   (o) `pragma Assert`, `pragma Inline`, `pragma Pack`.

   (p) Limited types.

   (q) `for E of Array_Name` array iteration.

   (r) Target name symbols (`@` in assignment).

6. **Cross-reference.** The following table maps 8652:2023 sections to Safe modifications:

| 8652:2023 Section | Safe Treatment |
|-------------------|---------------|
| §1 General | Retained |
| §2 Lexical Elements | Modified — additional reserved words, tick restricted to character literals |
| §3 Declarations and Types | Modified — tagged types excluded, ownership model added |
| §4 Names and Expressions | Modified — dot notation, type annotation, some constructs excluded |
| §5 Statements | Retained with minor exclusions (iterators, parallel blocks) |
| §6 Subprograms | Modified — no overloading, no contracts, bodies at declaration |
| §7 Packages | Modified — single-file model (Section 3) |
| §8 Visibility Rules | Modified — no general use clauses, `public`/private model |
| §9 Tasks and Synchronisation | Replaced — static tasks and channels (Section 4) |
| §10 Program Structure | Modified — no circular deps, packages only as library units |
| §11 Exceptions | Excluded (except `pragma Assert`) |
| §12 Generic Units | Excluded |
| §13 Representation Issues | Partially retained (Section 2, §2.1.12) |
| Annex A | Partially retained (Annex A of this specification) |
| Annex B | Excluded (D24) |
| Annexes C–J | Mostly excluded (Section 2, §2.1.13) |

7. Any feature of 8652:2023 not addressed by this specification or its cross-referenced sections is retained with its standard semantics.
