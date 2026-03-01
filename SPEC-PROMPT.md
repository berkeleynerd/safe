# Safe Language Specification — Drafter Prompt

## For use with Claude Code / Claude Copilot

---

## Overview

You are drafting the Language Reference Manual for **Safe**, a systems programming language defined subtractively from ISO/IEC 8652:2023 (Ada 2022) via the SPARK 2022 restriction profile, with further restrictions and a small number of structural changes.

Safe is not a new grammar. It is Ada with things removed and a few structural reorganizations. The specification is therefore a short document that references 8652:2023 normatively and states only the delta.

---

## Compatibility Note

Earlier design drafts included a C99 backend and OpenBSD as a primary deployment target. Those requirements are removed. Safe imposes no OS-specific targeting requirements. C foreign function interface is excluded from the safe language and reserved for a future system sublanguage.

---

## Conformance Note

Language conformance in this specification is defined in terms of language properties and legality rules, not specific tools or compilers. The normative conformance requirements appear in §06 and are expressed solely in terms of what a conforming implementation must accept, reject, and guarantee about program behaviour.

---

## ECMA Submission Shaping Constraints

The Safe specification is intended to be suitable for eventual submission as an Ecma International Standard. The following constraints apply to the generated draft:

1. **Drafting language:** Use consistent English throughout. For ECMA submission, use UK English spelling and conventions (e.g., "behaviour," "colour," "generalisation," "licence" as noun). If the initial draft uses US English, document an explicit conversion step before submission.

2. **Normative/informative declarations:** Each specification file shall declare its status in a header line: "This section is normative" or "This annex is informative." The following files are informative: `07-annex-b-impl-advice.md`. All other files are normative.

3. **Code examples are non-normative:** All code examples are non-normative illustrations unless explicitly stated otherwise. The normative content is the prose rules, not the examples. Examples must be conforming (Editorial Convention 6), but they do not define the language.

4. **Avoid normative pseudo-code:** Do not include pseudo-code algorithms as normative requirements. Describe semantics in prose (legality rules, static semantics, dynamic semantics). If an algorithm is included for clarity (e.g., the `Global`/`Depends` accumulation algorithm), label it as informative guidance.

5. **No normative software mandates:** Consistent with ECMA's policy that standards should define requirements and not mandate specific implementations, no normative section shall require the use of specific software, tools, or compilers. This reinforces Editorial Convention 7.

---

## Reserved Words

Safe reserves all ISO/IEC 8652:2023 (Ada 2022) reserved words (8652:2023 §2.9), regardless of whether the corresponding language feature is excluded in Safe. This preserves lexical clarity, simplifies the lexer, and ensures forward compatibility if excluded features are reconsidered in future revisions.

Safe also adds the following reserved words that are not Ada reserved words:

- `public` — visibility modifier (D8)
- `channel` — channel declaration (D28)
- `send` — channel send statement (D28)
- `receive` — channel receive statement (D28)
- `try_send` — non-blocking channel send (D28)
- `try_receive` — non-blocking channel receive (D28)
- `capacity` — channel capacity specifier (D28)

These identifiers shall not be used as user-defined names in Safe programs. A conforming implementation shall reject any program that uses a reserved word as an identifier.

---

## Design Decisions

This section records every design decision made during the language design process, with rationale. These decisions are final. Do not revisit or propose alternatives.

### D1. Subtractive Language Definition

**Decision:** Safe is defined as ISO/IEC 8652:2023 minus excluded features, not as a new language specified from scratch.

**Rationale:** A subtractive specification inherits decades of precision from the Ada RM. The type system, expression semantics, name resolution, and visibility rules are battle-tested. Rewriting them would introduce edge-case bugs that Ada already resolved. The resulting specification is approximately 80–110 pages referencing 8652:2023, versus 300+ pages written from scratch. This also provides a clear path for future ISO submission, since SC 22 reviewers already understand 8652.

### D2. SPARK 2022 as the Restriction Baseline

**Decision:** The starting feature set is the SPARK 2022 subset of Ada 2022, including SPARK's ownership and borrowing model for access types. We then apply additional restrictions on top of SPARK's (D12–D16, D18–D22). For concurrency, the baseline is a static tasking model surfaced through a channel-based programming model (D28).

**Rationale:** SPARK already removes the features most hostile to compilation simplicity and verification: exceptions, dynamic dispatch, and most of full Ada tasking. Starting from SPARK rather than full Ada means the excluded feature list is shorter and the retained feature set is already coherent. SPARK is a proven, deployed restriction profile used in safety-critical avionics and rail systems. SPARK 2022 reintroduced access types with Rust-style ownership semantics — including anonymous access for borrowing/observing, general access types with ownership checking, and named access-to-constant types — enabling dynamic data structures while preserving provability. Safe retains the full SPARK 2022 ownership model for access-to-object types. For tasking, Safe provides static tasks and channels through a higher-level channel abstraction designed for determinism and analysability.

### D6. No Separate Specification and Body Files

**Decision:** A Safe package is a single source file. There are no separate specification and body files. A conforming implementation shall make the public interface available to dependent compilation units for separate compilation. The mechanism (e.g., symbol files, compiler databases) is implementation-defined.

**Rationale:** The specification/body split creates maintenance burden — two files that must stay in sync, doubled file counts, and a confusing `private` section in the spec that is visible to the compiler but not logically to clients. Every modern language (Go, Rust, Zig, Odin, Swift) uses single-file modules with compiler-extracted interfaces. Oberon did this in 1987. The compiler already knows what is public; asking the programmer to state it twice is redundant.

### D7. Flat Package Structure — Purely Declarative

**Decision:** A package is a flat sequence of declarations. There is no `package body` wrapper, no `begin...end` initialization block, and no package-level executable statements. Variable initialization uses expressions or function calls at the point of declaration.

**Initialization order:**

- *Within a package:* Package-level variable initializers are evaluated in declaration order (top to bottom), as in Ada. An initializer may reference previously declared variables and call previously declared functions within the same package. Referencing a not-yet-declared entity in an initializer is a legality error (declaration-before-use).
- *Across packages:* If package A `with`s package B, then B's initializers complete before A's initializers begin. This matches Ada's elaboration semantics but is trivially satisfiable because Safe packages have no circular `with` dependencies (enforced as a legality rule — circular `with` dependencies are prohibited).
- *Tasks vs. initialization:* All package-level initialization across all compilation units completes before any task begins executing (D28). This is a language-level sequencing guarantee.

**Rationale:** If packages are purely declarative, the elaboration ordering problem is vastly simplified. Ada's elaboration model is a notorious source of complexity — `Elaborate`, `Elaborate_All`, `Elaborate_Body` pragmas and the elaboration order determination algorithm. By requiring that all initialization be expressible as declaration-time expressions or function calls, and by prohibiting circular dependencies, we reduce elaboration to a simple topological sort of the `with` graph. The package becomes what it should always have been: a namespace containing declarations. Executable code lives only inside subprogram bodies.

### D8. Default-Private Visibility with `public` Annotation

**Decision:** All declarations are private by default. The `public` keyword makes a declaration visible to client packages. There is no `private` section divider.

**Rationale:** Every modern safety-oriented language defaults to private: Rust, Go (lowercase), Zig, Swift. The reasoning is simple — forgetting to annotate something should hide it, not expose it. This also eliminates the need for a `private` section in the package, since there's no section model at all. The keyword `public` was chosen over alternatives (`pub`, Oberon's `*` marker) because it reads naturally in Ada's keyword-heavy style and is self-documenting.

### D9. Opaque Types via `public type T is private record`

**Decision:** A type can be public in name but private in structure using `public type T is private record ... end record;`. Clients can declare variables of the type (the compiler exports the size) but cannot access fields.

**Rationale:** This preserves Ada's information-hiding capability without requiring a separate specification file. The `public` keyword exports the type name to dependent units. The `private record` modifier tells the implementation to export size and alignment but not field layout. The implementation has full knowledge of the type (it's declared right there) and can generate correct code. The combination reads naturally: "this is a public type with a private structure."

### D10. Subprogram Bodies at Point of Declaration

**Decision:** Subprogram bodies appear at the point of declaration. A subprogram is declared and defined in one place. The only exception is forward declarations for mutual recursion.

**Rationale:** This is the Oberon model and eliminates the signature duplication that is Ada's most visible redundancy. In Ada, every subprogram declared in a spec must have its full signature repeated in the body — same parameters, same types, same modes, same contracts. In Safe, you write it once. The implementation extracts the signature for separate compilation. Forward declarations for mutual recursion are the one unavoidable case of signature repetition, and they are intrinsic to declaration-before-use compilation of mutually recursive functions (Pascal, C, and Oberon all require the same).

