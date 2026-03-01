# Safe Language Specification — Drafter Prompt

## For use with Claude Code / Claude Copilot

---

## Overview

You are drafting the Language Reference Manual for **Safe**, a systems programming language defined subtractively from ISO/IEC 8652:2023 (Ada 2022) via the SPARK 2022 restriction profile, with further restrictions and a small number of structural changes.

Safe is not a new grammar. It is Ada with things removed and a few structural reorganizations. The specification is therefore a short document that references 8652:2023 normatively and states only the delta.

---

## Compatibility Note

Earlier design drafts included a C99 emission backend and OpenBSD as a primary deployment target. Those requirements are removed. Safe has exactly one backend: Ada 2022 / SPARK 2022 emission (D4, D25). Safe imposes no OS-specific targeting requirements; portability is delegated to GNAT (D5). C foreign function interface is excluded from the safe language and reserved for a future system sublanguage.

---

## Conformance Note

Language conformance in this specification is defined in terms of language properties and legality rules, not specific tools or compilers. References to GNAT, GNATprove, and other tools throughout this document are informative — they describe the reference toolchain and provide implementation guidance, but do not define conformance. Toolchain profiles (e.g., GNAT/GNATprove guidance) are informative and belong in informative annexes or companion documents. The normative conformance requirements appear in §06 and are expressed solely in terms of what a conforming implementation must accept, reject, and guarantee about program behavior.

---

## Toolchain Baseline

All compiler and proof requirements in this specification are defined relative to the following baseline:

- **GNAT:** GNAT Pro or GNAT Community, version 14.x or later (Ada 2022 capable)
- **GNATprove:** Same release series as GNAT
- **Proof level:** `gnatprove --mode=prove --level=2` (or higher if needed to discharge all checks)
- **Runtime profile for concurrency:** `pragma Profile (Jorvik)` on hosted GNAT targets

If Jorvik is not available for a particular target runtime, the implementation shall document: (a) the chosen alternative profile (e.g., Ravenscar), (b) any restricted channel or select features, and (c) any impact on proof obligations.

### Proof acceptance policy

For the purposes of this specification, "passes Bronze" and "passes Silver" mean:

- **Bronze:** `gnatprove --mode=flow` reports zero errors and zero high-severity warnings on the emitted Ada.
- **Silver:** `gnatprove --mode=prove` reports: no unproved runtime checks, no unproved assertions, and no tool errors. Proof timeouts are treated as failures unless explicitly documented with a mitigation plan.

These are the acceptance criteria for D26's guarantees. Every conforming Safe program, when compiled and emitted as Ada/SPARK, shall meet both criteria without any developer-supplied SPARK annotations in the emitted code.

---

## Reserved Words

Safe retains all Ada 2022 reserved words that are not associated with excluded features. Safe adds the following context-sensitive keywords that are reserved in Safe source but not Ada reserved words:

- `public` — visibility modifier (D8)
- `channel` — channel declaration (D28)
- `send` — channel send statement (D28)
- `receive` — channel receive statement (D28)
- `try_send` — non-blocking channel send (D28)
- `try_receive` — non-blocking channel receive (D28)
- `capacity` — channel capacity specifier (D28)

These identifiers shall not be used as user-defined names in Safe programs. A conforming implementation shall reject any program that uses a reserved word as an identifier.

The emitted Ada maps these to Ada-legal identifiers (e.g., `channel Readings` emits as a protected object named `Readings`). The identifier mapping shall be deterministic and documented.

---

## Design Decisions and Rationale

This section records every design decision made during the language design process, with rationale. These decisions are final. Do not revisit or propose alternatives.

### D1. Subtractive Language Definition

**Decision:** Safe is defined as ISO/IEC 8652:2023 minus excluded features, not as a new language specified from scratch.

**Rationale:** A subtractive specification inherits decades of precision from the Ada RM. The type system, expression semantics, name resolution, and visibility rules are battle-tested. Rewriting them would introduce edge-case bugs that Ada already resolved. The resulting specification is approximately 80–110 pages referencing 8652:2023, versus 300+ pages written from scratch. This also provides a clear path for future ISO submission, since SC 22 reviewers already understand 8652.

### D2. SPARK 2022 as the Restriction Baseline

**Decision:** The starting feature set is the SPARK 2022 subset of Ada 2022, including SPARK's ownership and borrowing model for access types. We then apply additional restrictions on top of SPARK's (D12–D16, D18–D22). For concurrency, the baseline is the Jorvik tasking profile, surfaced through a channel-based programming model (D28).

**Rationale:** SPARK already removes the features most hostile to compilation simplicity and verification: exceptions, dynamic dispatch, and most of full Ada tasking. Starting from SPARK rather than full Ada means the excluded feature list is shorter and the retained feature set is already coherent. SPARK is a proven, deployed restriction profile used in safety-critical avionics and rail systems. SPARK 2022 reintroduced access types with Rust-style ownership semantics, enabling dynamic data structures while preserving provability — Safe retains this capability. For tasking, the Jorvik profile provides static tasks and protected objects with provable deadlock freedom — Safe surfaces this through a higher-level channel abstraction.

### D3. Single-Pass Recursive Descent Compiler

**Decision:** The language must be compilable in a single pass by a recursive descent parser, similar to Wirth's Oberon compiler.

**Operational definition of "single pass":** The compiler reads the token stream once, left to right. During this pass it builds an in-memory AST, resolves names, checks types, enforces legality rules, and accumulates analysis data (Global/Depends sets, ownership state, task-variable ownership). After the token stream is consumed, the compiler walks the completed AST to emit Ada/SPARK output. This post-parse AST walk is not a "second pass" — it does not re-read source tokens. What is prohibited is any design that requires re-parsing source text, multi-pass name resolution, or whole-program analysis across compilation units. Each compilation unit is compiled independently using only its source and the symbol files of its dependencies.

**Rationale:** Single-pass compilation constrains the language to be simple. If a feature cannot be compiled in one pass, it is too complex. Wirth's Oberon-07 compiler is approximately 4,000 lines and compiles a useful language. Safe's compiler targets roughly 10,000–14,000 lines of Silver-level SPARK (including ownership checking for access types, interval arithmetic for D27 rules, task/channel compilation for D28, and the Ada/SPARK emitter) — small enough for a single person to understand, audit, and formally verify. This also means fast compilation, which matters for developer experience.

### D4. Ada/SPARK as Sole Code Generation Target

**Decision:** The compiler emits Ada 2022 / SPARK 2022 source code. GNAT compiles the emitted Ada to object code. GNATprove verifies the emitted Ada at Bronze and Silver levels. There is no other backend.

**Rationale:** A single emission target eliminates an entire backend from the compiler (\~1,500–2,500 LOC saved), halves the testing surface, and produces output that is directly verifiable by GNATprove. The emitted Ada is the canonical representation of the Safe program — it is what gets proven, what gets compiled, and what gets certified. GNAT handles all platform-specific code generation, optimization, and ABI details. The compiler remains architecture-independent. Every Safe program is an Ada/SPARK program; emitting Ada is the natural and most direct representation.

### D5. Platform-Independent via GNAT

**Decision:** Safe targets any platform supported by GNAT. The compiler emits Ada/SPARK source; GNAT handles all platform-specific code generation, linking, and runtime support. No platform-specific requirements are imposed by the Safe language definition.

