# Section 2 — Restrictions and Modifications

**This section is normative.**

This section enumerates every feature of ISO/IEC 8652:2023 (Ada 2022) that Safe excludes or modifies. Features not mentioned here are retained with their 8652:2023 semantics. The section is organised by 8652:2023 section number to facilitate systematic cross-referencing.

---

## 2.1 Excluded Language Features

### 2.1.1 Section 2 — Lexical Elements (8652:2023 §2)

1. All lexical rules of 8652:2023 §2 are retained, with the following modifications:

2. **Reserved words (§2.9).** All reserved words defined in 8652:2023 §2.9 remain reserved in Safe, regardless of whether the corresponding language feature is excluded. A conforming implementation shall reject any program that uses a reserved word as an identifier.

3. **Additional reserved words.** Safe adds the following reserved words: `public`, `channel`, `send`, `receive`, `try_send`, `try_receive`, `capacity`, `from`. These identifiers shall not be used as user-defined names in Safe programs. `try_send` remains reserved as a legacy migration spelling even though it is no longer admitted source syntax.

4. **Tick notation (§2.2, §4.1.4).** The tick character (`'`) is used only for single-character string literals (`'A'`). All attribute references use dot notation (see §2.4). Qualified expressions using tick (`T'(Expr)`) are replaced by type annotation syntax (see §2.4.2). A conforming implementation shall reject any use of tick for attribute references or qualified expressions.

### 2.1.2 Section 3 — Declarations and Types (8652:2023 §3)

#### 3.2.4 Subtype Predicates

5. **Subtype predicates (§3.2.4).** `Static_Predicate` and `Dynamic_Predicate` aspects are excluded. A conforming implementation shall reject any subtype declaration bearing a `Static_Predicate` or `Dynamic_Predicate` aspect.

**Note:** Subtype predicates may be reconsidered in a future revision if they prove essential for the type system (see TBD register in §00).

#### 3.4 Derived Types and Classes

6. **Derived types (§3.4).** Non-tagged derived types are retained. Tagged derived types (type extensions) are excluded (see §2.1.2, 3.9 below).

#### 3.9 Tagged Types and Type Extensions

7. **Tagged types (§3.9).** Tagged type declarations, type extensions (§3.9.1), dispatching operations (§3.9.2), abstract types and subprograms (§3.9.3), and Ada interface types (§3.9.4) are excluded. A conforming implementation shall reject any `tagged` type declaration, type extension declaration, `abstract` type or subprogram declaration, or Ada interface type declaration. Safe structural interfaces introduced in PR11.11b are a distinct Safe-only construct; they are compile-time operation contracts, not Ada tagged/interface types.

8. **Related exclusions:** Extension aggregates (§4.3.2), class-wide types, class-wide operations, and all constructs requiring tagged types are excluded as a consequence.

#### 3.10 Access Types

9. **Access-to-subprogram types (§3.10).** Access-to-subprogram type declarations are excluded. A conforming implementation shall reject any access-to-subprogram type declaration. Rationale: indirect calls violate the static call resolution property (D18).

10. **Access-to-object types (§3.10).** All access-to-object type kinds supported by SPARK 2022 are retained with the SPARK 2022 ownership and borrowing model. See §2.3 for the complete ownership specification.

11. **Access discriminants.** Access discriminants (8652:2023 §3.7(8), §3.10) are excluded. A conforming implementation shall reject any discriminant of an access type.

#### 3.11 Controlled Types

12. **Controlled types (§7.6).** The types `Ada.Finalization.Controlled` and `Ada.Finalization.Limited_Controlled` and all user-defined finalization (`Initialize`, `Adjust`, `Finalize`) are excluded. A conforming implementation shall reject any type derivation from `Ada.Finalization.Controlled` or `Ada.Finalization.Limited_Controlled`. Rationale: controlled types require tagged types and introduce implicit code execution on assignment and scope exit; Safe uses ownership-based automatic deallocation instead.

### 2.1.3 Section 4 — Names and Expressions (8652:2023 §4)

#### 4.1.4 Attributes

13. **Attribute notation (§4.1.4).** All attribute references in Safe use dot notation (`X.First`) instead of tick notation (`X'First`). The resolution rules and semantics of each retained attribute are unchanged from 8652:2023; only the surface syntax changes. See §2.4.1 for the complete resolution rule and §2.5 for the attribute inventory.

#### 4.1.5 User-Defined References

14. **User-defined references (§4.1.5).** Excluded. A conforming implementation shall reject any declaration of a type with `Implicit_Dereference` aspect. Rationale: requires tagged types and introduces implicit dereferences.

#### 4.1.6 User-Defined Indexing

15. **User-defined indexing (§4.1.6).** Excluded. A conforming implementation shall reject any declaration of a type with `Constant_Indexing` or `Variable_Indexing` aspect. Rationale: requires tagged types and creates ambiguity in indexing semantics.

#### 4.2.1 User-Defined Literals

16. **User-defined literals (§4.2.1).** Excluded. A conforming implementation shall reject any declaration of a type with `Integer_Literal`, `Real_Literal`, or `String_Literal` aspect. Rationale: requires tagged types.

#### 4.3.2 Extension Aggregates

17. **Extension aggregates (§4.3.2).** Excluded. A conforming implementation shall reject any extension aggregate. Rationale: requires tagged types.

#### 4.3.4 Delta Aggregates

18. **Delta aggregates (§4.3.4).** Retained. Delta aggregates are part of the SPARK 2022 subset and are the standard replacement for the deprecated `Update` attribute.

#### 4.3.5 Container Aggregates

19. **Container aggregates (§4.3.5).** Excluded. A conforming implementation shall reject any container aggregate. Rationale: requires tagged types and generic container library.

#### 4.4 Expressions

20. **Declare expressions (§4.5.9).** Retained. Declare expressions are part of the SPARK 2022 subset (supported since SPARK 21).

#### 4.5.7 Conditional Expressions

21. **Conditional expressions (§4.5.7).** Retained (if-expressions and case-expressions).

#### 4.5.8 Quantified Expressions

22. **Quantified expressions (§4.5.8).** Excluded. A conforming implementation shall reject any quantified expression (`for all`, `for some`). Rationale: quantified expressions are primarily useful in contract specifications, which are excluded (D19).

#### 4.5.10 Reduction Expressions

23. **Reduction expressions (§4.5.10).** Excluded. A conforming implementation shall reject any reduction expression. Rationale: reduction expressions use container iteration and anonymous subprograms, both of which are excluded.

#### 4.6 Type Conversions

24. **Type conversions (§4.6).** Retained. Explicit type conversions remain available and are essential for the Silver-by-construction rules (D27), particularly for narrowing to nonzero or non-null subtypes.

#### 4.7 Qualified Expressions

25. **Qualified expressions (§4.7).** Excluded. The `T'(Expr)` syntax is replaced by type annotation syntax `(Expr as T)`. A conforming implementation shall reject any qualified expression using tick notation. See §2.4.2.

#### 4.8 Allocators

26. **Allocators (§4.8).** Retained, with modified syntax. The allocator syntax uses type annotation in place of qualified expressions: `new (Expr as T)` instead of `new T'(Expr)`. The allocator `new T` (without an initialising expression) is retained where T has default initialisation. See §2.4.2 for interaction with type annotation syntax.

#### 4.10 Image Attributes

27. **Image attributes (§4.10).** Retained in dot notation: `T.Image(X)`, `X.Image`. The semantics are unchanged from 8652:2023.

### 2.1.4 Section 5 — Statements (8652:2023 §5)

28. **Simple and compound statements (§5.1).** Retained from Ada statement syntax: assignment (§5.2), target name symbols (§5.2.1), if statements (§5.3), case statements (§5.4), loop statements (§5.5), exit statements (§5.7) without loop labels, delay statements (§9.6), and return statements (§6.5). Statement-level `declare` blocks (§5.6), `goto` statements (§5.8), and `null` statements are excluded from Safe source.

#### 5.5.1–5.5.3 Iterators

29. **User-defined iterator types (§5.5.1).** Excluded. A conforming implementation shall reject any declaration of a type with `Default_Iterator` or `Iterator_Element` aspect. Rationale: requires tagged types and controlled types.

30. **Generalised loop iteration (§5.5.2).** Excluded for user-defined iterators. The `for E of Array_Name` form for iterating over arrays is retained, as it is part of the SPARK 2022 subset. Iteration over containers and user-defined iterators is excluded.

31. **Procedural iterators (§5.5.3).** Excluded. A conforming implementation shall reject any procedural iterator. Rationale: requires access-to-subprogram types.

#### 5.6.1 Parallel Block Statements

32. **Parallel block statements (§5.6.1).** Excluded. A conforming implementation shall reject any parallel block statement. Rationale: Safe provides concurrency exclusively through static tasks and channels (D28).

### 2.1.5 Section 6 — Subprograms (8652:2023 §6)

33. **Subprogram declarations and bodies (§6.1, §6.3).** Retained. Subprogram bodies appear at the point of declaration (D10). Forward declarations are permitted for mutual recursion.

#### 6.1.1 Preconditions and Postconditions

34. **Preconditions and postconditions (§6.1.1).** Excluded. The aspects `Pre`, `Post`, `Pre'Class`, `Post'Class` are excluded. A conforming implementation shall reject any subprogram bearing these aspects. Rationale: replaced by `pragma Assert` for runtime checks; Bronze and Silver assurance guaranteed by D26/D27 language rules without developer-authored contracts.

#### 6.1.2 Global and Global'Class Aspects