### D11. Interleaved Declarations and Statements in Subprogram Bodies

**Decision:** Inside subprogram bodies, declarations and statements may interleave freely after `begin`. A declaration is visible from its point of declaration to the end of the enclosing scope. The pre-`begin` declarative part is still permitted but not required.

**Rationale:** Ada requires all local variable declarations before `begin`, which forces the programmer to declare variables far from their first use. Zig, Rust, Go, and most modern languages allow declarations at point of use. This is a pure ergonomic improvement — declarations are visible from their point of declaration to the end of the enclosing scope.

### D12. No Overloading

**Decision:** Subprogram name overloading is excluded. Each subprogram identifier denotes exactly one subprogram within a given declarative region. Predefined operators for language-defined types are retained. User-defined operator overloading (defining `"+"` for a record type, etc.) is excluded.

**Scope of the restriction:**

- **Excluded:** Two subprograms with the same name in the same declarative region, regardless of parameter profiles. A conforming implementation shall reject any declarative region containing two subprogram declarations with the same identifier.
- **Excluded:** User-defined operator symbols (`function "+" (A, B : Widget) return Widget`). A conforming implementation shall reject any operator function definition.
- **Retained:** Predefined operators for numeric types, boolean, and other language-defined types. These are not user-declared and do not participate in overload resolution — they are intrinsic to the type.
- **Retained:** The same subprogram name may appear in different packages (qualified by the package name: `Sensors.Initialize` vs `Motors.Initialize`). This is not overloading; it is distinct declarations in distinct namespaces.

**Name resolution rule (dot notation):** When `X.Name` appears in source, resolution is unambiguous because: (a) if `X` is a record object, `Name` is a field; (b) if `X` is a type or subtype mark, `Name` is an attribute (in dot notation per D20); (c) if `X` is a package name, `Name` is a declaration in that package. The implementation determines which case applies from the type/kind of `X`, which is always known at the point of use due to declaration-before-use. No overload resolution is needed.

**Rationale:** Overloading is the single biggest source of name-resolution complexity in Ada. Resolving which overloaded subprogram a call refers to requires examining return types, parameter types, and context — sometimes across compilation units. Oberon has zero overloading. Dropping it dramatically simplifies name resolution (every name resolves to exactly one entity) and makes the language easier to read (every call site is unambiguous without consulting type information).

### D13. No Use Clauses (General), Use Type Retained

**Decision:** General `use` clauses (8652:2023 §8.4) are excluded. `use type` clauses are retained.

**Rationale:** General `use` clauses import all visible declarations from a package into the current scope, creating name pollution and making code harder to read (you can't tell where a name comes from without checking which packages are `use`'d). SPARK style guides already discourage them. `use type` is retained because it makes operator notation usable for user-defined types without importing everything else from the package — this is a targeted, controlled form of use that doesn't create the name pollution problem.

### D14. No Exceptions

**Decision:** Section 11 of 8652:2023 (Exceptions) is excluded in its entirety. No exception declarations, no raise statements, no exception handlers.

**Rationale:** Exceptions create hidden control flow that the compiler must account for at every call site — stack unwinding, cleanup actions, propagation semantics. They are one of the most complex features to implement in a compiler and one of the hardest to reason about in code review. SPARK already excludes them. Error handling in Safe uses explicit return values (discriminated records, status codes) and `pragma Assert` for defensive checks that abort on failure.

### D15. Restricted Tasking — Static Tasks and Channels Only

**Decision:** Full Ada tasking (Section 9 of 8652:2023) is excluded. In its place, Safe provides a restricted concurrency model based on static tasks and typed channels (D28). The following Section 9 features are excluded: task types, dynamic task creation, task entries, rendezvous (`accept` statements), all forms of `select` on entries, `abort` statements, `requeue`, protected types as user-declared constructs, and the real-time annexes (D.1–D.14) except for task priorities.

**Rationale:** Ada's full tasking model (tasks, protected objects, rendezvous, select statements, real-time annexes) is one of the most complex parts of Ada. Safe replaces it with a channel-based model (D28) providing static tasks, bounded channels, and the ceiling priority protocol for priority inversion avoidance. The programmer sees tasks and channels; the language guarantees data-race freedom by construction (no shared mutable state). Application-level deadlock freedom is not guaranteed by the language rules alone — it depends on the program's communication topology. See D26 for the precise concurrency guarantees.

### D16. No Generics

**Decision:** Section 12 of 8652:2023 (Generic Units) is excluded in its entirety.

**Rationale:** Ada generics require instantiation, which is effectively a second compilation pass (or a macro expansion step). They create significant compiler complexity around sharing vs. code duplication strategies. Oberon has no generics. The resulting language requires monomorphic code — if you need the same algorithm for multiple types, you write it for each type, or you use code generation tools outside the language. This is a significant expressiveness tradeoff accepted in exchange for compiler simplicity.

### D17. Access Types with SPARK Ownership and Borrowing

**Decision:** Access types are retained with the full SPARK 2022 ownership and borrowing model. All access-to-object type kinds supported by SPARK 2022 are permitted: pool-specific access types, anonymous access types (for borrowing and observing), general access types (with ownership checking), and named access-to-constant types (exempt from ownership checking, as in SPARK). Access-to-subprogram types are excluded (they introduce indirect calls, violating the static call resolution property — see D18). The full SPARK ownership model applies: move semantics on assignment, borrowing for temporary mutable access, observing for temporary read-only access. Explicit `Unchecked_Deallocation` is excluded — deallocation occurs automatically when the owning object goes out of scope.

Additionally, dereference of an access value requires the access subtype to be `not null` (see D27 Rule 4).

**Ownership model summary:**

| Safe construct                                       | Ownership semantics                                                                   |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `type T_Ptr is access T;`                            | Pool-specific owner — can be moved, borrowed, or observed                             |
| `subtype T_Ref is not null T_Ptr;`                   | Non-null owner — legal for dereference                                                |
| `X := new T'(...)`                                   | Creates a new owned value; X becomes the owner                                        |
| `Y := X` (named access-to-variable assignment)       | **Move**: X becomes null, Y becomes owner                                             |
| `procedure P (A : in T_Ptr)`                         | **Observe**: read-only access during call; caller's ownership frozen                  |
| `procedure P (A : in out T_Ptr)`                     | **Borrow**: temporary mutable access during call; caller's ownership frozen           |
| `Y : access T := X`                                  | **Local borrow**: Y is a local borrower of X; X frozen while Y is in scope            |
| `Y : access constant T := X'Access`                  | **Local observe**: Y observes X; X frozen while Y is in scope                         |
| `type C_Ptr is access constant T;`                   | Named access-to-constant — not subject to ownership checking; data is constant        |
| `type G_Ptr is access all T;`                        | General access — subject to ownership checking to prevent aliasing; cannot deallocate  |
| `G : G_Ptr := Obj'Access` (general access-to-var)    | **Move**: ownership of aliased local object moves into pointer; original frozen        |
| Scope exit of owning variable                        | Automatic deallocation (pool-specific access types only)                              |

**Restrictions vs. full Ada access types:**

- Access-to-subprogram types are excluded. A conforming implementation shall reject any access-to-subprogram type declaration. Rationale: indirect calls violate static call resolution (D18).
- `Unchecked_Access` attribute is excluded. `'Access` is retained for uses defined by SPARK's ownership model (borrowing aliased objects, observing, moving into general access types).
- `Unchecked_Deallocation` is excluded from Safe source. Deallocation is automatic on scope exit for pool-specific owning access objects.
- All ownership checking is local to the compilation unit — no whole-program analysis. This is compatible with SPARK's ownership model, which is also local.

**Retained SPARK 2022 access type kinds (all subject to SPARK ownership rules):**

- Pool-specific access-to-variable types (`access T`): ownership, move, borrow, observe
- Anonymous access-to-variable types: local borrowing, traversal functions, reborrowing
- Anonymous access-to-constant types: local observing
- Named access-to-constant types (`access constant T`): exempt from ownership checking; data is constant through all dereferences
- General access-to-variable types (`access all T`): subject to ownership checking to prevent aliasing; cannot be deallocated (may designate stack memory)

**Rationale:** Dynamic data structures (linked lists, trees, buffer pools, process tables) are essential for OS construction and systems programming. SPARK 2022 solved the safety problem for access types by adopting Rust-style ownership semantics — each access value has exactly one owner, ownership transfers are explicit via move semantics on assignment, and borrowing/observing provide temporary access without ownership transfer. These rules are enforced at compile time by local analysis (no whole-program reasoning), which is compatible with separate compilation. Safe retains the full SPARK 2022 ownership model for access-to-object types, including the extended access type kinds added in SPARK 2022 (anonymous access for local borrowing/observing, general access with ownership checking, named access-to-constant exempt from ownership). Excluding access-to-subprogram types eliminates indirect calls, preserving the property that every call resolves statically.