**Rationale:** Since the compiler emits Ada source code (not machine code or C), platform targeting is entirely GNAT's responsibility. GNAT supports Linux, macOS, Windows, and various embedded targets including bare-metal ARM and RISC-V. The Safe compiler itself runs wherever GNAT runs. This makes Safe immediately portable to every GNAT-supported platform without any work in the Safe compiler. Platform-specific concerns (ABI, calling conventions, memory layout) are handled by GNAT and by the Ada language's representation clauses.

### D6. No Separate Specification and Body Files

**Decision:** A Safe package is a single source file. There are no separate `.ads` (specification) and `.adb` (body) files. The compiler extracts the public interface into a symbol file for incremental compilation, and emits `.ads`/`.adb` pairs as its output. The symbol file format is implementation-defined.

**Rationale:** The `.ads`/`.adb` split dates from the 1980s and creates maintenance burden — two files that must stay in sync, doubled file counts, and a confusing `private` section in the spec that is visible to the compiler but not logically to clients. Every modern language (Go, Rust, Zig, Odin, Swift) uses single-file modules with compiler-extracted interfaces. Oberon did this in 1987. The compiler already knows what's public; asking the programmer to state it twice is redundant. The compiler reconstructs the `.ads`/`.adb` split mechanically from the single Safe source file, giving full Ada ecosystem compatibility (GNAT compilation, GNATprove verification, DO-178C certification).

### D7. Flat Package Structure — Purely Declarative

**Decision:** A package is a flat sequence of declarations. There is no `package body` wrapper, no `begin...end` initialization block, and no package-level executable statements. Variable initialization uses expressions or function calls at the point of declaration.

**Initialization order:**

- *Within a package:* Package-level variable initializers are evaluated in declaration order (top to bottom), as in Ada. An initializer may reference previously declared variables and call previously declared functions within the same package. Referencing a not-yet-declared entity in an initializer is a legality error (declaration-before-use).
- *Across packages:* If package A `with`s package B, then B's initializers complete before A's initializers begin. This matches Ada's elaboration semantics but is trivially satisfiable because Safe packages have no circular `with` dependencies (enforced by the single-pass compilation model — you cannot `with` a package whose symbol file does not yet exist). The emitted Ada uses `pragma Preelaborate` or `pragma Pure` where possible, falling back to GNAT's static elaboration model for packages with non-static initializers.
- *Tasks vs. initialization:* All package-level initialization across all compilation units completes before any task begins executing (D28). This is a sequencing guarantee enforced by the emitted Ada's elaboration model.

**Rationale:** If packages are purely declarative, the elaboration ordering problem is vastly simplified. Ada's elaboration model is a notorious source of complexity — `Elaborate`, `Elaborate_All`, `Elaborate_Body` pragmas and the elaboration order determination algorithm. By requiring that all initialization be expressible as declaration-time expressions or function calls, and by prohibiting circular dependencies, we reduce elaboration to a simple topological sort of the `with` graph. The package becomes what it should always have been: a namespace containing declarations. Executable code lives only inside subprogram bodies.

### D8. Default-Private Visibility with `public` Annotation

**Decision:** All declarations are private by default. The `public` keyword makes a declaration visible to client packages. There is no `private` section divider.

**Rationale:** Every modern safety-oriented language defaults to private: Rust, Go (lowercase), Zig, Swift. The reasoning is simple — forgetting to annotate something should hide it, not expose it. This also eliminates the need for a `private` section in the package, since there's no section model at all. The keyword `public` was chosen over alternatives (`pub`, Oberon's `*` marker) because it reads naturally in Ada's keyword-heavy style and is self-documenting.

### D9. Opaque Types via `public type T is private record`

**Decision:** A type can be public in name but private in structure using `public type T is private record ... end record;`. Clients can declare variables of the type (the compiler exports the size) but cannot access fields.

**Rationale:** This preserves Ada's information-hiding capability without requiring a separate specification file. The `public` keyword exports the type name to the symbol file. The `private record` modifier tells the compiler to export size and alignment but not field layout. The compiler has full knowledge of the type (it's declared right there) and can generate correct code. The combination reads naturally: "this is a public type with a private structure."

### D10. Subprogram Bodies at Point of Declaration

**Decision:** Subprogram bodies appear at the point of declaration. A subprogram is declared and defined in one place. The only exception is forward declarations for mutual recursion.

**Rationale:** This is the Oberon model and eliminates the signature duplication that is Ada's most visible redundancy. In Ada, every subprogram declared in a spec must have its full signature repeated in the body — same parameters, same types, same modes, same contracts. In Safe, you write it once. The compiler extracts the signature for the symbol file. Forward declarations for mutual recursion are the one unavoidable case of signature repetition, and they're intrinsic to single-pass compilation of mutually recursive functions (Pascal, C, and Oberon all require the same).

### D11. Interleaved Declarations and Statements in Subprogram Bodies

**Decision:** Inside subprogram bodies, declarations and statements may interleave freely after `begin`. A declaration is visible from its point of declaration to the end of the enclosing scope. The pre-`begin` declarative part is still permitted but not required.

**Rationale:** Ada requires all local variable declarations before `begin`, which forces the programmer to declare variables far from their first use. Zig, Rust, Go, and most modern languages allow declarations at point of use. This is a pure ergonomic improvement with no cost — the compiler processes declarations when it encounters them, which is exactly what single-pass compilation does.

### D12. No Overloading

**Decision:** Subprogram name overloading is excluded. Each subprogram identifier denotes exactly one subprogram within a given declarative region. Predefined operators for language-defined types are retained. User-defined operator overloading (defining `"+"` for a record type, etc.) is excluded.

**Scope of the restriction:**

- **Excluded:** Two subprograms with the same name in the same declarative region, regardless of parameter profiles. A conforming implementation shall reject any declarative region containing two subprogram declarations with the same identifier.
- **Excluded:** User-defined operator symbols (`function "+" (A, B : Widget) return Widget`). A conforming implementation shall reject any operator function definition.
- **Retained:** Predefined operators for numeric types, boolean, and other language-defined types. These are not user-declared and do not participate in overload resolution — they are intrinsic to the type.
- **Retained:** The same subprogram name may appear in different packages (qualified by the package name: `Sensors.Initialize` vs `Motors.Initialize`). This is not overloading; it is distinct declarations in distinct namespaces.

**Name resolution rule (dot notation):** When `X.Name` appears in source, resolution is unambiguous because: (a) if `X` is a record object, `Name` is a field; (b) if `X` is a type or subtype mark, `Name` is an attribute (in dot notation per D20); (c) if `X` is a package name, `Name` is a declaration in that package. The compiler determines which case applies from the type/kind of `X`, which is always known in a single-pass compiler at the point of use. No overload resolution is needed.

**Rationale:** Overloading is the single biggest obstacle to single-pass compilation in Ada. Resolving which overloaded subprogram a call refers to requires examining return types, parameter types, and context — sometimes across compilation units. Oberon has zero overloading. Dropping it dramatically simplifies name resolution (every name resolves to exactly one entity) and makes the language easier to read (every call site is unambiguous without consulting type information).

### D13. No Use Clauses (General), Use Type Retained

**Decision:** General `use` clauses (8652:2023 §8.4) are excluded. `use type` clauses are retained.

**Rationale:** General `use` clauses import all visible declarations from a package into the current scope, creating name pollution and making code harder to read (you can't tell where a name comes from without checking which packages are `use`'d). SPARK style guides already discourage them. `use type` is retained because it makes operator notation usable for user-defined types without importing everything else from the package — this is a targeted, controlled form of use that doesn't create the name pollution problem.

### D14. No Exceptions

**Decision:** Section 11 of 8652:2023 (Exceptions) is excluded in its entirety. No exception declarations, no raise statements, no exception handlers.

