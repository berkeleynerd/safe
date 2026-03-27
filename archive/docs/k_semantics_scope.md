# K-Framework Formal Semantics Scope for Safe

**Status:** DRAFT
**Frozen commit:** `468cf72332724b04b7c193b4d2a3b02f1584125d`
**Date:** 2026-03-02
**Author:** Runtime Designer

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Safe Subset for K Semantics](#2-safe-subset-for-k-semantics)
3. [K Configuration](#3-k-configuration)
4. [Key Semantic Rules](#4-key-semantic-rules)
5. [kprove Properties](#5-kprove-properties)
6. [Relationship to D27 Rules](#6-relationship-to-d27-rules)
7. [K Skeleton Structure](#7-k-skeleton-structure)
8. [Effort Estimate and Roadmap](#8-effort-estimate-and-roadmap)
9. [Comparison with SPARK Approach](#9-comparison-with-spark-approach)
10. [Assumption Linkage](#10-assumption-linkage)
11. [References](#11-references)

---

## 1. Introduction

### 1.1 What is the K Framework

The K framework (https://kframework.org) is a rewrite-based executable semantics framework. Given a language's syntax and semantic rules expressed in K, the framework automatically derives:

- An **executable reference interpreter** from the formal semantics, providing a canonical execution model against which implementations can be tested.
- **Symbolic execution** via `kprove`, enabling formal property verification by exploring all reachable states symbolically.
- **Test-case generation** from semantic rules, producing positive and negative test programs that exercise specific semantic transitions.
- A **formal specification** that is simultaneously human-readable mathematical notation and machine-executable code, eliminating the gap between specification and implementation.

A K definition consists of three components: a syntax definition (productions in BNF-like notation), a configuration (a nested cell structure representing program state), and semantic rules (rewrite rules that transform configurations). Rules have the form `LHS => RHS` with optional side conditions, and the K rewriting engine applies them to transform program states.

### 1.2 Why K is Suitable for Safe

Safe is a restricted subset of Ada 2022 designed for formal verification. Several properties of Safe make it an especially good candidate for K-framework formalization:

1. **No overloading (D12).** Every identifier resolves to exactly one entity. This eliminates the need for overload resolution in the semantics, which in full Ada requires complex type inference. The K semantics can use simple environment lookup.

2. **No exceptions (D14).** Control flow is entirely structural. There are no hidden control-flow edges from exception handlers. K's rewriting model represents all control flow explicitly.

3. **No generics (D16).** No template instantiation or monomorphization is needed. Every construct in a Safe program is concrete.

4. **No tagged types (D18).** No dispatching, no class-wide types, no dynamic binding. Every call in Safe is statically resolved, making the K call semantics straightforward.

5. **Finite concurrency model.** Tasks are statically declared at package level; there is no dynamic task creation. Channels have statically-known bounded capacity. K's native support for concurrent rewriting (via the `<thread multiplicity="*">` cell) maps directly to Safe's static task model.

6. **Ownership state machine.** Safe's ownership model (Null_State, Owned, Moved, Borrowed, Observed) is a finite-state machine with well-defined transitions. K excels at modeling state machines through rewrite rules.

7. **Deterministic select.** Safe's `select` statement evaluates arms in declaration order and chooses the first ready arm. This deterministic semantics is directly expressible as ordered rewrite rules.

### 1.3 Benefits of a K Semantics for Safe

| Benefit | Description |
|---|---|
| Executable reference interpreter | Run Safe programs directly from the formal semantics to validate compiler output. |
| Symbolic verification via kprove | Prove safety properties (type safety, memory safety, channel safety) by symbolic execution over all possible inputs. |
| Test generation | Derive test programs that exercise specific narrowing points, ownership transitions, and channel states. |
| Formal bridge to implementation | The K definition serves as an unambiguous reference that the compiler can be tested against, complementing the SPARK companion's deductive approach. |
| Concurrency reasoning | K's native rewriting semantics can explore all task interleavings, verifying determinism and race-freedom properties that are difficult to test empirically. |

### 1.4 Relationship to the SPARK Companion

The SPARK companion (`companion/spark/safe_po.ads`, `companion/spark/safe_model.ads`) provides deductive verification using GNATprove. It expresses proof obligations as SPARK preconditions and ghost models. The K semantics provides a complementary verification approach:

- **SPARK companion:** Deductive (verification conditions + SMT solvers). Proves that specific contracts hold for all inputs. Mature Ada/SPARK ecosystem. Cannot directly execute or explore interleavings.
- **K semantics:** Rewrite-based (symbolic execution). Provides executable semantics, explores all reachable states including concurrent interleavings. Research-stage for Ada.

Together, they provide defense in depth: the SPARK companion verifies that the emitted Ada/SPARK code satisfies its contracts, while the K semantics verifies that the Safe language semantics themselves are sound and that the D27 rules achieve their intended guarantees.

---

## 2. Safe Subset for K Semantics

The full Safe grammar comprises approximately 148 BNF productions (spec/08-syntax-summary.md) with 90+ distinct AST node types (compiler/ast_schema.json). The K formalization proceeds in three phases, each adding a coherent subset of the language.

### 2.1 Phase 1: Core Expressions, Statements, and Subprograms

Phase 1 formalizes the sequential, single-task subset of Safe sufficient to express and verify the D27 arithmetic safety rules.

**Types formalized:**

| Category | Constructs | AST Nodes | BNF Productions |
|---|---|---|---|
| Scalar types | `SignedIntegerTypeDefinition`, `ModularTypeDefinition`, `EnumerationTypeDefinition`, `FloatingPointDefinition` | `SignedIntegerTypeDefinition`, `ModularTypeDefinition`, `EnumerationTypeDefinition`, `FloatingPointDefinition` | 8.4 |
| Subtype declarations | `SubtypeDeclaration` with `RangeConstraint` | `SubtypeDeclaration`, `SubtypeIndication`, `RangeConstraint`, `Range` | 8.3, 8.5 |
| Object declarations | Variable and constant declarations with initializers | `ObjectDeclaration`, `NumberDeclaration` | 8.3 |

**Expressions formalized:**

| Category | Constructs | AST Nodes |
|---|---|---|
| Arithmetic | `+`, `-`, `*`, `/`, `mod`, `rem`, `**`, `abs`, unary `+`/`-` | `Expression`, `Relation`, `SimpleExpression`, `Term`, `Factor`, `Primary` |
| Relational | `=`, `/=`, `<`, `<=`, `>`, `>=`, `in`, `not in` | `Relation`, `MembershipTest` |
| Logical | `and`, `and then`, `or`, `or else`, `xor`, `not` | `Expression` (with `LogicalOperator`) |
| Literals | Numeric literals, character literals, string literals, `null` | `NumericLiteral`, `CharacterLiteral`, `StringLiteral` |
| Names | Direct names, selected components (field access, package member), indexed components | `DirectName`, `SelectedComponent`, `IndexedComponent` |
| Type conversion | Explicit type conversions | `TypeConversion` |
| Type annotation | `(Expr as T)` syntax | `AnnotatedExpression` |
| Conditional | `if` expressions, `case` expressions | `IfExpression`, `CaseExpression` |
| Aggregates | Record aggregates, positional array aggregates, named array aggregates, delta aggregates | `RecordAggregate`, `PositionalArrayAggregate`, `NamedArrayAggregate`, `DeltaAggregate` |

**Statements formalized:**

| Category | Constructs | AST Nodes |
|---|---|---|
| Assignment | `X = Expr;` with narrowing-point check | `AssignmentStatement` |
| Procedure call | `P(Args);` with parameter narrowing | `ProcedureCallStatement` |
| Return | `return Expr;` with return narrowing | `SimpleReturnStatement`, `ExtendedReturnStatement` |
| Control flow | `if`/`else if`/`else`, `case`, `loop` (while, for-in, for-of, unconditional), `exit`, `return`, `delay`, `select` | `IfStatement`, `CaseStatement`, `LoopStatement`, `ExitStatement`, `SimpleReturnStatement`, `ExtendedReturnStatement`, `DelayStatement`, `SelectStatement` |
| Assertion | `pragma Assert(Cond);` | `Pragma` |
| Delay | `delay Expr;` | `DelayStatement` |

**Subprograms formalized:**

| Category | Constructs | AST Nodes |
|---|---|---|
| Procedure/function bodies | With declarative parts and parameter modes (`in`, `in out`, `out`) | `SubprogramBody`, `ProcedureSpecification`, `FunctionSpecification`, `FormalPart`, `ParameterSpecification` |
| Expression functions | `function F ... is (Expr);` | `ExpressionFunctionDeclaration` |
| Interleaved declarations | Declarations after `begin` | `InterleavedItem`, `SequenceOfStatements` |

**Wide arithmetic model:** All integer subexpressions are evaluated in `Long_Long_Integer` (64-bit signed). This is the defining semantic characteristic of Phase 1. The five narrowing-point categories from spec/02-restrictions.md section 2.8.1 paragraph 127 are formalized as K rules that check the 64-bit intermediate against the target type's range.

### 2.2 Phase 2: Ownership, Pointers, and Arrays

Phase 2 adds the memory model: heap-allocated objects, ownership state tracking, pointer operations, and array bounds enforcement.

**Ownership operations formalized:**

| Operation | Ownership Transition | Source State After | Spec Reference |
|---|---|---|---|
| Allocator (`new`) | Null_State -> Owned | (new variable) | 2.3.5, p103 |
| Move (`Y = X;` for access types) | source: Owned -> Moved; target: * -> Owned | source = null | 2.3.2, p96 |
| Borrow (`Y : access T = X;`) | source: Owned -> Borrowed | source frozen | 2.3.3, p98 |
| Observe (`Y : access constant T = X.Access;`) | source: Owned -> Observed (or Observed -> Observed) | source frozen (reads permitted) | 2.3.4, p101 |
| Borrow end (scope exit) | source: Borrowed -> Owned | source unfrozen | 2.3.3, p99(d) |
| Observe end (scope exit) | source: Observed -> Owned | source unfrozen | 2.3.4, p102(d) |
| Scope-exit deallocation | Owned -> Null_State | variable deallocated | 2.3.5, p104 |
| Explicit null assignment | Owned -> Null_State | variable = null | 2.3.2, p96(a) |

**Pointer operations formalized:**

| Operation | K Rule | D27 Rule |
|---|---|---|
| Dereference (`.all`, implicit) | Requires `not null` subtype | Rule 4 (p136) |
| Null comparison (`= null`, `/= null`) | Always legal | -- |
| `.Access` on heap object | Creates observer/borrower | 2.3.8, p110 |
| `.Access` on local object | Accessibility check (compile-time) | 2.3.8, p111 |

**Array operations formalized:**

| Operation | K Rule | D27 Rule |
|---|---|---|
| Indexed component `A(I)` | Index provably within `A'First .. A'Last` | Rule 2 (p131) |
| Slice `A(L..H)` | Bounds provably within array bounds | Rule 2 (extension) |
| Array aggregate | Component types match element type | -- |
| `for E of A loop` | Iterator variable typed to element type | -- |

**Record operations formalized:**

| Operation | K Rule |
|---|---|
| Field access `R.F` | Field exists in record type |
| Record aggregate `(F1 => V1, ...)` | All fields covered, types match |
| Discriminant-dependent access | Discriminant value matches variant |

**Automatic deallocation:** At every scope exit point (normal end, `return`, `exit`), all pool-specific access variables in scope with non-null values are deallocated in reverse declaration order (spec/02-restrictions.md section 2.3.5, paragraphs 104-105). The K rules model this as a cleanup sequence triggered by the scope-exit transition.

### 2.3 Phase 3: Concurrency -- Tasks, Channels, Select

Phase 3 adds Safe's concurrency model: static tasks, typed bounded channels, and the deterministic `select` statement.

**Task constructs formalized:**

| Construct | K Configuration Element | Spec Reference |
|---|---|---|
| `task T ... end T;` | New `<thread>` cell with unique `<task-id>` | 4.1, p2-3 |
| Task priority | `<priority>` field in `<thread>` cell | 4.1, p5 |
| Non-termination rule | Outermost statement is unconditional `loop` | 4.6, p53 |
| Task startup sequencing | All elaboration completes before any task runs | 4.7, p56 |
| Task-variable ownership | Each package-level variable accessed by at most one task | 4.5, p45 |

**Channel constructs formalized:**

| Construct | K Configuration Element | Spec Reference |
|---|---|---|
| `channel C : T capacity N;` | New `<channel>` cell with `<chan-id>`, `<buffer>`, `<capacity>` | 4.2, p12-15 |
| `send C, Expr;` | Append to buffer; block if full | 4.3, p27 |
| `receive C, Var;` | Remove from head; block if empty | 4.3, p28 |
| `try_send C, Expr, Ok;` | Non-blocking append; set Ok | 4.3, p29 |
| `try_receive C, Var, Ok;` | Non-blocking remove; set Ok | 4.3, p30 |
| Copy-only channel payloads | Access-bearing channel elements are excluded; channel payloads never transfer ownership | 4.2, p14; 4.3, p27a-31a |

**Select statement formalized:**

| Aspect | K Rule | Spec Reference |
|---|---|---|
| Arm evaluation order | Arms tested top-to-bottom in declaration order | 4.4, p39 |
| First-ready selection | First arm whose channel has data is chosen | 4.4, p41 |
| Delay arm | If no channel arm ready before timeout, delay arm fires | 4.4, p40 |
| No delay arm | Block indefinitely until a channel arm fires | 4.4, p42 |
| Variable scoping | `defining_identifier` in channel arm scoped to arm body | 4.4, p37 |
| Determinism | Given identical channel states, same arm is always chosen | 4.4, p41 |

---

## 3. K Configuration

The K configuration defines the mutable state of a Safe program during execution. It is a nested structure of named cells. The configuration below covers all three phases.

```k
configuration
  <safe>
    <threads>
      <thread multiplicity="*" type="Set">
        <k> $PGM:Pgm </k>
        <env> .Map </env>
        <store> .Map </store>
        <ownership> .Map </ownership>
        <call-stack> .List </call-stack>
        <task-id> 0 </task-id>
        <priority> 0 </priority>
        <blocked> false </blocked>
        <block-reason> .K </block-reason>
      </thread>
    </threads>

    <channels>
      <channel multiplicity="*" type="Set">
        <chan-id> 0 </chan-id>
        <chan-name> "" </chan-name>
        <element-type> .K </element-type>
        <buffer> .List </buffer>
        <capacity> 0 </capacity>
      </channel>
    </channels>

    <types>
      <type-env> .Map </type-env>
    </types>

    <globals>
      <global-env> .Map </global-env>
      <global-store> .Map </global-store>
      <global-ownership> .Map </global-ownership>
      <task-var-map> .Map </task-var-map>
    </globals>

    <next-loc> 0 </next-loc>
    <next-chan> 0 </next-chan>
    <next-task> 1 </next-task>

    <elaboration-complete> false </elaboration-complete>
  </safe>
```

### 3.1 Cell Descriptions

| Cell | Type | Purpose |
|---|---|---|
| `<k>` | Computation | Current continuation (code being executed) |
| `<env>` | Map (Identifier -> Location) | Local variable bindings (name to store location) |
| `<store>` | Map (Location -> Value) | Local mutable store (location to value) |
| `<ownership>` | Map (Location -> OwnershipState) | Ownership state per allocated location |
| `<call-stack>` | List (Frame) | Stack of saved (env, continuation) pairs for subprogram calls |
| `<task-id>` | Int | Unique identifier for this thread (0 = main/elaboration thread) |
| `<priority>` | Int | Task priority for scheduling |
| `<blocked>` | Bool | Whether this thread is blocked on a channel operation |
| `<block-reason>` | K item | Channel ID and operation type causing the block |
| `<chan-id>` | Int | Unique channel identifier |
| `<chan-name>` | String | Channel name for diagnostics |
| `<element-type>` | K item | Type descriptor for channel element type |
| `<buffer>` | List (Value) | Bounded FIFO queue of channel elements |
| `<capacity>` | Int | Maximum number of elements in the buffer |
| `<type-env>` | Map (TypeName -> TypeDescriptor) | Type definitions (ranges, record fields, array bounds) |
| `<global-env>` | Map (Identifier -> Location) | Package-level variable bindings |
| `<global-store>` | Map (Location -> Value) | Package-level mutable store |
| `<global-ownership>` | Map (Location -> OwnershipState) | Ownership state for package-level access variables |
| `<task-var-map>` | Map (Location -> TaskId) | Which task owns each package-level variable (for race-freedom) |
| `<next-loc>` | Int | Next fresh store location |
| `<next-chan>` | Int | Next fresh channel ID |
| `<next-task>` | Int | Next fresh task ID |
| `<elaboration-complete>` | Bool | Whether all package elaboration has finished |

### 3.2 Value Domain

```k
syntax Value ::= intVal(Int)          // Integer values (64-bit intermediates)
               | floatVal(Float)      // Floating-point values
               | boolVal(Bool)        // Boolean values
               | charVal(Int)         // Character values (position)
               | enumVal(String, Int) // Enumeration (type name, position)
               | nullVal()            // Null access value
               | ptrVal(Int)          // Non-null access value (store location)
               | arrayVal(Map)        // Array (index -> value)
               | recordVal(Map)       // Record (field name -> value)
               | unitVal()            // Void (for procedures)
```

### 3.3 Ownership State Domain

```k
syntax OwnershipState ::= "Null_State"
                        | "Owned"
                        | "Moved"
                        | "Borrowed"
                        | "Observed"
```

This corresponds directly to the `Ownership_State` enumeration in `companion/spark/safe_model.ads` (lines 184-185).

### 3.4 Type Descriptor Domain

```k
syntax TypeDescriptor ::= intType(Int, Int)        // Signed integer: range Lo..Hi
                        | modType(Int)              // Modular: mod N
                        | enumType(List)            // Enumeration: list of literal names
                        | floatType(Int, Float, Float) // Float: digits, range Lo..Hi
                        | arrayType(TypeDescriptor, TypeDescriptor)  // Index type, element type
                        | recordType(Map)           // Field name -> field type
                        | accessType(TypeDescriptor, Bool) // Designated type, is_not_null
                        | subtypeOf(String, TypeDescriptor) // Named subtype with constraint
```

---

## 4. Key Semantic Rules

This section presents representative K semantic rules for the major language features. Rules are written in K notation where `=>` denotes a rewrite, `...` denotes context that is unchanged, and `requires` introduces a side condition.

### 4.1 Expression Evaluation with Wide Arithmetic

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126

The fundamental semantic rule for integer arithmetic in Safe: all integer subexpressions evaluate to 64-bit signed intermediates. No intermediate overflow occurs within the 64-bit range; the compiler has statically verified that no intermediate exceeds the 64-bit range (spec/02-restrictions.md section 2.8.1, paragraph 129).

**Integer literal evaluation:**

```k
rule <k> intLiteral(S:String) => intVal(String2Int(S)) ... </k>
```

**Binary arithmetic on integers (addition):**

```k
rule <k> intVal(I1) + intVal(I2) => intVal(I1 +Int I2) ... </k>
  requires I1 +Int I2 >=Int minInt64
  andBool  I1 +Int I2 <=Int maxInt64
```

where `minInt64 = -(2^63)` and `maxInt64 = 2^63 - 1`. The side condition reflects the compiler's static guarantee (paragraph 129) that no intermediate exceeds the 64-bit range. If the condition fails, the configuration reaches a **stuck state**, modeling the compiler rejection.

**Subtraction, multiplication, exponentiation, abs, unary minus** follow the same pattern with their respective operations.

**Division with provably nonzero divisor (D27 Rule 3):**

```k
rule <k> intVal(I1) / intVal(I2) => intVal(I1 /Int I2) ... </k>
  requires I2 =/=Int 0
  andBool  notBool (I1 ==Int minInt64 andBool I2 ==Int -1)
```

The precondition `I2 =/= 0` corresponds to `Safe_PO.Nonzero` (`companion/spark/safe_po.ads`, line 148). The additional check for `minInt64 / -1` prevents signed overflow, corresponding to `Safe_PO.Safe_Div` (line 42).

**Modulo and remainder:**

```k
rule <k> intVal(I1) mod intVal(I2) => intVal(I1 modInt I2) ... </k>
  requires I2 =/=Int 0

rule <k> intVal(I1) rem intVal(I2) => intVal(I1 remInt I2) ... </k>
  requires I2 =/=Int 0
```

**Modular arithmetic (not lifted):**

Modular types use wrapping semantics. Per compiler/translation_rules.md section 8.4, modular operations are NOT lifted to wide intermediate. The K rule for modular addition:

```k
rule <k> modAdd(modVal(I1, M), modVal(I2, M)) => modVal((I1 +Int I2) modInt M, M) ... </k>
```

**Boolean and relational expressions** evaluate to `boolVal(true)` or `boolVal(false)` with standard semantics. Short-circuit `and then` and `or else` evaluate the right operand only if needed:

```k
rule <k> boolVal(false) andThen _ => boolVal(false) ... </k>
rule <k> boolVal(true)  andThen E => E ... </k>
rule <k> boolVal(true)  orElse  _ => boolVal(true)  ... </k>
rule <k> boolVal(false) orElse  E => E ... </k>
```

### 4.2 Narrowing Points

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127

Each narrowing point checks that the 64-bit intermediate value fits within the target type's declared range. These correspond to the five `Narrow_*` proof obligations in `companion/spark/safe_po.ads` (lines 52-109).

**4.2.1 Assignment Narrowing**

```k
rule <k> assign(Loc, intVal(V), intType(Lo, Hi))
         => checkNarrow(V, Lo, Hi) ~> store(Loc, intVal(V)) ... </k>

rule <k> checkNarrow(V, Lo, Hi) => .K ... </k>
  requires V >=Int Lo andBool V <=Int Hi

// Stuck state if narrowing fails -- models compile-time rejection
```

This rule corresponds to `Safe_PO.Narrow_Assignment` (safe_po.ads, line 52), where the precondition `Contains(Target, V)` is equivalent to the side condition `V >= Lo and V <= Hi`.

**4.2.2 Parameter Narrowing**

```k
rule <k> narrowParam(intVal(V), intType(Lo, Hi))
         => checkNarrow(V, Lo, Hi) ~> intVal(V) ... </k>
```

Corresponds to `Safe_PO.Narrow_Parameter` (safe_po.ads, line 65).

**4.2.3 Return Narrowing**

```k
rule <k> narrowReturn(intVal(V), intType(Lo, Hi))
         => checkNarrow(V, Lo, Hi) ~> intVal(V) ... </k>
```

Corresponds to `Safe_PO.Narrow_Return` (safe_po.ads, line 78).

**4.2.4 Index Narrowing**

```k
rule <k> narrowIndex(intVal(V), intType(Lo, Hi))
         => checkNarrow(V, Lo, Hi) ~> intVal(V) ... </k>
```

Corresponds to `Safe_PO.Narrow_Indexing` (safe_po.ads, line 91).

**4.2.5 Conversion/Annotation Narrowing**

```k
rule <k> narrowConversion(intVal(V), intType(Lo, Hi))
         => checkNarrow(V, Lo, Hi) ~> intVal(V) ... </k>
```

Corresponds to `Safe_PO.Narrow_Conversion` (safe_po.ads, line 104). Type annotation `(Expr as T)` uses the same rule, since the annotated expression translates to a conversion at the target type (compiler/translation_rules.md section 3).

**4.2.6 Floating-Point Narrowing (D27 Rule 5)**

```k
rule <k> checkNarrowFloat(V, FLo, FHi) => .K ... </k>
  requires V ==Float V                     // not NaN (NaN /= NaN)
  andBool  V >=Float FLo andBool V <=Float FHi  // finite and in range
```

This corresponds to `Safe_PO.FP_Not_NaN` (safe_po.ads, line 218) and `Safe_PO.FP_Not_Infinity` (safe_po.ads, line 230). The condition `V == V` exploits the IEEE 754 property that NaN is the only value not equal to itself. The range check ensures the value is finite and within the target type's model range, per spec/02-restrictions.md section 2.8.5 paragraphs 139b-139d.

### 4.3 Ownership State Machine

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.3

The ownership model is formalized as transitions on the `<ownership>` cell. Each rule matches an ownership operation and updates the ownership state of the relevant locations. The state machine corresponds directly to `Safe_Model.Is_Valid_Transition` (companion/spark/safe_model.ads, lines 223-238) and the ownership state enumeration `Ownership_State` (line 184).

**4.3.1 Variable Creation (Allocator)**

```k
rule <k> allocate(T) => ptrVal(L) ... </k>
     <store> S => S[L <- defaultValue(T)] </store>
     <ownership> O => O[L <- Owned] </ownership>
     <next-loc> L => L +Int 1 </next-loc>
```

Transition: Null_State -> Owned. The new location is marked `Owned`. Corresponds to spec/02-restrictions.md section 2.3.5 paragraph 103.

**4.3.2 Move**

```k
rule <k> moveAssign(TargetLoc, SourceLoc) => .K ... </k>
     <store> S => S[TargetLoc <- S[SourceLoc]][SourceLoc <- nullVal()] </store>
     <ownership> O => O[TargetLoc <- Owned][SourceLoc <- Moved] </ownership>
  requires O[SourceLoc] ==K Owned
  andBool  (O[TargetLoc] ==K Null_State orBool S[TargetLoc] ==K nullVal())
```

Source: Owned -> Moved. Target: * -> Owned. The source is set to null after the move. The precondition that the target is provably null corresponds to the null-before-move legality rule (spec/02-restrictions.md section 2.3.2, paragraph 97a) and `Safe_PO.Check_Owned_For_Move` (safe_po.ads, line 277).

**4.3.3 Borrow**

```k
rule <k> borrow(BorrowerLoc, LenderLoc) => .K ... </k>
     <store> S => S[BorrowerLoc <- ptrVal(deref(S[LenderLoc]))] </store>
     <ownership> O => O[BorrowerLoc <- Borrowed][LenderLoc <- Borrowed] </ownership>
  requires O[LenderLoc] ==K Owned
```

Lender: Owned -> Borrowed (frozen). Borrower: new -> Borrowed (has mutable access). Corresponds to `Safe_PO.Check_Borrow_Exclusive` (safe_po.ads, line 287).

**4.3.4 Observe**

```k
rule <k> observe(ObserverLoc, ObservedLoc) => .K ... </k>
     <store> S => S[ObserverLoc <- ptrVal(deref(S[ObservedLoc]))] </store>
     <ownership> O => O[ObserverLoc <- Observed]
                       [ObservedLoc <- Observed] </ownership>
  requires O[ObservedLoc] ==K Owned orBool O[ObservedLoc] ==K Observed
```

Observed: Owned -> Observed (or Observed -> Observed for multiple observers). Observer: new -> Observed (read-only access). Corresponds to `Safe_PO.Check_Observe_Shared` (safe_po.ads, line 295).

**4.3.5 Borrow End (Scope Exit)**

```k
rule <k> endBorrow(BorrowerLoc, LenderLoc) => .K ... </k>
     <ownership> O => O[BorrowerLoc <- Null_State][LenderLoc <- Owned] </ownership>
  requires O[LenderLoc] ==K Borrowed
```

Lender: Borrowed -> Owned (unfrozen). Borrower: Borrowed -> Null_State.

**4.3.6 Observe End (Scope Exit)**

```k
rule <k> endObserve(ObserverLoc, ObservedLoc) => .K ... </k>
     <ownership> O => O[ObserverLoc <- Null_State]
                       [ObservedLoc <- Owned] </ownership>
  requires O[ObservedLoc] ==K Observed
```

Observed: Observed -> Owned (when last observer exits). Observer: Observed -> Null_State.

**4.3.7 Automatic Deallocation (Scope Exit)**

```k
rule <k> scopeExit(Locs:List) => deallocateAll(reverse(Locs)) ... </k>

rule <k> deallocateAll(ListItem(L) Rest) =>
         deallocateOne(L) ~> deallocateAll(Rest) ... </k>
rule <k> deallocateAll(.List) => .K ... </k>

rule <k> deallocateOne(L) => .K ... </k>
     <store> S => S[L <- nullVal()] </store>
     <ownership> O => O[L <- Null_State] </ownership>
  requires S[L] =/=K nullVal()
  andBool  isPoolSpecific(typeOf(L))

// Skip deallocation for null or non-pool-specific access
rule <k> deallocateOne(L) => .K ... </k>
  requires S[L] ==K nullVal()
  orBool   notBool isPoolSpecific(typeOf(L))
```

Reverse declaration order per spec/02-restrictions.md section 2.3.5 paragraph 105. Conditional null check per section 9.5 of compiler/translation_rules.md. General access types (`access all T`) are not deallocated per paragraph 106.

**4.3.8 Error Rules (Stuck States)**

The following represent illegal operations that cause a stuck state, modeling compile-time rejection:

```k
// Use-after-move: attempting to read a moved variable
rule <k> readVar(L) => stuck("use-after-move") ... </k>
     <ownership> ... L |-> Moved ... </ownership>

// Double-borrow: attempting to borrow an already-borrowed variable
rule <k> borrow(_, LenderLoc) => stuck("double-borrow") ... </k>
     <ownership> ... LenderLoc |-> Borrowed ... </ownership>

// Borrow-while-observed: attempting to borrow an observed variable
rule <k> borrow(_, LenderLoc) => stuck("borrow-while-observed") ... </k>
     <ownership> ... LenderLoc |-> Observed ... </ownership>

// Write-while-borrowed: attempting to write through a frozen lender
rule <k> writeVar(LenderLoc, _) => stuck("write-while-borrowed") ... </k>
     <ownership> ... LenderLoc |-> Borrowed ... </ownership>

// Write-while-observed: attempting to write to an observed variable
rule <k> writeVar(ObservedLoc, _) => stuck("write-while-observed") ... </k>
     <ownership> ... ObservedLoc |-> Observed ... </ownership>

// Null dereference: attempting to dereference a null pointer (D27 Rule 4)
rule <k> deref(nullVal()) => stuck("null-dereference") ... </k>
```

### 4.4 Channel Operations

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.3

Channel operations interact with the `<channels>` configuration. Blocking semantics are modeled by setting `<blocked>` to `true` and recording the block reason.

**4.4.1 Channel Creation**

```k
rule <k> channelDecl(Name, ElemType, Cap) => .K ... </k>
     <channels>
       ... (.Bag =>
         <channel>
           <chan-id> CId </chan-id>
           <chan-name> Name </chan-name>
           <element-type> ElemType </element-type>
           <buffer> .List </buffer>
           <capacity> Cap </capacity>
         </channel>)
     </channels>
     <next-chan> CId => CId +Int 1 </next-chan>
  requires Cap >=Int 1
```

The `requires Cap >= 1` corresponds to `Safe_PO.Check_Channel_Capacity_Positive` (safe_po.ads, line 335) and spec/04-tasks-and-channels.md section 4.2 paragraph 15.

**4.4.2 Send (Blocking)**

```k
// Send when channel has space
rule <k> send(CId, V) => .K ... </k>
     <chan-id> CId </chan-id>
     <buffer> Buf => Buf ListItem(V) </buffer>
     <capacity> Cap </capacity>
  requires size(Buf) <Int Cap

// Send when channel is full: block
rule <k> send(CId, V) => blocked(send(CId, V)) ... </k>
     <chan-id> CId </chan-id>
     <buffer> Buf </buffer>
     <capacity> Cap </capacity>
     <blocked> false => true </blocked>
     <block-reason> .K => sendBlock(CId) </block-reason>
  requires size(Buf) >=Int Cap
```

The non-blocking path corresponds to `Safe_PO.Check_Channel_Not_Full` (safe_po.ads, line 314). The FIFO property is ensured by appending to the end of the list.

**4.4.3 Receive (Blocking)**

```k
// Receive when channel has data
rule <k> receive(CId, TargetLoc) => .K ... </k>
     <chan-id> CId </chan-id>
     <buffer> ListItem(V) Rest => Rest </buffer>
     <store> S => S[TargetLoc <- V] </store>

// Receive when channel is empty: block
rule <k> receive(CId, TargetLoc) => blocked(receive(CId, TargetLoc)) ... </k>
     <chan-id> CId </chan-id>
     <buffer> .List </buffer>
     <blocked> false => true </blocked>
     <block-reason> .K => receiveBlock(CId) </block-reason>
```

The non-blocking path corresponds to `Safe_PO.Check_Channel_Not_Empty` (safe_po.ads, line 325). Elements are dequeued from the front of the list (FIFO).

**4.4.4 Try_Send (Non-Blocking)**

```k
// try_send when channel has space
rule <k> trySend(CId, V, SuccessLoc) => .K ... </k>
     <chan-id> CId </chan-id>
     <buffer> Buf => Buf ListItem(V) </buffer>
     <capacity> Cap </capacity>
     <store> S => S[SuccessLoc <- boolVal(true)] </store>
  requires size(Buf) <Int Cap

// try_send when channel is full
rule <k> trySend(CId, V, SuccessLoc) => .K ... </k>
     <chan-id> CId </chan-id>
     <buffer> Buf </buffer>
     <capacity> Cap </capacity>
     <store> S => S[SuccessLoc <- boolVal(false)] </store>
  requires size(Buf) >=Int Cap
```

**4.4.5 Try_Receive (Non-Blocking)**

```k
// try_receive when channel has data
rule <k> tryReceive(CId, TargetLoc, SuccessLoc) => .K ... </k>
     <chan-id> CId </chan-id>
     <buffer> ListItem(V) Rest => Rest </buffer>
     <store> S => S[TargetLoc <- V][SuccessLoc <- boolVal(true)] </store>

// try_receive when channel is empty
rule <k> tryReceive(CId, TargetLoc, SuccessLoc) => .K ... </k>
     <chan-id> CId </chan-id>
     <buffer> .List </buffer>
     <store> S => S[SuccessLoc <- boolVal(false)] </store>
```

**4.4.6 Copy-Only Channel Payloads**

Safe now excludes channel element types that are access types or composite types
containing access-type subcomponents. The K model therefore treats channel
payloads as copy-only values; ownership transfer through channels is outside the
current language.

The exclusion corresponds to spec/04-tasks-and-channels.md section 4.2
paragraph 14, while the copy-only consequences correspond to section 4.3
paragraphs 27a, 28a, 29a, 29b, 30, and 31a.

### 4.5 Deterministic Select

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.4

The `select` statement is the most complex concurrent construct in Safe. Its deterministic arm-ordering semantics are modeled as a sequential scan through the arm list.

```k
// Select: try arms in declaration order
rule <k> selectStmt(Arms, MaybeDelay) =>
         tryArms(Arms, MaybeDelay, startTime()) ... </k>

// Try first channel arm: data available
rule <k> tryArms(
           ListItem(channelArm(VarName, VarType, CId, Body)) RestArms,
           MaybeDelay, StartT)
         => bind(VarName, V, VarType) ~> Body
            ~> unbind(VarName) ... </k>
     <chan-id> CId </chan-id>
     <buffer> ListItem(V) Rest => Rest </buffer>

// Try first channel arm: no data, continue to next arm
rule <k> tryArms(
           ListItem(channelArm(VarName, VarType, CId, Body)) RestArms,
           MaybeDelay, StartT)
         => tryArms(RestArms, MaybeDelay, StartT) ... </k>
     <chan-id> CId </chan-id>
     <buffer> .List </buffer>

// No more channel arms, delay arm present, timeout reached
rule <k> tryArms(.List, delayArm(Duration, Body), StartT)
         => Body ... </k>
  requires elapsed(StartT) >=Float Duration

// No more channel arms, delay arm present, timeout not reached: retry
rule <k> tryArms(.List, delayArm(Duration, Body), StartT)
         => pollDelay() ~> tryArms(AllArms, delayArm(Duration, Body), StartT)
         ... </k>
  requires elapsed(StartT) <Float Duration

// No more channel arms, no delay arm: retry (blocking)
rule <k> tryArms(.List, noDelay(), StartT)
         => pollDelay() ~> tryArms(AllArms, noDelay(), StartT) ... </k>
```

The declaration-order priority is ensured by processing arms left-to-right. The first arm whose channel has data is selected immediately. This matches spec/04-tasks-and-channels.md section 4.4 paragraph 41: "the first listed channel arm is selected."

### 4.6 Task Startup and Scheduling

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.7

```k
// Elaboration: process all package-level declarations
rule <k> elaborate(PackageDecls) => processDecls(PackageDecls)
         ~> setElaborationComplete() ... </k>
     <task-id> 0 </task-id>

// After elaboration, activate all tasks
rule <k> setElaborationComplete() => .K ... </k>
     <elaboration-complete> false => true </elaboration-complete>

// Task activation: a task thread begins only after elaboration is complete
rule <k> taskStart(Body) => Body ... </k>
     <task-id> TId </task-id>
     <elaboration-complete> true </elaboration-complete>
  requires TId =/=Int 0
```

This models the guarantee from spec/04-tasks-and-channels.md section 4.7 paragraph 56: "All package-level declarations and initialisations across all compilation units complete before any task begins executing."

### 4.7 Task-Variable Ownership Check

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.5

```k
// Task accesses a global variable: check exclusive ownership
rule <k> accessGlobal(VarLoc) => .K ... </k>
     <task-id> TId </task-id>
     <task-var-map> TVM => TVM[VarLoc <- TId] </task-var-map>
  requires TId =/=Int 0
  andBool  (TVM[VarLoc] ==Int 0 orBool TVM[VarLoc] ==Int TId)

// Task accesses a global variable already owned by another task: stuck
rule <k> accessGlobal(VarLoc) => stuck("data-race") ... </k>
     <task-id> TId </task-id>
     <task-var-map> ... VarLoc |-> OtherTId ... </task-var-map>
  requires TId =/=Int 0
  andBool  OtherTId =/=Int 0
  andBool  OtherTId =/=Int TId
```

This corresponds to `Safe_PO.Check_Exclusive_Ownership` (safe_po.ads, line 353) and the `Safe_Model.Task_Var_Map` type (safe_model.ads, line 269).

---

## 5. kprove Properties

The K framework's symbolic execution engine `kprove` can verify properties of Safe programs by exploring all reachable states symbolically. The following properties are the primary verification targets.

### 5.1 Type Safety

**Property:** Well-typed Safe programs do not produce runtime type errors.

**Formalization:** For every reachable configuration `C` starting from a well-typed program, no rule produces a `stuck("type-error")` state.

**Key lemmas:**

1. **Narrowing soundness.** For every narrowing point (assignment, parameter, return, index, conversion), if the static range analysis accepts the program, then the runtime value is within the target type's range. Formally: if `checkNarrow(V, Lo, Hi)` does not get stuck, then `Lo <= V <= Hi`.

2. **Wide arithmetic preservation.** Every intermediate integer value fits within the 64-bit signed range. Formally: for every `intVal(I)` produced during evaluation, `-(2^63) <= I <= 2^63 - 1`.

3. **Modular arithmetic wrapping.** Modular operations produce values in `0 .. M-1`. Formally: for every `modVal(I, M)`, `0 <= I < M`.

### 5.2 Memory Safety

**Property:** No Safe program dereferences a null pointer, accesses a moved value, or leaks memory.

**Formalization:**

1. **No use-after-move.** For every reachable configuration, no `readVar(L)` or `writeVar(L, _)` is attempted when `ownership[L] = Moved`.

2. **No null dereference.** For every reachable configuration, no `deref(nullVal())` occurs. This is guaranteed by D27 Rule 4 (spec/02-restrictions.md section 2.8.4, paragraph 136): dereference requires a `not null` access subtype.

3. **No memory leaks.** For every pool-specific access variable that goes out of scope with a non-null value, the automatic deallocation rule fires. Formally: at the final configuration, every location that was allocated has been deallocated.

4. **Borrows are exclusive.** No configuration has two simultaneous mutable borrows of the same location. Formally: for every location L, at most one `Borrowed` entry exists in the ownership map pointing to the same designated object.

5. **Observes are shared-readonly.** While an observe is active, no mutation of the observed data occurs. Formally: if `ownership[L] = Observed`, then no `writeVar(L, _)` rule can fire.

### 5.3 Channel Safety

**Property:** Channel operations preserve the bounded FIFO invariant, and no data corruption occurs under concurrent access.

**Formalization:**

1. **Capacity bound.** For every reachable configuration, `size(buffer) <= capacity`. The `send` rule only adds an element when `size(buffer) < capacity`.

2. **FIFO ordering.** Elements are dequeued in the order they were enqueued. The K `List` data structure with `ListItem(V) Rest` pattern-matching at the head and `Buf ListItem(V)` appending at the tail ensures this.

3. **Atomicity.** Channel operations are atomic with respect to each other. In the K model, each rule application is atomic (a single rewrite step), ensuring no interleaving within a channel operation.

4. **Channel non-ownership invariant.** Channel buffers never store owning access values because access-bearing channel element types are illegal. This keeps queued channel state disjoint from task-owned heap objects. Corresponds to spec/04-tasks-and-channels.md section 4.3 paragraph 31a.

### 5.4 Determinism

**Property:** Given identical channel states, the `select` statement produces deterministic results.

**Formalization:**

1. **Select determinism.** For any configuration where a `select` statement is evaluated, the chosen arm depends only on: (a) the order of arms in the source, and (b) the emptiness/non-emptiness of each channel at the point of evaluation. Two executions with the same channel states at the point of `select` evaluation will choose the same arm.

2. **No data races on shared state.** The task-variable ownership rule (section 4.5) ensures that no package-level variable is accessed by more than one task. Combined with channel-mediated communication, this guarantees sequential consistency of each task's view of its own variables. Formally: for every reachable configuration, the `task-var-map` has no entry with more than one distinct non-zero task ID. Corresponds to `Safe_Model.No_Shared_Variables` (safe_model.ads, line 313).

---

## 6. Relationship to D27 Rules

The five D27 Silver-by-construction rules (spec/02-restrictions.md section 2.8) map to specific K semantic components and kprove verification properties. The following table provides a comprehensive mapping.

| D27 Rule | Spec Reference | K Semantic Component | K Rules | kprove Property | SPARK PO Correspondence |
|---|---|---|---|---|---|
| **Rule 1: Wide arithmetic** | 2.8.1, p126-130 | Expression evaluation rules (section 4.1), narrowing-point rules (section 4.2) | `intVal(I1) + intVal(I2) => intVal(I1 +Int I2)` with 64-bit bounds; `checkNarrow(V, Lo, Hi)` at all 5 narrowing points | Type safety: no integer overflow at any intermediate or narrowing point. For all reachable `intVal(I)`, `minInt64 <= I <= maxInt64`. For all narrowing points, `Lo <= V <= Hi`. | `Safe_PO.Narrow_Assignment`, `Safe_PO.Narrow_Parameter`, `Safe_PO.Narrow_Return`, `Safe_PO.Narrow_Indexing`, `Safe_PO.Narrow_Conversion` |
| **Rule 2: Index safety** | 2.8.2, p131-132 | Array access rules in `safe-expressions.k` | `arrayAccess(Arr, intVal(Idx)) => ...` requires `Arr'First <= Idx <= Arr'Last` | No out-of-bounds array access. For all `arrayAccess` rules, the index is within bounds (stuck state otherwise). | `Safe_PO.Safe_Index` |
| **Rule 3: Division safety** | 2.8.3, p133-134 | Division/mod/rem rules (section 4.1) | `intVal(I1) / intVal(I2)` requires `I2 /= 0` and not (`I1 = minInt64` and `I2 = -1`) | No division by zero. No signed division overflow. For all division rules, the divisor is nonzero. | `Safe_PO.Nonzero`, `Safe_PO.Safe_Div`, `Safe_PO.Safe_Mod`, `Safe_PO.Safe_Rem` |
| **Rule 4: Null safety** | 2.8.4, p136-138 | Pointer dereference rules (section 4.3) | `deref(nullVal()) => stuck("null-dereference")` | No null dereference. For all `deref` operations, the access value is non-null (guaranteed by `not null` subtype requirement). | `Safe_PO.Not_Null_Ptr`, `Safe_PO.Safe_Deref` |
| **Rule 5: FP non-trapping** | 2.8.5, p139-139e | Float evaluation rules + float narrowing rules (section 4.2.6) | `checkNarrowFloat(V, FLo, FHi)` requires `V == V` (not NaN) and `FLo <= V <= FHi` (finite and in range) | No NaN or infinity at narrowing points. All narrowed float values are finite and within the target type's range. IEEE 754 non-trapping mode means no float exceptions -- overflow produces infinity, which is caught at narrowing. | `Safe_PO.FP_Not_NaN`, `Safe_PO.FP_Not_Infinity`, `Safe_PO.FP_Safe_Div` |

### 6.1 Additional Safety Properties Beyond D27

| Property | K Semantic Component | kprove Formulation |
|---|---|---|
| **Use-after-move** | Ownership state machine (section 4.3) | No `readVar(L)` when `ownership[L] = Moved` |
| **Memory leak freedom** | Automatic deallocation (section 4.3.7) | Every allocated location is deallocated by final configuration |
| **Borrow exclusivity** | Borrow rules (section 4.3.3) | At most one `Borrowed` alias per designated object |
| **Data race freedom** | Task-variable ownership (section 4.7) | No variable accessed by more than one task |
| **Channel capacity invariant** | Channel operations (section 4.4) | `size(buffer) <= capacity` in all reachable states |
| **FIFO ordering** | Channel buffer structure (section 4.4) | Dequeue order matches enqueue order |
| **Select determinism** | Select rules (section 4.5) | Same channel state implies same arm choice |
| **Non-termination** | Task structure rules (section 4.6) | Task body's outermost construct is unconditional loop |
| **Elaboration-before-activation** | Task startup rules (section 4.6) | No task code executes until `elaboration-complete = true` |

---

## 7. K Skeleton Structure

The following directory structure organizes the K definition into modular files, each covering a coherent subset of Safe's semantics. The structure mirrors the phased development plan.

```
k/
  safe.k                     -- Top-level module, imports all sub-modules
  safe-syntax.k              -- BNF grammar in K syntax (from spec/08-syntax-summary.md)
  safe-configuration.k       -- K configuration (section 3 of this document)
  safe-values.k              -- Value domain, type descriptors, ownership states

  -- Phase 1: Core
  safe-expressions.k         -- Expression evaluation rules with wide arithmetic
  safe-statements.k          -- Statement evaluation rules (if, case, loop, etc.)
  safe-narrowing.k           -- Narrowing-point rules (5 categories)
  safe-subprograms.k         -- Subprogram call/return, parameter passing
  safe-types.k               -- Type declaration processing, range computation
  safe-packages.k            -- Package elaboration, with-clause resolution

  -- Phase 2: Ownership + Pointers + Arrays
  safe-ownership.k           -- Ownership state machine rules
  safe-pointers.k            -- Pointer allocation, dereference, null checks
  safe-arrays.k              -- Array indexing with bounds checks, slicing
  safe-records.k             -- Record field access, discriminant checks
  safe-deallocation.k        -- Automatic scope-exit deallocation rules

  -- Phase 3: Concurrency
  safe-channels.k            -- Channel creation, send, receive, try_send, try_receive
  safe-select.k              -- Select statement with deterministic arm ordering
  safe-tasks.k               -- Task declaration, activation, scheduling, non-termination
  safe-task-ownership.k      -- Task-variable exclusive ownership checking

  -- Verification
  specs/
    type-safety.k            -- kprove specification: type safety properties
    memory-safety.k          -- kprove specification: ownership/pointer safety
    channel-safety.k         -- kprove specification: channel invariants
    determinism.k            -- kprove specification: select determinism, race freedom
    d27-rules.k              -- kprove specification: all 5 D27 rules

  -- Tests
  tests/
    positive/                -- Programs that should execute to completion
      arithmetic/
        average.safe         -- Wide intermediate arithmetic (D27 Rule 1)
        weighted-avg.safe    -- Multi-operand wide arithmetic
        division.safe        -- Division by nonzero (D27 Rule 3)
        modular.safe         -- Modular arithmetic (not lifted)
      arrays/
        safe-index.safe      -- Type-contained indexing (D27 Rule 2)
        guarded-index.safe   -- Condition-guarded indexing
        for-of-loop.safe     -- Array iteration
      pointers/
        allocate-free.safe   -- Allocator + auto deallocation
        move.safe            -- Move semantics
        borrow.safe          -- Borrow and unfreeze
        observe.safe         -- Multiple observers
      channels/
        producer-consumer.safe -- Basic send/receive
        try-operations.safe  -- try_send/try_receive
        ownership-xfer.safe  -- Ownership transfer through channels
      select/
        two-channel.safe     -- Select with two channel arms
        with-timeout.safe    -- Select with delay arm
        priority-order.safe  -- Arm priority by declaration order
      tasks/
        startup-order.safe   -- Elaboration before activation
        independent-vars.safe -- Task-variable ownership conforming
    negative/                -- Programs that should reach stuck states
      arithmetic/
        overflow.safe        -- Intermediate exceeds 64-bit (stuck)
        narrowing-fail.safe  -- Narrowing check fails (stuck)
        div-by-zero.safe     -- Divisor includes zero (stuck)
      arrays/
        out-of-bounds.safe   -- Index type wider than array bounds (stuck)
      pointers/
        null-deref.safe      -- Dereference of nullable type (stuck)
        use-after-move.safe  -- Read moved variable (stuck)
        double-borrow.safe   -- Borrow already-borrowed (stuck)
        borrow-observed.safe -- Borrow already-observed (stuck)
        leak.safe            -- Overwrite non-null owner (stuck)
      channels/
        send-full.safe       -- Send to full channel without blocking
      tasks/
        shared-variable.safe -- Two tasks access same variable (stuck)
```

### 7.1 Module Dependency Graph

```
safe.k
  |-- safe-syntax.k
  |-- safe-configuration.k
  |     |-- safe-values.k
  |-- safe-types.k
  |-- safe-expressions.k
  |     |-- safe-narrowing.k
  |-- safe-statements.k
  |     |-- safe-subprograms.k
  |-- safe-packages.k
  |-- safe-ownership.k
  |     |-- safe-pointers.k
  |     |-- safe-deallocation.k
  |-- safe-arrays.k
  |-- safe-records.k
  |-- safe-channels.k
  |-- safe-select.k
  |-- safe-tasks.k
  |     |-- safe-task-ownership.k
```

### 7.2 Grammar Encoding Strategy

The K syntax module (`safe-syntax.k`) encodes the 148 BNF productions from spec/08-syntax-summary.md. Key encoding decisions:

1. **Alternation productions** (e.g., `type_definition`, `simple_statement`, `compound_statement`) become K sort declarations with subsort relationships.

2. **Alias productions** (e.g., `subtype_mark ::= name`, `condition ::= expression`) become K subsort declarations: `syntax SubtypeMark = Name`.

3. **Lexical productions** (identifiers, numeric literals) are handled by K's built-in lexer infrastructure using regular expression tokens.

4. **The `name` ambiguity** (IndexedComponent vs. Slice vs. TypeConversion vs. FunctionCall all share `name(args)` syntax) is resolved by K disambiguation rules or a post-parse resolution pass, mirroring the compiler's `CallOrIndex` intermediate node described in compiler/ast_schema.json (line 1612).

---

## 8. Effort Estimate and Roadmap

### 8.1 Phase 1: Core (Expressions, Statements, Subprograms)

**Scope:** Sequential single-task Safe with wide arithmetic and narrowing points.

| Work Item | Estimated Effort | Dependencies |
|---|---|---|
| K syntax encoding (148 productions) | 3 person-weeks | spec/08-syntax-summary.md |
| K configuration design | 1 person-week | compiler/ast_schema.json |
| Expression evaluation rules | 3 person-weeks | safe-syntax.k |
| Narrowing-point rules (5 categories) | 2 person-weeks | safe-expressions.k |
| Statement evaluation rules | 2 person-weeks | safe-expressions.k |
| Subprogram call/return | 2 person-weeks | safe-statements.k |
| Type processing and packages | 2 person-weeks | safe-types.k |
| Positive/negative test suite | 2 person-weeks | all Phase 1 modules |
| kprove: D27 Rules 1, 3 | 2 person-weeks | all Phase 1 modules |

**Phase 1 total: approximately 2-3 person-months (19 person-weeks)**

### 8.2 Phase 2: Ownership, Pointers, Arrays, Records

**Scope:** Memory model with heap, ownership state machine, and aggregate types.

| Work Item | Estimated Effort | Dependencies |
|---|---|---|
| Ownership state machine rules | 2 person-weeks | Phase 1 complete |
| Pointer allocation and dereference | 2 person-weeks | safe-ownership.k |
| Automatic deallocation rules | 2 person-weeks | safe-ownership.k |
| Array indexing and bounds checking | 1 person-week | safe-expressions.k |
| Record field access | 1 person-week | safe-expressions.k |
| Positive/negative test suite | 1 person-week | all Phase 2 modules |
| kprove: D27 Rules 2, 4; memory safety | 2 person-weeks | all Phase 2 modules |

**Phase 2 total: approximately 2 person-months (11 person-weeks)**

### 8.3 Phase 3: Concurrency (Tasks, Channels, Select)

**Scope:** Full concurrency model with static tasks, bounded channels, and deterministic select.

| Work Item | Estimated Effort | Dependencies |
|---|---|---|
| Channel creation and operations | 2 person-weeks | Phase 2 complete |
| Ownership transfer through channels | 2 person-weeks | safe-channels.k, safe-ownership.k |
| Select statement rules | 3 person-weeks | safe-channels.k |
| Task declaration and activation | 2 person-weeks | safe-packages.k |
| Task scheduling and blocking | 2 person-weeks | safe-tasks.k |
| Task-variable ownership checking | 1 person-week | safe-tasks.k |
| Non-termination enforcement | 0.5 person-weeks | safe-tasks.k |
| Positive/negative test suite | 2 person-weeks | all Phase 3 modules |
| kprove: channel safety, determinism, race freedom | 3 person-weeks | all Phase 3 modules |
| kprove: D27 Rule 5 (floating-point) | 2 person-weeks | safe-expressions.k |

**Phase 3 total: approximately 3-4 person-months (19.5 person-weeks)**

### 8.4 Summary

| Phase | Scope | Duration | Prerequisites |
|---|---|---|---|
| Phase 1 | Core: expressions, statements, subprograms, wide arithmetic, narrowing | 2-3 person-months | Spec finalized |
| Phase 2 | Ownership, pointers, arrays, records, automatic deallocation | 2 person-months | Phase 1 |
| Phase 3 | Tasks, channels, select, task-variable ownership, FP safety | 3-4 person-months | Phase 2 |
| **Total** | **Full Safe language** | **7-9 person-months** | |

### 8.5 Risk Factors

| Risk | Impact | Mitigation |
|---|---|---|
| K framework maturity for Ada-like languages | Medium -- K has been used for C, Java, JavaScript, but not Ada. Ada-specific constructs (discriminated records, range constraints) may require novel encoding patterns. | Start with a minimal prototype (Phase 1 core subset) to validate the approach before committing to full formalization. |
| Concurrency state-space explosion | High -- symbolic execution of concurrent programs can be expensive. Even with static tasks and bounded channels, the number of interleavings grows combinatorially. | Exploit Safe's task-variable ownership rule to reduce the state space: since no variable is shared between tasks, many interleavings are equivalent. Use K's `--smt-timeout` and partial-order reduction where available. |
| Floating-point semantics in K | Medium -- K's support for IEEE 754 semantics is less mature than its integer support. NaN propagation and infinity handling require careful encoding. | Phase FP formalization (D27 Rule 5) into Phase 3, allowing time for the K team to address any framework limitations. Use concrete float testing before symbolic. |
| Spec evolution | Low -- the spec is at frozen commit 468cf72 and appears stable. | Pin all K rules to clause IDs from the frozen commit. Re-derive rules if the spec changes. |

---

## 9. Comparison with SPARK Approach

The following table compares the SPARK companion approach (deductive verification via GNATprove) with the K framework approach (rewrite-based executable semantics).

| Aspect | SPARK / GNATprove | K Framework |
|---|---|---|
| **Verification method** | Deductive: generates verification conditions (VCs) and discharges them with SMT solvers (CVC5, Z3, Alt-Ergo). | Rewrite-based: symbolic execution explores all reachable states by applying semantic rules. |
| **What it proves** | AoRTE (Absence of Run-Time Errors) for emitted Ada/SPARK code. Contract satisfaction. Flow analysis (Global, Depends). | Type safety, memory safety, channel safety, and semantic properties of the Safe language itself. |
| **Executable** | No -- proof only. GNATprove does not execute programs. | Yes -- the K definition IS a reference interpreter. Programs can be run directly from the formal semantics. |
| **Concurrency** | Limited. SPARK supports Ravenscar/Jorvik profile but concurrent verification is restricted. Protected object bodies are verified sequentially. | Native. K's rewriting engine can explore concurrent interleavings. The `<thread multiplicity="*">` cell supports arbitrary interleaving exploration. |
| **Maturity for Ada** | Production. GNATprove has been used in industrial projects (Thales, Airbus, etc.) for over a decade. | Research. No existing K definition for Ada or Safe. This would be a novel formalization. |
| **Specification language** | SPARK contracts (Pre, Post, Global, Depends) written in Ada subset with ghost code. | K rules written in K notation. The specification IS the semantics. |
| **Proof granularity** | Per-subprogram. Each function/procedure is verified independently with its contracts. | Per-program or per-property. Symbolic execution can verify properties about entire programs or about the language semantics. |
| **Test generation** | No built-in test generation. | Yes. K can generate concrete test cases from symbolic execution paths. |
| **Scope of verification** | Verifies the emitted Ada/SPARK code (after translation from Safe). | Verifies the Safe language semantics (before translation to Ada). |
| **Complementary role** | Ensures the implementation (emitted Ada) satisfies its contracts. | Ensures the specification (Safe semantics) is sound and the D27 rules achieve their goals. |

### 9.1 Complementary Verification Architecture

```
Safe Source Code
       |
       |  [K Framework: verify semantics]
       |  - Type safety (D27 Rules 1-5)
       |  - Memory safety (ownership)
       |  - Channel safety (FIFO, capacity)
       |  - Determinism (select, race-freedom)
       |  - Executable reference interpreter
       |
       v
   Safe Compiler (translation_rules.md)
       |
       |  [Translation correctness]
       |  - K semantics of Safe ==> Ada semantics of emitted code
       |  - (Manual review or future bisimulation proof)
       |
       v
   Emitted Ada/SPARK Code
       |
       |  [SPARK/GNATprove: verify implementation]
       |  - AoRTE (Bronze: flow, Silver: runtime checks)
       |  - Global/Depends contracts
       |  - Ownership model (SPARK RM 3.10)
       |  - Protected object verification
       |
       v
   Verified Executable
```

The K semantics provides the formal foundation at the top of this chain, while GNATprove provides the implementation-level assurance at the bottom. Together, they form a defense-in-depth verification strategy: the K semantics guarantees that the language design is sound, and GNATprove guarantees that the compiled output is correct.

---

## 10. Assumption Linkage

The SPARK companion tracks 14 assumptions in `companion/assumptions.yaml` -- dependencies that the companion relies on but cannot verify within SPARK itself. Several of these assumptions directly affect the semantic modeling choices made in this K definition. This section maps each relevant assumption to its K semantic counterpart and notes whether the K semantics can help discharge the assumption or whether it remains an external dependency.

### 10.1 Assumption-to-K-Component Mapping

| Assumption ID | Summary | Severity | K Semantic Component(s) | Relationship |
|---|---|---|---|---|
| **A-01** | 64-bit intermediate integer evaluation | Critical | Expression evaluation rules (section 4.1), narrowing-point rules (section 4.2), `intVal` value domain (section 3.2) | **External dependency.** The K rules enforce `minInt64 <= I <= maxInt64` side conditions on all integer operations, directly encoding this assumption. The K semantics *relies on* A-01 but cannot discharge it -- the guarantee that physical hardware provides 64-bit intermediates is outside the model. |
| **A-02** | IEEE 754 non-trapping floating-point mode | Critical | Float narrowing rules (section 4.2.6), `checkNarrowFloat` rules, `floatVal` value domain | **External dependency.** The K rules model NaN detection via `V == V` and infinity detection via range checks at narrowing points, assuming that intermediate float operations silently propagate NaN and infinity per IEEE 754. The hardware non-trapping guarantee is outside the model. |
| **A-03** | Static range analysis is sound | Critical | Narrowing-point rules (section 4.2), the "stuck state" model for compile-time rejection | **Partially dischargeable.** The K semantics models the *runtime effect* of narrowing points: if a value passes `checkNarrow`, it is in range. `kprove` can verify that, given the compiler's static guarantee, no narrowing check fails at runtime. However, soundness of the compiler's analysis itself is external. The K semantics can serve as a cross-check: a program accepted by the compiler should not reach a narrowing stuck state in the K interpreter. |
| **A-04** | Channel implementation correctly serializes access | Critical | Channel operation rules (section 4.4), `<channel>` configuration cell (section 3) | **External dependency.** The K model treats each channel operation as an atomic rewrite step, implicitly assuming serialization. The runtime's use of Ada protected objects to enforce this serialization is outside the K model. |
| **A-05** | FP division result is finite when operands are finite | Major | Float evaluation rules, `FP_Safe_Div` correspondence (section 6, D27 Rule 5) | **External dependency.** The K `checkNarrowFloat` rule catches infinity at narrowing points but does not model subnormal operand behavior. The compiler's narrowing-point analysis guaranteeing finite results is assumed, not verified by K. |
| **B-01** | Ownership state enumeration is complete | Major | Ownership state machine (section 4.3), `OwnershipState` sort (section 3.3) | **Dischargeable via kprove.** The K definition encodes exactly five ownership states (`Null_State`, `Owned`, `Moved`, `Borrowed`, `Observed`) and defines exhaustive transition rules. `kprove` can verify *transition completeness*: every reachable ownership configuration is handled by some rule, and no stuck state arises from an unmodeled ownership state. If a sixth state were needed, the K definition would reach a stuck configuration, exposing the gap. |
| **B-02** | Channel FIFO ordering preserved by implementation | Major | Channel buffer model (section 4.4), `<buffer>` cell using K `List` | **Dischargeable via kprove.** The K model uses an explicit `List` with head-removal and tail-append, directly encoding FIFO semantics. `kprove` can verify the FIFO invariant: for all reachable configurations, the dequeue order matches the enqueue order. This discharges B-02 *within the K model* and provides a reference specification that the runtime implementation must conform to. |
| **B-03** | Task-variable map covers all shared variables | Major | Task-variable ownership checking (section 4.7), `<task-var-map>` cell (section 3.1) | **Partially dischargeable.** The K rules enforce that every global variable access by a task is registered in the `<task-var-map>`. `kprove` can verify that the data-race stuck state is unreachable for conforming programs. However, completeness of the compiler's registration of variables into the map remains an external dependency on the compiler front-end. |
| **B-04** | Not_Null_Ptr and Safe_Deref model Boolean null flag | Minor | Null dereference rules (section 4.3.8), pointer operations (section 2.2) | **Superseded in K model.** The K semantics models pointers directly as `ptrVal(Loc)` or `nullVal()` rather than using a Boolean proxy. The `deref(nullVal()) => stuck("null-dereference")` rule directly encodes the null check. B-04 is a SPARK modeling limitation that does not apply to K. |
| **C-01** | Flow analysis (Bronze gate) is sufficient for data-dependency proofs | Minor | Not directly relevant | **Not applicable.** C-01 concerns GNATprove's `--mode=flow` analysis, which is specific to the SPARK toolchain. The K semantics operates at a different abstraction level and does not model flow analysis. |
| **C-02** | Proof-only (Ghost) procedures have no runtime effect | Minor | Not directly relevant | **Not applicable.** C-02 concerns the erasure of Ghost-annotated procedures in the SPARK companion. The K semantics does not include ghost code; all K rules model runtime behavior. |
| **D-01** | Select lowering via polling is conformant | Minor | Select statement rules (section 4.5), `tryArms`/`pollDelay` rules | **Partially dischargeable.** The K `select` rules model polling semantics (retry loop with `pollDelay`), matching the compiler's lowering strategy. `kprove` can verify that the polling model satisfies the spec's determinism requirement: given identical channel states, the same arm is always chosen. Whether the polling latency is acceptable under real-time constraints remains outside the K model. |
| **D-02** | Frozen spec commit is authoritative | Minor | All clause ID references throughout this document (e.g., `SAFE@468cf72:...`) | **External dependency.** The K definition pins all clause references to commit `468cf72`. D-02 is a process-level assumption that applies equally to the K semantics, the SPARK companion, and all other artifacts. If the spec evolves, K rules must be re-derived from updated clause IDs. |

### 10.2 Summary by Disposition

**Assumptions the K semantics can help discharge:**

- **B-01** (Ownership state completeness) -- `kprove` can verify that the five-state ownership model handles all reachable transitions without stuck states, confirming enumeration completeness.
- **B-02** (Channel FIFO ordering) -- The K `List`-based buffer model directly encodes FIFO semantics, and `kprove` can verify the ordering invariant across all interleavings.

**Assumptions the K semantics can partially verify:**

- **A-03** (Static range analysis soundness) -- K can cross-check: programs accepted by the compiler should not reach narrowing stuck states in the K interpreter, providing empirical evidence (via test execution) and bounded verification (via `kprove`) of range analysis soundness.
- **B-03** (Task-variable map completeness) -- K can verify race-freedom given a complete map, but map completeness depends on the compiler.
- **D-01** (Select polling conformance) -- K can verify the determinism property of the polling model but not real-time latency bounds.

**Assumptions that are external dependencies (hardware, toolchain, or process):**

- **A-01** (64-bit hardware) -- Hardware property; K relies on it.
- **A-02** (IEEE 754 non-trapping mode) -- Hardware property; K relies on it.
- **A-04** (Channel serialization by runtime) -- Runtime implementation property; K assumes atomicity.
- **A-05** (FP division finiteness) -- Compiler analysis property; K catches infinity at narrowing but does not verify the analysis.
- **D-02** (Frozen spec commit) -- Process-level assumption; applies to all artifacts.

**Assumptions not applicable to the K semantics:**

- **B-04** (Boolean null flag model) -- SPARK modeling workaround; K models pointers directly.
- **C-01** (Flow analysis sufficiency) -- SPARK toolchain concern; not relevant to K.
- **C-02** (Ghost procedure erasure) -- SPARK toolchain concern; not relevant to K.

---

## 11. References

1. **Safe Language Specification** -- spec/02-restrictions.md (ownership model, D27 rules), spec/04-tasks-and-channels.md (concurrency model), spec/08-syntax-summary.md (BNF grammar, 148 productions).

2. **Safe AST Schema** -- compiler/ast_schema.json (90+ AST node types with clause cross-references).

3. **Safe Translation Rules** -- compiler/translation_rules.md (Safe-to-Ada/SPARK translation semantics).

4. **SPARK Companion** -- companion/spark/safe_po.ads (D27 proof obligations), companion/spark/safe_model.ads (ghost models for ranges, channels, ownership, task-variable mapping).

5. **K Framework** -- https://kframework.org. Rosu, G. and Serbanuta, T. "An Overview of the K Semantic Framework." Journal of Logic and Algebraic Programming, 2010.

6. **K Semantics for C** -- Hathhorn, C., Ellison, C., and Rosu, G. "Defining the Undefinedness of C." PLDI 2015. (Precedent for formalizing a systems language in K.)

7. **K Semantics for Java** -- Bogdanas, D. and Rosu, G. "K-Java: A Complete Semantics of Java." POPL 2015. (Precedent for formalizing a typed, object-oriented language in K.)