**Drafting constraint:** In the generated LRM, specify all ownership and borrowing legality rules directly in Safe terms. The Safe LRM shall be self-contained: a reader shall not need to consult any external (non-ISO) specification to determine Safe's legality rules or semantics. You may cite SPARK RM/UG as informative precedent for the design of ownership checking rules, but the Safe LRM shall not define its semantics by reference to SPARK documents. Define borrowing, observing, moving, and reborrowing precisely for each access type kind, including all corner cases needed for a self-contained legality specification (scope exit, early return, goto interactions, reborrowing depth).

### D18. No Tagged Types or Dynamic Dispatch

**Decision:** Tagged types (3.9), type extensions, dispatching operations, class-wide types, abstract types, and interface types are excluded.

**Rationale:** Dynamic dispatch requires vtable management, tag checks, class-wide streaming, and runtime type identification. It is fundamentally incompatible with the goal of a simple, predictable compilation model where every call resolves statically. Excluding tagged types also eliminates extension aggregates (4.3.2) and a large portion of Ada's OOP machinery. This also has a direct benefit for the tick-to-dot syntax change (D20): without dispatching, `X.Foo` is unambiguous — it's either a record field or an attribute, never a dispatching call.

### D19. No Contracts — pragma Assert Instead

**Decision:** All SPARK/Ada contract aspects are excluded: `Pre`, `Post`, `Contract_Cases`, `Type_Invariant`, `Dynamic_Predicate`, `Default_Initial_Condition`, `Loop_Invariant`, `Loop_Variant`, `Subtype_Predicate`. The language provides `pragma Assert` for runtime defensive checks.

**Rationale:** Contract aspects add significant grammar and semantic complexity (special forms like `'Result` and `'Old` in postconditions). The value they provide — interface-level documentation, automatic checking at type boundaries — is real but does not justify the complexity in a language targeting simplicity. `pragma Assert` provides runtime checking capability. A failed assert calls the runtime abort handler with a source location diagnostic. The language rules (D26, D27) guarantee Bronze and Silver assurance without developer-authored contracts.

Note: `Static_Predicate` and `Dynamic_Predicate` as subtype features (not contract features) may be reconsidered in a future revision if they prove essential for the type system. For this initial specification, they are excluded.

### D20. Dot Notation for Attributes (No Tick)

**Decision:** Ada's tick notation for attributes (`X'First`, `T'Image(42)`) is replaced by dot notation (`X.First`, `T.Image(42)`). The `'` character is used only for character literals (`'A'`).

**Rationale:** The tick character is visually noisy, unfamiliar to programmers from any other language, and makes the lexer context-sensitive (the lexer must disambiguate `T'First` from `T'(X)` from `'A'`). Dot notation is universal — every modern language uses dots for member/property access. This is safe in Safe because there are no tagged types: `X.Foo` unambiguously means either record field access or attribute access, resolved at compile time by checking the type of `X`. The lexer is simplified because tick only appears in the paired `'X'` character literal form.

### D21. Type Annotation Syntax Instead of Qualified Expressions

**Decision:** Ada's qualified expression syntax (`T'(Expression)`) is replaced by type annotation syntax (`Expression : Type`). Qualified expressions are dropped.

**Rationale:** Qualified expressions exist in Ada primarily for overloading resolution and aggregate type disambiguation. Safe has no overloading, so most uses disappear. For the remaining cases (aggregate disambiguation), type annotation syntax reads naturally left-to-right ("this value, which has this type") and is consistent with declaration syntax (`X : Integer := 42` — the colon already means "has type"). Every modern typed language (Rust, Kotlin, TypeScript, Zig, Swift) puts the type after the value. The grammar production is trivial: `annotated_expression ::= expression ':' subtype_mark`. Precedence: `:` binds loosest, so parentheses are needed only in argument position: `Foo ((others => 0) : Buffer_Type)`.

### D22. Eliminated SPARK Verification-Only Aspects

**Decision:** The following SPARK-specific aspects are excluded because they exist solely for static verification (flow analysis, proof) and have no runtime meaning:

- `Global`, `Depends`
- `Refined_Global`, `Refined_Depends`, `Refined_State`, `Abstract_State`, `Initializes`
- `Ghost` (ghost code for proof)
- `SPARK_Mode` (the entire language is the mode)
- `Relaxed_Initialization`

**Rationale:** Safe does not require the developer to write these aspects. The language guarantees Bronze and Silver assurance through its type system and legality rules (D26, D27) without developer-supplied verification annotations. The remaining verification-only aspects (`Ghost`, `Refined_State`, etc.) provide information for Gold/Platinum proof levels and cannot be automatically derived; they are excluded.

### D23. Retained Ada Features

**Decision:** The following features are explicitly retained:

- All four numeric type families (signed integer, modular integer, floating point, fixed point)
- Subtypes with static and dynamic constraints
- Records including discriminated records (discrete discriminants, static constraints, defaults)
- Arrays including unconstrained array types
- Access-to-object types with full SPARK 2022 ownership and borrowing rules, including: pool-specific access types, anonymous access types (borrowing/observing), general access types (`access all`, with ownership checking), named access-to-constant types (exempt from ownership checking)
- `'Access` attribute for borrowing, observing, and moving as defined by SPARK 2022 ownership model
- Aliased objects (required for `'Access` attribute under SPARK ownership rules)
- `not null` access subtypes (required for dereference per D27 Rule 4)
- Allocators (`new`) with automatic deallocation on owner scope exit
- Static tasks with priority (D28)
- Typed channels with bounded capacity (D28)
- `send`, `receive`, `try_send`, `try_receive` statements (D28)
- `select` on channel receive with delay timeout (D28)
- String handling via fixed-length arrays and slices (no dynamic/unbounded strings)
- Expression functions
- Renaming declarations
- Separate body stubs (`is separate`)
- `goto` statements
- Child and hierarchical packages
- `use type` clauses
- Declare expressions (Ada 2022) — retained; confirmed as part of the SPARK subset since SPARK 21
- Delta aggregates (Ada 2022) — retained; confirmed as part of the SPARK subset since SPARK 21; standard replacement for deprecated `'Update` attribute
- All Ada 2022 features in the SPARK 2022 subset not otherwise excluded
- `pragma Assert`
- `pragma Inline`
- `pragma Pack`

**Rationale:** These features form the core of a useful systems programming language — rich numeric types for hardware modelling, records and arrays for data structures, access types with ownership for dynamic data structures (linked lists, trees, buffer pools), static tasks and channels for safe concurrency, and expression functions for concise pure computations. String handling is limited to fixed-length arrays, which is acceptable for systems programming and avoids unbounded heap allocation. Goto is retained because SPARK allows it and it is trivially compilable. All foreign language interface is excluded from this specification (see D24).

### D24. System Sublanguage — Not Specified

**Decision:** C foreign function interface (`pragma Convention`, `pragma Import`, `pragma Export`), raw memory access, inline assembly, volatile MMIO, unchecked conversions, and other unsafe capabilities are excluded from the Safe language. They are not specified in this document.

**Rationale:** The safe language must be hermetically safe — no construct in the safe language can introduce unverifiable behaviour. A single `pragma Import` of a C function creates an unverifiable hole in the Silver guarantee, since foreign code cannot be analysed by the language's verification rules. A future system sublanguage specification may provide controlled, auditable access to unsafe capabilities through explicitly scoped regions, similar to Go's `unsafe` package or Rust's `unsafe` blocks. That specification is a separate document with its own design process. This specification defines only the safe floor.

### D26. Guaranteed Bronze and Silver Assurance

**Decision:** Every conforming Safe program shall have the following language-level assurance properties, without developer-supplied verification annotations:

**Stone:** Every conforming Safe program is expressible as valid SPARK 2022 source. This is true by construction — every Safe construct maps to a SPARK-legal Ada construct.

**Bronze:** Every conforming Safe program has complete and correct flow information (`Global`, `Depends`, `Initializes`) derivable from its source without user-supplied annotations. The language's restrictions (no aliasing violations due to ownership rules, no dispatching, no exceptions) make dependency analysis straightforward and automatable.

**Silver (hard rejection rule):** Every conforming Safe program is free of runtime errors. Safe guarantees Silver through four language rules specified in D27:

1. Wide intermediate arithmetic — integer overflow is impossible in expressions.
2. Strict index typing — array index types must match or be subtypes of the array's index type.
3. Division-by-provably-nonzero-divisor — the divisor in `/`, `mod`, and `rem` must be provably nonzero at compile time (by type, static value, or checked conversion).
4. Not-null dereference — dereference of an access value requires the access subtype to be `not null`.