**Rationale:** Exceptions create hidden control flow that the compiler must account for at every call site — stack unwinding, cleanup actions, propagation semantics. They are one of the most complex features to implement in a compiler and one of the hardest to reason about in code review. SPARK already excludes them. Error handling in Safe uses explicit return values (discriminated records, status codes) and `pragma Assert` for defensive checks that abort on failure.

### D15. Restricted Tasking — Static Tasks and Channels Only

**Decision:** Full Ada tasking (Section 9 of 8652:2023) is excluded. In its place, Safe provides a restricted concurrency model based on static tasks and typed channels (D28). The following Section 9 features are excluded: task types, dynamic task creation, task entries, rendezvous (`accept` statements), all forms of `select` on entries, `abort` statements, `requeue`, protected types as user-declared constructs, and the real-time annexes (D.1–D.14) except for task priorities.

**Rationale:** Ada's full tasking model (tasks, protected objects, rendezvous, select statements, real-time annexes) is one of the hardest parts of Ada to compile and the largest runtime dependency. Safe replaces it with a channel-based model (D28) that compiles to Jorvik-profile SPARK — static tasks, compiler-generated protected objects backing channels, and the ceiling priority protocol for deadlock freedom. The emitted Ada uses GNAT's Jorvik-profile runtime, which is small and well-tested. The programmer sees tasks and channels; the prover sees Jorvik-profile SPARK.

### D16. No Generics

**Decision:** Section 12 of 8652:2023 (Generic Units) is excluded in its entirety.

**Rationale:** Ada generics require instantiation, which is effectively a second compilation pass (or a macro expansion step). They create significant compiler complexity around sharing vs. code duplication strategies. Oberon has no generics. The resulting language requires monomorphic code — if you need the same algorithm for multiple types, you write it for each type, or you use code generation tools outside the language. This is a significant expressiveness tradeoff accepted in exchange for compiler simplicity.

### D17. Access Types with SPARK Ownership and Borrowing

**Decision:** Access types are retained with SPARK 2022's ownership and borrowing rules. Access-to-object types are permitted. Access-to-subprogram types are excluded. The full SPARK ownership model applies: move semantics on assignment, borrowing for temporary mutable access, observing for temporary read-only access. Explicit `Unchecked_Deallocation` is excluded — deallocation occurs automatically when the owning object goes out of scope.

Additionally, dereference of an access value requires the access subtype to be `not null` (see D27 Rule 4).

**Ownership mapping from Safe to SPARK/Ada:**

| Safe construct                     | Ada access kind in emitted code   | Ownership semantics                                                  |
| ---------------------------------- | --------------------------------- | -------------------------------------------------------------------- |
| `type T_Ptr is access T;`          | Named access-to-variable type     | Owner — can be moved, borrowed, or observed                          |
| `subtype T_Ref is not null T_Ptr;` | `not null` subtype of above       | Non-null owner — legal for dereference                               |
| `X := new T'(...)`                 | Allocator                         | Creates a new owned value; X becomes the owner                       |
| `Y := X` (access assignment)       | Assignment                        | **Move**: X becomes null, Y becomes owner                            |
| `procedure P (A : in T_Ptr)`       | `in` mode access parameter        | **Observe**: read-only borrow; caller's ownership frozen during call |
| `procedure P (A : in out T_Ptr)`   | `in out` mode access parameter    | **Borrow**: mutable borrow; caller's ownership frozen during call    |
| Scope exit of owning variable      | (compiler-generated deallocation) | Automatic deallocation when owner goes out of scope                  |

**Restrictions vs. full SPARK ownership:**

- General access types (`access all T`) are excluded. A conforming implementation shall reject access type definitions that include the reserved word `all`. Rationale: general access types interact with aliased objects and `'Access` / `'Unchecked_Access` attributes, both of which Safe excludes; pool-specific access types are sufficient for Safe's ownership model.
- Anonymous access types are excluded (Safe requires named access types for all uses).
- Access-to-constant types (`access constant T`) are excluded for simplicity; use `in`-mode observe parameters instead.
- `Unchecked_Access` and `Unchecked_Deallocation` are excluded from Safe source.
- All ownership checking is local to the compilation unit — no whole-program analysis. This is compatible with SPARK's ownership model, which is also local.

**Implementation note (deallocation emission):** The emitted Ada uses `Ada.Unchecked_Deallocation` generic instantiations to implement automatic deallocation when the owning object goes out of scope. The exclusion of generics (D16) applies to Safe source, not emitted Ada. Deallocation calls must be emitted at every scope exit point, including early `return` statements, loop `exit` statements, and `goto` statements that leave the scope, not just the textual end of the scope. GNATprove's leak checking on the emitted Ada provides independent verification that the compiler's deallocation logic is complete.

**Rationale:** Dynamic data structures (linked lists, trees, buffer pools, process tables) are essential for OS construction and systems programming. SPARK 2022 solved the safety problem for access types by adopting Rust-style ownership semantics — each access value has exactly one owner, ownership transfers are explicit via move semantics on assignment, and borrowing/observing provide temporary access without ownership transfer. These rules are enforced at compile time by local analysis (no whole-program reasoning), which is compatible with single-pass compilation. Excluding access-to-subprogram types eliminates indirect calls, preserving the property that every call resolves statically.

### D18. No Tagged Types or Dynamic Dispatch

**Decision:** Tagged types (3.9), type extensions, dispatching operations, class-wide types, abstract types, and interface types are excluded.

**Rationale:** Dynamic dispatch requires vtable management, tag checks, class-wide streaming, and runtime type identification. It is fundamentally incompatible with the goal of a simple, predictable compilation model where every call resolves statically. Excluding tagged types also eliminates extension aggregates (4.3.2) and a large portion of Ada's OOP machinery. This also has a direct benefit for the tick-to-dot syntax change (D20): without dispatching, `X.Foo` is unambiguous — it's either a record field or an attribute, never a dispatching call.

### D19. No Contracts — pragma Assert Instead

**Decision:** All SPARK/Ada contract aspects are excluded: `Pre`, `Post`, `Contract_Cases`, `Type_Invariant`, `Dynamic_Predicate`, `Default_Initial_Condition`, `Loop_Invariant`, `Loop_Variant`, `Subtype_Predicate`. The language provides `pragma Assert` for runtime defensive checks.

**Rationale:** Without a prover, contract aspects are runtime assertions with special syntax. They add 10–15 grammar productions and 500–800 lines of compiler code for contract lowering, including special forms like `'Result` and `'Old` in postconditions. The value they provide — interface-level documentation, automatic checking at type boundaries — is real but does not justify the complexity in a language targeting Oberon-class simplicity. `pragma Assert` provides the same runtime checking capability. A failed assert calls the runtime abort handler with a source location diagnostic. The compiler automatically generates `Global`, `Depends`, and `Initializes` in the emitted Ada for Bronze-level SPARK assurance, and D27's language rules guarantee Silver-level AoRTE (see D26). Developer-authored `Pre` and `Post` are not needed for either level. A developer seeking Gold or Platinum assurance adds contracts to the emitted Ada directly.

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

**Rationale:** Safe does not require the developer to write these aspects. They exist solely for GNATprove's flow analyzer and proof engine. However, they are not simply discarded — the compiler automatically generates `Global`, `Depends`, and `Initializes` in the emitted Ada from the compiler's name resolution and data flow analysis (see D26). This means the developer writes zero verification annotations in Safe source, but gets Bronze-level SPARK assurance in the emitted Ada for free. The remaining verification-only aspects (`Ghost`, `Refined_State`, etc.) provide information for Gold/Platinum proof levels and cannot be automatically generated; they are excluded.

