# Translation Rules: Safe to Ada/SPARK

**Status: FINAL**
**Frozen commit:** `468cf72332724b04b7c193b4d2a3b02f1584125d`

This document defines the translation rules for lowering Safe AST nodes to Ada 2022 / SPARK 2022 source code. Safe source spellings are lowercase; the emitted Ada uses Ada-equivalent spellings for the same constructs and is the representation verified by GNATprove at Bronze and Silver levels.

**Clause ID format:** `SAFE@468cf72:spec/<file>#<section>.p<n>` references paragraph `<n>` of `<section>` in the given spec file at the frozen commit.

**AST node references** use PascalCase names corresponding to the node types defined in `compiler/ast_schema.json`.

---

## Table of Contents

1. [Mapping Table: Safe Construct to Ada/SPARK Emission](#1-mapping-table)
2. [Dot-to-Tick Notation](#2-dot-to-tick-notation)
3. [Type Annotations and Qualified Expressions](#3-type-annotations-and-qualified-expressions)
4. [Channel Lowering to Protected Objects](#4-channel-lowering-to-protected-objects)
5. [Select Lowering to Ada Select Patterns](#5-select-lowering)
6. [Task Emission](#6-task-emission)
7. [Ownership Emission](#7-ownership-emission)
8. [64-Bit Integer Arithmetic Emission](#8-64-bit-integer-arithmetic)
9. [Automatic Deallocation Emission](#9-automatic-deallocation)
10. [Effect Summary Generation](#10-effect-summary-generation)
11. [Package Structure Emission](#11-package-structure-emission)
12. [Discriminant-Check Emission](#12-discriminant-check-emission)
13. [Conservative Defaults for Underspecified Semantics](#13-conservative-defaults)
14. [Lowercase Source Mapping](#14-lowercase-source-mapping)
15. [End-to-End Examples](#15-end-to-end-examples)

---

## 1. Mapping Table

The following table maps each Safe construct to its Ada/SPARK emission pattern. AST node types (from `compiler/ast_schema.json`) are referenced in the Notes column.

| Safe Construct | Ada/SPARK Emission | Clause Reference | Notes |
|---|---|---|---|
| `package p is ...` | `.ads` + `.adb` pair with `pragma SPARK_Mode;` | SAFE@468cf72:spec/03-single-file-packages.md#3.1.p1 | AST: `CompilationUnit`, `PackageUnit`. Public decls to `.ads`, bodies to `.adb` |
| `public` keyword on declaration | Declaration appears in `.ads` (visible part) | SAFE@468cf72:spec/03-single-file-packages.md#3.1.p6 | No `public` = declaration in `.adb` body |
| `public type T is private record ... end record;` | Type in `.ads` visible part; full decl in `.ads` private part | SAFE@468cf72:spec/03-single-file-packages.md#3.1.p7 | AST: `RecordTypeDefinition` with `is_private=true` |
| `with p;` | `with P;` | SAFE@468cf72:spec/03-single-file-packages.md#3.1.p1 | AST: `WithClause`. Direct pass-through |
| `use type t;` | `use type T;` | SAFE@468cf72:spec/02-restrictions.md#2.1.7.p52 | AST: `UseTypeClause`. Direct pass-through |
| `x.first` (attribute) | `X'First` | SAFE@468cf72:spec/02-restrictions.md#2.4.1.p109 | AST: `SelectedComponent` with `resolved_kind=Attribute`. Dot-to-tick |
| `x.last` (attribute) | `X'Last` | SAFE@468cf72:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick for all attributes |
| `x.range` (attribute) | `X'Range` | SAFE@468cf72:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick for all attributes |
| `x.image(v)` | `X'Image(V)` | SAFE@468cf72:spec/02-restrictions.md#2.4.1.p112 | Parameterised attribute |
| `x.access` | `X'Access` | SAFE@468cf72:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick |
| `x.valid` | `X'Valid` | SAFE@468cf72:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick |
| `(expr as t)` (type annotation) | `T'(Expr)` (qualified expression) | SAFE@468cf72:spec/02-restrictions.md#2.4.2.p113 | AST: `AnnotatedExpression`. Reverse annotation to qualified expr |
| `new (expr as t)` (allocator) | `new T'(Expr)` | SAFE@468cf72:spec/02-restrictions.md#2.4.2.p116 | AST: `Allocator` with `kind=Annotated`. Combined with dot-to-tick |
| `new t` (allocator, default init) | `new T` | SAFE@468cf72:spec/02-restrictions.md#2.4.2.p116 | AST: `Allocator` with `kind=SubtypeOnly`. Direct pass-through |
| `type t is range l to h;` | `subtype T is Long_Long_Integer range L .. H;` | SAFE@468cf72:spec/08-syntax-summary.md#8.4 | AST: `SignedIntegerTypeDefinition`. Normalized to a constrained integer subtype |
| `type t is binary (8);` | `type T is mod 2 ** 8;` | SAFE@468cf72:spec/08-syntax-summary.md#8.4 | AST: `BinaryTypeDefinition`. Named fixed-width binary type |
| `type t is access t2;` | `type T is access T2;` | SAFE@468cf72:spec/08-syntax-summary.md#8.4 | AST: `AccessToObjectDefinition`. Direct pass-through |
| `subtype t_ref is not null t_ptr;` | `subtype T_Ref is not null T_Ptr;` | SAFE@468cf72:spec/02-restrictions.md#2.3.1.p95 | AST: `SubtypeDeclaration`. Direct pass-through |
| Integer arithmetic `A + B` | `Long_Long_Integer(A) + Long_Long_Integer(B)` | SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126 | AST: `Expression`. Direct 64-bit integer arithmetic |
| Narrowing: `return Expr` | `return T(Expr_64);` | SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127 | AST: `SimpleReturnStatement`. Range check at narrowing point |
| Narrowing: `X = Expr` | `X := T(Expr_64);` | SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127 | AST: `AssignmentStatement`. Range check at narrowing point |
| `task T ...` | Ada task type + single instance | SAFE@468cf72:spec/04-tasks-and-channels.md#4.1.p1 | AST: `TaskDeclaration`. See Section 6 |
| `task T ..., sends C1, receives C2` | Same Ada task type + instance; direction clauses affect legality and interface summaries only | SAFE@468cf72:spec/04-tasks-and-channels.md#4.1.p7c | Source-only constraint; no direct Ada syntax |
| `channel C : T capacity N;` | Protected object with bounded buffer | SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p12 | AST: `ChannelDeclaration`. See Section 4 |
| `send C, Expr, Ok;` | `C.Try_Send(Expr, Ok);` (procedure call) | SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p29 | AST: `SendStatement`. Non-blocking procedure |
| `receive C, Var;` | `C.Receive(Var);` (entry call) | SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p28 | AST: `ReceiveStatement`. Blocking entry call |
| `receive C, Var : T;` | `declare Var : T; begin C.Receive(Var); ... end;` | SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p28 | Lowered before AST / MIR emission to declaration + receive |
| `try_receive C, Var, Ok;` | `C.Try_Receive(Var, Ok);` (procedure call) | SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p30 | AST: `TryReceiveStatement`. Non-blocking procedure |
| `try_receive C, Var : T, Ok;` | `declare Var : T := <default>; begin C.Try_Receive(Var, Ok); ... end;` | SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p30 | Lowered before AST / MIR emission to declaration + try_receive |
| `X << Y` / `X >> Y` on `binary (N)` | `Interfaces.Shift_Left/Shift_Right (...)` | SAFE@468cf72:spec/08-syntax-summary.md#8.6 | `>>` lowers as logical zero-fill right shift |
| `select ... end select;` | Dispatcher-based loop with circular `Try_Receive` precheck | SAFE@468cf72:spec/04-tasks-and-channels.md#4.4.p39 | AST: `SelectStatement`. See Section 5 |
| `delay Expr;` | `delay Duration(Expr);` | SAFE@468cf72:spec/02-restrictions.md#2.1.8.p60 | AST: `DelayStatement`. Direct pass-through if Duration typed |
| `pragma Assert(Cond);` | `pragma Assert(Cond);` | SAFE@468cf72:spec/02-restrictions.md#2.1.10.p68 | AST: `Pragma`. Direct pass-through |
| Scope exit of owning access var | `Free(Var);` (generated Unchecked_Deallocation) | SAFE@468cf72:spec/02-restrictions.md#2.3.5.p104 | See Section 9 |
| Interleaved declaration in body | Declaration hoisted to `declare` block | SAFE@468cf72:spec/02-restrictions.md#2.9.p140 | AST: `InterleavedItem`. See Section 11 |
| Forward declaration | Subprogram spec in `.ads` | SAFE@468cf72:spec/03-single-file-packages.md#3.2.3.p11 | AST: `SubprogramDeclaration`. Body in `.adb` |
| `is separate` (subunit stub) | `is separate;` | SAFE@468cf72:spec/08-syntax-summary.md#8.9 | AST: `SubunitStub`. Direct pass-through |

### 1.1 Named Value Arguments

`ParameterAssociation.formal_name` is populated for named value-argument source forms. The resolver binds those associations to the callee declaration and rewrites arguments into positional declaration order before MIR construction, Ada emission, and proof generation. Built-in calls and generic type actuals remain positional-only.

---

## 2. Dot-to-Tick Notation

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.4.1.p109-112

**AST node:** `SelectedComponent` (with `resolved_kind` field)

Safe uses dot notation (`x.attr`) for all attribute references. Ada uses tick notation (`X'Attr`). The emitter must reverse this transformation.

### 2.1 Resolution Rule

During semantic analysis, each `SelectedComponent` node is classified per the resolution rule (SAFE@468cf72:spec/02-restrictions.md#2.4.1.p110):

| SelectedComponent resolved_kind | Emission |
|---|---|
| `RecordField` | `X.Field` (dot notation, unchanged) |
| `Attribute` | `X'Attr` (dot becomes tick) |
| `PackageMember` | `P.Name` (dot notation, unchanged) |
| `ImplicitDereference` | `X.all.Field` or `X.Field` (Ada implicit deref) |

### 2.2 Parameterised Attributes

Attributes taking parameters use function-call syntax in Safe (`t.image(42)`) and are emitted as Ada attribute calls (`T'Image(42)`).

### 2.3 Range Attribute

Safe `name.range` and `name.range(n)` emit as `name'Range` and `name'Range(N)`. These are represented by the `Range` AST node with `kind=AttributeRange`.

### 2.4 Example

```
-- Safe source:
return b(b.first);
x : integer = t.last;
s : string = v.image;

-- Emitted Ada:
return B(B'First);
X : Integer := T'Last;
S : String := V'Image;
```

### 2.5 Complete Attribute Inventory

All attributes listed in SAFE@468cf72:spec/02-restrictions.md#2.5.1.p118 are emitted with tick notation. The emitter maintains a compile-time lookup table of all 70 retained attribute names (enumerated in spec/02-restrictions.md section 2.5.1) to distinguish attribute references from record field accesses during emission. This table is generated from the spec inventory at compiler build time:

```
retained_attributes : constant array of String :=
   ("access", "address", "adjacent", "aft", "alignment", "base",
    "bit_order", "ceiling", "component_size", "compose",
    "constrained", "copy_sign", "definite", "delta", "denorm",
    "digits", "enum_rep", "enum_val", "exponent", "first",
    "first_valid", "floor", "fore", "fraction", "image", "last",
    "last_valid", "leading_part", "length", "machine",
    "machine_emax", "machine_emin", "machine_mantissa",
    "machine_overflows", "machine_radix", "machine_rounds",
    "max", "max_alignment_for_allocation",
    "max_size_in_storage_elements", "min", "mod", "model",
    "model_emin", "model_epsilon", "model_mantissa",
    "model_small", "modulus", "object_size",
    "overlaps_storage", "pos", "pred", "range", "remainder",
    "round", "rounding", "safe_first", "safe_last", "scale",
    "scaling", "size", "small", "storage_size", "succ",
    "truncation", "unbiased_rounding", "val", "valid",
    "value", "wide_image", "wide_value", "wide_wide_image",
    "wide_wide_value", "wide_wide_width", "wide_width", "width");
```

---

## 3. Type Annotations and Qualified Expressions

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.4.2.p113-116

**AST node:** `AnnotatedExpression`

### 3.1 Basic Rule

Safe `(expr as t)` emits as Ada `T'(Expr)`.

### 3.2 In Allocators

Safe `new (expr as t)` emits as Ada `new T'(Expr)`.

### 3.3 Examples

```
-- Safe source:
x = ((others = 0) as buffer_type);
p = new (42 as integer);
foo ((x as t));

-- Emitted Ada:
X := Buffer_Type'(others => 0);
P := new Integer'(42);
Foo (T'(X));
```

### 3.4 Interaction with 64-Bit Integer Arithmetic

When the expression inside a type annotation involves integer arithmetic, the
emitter performs the computation in `Long_Long_Integer`, then narrows via the
type conversion. The outer qualified expression is retained for disambiguation
only when the context requires it. In most cases, the type conversion alone is
sufficient since it performs the range check:

```
-- Safe source:
y = ((a + b) as reading);

-- Emitted Ada (standard case):
y := reading(Long_Long_Integer(a) + Long_Long_Integer(b));
```

**Decision:** The outer qualified expression `Reading'(...)` is omitted when
the context is unambiguous. The type conversion `Reading(Expr_64)` performs the
required range check. If the context is ambiguous, the qualified expression
form `Reading'(Reading(Expr_64))` is used. Since Safe has no user-defined
overloading, this ambiguity arises only with universal types.

---

## 4. Channel Lowering to Protected Objects

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p12, SAFE@468cf72:spec/07-annex-b-impl-advice.md#B.6.p16

**AST node:** `ChannelDeclaration`

Each Safe `channel` declaration is lowered to an Ada protected object implementing a bounded FIFO queue.

### 4.1 Protected Object Template

For a channel declared as:
```
channel data_ch : element_type capacity 16;
```

The emitter produces:

```ada
-- In .ads (if channel is public) or .adb (if private):
protected Data_Ch
   with Priority => <computed_ceiling>
is
   entry Send (Item : in Element_Type);
   entry Receive (Item : out Element_Type);
   procedure Try_Send (Item : in Element_Type; Success : out Boolean);
   procedure Try_Receive (Item : out Element_Type; Success : out Boolean);
private
   subtype Buffer_Index is Natural range 0 .. 15;  -- 0 .. capacity-1
   subtype Buffer_Count is Natural range 0 .. 16;  -- 0 .. capacity
   Buffer : array (Buffer_Index) of Element_Type;
   Head   : Buffer_Index := 0;
   Tail   : Buffer_Index := 0;
   Count  : Buffer_Count := 0;
end Data_Ch;
```

**Note:** `Try_Send`/`Try_Receive` use procedures, not entries, because SPARK does not permit functions with `out` parameters and entries would block.

### 4.2 Protected Body Template

```ada
protected body Data_Ch is
   entry Send (Item : in Element_Type) when Count < 16 is
   begin
      Buffer(Tail) := Item;
      Tail := Buffer_Index((Natural(Tail) + 1) mod 16);
      Count := Count + 1;
   end Send;

   entry Receive (Item : out Element_Type) when Count > 0 is
   begin
      Item := Buffer(Head);
      Head := Buffer_Index((Natural(Head) + 1) mod 16);
      Count := Count - 1;
   end Receive;

   procedure Try_Send (Item : in Element_Type; Success : out Boolean) is
   begin
      if Count < 16 then
         Buffer(Tail) := Item;
         Tail := Buffer_Index((Natural(Tail) + 1) mod 16);
         Count := Count + 1;
         Success := True;
      else
         Success := False;
      end if;
   end Try_Send;

   procedure Try_Receive (Item : out Element_Type; Success : out Boolean) is
   begin
      if Count > 0 then
         Item := Buffer(Head);
         Head := Buffer_Index((Natural(Head) + 1) mod 16);
         Count := Count - 1;
         Success := True;
      else
         Success := False;
      end if;
   end Try_Receive;
end Data_Ch;
```

### 4.3 Ceiling Priority Computation

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p21-21a

The emitter computes the ceiling priority for each channel as:

```
ceiling(Ch) = max { priority(T) | T accesses Ch directly or transitively }
```

Cross-package channel access is determined from channel-access summaries in the dependency interface (SAFE@468cf72:spec/03-single-file-packages.md#3.3.1.p33(i)).

Conservative over-approximation is permitted (SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p21a(d)). When no task accesses a channel (e.g., a public channel accessed only from client code not yet compiled), the ceiling defaults to `System.Any_Priority'Last` (see Section 12, conservative defaults).

### 4.4 Buffer Index Types

The internal buffer index types are generated as tight subtypes to satisfy Silver-level proof:

```ada
subtype Buffer_Index is Natural range 0 .. 15;  -- for capacity 16
subtype Buffer_Count is Natural range 0 .. 16;
```

This ensures that `Head`, `Tail`, and `Count` are provably in-range. The wraparound modulo step `(Natural(Tail) + 1) mod 16` is wrapped in a `Buffer_Index(...)` conversion to produce a value in the tight subtype range. GNATprove can verify this conversion is always valid since `(x + 1) mod N` is always in `0 .. N-1`.

### 4.5 Channel Send Semantics

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p27-29b

The admitted source form is the nonblocking three-argument send:

```safe
send ch, expr, success;
```

Channel element types are value-only. Access-bearing channel element types are
rejected by the frontend before emit, so admitted channel send is copy-only and
does not transfer ownership through the channel.

The emitter must:

1. Evaluate the expression exactly once before the fullness check.
2. For heap-backed channel elements, stage the copied/cloned value first and
   derive any modeled length from that staged value rather than re-rendering
   the source expression.
3. Call the emitted nonblocking channel `Try_Send` path.
4. Write the success flag with the enqueue result.

```ada
-- Emitted Ada for: send Ch, Value, Ok;
Ch.Try_Send (Value, Ok);
```

**Atomicity guarantee:** The emitted `Try_Send` call performs the fullness check
and enqueue decision inside the channel's protected operation, which is atomic
with respect to other operations on the same channel. This is the shipped
realization of SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p29b.

---

## 5. Select Lowering

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.4.p32-44

**AST nodes:** `SelectStatement`, `SelectArm`, `ChannelArm`, `DelayArm`

Safe's `select` statement multiplexes channel receive operations. The shipped lowering uses a package-scope readiness dispatcher per admitted `select` site rather than a fixed-quantum poll loop.

### 5.1 Dispatcher Pattern

```
-- Safe source:
select
   when msg : command from commands then
      handle(msg);
   or when data : integer from data_ch then
      process(data);
   or delay 5.0 then
      timeout_handler;
end select;
```

Emits as:

```ada
protected Safe_Select_Dispatcher_L23_C10 is
   procedure Reset;
   procedure Signal;
   procedure Signal_Delay
     (Event : in out Ada.Real_Time.Timing_Events.Timing_Event);
   entry Await (Timed_Out : out Boolean);
private
   Signaled : Boolean := False;
   Delay_Expired : Boolean := False;
end Safe_Select_Dispatcher_L23_C10;

Safe_Select_Dispatcher_L23_C10_Next_Arm : Positive range 1 .. 2 := 1;

Safe_Select_Dispatcher_L23_C10_Timer :
  Ada.Real_Time.Timing_Events.Timing_Event;

declare
   Select_Done : Boolean := False;
   Select_Timed_Out : Boolean := False;
   Select_Handler_Cancelled : Boolean := False;
   Select_Deadline : constant Ada.Real_Time.Time :=
      Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (5.0);
begin
   Safe_Select_Dispatcher_L23_C10.Reset;
   Ada.Real_Time.Timing_Events.Set_Handler (
      Safe_Select_Dispatcher_L23_C10_Timer,
      Select_Deadline,
      Safe_Select_Dispatcher_L23_C10.Signal_Delay'Access);

   loop
      case Safe_Select_Dispatcher_L23_C10_Next_Arm is
         when 1 =>
            -- Probe Commands, then Data_Ch.
            null;
         when 2 =>
            -- Probe Data_Ch, then Commands.
            null;
      end case;

      if not Select_Done then
         Safe_Select_Dispatcher_L23_C10.Await (Select_Timed_Out);
         if Select_Timed_Out then
            Timeout_Handler;
            Select_Done := True;
         end if;
      end if;
      exit when Select_Done;
   end loop;
end;
```

### 5.2 select without delay arm

if no delay arm is present, the emitter still performs the same circular readiness precheck starting at the persistent `Next_Arm` cursor, but the fallback wait is a blocking dispatcher `Await` call with no deadline. there is no emitted fixed sleep quantum.

### 5.3 arm rotation

arms are tested exactly once in circular order starting at the per-select `Next_Arm` cursor. the first ready arm in that circular order is selected, and `Next_Arm` advances to the successor of the winning channel arm. if the select times out or wakes without selecting an arm, `Next_Arm` stays unchanged.

### 5.4 admitted lowering boundary

the admitted dispatcher lowering in `PR11.9a`/`PR11.9b` is intentionally narrower than the full language surface:

- select channel arms must target same-unit, non-public channels
- select statements are emitted only from unit-scope statements and direct task bodies
- the dispatcher is readiness-only; payload transfer still happens through the existing `Try_Receive` path
- delay arms use one absolute deadline established at `select` entry and a package-scope timing event to wake the dispatcher when that deadline expires
- plain `select` is fair by default on this admitted subset; there is no separate priority-ordered form

### 5.5 ownership in select arms

when the channel element type is an owning access type, the `try_receive` in the select arm performs ownership transfer. the received variable is scoped to the arm's declare block, so deallocation occurs at the end of the arm's statements.

---

## 6. task emission

**clause:** safe@468cf72:spec/04-tasks-and-channels.md#4.1

**ast node:** `taskdeclaration`

### 6.1 task type and instance

each safe `task` declaration becomes an ada task type with a single instance:

```
-- Safe source:
task producer with priority = 10 is
   ...
begin
   loop
      ...
   end loop;
end producer;
```

emits as:

```ada
-- In .adb:
task type producer_task_type
   with priority => 10
is
end producer_task_type;

producer : producer_task_type;

task body producer_task_type is
   -- declarative_part from Safe task
begin
   loop
      ...
   end loop;
end producer_task_type;
```

### 6.2 Task Naming Convention

The generated task type name is `<SafeName>_Task_Type`. The single instance retains the Safe task name.

**Collision avoidance:** Since Safe prohibits overloading (SAFE@468cf72:spec/02-restrictions.md#2.10.p141), there can be at most one user-declared entity with any given name in a declarative region. The suffix `_Task_Type` cannot collide with the instance name (which is the unadorned Safe task name), and if the user declares an entity named `Producer_Task_Type`, it would conflict with the task name `Producer` only if both are in the same package -- but Safe tasks are package-level items and cannot share a name with another package-level item. If an implementation detects a rare collision, it appends a numeric suffix (e.g., `Producer_Task_Type_1`).

### 6.3 Priority Aspect

The `priority` aspect is emitted directly on the task type declaration. If no
priority is specified in Safe source, the implementation's default priority is
used (SAFE@468cf72:spec/04-tasks-and-channels.md#4.1.p9), which is
`System.Default_Priority` in Ada.

### 6.4 Task Direction Clauses

Task `sends` / `receives` clauses are source-level legality checks and do not
introduce any additional Ada syntax. The emitter therefore produces the same
task type, task body, and instance declarations regardless of whether the Safe
source declared channel-direction contracts. The contracts do affect the
generated interface summaries described in Section 10.5.

### 6.5 Non-Termination

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.6.p53

The non-termination legality rule is enforced at compile time. The emitted task body preserves the unconditional outer loop from the Safe source. No additional runtime enforcement is needed.

### 6.6 Global Aspects on Task Bodies

The emitter generates `Global` aspects on task bodies referencing only owned variables and channel operations:

```ada
task body Producer_Task_Type
   with Global => (In_Out => (Raw_Data, Sample_Counter))
is
   ...
```

### 6.7 Elaboration Policy

**Clause:** SAFE@468cf72:spec/04-tasks-and-channels.md#4.7.p56, SAFE@468cf72:spec/07-annex-b-impl-advice.md#B.6.p15

The emitter produces a GNAT configuration file containing:

```ada
pragma Partition_Elaboration_Policy(Sequential);
pragma Profile(Jorvik);
```

This ensures all package elaboration completes before any task activates (SAFE@468cf72:spec/04-tasks-and-channels.md#4.7.p56).

---

## 7. Ownership Emission

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.3

**AST nodes:** `AssignmentStatement` (with `ownership_action` field), `ObjectDeclaration`

### 7.1 Ownership Mapping Table

| Safe Ownership Operation | Emitted Ada Pattern | Clause |
|---|---|---|
| Move: `Y = X;` (access assignment) | `Y := X; X := null;` | SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96 |
| Borrow: `Y : access T = X;` | `declare Y : access T := X; begin ... end;` | SAFE@468cf72:spec/02-restrictions.md#2.3.3.p98 |
| Observe: `Y : access constant T = X.Access;` | `declare Y : access constant T := X'Access; begin ... end;` | SAFE@468cf72:spec/02-restrictions.md#2.3.4.p101 |
| Parameter borrow: `P(X)` where param is `in out` access | Direct pass-through; SPARK ownership checks apply | SAFE@468cf72:spec/02-restrictions.md#2.3.3.p98(b) |
| Parameter observe: `P(X)` where param is `in` access | Direct pass-through; SPARK ownership checks apply | SAFE@468cf72:spec/02-restrictions.md#2.3.4.p101(b) |
| Scope-exit deallocation | `Free(Var);` before scope end | SAFE@468cf72:spec/02-restrictions.md#2.3.5.p104 |

### 7.2 Move Emission

For every assignment of an owning access value, the emitter inserts a null-assignment of the source:

```ada
-- Safe source:
Y = X;

-- Emitted Ada:
Y := X;
X := null;  -- move: source becomes null
```

for function returns, the move is implicit (the local goes out of scope).

### 7.3 null-before-move verification

**clause:** safe@468cf72:spec/02-restrictions.md#2.3.2.p97a

the compiler verifies at compile time that the target of a move is provably null. this is a legality rule enforced before emission; no runtime code is needed.

### 7.4 spark annotations for ownership

the emitted ada relies on spark 2022's built-in ownership model (SPARK RM 3.10). The emitter does not generate additional ownership annotations beyond what SPARK infers from the access type declarations. GNATprove's ownership checking on the emitted ada is sufficient because:

- safe's ownership model (SAFE@468cf72:spec/02-restrictions.md#2.3) is a subset of SPARK 2022's ownership model (spark rm 3.10).
- the emitted null-assignment after moves is exactly what spark expects.
- the `not null` subtype declarations provide the non-null guarantees spark uses for dereference safety.

no additional `pragma annotate` directives are required.

---

## 8. 64-bit integer arithmetic

**clause:** safe@468cf72:spec/02-restrictions.md#2.8.1.p126-130

**ast node:** `expression`

### 8.1 Integer Model

The emitted Ada uses `Long_Long_Integer` as the target representation for Safe
`integer`. Constrained Safe integer spellings become Ada subtypes of
`Long_Long_Integer`.

### 8.2 Direct 64-Bit Evaluation

Every emitted integer subexpression is evaluated directly in
`Long_Long_Integer`. There is no generated `safe_runtime.ads` support package
and no `Safe_Runtime.Wide_Integer` lifting stage:

```
-- Safe source:
return (a + b) / 2;
-- where A, B : Reading (range 0 .. 4095)

-- Emitted Ada:
return Reading(
   (Long_Long_Integer(A) + Long_Long_Integer(B)) / 2
);
```

### 8.3 Narrowing Points

Narrowing (conversion back to the target type) occurs at exactly five points (SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127):

| Narrowing Point | Emission Pattern | AST Node |
|---|---|---|
| Assignment: `X = Expr;` | `X := Target_Type(Wide_Expr);` | `AssignmentStatement` |
| Parameter passing | `Call(Target_Type(Wide_Expr));` | `ProcedureCallStatement` / `FunctionCall` |
| Function return | `return Target_Type(Wide_Expr);` | `SimpleReturnStatement` |
| Type conversion | `Target_Type(Wide_Expr)` | `TypeConversion` |
| Type annotation | `Target_Type(Wide_Expr)` | `AnnotatedExpression` |

### 8.4 Non-Integer Expressions

This rule applies only to integer types. Floating-point and Boolean expressions
pass through without integer-specific rewriting.

**Binary types:** `binary (8|16|32|64)` uses fixed-width wrapping semantics.
These expressions are not rewritten through the signed `integer` path. The
emitter lowers them through Ada's `Interfaces.Unsigned_*` types and
`Interfaces.Shift_Left` / `Interfaces.Shift_Right`, with `>>` emitted as a
logical zero-fill right shift.

### 8.5 Static Expressions

Static expressions (compile-time evaluable) may be evaluated by the compiler
rather than emitted as explicit `Long_Long_Integer` code. The result must fit
in the target type.

### 8.6 Intermediate Overflow Rejection

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.8.1.p129

If the compiler's interval analysis determines that an integer subexpression
could exceed signed 64-bit range, the program is rejected at compile time.

### 8.7 Example: Full Emission

```
-- Safe source:
public subtype reading is integer (0 to 4095);

public function average (a, b : reading) returns reading
   return (a + b) / 2;

-- Emitted Ada (in .adb):
subtype Reading is Long_Long_Integer range 0 .. 4095;

function Average (A, B : Reading) return Reading is
begin
   return Reading(
      (Long_Long_Integer(A) + Long_Long_Integer(B)) / 2
   );
   -- GNATprove: Long_Long_Integer range [0 .. 8190] / 2 = [0 .. 4095]
   -- Narrowing to Reading (0 .. 4095): provably safe
end Average;
```

---

## 9. Automatic Deallocation

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.3.5.p103-106

### 9.1 Unchecked_Deallocation Instantiation

For each pool-specific access type (both owning and named access-to-constant), the emitter generates an `Unchecked_Deallocation` instantiation:

```ada
-- For: type Node_Ptr is access Node;
procedure Free_Node_Ptr is new Ada.Unchecked_Deallocation(Node, Node_Ptr);
```

**Note:** The exclusion of generics (SAFE@468cf72:spec/02-restrictions.md#2.1.11.p69) applies to Safe source, not emitted Ada. The emitter freely uses `Ada.Unchecked_Deallocation`.

### 9.2 Scope Exit Points

Deallocation calls are emitted at every scope exit point (SAFE@468cf72:spec/02-restrictions.md#2.3.5.p104):

| Exit Point | Emission |
|---|---|
| Normal scope end (`end` of block/subprogram) | `if Var /= null then Free(Var); end if;` before `end` |
| Early `return` | Deallocation before `return` |
| `exit` statement leaving owning scope | Deallocation before `exit` |
| `goto` statement leaving owning scope | Deallocation before `goto` |

### 9.3 Reverse Declaration Order

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.3.5.p105

When multiple owning access objects exit scope simultaneously, they are deallocated in reverse declaration order:

```ada
-- Safe source:
a : node_ptr = new (... as node);
b : node_ptr = new (... as node);
-- ... end of scope

-- Emitted Ada (before end):
if b /= null then free_node_ptr(b); end if;
if a /= null then free_node_ptr(a); end if;
```

### 9.4 General Access Types

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.3.5.p106

General access types (`access all T`) are NOT deallocated, as they may designate stack-allocated objects.

### 9.5 Conditional Deallocation

The null check (`if Var /= null then`) is required because ownership moves may have set the variable to null during the scope's lifetime. Only non-null values are deallocated.

### 9.6 Named Access-to-Constant

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.3.5.p104a

Named access-to-constant types (`type C_Ptr is access constant T;`) are pool-specific and must be deallocated at scope exit, just like owning access-to-variable types.

### 9.7 Deallocation Strategy: Duplicated at Each Exit Point

Deallocation calls are duplicated at each scope exit point (before each `return`, `exit`, or `goto` that leaves the owning scope, and before the normal `end`). This approach is chosen over a cleanup block because:

1. **Transparency:** Each exit point's deallocation is visible and verifiable by GNATprove independently.
2. **No hidden control flow:** A cleanup block would require restructuring the control flow to funnel all exits through a single cleanup path, potentially introducing additional variables and branches.
3. **Code size:** The duplication is bounded by the number of exit points times the number of owning access variables in scope, which is typically small.
4. **Verification:** GNATprove can verify each deallocation path independently, which is simpler than verifying a shared cleanup path with merged ownership states.

### 9.8 Example: Multiple Exit Points

```
-- Safe source:
public procedure process (flag : boolean) is
begin
   n : node_ptr = new ((value = 0, next = null) as node);
   if flag then
      return;       -- early exit: N must be freed
   end if;
   -- ... normal processing ...
end process;        -- normal exit: N must be freed

-- Emitted Ada:
procedure Process (Flag : Boolean) is
   N : Node_Ptr := new Node'(Value => 0, Next => null);
begin
   if Flag then
      if N /= null then Free_Node_Ptr(N); end if;
      return;
   end if;
   -- ... normal processing ...
   if N /= null then Free_Node_Ptr(N); end if;
end Process;
```

---

## 10. Effect Summary Generation

**Clause:** SAFE@468cf72:spec/05-assurance.md#5.2

### 10.1 Global Aspects

For each subprogram, the emitter generates a `Global` aspect listing the package-level variables read and written:

```ada
function Average (A, B : Reading) return Reading
   with Global => null;  -- no package-level state

procedure Initialize
   with Global => (In_Out => (Cal_Table, Initialized));
```

**algorithm (informative):** safe@468cf72:spec/05-assurance.md#5.2.2.p6

1. during the single-pass compilation, accumulate a read-set and write-set per subprogram.
2. for each package-level variable reference, add to the appropriate set.
3. for each called subprogram, merge callee's sets into caller's sets.
4. for mutual recursion, compute fixed point.

### 10.2 depends aspects

for each subprogram, the emitter generates a `depends` aspect:

```ada
function average (a, b : reading) return reading
   with depends => (average'Result => (A, B));

procedure Update (D : Units.Metres; T : Units.Seconds; H : Heading)
   with Depends => (Current_Speed => (D, T),
                    Current_Heading => H);
```

**Over-approximation is acceptable:** SAFE@468cf72:spec/05-assurance.md#5.2.3.p10

### 10.3 Initializes Aspects

For each package, the emitter generates an `Initializes` aspect listing all package-level variables with initializers:

```ada
package Sensors
   with Initializes => (Cal_Table, Initialized)
is
   ...
```

**Clause:** SAFE@468cf72:spec/05-assurance.md#5.2.4.p11

### 10.4 SPARK_Mode

Every emitted unit includes:

```ada
pragma SPARK_Mode;
```

### 10.5 Channel-Access Summaries

For cross-package ceiling priority computation, the dependency interface must include channel-access summaries (SAFE@468cf72:spec/03-single-file-packages.md#3.3.1.p33(i)). These are computed during the same single-pass analysis as Global/Depends.

The retained `safei-v1` shape carries three channel-summary views per exported
subprogram:

- `channels`: the conservative transitive union of all reachable channel uses
- `sends`: the conservative transitive subset used by `send`
- `receives`: the conservative transitive subset used by `receive`,
  `try_receive`, and `select` channel arms

Legacy dependency interfaces may provide only `channels`. In that case the
imported summary is treated as directionally ambiguous until the provider
interface is regenerated.

### 10.6 Constant_After_Elaboration

The emitter generates `Constant_After_Elaboration` on package-level variables that satisfy both conditions:

1. The variable has an initializer at the point of declaration.
2. No task body in the same package writes to the variable (determined from the task-variable ownership analysis).

This aspect helps GNATprove verify that variables read by tasks are stable after elaboration:

```ada
Threshold : Sensors.Reading := 3000
   with Constant_After_Elaboration;
-- Only read by Evaluator task, never written by any task
```

Variables that ARE written by a task body do not receive this aspect.

---

## 11. Package Structure Emission

**Clause:** SAFE@468cf72:spec/03-single-file-packages.md#3.1

**AST nodes:** `CompilationUnit`, `PackageUnit`, `PackageItem`

### 11.1 .ads / .adb Split

The emitter produces two files from each Safe compilation unit:

**`.ads` (specification):**
- `pragma SPARK_Mode;`
- `with` clauses (pass-through from `ContextClause`)
- Package declaration with `Initializes` aspect
- Public type declarations, subtype declarations, number declarations
- Public subprogram specifications with `Global` and `Depends` aspects
- Public channel declarations (as protected object specs)
- Public object declarations
- `private` section containing:
  - Opaque type full definitions (for `RecordTypeDefinition` with `is_private=true`)
  - Private type/subtype/object declarations needed by public subprograms

**`.adb` (body):**
- `pragma SPARK_Mode;`
- no numeric support package; integer emission uses `Long_Long_Integer` directly
- Package body
- Subprogram bodies
- Task type declarations and bodies
- Channel (protected object) bodies
- Private subprogram bodies
- Unchecked_Deallocation instantiations
- Deallocation procedure declarations

### 11.2 Interleaved Declaration Handling

**Clause:** SAFE@468cf72:spec/02-restrictions.md#2.9.p140

**AST node:** `InterleavedItem`

Safe allows interleaved declarations and statements after `begin`. Ada requires all declarations before `begin`. The emitter restructures subprogram bodies using nested `declare` blocks:

```
-- Safe source:
public procedure Example is
begin
   X : Integer = 0;
   Do_Something(X);
   Y : Integer = X + 1;
   Do_More(Y);
end Example;

-- Emitted Ada:
procedure Example is
begin
   declare
      X : Integer := 0;
   begin
      Do_Something(X);
      declare
         Y : Integer := X + 1;
      begin
         Do_More(Y);
      end;
   end;
end Example;
```

**decision: declare-block approach.** the nested-declare-block approach is chosen over hoisting declarations to the subprogram's declarative part because:

1. **Scope fidelity:** Safe's "visible from declaration to end of scope" semantics are faithfully preserved. variables are not visible before their declaration point.
2. **initialization safety:** variables are initialized at their declaration point, avoiding the need to track uninitialized variables.
3. **deallocation correctness:** owning access variables declared in interleaved positions are automatically scoped correctly for deallocation at scope exit.
4. **gnatprove compatibility:** gnatprove handles nested declare blocks correctly for flow analysis.

### 11.3 opaque type emission

**clause:** safe@468cf72:spec/03-single-file-packages.md#3.2.6.p21-24

**ast node:** `recordtypedefinition` with `is_private=true`

```
-- Safe source:
public type buffer is private record
   data   : array (buffer_index) of character;
   length : buffer_size;
end record;

-- Emitted .ads (visible part):
type buffer is private;

-- Emitted .ads (private section):
type buffer is record
   data   : array (buffer_index) of character;
   length : buffer_size;
end record;
```

---

## 12. discriminant-check emission

**clause:** safe@468cf72:spec/02-restrictions.md#2.8.6.p139f, safe@468cf72:spec/02-restrictions.md#2.12.p148

**ast nodes:** `selectedcomponent` (with `resolved_kind=variantfield`), `assignmentstatement` (target is discriminated record)

### 12.1 emission rule

before every access to a variant field of a discriminated record, the emitter inserts a ghost `check_discriminant` call asserting that the record's discriminant matches the expected variant:

```
-- Safe source:
R : Parse_Result = Parse (Input);
if R.OK then
   Process (R.Value);
end if;

-- Emitted Ada:
R : Parse_Result := Parse (Input);
if R.OK then
   Check_Discriminant (R.OK, True);   -- ghost assertion
   Process (R.Value);
end if;
```

GNATprove proves the ghost assertion from the conditional branch. No runtime code is generated (the call is `Ghost`).

### 12.2 Mutation Invalidation

The emitter tracks discriminant facts per-variable. A fact established by a conditional branch is invalidated when the discriminated object is:

   (a) Assigned to (`R := New_Value;`).

   (b) Passed as an `out` or `in out` parameter.

After invalidation, the emitter requires a new conditional guard before inserting any further variant-field access. If no guard is present, the program is rejected at compile time (the `Check_Discriminant` precondition would be unprovable).

### 12.3 Precondition-Established Access

When a subprogram has a precondition establishing the discriminant (e.g., `Pre => R.OK`), the emitter trusts the precondition and inserts `Check_Discriminant` at the access point. GNATprove proves it from the precondition without a branch:

```
-- Safe source:
function unwrap (r : parse_result) return value_type is
begin
   pragma assert (r.ok);  -- or established by precondition
   return r.value;
end unwrap;

-- Emitted Ada:
function unwrap (r : parse_result) return value_type
  with pre => r.ok
is
begin
   check_discriminant (r.ok, true);
   return r.value;
end unwrap;
```

### 12.4 mapping table entry

| safe construct | ada/spark emission | clause reference | notes |
|---|---|---|---|
| variant field access `r.value` | `check_discriminant(r.ok, true); r.value` | safe@468cf72:spec/02-restrictions.md#2.12.p148 | ghost call before every variant-field access |

---

## 13. conservative defaults for underspecified semantics

the following table lists semantics that are underspecified or implementation-defined in the safe spec, along with the conservative default the emitter adopts and the rationale.

| area | underspecified aspect | conservative default | rationale | clause reference |
|---|---|---|---|---|
| task default priority | priority when no `priority` aspect specified | `System.Default_Priority` (Ada default) | matches Ada semantics; no surprising behavior | SAFE@468cf72:spec/04-tasks-and-channels.md#4.1.p9 |
| task activation order | order among tasks starting execution | undefined; rely on ada runtime scheduling | no way to control this portably; spec allows implementation-defined | safe@468cf72:spec/04-tasks-and-channels.md#4.7.p58 |
| channel allocation strategy | static vs. heap-allocated buffer | static array in protected object (deterministic, no allocation failure) | avoids heap allocation; bounded memory; provable | SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p18 |
| channel ceiling priority (no task accesses) | ceiling when no task references channel | `system.any_priority'Last` (safe upper bound) | Prevents priority inversion for any future accessor | SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p21 |
| Select wake mechanism | How blocked `select` resumes after no arm is initially ready | Package-scope dispatcher latch signaled by successful sends and awaited by the select site | Preserves fair circular precheck semantics without polling or a fixed sleep quantum | SAFE@468cf72:spec/04-tasks-and-channels.md#4.4.p39 |
| Select timing mechanism | How to measure delay arm expiry | `Safe_Runtime.Elapsed_Since` using monotonic Duration tracking | Ada.Real_Time is excluded from Safe source but the emitter can use it internally; Duration-based fallback available | SAFE@468cf72:spec/02-restrictions.md#2.1.8.p60 |
| Depends over-approximation | Granularity of data-flow tracking | Include all potentially-contributing inputs (superset); refine later | Sound for Bronze verification; spec permits over-approximation | SAFE@468cf72:spec/05-assurance.md#5.2.3.p10 |
| Global over-approximation | Granularity of variable tracking | Include all package-level vars referenced in any code path (superset) | Sound for Bronze verification; spec permits over-approximation | SAFE@468cf72:spec/05-assurance.md#5.2.2.p6 |
| Equal-priority task scheduling | Scheduling among same-priority tasks | Implementation-defined by Ada runtime; emit no additional control | Spec explicitly allows this | SAFE@468cf72:spec/04-tasks-and-channels.md#4.1.p11 |
| Package init order (no dependency) | Order among unrelated packages | Alphabetical by package name (deterministic tie-breaking) | Ensures byte-identical emission across runs | SAFE@468cf72:spec/03-single-file-packages.md#3.4.2.p45 |
| Floating-point rounding mode | IEEE 754 rounding mode | Default rounding (round-to-nearest-even); emit no explicit mode change | Standard IEEE 754 default | SAFE@468cf72:spec/06-conformance.md#6.7.p22(i) |
| Runtime abort handler | Behaviour on Assert failure or allocation failure | Call `GNAT.OS_Lib.OS_Exit(1)` with source-location diagnostic to stderr | Deterministic, observable failure behavior | SAFE@468cf72:spec/06-conformance.md#6.7.p22(g) |
| Deallocation order at scope exit | When multiple owners exit simultaneously | Reverse declaration order | Spec mandates this | SAFE@468cf72:spec/02-restrictions.md#2.3.5.p105 |
| Anonymous access reassignment | Whether anonymous access vars can be reassigned after init | Rejected at compile time (initialisation-only restriction) | Spec mandates this | SAFE@468cf72:spec/02-restrictions.md#2.3.3.p100a |
| Emitted integer base type | Name of the 64-bit integer type in emitted Ada | `Long_Long_Integer` | Matches the PR11.8 single-`integer` model | SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126 |
| Constant_After_Elaboration | Whether to emit this GNATprove aspect | Emit for all package-level variables not written by any task body | Conservative: helps GNATprove verify task-safe reads | SAFE@468cf72:spec/05-assurance.md#5.2.4.p11 |
| Tasking profile | Which Ada tasking profile to use | `pragma Profile(Jorvik);` | Provides static task/protected object model compatible with Safe's restrictions | SAFE@468cf72:spec/04-tasks-and-channels.md#4.7.p59 |
| elaboration policy | partition elaboration policy | `pragma partition_elaboration_policy(sequential);` | ensures elaboration before task activation | SAFE@468cf72:spec/04-tasks-and-channels.md#4.7.p59 |
| identifier collision avoidance | when generated names might conflict with user identifiers | prefix generated internal names with `safe_` (e.g., `safe_select_done`) | avoid collision with user identifiers while maintaining readability | SAFE@468cf72:spec/08-syntax-summary.md#8.15 |
| binary arithmetic lifting | whether `binary (8|16|32|64)` is lifted through signed integer machinery | not lifted; binary arithmetic passes through as fixed-width `Interfaces.Unsigned_*` operations | wrapping and logical-shift semantics would be changed by signed lifting | SAFE@468cf72:spec/08-syntax-summary.md#8.4 |

---

## 14. Lowercase Source Mapping

**Clause:** SAFE@468cf72:spec/08-syntax-summary.md#8.15

### 14.1 Safe-Only Reserved Words

Safe introduces reserved words not reserved in Ada: `public`, `channel`,
`send`, `receive`, `try_send`, `try_receive`, `capacity`, and `from`. These do
not appear directly in emitted Ada; they are consumed by the compiler. The
legacy `try_send` spelling remains reserved only so the frontend can issue a
targeted migration diagnostic.

### 14.2 Lowercase Source Rule

All Safe source spellings are lowercase: identifiers, reserved words,
predefined names, admitted attribute selectors, and admitted aspect / pragma
names. The emitter maps those lowercase source spellings to Ada-equivalent
identifiers and attributes during emission.

### 14.3 Safe-to-Ada Spelling Map

| Safe source spelling | Emitted Ada spelling | Kind |
|---|---|---|
| `integer` | `Long_Long_Integer` | predefined type |
| `boolean` | `Boolean` | predefined type |
| `character` | `Character` | predefined type |
| `string` | `String` | predefined type |
| `float` | `Float` | predefined type |
| `long_float` | `Long_Float` | predefined type |
| `duration` | `Duration` | predefined type |
| `true` | `True` | boolean literal |
| `false` | `False` | boolean literal |
| `.first` | `'First` | attribute selector |
| `.last` | `'Last` | attribute selector |
| `.range` | `'Range` | attribute selector |
| `.image` | `'Image` | attribute selector |
| `.access` | `'Access` | attribute selector |
| `.valid` | `'Valid` | attribute selector |
| `priority` | `Priority` | task aspect name |

### 14.4 Mapping for Generated Entities

| Safe Concept | Generated Ada Identifier | Convention | AST Node |
|---|---|---|---|
| channel `ch` | protected object `ch` | same name | `ChannelDeclaration` |
| task `t` | task type `t_task_type`, instance `t` | suffix `_task_type` | `TaskDeclaration` |
| channel send procedure | `ch.try_send` | fixed name | `SendStatement` |
| channel receive entry | `ch.receive` | fixed name | `ReceiveStatement` |
| channel try_receive procedure | `ch.try_receive` | fixed name | `TryReceiveStatement` |
| wide integer type | `safe_runtime.wide_integer` | in support package | `Expression` nodes |
| deallocation procedure | `free_<typename>` | prefix `free_` | generated for each access type |
| select loop flag | `safe_select_done` | prefix `safe_` | generated for `SelectStatement` |
| select deadline | `safe_select_deadline` | prefix `safe_` | generated for `DelayArm` |
| buffer index subtype | `buffer_index` | local to protected object | generated for `ChannelDeclaration` |
| buffer count subtype | `buffer_count` | local to protected object | generated for `ChannelDeclaration` |

### 14.5 Deterministic Emission

**Clause:** SAFE@468cf72:spec/07-annex-b-impl-advice.md#B.5.p12

The emitter must produce byte-identical output for the same Safe source
compiled with the same compiler version. All ordering decisions (declaration
order, aspect order, import order) must be deterministic.

---

## 15. End-to-End Examples

### 15.1 Example A: Sensor Averaging with 64-Bit Integer Arithmetic (D27 Rule 1)

This example demonstrates PR11.8 integer emission for a simple averaging computation.

#### Safe Source (`averaging.safe`)

```
package averaging

   public subtype reading is integer (0 to 4095);

   public function average (a, b : reading) returns reading

      return (a + b) / 2;
      -- D27 Rule 1: max (4095+4095)/2 = 4095
      -- D27 Rule 3(b): literal 2 is static nonzero

   public function weighted_avg (a, b : reading; w : reading) returns reading

      return ((a * 3) + (b * 1)) / 4;
      -- D27 Rule 1: max (4095*3 + 4095*1)/4 = 4095
      -- D27 Rule 3(b): literal 4 is static nonzero
```

#### Emitted `averaging.ads`

```ada
pragma SPARK_Mode;

package Averaging
   with Initializes => null
is
   type Reading is range 0 .. 4095;

   function Average (A, B : Reading) return Reading
      with Global => null,
           Depends => (Average'Result => (A, B));

   function Weighted_Avg (A, B : Reading; W : Reading) return Reading
      with Global => null,
           Depends => (Weighted_Avg'Result => (A, B));
end Averaging;
```

#### Emitted `averaging.adb`

```ada
pragma SPARK_Mode;

package body Averaging is

   function Average (A, B : Reading) return Reading is
   begin
      return Reading(
         (Long_Long_Integer(A) + Long_Long_Integer(B)) / 2
      );
      -- GNATprove: Long_Long_Integer range [0 .. 8190] / 2 = [0 .. 4095]
      -- Narrowing to Reading (0 .. 4095): provably safe
   end Average;

   function Weighted_Avg (A, B : Reading; W : Reading) return Reading is
   begin
      return Reading(
         (Long_Long_Integer(A) * 3 +
          Long_Long_Integer(B) * 1) / 4
      );
      -- GNATprove: Long_Long_Integer range [0 .. 16380] / 4 = [0 .. 4095]
      -- Narrowing to Reading (0 .. 4095): provably safe
   end Weighted_Avg;

end Averaging;
```

---

### 15.2 Example B: Producer-Consumer Channel Program (Sections 4.2-4.3)

This example demonstrates channel lowering, task emission, and select lowering.

#### safe source (`pipeline.safe`)

```
package pipeline

   public subtype measurement is integer (0 to 65535);

   channel raw_data : measurement capacity 16;
   public channel processed : measurement capacity 8;

   task producer with priority = 10

      loop
         sample : measurement = read_sensor;
         send raw_data, sample, ok;
         delay 0.01;

   task consumer with priority = 5

      loop
         m : measurement;
         receive raw_data, m;
         result : measurement = measurement ((m + 1) / 2);
         send processed, result, ok;

   function read_sensor returns measurement is separate;
```

#### Emitted `pipeline.ads`

```ada
pragma SPARK_Mode;

package Pipeline
   with Initializes => null
is
   type Measurement is range 0 .. 65535;

   function Read_Sensor return Measurement is separate
      with Global => null;

   -- Public channel as protected object spec
   protected Processed
      with Priority => 5  -- ceiling = max priority of tasks accessing it
   is
      entry Send (Item : in Measurement);
      entry Receive (Item : out Measurement);
      procedure Try_Send (Item : in Measurement; Success : out Boolean);
      procedure Try_Receive (Item : out Measurement; Success : out Boolean);
   private
      subtype Buffer_Index is Natural range 0 .. 7;
      subtype Buffer_Count is Natural range 0 .. 8;
      Buffer : array (Buffer_Index) of Measurement;
      Head   : Buffer_Index := 0;
      Tail   : Buffer_Index := 0;
      Count  : Buffer_Count := 0;
   end Processed;

end Pipeline;
```

#### Emitted `pipeline.adb`

```ada
pragma SPARK_Mode;

package body Pipeline is

   -- Private channel
   protected Raw_Data
      with Priority => 10  -- ceiling = max(Producer=10, Consumer=5)
   is
      entry Send (Item : in Measurement);
      entry Receive (Item : out Measurement);
      procedure Try_Send (Item : in Measurement; Success : out Boolean);
      procedure Try_Receive (Item : out Measurement; Success : out Boolean);
   private
      subtype Buffer_Index is Natural range 0 .. 15;
      subtype Buffer_Count is Natural range 0 .. 16;
      Buffer : array (Buffer_Index) of Measurement;
      Head   : Buffer_Index := 0;
      Tail   : Buffer_Index := 0;
      Count  : Buffer_Count := 0;
   end Raw_Data;

   -- Task type and instance: Producer
   task type Producer_Task_Type
      with Priority => 10
   is
   end Producer_Task_Type;

   Producer : Producer_Task_Type;

   task body Producer_Task_Type
      with Global => (In_Out => Raw_Data)
   is
   begin
      loop
         declare
            Sample : Measurement := Read_Sensor;
         begin
            Raw_Data.Send(Sample);
            delay 0.01;
         end;
      end loop;
   end Producer_Task_Type;

   -- Task type and instance: Consumer
   task type Consumer_Task_Type
      with Priority => 5
   is
   end Consumer_Task_Type;

   Consumer : Consumer_Task_Type;

   task body Consumer_Task_Type
      with Global => (In_Out => (Raw_Data, Processed))
   is
   begin
      loop
         declare
            M : Measurement;
         begin
            Raw_Data.Receive(M);
            declare
               Result : Measurement := Measurement(
                  (Long_Long_Integer(M) + 1) / 2
               );
            begin
               Processed.Send(Result);
            end;
         end;
      end loop;
   end Consumer_Task_Type;

   -- Protected body: Raw_Data
   protected body Raw_Data is
      entry Send (Item : in Measurement) when Count < 16 is
      begin
         Buffer(Tail) := Item;
         Tail := Buffer_Index((Natural(Tail) + 1) mod 16);
         Count := Count + 1;
      end Send;

      entry Receive (Item : out Measurement) when Count > 0 is
      begin
         Item := Buffer(Head);
         Head := Buffer_Index((Natural(Head) + 1) mod 16);
         Count := Count - 1;
      end Receive;

      procedure Try_Send (Item : in Measurement; Success : out Boolean) is
      begin
         if Count < 16 then
            Buffer(Tail) := Item;
            Tail := Buffer_Index((Natural(Tail) + 1) mod 16);
            Count := Count + 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Send;

      procedure Try_Receive (Item : out Measurement; Success : out Boolean) is
      begin
         if Count > 0 then
            Item := Buffer(Head);
            Head := Buffer_Index((Natural(Head) + 1) mod 16);
            Count := Count - 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Receive;
   end Raw_Data;

   -- Protected body: Processed (same pattern, capacity 8)
   protected body Processed is
      entry Send (Item : in Measurement) when Count < 8 is
      begin
         Buffer(Tail) := Item;
         Tail := Buffer_Index((Natural(Tail) + 1) mod 8);
         Count := Count + 1;
      end Send;

      entry Receive (Item : out Measurement) when Count > 0 is
      begin
         Item := Buffer(Head);
         Head := Buffer_Index((Natural(Head) + 1) mod 8);
         Count := Count - 1;
      end Receive;

      procedure Try_Send (Item : in Measurement; Success : out Boolean) is
      begin
         if Count < 8 then
            Buffer(Tail) := Item;
            Tail := Buffer_Index((Natural(Tail) + 1) mod 8);
            Count := Count + 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Send;

      procedure Try_Receive (Item : out Measurement; Success : out Boolean) is
      begin
         if Count > 0 then
            Item := Buffer(Head);
            Head := Buffer_Index((Natural(Head) + 1) mod 8);
            Count := Count - 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Receive;
   end Processed;

end Pipeline;
```

---

### 15.3 Example C: Ownership Transfer (Section 2.3)

This example demonstrates move semantics, automatic deallocation, and borrow/observe emission.

#### Safe Source (`ownership.safe`)

```
package ownership

   public type node;
   public type node_ptr is access node;
   public subtype node_ref is not null node_ptr;

   public type node is record
      value : integer;
      next  : node_ptr;

   -- Move: caller's pointer is nulled after call
   public function make_node (v : integer) returns node_ptr

      return new ((v, null) as node);

   -- Borrow: mutable temporary access via in-out parameter
   public procedure set_value (n : in out node_ref; v : integer)

      n.value = v;

   -- Observe: read-only access
   public function get_value (n : node_ref) returns integer

      return n.value;

   -- Demonstrates automatic deallocation at scope exit
   public procedure demo

      a : node_ptr = make_node(10);
      b : node_ptr = make_node(20);

      -- Move: A transferred to C, A becomes null
      c : node_ptr = a;

      -- Use C (which now owns the node)
      pragma assert(c != null);
      ref : node_ref = node_ref(c);
      set_value(ref, 42);

      -- End of scope: C and B deallocated in reverse order
```

#### Emitted `ownership.ads`

```ada
pragma SPARK_Mode;

package Ownership
   with Initializes => null
is
   type Node;
   type Node_Ptr is access Node;
   subtype Node_Ref is not null Node_Ptr;

   type Node is record
      Value : Integer;
      Next  : Node_Ptr;
   end record;

   function Make_Node (V : Integer) return Node_Ptr
      with Global => null,
           Depends => (Make_Node'Result => V);

   procedure Set_Value (N : in out Node_Ref; V : Integer)
      with Global => null,
           Depends => (N => (N, V));

   function Get_Value (N : Node_Ref) return Integer
      with Global => null,
           Depends => (Get_Value'Result => N);

   procedure Demo
      with Global => null;
end Ownership;
```

#### Emitted `ownership.adb`

```ada
pragma SPARK_Mode;
with Ada.Unchecked_Deallocation;

package body Ownership is

   procedure Free_Node_Ptr is new Ada.Unchecked_Deallocation(Node, Node_Ptr);

   function Make_Node (V : Integer) return Node_Ptr is
   begin
      return new Node'(V, null);
   end Make_Node;

   procedure Set_Value (N : in out Node_Ref; V : Integer) is
   begin
      N.Value := V;
   end Set_Value;

   function Get_Value (N : Node_Ref) return Integer
   is (N.Value);

   procedure Demo is
   begin
      declare
         A : Node_Ptr := Make_Node(10);
      begin
         declare
            B : Node_Ptr := Make_Node(20);
         begin
            -- Move: A transferred to C, A becomes null
            declare
               C : Node_Ptr := A;
            begin
               A := null;  -- move: source becomes null
               pragma Assert(C /= null);
               declare
                  Ref : Node_Ref := Node_Ref(C);
               begin
                  Set_Value(Ref, 42);
               end;
               -- End of scope for C: deallocate
               if C /= null then Free_Node_Ptr(C); end if;
            end;
            -- End of scope for B: deallocate
            if B /= null then Free_Node_Ptr(B); end if;
         end;
         -- A is null (moved to C), no deallocation needed
         if A /= null then Free_Node_Ptr(A); end if;
      end;
   end Demo;

end Ownership;
```

---

### Emitted Support Files

#### `gnat.adc` (configuration file)

```ada
pragma Partition_Elaboration_Policy(Sequential);
pragma Profile(Jorvik);
```