35. **Global and Global'Class aspects (§6.1.2).** Excluded from Safe source. A conforming implementation shall reject any user-authored `Global` or `Global'Class` aspect in Safe source. Rationale: the implementation derives flow information automatically (D22, D26).

#### 6.3.1 Conformance Rules

36. **Subtype conformance for overloading (§6.3.1).** The conformance rules are simplified by the absence of overloading (D12). Each subprogram identifier denotes exactly one subprogram within a given declarative region.

#### 6.4 Subprogram Calls

37. **Subprogram calls (§6.4).** Retained. Named and positional parameter associations (§6.4.1) are retained.

#### 6.5 Return Statements

38. **Return statements (§6.5).** Retained for subprograms. Extended return statements are retained. A `return` statement shall not appear within a task body (see Section 4, non-termination legality rule).

#### 6.5.1 Nonreturning Subprograms

39. **Nonreturning subprograms (§6.5.1).** The `No_Return` aspect is retained.

#### 6.6 Overloading of Operators

40. **Operator overloading (§6.6).** Excluded. A conforming implementation shall reject any user-defined operator function (a function whose designator is an operator symbol). Predefined operators for language-defined types are retained. Rationale: overloading is the primary source of name-resolution complexity (D12).

#### 6.7 Null Procedures

41. **Null procedures (§6.7).** Retained.

#### 6.8 Expression Functions

42. **Expression functions (§6.8).** Retained. Expression functions are part of the SPARK 2022 subset.

### 2.1.6 Section 7 — Packages (8652:2023 §7)

43. **Package specifications and declarations (§7.1).** Modified. Safe uses a single-file package model (D6). See Section 3 for the complete specification.

#### 7.2 Package Bodies

44. **Package bodies (§7.2).** Excluded as a separate construct. A Safe package is a single source file containing all declarations and subprogram bodies. There is no separate `package body`. A conforming implementation shall reject any standalone `package body` compilation unit. See Section 3.

#### 7.3 Private Types and Private Extensions

45. **Private types and private extensions (§7.3).** The Ada `private` section model is excluded. There is no `private` keyword as a section divider in package declarations. Safe uses `public` annotation for visibility (D8) and `private record` for opaque types (D9). Private type extensions (§7.3) are excluded (requires tagged types). Type invariants (§7.3.2), default initial conditions (§7.3.3), and stable properties (§7.3.4) are excluded.

#### 7.4 Deferred Constants

46. **Deferred constants (§7.4).** Excluded. Deferred constants require a separate package body for completion. In Safe's single-file package model, constants are declared and initialised at the point of declaration.

#### 7.5 Limited Types

47. **Limited types (§7.5).** Retained. Limited types without assignment are supported.

#### 7.6 Assignment and Finalization

48. **Assignment and finalization (§7.6).** User-defined finalization via controlled types is excluded (see paragraph 12). The default assignment semantics of 8652:2023 are retained. For access types with ownership, assignment performs a move (see §2.3).

### 2.1.7 Section 8 — Visibility Rules (8652:2023 §8)

49. **Declarative regions and scope (§8.1, §8.2).** Retained.

50. **Visibility (§8.3).** Modified by the `public`/default-private model. See Section 3. Overriding indicators (§8.3.1) are excluded (requires tagged types).

#### 8.4 Use Clauses

51. **General use clauses (§8.4).** Excluded. A conforming implementation shall reject any `use Package_Name;` clause. Rationale: general use clauses create name pollution (D13).

52. **Use type clauses (§8.4).** Retained. `use type T;` makes the predefined operators of type T directly visible without importing all declarations from the enclosing package.

#### 8.5 Renaming Declarations

53. **Renaming declarations (§8.5).** Retained: object renaming (§8.5.1), package renaming (§8.5.3), subprogram renaming (§8.5.4). Exception renaming (§8.5.2) is excluded (exceptions are excluded). Ada generic renaming (§8.5.5) is excluded; Safe-native generics do not introduce a separate renaming form.

#### 8.6 Overload Resolution

54. **The context of overload resolution (§8.6).** Excluded. Overload resolution is not needed because overloading is excluded (D12). Each name resolves to exactly one entity based on declaration-before-use and qualified naming.

### 2.1.8 Section 9 — Tasks and Synchronisation (8652:2023 §9)

55. **Task units and task objects (§9.1).** Excluded. Task types, task objects declared from task types, and the Ada `task type` / `task body` model are excluded. Safe provides static task declarations as a new construct (D28, Section 4).

56. **Task execution and activation (§9.2).** Modified. Task activation semantics are replaced by the Safe task startup model (Section 4): all package-level initialisation completes before any task begins execution.

57. **Task dependence and termination (§9.3).** Modified. Safe tasks shall not terminate (D28 non-termination legality rule, Section 4).

58. **Protected units and protected objects (§9.4).** Excluded as user-declared constructs. A conforming implementation shall reject any user-declared `protected type` or `protected object` declaration. Protected objects may be used internally by an implementation to realise channel semantics; such use is not visible to Safe source.

59. **Intertask communication (§9.5).** Excluded. Entry declarations (§9.5.2), accept statements (§9.5.2), entry calls (§9.5.3), and requeue statements (§9.5.4) are excluded. A conforming implementation shall reject any entry_declaration, accept_statement, entry_call_statement, or requeue_statement. Safe provides channels for inter-task communication (Section 4).

60. **Delay statements (§9.6).** The relative delay statement `delay Duration_Expression;` is retained. `delay` is used in task bodies and in `select` statement delay arms. The type `Duration` from package `Standard` is retained. The absolute delay statement `delay until Time_Expression;` is excluded. A conforming implementation shall reject any `delay until` statement. Rationale: both `Ada.Calendar` and `Ada.Real_Time` are excluded (Annex A), leaving no language-defined time type for the absolute delay expression; relative delays via `Duration` cover periodic task loops and select timeouts.

61. **Select statements (§9.7).** The Ada select statement (selective accept §9.7.1, timed entry calls §9.7.2, conditional entry calls §9.7.3, asynchronous transfer of control §9.7.4) is excluded. Safe provides its own `select` statement for multiplexing channel receive operations (Section 4). A conforming implementation shall reject any selective_accept, timed_entry_call, conditional_entry_call, or asynchronous_select.

62. **Abort of a task (§9.8).** Excluded. A conforming implementation shall reject any `abort` statement.

63. **Task and entry attributes (§9.9).** Excluded. The attributes `Callable`, `Terminated`, `Count`, `Caller` (in dot notation) are excluded.

64. **Shared variables (§9.10).** Retained with modifications. Safe excludes Ada's general shared-variable model and conflict-check policies (§9.10.1). Safe instead admits package-level `shared` roots lowered to compiler-generated protected wrappers. `PR11.12a` through `PR11.12c` admit plain non-discriminated record roots, with `PR11.12b` adding bare shared-root snapshot expressions, whole-record assignment, and nested writes rooted in the shared record, and `PR11.12c` broadening the admitted field subset to copy-safe heap-backed value fields including plain `string`, growable arrays, `list of T`, `map of (K, V)`, and `optional T` when `T` is itself admitted. `PR11.12d` additionally admits shared built-in container roots (`list of T`, growable `array of T`, and `map of (K, V)`) with a limited live protected-operation surface: whole-value snapshot/update, `.length`, `append`, `pop_last`, `contains`, `get`, `set`, and `remove`. `PR11.12e` additionally admits `public shared` declarations and imported use of that same shared read/write surface across package boundaries. Direct indexed mutation, live iteration, and other non-admitted live container operations still require snapshotting the shared value first. `PR11.12f` aligns wrapper ceilings with the channel policy: private closed-world shared roots use the exact maximum accessing task priority, while public or otherwise open-ended shared roots conservatively retain `System.Any_Priority'Last`. `PR11.12g` closes the parent emitted-proof checkpoint over that shipped shared-wrapper surface.

### 2.1.9 Section 10 — Program Structure and Compilation Issues (8652:2023 §10)

65. **Separate compilation (§10.1).** Retained with modifications. Library units shall be packages (D6); library-level subprograms are not permitted as compilation units. `with` clauses (§10.1.2) are retained. Subunits (§10.1.3, `is separate`) are retained. The compilation process (§10.1.4) is implementation-defined.

66. **Elaboration control (§10.2.1).** The pragmas `Elaborate`, `Elaborate_All`, and `Elaborate_Body` are excluded. Safe's prohibition of circular `with` dependencies (D7) reduces elaboration to a topological sort of the dependency graph. A conforming implementation shall reject any program with circular `with` dependencies among compilation units.

### 2.1.10 Section 11 — Exceptions (8652:2023 §11)

67. **Exceptions (§11.1–§11.6).** Section 11 of 8652:2023 is excluded in its entirety. A conforming implementation shall reject any exception declaration (§11.1), exception handler (§11.2), raise statement or raise expression (§11.3), or `pragma Suppress`/`Unsuppress` applied to language-defined checks (§11.5). Rationale: exceptions create hidden control flow incompatible with static analysis (D14).

68. **pragma Assert (§11.4.2).** Retained. `pragma Assert` is the sole assertion mechanism in Safe. A failed assertion calls the runtime abort handler with source location diagnostic information. The `Assertion_Policy` pragma is excluded; assertions are always enabled.

### 2.1.11 Section 12 — Generic Units (8652:2023 §12)

69. **Ada generic units (§12.1–§12.8).** Section 12 of 8652:2023 is excluded in its entirety. A conforming implementation shall reject any Ada generic declaration, generic body, or Ada generic instantiation. Safe instead admits its own native generic type and function surface (`type name of ...`, `function name of ...`) with frontend monomorphization; that Safe-native surface is specified elsewhere in this document set and is not an adoption of Ada §12.

### 2.1.12 Section 13 — Representation Issues (8652:2023 §13)