### D23. Retained Ada Features

**Decision:** The following features are explicitly retained:

- All four numeric type families (signed integer, modular integer, floating point, fixed point)
- Subtypes with static and dynamic constraints
- Records including discriminated records (discrete discriminants, static constraints, defaults)
- Arrays including unconstrained array types
- Access-to-object types with SPARK 2022 ownership and borrowing rules
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
- Declare expressions (Ada 2022) — if part of SPARK 2022
- Delta aggregates (Ada 2022) — if part of SPARK 2022
- All Ada 2022 features in the SPARK 2022 subset not otherwise excluded
- `pragma Assert`
- `pragma Inline`
- `pragma Pack`

**Rationale:** These features form the core of a useful systems programming language — rich numeric types for hardware modeling, records and arrays for data structures, access types with ownership for dynamic data structures (linked lists, trees, buffer pools), static tasks and channels for safe concurrency, and expression functions for concise pure computations. String handling is limited to fixed-length arrays, which is acceptable for systems programming and avoids unbounded heap allocation. Goto is retained because SPARK allows it and it is trivially single-pass compilable. C FFI (`pragma Convention`, `pragma Import`, `pragma Export`) is deliberately excluded because an imported C function is an unverifiable hole in the Silver guarantee. All foreign language interface is excluded from this specification (see D24).

### D24. System Sublanguage — Not Specified

**Decision:** C foreign function interface (`pragma Convention`, `pragma Import`, `pragma Export`), raw memory access, inline assembly, volatile MMIO, unchecked conversions, and other unsafe capabilities are excluded from the Safe language. They are not specified in this document.

**Rationale:** The safe language must be hermetically safe — no construct in the safe language can introduce unverifiable behavior. A single `pragma Import` of a C function creates an unverifiable hole in the Silver guarantee, since GNATprove cannot analyze foreign code. A future system sublanguage specification may provide controlled, auditable access to unsafe capabilities through explicitly scoped regions, similar to Go's `unsafe` package or Rust's `unsafe` blocks. That specification is a separate document with its own design process. This specification defines only the safe floor.

### D25. Ada/SPARK Emission Backend

**Decision:** The compiler emits valid ISO/IEC 8652:2023 `.ads`/`.adb` file pairs that are guaranteed to pass GNATprove at SPARK Bronze and Silver levels. This is the sole backend.

**Rationale:** Ada emission gives access to the entire Ada ecosystem — GNAT's optimizing compiler for any supported platform, GNATprove for formal verification, DO-178C certification toolchains, and interoperability with existing Ada libraries. Every restriction in Safe is a restriction of Ada, so every Safe program is expressible as valid Ada/SPARK. The single-file package model is split mechanically: public declarations become the `.ads`, everything else becomes the `.adb`, with full signatures reconstituted from the symbol table. Having a single backend simplifies the compiler (no C emitter to maintain), simplifies testing (one output format to verify), and simplifies the trust chain (GNATprove verifies the same code that GNAT compiles).

### D26. Guaranteed Bronze and Silver SPARK Assurance

**Decision:** The compiler shall automatically generate SPARK annotations in the emitted Ada sufficient for GNATprove Bronze-level assurance on every conforming Safe program. Every conforming Safe program shall also be Silver-provable (Absence of Runtime Errors) by construction — the language rules guarantee that all runtime checks are dischargeable by the prover.

**Rationale and analysis by SPARK assurance level:**

**Stone (guaranteed, trivially):** The emitted Ada compiles with `SPARK_Mode`. This is true by construction — every Safe construct maps to a SPARK-legal Ada construct.

**Bronze (guaranteed, mechanically generated):** Bronze requires GNATprove to pass flow analysis. This requires three annotation families:

- `Global` — which package-level variables does a subprogram read or write. The Safe compiler already resolves every variable reference during its single pass. It accumulates a read-set and write-set per subprogram as a natural byproduct of name resolution. The emitter formats these as `Global` aspects.

- `Depends` — which outputs are influenced by which inputs. The Safe compiler tracks data flow through assignments and expressions during compilation. In a language with no uncontrolled aliasing (ownership rules prevent it), no dispatching, and no exceptions, dependency analysis is straightforward. The emitter formats these as `Depends` aspects.

- `Initializes` — which package variables are initialized at elaboration. Since Safe packages are purely declarative with mandatory initialization expressions, every package-level variable is initialized. The emitter lists all package variables in the `Initializes` aspect.

Estimated compiler cost: 500–800 lines (300–500 for analysis during the existing single pass, 200–300 in the emitter for formatting).

**Silver (guaranteed, by language design — hard rejection rule):** Silver requires proof of Absence of Runtime Errors — every range check, overflow check, index check, division-by-zero check, and null dereference check must be dischargeable from the program's type information. Safe guarantees Silver through four language rules specified in D27:

1. Wide intermediate arithmetic — integer overflow is impossible in expressions.
2. Strict index typing — array index types must match or be subtypes of the array's index type.
3. Division-by-nonzero-type — the divisor in `/`, `mod`, and `rem` must be of a type whose range excludes zero.
4. Not-null dereference — dereference of an access value requires the access subtype to be `not null`.

These rules ensure that every runtime check in a conforming Safe program is provably safe from type information alone. No developer annotations are needed.

**Hard rejection rule:** If a conforming implementation cannot establish, from the specification's type rules and D27 legality rules, that a required runtime check will not fail, the program is nonconforming and the implementation shall reject it with a diagnostic. There is no "developer must restructure" advisory — failure to satisfy any Silver-level proof obligation is a compilation error, not a warning.

**Concurrency safety (guaranteed, by language design):** The channel-based tasking model (D28) provides additional safety guarantees verifiable by GNATprove on the emitted Jorvik-profile SPARK:

- **Data race freedom:** No shared mutable state between tasks. All inter-task communication is through channels (compiler-generated protected objects). GNATprove verifies this via `Global` aspects on task bodies.
- **Deadlock freedom:** The ceiling priority protocol is enforced by the Jorvik profile. The compiler assigns ceiling priorities to channel-backing protected objects based on the static priorities of tasks that access them. GNATprove verifies the protocol is respected.

**Gold and Platinum (out of scope):** Functional correctness and full formal verification require developer-authored specifications (postconditions stating functional intent, ghost code, lemmas). These are inherently non-automatable and are out of scope for the Safe compiler. A developer seeking Gold or Platinum works with the emitted Ada directly, adding specifications to the generated code.

### D27. Silver-by-Construction: Arithmetic, Indexing, and Division Rules

**Decision:** The following four legality and semantic rules guarantee that every conforming Safe program is Silver-provable (Absence of Runtime Errors) when emitted as Ada:

**Rule 1: Wide Intermediate Arithmetic**

All integer arithmetic expressions are evaluated in a mathematical integer type with no overflow. Range checks are performed only when the result is:

- Assigned to an object
- Passed as a parameter
- Returned from a function

**Emitted Ada idiom:** The compiler emits intermediate arithmetic using a 64-bit type: `type Wide_Integer is range -(2**63) .. (2**63 - 1);`. All subexpressions are lifted to `Wide_Integer` before evaluation. At narrowing points (assignment, return, parameter), the compiler emits an explicit type conversion to the target type, which generates a range check that GNATprove discharges via interval analysis.

If the static range of any declared type in the program exceeds 64-bit signed range, the compiler shall reject the program. This is a legality rule, not a silent truncation. In practice, all Safe integer types will fit within 64 bits.

