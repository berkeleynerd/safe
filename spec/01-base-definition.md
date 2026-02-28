# 1. Base Definition

1. The Safe language is defined as ISO/IEC 8652:2023 (Ada 2022), as restricted by Section 2 and modified by Sections 3–4 of this document.

2. All syntax, legality rules, static semantics, dynamic semantics, and implementation requirements of 8652:2023 apply except where explicitly excluded or modified by this specification.

3. Where this specification is silent on a language feature retained from 8652:2023, the rules of 8652:2023 govern. No inference shall be drawn from the absence of a feature from the exclusion list — if a feature is not excluded, it is retained with its 8652:2023 semantics.

4. The following table summarizes how each major section of 8652:2023 is treated:

| 8652:2023 Section | Safe Treatment | This Spec Reference |
|-------------------|---------------|-------------------|
| 1. General | Retained | §0 (Front Matter) |
| 2. Lexical Elements | Retained, with dot notation for attributes | §2.4.1 |
| 3. Declarations and Types | Modified — tagged types, generics, controlled types excluded; access types with ownership | §2.1.1, §2.3 |
| 4. Names and Expressions | Modified — qualified expressions replaced by type annotations; dot notation for attributes | §2.1.2, §2.4 |
| 5. Statements | Retained, with channel operations and interleaved declarations added | §2.1.3, §4.3 |
| 6. Subprograms | Modified — no overloading, no contracts, bodies at point of declaration | §2.1.4, §3.1 |
| 7. Packages | Replaced by single-file package model | §3 |
| 8. Visibility Rules | Modified — no general use clauses, no overload resolution | §2.1.6 |
| 9. Tasks and Synchronization | Replaced by static tasks and channels | §4 |
| 10. Program Structure | Modified — packages only, compiler-managed elaboration | §2.1.8 |
| 11. Exceptions | Excluded (except `pragma Assert`) | §2.1.9 |
| 12. Generic Units | Excluded | §2.1.10 |
| 13. Representation Issues | Partially retained | §2.1.11 |
| Annex A | Partially retained | §7a |
| Annex B | Excluded | §2.1.12 |
| Annexes C–J | Partially retained | §2.1.12 |

5. The retained feature set includes all four numeric type families, subtypes with constraints, records (including discriminated records with variant parts), arrays (including unconstrained), access-to-object types with SPARK 2022 ownership, static tasks and typed channels, expression functions, renaming declarations, `goto` statements, child packages, `use type` clauses, declare expressions, delta aggregates, and `pragma Assert`.

6. Features not listed in Section 2's exclusion tables and not otherwise modified by Sections 3–4 are retained with their full 8652:2023 semantics.