70. **Operational and representation aspects (§13.1).** Retained where applicable. Aspect specifications (§13.1.1) are retained for retained aspects.

71. **Packed types (§13.2).** Retained. `pragma Pack` is retained.

72. **Representation attributes (§13.3).** Retained in dot notation (e.g., `T.Size`, `T.Alignment`).

73. **Enumeration representation clauses (§13.4).** Excluded from Safe source. A conforming implementation shall reject any user-authored enumeration representation clause.

74. **Record layout (§13.5).** Record representation clauses (§13.5.1), storage place attributes (§13.5.2), and bit ordering (§13.5.3) are excluded from Safe source. A conforming implementation shall reject any user-authored record representation clause or related storage-layout clause.

75. **Change of representation (§13.6).** Retained where applicable (non-tagged derived types only).

76. **The package System (§13.7).** Retained. `System.Storage_Elements` (§13.7.1) is retained. `System.Address_To_Access_Conversions` (§13.7.2) is excluded (unsafe conversion).

77. **Machine code insertions (§13.8).** Excluded. A conforming implementation shall reject any machine code insertion. Rationale: unsafe capability reserved for a future system sublanguage (D24).

78. **Unchecked type conversions (§13.9).** Excluded. `Ada.Unchecked_Conversion` is excluded. A conforming implementation shall reject any instantiation of or reference to `Ada.Unchecked_Conversion`. Data validity (§13.9.1) and the `Valid` attribute (§13.9.2) are retained (dot notation: `X.Valid`).

79. **Unchecked access value creation (§13.10).** The `Unchecked_Access` attribute is excluded. A conforming implementation shall reject any use of `.Unchecked_Access`. The `Access` attribute (`.Access`) is retained for uses consistent with the ownership model (see §2.3).

80. **Storage management (§13.11).** User-defined storage pools, storage pool aspects, and `Ada.Unchecked_Deallocation` are excluded from Safe source. A conforming implementation shall reject any `Storage_Pool` aspect specification, any storage pool type declaration, and any reference to `Ada.Unchecked_Deallocation` in Safe source. Deallocation is automatic on scope exit for pool-specific owning access objects (see §2.3). Storage allocation attributes (§13.11.1) — `Storage_Size` in dot notation — are retained.

81. **Restrictions and profiles (§13.12).** `pragma Restrictions` and `pragma Profile` are excluded from Safe source. The language's restrictions are defined by this specification, not by user-declared pragmas. A conforming implementation may use restriction pragmas internally.

82. **Streams (§13.13).** Excluded. Stream-oriented attributes and the streams subsystem are excluded. A conforming implementation shall reject any stream attribute reference or stream type declaration. Rationale: streams require tagged types and controlled types.

83. **Freezing rules (§13.14).** Retained. The freezing rules of 8652:2023 §13.14 apply to Safe programs.

### 2.1.13 Annexes

#### Annex B — Interface to Other Languages

84. **Interface to other languages (Annex B).** Excluded in its entirety. `pragma Import`, `pragma Export`, `pragma Convention`, and all of Annex B are excluded from Safe source. A conforming implementation shall reject any such pragma. Rationale: foreign language interface is excluded from the safe language and reserved for a future system sublanguage (D24).

#### Annex C — Systems Programming

85. **Systems programming (Annex C).** Excluded. Interrupt handling (C.3), machine operations (C.1), and other Annex C features are excluded.

#### Annex D — Real-Time Systems

86. **Real-time systems (Annex D).** Excluded except for task priorities. Safe retains the `Priority` aspect on task declarations (Section 4). All other Annex D features (D.1–D.14) including `Ada.Real_Time`, monotonic time, timing events, execution-time clocks, and group budgets are excluded. The `delay until` statement is excluded (see paragraph 60).

#### Annex E — Distributed Systems

87. **Distributed systems (Annex E).** Excluded in its entirety.

#### Annex F — Information Systems

88. **Information systems (Annex F).** Excluded in its entirety. Rationale: requires Ada generic decimal libraries and related Annex F runtime surface beyond the admitted Safe-native generic feature set.

#### Annex G — Numerics

89. **Numerics (Annex G).** The core numerics model from §3.5 is retained. Annex G extensions (complex types G.1, generic elementary functions G.2) are excluded; they require broader numeric libraries and Ada generic packages beyond the admitted Safe-native generic feature set.

#### Annex H — High Integrity Systems

90. **High integrity systems (Annex H).** The restrictions defined by Annex H that overlap with Safe's own restrictions are subsumed. `pragma Normalize_Scalars` is excluded (see §2.6).

#### Annex J — Obsolescent Features

91. **Obsolescent features (Annex J).** Excluded in their entirety. A conforming implementation shall reject any use of Annex J features. This includes `delta` constraint, `at` clause for entries, and other obsolescent forms.

---

## 2.2 Excluded SPARK Verification-Only Aspects

92. The following aspects exist solely for static verification in SPARK and have no runtime meaning. They are excluded from Safe source because Safe derives this information automatically (D22, D26):

| Aspect | 8652:2023 / SPARK RM Reference | Rationale |
|--------|-------------------------------|-----------|
| `Global` | §6.1.2, SPARK RM §6.1.4 | Derived automatically by the implementation |
| `Depends` | SPARK RM §6.1.5 | Derived automatically by the implementation |
| `Refined_Global` | SPARK RM §6.1.4 | Derived automatically by the implementation |
| `Refined_Depends` | SPARK RM §6.1.5 | Derived automatically by the implementation |
| `Refined_State` | SPARK RM §7.2.2 | No abstract state in Safe's single-file model |
| `Abstract_State` | SPARK RM §7.1.4 | No abstract state in Safe's single-file model |
| `Initializes` | SPARK RM §7.1.5 | Derived automatically by the implementation |
| `Ghost` | SPARK RM §6.9 | Ghost code for proof; out of scope for Safe |
| `SPARK_Mode` | SPARK RM §1.4 | The entire language is the mode |
| `Relaxed_Initialization` | SPARK RM §6.10 | Excluded; full initialisation required |
| `Contract_Cases` | §6.1.1, SPARK RM §6.1.3 | Excluded with all contract aspects |
| `Subprogram_Variant` | SPARK RM §6.1.6 | Excluded; proof-only aspect |

93. A conforming implementation shall reject any Safe source containing a user-authored instance of any aspect listed in paragraph 92.

---

## 2.3 Access Types and Ownership Model

94. Safe retains access-to-object types with the full SPARK 2022 ownership and borrowing model. This section specifies Safe's ownership rules directly and self-containedly. The SPARK RM §3.10 and SPARK UG §5.9 are informative design precedent; the normative rules are those stated below.

### 2.3.1 Retained Access Type Kinds

95. The following access-to-object type kinds are permitted in Safe:

| Access type kind | Safe declaration syntax | Ownership semantics |
|-----------------|----------------------|-------------------|
| Pool-specific access-to-variable | `type T_Ptr is access T;` | Owner — can be moved, borrowed, or observed |
| Non-null subtype of pool-specific | `subtype T_Ref is not null T_Ptr;` | Non-null owner — legal for dereference |
| Anonymous access-to-variable | `A : access T = ...` | Local borrower — X frozen while A in scope |
| Anonymous access-to-constant | `A : access constant T = ...` | Local observer — X frozen while A in scope |
| Named access-to-constant | `type C_Ptr is access constant T;` | Not subject to ownership checking; data is constant |
| General access-to-variable | `type G_Ptr is access all T;` | Subject to ownership checking; cannot be deallocated |

### 2.3.2 Move Semantics

96. When a named access-to-variable value is assigned to another object of the same type, a **move** occurs:

   (a) The source object becomes `null` after the assignment.

   (b) The target object becomes the new owner of the designated object.

   (c) A conforming implementation shall reject any subsequent dereference of the source object unless it has been reassigned or verified as non-null.