**Intermediate overflow legality rule:** For types whose range fits within 32 bits, intermediate `Wide_Integer` arithmetic cannot overflow for single operations. For chained operations or types with larger ranges (e.g., products of two values near the 32-bit boundary), intermediate `Wide_Integer` subexpressions may approach the 64-bit bounds. If the implementation's interval analysis determines that any intermediate `Wide_Integer` subexpression in an expression could overflow 64-bit signed range, the expression shall be rejected with a diagnostic. This ensures the "no intermediate overflow" guarantee holds universally, not just for small-range types. Narrowing checks at assignment, return, and parameter points are discharged via interval analysis on the wide result.

This means `A + B` where `A, B : Reading` (0..4095) computes in `Wide_Integer` — the intermediate result 8190 does not overflow. A range check fires only if the result is stored back into a `Reading`.

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

**Rule 3: Division by Nonzero Type**

The right operand of the operators `/`, `mod`, and `rem` shall be of a type or subtype whose range does not include zero. If the divisor's type range includes zero, the program is rejected at compile time.

This guarantees that every division-by-zero check is dischargeable by the prover — the divisor value is constrained by its type to be nonzero.

The language provides standard subtypes that exclude zero:

```ada
subtype Positive is Integer range 1 .. Integer.Last;
subtype Negative is Integer range Integer.First .. -1;
```

Example:

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

**Combined effect:** These four rules ensure that the six categories of runtime check — overflow, range, index, division-by-zero, null dereference, and discriminant — are all dischargeable by GNATprove from type information alone:

| Check                                | How discharged                                                        |
| ------------------------------------ | --------------------------------------------------------------------- |
| Integer overflow                     | Impossible — wide intermediate arithmetic                             |
| Range on assignment/return/parameter | Interval analysis on wide intermediates                               |
| Array index out of bounds            | Index type matches array index type                                   |
| Division by zero                     | Divisor type excludes zero                                            |
| Null dereference                     | Access subtype is `not null` at every dereference                     |
| Discriminant                         | Discriminant type is discrete and static (from D23 retained features) |

**Ergonomic impact:** The rules push the programmer toward tighter types — `Positive` instead of `Integer` for counts, `Channel_Id` instead of `Integer` for indices, `Seconds` instead of `Integer` for durations, `Node_Ref` instead of `Node_Ptr` for dereference. In every case this produces better, more self-documenting code. The friction is limited to explicit narrowing conversions when crossing type boundaries after a conditional check, which is where the programmer should be making a conscious decision about bounds, nullability, or validity anyway.

**Rationale:** Silver-by-construction is the language's defining feature. The developer writes zero verification annotations — no contracts, no `Global`, no `Depends`, no preconditions. The type system and these four rules guarantee both Bronze and Silver SPARK assurance automatically. This removes the single biggest barrier to formal verification adoption: the annotation burden.

### D28. Static Tasks and Typed Channels

**Decision:** Safe provides concurrency through static tasks and typed channels as first-class language constructs. Tasks are declared at package level and create exactly one task each. Channels are typed, bounded-capacity, blocking FIFO queues declared at package level. Tasks communicate exclusively through channels — no shared mutable state between tasks. The model maps to the Jorvik tasking profile in the emitted SPARK Ada.

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

Tasks begin executing when the program starts, after all package-level initialization is complete. Each task declaration creates exactly one task — no dynamic spawning, no task types, no task arrays. Tasks shall not terminate — every task body must contain a non-terminating control structure (e.g., an unconditional `loop`). A conforming implementation shall reject any task body that is not syntactically non-terminating. This is required by the Jorvik profile, which retains the `No_Task_Termination` restriction from Ravenscar.