These rules ensure that every runtime check in a conforming Safe program is provably safe from static type and range information derivable from the program text (including subtype bounds, static expressions, and checked conversions). No developer annotations are needed.

**Hard rejection rule:** If a conforming implementation cannot establish, from the specification's type rules and D27 legality rules, that a required runtime check will not fail, the program is nonconforming and the implementation shall reject it with a diagnostic. There is no "developer must restructure" advisory — failure to satisfy any Silver-level proof obligation is a compilation error, not a warning.

**Concurrency safety:** The channel-based tasking model (D28) provides additional safety guarantees as language properties:

- **Data race freedom:** No shared mutable state between tasks. All inter-task communication is through channels. The implementation verifies this via effect analysis on task bodies.
- **Priority inversion avoidance:** When mapping channels to underlying synchronisation mechanisms, the implementation should use ceiling priority rules (or equivalent) to prevent priority inversion. This does not, by itself, guarantee application-level deadlock freedom for arbitrary blocking channel programs. Deadlock freedom depends on the program's communication topology — specifically, on the absence of circular blocking dependencies between tasks and channels. The language does not currently specify restrictions sufficient to guarantee deadlock freedom statically. This is noted as a potential area for future specification work (see TBD register).

**Gold and Platinum (out of scope):** Functional correctness and full formal verification require developer-authored specifications (postconditions stating functional intent, ghost code, lemmas). These are inherently non-automatable and are out of scope for the language specification.

### D27. Silver-by-Construction: Arithmetic, Indexing, and Division Rules

**Decision:** The following four legality and semantic rules guarantee that every conforming Safe program is free of runtime errors (Absence of Runtime Errors):

**Rule 1: Wide Intermediate Arithmetic**

All integer arithmetic expressions are evaluated in a mathematical integer type with no overflow. Range checks are performed only when the result is:

- Assigned to an object
- Passed as a parameter
- Returned from a function

If the static range of any declared type in the program exceeds 64-bit signed range, the implementation shall reject the program. This is a legality rule, not a silent truncation. In practice, all Safe integer types will fit within 64 bits.

**Intermediate overflow legality rule:** For types whose range fits within 32 bits, intermediate wide arithmetic cannot overflow for single operations. For chained operations or types with larger ranges (e.g., products of two values near the 32-bit boundary), intermediate subexpressions may approach the 64-bit bounds. If a conforming implementation cannot establish (by sound static range analysis) that every intermediate subexpression stays within 64-bit signed range, the expression shall be rejected with a diagnostic. This ensures the "no intermediate overflow" guarantee holds universally, not just for small-range types. Narrowing checks at assignment, return, and parameter points are discharged via sound static range analysis on the wide result. Interval analysis is one permitted technique; no specific analysis algorithm is mandated.

For example, `A + B` where `A, B : Reading` (0..4095) computes in a wide intermediate type — the intermediate result 8190 does not overflow, and a range check fires only when the result is narrowed to `Reading` at an assignment, return, or parameter point.

Example:

```ada
public type Reading is range 0 .. 4095;

public function Average (A, B : Reading) return Reading is
begin
    return (A + B) / 2;  -- wide intermediate: max (4095+4095)/2 = 4095
                          -- range check at return: provably in 0..4095
end Average;
```

**Rule 2: Strict Index Typing**

The index expression in an array indexing operation shall be of a type or subtype that is the same as, or a subtype of, the array's index type. If the index expression's type is wider than the array's index type, the program is rejected at compile time.

This guarantees that every array index check is dischargeable by the prover — the index value is constrained by its type to be within the array bounds.

Example:

```ada
public type Channel_Id is range 0 .. 7;
Table : array (Channel_Id) of Integer;

-- Legal: index type matches array index type
public function Lookup (Ch : Channel_Id) return Integer is
begin
    return Table(Ch);  -- Silver-provable: Ch is in 0..7 by type
end Lookup;

-- ILLEGAL: index type wider than array index type
public function Bad_Lookup (N : Integer) return Integer is
begin
    return Table(N);  -- compile error: Integer is not a subtype of Channel_Id
end Bad_Lookup;
```

The programmer narrows at the call site after a bounds check:

```ada
if N in Channel_Id.First .. Channel_Id.Last then
    Result := Lookup(Channel_Id(N));  -- conversion provably valid inside the if
end if;
```

**Rule 3: Division by Provably Nonzero Divisor**

The right operand of the operators `/`, `mod`, and `rem` shall be provably nonzero at compile time. A conforming implementation shall accept a divisor expression as provably nonzero if any of the following conditions holds:

(a) The divisor expression has a type or subtype whose range excludes zero (the preferred mechanism — e.g., `Positive`, `Channel_Count`).
(b) The divisor expression is a static expression (8652:2023 §4.9) whose value is nonzero (e.g., a literal `2`, a named number `Divisor : constant := 3;`, a static constant).
(c) The divisor expression is an explicit conversion to a nonzero subtype where the conversion is provably valid at that program point (e.g., `Positive(B)` inside an `if B > 0` branch).

If none of these conditions holds, the program is rejected at compile time.

This guarantees that every division-by-zero check is dischargeable — the divisor value is constrained to be nonzero either by its type, by its static value, or by a narrowing conversion the implementation can verify.

The language provides standard subtypes that exclude zero:

```ada
subtype Positive is Integer range 1 .. Integer.Last;
subtype Negative is Integer range Integer.First .. -1;
```

Example (static nonzero literal — condition b):

```ada
public function Average (A, B : Reading) return Reading is
begin
    return (A + B) / 2;  -- divisor 2 is a static nonzero expression: legal
                          -- wide intermediate: max (4095+4095)/2 = 4095
                          -- range check at return: provably in 0..4095
end Average;
```

Example (named number — condition b):

```ada
Sample_Count : constant := 4;  -- named number, static, nonzero

public function Quarter_Sum (Total : Integer) return Integer is
begin
    return Total / Sample_Count;  -- static nonzero divisor: legal
end Quarter_Sum;
```

Example (nonzero type — condition a):

```ada
public type Seconds is range 1 .. 3600;

-- Legal: Seconds excludes zero
public function Rate (Distance : Meters; Time : Seconds) return Integer is
begin
    return Distance / Time;  -- Silver-provable: Time >= 1 by type
end Rate;

-- ILLEGAL: Integer includes zero
public function Bad_Divide (A, B : Integer) return Integer is
begin
    return A / B;  -- compile error: Integer range includes zero
end Bad_Divide;
```

The programmer handles the zero case explicitly:

```ada
public function Safe_Divide (A, B : Integer) return Integer is
begin
    if B > 0 then
        return A / Positive(B);   -- Positive excludes zero, provably valid here
    elsif B < 0 then
        return A / Negative(B);   -- Negative excludes zero, provably valid here
    else
        return 0;                 -- zero case handled explicitly
    end if;
end Safe_Divide;
```

**Rule 4: Not-Null Dereference**

Dereference of an access value — whether explicit (`.all`) or implicit (selected component through an access value) — shall require the access subtype to be `not null`. If the access subtype at the point of dereference does not exclude null, the program is rejected at compile time.

Every access type declaration produces two usable forms: a nullable one for storage and a non-null one for dereference:

```ada
public type Node;
public type Node_Ptr is access Node;            -- nullable, for storage
public subtype Node_Ref is not null Node_Ptr;   -- non-null, for dereference
```

Example:

```ada
-- Legal: Node_Ref excludes null, dereference provably safe
public function Value_Of (N : Node_Ref) return Integer
is (N.Value);

-- ILLEGAL: Node_Ptr includes null
public function Bad_Value (N : Node_Ptr) return Integer
is (N.Value);  -- compile error: dereference of nullable access type

-- Narrowing after null check:
public function Safe_Value (N : Node_Ptr; Default : Integer) return Integer is
begin
    if N /= null then
        Ref : Node_Ref := Node_Ref(N);  -- conversion provably valid here
        return Ref.Value;                 -- legal: Node_Ref excludes null
    else
        return Default;
    end if;
end Safe_Value;
```

This is consistent with D27's philosophy throughout: `not null access` is to null dereference what `Positive` is to division by zero — the type carries the proof. Null comparison (`= null`, `/= null`) is always legal on any access type; only dereference requires the not-null guarantee.

**Combined effect:** These four rules ensure that the six categories of runtime check — overflow, range, index, division-by-zero, null dereference, and discriminant — are all dischargeable from static type and range information derivable from the program text:

| Check                                | How discharged                                                        |
| ------------------------------------ | --------------------------------------------------------------------- |
| Integer overflow                     | Impossible — wide intermediate arithmetic                             |
| Range on assignment/return/parameter | Sound static range analysis on wide intermediates                     |
| Array index out of bounds            | Index type matches array index type                                   |
| Division by zero                     | Divisor is provably nonzero (type, static value, or checked conversion) |
| Null dereference                     | Access subtype is `not null` at every dereference                     |
| Discriminant                         | Discriminant type is discrete and static (from D23 retained features) |

**Ergonomic impact:** The rules push the programmer toward tighter types — `Positive` instead of `Integer` for counts, `Channel_Id` instead of `Integer` for indices, `Seconds` instead of `Integer` for durations, `Node_Ref` instead of `Node_Ptr` for dereference. In every case this produces better, more self-documenting code. The friction is limited to explicit narrowing conversions when crossing type boundaries after a conditional check, which is where the programmer should be making a conscious decision about bounds, nullability, or validity anyway.

**Rationale:** Silver-by-construction is the language's defining feature. The developer writes zero verification annotations — no contracts, no `Global`, no `Depends`, no preconditions. The type system and these four rules guarantee both Bronze and Silver SPARK assurance automatically. This removes the single biggest barrier to formal verification adoption: the annotation burden.

### D28. Static Tasks and Typed Channels

**Decision:** Safe provides concurrency through static tasks and typed channels as first-class language constructs. Tasks are declared at package level and create exactly one task each. Channels are typed, bounded-capacity, blocking FIFO queues declared at package level. Tasks communicate exclusively through channels — no shared mutable state between tasks.

**Task declarations:**

A task is declared at package level with an optional static priority and a body:

```ada
task Sensor_Reader with Priority => 10 is
begin
    loop
        R : Reading := Read_ADC (0);
        send Readings, R;
    end loop;
end Sensor_Reader;
```

Tasks begin executing when the program starts, after all package-level initialization is complete. Each task declaration creates exactly one task — no dynamic spawning, no task types, no task arrays. Tasks shall not terminate.

**Non-termination legality rule:** The outermost statement of a task body's `handled_sequence_of_statements` shall be an unconditional `loop` statement (`loop ... end loop;`). Declarations may precede the loop. A `return` statement shall not appear anywhere within a task body. No `exit` statement within the task body shall name or otherwise target the outermost loop. A conforming implementation shall reject any task body that violates these constraints. This is a syntactic restriction checkable without control-flow or whole-program analysis.