97. Move semantics apply to:

   (a) Direct assignment of access-to-variable values: `Y = X;`

   (b) Return of an access-to-variable value from a function.

   (c) Passing an access-to-variable value as an `out` or `in out` mode parameter (the caller's value may be moved out).

97a. **Null-before-move legality rule.** The target of any move into a pool-specific owning access variable — whether by assignment or by `out` / `in out` parameter copy-back — shall be provably null at the point of the move. A conforming implementation shall verify this by flow analysis: after declaration with default initialisation (null), after a move-out (the source becomes null per paragraph 96(a)), or after explicit assignment of `null`, the variable is in the null state. After an allocator or any move-in, the variable is in the non-null state. A conforming implementation shall reject any move into a variable that is not provably null at that program point, with a diagnostic identifying the variable and the unresolvable ownership conflict.

97b. **Rationale.** Without this rule, overwriting a non-null owning access variable leaks the old designated object — there is no mechanism to deallocate it mid-scope (`Ada.Unchecked_Deallocation` is excluded, paragraph 107(c), and automatic deallocation occurs only at scope exit, paragraph 104). The rule prevents leaks by construction and uses the same flow-analysis machinery already required for paragraph 96(c) (tracking the null/non-null state of moved-from variables).

97c. **Channel exclusion.** Section 4, §4.2, paragraph 14 excludes access-typed channel element subtypes and composite channel element types containing access-type subcomponents. Channel operations therefore do not participate in ownership transfer or move semantics.

### 2.3.3 Borrowing

98. A **borrow** creates a temporary mutable alias to a designated object. Borrowing occurs when:

   (a) An anonymous access-to-variable object is initialised from an owning access value: `Y : access T = X;`

   (b) An `in out` mode access parameter receives an owning access value at a call site.

99. During a borrow:

   (a) The borrower has mutable access to the designated object.

   (b) The lender (the source of the borrow) is **frozen**: no read, write, or move of the lender is permitted while the borrow is active.

   (c) The borrow ends when the borrower goes out of scope (for local borrows) or when the subprogram returns (for parameter borrows).

   (d) Upon borrow end, the lender is unfrozen and regains full ownership.

100. **Reborrowing.** A borrower may create a further borrow from its own access value, subject to the same freezing rules. The chain of borrows forms a stack: the innermost borrow must end before the outer borrow can be accessed.

100a. **Initialisation-only restriction.** An anonymous access variable (whether access-to-variable or access-to-constant) shall only receive its value at its point of declaration. A conforming implementation shall reject any assignment to an anonymous access variable after its declaration. Rationale: restricting anonymous access to initialisation ensures that the borrower/observer's lifetime is lexically determined by its declaration point, which is essential for the lifetime-containment rule below. This is consistent with SPARK 2022's treatment of anonymous access objects.

### 2.3.4 Observing

101. An **observe** creates a temporary read-only alias to a designated object. Observing occurs when:

   (a) An anonymous access-to-constant object is initialised from an owning access value using `.Access`: `Y : access constant T = X.Access;`

   (b) An `in` mode access parameter receives an owning access value at a call site.

102. During an observe:

   (a) The observer has read-only access to the designated object.

   (b) The observed object (the source) is **frozen**: no write or move of the source is permitted while the observe is active. Reads of the source are permitted.

   (c) Multiple simultaneous observers of the same object are permitted (multiple read-only aliases are safe).

   (d) The observe ends when the observer goes out of scope or the subprogram returns.

### 2.3.4a Lifetime Containment

102a. **Lifetime-containment legality rule.** The scope of a borrower or observer shall be contained within the scope of the lender or observed object. Specifically:

   (a) For a local borrow or observe (created at a variable declaration), the borrower/observer shall be declared in the same scope as, and after, the lender/observed variable — or in an inner scope. A conforming implementation shall reject any borrow or observe where the borrower/observer could outlive the lender/observed object.

   (b) For a parameter borrow or observe (created at a subprogram call), the borrow/observe ends when the subprogram returns (paragraphs 99(c), 102(d)), which is before the caller's scope exits. This is safe by construction.

   (c) At scope exit, all borrows and observes on objects in that scope shall have ended before any automatic deallocation of objects in that scope occurs. With reverse declaration order (paragraph 105) and the restriction that borrowers/observers are declared after their lenders (item (a) above), this is guaranteed: borrowers/observers exit scope first (reverse order), ending the borrow/observe, then owners exit scope and are deallocated.

102b. **No dangling access values.** No access value — whether owning, borrowing, observing, or constant — shall designate a deallocated object at any reachable program point. The combination of lifetime containment (paragraph 102a), the initialisation-only restriction for anonymous access (paragraph 100a), Ada's accessibility rules (§2.3.8), the exclusion of `Unchecked_Access` (paragraph 107(b)), and automatic deallocation only at scope exit (paragraph 104) collectively ensures this property. A conforming implementation shall reject any program where it cannot establish that all access values designate live objects throughout their reachable lifetime.

### 2.3.5 Allocators and Automatic Deallocation

103. **Allocators.** The `new` allocator creates a new designated object and returns an owning access value. The allocator syntax is:

   - `new (Expr as T)` — creates an object of type T initialised with Expr.
   - `new T` — creates an object of type T with default initialisation (when T has default initialisation).

103a. **Allocation failure.** If an allocator cannot obtain sufficient storage to create the designated object, the program is aborted. The implementation shall invoke the runtime abort handler with a diagnostic that identifies the source location of the failing allocator. This is consistent with the error model for `pragma Assert` failure: both are non-recoverable conditions that terminate the program. Rationale: in 8652:2023, allocation failure raises `Storage_Error`; since exceptions are excluded (paragraph 31), Safe replaces the exception with a hard abort.

104. **Automatic deallocation.** When a pool-specific access variable — whether access-to-variable (owning) or access-to-constant (named) — goes out of scope and its value is non-null, the designated object is automatically deallocated. Deallocation occurs at every scope exit point:

   (a) Normal end of scope (the textual `end` of the enclosing block, subprogram, or package).

   (b) Early `return` statements.

   (c) `exit` statements that transfer control out of the owning scope.

104a. **Named access-to-constant deallocation.** Named access-to-constant types (`type C_Ptr is access constant T;`) are pool-specific and allocate from a pool. Although they are exempt from ownership checking (paragraph 95), their designated objects must be reclaimed. Automatic deallocation at scope exit applies to named access-to-constant variables in the same manner as pool-specific access-to-variable variables. Since `Unchecked_Deallocation` is excluded (paragraph 107(c)), scope-exit deallocation is the only mechanism for reclaiming storage allocated through named access-to-constant types.

105. When multiple pool-specific access objects (whether owning or constant) exit scope simultaneously, the order of deallocation is the reverse of their declaration order.

106. General access-to-variable types (`access all T`) cannot be deallocated, as they may designate stack-allocated local objects.

### 2.3.6 Excluded Access Features

107. The following access-related features are excluded:

   (a) Access-to-subprogram types (paragraph 9).

   (b) `Unchecked_Access` attribute (paragraph 79).

   (c) `Ada.Unchecked_Deallocation` (paragraph 80).

   (d) Access discriminants (paragraph 11).

   (e) Storage pools and user-defined storage management (paragraph 80).

### 2.3.7 Ownership Checking Scope

108. All ownership checking is local to the compilation unit — no whole-program analysis is required. A conforming implementation shall verify ownership rules using only the current compilation unit's source and the dependency interface information of its direct and transitive dependencies. This is compatible with separate compilation.

### 2.3.8 Accessibility Rules for `.Access` and General Access Types

109. Safe retains Ada's accessibility rules (8652:2023 §3.10.2) as compile-time legality rules. These rules prevent access values from outliving the objects they designate. In Safe's simplified type landscape (no tagged types, no anonymous access return types, no access discriminants), all accessibility checks reduce to compile-time checks — no runtime accessibility check is ever required.

110. **`.Access` on a heap-designated object.** When `.Access` is applied to an object designated by a pool-specific owning access value (a heap-allocated object), the result has the accessibility level of the owning access type's declaration. This permits:

   (a) Creating an anonymous access-to-constant observer: `Y : access constant T = X.Access;` — governed by the borrowing/observing rules (§2.3.3, §2.3.4) and lifetime containment (§2.3.4a).

   (b) Creating an anonymous access-to-variable borrow: `Y : access T = X;` — governed by borrowing rules.

111. **`.Access` on a local object.** When `.Access` is applied to a local variable (a stack-allocated object), the result has the accessibility level of the local scope in which the variable is declared. A conforming implementation shall reject any use of `.Access` on a local variable where the result could escape the variable's scope. Specifically:

   (a) **Return:** A function shall not return the result of `.Access` applied to one of its local variables or parameters. The accessibility level of the local is deeper than the function's return type. A conforming implementation shall reject such a return.

   (b) **Assignment to outer-scope variable:** The result of `.Access` on a local variable shall not be assigned to a variable declared in an enclosing scope whose lifetime exceeds the local variable's scope. A conforming implementation shall reject any such assignment.

   (c) **Channel send:** The result of `.Access` on a local variable shall not be sent through a channel, since the channel's lifetime exceeds the local scope. A conforming implementation shall reject such a send.

   (d) **Inner-scope use:** The result of `.Access` on a local variable may be stored in a variable declared in the same scope or an inner scope, subject to the lifetime-containment rule (paragraph 102a). This is the normal borrow/observe pattern.

112. **General access types (`access all T`).** General access values are subject to the same accessibility rules. A general access value shall not designate an object whose accessibility level is deeper than the general access type's declaration. This prevents a general access variable from outliving the stack object it designates:

```ada
type G_Ptr is access all Integer;  -- declared at package level

function Bad return G_Ptr is
begin
    X : Integer = 42;
    return X.Access;  -- REJECTED: X has deeper accessibility than G_Ptr
end Bad;
```

The following is conforming:

```ada
type G_Ptr is access all Integer;

procedure Use_Local is
begin
    X : Integer = 42;
    G : G_Ptr = X.Access;   -- legal: G declared in same scope as X
    G.all = 99;              -- legal: G_Ptr is not null by flow analysis
                               -- (or use not-null subtype for dereference)
end Use_Local;
-- G goes out of scope before X (reverse declaration order)
-- G_Ptr cannot be deallocated (paragraph 106), but X's storage is
-- reclaimed normally — G is no longer reachable
```

113. **No runtime accessibility checks.** In Safe, accessibility violations are always detectable at compile time. The following properties ensure this:

   (a) No anonymous access return types — Safe does not use anonymous access as a function return type, which is the primary source of runtime accessibility checks in full Ada.

   (b) No tagged types — no dispatching calls that could return access values with dynamic accessibility levels.

   (c) No access discriminants — excluded (paragraph 107(d)).

   (d) `Unchecked_Access` excluded — the only mechanism to bypass accessibility levels is absent (paragraph 107(b)).

A conforming implementation shall discharge the accessibility check row in the runtime check table (§5.3.8) entirely at compile time. No runtime accessibility check code shall be emitted.

---

## 2.4 Notation Changes

### 2.4.1 Dot Notation for Attributes

109. All 8652:2023 attribute references using tick notation (`X'Attr`) are replaced by dot notation (`X.Attr`) in Safe. The semantics of each retained attribute are unchanged; only the surface syntax changes.

110. **Resolution rule.** When `X.Name` appears in source, the implementation resolves it as follows:

   (a) If `X` denotes a record object, `Name` is resolved as a record component (field access).

   (b) If `X` denotes a type or subtype mark, `Name` is resolved as an attribute of that type. The retained attributes are listed in §2.5.

   (c) If `X` denotes a package name, `Name` is resolved as a declaration within that package.

   (d) If `X` denotes an access value, `Name` is resolved as implicit dereference followed by component selection (equivalent to `X.all.Name`).

111. This resolution is unambiguous because Safe has no overloading (D12) and no tagged types (D18). The implementation determines which case applies from the type or kind of `X`, which is known at the point of use due to declaration-before-use.

112. **Parameterised attributes.** Attributes that take parameters use function-call syntax: `T.Image(42)`, `T.Value("123")`. No special syntax is needed; the attribute is resolved as if it were a function of the type.

### 2.4.2 Type Annotation Syntax

113. Ada's qualified expression syntax `T'(Expr)` is replaced by type annotation syntax `(Expr as T)`.

114. **Grammar.**

```
annotated_expression ::= '(' expression 'as' subtype_mark ')'
```

115. **Precedence.** The keyword `as` binds looser than any operator. Parentheses are always required around type annotation expressions to avoid ambiguity with declaration syntax.

116. **Usage contexts.** Type annotation is used wherever Ada 2022 uses qualified expressions:

   (a) Aggregate disambiguation: `(others = 0) as Buffer_Type` becomes `((others = 0) as Buffer_Type)`.

   (b) Allocators: `new T'(Expr)` becomes `new (Expr as T)`.

   (c) Type assertion in expressions: `T'(X)` becomes `(X as T)`.

---

## 2.5 Attribute Inventory

117. The following tables list all language-defined attributes from 8652:2023 with their Safe status. All retained attributes use dot notation.

### 2.5.1 Retained Attributes

118.

| 8652:2023 Attribute | Safe Dot Notation | Reference |
|--------------------|--------------------|-----------|
| `Access` | `.Access` | §3.10.2(24) |
| `Address` | `.Address` | §13.3(11) |
| `Adjacent` | `.Adjacent` | §A.5.3(48) |
| `Aft` | `.Aft` | §3.5.10(5) |
| `Alignment` | `.Alignment` | §13.3(23) |
| `Base` | `.Base` | §3.5(15) |
| `Bit_Order` | `.Bit_Order` | §13.5.3(4) |
| `Ceiling` | `.Ceiling` | §A.5.3(33) |
| `Component_Size` | `.Component_Size` | §13.3(69) |
| `Compose` | `.Compose` | §A.5.3(24) |
| `Constrained` | `.Constrained` | §3.7.2(3) |
| `Copy_Sign` | `.Copy_Sign` | §A.5.3(51) |
| `Definite` | `.Definite` | §12.5.1(23) |
| `Delta` | `.Delta` | §3.5.10(3) |
| `Denorm` | `.Denorm` | §A.5.3(9) |
| `Digits` | `.Digits` | §3.5.8(2), §3.5.10(7) |
| `Enum_Rep` | `.Enum_Rep` | §13.4(10.3) |
| `Enum_Val` | `.Enum_Val` | §13.4(10.5) |
| `Exponent` | `.Exponent` | §A.5.3(18) |
| `First` | `.First` | §3.5(12), §3.6.2(3) |
| `First_Valid` | `.First_Valid` | §3.5.5(7.2) |
| `Floor` | `.Floor` | §A.5.3(30) |
| `Fore` | `.Fore` | §3.5.10(4) |
| `Fraction` | `.Fraction` | §A.5.3(21) |
| `Image` | `.Image` | §4.10(30), §4.10(33) |
| `Last` | `.Last` | §3.5(13), §3.6.2(5) |
| `Last_Valid` | `.Last_Valid` | §3.5.5(7.4) |
| `Leading_Part` | `.Leading_Part` | §A.5.3(54) |
| `Length` | `.Length` | §3.6.2(9) |
| `Machine` | `.Machine` | §A.5.3(60) |
| `Machine_Emax` | `.Machine_Emax` | §A.5.3(8) |
| `Machine_Emin` | `.Machine_Emin` | §A.5.3(7) |
| `Machine_Mantissa` | `.Machine_Mantissa` | §A.5.3(6) |
| `Machine_Overflows` | `.Machine_Overflows` | §A.5.3(12) |
| `Machine_Radix` | `.Machine_Radix` | §A.5.3(2) |
| `Machine_Rounds` | `.Machine_Rounds` | §A.5.3(11) |
| `Max` | `.Max` | §3.5(19) |
| `Max_Alignment_For_Allocation` | `.Max_Alignment_For_Allocation` | §13.11.1(4) |
| `Max_Size_In_Storage_Elements` | `.Max_Size_In_Storage_Elements` | §13.11.1(3) |
| `Min` | `.Min` | §3.5(16) |
| `Mod` | `.Mod` | §3.5.4(17) |
| `Model` | `.Model` | §A.5.3(68) |
| `Model_Emin` | `.Model_Emin` | §A.5.3(65) |
| `Model_Epsilon` | `.Model_Epsilon` | §A.5.3(66) |
| `Model_Mantissa` | `.Model_Mantissa` | §A.5.3(64) |
| `Model_Small` | `.Model_Small` | §A.5.3(67) |
| `Modulus` | `.Modulus` | §3.5.4(17) |
| `Object_Size` | `.Object_Size` | §13.3(58) |
| `Overlaps_Storage` | `.Overlaps_Storage` | §13.3(73.1) |
| `Pos` | `.Pos` | §3.5.5(2) |
| `Pred` | `.Pred` | §3.5(25) |
| `Range` | `.Range` | §3.5(14), §3.6.2(7) |
| `Remainder` | `.Remainder` | §A.5.3(45) |
| `Round` | `.Round` | §3.5.10(12) |
| `Rounding` | `.Rounding` | §A.5.3(36) |
| `Safe_First` | `.Safe_First` | §A.5.3(71) |
| `Safe_Last` | `.Safe_Last` | §A.5.3(72) |
| `Scale` | `.Scale` | §3.5.10(11) |
| `Scaling` | `.Scaling` | §A.5.3(27) |
| `Size` | `.Size` | §13.3(40), §13.3(45) |
| `Small` | `.Small` | §3.5.10(2) |
| `Storage_Size` | `.Storage_Size` | §13.11.1(1) |
| `Succ` | `.Succ` | §3.5(22) |
| `Truncation` | `.Truncation` | §A.5.3(42) |
| `Unbiased_Rounding` | `.Unbiased_Rounding` | §A.5.3(39) |
| `Val` | `.Val` | §3.5.5(5) |
| `Valid` | `.Valid` | §13.9.2(3) |
| `Value` | `.Value` | §3.5(52) |
| `Wide_Image` | `.Wide_Image` | §4.10(34) |
| `Wide_Value` | `.Wide_Value` | §3.5(53) |
| `Wide_Wide_Image` | `.Wide_Wide_Image` | §4.10(35) |
| `Wide_Wide_Value` | `.Wide_Wide_Value` | §3.5(54) |
| `Wide_Wide_Width` | `.Wide_Wide_Width` | §3.5.5(7.7) |
| `Wide_Width` | `.Wide_Width` | §3.5.5(7.6) |
| `Width` | `.Width` | §3.5.5(7.5) |

### 2.5.2 Excluded Attributes

119.

| 8652:2023 Attribute | Reason for Exclusion |
|--------------------|---------------------|
| `Body_Version` | Requires separate body (§7.2) |
| `Callable` | Requires Ada tasking (§9.9) |
| `Caller` | Requires entries (§9.9) |
| `Class` | Requires tagged types (§3.9) |
| `Count` | Requires entries (§9.9) |
| `External_Tag` | Requires tagged types (§13.3) |
| `Has_Same_Storage` | Implementation-internal |
| `Identity` (exception) | Requires exceptions (§11.4.1) |
| `Identity` (task) | Requires Ada tasking (§9.1) |
| `Index` | Requires iterators (§5.5.2) |
| `Input` | Requires streams (§13.13.2) |
| `Machine_Rounding` | Implementation-internal |
| `Old` | Requires postconditions (§6.1.1) |
| `Output` | Requires streams (§13.13.2) |
| `Parallel_Reduce` | Requires parallel features (§5.6.1) |
| `Partition_Id` | Requires distributed systems (Annex E) |
| `Put_Image` | Requires tagged types (§4.10) |
| `Read` | Requires streams (§13.13.2) |
| `Reduce` | Requires reduction expressions (§4.5.10) |
| `Result` | Requires postconditions (§6.1.1) |
| `Storage_Pool` | Requires user-defined pools (§13.11) |
| `Tag` | Requires tagged types (§3.9) |
| `Terminated` | Requires Ada tasking (§9.9) |
| `Unchecked_Access` | Unsafe; excluded (§13.10) |
| `Update` | Deprecated; replaced by delta aggregates (§4.3.4) |
| `Version` | Requires separate body (§7.2) |
| `Write` | Requires streams (§13.13.2) |

---

## 2.6 Pragma Inventory

120. The following tables list all language-defined pragmas from 8652:2023 with their Safe status.

### 2.6.1 Retained Pragmas

121.

| Pragma | Reference | Notes |
|--------|-----------|-------|
| `Assert` | §11.4.2 | Sole assertion mechanism; always enabled |
| `Atomic` | §C.6 | Retained for hardware register modelling |
| `Atomic_Components` | §C.6 | Retained for array components |
| `Discard_Names` | §C.5 | Retained |
| `Independent` | §C.6 | Retained for memory-mapped registers |
| `Independent_Components` | §C.6 | Retained for array components |
| `Inline` | §6.3.2 | Retained |
| `No_Return` | §6.5.1 | Retained (as aspect; pragma form also retained) |
| `Optimize` | §2.8 | Retained |
| `Pack` | §13.2 | Retained |
| `Preelaborable_Initialization` | §10.2.1 | Retained |
| `Preelaborate` | §10.2.1 | Retained |
| `Priority` | §D.1 | Retained for task declarations (Section 4 syntax) |
| `Pure` | §10.2.1 | Retained |
| `Reviewable` | §H.3.1 | Retained |
| `Volatile` | §C.6 | Retained for hardware registers |
| `Volatile_Components` | §C.6 | Retained for array components |

### 2.6.2 Excluded Pragmas

122.

| Pragma | Reference | Reason for Exclusion |
|--------|-----------|---------------------|
| `All_Calls_Remote` | §E.2.3 | Requires distributed systems |
| `Assertion_Policy` | §11.4.2 | Assertions always enabled |
| `Asynchronous` | §E.4.1 | Requires distributed systems |
| `Convention` | §B.1 | Requires foreign language interface |
| `Controlled` | §13.11.3 | Requires controlled types |
| `Default_Storage_Pool` | §13.11.3 | Requires storage pools |
| `Detect_Blocking` | §H.5 | Implementation concern |
| `Elaborate` | §10.2.1 | Circular dependencies prohibited |
| `Elaborate_All` | §10.2.1 | Circular dependencies prohibited |
| `Elaborate_Body` | §10.2.1 | No separate body model |
| `Export` | §B.1 | Requires foreign language interface |
| `Import` | §B.1 | Requires foreign language interface |
| `Inspection_Point` | §H.3.2 | Implementation concern |
| `Interrupt_Handler` | §C.3.1 | Requires interrupt handling |
| `Interrupt_Priority` | §D.1 | Requires interrupt handling |
| `Linker_Options` | §B.1 | Requires foreign language interface |
| `List` | §2.8 | Compiler directive; not language semantic |
| `Locking_Policy` | §D.3 | Implementation concern |
| `Normalize_Scalars` | §H.1 | Implementation concern; may mask uninitialised reads |
| `Page` | §2.8 | Compiler directive; not language semantic |
| `Partition_Elaboration_Policy` | §D.13 | Implementation concern (informative note in §04) |
| `Profile` | §13.12.1 | Not needed; restrictions defined by this specification |
| `Queuing_Policy` | §D.4 | Requires full Ada tasking |
| `Remote_Call_Interface` | §E.2.3 | Requires distributed systems |
| `Remote_Types` | §E.2.2 | Requires distributed systems |
| `Restrictions` | §13.12 | Not needed; restrictions defined by this specification |
| `Shared_Passive` | §E.2.1 | Requires distributed systems |
| `Storage_Size` (pragma form) | §13.3 | Aspect form retained |
| `Suppress` | §11.5 | Excluded; all checks retained |
| `Task_Dispatching_Policy` | §D.2.2 | Implementation concern |
| `Unchecked_Union` | §B.3.3 | Requires unchecked features |
| `Unsuppress` | §11.5 | Excluded with Suppress |

---

## 2.7 Contract Exclusions

123. The following contract-related aspects are excluded from Safe source. Rationale: replaced by `pragma Assert` for runtime defensive checks; Bronze and Silver assurance guaranteed by D26/D27 language rules without developer-authored contracts.

| Aspect | Reference | Replacement |
|--------|-----------|-------------|
| `Pre` | §6.1.1 | `pragma Assert` |
| `Post` | §6.1.1 | `pragma Assert` |
| `Pre'Class` | §6.1.1 | Excluded (no tagged types) |
| `Post'Class` | §6.1.1 | Excluded (no tagged types) |
| `Contract_Cases` | SPARK RM §6.1.3 | `pragma Assert` |
| `Type_Invariant` | §7.3.2 | Excluded (no tagged types) |
| `Type_Invariant'Class` | §7.3.2 | Excluded (no tagged types) |
| `Dynamic_Predicate` | §3.2.4 | Excluded (see paragraph 5) |
| `Static_Predicate` | §3.2.4 | Excluded (see paragraph 5) |
| `Default_Initial_Condition` | §7.3.3 | Excluded (no tagged types) |
| `Loop_Invariant` | SPARK RM §5.5 | Excluded; proof-only aspect |
| `Loop_Variant` | SPARK RM §5.5 | Excluded; proof-only aspect |

124. A conforming implementation shall reject any Safe source bearing any aspect listed in paragraph 123.

---

## 2.8 Silver-by-Construction Rules

125. The following five legality and semantic rules are new to Safe — they have no 8652:2023 precedent. Together they guarantee that every conforming Safe program is free of runtime errors within the scope defined by Section 5, §5.3.1, paragraph 12a (D26, D27).

### 2.8.1 Rule 1: 64-Bit Integer Arithmetic

126. All integer arithmetic expressions shall be evaluated in Safe's single predefined `integer` model, which has at least signed 64-bit range. This modifies the dynamic semantics of 8652:2023 §4.5 (Operators and Expression Evaluation): every integer arithmetic result shall be statically provable to remain within the signed 64-bit range.

127. Range checks shall be performed only at the following **narrowing points**:

   (a) Assigned to an object.

   (b) Passed as a parameter.

   (c) Returned from a function.

   (d) Used as the operand of a type conversion whose target type or subtype has a more restrictive range than the operand's type.

   (e) Used as the expression of a type annotation `(Expr as T)` (see §2.4.2).

128. If the static range of any declared integer type in the program exceeds the 64-bit signed range (-(2^63) .. (2^63 - 1)), the program is nonconforming and a conforming implementation shall reject it.

129. **Intermediate overflow legality rule.** If a conforming implementation cannot establish, by sound static range analysis, that every intermediate subexpression of an integer arithmetic expression stays within the 64-bit signed range, the expression shall be rejected with a diagnostic.

130. Narrowing checks at all five categories of narrowing point — assignment, parameter passing, return, type conversion, and type annotation — shall be discharged via sound static range analysis on the computed integer result. Interval analysis is one permitted technique; no specific analysis algorithm is mandated.

**Example (conforming):**

```safe
public subtype reading is integer (0 to 4095)

public function average (a, b : reading) returns reading
    return (a + b) / 2  -- max (4095+4095)/2 = 4095
                         -- range check at return: provably in 0..4095
                         -- D27 proof: reading.first <= result <= reading.last
```

### 2.8.2 Rule 2: Provable Index Safety

131. The index expression in an indexed_component (8652:2023 §4.1.1) shall be provably within the array object's index bounds at compile time. A conforming implementation shall accept an indexed_component if any of the following conditions holds:

   (a) **Type containment:** The index expression's type or subtype range is statically contained within the array object's index constraint. For an array whose index constraint spans the full range of its index type (e.g., `array (Channel_Id) of T` where `Channel_Id` covers all values), this reduces to checking that the index expression's type is the same as, or a subtype of, the array's index type.

   (b) **Static range analysis:** The implementation can establish, by sound static range analysis at the program point of the indexed_component, that the index expression's value is within the array object's bounds. This includes cases where a preceding conditional narrows the index range (e.g., `if I in A.First .. A.Last then A(I)`) or where the index is derived from the array's own bounds attributes.

132. If neither condition holds, the program is nonconforming and the implementation shall reject it with a diagnostic identifying the indexed_component and the unresolvable bound relationship.

132a. **Rationale.** Type containment alone (condition a) is sufficient when the array object's bounds span the full range of its index type — the common case for arrays indexed by a dedicated type. When the array object has a narrower constraint than the full index type (e.g., `array (Channel_Id range 0 .. 3) of T`) or when the array has unconstrained bounds (e.g., an unconstrained array parameter), the index expression's type range may exceed the array's actual bounds. Condition (b) extends the guarantee to these cases using the same static range analysis machinery required for Rule 1's narrowing checks and Rule 3's division checks.

**Example 1 (conforming — full-range array, type containment):**

```ada
public type Channel_Id is range 0 .. 7;
Table : array (Channel_Id) of Integer;

public function Lookup (Ch : Channel_Id) return Integer is
begin
    return Table(Ch);  -- legal via condition (a): Channel_Id 0..7
                       -- matches array bounds 0..7
end Lookup;
```

**Example 2 (conforming — narrower array, tighter subtype):**

```ada
subtype Low_Channel is Channel_Id range 0 .. 3;
Partial : array (Low_Channel) of Integer;

public function Lookup_Low (Ch : Low_Channel) return Integer is
begin
    return Partial(Ch);  -- legal via condition (a): Low_Channel 0..3
                         -- contained in array bounds 0..3
end Lookup_Low;
```

**Example 3 (conforming — unconstrained parameter, bounds-derived index):**

```ada
public type Buffer is array (Positive range <>) of Character;

public function First_Char (B : Buffer) return Character is
begin
    return B(B.First);  -- legal via condition (b): B.First is provably
                        -- within B.First .. B.Last
end First_Char;
```

**Example 4 (conforming — unconstrained parameter, guarded index):**

```ada
public function Char_At (B : Buffer; I : Positive) return Character is
begin
    if I in B.First .. B.Last then
        return B(I);  -- legal via condition (b): range of I narrowed
                      -- to B.First .. B.Last by enclosing condition
    else
        return ' ';
    end if;
end Char_At;
```

**Nonconforming Example — index type wider than array bounds:**

```ada
-- NONCONFORMING: Integer range (Integer.First .. Integer.Last) not
-- contained in Channel_Id (0..7)
public function Bad_Lookup (N : Integer) return Integer is
begin
    return Table(N);  -- rejected: neither condition (a) nor (b) holds
end Bad_Lookup;
```

**Nonconforming Example — full type used on narrower array:**

```ada
-- NONCONFORMING: Channel_Id (0..7) exceeds Partial bounds (0..3)
public function Bad_Partial (Ch : Channel_Id) return Integer is
begin
    return Partial(Ch);  -- rejected: Channel_Id range 0..7 not contained
                         -- in array bounds 0..3
end Bad_Partial;
```

**Nonconforming Example — unconstrained array, unguarded index:**

```ada
-- NONCONFORMING: I (type Positive) not provably within B's bounds
public function Bad_Char (B : Buffer; I : Positive) return Character is
begin
    return B(I);  -- rejected: B has dynamic bounds; Positive range
                  -- not provably contained in B.First .. B.Last
end Bad_Char;
```

### 2.8.3 Rule 3: Division by Provably Nonzero Divisor

133. The right operand of the operators `/`, `mod`, and `rem` (8652:2023 §4.5.5) shall be provably nonzero at compile time. A conforming implementation shall accept a divisor expression as provably nonzero if any of the following conditions holds:

   (a) The divisor expression has a type or subtype whose range excludes zero.

   (b) The divisor expression is a static expression (8652:2023 §4.9) whose value is nonzero.

   (c) The divisor expression is an explicit conversion to a nonzero subtype where the conversion is provably valid at that program point.

134. If none of the conditions in paragraph 133 holds, the program is nonconforming and a conforming implementation shall reject the expression with a diagnostic.

135. The language provides standard subtypes that exclude zero:

```ada
subtype Positive is Integer range 1 .. Integer.Last;
subtype Negative is Integer range Integer.First .. -1;
```

**Example (conforming — condition a, nonzero type):**

```ada
public type Seconds is range 1 .. 3600;

public function Rate (Distance : Meters; Time : Seconds) return Integer is
begin
    return Distance / Time;  -- legal: Seconds excludes zero
                              -- D27 proof: Time >= 1
end Rate;
```

**Example (conforming — condition b, static nonzero literal):**

```ada
public function Average (A, B : Reading) return Reading is
begin
    return (A + B) / 2;  -- legal: 2 is a static nonzero expression
                          -- D27 proof: divisor is the static literal 2 (2 != 0)
end Average;
```

**Nonconforming Example — Rule 3 violation at division:**

```ada
-- NONCONFORMING: divisor type includes zero
public function Bad_Divide (A, B : Integer) return Integer is
begin
    return A / B;  -- rejected: Integer range includes zero
end Bad_Divide;
```

### 2.8.4 Rule 4: Not-Null Dereference

136. Dereference of an access value — whether explicit (`.all`) or implicit (selected component through an access value) — shall require the access subtype to be `not null` (8652:2023 §3.10). A conforming implementation shall reject any dereference where the access subtype at the point of dereference does not exclude null.

137. Every access type declaration produces two usable forms: a nullable one for storage and a non-null one for dereference:

```ada
public type Node;
public type Node_Ptr is access Node;            -- nullable, for storage
public subtype Node_Ref is not null Node_Ptr;   -- non-null, for dereference
```

138. Null comparison (`== null`, `!= null`) is always legal on any access type; only dereference requires the not-null guarantee.

**Example (conforming):**

```ada
public function Value_Of (N : Node_Ref) return Integer
is (N.Value);  -- legal: Node_Ref excludes null
               -- D27 proof: N != null by subtype
```

**Nonconforming Example — Rule 4 violation at dereference:**

```ada
-- NONCONFORMING: dereference of nullable access type
public function Bad_Value (N : Node_Ptr) return Integer
is (N.Value);  -- rejected: Node_Ptr includes null
```

### 2.8.5 Rule 5: Floating-Point Non-Trapping Semantics and Range Safety

139. **IEEE 754 non-trapping requirement.** A conforming implementation shall ensure that all predefined floating-point types have `Machine_Overflows` equal to `False` (8652:2023 §A.5.3(12)). This requires the implementation to use IEEE 754 default non-trapping arithmetic: floating-point overflow produces ±infinity, floating-point division by zero produces ±infinity, and invalid operations (such as `0.0 / 0.0` or `sqrt(-1.0)`) produce NaN (Not a Number). These are defined values in the IEEE 754 model, not runtime errors.

139a. **Rationale.** In Ada 2022, `Machine_Overflows` is implementation-defined. If `True`, float overflow and division by zero raise `Constraint_Error` — a runtime error that the Silver guarantee must prevent. By requiring `Machine_Overflows = False`, Safe eliminates these exception sources entirely. IEEE 754 non-trapping semantics are the default on virtually all modern hardware (ARM, x86, RISC-V, POWER); this requirement excludes only legacy or unusual targets where trapping floats are the sole option.

139b. **Floating-point range checks at narrowing points.** Range checks at the five categories of narrowing point (assignment, parameter passing, return, type conversion, type annotation) apply to floating-point types as well as integer types. At each narrowing point, the implementation shall verify that the floating-point value is within the target type's range. Since IEEE 754 arithmetic can produce ±infinity or NaN as intermediate results, the implementation shall apply sound static range analysis to establish that the value at the narrowing point is a finite number within the target type's model range.

139c. If a conforming implementation cannot establish, by sound static range analysis, that a floating-point narrowing point is safe (i.e., that the value is a finite number within the target type's range), the program is nonconforming and shall be rejected with a diagnostic.

139d. **NaN and infinity as intermediate values.** NaN and ±infinity are permitted as intermediate values in floating-point computations — they are defined values under IEEE 754, not runtime errors. However, they shall not survive narrowing: no conforming program can assign NaN or ±infinity to a typed floating-point variable, pass it as a parameter, return it from a function, convert it to a more restrictive type, or annotate it with a type annotation, because these values are outside every finite floating-point type's range. The implementation rejects any program where NaN or infinity could reach a narrowing point.

139e. **How this discharges floating-point checks.** Since `Machine_Overflows = False`, no floating-point operation raises `Constraint_Error` for overflow or division by zero — these produce infinity or NaN instead. Infinity and NaN are caught at narrowing points by the same static range analysis used for integer narrowing (Rule 1). The result is a uniform model: floating-point exceptions are eliminated at the source (non-trapping arithmetic), and out-of-range values are caught at narrowing points (static analysis or rejection).

**Example (conforming):**

```ada
public type Measurement is digits 6 range -1.0E6 .. 1.0E6;

public function Scale (M : Measurement; Factor : Measurement) return Measurement is
begin
    return M * Factor;
    -- Rule 5: Machine_Overflows = False; M * Factor cannot raise
    -- Constraint_Error. Range check at return: implementation verifies
    -- M * Factor is within -1.0E6 .. 1.0E6. Max |M * Factor| =
    -- 1.0E6 * 1.0E6 = 1.0E12, which exceeds the range — rejected
    -- unless the implementation can narrow the range further.
end Scale;
```

**Nonconforming Example — unresolvable float range:**

```ada
-- NONCONFORMING: float product can exceed target range
public type Probability is digits 6 range 0.0 .. 1.0;

public function Unsafe_Scale (P : Probability; X : Float) return Float is
begin
    return Float(P * X);
    -- Rule 5: P * X could be any float value (X is unconstrained);
    -- result could be infinity if X is very large.
    -- Range check at return: Float range may not contain result.
    -- REJECTED if implementation cannot prove result in Float'Range.
end Unsafe_Scale;
```

### 2.8.6 Combined Effect

139f. These five rules ensure that all categories of runtime check are dischargeable from static type and range information derivable from the program text:

| Check | How Discharged |
|-------|---------------|
| Integer overflow | Rejected unless every integer arithmetic result is provably within signed 64-bit range (Rule 1) |
| Range on assignment/return/parameter/conversion/annotation (integer) | Sound static range analysis on integer results at all narrowing points (Rule 1) |
| Range on assignment/return/parameter/conversion/annotation (float) | Sound static range analysis; non-trapping arithmetic eliminates exception sources; NaN/infinity caught at narrowing points (Rule 5) |
| Floating-point overflow | Non-exceptional — produces ±infinity under IEEE 754 non-trapping mode (Rule 5); caught at narrowing points |
| Floating-point division by zero | Non-exceptional — produces ±infinity under IEEE 754 non-trapping mode (Rule 5); caught at narrowing points |
| Floating-point invalid operation (NaN) | Non-exceptional — produces NaN under IEEE 754 non-trapping mode (Rule 5); caught at narrowing points |
| Array index out of bounds | Index provably within array object's bounds — by type containment or static range analysis (Rule 2) |
| Division by zero (integer) | Divisor is provably nonzero (Rule 3) |
| Null dereference | Access subtype is `not null` at every dereference (Rule 4) |
| Discriminant | Discriminant type is discrete and static; variant access requires matching discriminant value |

---

## 2.9 Interleaved Declarations

140. Inside subprogram bodies, declarations and statements may interleave freely after `begin` (D11). A declaration is visible from its point of declaration to the end of the enclosing scope. The pre-`begin` declarative part is still permitted but not required. This modifies 8652:2023 §3.11, which requires all declarations before `begin`.

---

## 2.10 No Overloading

141. Subprogram name overloading is excluded (D12). Each subprogram identifier shall denote exactly one subprogram within a given declarative region. A conforming implementation shall reject any declarative region containing two subprogram declarations with the same identifier.

142. **Predefined operators** for numeric types, Boolean, and other language-defined types are retained. These are intrinsic to the type and do not participate in overload resolution.

143. **Cross-package names.** The same subprogram name may appear in different packages (qualified by the package name: `Sensors.Initialize` vs. `Motors.Initialize`). This is not overloading; it is distinct declarations in distinct namespaces.

---

## 2.11 No General Use Clauses

144. General `use` clauses (8652:2023 §8.4 first form) are excluded (D13). `use type` clauses (§8.4 second form) are retained.

---

## 2.12 Recoverable Error Convention

145. Safe's error model distinguishes two categories of failure:

   (a) **Fatal failures** invoke the runtime abort handler. These include assertion failure (paragraph 68) and allocation failure (paragraph 103a). In the current model, a fatal failure terminates the program. A future version of Safe may introduce task-level fault containment for assertion failures (see paragraph 151a), in which case an assertion failure would terminate only the failing task rather than the entire program — but the failing task's execution is never resumed from the point of failure. A supervisor may restart the task from its initial entry point (paragraph 151d), which is distinct from resumption. Allocation failure would remain a program abort unless per-task allocation budgets are introduced (paragraph 151b).

   (b) **Recoverable failures** represent conditions that a caller can meaningfully respond to: parse failures, lookup misses, invalid inputs, protocol errors, resource unavailability, and similar domain-level conditions. Since exceptions are excluded (paragraph 67), recoverable failures shall be communicated through explicit program-visible values — discriminated result records (paragraph 146), status parameters (paragraph 149(b)), or channel messages (paragraph 149(c)) — and shall not rely on exceptions or hidden control flow.

146. **Discriminated result convention.** The canonical Safe pattern for representing a recoverable failure is a discriminated record with a Boolean discriminant that selects between a success variant and an error variant:

```ada
type Result (OK : Boolean = False) is record
   case OK is
      when True  then Value : Success_Type;
      when False then Error : Error_Type;
   end case;
end record;
```

The default discriminant shall be `False` so that a default-initialised result represents failure.

147. **Naming convention.** A conforming program that uses the discriminated result pattern should use the following names:

   (a) The discriminant shall be named `OK` (type `Boolean`, default `False`).

   (b) The success variant field shall be named `Value`.

   (c) The error variant field shall be named `Error`.

   (d) The type name should end with `_Result` or be named `Result` when unambiguous within the enclosing package.

These conventions are recommended, not required. A conforming implementation shall not reject a program solely because a discriminated result type uses different field names.

148. **Discriminant-check safety.** Accessing a variant field requires that the discriminant value matches the corresponding variant (8652:2023 §4.1.3(13)). In Safe, this check is discharged statically: a conforming implementation shall reject any program where it cannot prove that the discriminant matches the selected variant at every variant field access. This is consistent with the Silver-by-construction guarantee (§2.8.6, paragraph 139f, "Discriminant" row).

In practice, a conditional guard establishes the discriminant value:

```ada
R : Parse_Result = Parse (Input);
if R.OK then
   Process (R.Value);   -- legal: R.OK = True is established
else
   Log_Error (R.Error);  -- legal: R.OK = False is established
end if;
```

A conforming implementation shall treat a conditional branch on the discriminant as sufficient to establish the discriminant value within that branch for the purpose of variant field access, **until the discriminated object is potentially modified**. The established discriminant fact is invalidated by any of:

   (a) Assignment to the discriminated object (e.g., `R = other_result;`).

   (b) Passing the discriminated object as an `out` or `in out` parameter.

After invalidation, the discriminant must be re-established by a new conditional guard before any variant field access.

**Nonconforming example — access after mutation within guarded branch:**

```ada
R : Parse_Result = Parse (Input);
if R.OK then
   R = Parse (Other_Input);  -- R.OK is now unknown (invalidated)
   Process (R.Value);         -- REJECTED: R.OK = True no longer established
end if;
```

149. **Coexistence with status-code parameters.** Safe's nonblocking channel operations (`send`, `try_receive`) use Boolean out-parameters to report success or failure (Section 4, §4.3). This form is appropriate for statement-level primitives where the operation has side effects and the result is not a computed value.

The discriminated result convention, the status-code convention, and result-typed channels serve different contexts:

   (a) **Functions that compute a fallible value** should return a discriminated result record.

   (b) **Statements or procedures with side effects** that may fail non-fatally may use a Boolean out-parameter to report success.

   (c) **Concurrent error reporting** should use channels whose element type is a discriminated result record. This unifies the sequential and concurrent error models: the same `Result` layout represents failure in both contexts, delivered via function return in sequential code and via `send`/`receive` in concurrent code.

A conforming implementation shall accept all three forms.

150. **Guidance on fatal failure vs. result.** The following conditions warrant a fatal failure (runtime abort handler) rather than a result return:

   (a) Assertion violations (`pragma Assert`).

   (b) Allocation failure.

   (c) Any condition where the program's invariants are broken and continued execution would violate the Silver guarantee.

All other domain-level failures — including but not limited to invalid input, missing data, communication timeouts, and format errors — should use the discriminated result convention.

151. **Future evolution: parametric result type.** The current convention still commonly uses per-API result records even after Safe-native generics, because a standard `result (T, E)` abstraction and error-propagation surface are not yet shipped. A future version of Safe may introduce a built-in parametric type constructor (e.g., `Result[T, E]`) and an error-propagation operator to reduce boilerplate. Such features would be additive — programs written using the per-type discriminated result convention defined in this section would remain conforming.

151a. **Future evolution: task-level fault containment.** Safe's ownership model guarantees that a task's mutable state is unreachable from other tasks (Section 4, §4.2). This isolation property means that a fatal failure in one task cannot corrupt another task's state. A future version of Safe may exploit this property to contain certain fatal failures to the failing task rather than aborting the entire program. The following subsections sketch the design constraints such a feature would need to satisfy.

151b. **Containable vs. catastrophic failures.** Not all fatal failures are equally containable:

   (a) **Assertion failure** (`pragma Assert`) is task-local: the failing task violated an invariant in its own code. Assertion failures are strong candidates for task-level containment because the failing task's state is provably isolated from other tasks.

   (b) **Allocation failure** is a shared environmental resource problem: heap exhaustion affects all tasks, not just the one whose allocation failed. Allocation failure should remain catastrophic (program abort) unless a future version introduces per-task allocation budgets or arenas that make exhaustion genuinely task-local. Without such budgets, "containing" an allocation failure risks masking a system-wide resource problem behind repeated task restarts.

   (c) **Hardware faults, stack overflow, and similar unrecoverable conditions** remain catastrophic and always abort the program.

151c. **Notification mechanism.** A supervisor task must learn that a peer task has failed. The minimal surface syntax would be an optional aspect on the task declaration designating a typed fault channel:

```ada
channel Worker_Faults : Fault_Event capacity 4;

task Worker with Priority = 5, Fault_Channel = Worker_Faults is
   ...
end Worker;
```

When the runtime detects a containable failure in `Worker`, it posts a fault event (identifying the failed task, the fault kind, and the source location) to the designated channel. The supervisor receives fault events through ordinary `receive` or `select` operations — no new control-flow mechanism is needed.

151d. **Restart and the non-termination rule.** Tasks are syntactically required to be non-terminating (Section 4, §4.6, paragraph 53). A task-level "restart" does not violate this rule: the programmer-visible task body remains an unconditional loop with no `return` or outer `exit`. The runtime may end a failing execution instance and re-enter the task body at its initial entry point, but this is a runtime recovery mechanism, not a language-level termination. The task is never observed to have "completed" in the Ada sense.

On restart, all task-local state is reset: local declarations within the task body are re-elaborated with their initial values, and package-level variables owned by the task are re-initialised to their declaration values. This ensures the task starts from a known-good state — the assertion failure may have been caused by corrupted local state, and preserving that state across a restart would defeat the purpose of recovery. If a task needs to persist state across restarts, the supervisor should hold it and send it to the restarted task via a channel.

151e. **Channel state on task failure.** The existing channel and ownership semantics constrain the options:

   (a) **No blocked sends.** `send` is nonblocking in admitted Safe source. If a channel is full, the operation simply reports `success = false` and leaves channel state unchanged. There is therefore no runtime notion of a task terminated while blocked in send.

   (b) **Completed receives.** A message removed from a channel by `receive` is not re-delivered if the receiver then crashes. Any task-local owned objects in the crashed task's scope are reclaimed by automatic deallocation (paragraph 104–105), preserving memory safety.

   (c) **Blocked receives.** A task blocked in `receive` that is terminated by a supervisor (or by restart) simply stops waiting. No message is consumed. Other tasks may subsequently receive from the same channel.

151f. **Restart intensity and escalation.** Unrestricted restarts under persistent failures produce infinite crash loops, wasting resources and masking bugs. A future fault containment feature shall include:

   (a) A **restart intensity limit**: a maximum number of restarts within a defined time period. If the limit is exceeded, the supervisor escalates rather than restarting again.

   (b) An **escalation policy**: when restart intensity is exceeded, the supervisor may abort the program, shut down a subsystem, or take other corrective action defined by the program.

   These mechanisms draw from Erlang/OTP's supervisor restart intensity model, adapted to Safe's static task structure.

151g. **Three-tier failure model.** With fault containment, Safe's error model would have three tiers:

   (a) **Recoverable failures** — domain-level conditions handled via discriminated result records in sequential code (paragraphs 146–148) and via result-typed channel messages in concurrent code. The caller or receiver inspects the result and responds.

   (b) **Contained failures** — assertion failures (and, with per-task budgets, allocation failures) that terminate the failing task. A supervisor task is notified and may restart the failed task, subject to restart intensity limits. No other task's state is affected.

   (c) **Catastrophic failures** — allocation exhaustion without per-task budgets, stack overflow, hardware faults, and restart-intensity-exceeded escalation. These abort the program via the runtime abort handler.

This feature is under consideration and does not affect the normative status of the conventions defined in paragraphs 146–150.
