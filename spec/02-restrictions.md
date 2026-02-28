# 2. Restrictions

This section enumerates every feature of ISO/IEC 8652:2023 that Safe excludes or modifies. All syntax, legality rules, static semantics, dynamic semantics, and implementation requirements of 8652:2023 apply except as stated below.

For each exclusion, the relevant 8652:2023 section is cited, and a legality rule is stated. A conforming implementation shall reject any program that uses an excluded construct.

---

## 2.1 Excluded Language Features

### 2.1.1 Section 3 — Declarations and Types

#### 3.2.4 Subtype Predicates

**8652:2023 Reference:** §3.2.4

**Legality Rule:** Static predicates and dynamic predicates are not permitted. A conforming implementation shall reject any `Static_Predicate` or `Dynamic_Predicate` aspect specification.

**Rationale:** Excluded per D19. Predicates are assertion mechanisms; Safe uses `pragma Assert` for runtime checks and relies on D27 type rules for Silver assurance. May be reconsidered in a future revision.

#### 3.4 Derived Types and Classes (Partial)

**8652:2023 Reference:** §3.4

**Legality Rule:** Derived type declarations are retained for non-tagged types only. Type derivation from tagged types, type extensions, and class-wide types are not permitted. A conforming implementation shall reject any `type T is new Parent with ...` declaration or any reference to a class-wide type `T'Class` (rendered as `T.Class` in Safe's dot notation, but still excluded).

**Note:** Simple derived types (`type T is new Integer range 1 .. 100;`) are retained — they are the standard Ada mechanism for creating new numeric types.

#### 3.9 Tagged Types and Type Extensions

**8652:2023 Reference:** §3.9, §3.9.1, §3.9.2, §3.9.3, §3.9.4

**Legality Rule:** Tagged type declarations, type extensions, dispatching operations, abstract types and subprograms, and interface types are not permitted. A conforming implementation shall reject any `tagged` type declaration, any type extension (`type T is new Parent with record`), any `abstract` type or subprogram declaration, and any `interface` type declaration.

**Rationale:** Excluded per D18. Dynamic dispatch requires vtable management and runtime type identification, which is incompatible with static call resolution. Excluding tagged types also eliminates extension aggregates (§4.3.2).

#### 3.10 Access Types (Modified)

**8652:2023 Reference:** §3.10, §3.10.1, §3.10.2

**Legality Rule:** Access-to-object types are retained with SPARK 2022 ownership rules (see §2.3). The following are not permitted:

- Access-to-subprogram types. A conforming implementation shall reject any `access function` or `access procedure` type declaration.
- Anonymous access types. A conforming implementation shall reject any anonymous access type in a parameter declaration, discriminant, object declaration, or return type. Named access types shall be used instead.
- Access-to-constant types (`access constant T`). A conforming implementation shall reject any `access constant` type declaration.

**Retained:**
- Named access-to-variable types (`type T_Ptr is access T;`)
- `not null` access subtypes (`subtype T_Ref is not null T_Ptr;`)
- Incomplete type declarations for recursive structures (`type T;`)
- Allocators (`new T'(...)`)

**Note:** See §2.3 for the full ownership model specification.

#### 3.11 Controlled Types

**8652:2023 Reference:** §7.6, §7.6.1

**Legality Rule:** Controlled types are not permitted. A conforming implementation shall reject any type derived from `Ada.Finalization.Controlled` or `Ada.Finalization.Limited_Controlled`. The packages `Ada.Finalization` are excluded from the retained library (see Annex A).

**Rationale:** Controlled types require compiler-generated finalization code at every scope exit, assignment, and exception handler. Safe uses automatic deallocation via the ownership model instead.

---

### 2.1.2 Section 4 — Names and Expressions

#### 4.1.4 Attributes (Modified)

**8652:2023 Reference:** §4.1.4

**Legality Rule:** All attribute references use dot notation instead of tick notation. The tick character (`'`) is used only for character literals. A conforming implementation shall reject any tick-based attribute reference.

Safe source writes `X.First` where Ada writes `X'First`. See §2.4.1 for the complete dot-notation specification.

#### 4.1.5 User-Defined References

**8652:2023 Reference:** §4.1.5

**Legality Rule:** User-defined references (the `Implicit_Dereference` aspect) are not permitted. A conforming implementation shall reject any `Implicit_Dereference` aspect specification.

**Rationale:** Requires tagged types and generics (containers), both of which are excluded.

#### 4.1.6 User-Defined Indexing

**8652:2023 Reference:** §4.1.6

**Legality Rule:** User-defined indexing (the `Constant_Indexing` and `Variable_Indexing` aspects) is not permitted. A conforming implementation shall reject any `Constant_Indexing` or `Variable_Indexing` aspect specification.

**Rationale:** Requires tagged types and generics (containers), both of which are excluded.

#### 4.2.1 User-Defined Literals

**8652:2023 Reference:** §4.2.1

**Legality Rule:** User-defined literals (the `Integer_Literal`, `Real_Literal`, and `String_Literal` aspects) are not permitted. A conforming implementation shall reject any such aspect specification.

**Rationale:** Requires tagged types, which are excluded.

#### 4.3.2 Extension Aggregates

**8652:2023 Reference:** §4.3.2

**Legality Rule:** Extension aggregates are not permitted. A conforming implementation shall reject any aggregate of the form `(Parent_Expression with ...)`.

**Rationale:** Requires tagged types, which are excluded.

#### 4.3.5 Container Aggregates

**8652:2023 Reference:** §4.3.5

**Legality Rule:** Container aggregates (the `Aggregate` aspect) are not permitted. A conforming implementation shall reject any `Aggregate` aspect specification.

**Rationale:** Requires tagged types and generics (containers), both of which are excluded.

#### 4.5.8 Quantified Expressions

**8652:2023 Reference:** §4.5.8

**Legality Rule:** Quantified expressions (`for all ... =>` and `for some ... =>`) are not permitted. A conforming implementation shall reject any quantified expression.

**Rationale:** Quantified expressions exist primarily for contracts and proof. Safe excludes contracts (D19) and does not require developer-written verification expressions.

#### 4.5.9 Declare Expressions

**8652:2023 Reference:** §4.5.9

**Legality Rule:** Declare expressions are retained. They are part of the SPARK 2022 subset and provide useful local binding within expressions.

#### 4.5.10 Reduction Expressions

**8652:2023 Reference:** §4.5.10

**Legality Rule:** Reduction expressions (the `Reduce` attribute) are not permitted. A conforming implementation shall reject any reduction expression.

**Rationale:** Reduction expressions are complex iterator-based constructs that add significant parser and semantic complexity.

#### 4.7 Qualified Expressions

**8652:2023 Reference:** §4.7

**Legality Rule:** Qualified expressions (`T'(Expression)`) are not permitted. A conforming implementation shall reject any qualified expression. Type annotation syntax (`Expression : Type`) replaces qualified expressions. See §2.4.2.

**Rationale:** Excluded per D21. Safe has no overloading, so most uses of qualified expressions disappear. Type annotation syntax provides the remaining disambiguation capability.

---

### 2.1.3 Section 5 — Statements

#### 5.2.1 Target Name Symbols

**8652:2023 Reference:** §5.2.1

**Legality Rule:** Target name symbols (`@`) are retained. They are part of the SPARK 2022 subset.

#### 5.5.1 User-Defined Iterator Types

**8652:2023 Reference:** §5.5.1

**Legality Rule:** User-defined iterator types (the `Default_Iterator` and `Iterator_Element` aspects) are not permitted. A conforming implementation shall reject any such aspect specification.

**Rationale:** Requires tagged types and generics (containers), both of which are excluded.

#### 5.5.2 Generalized Loop Iteration

**8652:2023 Reference:** §5.5.2

**Legality Rule:** Generalized loop iteration using iterators (`for Cursor in Iterator`) is not permitted when the iteration requires user-defined iterator types. Basic `for ... of` iteration over arrays is retained.

**Retained:**
- `for E of Array_Name loop` — element iteration over arrays
- `for I in Range loop` — standard discrete range iteration

**Excluded:**
- `for Cursor in Container.Iterate loop` — container iterators
- All forms requiring user-defined iterator types

#### 5.5.3 Procedural Iterators

**8652:2023 Reference:** §5.5.3

**Legality Rule:** Procedural iterators are not permitted. A conforming implementation shall reject any procedural iterator.

**Rationale:** Requires access-to-subprogram types, which are excluded.

#### 5.6.1 Parallel Block Statements

**8652:2023 Reference:** §5.6.1

**Legality Rule:** Parallel block statements are not permitted. A conforming implementation shall reject any `parallel` block statement.

**Rationale:** Safe's concurrency model uses static tasks and channels (D28), not parallel blocks.

**Retained statements:** Assignment (§5.2), `if` (§5.3), `case` (§5.4), `loop` (§5.5) with standard `for`/`while`/bare forms, `block` (§5.6), `exit` (§5.7), `goto` (§5.8), `return` (§6.5), `null`, `pragma Assert`.

---

### 2.1.4 Section 6 — Subprograms

#### 6.1.1 Preconditions and Postconditions

**8652:2023 Reference:** §6.1.1

**Legality Rule:** Precondition and postcondition aspects (`Pre`, `Post`, `Pre'Class`, `Post'Class`) are not permitted. A conforming implementation shall reject any such aspect specification.

**Rationale:** Excluded per D19. `pragma Assert` provides runtime checking. Bronze and Silver assurance are guaranteed by compiler-generated annotations and D27 language rules. See §2.7.

#### 6.1.2 The Global and Global'Class Aspects

**8652:2023 Reference:** §6.1.2

**Legality Rule:** Developer-written `Global` and `Global'Class` aspects are not permitted in Safe source. A conforming implementation shall reject any `Global` or `Global'Class` aspect specification in Safe source code.

**Note:** The compiler automatically generates `Global` aspects in the emitted Ada. See §2.2 (SPARK verification aspects) and Section 5 (SPARK Assurance).

#### 6.3.1 Conformance Rules (Modified)

**8652:2023 Reference:** §6.3.1

**Legality Rule:** Subprogram conformance rules are simplified by the absence of overloading. Since each subprogram identifier denotes exactly one subprogram in a given declarative region, the full conformance, mode conformance, and subtype conformance rules of 8652:2023 apply but the overloading-related complexity is eliminated.

#### 6.5.1 Nonreturning Subprograms

**8652:2023 Reference:** §6.5.1

**Legality Rule:** The `No_Return` aspect is retained. A subprogram with `No_Return => True` (or equivalently `pragma No_Return`) shall not return normally. This is useful for abort/halt procedures.

#### 6.6 Overloading of Operators

**8652:2023 Reference:** §6.6

**Legality Rule:** User-defined operator overloading is not permitted. A conforming implementation shall reject any operator function definition (a function whose designator is an operator symbol such as `"+"`). Predefined operators for language-defined types are retained.

**Rationale:** Excluded per D12. User-defined operators participate in overload resolution, which is excluded.

#### 6.6 Subprogram Name Overloading (General)

**8652:2023 Reference:** §6.6, §8.6

**Legality Rule:** Subprogram name overloading is not permitted. A conforming implementation shall reject any declarative region containing two subprogram declarations with the same identifier. The same subprogram name may appear in different packages (qualified by the package name) — this is distinct declarations in distinct namespaces, not overloading.

**Rationale:** Excluded per D12. Overloading is the single biggest obstacle to single-pass compilation in Ada.

---

### 2.1.5 Section 7 — Packages (Modified)

#### 7.1–7.2 Package Specifications and Bodies

**8652:2023 Reference:** §7.1, §7.2

**Legality Rule:** The Ada package specification/body model is replaced by Safe's single-file package model (Section 3 of this specification). The following are not permitted:

- Separate `package body` declarations. A conforming implementation shall reject any `package body` that is not mechanically generated by the compiler from a single Safe source file.
- The `private` section divider within a package specification.
- Package-level `begin...end` initialization blocks.

**Note:** The compiler emits `.ads`/`.adb` file pairs from a single `.safe` source file. See Section 3.

#### 7.3 Private Types and Private Extensions

**8652:2023 Reference:** §7.3, §7.3.1

**Legality Rule:** Ada's `private` type model (full type in body, partial view in spec) is replaced by Safe's opaque type model: `public type T is private record ... end record;`. Private extensions (`type T is new Parent with private`) are not permitted (requires tagged types).

#### 7.3.2 Type Invariants

**8652:2023 Reference:** §7.3.2

**Legality Rule:** Type invariants (`Type_Invariant` aspect) are not permitted. A conforming implementation shall reject any `Type_Invariant` or `Type_Invariant'Class` aspect specification.

**Rationale:** Excluded per D19 (contract aspects excluded).

#### 7.3.3 Default Initial Conditions

**8652:2023 Reference:** §7.3.3

**Legality Rule:** Default initial conditions (`Default_Initial_Condition` aspect) are not permitted. A conforming implementation shall reject any `Default_Initial_Condition` aspect specification.

**Rationale:** Excluded per D19 (contract aspects excluded).

#### 7.3.4 Stable Properties of a Type

**8652:2023 Reference:** §7.3.4

**Legality Rule:** Stable properties (`Stable_Properties` aspect) are not permitted. A conforming implementation shall reject any `Stable_Properties` aspect specification.

**Rationale:** Requires tagged types and contracts, both of which are excluded.

#### 7.4 Deferred Constants

**8652:2023 Reference:** §7.4

**Legality Rule:** Deferred constants (declared in a package specification with completion in the body) are not permitted. All constants shall be fully defined at the point of declaration.

**Rationale:** Safe has no separate specification and body (D6). All declarations are complete at their point of declaration.

#### 7.6 Assignment and Finalization

**8652:2023 Reference:** §7.6, §7.6.1

**Legality Rule:** Controlled types, user-defined `Adjust`, `Finalize`, and `Initialize` procedures, and the finalization framework are not permitted. A conforming implementation shall reject any type derivation from `Ada.Finalization.Controlled` or `Ada.Finalization.Limited_Controlled`.

**Rationale:** See §2.1.1 (Controlled Types). Safe uses automatic deallocation via the ownership model.

---

### 2.1.6 Section 8 — Visibility Rules

#### 8.3.1 Overriding Indicators

**8652:2023 Reference:** §8.3.1

**Legality Rule:** Overriding indicators (`overriding` and `not overriding`) are not permitted. A conforming implementation shall reject any overriding indicator.

**Rationale:** Requires tagged types and dispatching, which are excluded.

#### 8.4 Use Clauses

**8652:2023 Reference:** §8.4

**Legality Rule:** General `use` clauses are not permitted. A conforming implementation shall reject any `use Package_Name;` clause.

`use type` clauses are retained. `use type` makes operator notation usable for the named type without importing all declarations from the type's package.

**Rationale:** Excluded per D13. General `use` clauses create name pollution and make code harder to read.

#### 8.5.2 Exception Renaming Declarations

**8652:2023 Reference:** §8.5.2

**Legality Rule:** Exception renaming declarations are not permitted. A conforming implementation shall reject any exception renaming.

**Rationale:** Exceptions are excluded (§2.1.9).

#### 8.5.5 Generic Renaming Declarations

**8652:2023 Reference:** §8.5.5

**Legality Rule:** Generic renaming declarations are not permitted. A conforming implementation shall reject any generic renaming.

**Rationale:** Generics are excluded (§2.1.10).

#### 8.6 The Context of Overload Resolution

**8652:2023 Reference:** §8.6

**Legality Rule:** The overload resolution rules of §8.6 are not applicable. Since overloading is excluded, every name resolves to exactly one entity. The compiler need not implement overload resolution.

---

### 2.1.7 Section 9 — Tasks and Synchronization

#### 9.1–9.11 Full Ada Tasking

**8652:2023 Reference:** Sections 9.1 through 9.11

**Legality Rule:** The following Ada tasking constructs are not permitted. A conforming implementation shall reject any occurrence of these constructs:

- Task type declarations (`task type T is ...`)
- Dynamic task creation (task allocators)
- Task entries (`entry E ...`)
- Accept statements (`accept E do ... end E;`)
- Selective accept (`select ... or accept ... end select;`)
- Timed entry calls (§9.7.2)
- Conditional entry calls (§9.7.3)
- Asynchronous transfer of control (§9.7.4)
- Abort statements (`abort T;`) (§9.8)
- Requeue statements (`requeue E;`) (§9.5.4)
- User-declared protected types and protected objects

**Note:** Safe provides a restricted concurrency model (D28) via static task declarations and typed channels, which maps to Jorvik-profile SPARK tasking in emitted Ada. See Section 4 of this specification.

**Retained from Section 9:**
- `delay` statements (§9.6) — for use in channel select timeout arms
- `delay until` statements (§9.6) — for periodic task timing
- The `Duration` type and time types from `Ada.Real_Time`

**Related exclusions:**
- Real-time annexes D.1–D.16 — excluded except task priorities (D.1) and the Jorvik profile definition (D.13)
- `Ada.Task_Identification` (C.7.1) — excluded
- `Ada.Synchronous_Task_Control` (D.10) — excluded (channels replace suspension objects)
- `Ada.Asynchronous_Task_Control` (D.11) — excluded

---

### 2.1.8 Section 10 — Program Structure and Compilation

#### 10.1.1 Library Units (Modified)

**8652:2023 Reference:** §10.1.1

**Legality Rule:** A library unit shall be a package. Library-level subprograms are not permitted as compilation units. A conforming implementation shall reject any library-level subprogram declaration or body that is not enclosed within a package.

**Note:** The main entry point is provided by a designated package's initialization or task startup, not by a library-level procedure.

#### 10.1.3 Subunits

**8652:2023 Reference:** §10.1.3

**Legality Rule:** Separate body stubs (`is separate`) are retained per D23. A subprogram body may be provided as a subunit in a separate file.

#### 10.2.1 Elaboration Control

**8652:2023 Reference:** §10.2.1

**Legality Rule:** Explicit elaboration control pragmas (`Elaborate`, `Elaborate_All`, `Elaborate_Body`) are not required. The compiler determines elaboration order from the acyclic `with` dependency graph. Circular `with` dependencies are not permitted.

**Rationale:** Per D7, Safe packages are purely declarative with no circular dependencies. The compiler uses `pragma Preelaborate` or `pragma Pure` where possible in emitted Ada, falling back to GNAT's static elaboration model for packages with non-static initializers.

---

### 2.1.9 Section 11 — Exceptions

**8652:2023 Reference:** Sections 11.1 through 11.6

**Legality Rule:** The entirety of Section 11 (Exceptions) is excluded, except for `pragma Assert` (§11.4.2). A conforming implementation shall reject:

- Exception declarations (`E : exception;`)
- Raise statements and raise expressions (`raise E;`, `raise E with "msg";`)
- Exception handlers (`when E => ...`)
- Exception choice `others` in a handler
- The package `Ada.Exceptions` (§11.4.1)
- `pragma Suppress` and `pragma Unsuppress` (§11.5)

**Retained:**
- `pragma Assert(Condition);` — a failed assertion calls the runtime abort handler with a source location diagnostic. Assertions are always enabled; there is no `Assertion_Policy` pragma.

**Rationale:** Excluded per D14. Exceptions create hidden control flow. SPARK already excludes them. Error handling in Safe uses explicit return values (discriminated records, status codes).

---

### 2.1.10 Section 12 — Generic Units

**8652:2023 Reference:** Sections 12.1 through 12.8

**Legality Rule:** The entirety of Section 12 (Generic Units) is excluded. A conforming implementation shall reject any `generic` declaration, any generic instantiation, and any generic formal parameter.

**Rationale:** Excluded per D16. Generics require instantiation, which is effectively a second compilation pass. Oberon has no generics.

---

### 2.1.11 Section 13 — Representation Issues

#### 13.1–13.5 Representation Aspects (Retained)

**8652:2023 Reference:** §13.1, §13.2, §13.3, §13.4, §13.5

**Legality Rule:** The following representation features are retained:

- Aspect specifications (§13.1.1) for representation aspects (`Size`, `Alignment`, `Object_Size`, `Component_Size`, `Bit_Order`)
- `pragma Pack` (§13.2)
- Enumeration representation clauses (§13.4)
- Record representation clauses (§13.5, §13.5.1)
- Storage place attributes (§13.5.2)
- Bit ordering (§13.5.3)

#### 13.6 Change of Representation

**8652:2023 Reference:** §13.6

**Legality Rule:** Change of representation via type derivation is retained for non-tagged types.

#### 13.7 The Package System

**8652:2023 Reference:** §13.7

**Legality Rule:** The package `System` is retained. `System.Storage_Elements` (§13.7.1) is retained. `System.Address_To_Access_Conversions` (§13.7.2) is excluded (unsafe conversion).

#### 13.8 Machine Code Insertions

**8652:2023 Reference:** §13.8

**Legality Rule:** Machine code insertions are not permitted. A conforming implementation shall reject any machine code insertion.

**Rationale:** Excluded per D24 (system sublanguage features).

#### 13.9 Unchecked Type Conversions

**8652:2023 Reference:** §13.9

**Legality Rule:** Unchecked type conversions (`Ada.Unchecked_Conversion`) are not permitted. A conforming implementation shall reject any instantiation or use of `Unchecked_Conversion`.

**Rationale:** Excluded per D24 (system sublanguage features). Unchecked conversions bypass the type system.

#### 13.10 Unchecked Access Value Creation

**8652:2023 Reference:** §13.10

**Legality Rule:** `Unchecked_Access` is not permitted. A conforming implementation shall reject any use of the `Unchecked_Access` attribute. The `Access` attribute on objects is also excluded (anonymous access types are excluded).

**Rationale:** Excluded per D17. Unchecked access bypasses the ownership model.

#### 13.11 Storage Management

**8652:2023 Reference:** §13.11, §13.11.1, §13.11.2, §13.11.3, §13.11.4, §13.11.5

**Legality Rule:** User-defined storage pools, `Unchecked_Deallocation`, default storage pool specifications, and storage subpools are not permitted. A conforming implementation shall reject any of these constructs.

- Explicit `Unchecked_Deallocation` is replaced by automatic deallocation when the owning object goes out of scope (see §2.3).
- The `Storage_Size` attribute for access types is retained for querying; the `Storage_Pool` attribute is excluded.

#### 13.12 Pragma Restrictions and Pragma Profile

**8652:2023 Reference:** §13.12, §13.12.1

**Legality Rule:** `pragma Restrictions` and `pragma Profile` are not permitted in Safe source. The compiler implicitly enforces all Safe restrictions and emits the appropriate profile (`pragma Profile (Jorvik)`) in the emitted Ada.

#### 13.13 Streams

**8652:2023 Reference:** §13.13, §13.13.1, §13.13.2

**Legality Rule:** Streams and stream-oriented attributes (`Read`, `Write`, `Input`, `Output`) are not permitted. A conforming implementation shall reject any stream operation or stream attribute reference.

**Rationale:** Streams require tagged types and controlled types for dispatching and finalization.

---

### 2.1.12 Annexes

#### Annex B — Interface to Other Languages

**8652:2023 Reference:** Annex B (§B.1–§B.5)

**Legality Rule:** The entirety of Annex B is excluded. `pragma Import`, `pragma Export`, `pragma Convention`, and all interfacing aspects are not permitted. A conforming implementation shall reject any interfacing aspect or pragma.

**Rationale:** Excluded per D24. An imported foreign function is an unverifiable hole in the Silver guarantee. C FFI is reserved for a future system sublanguage specification.

#### Annex C — Systems Programming (Partial)

**8652:2023 Reference:** Annex C

**Excluded:**
- C.1 Access to Machine Operations — excluded (system sublanguage)
- C.3 Interrupt Support — excluded (system sublanguage)
- C.6 Shared Variable Control — `Atomic` and `Volatile` aspects excluded (system sublanguage)
- C.6.1–C.6.5 Atomic Operations packages — excluded
- C.7 Task Information — excluded (C.7.1 `Task_Identification`, C.7.2 `Task_Attributes`, C.7.3 `Task_Termination`)

**Retained:**
- C.2 Required Representation Support — retained (minimum representation requirements)
- C.4 Preelaboration Requirements — retained (`pragma Preelaborate`, `pragma Pure`)
- C.5 Aspect `Discard_Names` — retained

#### Annex D — Real-Time Systems (Partial)

**8652:2023 Reference:** Annex D

**Excluded:** D.2 through D.12, D.14 through D.16. Priority scheduling policies beyond FIFO-within-priorities, dynamic priorities, preemptive abort, synchronous and asynchronous task control, execution time measurements, timing events, and multiprocessor dispatching are all excluded.

**Retained:**
- D.1 Task Priorities — retained (static priorities on Safe task declarations)
- D.3 Priority Ceiling Locking — retained (used by channel-backing protected objects in emitted Ada)
- D.7 Tasking Restrictions — retained (the compiler emits appropriate restriction identifiers)
- D.8 Monotonic Time — retained (`Ada.Real_Time` for `delay until`)
- D.9 Delay Accuracy — retained
- D.13 The Ravenscar and Jorvik Profiles — retained (the compiler emits `pragma Profile (Jorvik)`)

#### Annex E — Distributed Systems

**8652:2023 Reference:** Annex E

**Legality Rule:** The entirety of Annex E is excluded. A conforming implementation shall reject any partition categorization pragma or aspect (`Shared_Passive`, `Remote_Types`, `Remote_Call_Interface`).

#### Annex F — Information Systems

**8652:2023 Reference:** Annex F

**Legality Rule:** The entirety of Annex F is excluded.

**Rationale:** Decimal types and edited output are specialized for business applications.

#### Annex G — Numerics (Partial)

**8652:2023 Reference:** Annex G

**Excluded:**
- G.1 Complex Arithmetic — excluded (requires generics)
- G.3 Vector and Matrix Manipulation — excluded (requires generics)

**Retained:**
- G.2 Numeric Performance Requirements — retained

#### Annex H — High Integrity Systems (Partial)

**8652:2023 Reference:** Annex H

**Excluded:**
- H.1 `pragma Normalize_Scalars` — excluded (incompatible with Safe's initialization model)
- H.3 Reviewable Object Code (`pragma Reviewable`, `pragma Inspection_Point`) — excluded
- H.5 `pragma Detect_Blocking` — excluded (the compiler emits this automatically in Jorvik-profile Ada)
- H.6 `pragma Partition_Elaboration_Policy` — excluded (compiler-managed)
- H.7 Extensions to Global aspects — excluded (Global aspects are compiler-generated)

**Retained:**
- H.2 Documentation of Implementation Decisions — retained
- H.4 High Integrity Restrictions — retained
- H.4.1 Aspect `No_Controlled_Parts` — retained (trivially satisfied since controlled types are excluded)

#### Annex J — Obsolescent Features

**8652:2023 Reference:** Annex J

**Legality Rule:** The entirety of Annex J is excluded. Obsolescent features shall not be used in Safe programs.

---

## 2.2 Excluded SPARK Verification Aspects

The following SPARK-specific aspects are excluded from Safe source code. They exist solely for static verification and have no runtime meaning. The compiler generates the necessary verification annotations automatically in the emitted Ada.

| Aspect | SPARK RM Reference | Status | Rationale |
|--------|-------------------|--------|-----------|
| `Global` | SPARK RM §6.1.4 | Excluded from source; auto-generated in emitted Ada | Compiler generates from name resolution |
| `Depends` | SPARK RM §6.1.5 | Excluded from source; auto-generated in emitted Ada | Compiler generates from data flow analysis |
| `Refined_Global` | SPARK RM §6.1.4 | Excluded | Refinement not needed (no abstract state) |
| `Refined_Depends` | SPARK RM §6.1.5 | Excluded | Refinement not needed (no abstract state) |
| `Refined_State` | SPARK RM §7.2.2 | Excluded | No abstract state declarations |
| `Abstract_State` | SPARK RM §7.1.4 | Excluded | No state abstraction in Safe |
| `Initializes` | SPARK RM §7.1.5 | Excluded from source; auto-generated in emitted Ada | All package variables are initialized |
| `Ghost` | SPARK RM §6.9 | Excluded | Ghost code is for proof (Gold/Platinum) |
| `SPARK_Mode` | SPARK RM §6.9 | Excluded from source; auto-generated in emitted Ada | The entire language is SPARK-compatible |
| `Relaxed_Initialization` | SPARK RM §6.10 | Excluded | Safe requires full initialization |
| `Constant_After_Elaboration` | SPARK RM §3.3 | Excluded | Safe's initialization model makes this unnecessary |
| `Volatile_Function` | SPARK RM §7.1.2 | Excluded | Volatile is excluded (system sublanguage) |

**Note:** A conforming implementation shall reject any of these aspects in Safe source code.

---

## 2.3 Access Types and the Ownership Model

Safe retains access-to-object types with the SPARK 2022 ownership and borrowing model. This section specifies the retained ownership semantics and excluded features.

### 2.3.1 Retained Access Type Features

1. Named access-to-variable types: `type T_Ptr is access T;`
2. `not null` access subtypes: `subtype T_Ref is not null T_Ptr;`
3. Incomplete type declarations for recursive data structures: `type Node;`
4. Allocators: `X := new T'(...);`
5. Null access values and null comparisons: `X = null`, `X /= null`
6. Explicit dereference with dot notation: `X.all` (requires `not null` subtype per D27 Rule 4)
7. Implicit dereference through selected components: `X.Field` (requires `not null` subtype per D27 Rule 4)

### 2.3.2 Ownership Semantics

The SPARK 2022 ownership model applies:

| Operation | Semantics |
|-----------|-----------|
| `Y := X` (access assignment) | **Move**: X becomes null, Y becomes the owner |
| `procedure P (A : in T_Ptr)` | **Observe**: temporary read-only borrow; caller's ownership is frozen during the call |
| `procedure P (A : in out T_Ptr)` | **Borrow**: temporary mutable borrow; caller's ownership is frozen during the call |
| Scope exit of owning variable | **Automatic deallocation**: compiler generates deallocation call in emitted Ada |
| `X := new T'(...)` | **Create**: allocates and assigns ownership to X |

### 2.3.3 Ownership Rules

2. At any point in the program, each allocated object has exactly one owner.
3. Assignment of an access value is a move: the source variable becomes null after the assignment.
4. A parameter of mode `in` with an access type observes the pointed-to object (read-only). The caller's ownership is frozen for the duration of the call.
5. A parameter of mode `in out` with an access type borrows the pointed-to object (read-write). The caller's ownership is frozen for the duration of the call.
6. When the owning variable goes out of scope, the implementation shall automatically deallocate the pointed-to object. In emitted Ada, this is implemented by compiler-generated calls equivalent to `Unchecked_Deallocation` at scope exit points.
7. All ownership checking is local to the compilation unit — no whole-program analysis is required.

### 2.3.4 Not-Null Dereference Rule

8. Dereference of an access value — whether explicit (`.all`) or implicit (selected component through an access value) — shall require the access subtype to be `not null`. A conforming implementation shall reject any dereference where the access subtype at the point of dereference does not exclude null.

This is D27 Rule 4. See §2.8.4 for the complete specification.

### 2.3.5 Excluded Access Type Features

A conforming implementation shall reject:

- Access-to-subprogram types (`access procedure`, `access function`)
- Anonymous access types in any context
- Access-to-constant types (`access constant T`)
- `Unchecked_Deallocation` (deallocation is automatic)
- `Unchecked_Access` attribute
- Access discriminants
- The `Access` attribute on objects (requires anonymous access types)

### 2.3.6 Relationship to SPARK RM

Safe's ownership model is a proper subset of SPARK 2022's ownership model:

- SPARK allows anonymous access types for traversal functions; Safe does not.
- SPARK allows access-to-constant types; Safe does not.
- SPARK allows `Unchecked_Deallocation` (with restrictions); Safe does not.
- Safe's rules are otherwise identical to the SPARK RM ownership rules (SPARK RM §3.10).

---

## 2.4 Syntax Modifications

### 2.4.1 Dot Notation for Attributes

**8652:2023 Reference:** §4.1.4

All attribute references in Safe use dot notation instead of Ada's tick notation.

**Syntax:**

```
attribute_reference ::= prefix '.' attribute_designator
```

This replaces the Ada production:

```
attribute_reference ::= prefix ''' attribute_designator
```

The tick character (`'`) is used only for character literals (`'A'`, `'0'`).

**Resolution rule:** When `X.Name` appears in Safe source, the compiler resolves the reference as follows:

1. If `X` denotes a record object and `Name` is a component of that record type, the reference is a selected component (record field access).
2. If `X` denotes a type or subtype and `Name` is a language-defined attribute of that type, the reference is an attribute reference.
3. If `X` denotes a package name and `Name` is a declaration in that package, the reference is an expanded name (package-qualified access).
4. If `X` denotes an object and `Name` is a language-defined attribute applicable to objects, the reference is an attribute reference.

This resolution is unambiguous because:
- Tagged types are excluded, so `X.Name` cannot be a dispatching call.
- Overloading is excluded, so each `Name` in a given context resolves to exactly one entity.
- The kind of `X` (object, type, package) is always known at the point of use in a single-pass compiler.

**Parameterized attributes** use function-call syntax: `T.Image(42)` (Ada: `T'Image(42)`), `T.Value("42")` (Ada: `T'Value("42")`).

**Emitted Ada:** The compiler emits tick notation in the generated Ada. `X.First` in Safe becomes `X'First` in emitted Ada.

### 2.4.2 Type Annotation Syntax

**8652:2023 Reference:** §4.7

**Syntax:**

```
annotated_expression ::= '(' expression ':' subtype_mark ')'
```

This replaces Ada's qualified expression syntax (`T'(Expression)`). Parentheses are always required around the annotated expression.

**Precedence:** The `:` operator binds loosest within the parenthesized form. No precedence ambiguity arises because the annotation is always enclosed in parentheses.

**Usage contexts:**

- Aggregate disambiguation: `(Buffer'(others => 0) : Buffer_Type)` becomes `((others => 0) : Buffer_Type)`
- Argument position: `Foo((others => 0) : Buffer_Type)` — parentheses already present from the annotation syntax
- Assignment: not needed (the target type provides context)

**Emitted Ada:** The compiler emits qualified expressions in the generated Ada. `((others => 0) : Buffer_Type)` in Safe becomes `Buffer_Type'(others => 0)` in emitted Ada.

---

## 2.5 Attribute Inventory

All retained attributes use dot notation in Safe source (`X.Attr` instead of `X'Attr`). The compiler emits tick notation in the generated Ada.

### 2.5.1 Retained Attributes

| Attribute | 8652:2023 Reference | Applies To | Notes |
|-----------|-------------------|------------|-------|
| `Address` | §13.3 | Objects, subprograms | |
| `Adjacent` | §A.5.3 | Floating point types | |
| `Alignment` | §13.3 | Types, objects | |
| `Base` | §3.5 | Scalar types | |
| `Bit_Order` | §13.5.3 | Record types | |
| `Ceiling` | §A.5.3 | Floating point types | |
| `Component_Size` | §13.3 | Array types | |
| `Compose` | §A.5.3 | Floating point types | |
| `Constrained` | §3.7.2 | Discriminated objects | |
| `Copy_Sign` | §A.5.3 | Floating point types | |
| `Definite` | §3.7.2 | Subtypes | |
| `Delta` | §3.5.10 | Fixed point types | |
| `Denorm` | §A.5.3 | Floating point types | |
| `Digits` | §3.5.8 | Floating point types | |
| `Enum_Rep` | §13.4 | Enumeration types | |
| `Enum_Val` | §13.4 | Enumeration types | |
| `Exponent` | §A.5.3 | Floating point types | |
| `First` | §3.5, §3.6.2 | Scalar types, arrays | |
| `First(N)` | §3.6.2 | Multidimensional arrays | |
| `Floor` | §A.5.3 | Floating point types | |
| `Fore` | §3.5.10 | Fixed point types | |
| `Fraction` | §A.5.3 | Floating point types | |
| `Image` | §4.10 | Scalar types | Parameterized: `T.Image(X)` |
| `Last` | §3.5, §3.6.2 | Scalar types, arrays | |
| `Last(N)` | §3.6.2 | Multidimensional arrays | |
| `Leading_Part` | §A.5.3 | Floating point types | |
| `Length` | §3.6.2 | Arrays | |
| `Length(N)` | §3.6.2 | Multidimensional arrays | |
| `Machine` | §A.5.3 | Floating point types | |
| `Machine_Emax` | §A.5.3 | Floating point types | |
| `Machine_Emin` | §A.5.3 | Floating point types | |
| `Machine_Mantissa` | §A.5.3 | Floating point types | |
| `Machine_Overflows` | §A.5.3 | Floating point types | |
| `Machine_Radix` | §A.5.3 | Floating point types | |
| `Machine_Rounds` | §A.5.3 | Floating point types | |
| `Max` | §3.5 | Scalar types | Parameterized: `T.Max(A, B)` |
| `Max_Alignment_For_Allocation` | §13.11.1 | Access types | |
| `Max_Size_In_Storage_Elements` | §13.11.1 | Types | |
| `Min` | §3.5 | Scalar types | Parameterized: `T.Min(A, B)` |
| `Mod` | §3.5.4 | Modular types | |
| `Model` | §A.5.3 | Floating point types | |
| `Model_Emin` | §A.5.3 | Floating point types | |
| `Model_Epsilon` | §A.5.3 | Floating point types | |
| `Model_Mantissa` | §A.5.3 | Floating point types | |
| `Model_Small` | §A.5.3 | Floating point types | |
| `Modulus` | §3.5.4 | Modular types | |
| `Object_Size` | §13.3 | Types | |
| `Pos` | §3.5.5 | Discrete types | Parameterized: `T.Pos(X)` |
| `Pred` | §3.5 | Scalar types | Parameterized: `T.Pred(X)` |
| `Range` | §3.5, §3.6.2 | Scalar types, arrays | |
| `Range(N)` | §3.6.2 | Multidimensional arrays | |
| `Remainder` | §A.5.3 | Floating point types | |
| `Round` | §3.5.10 | Fixed point types | |
| `Rounding` | §A.5.3 | Floating point types | |
| `Safe_First` | §A.5.3 | Floating point types | |
| `Safe_Last` | §A.5.3 | Floating point types | |
| `Scale` | §3.5.10 | Decimal fixed point types | |
| `Scaling` | §A.5.3 | Floating point types | |
| `Size` | §13.3 | Types, objects | |
| `Small` | §3.5.10 | Fixed point types | |
| `Storage_Size` | §13.11.1 | Access types | Query only |
| `Succ` | §3.5 | Scalar types | Parameterized: `T.Succ(X)` |
| `Truncation` | §A.5.3 | Floating point types | |
| `Unbiased_Rounding` | §A.5.3 | Floating point types | |
| `Val` | §3.5.5 | Discrete types | Parameterized: `T.Val(N)` |
| `Valid` | §13.9.2 | Scalar objects | |
| `Value` | §3.5 | Scalar types | Parameterized: `T.Value("str")` |
| `Wide_Image` | §4.10 | Scalar types | Parameterized |
| `Wide_Value` | §3.5 | Scalar types | Parameterized |
| `Wide_Wide_Image` | §4.10 | Scalar types | Parameterized |
| `Wide_Wide_Value` | §3.5 | Scalar types | Parameterized |
| `Wide_Wide_Width` | §3.5.5 | Discrete types | |
| `Wide_Width` | §3.5.5 | Discrete types | |
| `Width` | §3.5.5 | Discrete types | |

### 2.5.2 Excluded Attributes

| Attribute | 8652:2023 Reference | Rationale |
|-----------|-------------------|-----------|
| `Access` | §3.10.2 | Access-to-subprogram and anonymous access types excluded |
| `Body_Version` | §E.3 | Distributed systems excluded |
| `Callable` | §9.9 | Full tasking excluded |
| `Caller` | §9.5.2 | Entries excluded |
| `Class` | §3.9 | Tagged types excluded |
| `Count` | §9.9 | Entries excluded |
| `External_Tag` | §13.3 | Tagged types excluded |
| `Has_Same_Storage` | §13.3 | Aliasing analysis; not needed |
| `Identity` (exception) | §11.4.1 | Exceptions excluded |
| `Identity` (task) | §C.7.1 | Task identification excluded |
| `Index` | §4.1.5 | User-defined indexing excluded |
| `Input` | §13.13.2 | Streams excluded |
| `Machine_Rounding` | §A.5.3 | Implementation-specific; excluded for simplicity |
| `Old` | §6.1.1 | Postconditions excluded |
| `Output` | §13.13.2 | Streams excluded |
| `Overlaps_Storage` | §13.3 | Aliasing analysis; not needed |
| `Parallel_Reduce` | §4.5.10 | Reduction expressions excluded |
| `Partition_Id` | §E.1 | Distributed systems excluded |
| `Priority` | §D.5.2 | Dynamic priorities excluded (static priorities via task declarations) |
| `Read` | §13.13.2 | Streams excluded |
| `Reduce` | §4.5.10 | Reduction expressions excluded |
| `Result` | §6.1.1 | Postconditions excluded |
| `Storage_Pool` | §13.11 | User-defined storage pools excluded |
| `Stream_Size` | §13.13.2 | Streams excluded |
| `Tag` | §3.9 | Tagged types excluded |
| `Terminated` | §9.9 | Full tasking excluded |
| `Unchecked_Access` | §13.10 | Unsafe; excluded |
| `Update` | — | Obsolescent; delta aggregates preferred |
| `Version` | §E.3 | Distributed systems excluded |
| `Write` | §13.13.2 | Streams excluded |

---

## 2.6 Pragma Inventory

### 2.6.1 Retained Pragmas

| Pragma | 8652:2023 Reference | Notes |
|--------|-------------------|-------|
| `Assert` | §11.4.2 | The sole assertion mechanism in Safe |
| `Compile_Time_Error` | §2.8 | Static error checking |
| `Compile_Time_Warning` | §2.8 | Static warning checking |
| `Inline` | §6.3.2, J.15.1 | Retained per D23 |
| `List` | §2.8 | Listing control |
| `No_Return` | §6.5.1, J.15.2 | Retained as pragma and aspect |
| `Optimize` | §2.8 | Compiler optimization hints |
| `Pack` | §13.2, J.15.3 | Retained per D23 |
| `Page` | §2.8 | Listing control |
| `Preelaborate` | §10.2.1 | Used in emitted Ada; accepted in Safe source |
| `Pure` | §10.2.1 | Used in emitted Ada; accepted in Safe source |
| `Warnings` | GNAT-specific | GNAT compatibility |

**Note:** `pragma Preelaborate` and `pragma Pure` may appear in Safe source to provide hints to the compiler, but the compiler determines the appropriate categorization from the package contents.

### 2.6.2 Excluded Pragmas

| Pragma | 8652:2023 Reference | Rationale |
|--------|-------------------|-----------|
| `All_Calls_Remote` | §E.2.3 | Distributed systems excluded |
| `Assert_And_Cut` | SPARK-specific | Proof-only pragma |
| `Assertion_Policy` | §11.4.2 | Assertions always enabled |
| `Assume` | SPARK-specific | Proof-only pragma |
| `Asynchronous` | §E.4.1 | Distributed systems excluded |
| `Atomic` | §C.6 | System sublanguage feature |
| `Atomic_Components` | §C.6 | System sublanguage feature |
| `Attach_Handler` | §C.3.1 | Interrupt handling excluded |
| `Convention` | §B.1 | Foreign interface excluded (D24) |
| `CPU` | §D.16 | Multiprocessor features excluded |
| `Detect_Blocking` | §H.5 | Auto-generated in emitted Ada |
| `Dispatching_Domain` | §D.16.1 | Multiprocessor features excluded |
| `Elaborate` | §10.2.1 | Compiler-managed elaboration |
| `Elaborate_All` | §10.2.1 | Compiler-managed elaboration |
| `Elaborate_Body` | §10.2.1 | Compiler-managed elaboration |
| `Export` | §B.1 | Foreign interface excluded (D24) |
| `Import` | §B.1 | Foreign interface excluded (D24) |
| `Independent` | §C.6 | System sublanguage feature |
| `Linker_Options` | §B.1 | Foreign interface excluded (D24) |
| `Independent_Components` | §C.6 | System sublanguage feature |
| `Inspection_Point` | §H.3.2 | High integrity annex excluded |
| `Interrupt_Handler` | §C.3.1 | Interrupt handling excluded |
| `Interrupt_Priority` | §D.1 | Use Safe's task priority syntax |
| `Normalize_Scalars` | §H.1 | Incompatible with Safe's initialization model |
| `Partition_Elaboration_Policy` | §H.6 | Compiler-managed |
| `Priority` | §D.1 | Use Safe's task priority syntax |
| `Profile` | §13.12.1 | Compiler emits `pragma Profile (Jorvik)` automatically |
| `Relative_Deadline` | §D.2.6 | EDF scheduling excluded |
| `Remote_Call_Interface` | §E.2.3 | Distributed systems excluded |
| `Remote_Types` | §E.2.2 | Distributed systems excluded |
| `Restrictions` | §13.12 | Compiler-managed |
| `Reviewable` | §H.3.1 | High integrity annex excluded |
| `Shared_Passive` | §E.2.1 | Distributed systems excluded |
| `Suppress` | §11.5 | Suppressing checks is excluded |
| `Unchecked_Union` | §B.3.3 | Foreign interface excluded (D24) |
| `Unsuppress` | §11.5 | Suppressing checks is excluded |
| `Volatile` | §C.6 | System sublanguage feature |
| `Volatile_Components` | §C.6 | System sublanguage feature |

---

## 2.7 Excluded Contract Aspects

All SPARK/Ada contract aspects are excluded from Safe source code per D19. The following table enumerates every excluded contract aspect.

| Contract Aspect | 8652:2023 / SPARK RM Reference | Replacement |
|----------------|-------------------------------|-------------|
| `Pre` | §6.1.1 | `pragma Assert` for runtime checks |
| `Post` | §6.1.1 | `pragma Assert` for runtime checks |
| `Pre'Class` | §6.1.1 | Excluded (tagged types excluded) |
| `Post'Class` | §6.1.1 | Excluded (tagged types excluded) |
| `Contract_Cases` | SPARK RM §6.1.6 | `pragma Assert` for runtime checks |
| `Type_Invariant` | §7.3.2 | Excluded (contracts excluded) |
| `Type_Invariant'Class` | §7.3.2 | Excluded (tagged types excluded) |
| `Default_Initial_Condition` | §7.3.3 | Excluded (contracts excluded) |
| `Subtype_Predicate` | §3.2.4 | Excluded (contracts excluded) |
| `Dynamic_Predicate` | §3.2.4 | Excluded (contracts excluded) |
| `Static_Predicate` | §3.2.4 | Excluded (contracts excluded) |
| `Loop_Invariant` | SPARK RM §5.5 | Excluded (proof-only construct) |
| `Loop_Variant` | SPARK RM §5.5 | Excluded (proof-only construct) |

**Rationale:** `pragma Assert` provides runtime checking capability. Bronze and Silver SPARK assurance are guaranteed automatically: Bronze by compiler-generated `Global`, `Depends`, and `Initializes` annotations; Silver by D27's language rules (wide intermediate arithmetic, strict index typing, division by nonzero type, not-null dereference). Developers seeking Gold or Platinum assurance add contracts to the emitted Ada directly.

---

## 2.8 Silver-by-Construction Rules (D27)

These are new legality rules with no precedent in 8652:2023. They guarantee that every conforming Safe program is Silver-provable (Absence of Runtime Errors) when emitted as Ada/SPARK. No developer annotations are needed.

### 2.8.1 Rule 1: Wide Intermediate Arithmetic

**Modifies:** 8652:2023 §4.5 (Operators and Expression Evaluation)

1. All integer arithmetic expressions shall be evaluated in a mathematical integer type with no overflow. Intermediate results are not subject to range checks.

2. Range checks are performed only when the result of an integer expression is:
   - Assigned to an object
   - Passed as a parameter
   - Returned from a function

3. **Emitted Ada:** The compiler emits intermediate arithmetic using a 64-bit type:

   ```ada
   type Wide_Integer is range -(2**63) .. (2**63 - 1);
   ```

   All integer subexpressions are lifted to `Wide_Integer` before evaluation. At narrowing points (assignment, return, parameter), the compiler emits an explicit type conversion to the target type. GNATprove discharges the intermediate arithmetic trivially (no overflow possible for operations on narrower types) and discharges narrowing checks via interval analysis on the wide result.

4. **Legality Rule:** If the static range of any declared integer type in the program exceeds the 64-bit signed range (-(2^63) .. (2^63 - 1)), the compiler shall reject the program.

5. **Example:**

   ```
   public type Reading is range 0 .. 4095;

   public function Average (A, B : Reading) return Reading is
   begin
       return (A + B) / 2;  -- wide intermediate: max (4095+4095)/2 = 4095
                             -- range check at return: provably in 0..4095
   end Average;
   ```

### 2.8.2 Rule 2: Strict Index Typing

**Modifies:** 8652:2023 §4.1.1 (Indexed Components)

6. The index expression in an `indexed_component` shall be of a type or subtype that is the same as, or a subtype of, the array's index type.

7. **Legality Rule:** If the index expression's type is wider than the array's index type, the program is rejected at compile time. A conforming implementation shall reject any `indexed_component` where the index type is not statically determinable to be the same as, or a subtype of, the array's index type.

8. This guarantees that every array index check is dischargeable by the prover — the index value is constrained by its type to be within the array bounds.

9. **Example:**

   ```
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

10. The programmer narrows at the call site after a bounds check:

    ```
    if N in Channel_Id.First .. Channel_Id.Last then
        Result := Lookup(Channel_Id(N));  -- conversion provably valid inside the if
    end if;
    ```

### 2.8.3 Rule 3: Division by Nonzero Type

**Modifies:** 8652:2023 §4.5.5 (Multiplying Operators)

11. The right operand of the operators `/`, `mod`, and `rem` shall be of a type or subtype whose range does not include zero.

12. **Legality Rule:** A conforming implementation shall reject any division, `mod`, or `rem` operation where the right operand's type or subtype range includes zero.

13. The language provides standard subtypes that exclude zero:

    ```
    subtype Positive is Integer range 1 .. Integer.Last;
    subtype Negative is Integer range Integer.First .. -1;
    ```

14. **Example:**

    ```
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

15. The programmer handles the zero case explicitly:

    ```
    public function Safe_Divide (A, B : Integer) return Integer is
    begin
        if B > 0 then
            return A / Positive(B);   -- Positive excludes zero
        elsif B < 0 then
            return A / Negative(B);   -- Negative excludes zero
        else
            return 0;                 -- zero case handled
        end if;
    end Safe_Divide;
    ```

### 2.8.4 Rule 4: Not-Null Dereference

**Modifies:** 8652:2023 §3.10 (Access Types), §4.1 (Names)

16. Dereference of an access value — whether explicit (`.all`) or implicit (selected component through an access value) — shall require the access subtype to be `not null`.

17. **Legality Rule:** A conforming implementation shall reject any dereference where the access subtype at the point of dereference does not exclude null.

18. Every access type declaration produces two usable forms: a nullable one for storage and a non-null one for dereference:

    ```
    public type Node;
    public type Node_Ptr is access Node;            -- nullable, for storage
    public subtype Node_Ref is not null Node_Ptr;   -- non-null, for dereference
    ```

19. **Example:**

    ```
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

20. Null comparison (`= null`, `/= null`) is always legal on any access type; only dereference requires the not-null guarantee.

### 2.8.5 Combined Effect

21. These four rules ensure that the six categories of runtime check are all dischargeable by GNATprove from type information alone:

| Check | How Discharged |
|-------|---------------|
| Integer overflow | Impossible — wide intermediate arithmetic |
| Range on assignment/return/parameter | Interval analysis on wide intermediates |
| Array index out of bounds | Index type matches array index type |
| Division by zero | Divisor type excludes zero |
| Null dereference | Access subtype is `not null` at every dereference |
| Discriminant check | Discriminant type is discrete and static (retained per D23) |

22. **Ergonomic impact:** The rules push the programmer toward tighter types — `Positive` instead of `Integer` for counts, `Channel_Id` instead of `Integer` for indices, `Seconds` instead of `Integer` for durations, `Node_Ref` instead of `Node_Ptr` for dereference. This produces better, more self-documenting code.

---

## 2.9 Reserved Words

### 2.9.1 Ada Reserved Words

23. Safe retains all Ada 2022 reserved words (8652:2023 §2.9) that are not associated with excluded features. The following Ada reserved words have no meaning in Safe and shall not appear in Safe source except as part of an excluded construct that the compiler rejects:

| Reserved Word | Associated Excluded Feature |
|--------------|---------------------------|
| `abort` | Full tasking (D15) |
| `abstract` | Tagged types (D18) |
| `accept` | Full tasking (D15) |
| `entry` | Full tasking (D15) |
| `exception` | Exceptions (D14) |
| `generic` | Generics (D16) |
| `interface` | Tagged types (D18) |
| `new` (in generics) | Generics (D16); `new` as allocator is retained |
| `overriding` | Tagged types (D18) |
| `protected` | Full tasking (D15); compiler generates protected objects internally |
| `raise` | Exceptions (D14) |
| `requeue` | Full tasking (D15) |
| `synchronized` | Tagged types (D18) |
| `tagged` | Tagged types (D18) |
| `terminate` | Full tasking (D15) |
| `until` (in `select`) | Full Ada select excluded; `delay until` retained |

24. These words remain reserved (a conforming implementation shall reject them as identifiers) to preserve Ada keyword compatibility and avoid source-level confusion.

### 2.9.2 Safe Context-Sensitive Keywords

25. Safe adds the following context-sensitive keywords that are reserved in Safe source but are not Ada reserved words:

| Keyword | Usage | Design Decision |
|---------|-------|----------------|
| `public` | Visibility modifier | D8 |
| `channel` | Channel declaration | D28 |
| `send` | Channel send statement | D28 |
| `receive` | Channel receive statement | D28 |
| `try_send` | Non-blocking channel send | D28 |
| `try_receive` | Non-blocking channel receive | D28 |
| `capacity` | Channel capacity specifier | D28 |

26. These identifiers shall not be used as user-defined names in Safe programs. A conforming implementation shall reject any program that uses a Safe keyword as an identifier.

27. **Emitted Ada mapping:** The emitted Ada maps these to Ada-legal identifiers. For example, `channel Readings` emits as a protected object named `Readings`. The identifier mapping shall be deterministic and documented.