**Rationale (static, non-terminating tasks):** Dynamic task creation (Go's `go f()`) prevents static analysis of the task set — you cannot count tasks, assign ceiling priorities, prove resource bounds, or verify deadlock freedom if the number of tasks is unknown at compile time. Tasks run forever once started, which simplifies resource analysis and prevents dangling references to task-owned state. Every task in a Safe program is visible by reading the source — you can enumerate the entire concurrent architecture from the package declarations. This is the right tradeoff for systems programming, where the set of concurrent activities (interrupt handlers, device drivers, protocol stacks, schedulers) is known at design time.

**Channel declarations:**

A channel is a typed, bounded FIFO queue:

```ada
channel Readings : Reading capacity 16;
channel Commands : Command capacity 4;
```

The element type must be a definite type (not unconstrained). The capacity is a static expression — known at compile time, so the required storage bound for any channel is fixed for a given program. The allocation strategy (static, pre-allocated heap, or other) is implementation-defined. Channels may be declared `public` for cross-package communication.

**Channel operations:**

```ada
send Ch, Value;                     -- blocking: enqueue Value, block if Ch full
receive Ch, Variable;               -- blocking: dequeue into Variable, block if Ch empty
try_send Ch, Value, Success;        -- non-blocking: Success is Boolean
try_receive Ch, Variable, Success;  -- non-blocking: Success is Boolean
```

`send` and `receive` are statements, not expressions. They block the current task (not the whole program) until the operation can complete. `try_send` and `try_receive` never block — they set a `Boolean` indicating success.

**Rationale (channels):** Channels replace protected objects as the user-visible communication mechanism. A protected object is a monitor with entries, barriers, and the ceiling priority protocol — powerful but complex. A channel is a bounded buffer with send and receive — simple, composable, and familiar to anyone who has used Go, Erlang, or Unix pipes. The programmer sees channels; the language guarantees data-race freedom by construction. Deadlock freedom depends on the program's communication topology and is not guaranteed by the language rules alone.

**Select statement:**

Multiplex across multiple channel receive operations with an optional timeout:

```ada
select
    when Msg : Message from Incoming =>
        Process (Msg);
    or when Cmd : Command from Commands =>
        Handle (Cmd);
    or delay 1.0 =>
        Heartbeat;
end select;
```

Each arm is either a channel receive or a delay timeout. The select blocks until one arm is ready, then executes that arm's statements.

**Arm selection semantics:** When the select statement is evaluated, the implementation tests each arm in declaration order (top to bottom). The first arm whose channel has data available is selected. If no channel arm is ready and a delay arm is present, the implementation waits until either a channel arm becomes ready or the delay expires, whichever occurs first. If the delay expires, the delay arm is selected. If multiple channels become ready simultaneously (e.g., data arrives on two channels between scheduling quanta), the first listed channel arm wins. This is deterministic — arm ordering in source code determines priority. There is no random selection as in Go's `select`.

**Starvation:** A channel whose arm is listed later in a select may be starved if earlier arms are always ready. This is by design — it gives the programmer explicit priority control via declaration order. If fairness is needed, the programmer can use separate tasks or rotate through channels in application logic.

**Restrictions on select:** Only receive operations appear in select arms, not send. This is a deliberate restriction — select-on-send creates priority inversion scenarios and makes deadlock analysis substantially harder. Go allows select-on-send but it is a common source of subtle bugs.

**No shared mutable state between tasks:**

This is the critical safety rule. Each package-level variable must be accessed by at most one task. The implementation checks this at compile time — it is an extension of effect analysis applied across task boundaries.

```ada
Cal_Offset : Reading := 0;  -- owned by Sensor_Reader (only it accesses this)

task Sensor_Reader is
begin
    loop
        R : Reading := Read_ADC (0) + Cal_Offset;  -- legal: owns Cal_Offset
        send Readings, R;
    end loop;
end Sensor_Reader;

task Processor is
begin
    loop
        R : Reading;
        receive Readings, R;
        -- Cal_Offset := 10;  -- ILLEGAL: Cal_Offset owned by Sensor_Reader
    end loop;
end Processor;
```

Variables not accessed by any task remain accessible to non-task subprograms. A subprogram called from a task body may access only the variables owned by that task (transitively checked through the call graph).

**Rationale (no shared state):** Data races are the primary source of concurrency bugs. Go's motto is "share memory by communicating, don't communicate by sharing memory." Safe enforces this at compile time. The result is that every inter-task data flow is visible as a channel operation — auditable, analysable, and provable.

**Non-termination requirement:**

Tasks shall not terminate — every task runs forever once started.

The non-termination legality rule (stated in the task declarations section above) requires that: (a) the outermost statement of the task body is an unconditional `loop ... end loop;`, (b) no `return` statement appears anywhere in the task body, and (c) no `exit` statement names or targets the outermost loop. Declarations may precede the outermost loop. Inner loops within the task body may contain `exit` statements targeting those inner loops.

This is a conservative syntactic restriction. Some theoretically non-terminating forms (e.g., `while True loop ... end loop;`) are excluded because "non-terminating" is not decidable in general; the unconditional `loop` form is trivially checkable by any implementation. The restriction may be relaxed in future revisions if experience shows it is too limiting.

This simplifies resource analysis: task-owned package variables remain accessible for the lifetime of the program, and channel endpoints are always active.

**Grammar additions (\~12 new productions):**

```
channel_declaration ::=
    [ 'public' ] 'channel' identifier ':' type_mark
        'capacity' static_expression ';'

task_declaration ::=
    'task' identifier [ 'with' 'Priority' '=>' static_expression ] 'is'
    'begin'
        handled_sequence_of_statements
    'end' identifier ';'

send_statement ::=
    'send' channel_name ',' expression ';'

receive_statement ::=
    'receive' channel_name ',' name ';'

try_send_statement ::=
    'try_send' channel_name ',' expression ',' name ';'

try_receive_statement ::=
    'try_receive' channel_name ',' name ',' name ';'

select_statement ::=
    'select'
        select_arm
    { 'or' select_arm }
    'end' 'select' ';'

select_arm ::=
    channel_arm | delay_arm

channel_arm ::=
    'when' identifier ':' type_mark 'from' channel_name '=>'
        sequence_of_statements

delay_arm ::=
    'delay' expression '=>'
        sequence_of_statements
```

---

## Specification Document Structure

Produce the specification as Markdown files:

```
spec/
  00-front-matter.md
  01-base-definition.md
  02-restrictions.md
  03-single-file-packages.md
  04-tasks-and-channels.md
  05-assurance.md
  06-conformance.md
  07-annex-a-retained-library.md
  07-annex-b-impl-advice.md
  08-syntax-summary.md
```

### 00-front-matter.md

- Title, working language name (Safe), file extension (`.safe`)
- Scope statement
- Normative references: ISO/IEC 8652:2023
- Terms and definitions (reference 8652:2023 §1.3, state only additions/modifications)
- Method of description (reference 8652:2023 §1.1.4 — use their BNF notation)
- Summary of design decisions (reference this document's D1–D28)
- **TBD Register** — the following items are acknowledged as unresolved and reserved for future specification revisions. Each item should be resolved before baselining. When resolution ownership is assigned, annotate each item with: owner, resolution plan, and target milestone.
  - Target platform constraints beyond "Ada compiler exists"
  - Performance targets (compile time, proof time, code size)
  - Memory model constraints (stack bounds, heap bounds, allocation failure handling)
  - Floating-point semantics beyond inheriting Ada's
  - Diagnostic catalog and localization
  - `Constant_After_Elaboration` aspect — determine whether required for concurrency analysis
  - Abort handler behavior (language-defined or implementation-defined)
  - AST/IR interchange format (if any)
  - Deadlock freedom: determine whether additional language restrictions (e.g., static communication topology analysis, channel-dependency ordering, prohibition of blocking send) can provide a language-level deadlock-freedom guarantee. Currently, only data-race freedom is guaranteed by construction.
  - Numeric model: required ranges/representation assumptions for predefined integer types given the 64-bit signed bound in D27 Rule 1
  - Automatic deallocation semantics for owned access objects (ordering at scope exit, interaction with early return/goto, multiple owned objects exiting scope simultaneously)
  - Modular arithmetic wrapping semantics: Safe retains modular types (D23) but D27's wide intermediate arithmetic applies only to signed integer types. Modular types wrap silently by Ada's definition. Evaluate whether non-wrapping should be the default for modular types (with explicit opt-in for intentional wrapping), extending Silver coverage to modular arithmetic. SPARK 21 (`No_Wrap_Around`) and SPARK 25 (`No_Bitwise_Operations`) provide design precedent. High priority — natural extension of D27's philosophy.
  - Limited/private type views across packages: D7 prohibits circular `with` dependencies to simplify elaboration ordering. SPARK 26's `with type` mechanism provides named type views without full package dependency, which could relax this restriction surgically without creating elaboration-order hazards. Evaluate whether a limited type-view mechanism fits Safe's single-file package model.
  - Partial initialisation facility: Safe currently requires full initialisation at declaration (supporting the Silver guarantee without contracts). For systems-programming patterns (buffers, arenas, staged construction), evaluate whether a Safe-level uninitialised/maybe-initialised facility can preserve Silver without requiring developer-authored proof annotations. SPARK 21–24's `Relaxed_Initialization` and `Initialized` aspects provide design precedent. Note: this may require a proof mechanism Safe currently lacks; feasibility depends on whether initialisation can be tracked through Safe's type system alone.
- **Normative/informative status**: State this file's status (normative). State that §07-annex-b is informative. State that all code examples are non-normative unless explicitly labeled otherwise.

### 01-base-definition.md

Short (half a page):

> The Safe language is defined as ISO/IEC 8652:2023, as restricted by Section 2 and modified by Sections 3–4 of this document.
> 
> All syntax, legality rules, static semantics, dynamic semantics, and implementation requirements of 8652:2023 apply except where explicitly excluded or modified.

### 02-restrictions.md

For every exclusion:

1. Cite the specific 8652:2023 section and paragraph numbers.
2. State the legality rule: "A conforming implementation shall reject [construct]."
3. Group by 8652:2023 section number.

Use this structure for each item:

```markdown
#### 9.1–9.11 Full Ada Tasking

**8652:2023 Reference:** Sections 9.1 through 9.11

**Legality Rule:** Task types, task entries, accept statements, all
forms of select on entries, abort statements, requeue, and user-declared
protected types are not permitted. A conforming implementation shall reject
any task_type_declaration, entry_declaration, accept_statement,
selective_accept, abort_statement, or requeue_statement.

**Note:** Safe provides a restricted concurrency model (D28) via static
task declarations and typed channels.

**Related exclusions:**
- Real-time annexes D.1–D.14 — excluded except task priorities
- Ada.Task_Identification — excluded
- Ada.Synchronous_Task_Control — excluded (channels replace suspension objects)
```

Do this for every exclusion. Be exhaustive. Cross-reference related exclusions.

**Attribute notation change:** State that all 8652:2023 attribute references using tick notation (`X'Attr`) are replaced by dot notation (`X.Attr`) in Safe. Provide the complete list of retained attributes using dot notation. State that qualified expressions (`T'(Expr)`) are replaced by type annotation syntax (`Expr : T`).

**Silver-by-construction rules (D27):** These are new legality rules with no 8652:2023 precedent. Specify each precisely:

1. **Wide intermediate arithmetic:** All integer arithmetic expressions are evaluated in a mathematical integer type. Range checks are performed only at assignment, parameter passing, and return. Reference how this modifies the dynamic semantics of 8652:2023 §4.5 (Operators and Expression Evaluation).

2. **Strict index typing:** The index expression in an indexed\_component (8652:2023 §4.1.1) shall be of a type or subtype that is the same as, or a subtype of, the array's index type. A conforming implementation shall reject any indexed\_component where this is not statically determinable.

3. **Division by provably nonzero divisor:** The right operand of `/`, `mod`, and `rem` (8652:2023 §4.5.5) shall be provably nonzero at compile time. Accepted proofs: (a) divisor type/subtype range excludes zero, (b) divisor is a static expression (8652:2023 §4.9) whose value is nonzero, (c) divisor is an explicit conversion to a nonzero subtype that is provably valid at that program point. A conforming implementation shall reject any division, `mod`, or `rem` operation where none of these conditions holds. Document the language-defined subtypes `Positive` and `Negative` as standard nonzero types.

4. **Not-null dereference:** Dereference of an access value — explicit `.all` or implicit selected component through an access — shall require the access subtype to be `not null` (8652:2023 §3.10). A conforming implementation shall reject any dereference where the access subtype does not exclude null. Document the `not null` subtype pattern: `type T_Ptr is access T; subtype T_Ref is not null T_Ptr;`.

**Access types and ownership:** Specify the retained SPARK 2022 ownership model:

- All access-to-object type kinds supported by SPARK 2022 are retained with SPARK ownership rules:
  - Pool-specific access-to-variable types (`access T`)
  - Anonymous access-to-variable types (for local borrowing and traversal functions)
  - Anonymous access-to-constant types (for local observing)
  - Named access-to-constant types (`access constant T`) — exempt from ownership checking
  - General access-to-variable types (`access all T`) — subject to ownership checking
- Access-to-subprogram types are excluded — a conforming implementation shall reject any access-to-subprogram type declaration
- `Unchecked_Access` attribute is excluded
- `Unchecked_Deallocation` is excluded
- `'Access` attribute is retained for uses consistent with SPARK 2022 ownership rules
- Specify Safe ownership rules directly and self-containedly within this LRM. Use SPARK RM/UG §5.9 as informative design precedent, but do not define Safe semantics by reference to SPARK documents. State how Safe ownership rules apply in Safe's single-file package model.

**Contract exclusions:** List every excluded contract aspect with a reference to its 8652:2023 or SPARK RM definition and the rationale "replaced by pragma Assert; Bronze and Silver assurance guaranteed by D26/D27 language rules."

**Pragma inventory:** Provide the complete list of 8652:2023 language-defined pragmas with retained/excluded status for each.

**Attribute inventory:** Provide the complete list of 8652:2023 language-defined attributes with retained/excluded status, noting the dot notation change for all retained attributes.

### 03-single-file-packages.md

Full specification of the single-file package model. Use Ada RM section conventions:

- **Syntax** — complete BNF for `package_unit` and the interleaved declarations within subprogram bodies
- **Legality Rules** — numbered, covering:
  - Matching end identifier
  - Declaration-before-use strictly enforced
  - Forward declarations for mutual recursion
  - No package-level statements
  - `public` keyword visibility rules
  - Opaque types (`public type T is private record`)
  - Dot notation for attributes (full specification of how `X.Name` resolves: record field vs. attribute, checked at compile time by type)
  - Type annotation syntax (`Expr : T`) — precedence, where parentheses are required
- **Static Semantics** — define what interface information a conforming implementation must make available for separate compilation and cross-unit legality checking:
      - Visibility: which declarations are `public`
      - Types: size and alignment for opaque types (clients can declare objects but not access fields)
      - Subprogram signatures: parameter profiles for all exported subprograms
      - Effect summaries: for each exported subprogram, a conservative interprocedural summary (including transitive callees) of the package-level variables read and written. This is needed for callers to compute their own flow information and for task-variable ownership checking across packages. The summary may be conservatively over-approximate; precision may improve over time without affecting conformance.
      - If required dependency interface information is unavailable, the program shall be rejected
      - The mechanism for conveying this information (e.g., symbol files, compiler databases) is implementation-defined
- **Dynamic Semantics** — variable initializers evaluated at load time in declaration order; no elaboration-time code
- **Implementation Requirements** — interface information mechanism requirements (implementation-defined). Do not mandate incremental recompilation in normative text; performance/build-system advice belongs in Annex B (informative).
- **Examples** — at least four complete packages:
  - A simple package with public types and functions
  - A package with opaque types
  - Two packages where one depends on the other via with-clause
  - A package demonstrating interleaved declarations in subprogram bodies, dot notation for attributes, and type annotation syntax

### 04-tasks-and-channels.md

Full specification of Safe's concurrency model.

- **Task declarations** — syntax, static constraints (one task per declaration, package-level only), priority assignment, task body scoping rules
- **Channel declarations** — syntax, element type constraints (must be definite), capacity as static expression (storage bound fixed at compile time; allocation strategy is implementation-defined)
- **Channel operations** — `send`, `receive`, `try_send`, `try_receive` semantics, blocking behavior, interaction with task priorities
- **Select statement** — syntax, receive-only restriction, deterministic arm selection (first-ready wins), delay timeout semantics
- **Task-variable ownership** — the no-shared-mutable-state rule as a legality rule: each package-level variable shall be accessed by at most one task (transitively through the call graph). Specify that cross-package transitivity uses effect summaries from dependency interface information (see §03 Static Semantics). The ownership check shall be completable from the compilation unit's source plus its direct and transitive dependency interface information, without access to dependency source code.
- **Non-termination legality rule** — the outermost statement of a task body shall be an unconditional `loop ... end loop;`; declarations may precede the loop; `return` shall not appear anywhere in a task body; no `exit` shall target the outermost loop; inner loops may contain `exit` targeting those inner loops; this is a syntactic restriction checkable without control-flow analysis
- **Task startup** — ordering relative to package initialization: all package-level declarations and initializations complete before any task begins execution. The order of package initialization is implementation-defined but deterministic for a given program. Include an informative note (or cross-reference to Annex B) explaining that when targeting Ada/SPARK tasking under Ravenscar or Jorvik profile restrictions, `pragma Partition_Elaboration_Policy(Sequential)` is the standard mechanism for ensuring library-level task activation is deferred until all library units are elaborated. This note is informative — the normative requirement is the language-level guarantee stated above.
- **Examples** — producer/consumer, router/worker, command/response patterns

### 05-assurance.md

Full specification of the language-level assurance guarantees. This is the language's defining feature — the developer writes zero verification annotations and gets both Bronze and Silver assurance automatically.

- **Overview** — explain the assurance levels (Stone through Platinum) and what Safe guarantees at each level
- **Bronze Guarantee** — state the normative guarantee as a language property: every conforming Safe program has complete and correct flow information (`Global`, `Depends`, `Initializes`) derivable without user-supplied annotations
- **Concurrency Assurance** — specify how the tasking model provides:
  - Data race freedom: no shared mutable state between tasks (all inter-task communication via channels)
  - Priority inversion avoidance: ceiling priority rules on channel-backing synchronisation mechanisms (informative mapping consideration)
      - Note explicitly that application-level deadlock freedom is NOT guaranteed by the language rules for arbitrary blocking channel programs. Explain the circular-wait risk with blocking sends/receives on bounded channels. State that deadlock freedom is a program-level property dependent on communication topology, not a language-level guarantee.
  - Task-variable ownership: effect summaries on task bodies reference only owned variables and channel operations
- **Silver Guarantee** — specify how D27's four language rules guarantee Absence of Runtime Errors (AoRTE):
  - Wide intermediate arithmetic: explain the mathematical integer evaluation model
  - Strict index typing: explain how the index subtype matching rule guarantees all array index checks are dischargeable
  - Division by provably nonzero divisor: explain how the three-condition rule (nonzero type, static nonzero value, checked conversion) guarantees all division-by-zero checks are dischargeable
  - Not-null dereference: explain how the `not null` access subtype rule guarantees all null dereference checks are dischargeable
  - Range checks at narrowing points: explain how sound static range analysis on wide intermediates makes these decidable. Interval analysis is one permitted technique; do not mandate a specific algorithm in normative text.
  - Provide a complete enumeration of all runtime check categories and how each is discharged
  - State the hard rejection rule: if a conforming implementation cannot establish absence of a required runtime check failure from the specification's type rules and D27 legality rules, the program is nonconforming and the implementation shall reject it with a diagnostic
- **`Depends` over-approximation note:** Implementation-derived `Depends` information may be conservatively over-approximate (listing more dependencies than actually exist). An implementation may refine precision over time without affecting conformance.
- **Gold and Platinum** — state these are out of scope
- **Examples** — show Safe source files illustrating:
  - Arithmetic that is Silver-provable via wide intermediates
  - Array indexing that is Silver-provable via strict index typing
  - Division that is Silver-provable via nonzero divisor types
  - Access type dereference that is Silver-provable via not-null subtypes
  - Ownership: move, borrow, observe patterns with access types
  - A rejected program (index type too wide, divisor type includes zero, nullable dereference) with identification of the violated D27 rule for each rejection
  - A concurrent program with tasks and channels demonstrating data-race freedom and task-variable ownership
      - An informative note showing a communication topology that WOULD deadlock (circular blocking sends on full channels) to illustrate why deadlock freedom is a program-level, not language-level, property

### 06-conformance.md

**Normative conformance requirements** (defined in terms of language properties, not specific tools):

- A conforming implementation shall provide a mechanism for separate compilation of units and combination of separately compiled units into a program. The mechanism is implementation-defined.
- What constitutes a conforming implementation:
  - A conforming implementation shall accept all conforming programs and reject all non-conforming programs with a diagnostic
  - A conforming implementation shall implement the dynamic semantics correctly for all conforming programs
  - A conforming implementation shall enforce all legality rules defined in this specification, including D27 Rules 1–4
  - No mention of specific compilers or provers in the normative conformance definition
- What constitutes a conforming program — a program is conforming if and only if the implementation can establish, from the specification's type rules and D27 legality rules, that all required runtime checks are dischargeable. A program for which any runtime check cannot be so established is nonconforming and shall be rejected with a diagnostic.
- Language-level assurance guarantees (expressed as language properties, not tool invocations):
  - **Representability:** Every conforming Safe program uses only constructs defined by ISO/IEC 8652:2023 as restricted and modified by this specification. (Informative note: this means every conforming Safe program has a natural mapping to valid Ada 2022 / SPARK 2022 source, but the mapping is an implementation concern, not a conformance requirement.)
  - **Bronze:** Every conforming Safe program has sufficient flow analysis information (Global, Depends, Initializes) to pass flow analysis without user-supplied annotations
  - **Silver:** Every conforming Safe program is free of runtime errors — all runtime checks (overflow, range, index, division-by-zero, null dereference, discriminant) are dischargeable from static type and range information derivable from the program text, combined with D27 legality rules
- **Conformance levels:** To preserve the safety story through standards refactoring, define two conformance levels:
  - **Safe/Core:** Language rules and legality checking only — a conforming implementation accepts all conforming programs and rejects all non-conforming programs
  - **Safe/Assured:** Language rules plus verification that every conforming program is free of runtime errors (the Silver guarantee expressed as a language property, validatable by any suitable method — not tied to a specific prover)

### 07-annex-a-retained-library.md

Walk through 8652:2023 Annex A and for each library unit state: retained, excluded, or modified. Provide rationale for each exclusion. Note that Annex B (Interface to Other Languages) is excluded in its entirety — C FFI is outside the scope of this specification (D24).

### 07-annex-b-impl-advice.md

**Drafting note:** This annex is informative. Use "should" rather than "shall" throughout. Content for this annex (symbol file format, diagnostic messages, incremental recompilation, and other implementation guidance) is maintained in `DEFERRED-IMPL-CONTENT.md` and should be incorporated during the drafting of this annex.

### 08-syntax-summary.md

Complete consolidated BNF grammar for Safe. Target: approximately 140–160 productions. This is the authoritative grammar. Must reflect:

- Flat package structure with `public` annotation
- No `package body`, no `begin...end` at package level
- Interleaved declarations and statements in subprogram bodies
- Dot notation for attributes (no tick)
- Type annotation syntax (no qualified expressions)
- `pragma Assert` as the only assertion mechanism
- Task declarations with priority aspect
- Channel declarations with capacity
- `send`, `receive`, `try_send`, `try_receive` statements
- `select` statement with channel receive arms and delay arm
- Access type declarations (all access-to-object kinds per SPARK 2022 ownership model), `not null` subtypes, allocators
- All exclusions from 02-restrictions.md (access-to-subprogram excluded; all access-to-object kinds retained)

---

## Editorial Conventions

1. **Paragraph numbering**: Number every normative paragraph sequentially within each section.

2. **Cross-references**: Cite 8652:2023 by section and paragraph: "8652:2023 §3.10(1)". Never reproduce 8652 text — reference it.

3. **BNF notation**: Use 8652:2023 §1.1.4 conventions:
   2. `::=` for productions
   3. `[ ]` for optional
   4. `{ }` for zero or more
   5. `|` for alternation
   6. Keywords in **bold**
   7. Nonterminals in *italic* or `snake_case`

4. **Section structure** per feature:
   2. Syntax
   3. Legality Rules
   4. Static Semantics
   5. Dynamic Semantics
   6. Implementation Requirements
   7. Examples

5. **Normative voice**: "shall" for requirements, "may" for permissions, "should" for recommendations.

6. **Example conformance**: All code examples in the specification shall be conforming programs under the stated legality rules (including D27 Rules 1–4). If an example is intentionally nonconforming (e.g., to illustrate a required diagnostic), it shall be explicitly labeled "Nonconforming Example" and accompanied by identification of the violated rule and the source location of the violation. Do not mandate specific diagnostic wording in normative text.

7. **Tool independence**: No normative paragraph shall mandate invocation of a specific tool, compiler, or prover by name. Tool-specific guidance belongs exclusively in §07-annex-b (informative implementation advice). Normative requirements shall be expressed in terms of language properties, legality rules, and semantic guarantees.

---

## Reference Documents

Read these documents before and during drafting.

### Ada 2022 Reference Manual (normative base)

- HTML browsable (all sections): http://www.ada-auth.org/standards/22rm/html/RM-TOC.html
- PDF complete: http://www.ada-auth.org/standards/22rm/rm-final.pdf
- PDF with bookmarks: https://www.adaic.org/resources/add\_content/standards/22rm/rm-bar.pdf

### Annotated Ada Reference Manual (implementer annotations)

- HTML: http://www.ada-auth.org/standards/22aarm/html/AA-TOC.html
- PDF: https://www.adaic.org/resources/add\_content/standards/22aarm/aa-final.pdf

### SPARK Reference Manual (restriction model precedent)

- HTML: https://docs.adacore.com/spark2014-docs/html/lrm/
- PDF: https://docs.adacore.com/live/wave/spark2014/pdf/spark2014\_rm/spark2014\_rm.pdf

### SPARK User's Guide (feature inventory)

- HTML: https://docs.adacore.com/spark2014-docs/html/ug/en/spark\_2014.html
- PDF: https://docs.adacore.com/spark2014-docs/pdf/spark2014\_ug.pdf

### SPARK Release Notes (changelog)

- HTML: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/index.html

### Ada 2022 Overview (feature rationale)

- PDF: http://www.ada-auth.org/standards/22over/Ada2022-Overview.pdf

### Standards Portal

- http://ada-auth.org/standards/ada22.html
- https://www.adaic.org/ada-resources/standards/ada22/

---

## Workflow

Execute in this order:

1. Fetch and read the Ada 2022 RM Table of Contents to understand the full structure of 8652:2023.
2. Fetch and read the SPARK language overview (spark\_2014.html) to establish which Ada 2022 features SPARK retains.
3. Draft `02-restrictions.md` — walk every section of 8652:2023 and classify each construct as retained or excluded.
4. Draft `08-syntax-summary.md` — the complete Safe grammar. This forces precision on every syntactic decision.
5. Draft `03-single-file-packages.md` — the main structural change, including dot notation and type annotation syntax.
6. Draft `04-tasks-and-channels.md` — task declarations, channel declarations, send/receive, select, task-variable ownership.
7. Draft `05-assurance.md` — Bronze and Silver guarantee specification, concurrency assurance.
8. Draft `06-conformance.md` — implementation requirements.
9. Draft `07-annex-a-retained-library.md` — walk Annex A. Note Annex B (C interface) excluded entirely.
10. Draft `07-annex-b-impl-advice.md` — implementation advice.
11. Draft `01-base-definition.md` and `00-front-matter.md` last.

Commit each file as it is completed.

---

## Quick Reference: What Safe Looks Like

```ada
-- sensors.safe

with Interfaces;

package Sensors is

    public type Reading is range 0 .. 4095;

    public type Channel_Id is range 0 .. 7;

    public subtype Channel_Count is Integer range 1 .. 8;  -- excludes zero: valid divisor

    type Calibration is private record
        Scale  : Float := 1.0;
        Bias   : Integer := 0;
    end record;

    Cal_Table : array (Channel_Id) of Calibration :=
        (others => (Scale => 1.0, Bias => 0));

    Initialized : Boolean := False;

    public function Is_Initialized return Boolean
    is (Initialized);

    public procedure Initialize is
    begin
        Default_Cal : constant Calibration := (Scale => 1.0, Bias => 0);
        for I in Channel_Id.Range loop
            Cal_Table (I) := Default_Cal;
        end loop;
        Initialized := True;
    end Initialize;

    public function Get_Reading (Channel : Channel_Id) return Reading is
    begin
        pragma Assert (Initialized);
        Raw : Reading := Read_ADC (Channel);
        return Raw;  -- D27: no narrowing needed, already Reading type
    end Get_Reading;

    public function Average (A, B : Reading) return Reading is
    begin
        -- D27 Rule 1: wide intermediate, max (4095+4095)/2 = 4095
        -- D27 Rule 3(b): literal 2 is a static nonzero expression
        -- Narrowing at return: provably in 0..4095
        return (A + B) / 2;
    end Average;

    public function Scale (R : Reading; Divisor : Channel_Count) return Integer is
    begin
        -- D27 Rule 3(a): Channel_Count range 1..8 excludes zero
        -- Wide intermediate arithmetic handles mixed-type operands
        -- Returns Integer, no narrowing needed
        return Integer(R) / Divisor;
    end Scale;

    function Read_ADC (Channel : Channel_Id) return Reading is separate;
        -- body in sensors-read_adc.safe

end Sensors;
```

Note the following Safe features visible in this example:

- Single file, flat declaration list, no `package body`
- `public` keyword on exported declarations, everything else private
- `private record` for opaque type
- Subprogram bodies at point of declaration
- Interleaved declarations and statements after `begin`
- Dot notation for attributes: `Channel_Id.Range`, `Channel_Id.First`
- `pragma Assert` for runtime checks
- No contracts, no tick, no qualified expressions
- Variable initialization at declaration with expressions
- **D27 in action:** `Channel_Count` excludes zero, making it a legal divisor type (Rule 3a); literal `2` is a static nonzero expression, making `/ 2` legal (Rule 3b); `Channel_Id` used directly as array index (Rule 2: strict index typing); `Average` uses wide intermediate arithmetic with provably safe narrowing at return (Rule 1)

### Concurrency Example — Tasks and Channels

```ada
-- monitor.safe

with Sensors;

package Monitor is

    public type Alarm_Level is (None, Warning, Critical);

    channel Readings : Sensors.Reading capacity 32;
    channel Alarms   : Alarm_Level capacity 8;

    task Sampler with Priority => 10 is
    begin
        loop
            R : Sensors.Reading := Sensors.Get_Reading (0);
            send Readings, R;
            delay 0.1;
        end loop;
    end Sampler;

    Threshold : Sensors.Reading := 3000;  -- owned by Evaluator (only task accessing it)

    task Evaluator with Priority => 5 is
    begin
        loop
            R : Sensors.Reading;
            receive Readings, R;
            if R > Threshold then
                send Alarms, Critical;
            end if;
        end loop;
    end Evaluator;

    -- Public API: other packages read alarms via channel
    public function Next_Alarm return Alarm_Level is
    begin
        Level : Alarm_Level;
        receive Alarms, Level;
        return Level;
    end Next_Alarm;

end Monitor;
```

Note the following concurrency features visible in this example:

- Static tasks declared at package level, each with a priority
- Typed, bounded channels for inter-task communication
- `send` and `receive` as first-class statements
- Task-variable ownership: `Threshold` accessed only by `Evaluator`; implementation enforces exclusivity
- Public API exposes channel access through ordinary subprograms
- No shared mutable state, no locks, no protected objects visible to the programmer