**Rationale (static, non-terminating tasks):** Dynamic task creation (Go's `go f()`) prevents static analysis of the task set — you cannot count tasks, assign ceiling priorities, prove resource bounds, or verify deadlock freedom if the number of tasks is unknown at compile time. Ravenscar and Jorvik both require static tasks for exactly this reason. Both profiles also retain `No_Task_Termination` — tasks run forever once started, which simplifies resource analysis and prevents dangling references to task-owned state. Every task in a Safe program is visible by reading the source — you can enumerate the entire concurrent architecture from the package declarations. This is the right tradeoff for systems programming, where the set of concurrent activities (interrupt handlers, device drivers, protocol stacks, schedulers) is known at design time.

**Channel declarations:**

A channel is a typed, bounded FIFO queue:

```ada
channel Readings : Reading capacity 16;
channel Commands : Command capacity 4;
```

The element type must be a definite type (not unconstrained). The capacity is a static expression — known at compile time, so the buffer is statically allocated. Channels may be declared `public` for cross-package communication.

**Channel operations:**

```ada
send Ch, Value;                     -- blocking: enqueue Value, block if Ch full
receive Ch, Variable;               -- blocking: dequeue into Variable, block if Ch empty
try_send Ch, Value, Success;        -- non-blocking: Success is Boolean
try_receive Ch, Variable, Success;  -- non-blocking: Success is Boolean
```

`send` and `receive` are statements, not expressions. They block the current task (not the whole program) until the operation can complete. `try_send` and `try_receive` never block — they set a `Boolean` indicating success.

**Rationale (channels):** Channels replace protected objects as the user-visible communication mechanism. A protected object is a monitor with entries, barriers, and the ceiling priority protocol — powerful but complex. A channel is a bounded buffer with send and receive — simple, composable, and familiar to anyone who has used Go, Erlang, or Unix pipes. Under the hood, the compiler generates protected objects in the emitted Ada, preserving the Jorvik ceiling priority protocol for deadlock freedom analysis. The programmer never sees the protected object; they see channels.

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

This is the critical safety rule. Each package-level variable must be accessed by at most one task. The compiler checks this at compile time — it is an extension of the `Global` analysis already performed for Bronze SPARK assurance, applied across task boundaries.

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

**Rationale (no shared state):** Data races are the primary source of concurrency bugs. Go's motto is "share memory by communicating, don't communicate by sharing memory." Safe enforces this at compile time. The ownership check is straightforward in a single-pass compiler — the `Global` analysis already tracks which variables each subprogram accesses. Extending this to task boundaries adds approximately 200–300 lines of compiler code. The result is that every inter-task data flow is visible as a channel operation — auditable, analyzable, and provable.

**Non-termination requirement:**

Tasks shall not terminate. The Jorvik profile retains the `No_Task_Termination` restriction from Ravenscar — both profiles require tasks to run forever once started. Every task body must contain a non-terminating control structure (typically an unconditional `loop`). A conforming implementation shall reject any task body whose outermost statement sequence is not syntactically non-terminating. `return` statements are not permitted in task bodies. This simplifies resource analysis: task-owned package variables remain accessible for the lifetime of the program, and channel endpoints are always active.

**SPARK emission:**

The compiler generates Jorvik-profile SPARK in the emitted Ada:

- `pragma Partition_Elaboration_Policy(Sequential)` is emitted in the configuration file, ensuring all package-level declarations and initializations complete before any task begins execution. This is required by SPARK for programs using tasks or protected objects.
- Each `task` becomes an Ada task type with a single instance and a `Priority` aspect.
- Each `channel` becomes a protected object with ceiling priority, `Send` and `Receive` entries, and an internal bounded buffer.
- `send`/`receive` become entry calls on the generated protected object.
- `select` on channels becomes a conditional entry call pattern. **Latency note:** The polling-with-sleep emission pattern for `select` is pragmatically correct but not zero-overhead — it introduces latency equal to the sleep interval. Implementations may use more efficient patterns (e.g., POSIX `select`-style multiplexing) where the target runtime supports them. The implementation may use alternative emission patterns provided the observable semantics (arm selection order, deterministic priority) are preserved.
- Task-variable ownership becomes `Global` aspects on task bodies, referencing only owned variables and channel operations.

GNATprove can then verify: data race freedom (no unprotected shared state), deadlock freedom (ceiling priority protocol), and all Silver-level AoRTE checks within task bodies.

**Runtime:** The emitted Ada uses GNAT's Jorvik-profile runtime. No custom runtime is needed — GNAT provides task scheduling, protected object implementation, and delay support. The Safe compiler's responsibility ends at emitting correct Jorvik-profile Ada.

**Compiler cost:**

| Component                                                    | LOC     |
| ------------------------------------------------------------ | ------- |
| Channel declarations and type checking                       | 200–300 |
| Task declarations and body compilation                       | 200–300 |
| Send/receive/try\_send/try\_receive statements               | 150–200 |
| Select statement compilation                                 | 300–400 |
| Task-variable ownership checking                             | 200–300 |
| Ada emission (task types, protected objects, Jorvik aspects) | 300–500 |

Approximately 1,350–2,000 LOC additional compiler code.

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

### D29. Reference Implementation in Silver-Level SPARK (Project Requirement)

**Decision:** The reference implementation of the Safe compiler shall be written in Ada 2022 / SPARK 2022, with all compiler source code at SPARK Silver level (Absence of Runtime Errors proven by GNATprove). This is a project requirement for the reference implementation, not a language conformance requirement — a conforming implementation may be written in any language, provided it satisfies the conformance requirements of §06.

**Rationale:** A safety-oriented language should have a verifiable reference implementation. If the compiler itself can crash due to a buffer overrun, null dereference, or integer overflow when processing adversarial input, the safety guarantees it provides to user programs are undermined. Writing the reference compiler in Silver-level SPARK means:

1. **No runtime errors in the compiler.** Every array access, integer operation, pointer dereference, and type conversion in the compiler is proven safe by GNATprove. A malformed Safe source file may produce a compilation error, but it cannot crash the compiler.

2. **The trust chain is coherent.** Safe programs are Silver-proven when emitted as Ada. The compiler that performs this emission is itself Silver-proven. The verification tools (GNATprove, GNAT) are existing, independently audited infrastructure. There is no unverified link in the chain from Safe source to proven object code.

3. **The compiler eats its own cooking.** The compiler uses Ada's type system the same way Safe's D27 rules require: tight range types for buffer indices, `not null` access subtypes for AST node pointers, nonzero subtypes for divisors. The compiler's source code serves as a large-scale demonstration that Silver-level programming is practical and ergonomic.

4. **Bootstrapping path.** The compiler is built by GNAT on any GNAT-supported host. It does not need to self-host — it is an Ada program that compiles Safe programs, not a Safe program that compiles Safe programs. The compiled Safe compiler binary, together with GNAT and GNATprove, forms the complete Safe toolchain.

**What Silver requires for the compiler:**

The compiler source will use the same patterns that Safe encourages in user code:

- **AST nodes:** Access types with SPARK ownership for tree structures. `not null` subtypes at every dereference. Ownership moves during tree construction, borrows during tree walks.
- **Symbol tables:** Array-based or access-based, with index types matching array bounds.
- **Lexer/parser buffers:** Bounded arrays with range types for positions. No unchecked indexing.
- **Numeric computations:** Wide intermediates for line/column arithmetic, interval analysis for source positions.
- **Error handling:** Discriminated records for parse results (success/failure), no exceptions.

**Estimated compiler structure:**

| Component            | Approximate LOC  | Silver challenge                                  |
| -------------------- | ---------------- | ------------------------------------------------- |
| Lexer                | 800–1,200        | Low — character-level, bounded buffers            |
| Parser               | 2,500–3,500      | Low — recursive descent, predictable control flow |
| Semantic analysis    | 2,000–3,000      | Medium — symbol table lookups, type checking      |
| Ownership checker    | 800–1,200        | Medium — access type tracking                     |
| D27 rule enforcement | 500–800          | Low — interval arithmetic, type range queries     |
| Ada/SPARK emitter    | 1,500–2,500      | Low — string building, annotation generation      |
| Driver and I/O       | 500–800          | Low — file handling, command line                 |
| **Total**            | **9,000–13,000** |                                                   |

GNATprove at Silver level on a codebase of this size is well within demonstrated capability — AdaCore has verified larger SPARK codebases (e.g., the SPARK runtime itself, the CubeOS operating system components).

**What this does NOT mean:**

- The compiler is not written in Safe. It is written in Ada/SPARK. Safe is the language being compiled, not the language the compiler is written in. Self-hosting is a possible future goal but is not required or planned.
- The compiler does not need to be Gold-level (functional correctness). Silver proves the compiler won't crash. Proving it compiles correctly (semantic preservation) would require Gold or Platinum and is orders of magnitude harder.

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
  05-spark-assurance.md
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
- Summary of design decisions (reference this document's D1–D29)
- **TBD Register** — the following items are acknowledged as unresolved and reserved for future specification revisions:
  - Target platform constraints beyond "Ada compiler exists"
  - Performance targets (compile time, proof time, code size)
  - Memory model constraints (stack bounds, heap bounds, allocation failure handling)
  - Floating-point semantics beyond inheriting Ada's
  - Diagnostic catalog and localization
  - `Constant_After_Elaboration` aspect — verify whether GNATprove requires it for concurrency analysis of emitted Ada; generate if needed
  - Abort handler behavior (language-defined or implementation-defined)
  - AST/IR interchange format (if any)

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
task declarations and typed channels, which maps to Jorvik-profile SPARK
tasking in emitted Ada.

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

3. **Division by nonzero type:** The right operand of `/`, `mod`, and `rem` (8652:2023 §4.5.5) shall be of a type or subtype whose range does not include zero. A conforming implementation shall reject any division, `mod`, or `rem` operation where the right operand's type range includes zero. Document the language-defined subtypes `Positive` and `Negative` as standard nonzero types.

4. **Not-null dereference:** Dereference of an access value — explicit `.all` or implicit selected component through an access — shall require the access subtype to be `not null` (8652:2023 §3.10). A conforming implementation shall reject any dereference where the access subtype does not exclude null. Document the `not null` subtype pattern: `type T_Ptr is access T; subtype T_Ref is not null T_Ptr;`.

**Access types and ownership:** Specify the retained SPARK 2022 ownership model:

- Pool-specific access-to-object types (`access T`) are retained with SPARK ownership rules
- General access types (`access all T`) are excluded — a conforming implementation shall reject access type definitions that include the reserved word `all`
- Access-to-subprogram types are excluded
- Anonymous access types are excluded
- Access-to-constant types (`access constant T`) are excluded
- Assignment of an access value is a **move**: the source becomes null, the target receives ownership
- A parameter of mode `in` with an access type **observes** (temporary read-only, owner frozen)
- A parameter of mode `in out` with an access type **borrows** (temporary mutable, owner frozen)
- Deallocation occurs automatically when the owning object goes out of scope
- Explicit `Unchecked_Deallocation` is excluded
- `Unchecked_Access` attribute is excluded
- Reference the SPARK RM ownership rules and specify how they map to Safe's single-file package model

**Contract exclusions:** List every excluded contract aspect with a reference to its 8652:2023 or SPARK RM definition and the rationale "replaced by pragma Assert; Bronze and Silver assurance guaranteed by compiler-generated annotations and D27 language rules."

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
- **Static Semantics** — symbol file contents, what clients see, how opaque types export size but not structure
- **Dynamic Semantics** — variable initializers evaluated at load time in declaration order; no elaboration-time code
- **Implementation Requirements** — emitted Ada structure (`.ads`/`.adb` split), symbol file emission, incremental recompilation rules
- **Examples** — at least four complete packages:
  - A simple package with public types and functions
  - A package with opaque types
  - Two packages where one depends on the other via with-clause
  - A package demonstrating interleaved declarations in subprogram bodies, dot notation for attributes, and type annotation syntax

### 04-tasks-and-channels.md

Full specification of Safe's concurrency model. This defines the channel-based programming model that maps to Jorvik-profile SPARK.

- **Task declarations** — syntax, static constraints (one task per declaration, package-level only), priority assignment, task body scoping rules
- **Channel declarations** — syntax, element type constraints (must be definite), capacity as static expression, static allocation of channel buffers
- **Channel operations** — `send`, `receive`, `try_send`, `try_receive` semantics, blocking behavior, interaction with task priorities
- **Select statement** — syntax, receive-only restriction, deterministic arm selection (first-ready wins), delay timeout semantics
- **Task-variable ownership** — the no-shared-mutable-state rule, compile-time checking algorithm (extension of `Global` analysis across task boundaries), transitivity through the call graph
- **Non-termination requirement** — every task body must contain a non-terminating control structure; `return` is not permitted in task bodies; conforming implementations shall reject task bodies that are not syntactically non-terminating; rationale: Jorvik retains `No_Task_Termination` from Ravenscar
- **Task startup** — ordering relative to package initialization: all package-level declarations and initializations complete before any task begins execution. The order of package initialization is implementation-defined but deterministic for a given program. The emitted Ada shall include `pragma Partition_Elaboration_Policy(Sequential)` to enforce this guarantee.
- **Examples** — producer/consumer, router/worker, command/response patterns

### 05-spark-assurance.md

Full specification of the SPARK assurance guarantees. This is the language's defining feature — the developer writes zero verification annotations and gets both Bronze and Silver SPARK assurance automatically.

- **Overview** — explain the SPARK assurance levels (Stone through Platinum) and what Safe guarantees at each level
- **Bronze Guarantee** — specify precisely what the compiler generates in the emitted Ada:
  - `Global` aspects on every subprogram: specify the algorithm (accumulate read-set and write-set during name resolution)
  - `Depends` aspects on every subprogram: specify the algorithm (track data flow through assignments and expressions)
  - `Initializes` aspect on every package: specify the rule (all package-level variables with initializers)
  - `SPARK_Mode` on every unit
  - State the normative guarantee as a language property: every conforming Safe program has complete and correct flow information (Global, Depends, Initializes) without user-supplied annotations. As informative validation: when the emitted Ada is submitted to GNATprove, it shall pass flow analysis with no errors
- **Concurrency Assurance** — specify how the tasking model enables additional SPARK verification:
  - Data race freedom: no shared mutable state between tasks (all inter-task communication via channels/protected objects)
  - Deadlock freedom: ceiling priority protocol on channel-backing protected objects, statically assigned priorities
  - Task-variable ownership: `Global` aspects on task bodies reference only owned variables and channel operations
  - Document what GNATprove can verify beyond Bronze and Silver when analyzing the emitted Jorvik-profile SPARK
- **Silver Guarantee** — specify how D27's four language rules guarantee AoRTE:
  - Wide intermediate arithmetic: explain the mathematical integer evaluation model and how it maps to the emitted Ada (intermediate expressions use a wide type; GNATprove discharges overflow checks trivially)
  - Strict index typing: explain how the index subtype matching rule guarantees all array index checks are dischargeable
  - Division by nonzero type: explain how the divisor type rule guarantees all division-by-zero checks are dischargeable
  - Not-null dereference: explain how the `not null` access subtype rule guarantees all null dereference checks are dischargeable
  - Range checks at narrowing points: explain how interval arithmetic on wide intermediates makes these provable
  - Provide a complete enumeration of all runtime check categories and how each is discharged
  - State the hard rejection rule: if a conforming implementation cannot establish absence of a required runtime check failure from the specification's type rules and D27 legality rules, the program is nonconforming and the implementation shall reject it with a diagnostic
  - State that every conforming Safe program, when emitted and submitted to GNATprove, shall pass AoRTE proof with no errors and no user-supplied annotations
- **`Depends` over-approximation note:** The compiler-generated `Depends` contracts may be conservatively over-approximate (listing more dependencies than actually exist). This is acceptable for Bronze — GNATprove accepts `Depends` contracts that are supersets of actual dependencies. An implementation may refine precision over time without affecting conformance.
- **Gold and Platinum** — state these are out of scope; the developer works with emitted Ada directly
- **Examples** — show a Safe source file, the emitted Ada with generated annotations, and the expected GNATprove output at Bronze and Silver levels. Include examples of:
  - Arithmetic that is Silver-provable via wide intermediates
  - Array indexing that is Silver-provable via strict index typing
  - Division that is Silver-provable via nonzero divisor types
  - Access type dereference that is Silver-provable via not-null subtypes
  - Ownership: move, borrow, observe patterns with access types
  - A rejected program (index type too wide, divisor type includes zero, nullable dereference) with the compiler error message
  - A concurrent program with tasks and channels, the emitted Jorvik-profile Ada, and GNATprove's data race freedom and deadlock freedom analysis

### 06-conformance.md

**Normative conformance requirements** (defined in terms of language properties, not specific tools):

- Compilation model (single-pass, Ada/SPARK emission, symbol files). A conforming implementation shall provide a mechanism for separate compilation; symbol files are one permitted mechanism and their format is implementation-defined.
- What constitutes a conforming implementation:
  - A conforming implementation shall accept all conforming programs and reject all non-conforming programs with a diagnostic
  - A conforming implementation shall implement the dynamic semantics correctly for all conforming programs
  - A conforming implementation shall enforce all legality rules defined in this specification, including D27 Rules 1–4
  - No mention of specific compilers or provers in the normative conformance definition
- What constitutes a conforming program — a program is conforming if and only if the implementation can establish, from the specification's type rules and D27 legality rules, that all required runtime checks are dischargeable. A program for which any runtime check cannot be so established is nonconforming and shall be rejected with a diagnostic.
- Language-level assurance guarantees (expressed as language properties, not tool invocations):
  - **Stone:** Every conforming Safe program is expressible as valid Ada 2022 / SPARK 2022 source
  - **Bronze:** Every conforming Safe program has sufficient flow analysis information (Global, Depends, Initializes) to pass flow analysis without user-supplied annotations
  - **Silver:** Every conforming Safe program is free of runtime errors — all runtime checks (overflow, range, index, division-by-zero, null dereference, discriminant) are dischargeable from type information and D27 legality rules alone
- **Conformance levels:** To preserve the safety story through standards refactoring, define two conformance levels:
  - **Safe/Core:** Language rules and legality checking only — a conforming implementation accepts all conforming programs and rejects all non-conforming programs
  - **Safe/Assured:** Language rules plus verification that every conforming program is free of runtime errors (the Silver guarantee expressed as a language property, validatable by any suitable method — not tied to a specific prover)

**Informative implementation guidance** (relocated to §07-annex-b for toolchain-specific details):

- Emitted Ada requirements (informative — describes the reference implementation's emission strategy):
  - Produces valid 8652:2023 `.ads`/`.adb` pairs
  - Emitted code compiles with `SPARK_Mode`
  - Compiler generates `Global`, `Depends`, and `Initializes` aspects automatically
  - Tasks emitted as Jorvik-profile Ada task types with single instances and `Priority` aspects
  - Channels emitted as protected objects with ceiling priority, `Send`/`Receive` entries, and bounded internal buffers
  - Task-variable ownership emitted as `Global` aspects on task bodies
  - `select` on channels emitted as conditional entry call patterns
  - Access type ownership tracked; deallocation calls emitted at owner scope exit
  - Wide intermediate arithmetic emitted using `Wide_Integer` (64-bit signed) per D27 Rule 1
  - Array index checks and null dereference checks guaranteed to be provably safe by D27 Rules 2–4
- Runtime: for the reference implementation, GNAT's Jorvik-profile runtime; no custom runtime required
- **Reference implementation profile (D29, project requirement — not a language conformance requirement):** The reference implementation is written in Ada 2022 / SPARK 2022 at Silver level. This is a project goal for the reference compiler; other conforming implementations may be written in any language.

### 07-annex-a-retained-library.md

Walk through 8652:2023 Annex A and for each library unit state: retained, excluded, or modified. Provide rationale for each exclusion. Note that Annex B (Interface to Other Languages) is excluded in its entirety — C FFI is outside the scope of this specification (D24).

### 07-annex-b-impl-advice.md

Implementation advice covering:

- **Emitted Ada conventions:** The emitted `.ads`/`.adb` files shall be deterministic — the same Safe source, compiled with the same compiler version, shall always produce byte-identical Ada output. Specify naming conventions for generated entities (e.g., channel-backing protected objects, task types, wide integer intermediates). Specify formatting conventions (indentation, line width, declaration ordering) to ensure stable golden tests. The emitted channel-backing protected objects shall use **procedures** (not functions) for non-blocking operations, since SPARK does not permit functions with `out` parameters:
  ```ada
  procedure Try_Send (Item : in Element_Type; Success : out Boolean);
  procedure Try_Receive (Item : out Element_Type; Success : out Boolean);
  ```
- **Symbol file format (recommended practice):** The symbol file format is implementation-defined (see §06). As a recommended practice for the reference implementation, the per-package symbol file should be text-based (UTF-8, line-oriented, versioned header) for debuggability and diffability. Specify: exported names, types (including size/alignment for opaque types), subprogram signatures, and dependency fingerprints. Deterministic ordering for stable diffs. This is the single normative home for symbol file format guidance; §06 states only that the format is implementation-defined.
- **Diagnostic messages:** Format, severity levels, and source location conventions. Error messages shall include the Safe source file, line, and column. Compiler diagnostics should be stable (same input produces same diagnostics) to support automated testing.
- **Incremental recompilation:** Rules for when a symbol file change triggers recompilation of dependent units. Specify the fingerprinting strategy.
- **Emitted Ada quality:** The emitted Ada should be human-readable and suitable for manual inspection, Gold/Platinum annotation, and DO-178C certification review.
- **Elaboration and tasking configuration:** The emitted Ada shall include `pragma Partition_Elaboration_Policy(Sequential)` in the configuration file. This defers library-level task activation until all library units are elaborated, preventing elaboration-time data races. SPARK requires this pragma for programs using tasks or protected objects under Ravenscar/Jorvik profiles.
- **Deallocation emission:** The emitted Ada uses `Ada.Unchecked_Deallocation` generic instantiations for automatic deallocation of owned access objects at scope exit. The exclusion of generics (D16) applies to Safe source only, not emitted Ada. The compiler must emit deallocation at every scope exit point: normal scope end, early `return`, loop `exit`, and `goto` that leaves the scope. GNATprove's leak checking on the emitted Ada independently verifies completeness of the compiler's deallocation logic.

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
- Access type declarations (pool-specific only — `access all` excluded), `not null` subtypes, allocators
- All exclusions from 02-restrictions.md (including `access all`, anonymous access, access-to-constant, access-to-subprogram)

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
7. Draft `05-spark-assurance.md` — Bronze and Silver guarantee specification, concurrency assurance, examples of emitted Ada with annotations.
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
        Offset : Reading := 0;
        Scale  : Float := 1.0;
    end record;

    Cal_Table : array (Channel_Id) of Calibration :=
        (others => (Offset => 0, Scale => 1.0));

    Initialized : Boolean := False;

    public function Is_Initialized return Boolean
    is (Initialized);

    public procedure Initialize is
    begin
        Default_Cal : constant Calibration := (Offset => 0, Scale => 1.0);
        for I in Channel_Id.Range loop
            Cal_Table (I) := Default_Cal;
        end loop;
        Initialized := True;
    end Initialize;

    public function Get_Reading (Channel : Channel_Id) return Reading is
    begin
        pragma Assert (Initialized);
        Raw : Reading := Read_ADC (Channel);
        -- wide intermediate: Raw + Offset computed in mathematical integer
        -- max 4095 + 4095 = 8190, narrowed to Reading on assignment
        -- compiler verifies (4095 + 4095) fits Reading? No — but /1 does.
        -- in practice, Offset should be constrained. Example kept simple.
        Adjusted : Reading := Raw + Cal_Table (Channel).Offset;
        return Adjusted;
    end Get_Reading;

    public function Average_Reading (Count : Channel_Count) return Reading is
    begin
        Total : Integer := 0;
        for I in Channel_Id.First .. Channel_Id(Count - 1) loop
            Total := Total + Integer(Get_Reading(I));
        end loop;
        -- Count is Channel_Count (1..8), excludes zero: division is legal
        return Reading(Total / Count);
    end Average_Reading;

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
- **D27 in action:** `Channel_Count` excludes zero, making it a legal divisor type; `Channel_Id` used directly as array index (strict index typing); arithmetic on `Reading` values uses wide intermediates

### What the Compiler Emits (Bronze + Silver Annotated)

```ada
-- sensors.ads (generated)
pragma SPARK_Mode;

package Sensors
    with Initializes => (Cal_Table, Initialized)
is
    type Reading is range 0 .. 4095;
    type Channel_Id is range 0 .. 7;
    subtype Channel_Count is Integer range 1 .. 8;

    function Is_Initialized return Boolean
        with Global => (Input => Initialized);

    procedure Initialize
        with Global => (In_Out => (Cal_Table, Initialized));

    function Get_Reading (Channel : Channel_Id) return Reading
        with Global => (Input => (Initialized, Cal_Table)),
             Depends => (Get_Reading'Result => (Channel, Initialized, Cal_Table));

    function Average_Reading (Count : Channel_Count) return Reading
        with Global => (Input => (Initialized, Cal_Table)),
             Depends => (Average_Reading'Result => (Count, Initialized, Cal_Table));

private
    type Calibration is record
        Offset : Reading := 0;
        Scale  : Float := 1.0;
    end record;
end Sensors;
```

The developer wrote zero annotations. The compiler generated `Global`, `Depends`, and `Initializes` automatically. This output passes GNATprove at both Bronze level (flow analysis) and Silver level (AoRTE — absence of runtime errors). Division by `Count` is provably safe because `Channel_Count` excludes zero. Array indexing by `Channel_Id` is provably safe because the index type matches the array index type. Arithmetic uses wide intermediates, so no overflow is possible in expressions.

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
- Task-variable ownership: `Threshold` accessed only by `Evaluator`; compiler enforces exclusivity
- Public API exposes channel access through ordinary subprograms
- No shared mutable state, no locks, no protected objects visible to the programmer
