# Translation Rules: Safe to Ada/SPARK

**Status: FINAL**
**Frozen commit:** `4aecf219ffa5473bfc42b026a66c8bdea2ce5872`

This document defines the translation rules for lowering Safe AST nodes to Ada 2022 / SPARK 2022 source code. The emitted Ada is the canonical representation verified by GNATprove at Bronze and Silver levels.

**Clause ID format:** `SAFE@4aecf21:spec/<file>#<section>.p<n>` references paragraph `<n>` of `<section>` in the given spec file at the frozen commit.

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
8. [Wide Intermediate Arithmetic Emission](#8-wide-intermediate-arithmetic)
9. [Automatic Deallocation Emission](#9-automatic-deallocation)
10. [Effect Summary Generation](#10-effect-summary-generation)
11. [Package Structure Emission](#11-package-structure-emission)
12. [Conservative Defaults for Underspecified Semantics](#12-conservative-defaults)
13. [Reserved Word and Identifier Mapping](#13-identifier-mapping)
14. [End-to-End Examples](#14-end-to-end-examples)

---

## 1. Mapping Table

The following table maps each Safe construct to its Ada/SPARK emission pattern. AST node types (from `compiler/ast_schema.json`) are referenced in the Notes column.

| Safe Construct | Ada/SPARK Emission | Clause Reference | Notes |
|---|---|---|---|
| `package P is ... end P;` | `.ads` + `.adb` pair with `pragma SPARK_Mode;` | SAFE@4aecf21:spec/03-single-file-packages.md#3.1.p1 | AST: `CompilationUnit`, `PackageUnit`. Public decls to `.ads`, bodies to `.adb` |
| `public` keyword on declaration | Declaration appears in `.ads` (visible part) | SAFE@4aecf21:spec/03-single-file-packages.md#3.1.p6 | No `public` = declaration in `.adb` body |
| `public type T is private record ... end record;` | Type in `.ads` visible part; full decl in `.ads` private part | SAFE@4aecf21:spec/03-single-file-packages.md#3.1.p7 | AST: `RecordTypeDefinition` with `is_private=true` |
| `with P;` | `with P;` | SAFE@4aecf21:spec/03-single-file-packages.md#3.1.p1 | AST: `WithClause`. Direct pass-through |
| `use type T;` | `use type T;` | SAFE@4aecf21:spec/02-restrictions.md#2.1.7.p52 | AST: `UseTypeClause`. Direct pass-through |
| `X.First` (attribute) | `X'First` | SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p109 | AST: `SelectedComponent` with `resolved_kind=Attribute`. Dot-to-tick |
| `X.Last` (attribute) | `X'Last` | SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick for all attributes |
| `X.Range` (attribute) | `X'Range` | SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick for all attributes |
| `X.Image(V)` | `X'Image(V)` | SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p112 | Parameterised attribute |
| `X.Access` | `X'Access` | SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick |
| `X.Valid` | `X'Valid` | SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p109 | Dot-to-tick |
| `(Expr as T)` (type annotation) | `T'(Expr)` (qualified expression) | SAFE@4aecf21:spec/02-restrictions.md#2.4.2.p113 | AST: `AnnotatedExpression`. Reverse annotation to qualified expr |
| `new (Expr as T)` (allocator) | `new T'(Expr)` | SAFE@4aecf21:spec/02-restrictions.md#2.4.2.p116 | AST: `Allocator` with `kind=Annotated`. Combined with dot-to-tick |
| `new T` (allocator, default init) | `new T` | SAFE@4aecf21:spec/02-restrictions.md#2.4.2.p116 | AST: `Allocator` with `kind=SubtypeOnly`. Direct pass-through |
| `type T is range L .. H;` | `type T is range L .. H;` | SAFE@4aecf21:spec/08-syntax-summary.md#8.4 | AST: `SignedIntegerTypeDefinition`. Direct pass-through |
| `type T is access T2;` | `type T is access T2;` | SAFE@4aecf21:spec/08-syntax-summary.md#8.4 | AST: `AccessToObjectDefinition`. Direct pass-through |
| `subtype T_Ref is not null T_Ptr;` | `subtype T_Ref is not null T_Ptr;` | SAFE@4aecf21:spec/02-restrictions.md#2.3.1.p95 | AST: `SubtypeDeclaration`. Direct pass-through |
| Integer arithmetic `A + B` | `Wide_Integer(A) + Wide_Integer(B)` | SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p126 | AST: `Expression` with `wide_arithmetic=true`. Wide intermediate lifting |
| Narrowing: `return Expr` | `return T(Wide_Expr)` | SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p127 | AST: `SimpleReturnStatement`. Range check at narrowing point |
| Narrowing: `X = Expr` | `X := T(Wide_Expr);` | SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p127 | AST: `AssignmentStatement`. Range check at narrowing point |
| `task T ... end T;` | Ada task type + single instance | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.1.p1 | AST: `TaskDeclaration`. See Section 6 |
| `channel C : T capacity N;` | Protected object with bounded buffer | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p12 | AST: `ChannelDeclaration`. See Section 4 |
| `send C, Expr;` | `C.Send(Expr);` (entry call) | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p27 | AST: `SendStatement`. Blocking entry call |
| `receive C, Var;` | `C.Receive(Var);` (entry call) | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p28 | AST: `ReceiveStatement`. Blocking entry call |
| `try_send C, Expr, Ok;` | `C.Try_Send(Expr, Ok);` (procedure call) | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p29 | AST: `TrySendStatement`. Non-blocking procedure |
| `try_receive C, Var, Ok;` | `C.Try_Receive(Var, Ok);` (procedure call) | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p30 | AST: `TryReceiveStatement`. Non-blocking procedure |
| `select ... end select;` | Polling loop with `Try_Receive` calls | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.4.p39 | AST: `SelectStatement`. See Section 5 |
| `delay Expr;` | `delay Duration(Expr);` | SAFE@4aecf21:spec/02-restrictions.md#2.1.8.p60 | AST: `DelayStatement`. Direct pass-through if Duration typed |
| `pragma Assert(Cond);` | `pragma Assert(Cond);` | SAFE@4aecf21:spec/02-restrictions.md#2.1.10.p68 | AST: `Pragma`. Direct pass-through |
| Scope exit of owning access var | `Free(Var);` (generated Unchecked_Deallocation) | SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p104 | See Section 9 |
| Interleaved declaration in body | Declaration hoisted to `declare` block | SAFE@4aecf21:spec/02-restrictions.md#2.9.p140 | AST: `InterleavedItem`. See Section 11 |
| Forward declaration | Subprogram spec in `.ads` | SAFE@4aecf21:spec/03-single-file-packages.md#3.2.3.p11 | AST: `SubprogramDeclaration`. Body in `.adb` |
| `is separate` (subunit stub) | `is separate;` | SAFE@4aecf21:spec/08-syntax-summary.md#8.9 | AST: `SubunitStub`. Direct pass-through |

---

## 2. Dot-to-Tick Notation

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p109-112

**AST node:** `SelectedComponent` (with `resolved_kind` field)

Safe uses dot notation (`X.Attr`) for all attribute references. Ada uses tick notation (`X'Attr`). The emitter must reverse this transformation.

### 2.1 Resolution Rule

During semantic analysis, each `SelectedComponent` node is classified per the resolution rule (SAFE@4aecf21:spec/02-restrictions.md#2.4.1.p110):

| SelectedComponent resolved_kind | Emission |
|---|---|
| `RecordField` | `X.Field` (dot notation, unchanged) |
| `Attribute` | `X'Attr` (dot becomes tick) |
| `PackageMember` | `P.Name` (dot notation, unchanged) |
| `ImplicitDereference` | `X.all.Field` or `X.Field` (Ada implicit deref) |

### 2.2 Parameterised Attributes

Attributes taking parameters use function-call syntax in Safe (`T.Image(42)`) and are emitted as Ada attribute calls (`T'Image(42)`).

### 2.3 Range Attribute

Safe `name.Range` and `name.Range(N)` emit as `name'Range` and `name'Range(N)`. These are represented by the `Range` AST node with `kind=AttributeRange`.

### 2.4 Example

```
-- Safe source:
return B(B.First);
X : Integer = T.Last;
S : String = V.Image;

-- Emitted Ada:
return B(B'First);
X : Integer := T'Last;
S : String := V'Image;
```

### 2.5 Complete Attribute Inventory

All attributes listed in SAFE@4aecf21:spec/02-restrictions.md#2.5.1.p118 are emitted with tick notation. The emitter maintains a compile-time lookup table of all 70 retained attribute names (enumerated in spec/02-restrictions.md section 2.5.1) to distinguish attribute references from record field accesses during emission. This table is generated from the spec inventory at compiler build time:

```
RETAINED_ATTRIBUTES : constant array of String :=
   ("Access", "Address", "Adjacent", "Aft", "Alignment", "Base",
    "Bit_Order", "Ceiling", "Component_Size", "Compose",
    "Constrained", "Copy_Sign", "Definite", "Delta", "Denorm",
    "Digits", "Enum_Rep", "Enum_Val", "Exponent", "First",
    "First_Valid", "Floor", "Fore", "Fraction", "Image", "Last",
    "Last_Valid", "Leading_Part", "Length", "Machine",
    "Machine_Emax", "Machine_Emin", "Machine_Mantissa",
    "Machine_Overflows", "Machine_Radix", "Machine_Rounds",
    "Max", "Max_Alignment_For_Allocation",
    "Max_Size_In_Storage_Elements", "Min", "Mod", "Model",
    "Model_Emin", "Model_Epsilon", "Model_Mantissa",
    "Model_Small", "Modulus", "Object_Size",
    "Overlaps_Storage", "Pos", "Pred", "Range", "Remainder",
    "Round", "Rounding", "Safe_First", "Safe_Last", "Scale",
    "Scaling", "Size", "Small", "Storage_Size", "Succ",
    "Truncation", "Unbiased_Rounding", "Val", "Valid",
    "Value", "Wide_Image", "Wide_Value", "Wide_Wide_Image",
    "Wide_Wide_Value", "Wide_Wide_Width", "Wide_Width", "Width");
```

---

## 3. Type Annotations and Qualified Expressions

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.4.2.p113-116

**AST node:** `AnnotatedExpression`

### 3.1 Basic Rule

Safe `(Expr as T)` emits as Ada `T'(Expr)`.

### 3.2 In Allocators

Safe `new (Expr as T)` emits as Ada `new T'(Expr)`.

### 3.3 Examples

```
-- Safe source:
X = ((others = 0) as Buffer_Type);
P = new (42 as Integer);
Foo ((X as T));

-- Emitted Ada:
X := Buffer_Type'(others => 0);
P := new Integer'(42);
Foo (T'(X));
```

### 3.4 Interaction with Wide Intermediate Arithmetic

When the expression inside a type annotation involves integer arithmetic, the emitter first lifts to `Wide_Integer`, then narrows via the type conversion. The outer qualified expression is retained for disambiguation only when the context requires it (e.g., overloaded predefined operators for universal types). In most cases, the type conversion alone is sufficient since it performs the range check:

```
-- Safe source:
Y = ((A + B) as Reading);

-- Emitted Ada (standard case):
Y := Reading(Safe_Runtime.Wide_Integer(A) + Safe_Runtime.Wide_Integer(B));
```

**Decision:** The outer qualified expression `Reading'(...)` is omitted when the context is unambiguous. The type conversion `Reading(Wide_Expr)` performs the required range check. If the context is ambiguous (e.g., as a parameter to an overloaded predefined operator), the qualified expression form `Reading'(Reading(Wide_Expr))` is used. Since Safe has no user-defined overloading, this ambiguity arises only with universal types.

---

## 4. Channel Lowering to Protected Objects

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p12, SAFE@4aecf21:spec/07-annex-b-impl-advice.md#B.6.p16

**AST node:** `ChannelDeclaration`

Each Safe `channel` declaration is lowered to an Ada protected object implementing a bounded FIFO queue.

### 4.1 Protected Object Template

For a channel declared as:
```
channel Data_Ch : Element_Type capacity 16;
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

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p21-21a

The emitter computes the ceiling priority for each channel as:

```
ceiling(Ch) = max { priority(T) | T accesses Ch directly or transitively }
```

Cross-package channel access is determined from channel-access summaries in the dependency interface (SAFE@4aecf21:spec/03-single-file-packages.md#3.3.1.p33(i)).

Conservative over-approximation is permitted (SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p21a(d)). When no task accesses a channel (e.g., a public channel accessed only from client code not yet compiled), the ceiling defaults to `System.Any_Priority'Last` (see Section 12, conservative defaults).

### 4.4 Buffer Index Types

The internal buffer index types are generated as tight subtypes to satisfy Silver-level proof:

```ada
subtype Buffer_Index is Natural range 0 .. 15;  -- for capacity 16
subtype Buffer_Count is Natural range 0 .. 16;
```

This ensures that `Head`, `Tail`, and `Count` are provably in-range. The modular arithmetic `(Natural(Tail) + 1) mod 16` is wrapped in a `Buffer_Index(...)` conversion to produce a value in the tight subtype range. GNATprove can verify this conversion is always valid since `(x + 1) mod N` is always in `0 .. N-1`.

### 4.5 Ownership Transfer through Channels

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p27a-29b

When the channel element type is an owning access type, the `Send` entry performs a move. The emitter must:

1. Evaluate the expression.
2. Enqueue the value.
3. Set the source variable to `null` after the send.

For `try_send`, the source is set to `null` only when `Success = True`.

```ada
-- Emitted Ada for: send Ch, Ptr;
Ch.Send(Ptr);
Ptr := null;  -- move semantics: source becomes null

-- Emitted Ada for: try_send Ch, Ptr, Ok;
declare
   Tmp : Element_Type := Ptr;
begin
   Ch.Try_Send(Tmp, Ok);
   if Ok then
      Ptr := null;
   end if;
end;
```

**Atomicity guarantee:** The `try_send` emission uses a temporary variable `Tmp` to capture the value before the fullness check. The protected object's mutual exclusion provides the atomicity required by SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p29b: the evaluation of the fullness condition and the enqueue decision occur within the protected procedure call, which is atomic with respect to other channel operations. The source variable is nulled only after the protected call confirms success.

---

## 5. Select Lowering

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.4.p32-44

**AST nodes:** `SelectStatement`, `SelectArm`, `ChannelArm`, `DelayArm`

Safe's `select` statement multiplexes channel receive operations. Ada does not have a direct equivalent for protected-object entry multiplexing, so the emitter produces a polling pattern.

### 5.1 Polling Loop Pattern

```
-- Safe source:
select
   when Msg : Command from Commands then
      Handle(Msg);
   or when Data : Integer from Data_Ch then
      Process(Data);
   or delay 5.0 then
      Timeout_Handler;
end select;
```

Emits as:

```ada
declare
   Select_Done : Boolean := False;
   Select_Deadline : constant Duration := 5.0;
   Select_Start : constant Duration := Ada.Real_Time.To_Duration(
      Ada.Real_Time.Clock - Ada.Real_Time.Time_First);
   -- Note: Since Ada.Real_Time is excluded from Safe source, the emitter
   -- uses Duration-based timing with a monotonic clock wrapper from
   -- Safe_Runtime. See conservative default for timing mechanism below.
begin
   while not Select_Done loop
      -- Arm 1: Commands (higher priority by source order)
      declare
         Msg : Command;
         Got_Msg : Boolean;
      begin
         Commands.Try_Receive(Msg, Got_Msg);
         if Got_Msg then
            Handle(Msg);
            Select_Done := True;
         end if;
      end;

      if not Select_Done then
         -- Arm 2: Data_Ch
         declare
            Data : Integer;
            Got_Data : Boolean;
         begin
            Data_Ch.Try_Receive(Data, Got_Data);
            if Got_Data then
               Process(Data);
               Select_Done := True;
            end if;
         end;
      end if;

      if not Select_Done then
         -- Check delay arm
         if Safe_Runtime.Elapsed_Since(Select_Start) >= Select_Deadline then
            Timeout_Handler;
            Select_Done := True;
         else
            delay 0.001;  -- 1ms sleep to avoid busy-wait
         end if;
      end if;
   end loop;
end;
```

### 5.2 Select without Delay Arm

If no delay arm is present, the polling loop has no deadline and polls indefinitely until a channel arm fires (SAFE@4aecf21:spec/04-tasks-and-channels.md#4.4.p42). The `delay 0.001` sleep between poll rounds is retained to avoid busy-waiting.

### 5.3 Arm Priority

Arms are tested in declaration order (top to bottom). The first ready arm is selected (SAFE@4aecf21:spec/04-tasks-and-channels.md#4.4.p41). The emission preserves this ordering with sequential `if not Select_Done then` checks.

### 5.4 Latency Note

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.4.p39

The polling-with-sleep pattern introduces latency equal to the sleep interval (1 millisecond by default). Implementations may use more efficient patterns (e.g., a dispatcher task with entry calls, or a combined protected object that aggregates all channel states) provided the observable semantics are preserved. The conservative default is the polling pattern because it:

- Works with any Ada runtime
- Does not require additional task creation
- Has bounded, predictable resource usage
- Preserves the declaration-order arm priority semantics

### 5.5 Ownership in Select Arms

When the channel element type is an owning access type, the `Try_Receive` in the select arm performs ownership transfer. The received variable is scoped to the arm's declare block, so deallocation occurs at the end of the arm's statements.

---

## 6. Task Emission

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.1

**AST node:** `TaskDeclaration`

### 6.1 Task Type and Instance

Each Safe `task` declaration becomes an Ada task type with a single instance:

```
-- Safe source:
task Producer with Priority = 10 is
   ...
begin
   loop
      ...
   end loop;
end Producer;
```

Emits as:

```ada
-- In .adb:
task type Producer_Task_Type
   with Priority => 10
is
end Producer_Task_Type;

Producer : Producer_Task_Type;

task body Producer_Task_Type is
   -- declarative_part from Safe task
begin
   loop
      ...
   end loop;
end Producer_Task_Type;
```

### 6.2 Task Naming Convention

The generated task type name is `<SafeName>_Task_Type`. The single instance retains the Safe task name.

**Collision avoidance:** Since Safe prohibits overloading (SAFE@4aecf21:spec/02-restrictions.md#2.10.p141), there can be at most one user-declared entity with any given name in a declarative region. The suffix `_Task_Type` cannot collide with the instance name (which is the unadorned Safe task name), and if the user declares an entity named `Producer_Task_Type`, it would conflict with the task name `Producer` only if both are in the same package -- but Safe tasks are package-level items and cannot share a name with another package-level item. If an implementation detects a rare collision, it appends a numeric suffix (e.g., `Producer_Task_Type_1`).

### 6.3 Priority Aspect

The `Priority` aspect is emitted directly on the task type declaration. If no priority is specified in Safe source, the implementation's default priority is used (SAFE@4aecf21:spec/04-tasks-and-channels.md#4.1.p9), which is `System.Default_Priority` in Ada.

### 6.4 Non-Termination

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.6.p53

The non-termination legality rule is enforced at compile time. The emitted task body preserves the unconditional outer loop from the Safe source. No additional runtime enforcement is needed.

### 6.5 Global Aspects on Task Bodies

The emitter generates `Global` aspects on task bodies referencing only owned variables and channel operations:

```ada
task body Producer_Task_Type
   with Global => (In_Out => (Raw_Data, Sample_Counter))
is
   ...
```

### 6.6 Elaboration Policy

**Clause:** SAFE@4aecf21:spec/04-tasks-and-channels.md#4.7.p56, SAFE@4aecf21:spec/07-annex-b-impl-advice.md#B.6.p15

The emitter produces a GNAT configuration file containing:

```ada
pragma Partition_Elaboration_Policy(Sequential);
pragma Profile(Jorvik);
```

This ensures all package elaboration completes before any task activates (SAFE@4aecf21:spec/04-tasks-and-channels.md#4.7.p56).

---

## 7. Ownership Emission

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.3

**AST nodes:** `AssignmentStatement` (with `ownership_action` field), `ObjectDeclaration`

### 7.1 Ownership Mapping Table

| Safe Ownership Operation | Emitted Ada Pattern | Clause |
|---|---|---|
| Move: `Y = X;` (access assignment) | `Y := X; X := null;` | SAFE@4aecf21:spec/02-restrictions.md#2.3.2.p96 |
| Borrow: `Y : access T = X;` | `declare Y : access T := X; begin ... end;` | SAFE@4aecf21:spec/02-restrictions.md#2.3.3.p98 |
| Observe: `Y : access constant T = X.Access;` | `declare Y : access constant T := X'Access; begin ... end;` | SAFE@4aecf21:spec/02-restrictions.md#2.3.4.p101 |
| Parameter borrow: `P(X)` where param is `in out` access | Direct pass-through; SPARK ownership checks apply | SAFE@4aecf21:spec/02-restrictions.md#2.3.3.p98(b) |
| Parameter observe: `P(X)` where param is `in` access | Direct pass-through; SPARK ownership checks apply | SAFE@4aecf21:spec/02-restrictions.md#2.3.4.p101(b) |
| Scope-exit deallocation | `Free(Var);` before scope end | SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p104 |

### 7.2 Move Emission

For every assignment of an owning access value, the emitter inserts a null-assignment of the source:

```ada
-- Safe source:
Y = X;

-- Emitted Ada:
Y := X;
X := null;  -- move: source becomes null
```

For function returns, the move is implicit (the local goes out of scope).

### 7.3 Null-Before-Move Verification

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.3.2.p97a

The compiler verifies at compile time that the target of a move is provably null. This is a legality rule enforced before emission; no runtime code is needed.

### 7.4 SPARK Annotations for Ownership

The emitted Ada relies on SPARK 2022's built-in ownership model (SPARK RM 3.10). The emitter does not generate additional ownership annotations beyond what SPARK infers from the access type declarations. GNATprove's ownership checking on the emitted Ada is sufficient because:

- Safe's ownership model (SAFE@4aecf21:spec/02-restrictions.md#2.3) is a subset of SPARK 2022's ownership model (SPARK RM 3.10).
- The emitted null-assignment after moves is exactly what SPARK expects.
- The `not null` subtype declarations provide the non-null guarantees SPARK uses for dereference safety.

No additional `pragma Annotate` directives are required.

---

## 8. Wide Intermediate Arithmetic

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p126-130

**AST node:** `Expression` (with `wide_arithmetic` field)

### 8.1 Wide_Integer Type Declaration

The emitter produces a wide integer type in a support package:

```ada
-- safe_runtime.ads
package Safe_Runtime is
   type Wide_Integer is range -(2**63) .. (2**63 - 1);
end Safe_Runtime;
```

### 8.2 Lifting Rule

Every integer subexpression is lifted to `Wide_Integer` before evaluation. The lifting occurs at the leaves (operands) of arithmetic expressions:

```
-- Safe source:
return (A + B) / 2;
-- where A, B : Reading (range 0 .. 4095)

-- Emitted Ada:
return Reading(
   (Safe_Runtime.Wide_Integer(A) + Safe_Runtime.Wide_Integer(B)) / 2
);
```

### 8.3 Narrowing Points

Narrowing (conversion back to the target type) occurs at exactly five points (SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p127):

| Narrowing Point | Emission Pattern | AST Node |
|---|---|---|
| Assignment: `X = Expr;` | `X := Target_Type(Wide_Expr);` | `AssignmentStatement` |
| Parameter passing | `Call(Target_Type(Wide_Expr));` | `ProcedureCallStatement` / `FunctionCall` |
| Function return | `return Target_Type(Wide_Expr);` | `SimpleReturnStatement` |
| Type conversion | `Target_Type(Wide_Expr)` | `TypeConversion` |
| Type annotation | `Target_Type(Wide_Expr)` | `AnnotatedExpression` |

### 8.4 Non-Integer Expressions

Wide intermediate arithmetic applies only to integer types. Floating-point and Boolean expressions pass through without lifting.

**Modular types:** Modular types use modular arithmetic with well-defined wrapping semantics (SAFE@4aecf21:spec/08-syntax-summary.md#8.4). Modular operations are NOT lifted to wide intermediate. Modular arithmetic wraps at the modulus boundary by definition, and lifting would change the semantics. For example, `Mod_Type'Last + 1` wraps to 0 in modular arithmetic but would be `Mod_Type'Last + 1` in wide arithmetic. The emitter passes modular expressions through unchanged.

### 8.5 Static Expressions

Static expressions (compile-time evaluable) may be evaluated by the compiler rather than emitted as wide-intermediate code. The result must fit in the target type.

### 8.6 Intermediate Overflow Rejection

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p129

If the compiler's interval analysis determines that an intermediate subexpression could exceed 64-bit signed range, the program is rejected at compile time. No runtime wide-integer overflow is possible in emitted code.

### 8.7 Example: Full Emission

```
-- Safe source:
public type Reading is range 0 .. 4095;

public function Average (A, B : Reading) return Reading is
begin
   return (A + B) / 2;
end Average;

-- Emitted Ada (in .adb):
function Average (A, B : Reading) return Reading is
begin
   return Reading(
      (Safe_Runtime.Wide_Integer(A) + Safe_Runtime.Wide_Integer(B)) / 2
   );
   -- GNATprove: Wide_Integer range [0 .. 8190] / 2 = [0 .. 4095]
   -- Narrowing to Reading (0 .. 4095): provably safe
end Average;
```

---

## 9. Automatic Deallocation

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p103-106

### 9.1 Unchecked_Deallocation Instantiation

For each pool-specific access type (both owning and named access-to-constant), the emitter generates an `Unchecked_Deallocation` instantiation:

```ada
-- For: type Node_Ptr is access Node;
procedure Free_Node_Ptr is new Ada.Unchecked_Deallocation(Node, Node_Ptr);
```

**Note:** The exclusion of generics (SAFE@4aecf21:spec/02-restrictions.md#2.1.11.p69) applies to Safe source, not emitted Ada. The emitter freely uses `Ada.Unchecked_Deallocation`.

### 9.2 Scope Exit Points

Deallocation calls are emitted at every scope exit point (SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p104):

| Exit Point | Emission |
|---|---|
| Normal scope end (`end` of block/subprogram) | `if Var /= null then Free(Var); end if;` before `end` |
| Early `return` | Deallocation before `return` |
| `exit` statement leaving owning scope | Deallocation before `exit` |
| `goto` statement leaving owning scope | Deallocation before `goto` |

### 9.3 Reverse Declaration Order

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p105

When multiple owning access objects exit scope simultaneously, they are deallocated in reverse declaration order:

```ada
-- Safe source:
A : Node_Ptr = new Node'(...);
B : Node_Ptr = new Node'(...);
-- ... end of scope

-- Emitted Ada (before end):
if B /= null then Free_Node_Ptr(B); end if;
if A /= null then Free_Node_Ptr(A); end if;
```

### 9.4 General Access Types

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p106

General access types (`access all T`) are NOT deallocated, as they may designate stack-allocated objects.

### 9.5 Conditional Deallocation

The null check (`if Var /= null then`) is required because ownership moves may have set the variable to null during the scope's lifetime. Only non-null values are deallocated.

### 9.6 Named Access-to-Constant

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p104a

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
public procedure Process (Flag : Boolean) is
begin
   N : Node_Ptr = new Node'(Value = 0, Next = null);
   if Flag then
      return;       -- early exit: N must be freed
   end if;
   -- ... normal processing ...
end Process;        -- normal exit: N must be freed

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

**Clause:** SAFE@4aecf21:spec/05-assurance.md#5.2

### 10.1 Global Aspects

For each subprogram, the emitter generates a `Global` aspect listing the package-level variables read and written:

```ada
function Average (A, B : Reading) return Reading
   with Global => null;  -- no package-level state

procedure Initialize
   with Global => (In_Out => (Cal_Table, Initialized));
```

**Algorithm (informative):** SAFE@4aecf21:spec/05-assurance.md#5.2.2.p6

1. During the single-pass compilation, accumulate a read-set and write-set per subprogram.
2. For each package-level variable reference, add to the appropriate set.
3. For each called subprogram, merge callee's sets into caller's sets.
4. For mutual recursion, compute fixed point.

### 10.2 Depends Aspects

For each subprogram, the emitter generates a `Depends` aspect:

```ada
function Average (A, B : Reading) return Reading
   with Depends => (Average'Result => (A, B));

procedure Update (D : Units.Metres; T : Units.Seconds; H : Heading)
   with Depends => (Current_Speed => (D, T),
                    Current_Heading => H);
```

**Over-approximation is acceptable:** SAFE@4aecf21:spec/05-assurance.md#5.2.3.p10

### 10.3 Initializes Aspects

For each package, the emitter generates an `Initializes` aspect listing all package-level variables with initializers:

```ada
package Sensors
   with Initializes => (Cal_Table, Initialized)
is
   ...
```

**Clause:** SAFE@4aecf21:spec/05-assurance.md#5.2.4.p11

### 10.4 SPARK_Mode

Every emitted unit includes:

```ada
pragma SPARK_Mode;
```

### 10.5 Channel-Access Summaries

For cross-package ceiling priority computation, the dependency interface must include channel-access summaries (SAFE@4aecf21:spec/03-single-file-packages.md#3.3.1.p33(i)). These are computed during the same single-pass analysis as Global/Depends.

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

**Clause:** SAFE@4aecf21:spec/03-single-file-packages.md#3.1

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
- `with Safe_Runtime; use type Safe_Runtime.Wide_Integer;` (if wide arithmetic is used)
- Package body
- Subprogram bodies
- Task type declarations and bodies
- Channel (protected object) bodies
- Private subprogram bodies
- Unchecked_Deallocation instantiations
- Deallocation procedure declarations

### 11.2 Interleaved Declaration Handling

**Clause:** SAFE@4aecf21:spec/02-restrictions.md#2.9.p140

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

**Decision: declare-block approach.** The nested-declare-block approach is chosen over hoisting declarations to the subprogram's declarative part because:

1. **Scope fidelity:** Safe's "visible from declaration to end of scope" semantics are faithfully preserved. Variables are not visible before their declaration point.
2. **Initialization safety:** Variables are initialized at their declaration point, avoiding the need to track uninitialized variables.
3. **Deallocation correctness:** Owning access variables declared in interleaved positions are automatically scoped correctly for deallocation at scope exit.
4. **GNATprove compatibility:** GNATprove handles nested declare blocks correctly for flow analysis.

### 11.3 Opaque Type Emission

**Clause:** SAFE@4aecf21:spec/03-single-file-packages.md#3.2.6.p21-24

**AST node:** `RecordTypeDefinition` with `is_private=true`

```
-- Safe source:
public type Buffer is private record
   Data   : array (Buffer_Index) of Character;
   Length : Buffer_Size;
end record;

-- Emitted .ads (visible part):
type Buffer is private;

-- Emitted .ads (private section):
type Buffer is record
   Data   : array (Buffer_Index) of Character;
   Length : Buffer_Size;
end record;
```

---

## 12. Conservative Defaults for Underspecified Semantics

The following table lists semantics that are underspecified or implementation-defined in the Safe spec, along with the conservative default the emitter adopts and the rationale.

| Area | Underspecified Aspect | Conservative Default | Rationale | Clause Reference |
|---|---|---|---|---|
| Task default priority | Priority when no `Priority` aspect specified | `System.Default_Priority` (Ada default) | Matches Ada semantics; no surprising behavior | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.1.p9 |
| Task activation order | Order among tasks starting execution | Undefined; rely on Ada runtime scheduling | No way to control this portably; spec allows implementation-defined | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.7.p58 |
| Channel allocation strategy | Static vs. heap-allocated buffer | Static array in protected object (deterministic, no allocation failure) | Avoids heap allocation; bounded memory; provable | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p18 |
| Channel ceiling priority (no task accesses) | Ceiling when no task references channel | `System.Any_Priority'Last` (safe upper bound) | Prevents priority inversion for any future accessor | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p21 |
| Select polling interval | Sleep duration in select polling loop | 1 millisecond (`delay 0.001;`) | Balance between latency and CPU usage; configurable via Safe_Runtime constant | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.4.p39 |
| Select timing mechanism | How to measure delay arm expiry | `Safe_Runtime.Elapsed_Since` using monotonic Duration tracking | Ada.Real_Time is excluded from Safe source but the emitter can use it internally; Duration-based fallback available | SAFE@4aecf21:spec/02-restrictions.md#2.1.8.p60 |
| Depends over-approximation | Granularity of data-flow tracking | Include all potentially-contributing inputs (superset); refine later | Sound for Bronze verification; spec permits over-approximation | SAFE@4aecf21:spec/05-assurance.md#5.2.3.p10 |
| Global over-approximation | Granularity of variable tracking | Include all package-level vars referenced in any code path (superset) | Sound for Bronze verification; spec permits over-approximation | SAFE@4aecf21:spec/05-assurance.md#5.2.2.p6 |
| Equal-priority task scheduling | Scheduling among same-priority tasks | Implementation-defined by Ada runtime; emit no additional control | Spec explicitly allows this | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.1.p11 |
| Package init order (no dependency) | Order among unrelated packages | Alphabetical by package name (deterministic tie-breaking) | Ensures byte-identical emission across runs | SAFE@4aecf21:spec/03-single-file-packages.md#3.4.2.p45 |
| Floating-point rounding mode | IEEE 754 rounding mode | Default rounding (round-to-nearest-even); emit no explicit mode change | Standard IEEE 754 default | SAFE@4aecf21:spec/06-conformance.md#6.7.p22(i) |
| Runtime abort handler | Behaviour on Assert failure or allocation failure | Call `GNAT.OS_Lib.OS_Exit(1)` with source-location diagnostic to stderr | Deterministic, observable failure behavior | SAFE@4aecf21:spec/06-conformance.md#6.7.p22(g) |
| Deallocation order at scope exit | When multiple owners exit simultaneously | Reverse declaration order | Spec mandates this | SAFE@4aecf21:spec/02-restrictions.md#2.3.5.p105 |
| Anonymous access reassignment | Whether anonymous access vars can be reassigned after init | Rejected at compile time (initialisation-only restriction) | Spec mandates this | SAFE@4aecf21:spec/02-restrictions.md#2.3.3.p100a |
| Wide_Integer type name | Name of the 64-bit intermediate type in emitted Ada | `Safe_Runtime.Wide_Integer` in a dedicated support package | Avoids name collision with user types | SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p126 |
| Constant_After_Elaboration | Whether to emit this GNATprove aspect | Emit for all package-level variables not written by any task body | Conservative: helps GNATprove verify task-safe reads | SAFE@4aecf21:spec/05-assurance.md#5.2.4.p11 |
| Tasking profile | Which Ada tasking profile to use | `pragma Profile(Jorvik);` | Provides static task/protected object model compatible with Safe's restrictions | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.7.p59 |
| Elaboration policy | Partition elaboration policy | `pragma Partition_Elaboration_Policy(Sequential);` | Ensures elaboration before task activation | SAFE@4aecf21:spec/04-tasks-and-channels.md#4.7.p59 |
| Identifier collision avoidance | When generated names might conflict with user identifiers | Prefix generated internal names with `Safe_` (e.g., `Safe_Select_Done`) | Avoid collision with user identifiers while maintaining readability | SAFE@4aecf21:spec/08-syntax-summary.md#8.15 |
| Modular wide arithmetic | Whether modular types are lifted to Wide_Integer | Not lifted; modular arithmetic passes through unchanged | Modular wrapping semantics would be changed by lifting | SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p126 |

---

## 13. Reserved Word and Identifier Mapping

**Clause:** SAFE@4aecf21:spec/08-syntax-summary.md#8.15

### 13.1 Safe-Only Reserved Words

Safe introduces reserved words not reserved in Ada: `public`, `channel`, `send`, `receive`, `try_send`, `try_receive`, `capacity`, `from`. These do not appear directly in emitted Ada; they are consumed by the compiler.

### 13.2 Mapping for Generated Entities

| Safe Concept | Generated Ada Identifier | Convention | AST Node |
|---|---|---|---|
| Channel `Ch` | Protected object `Ch` | Same name | `ChannelDeclaration` |
| Task `T` | Task type `T_Task_Type`, instance `T` | Suffix `_Task_Type` | `TaskDeclaration` |
| Channel send entry | `Ch.Send` | Fixed name | `SendStatement` |
| Channel receive entry | `Ch.Receive` | Fixed name | `ReceiveStatement` |
| Channel try_send procedure | `Ch.Try_Send` | Fixed name | `TrySendStatement` |
| Channel try_receive procedure | `Ch.Try_Receive` | Fixed name | `TryReceiveStatement` |
| Wide integer type | `Safe_Runtime.Wide_Integer` | In support package | `Expression` nodes |
| Deallocation procedure | `Free_<TypeName>` | Prefix `Free_` | Generated for each access type |
| Select loop flag | `Safe_Select_Done` | Prefix `Safe_` | Generated for `SelectStatement` |
| Select deadline | `Safe_Select_Deadline` | Prefix `Safe_` | Generated for `DelayArm` |
| Buffer index subtype | `Buffer_Index` | Local to protected object | Generated for `ChannelDeclaration` |
| Buffer count subtype | `Buffer_Count` | Local to protected object | Generated for `ChannelDeclaration` |

### 13.3 Deterministic Emission

**Clause:** SAFE@4aecf21:spec/07-annex-b-impl-advice.md#B.5.p12

The emitter must produce byte-identical output for the same Safe source compiled with the same compiler version. All ordering decisions (declaration order, aspect order, import order) must be deterministic.

---

## 14. End-to-End Examples

### 14.1 Example A: Sensor Averaging with Wide Intermediate Arithmetic (D27 Rule 1)

This example demonstrates wide intermediate arithmetic emission for a simple averaging computation.

#### Safe Source (`averaging.safe`)

```
package Averaging is

   public type Reading is range 0 .. 4095;

   public function Average (A, B : Reading) return Reading is
   begin
      return (A + B) / 2;
      -- D27 Rule 1: wide intermediate, max (4095+4095)/2 = 4095
      -- D27 Rule 3(b): literal 2 is static nonzero
   end Average;

   public function Weighted_Avg (A, B : Reading; W : Reading) return Reading is
   begin
      return ((A * 3) + (B * 1)) / 4;
      -- D27 Rule 1: max (4095*3 + 4095*1)/4 = 4095
      -- D27 Rule 3(b): literal 4 is static nonzero
   end Weighted_Avg;

end Averaging;
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
with Safe_Runtime; use type Safe_Runtime.Wide_Integer;

package body Averaging is

   function Average (A, B : Reading) return Reading is
   begin
      return Reading(
         (Safe_Runtime.Wide_Integer(A) + Safe_Runtime.Wide_Integer(B)) / 2
      );
      -- GNATprove: Wide_Integer range [0 .. 8190] / 2 = [0 .. 4095]
      -- Narrowing to Reading (0 .. 4095): provably safe
   end Average;

   function Weighted_Avg (A, B : Reading; W : Reading) return Reading is
   begin
      return Reading(
         (Safe_Runtime.Wide_Integer(A) * 3 +
          Safe_Runtime.Wide_Integer(B) * 1) / 4
      );
      -- GNATprove: Wide_Integer range [0 .. 16380] / 4 = [0 .. 4095]
      -- Narrowing to Reading (0 .. 4095): provably safe
   end Weighted_Avg;

end Averaging;
```

---

### 14.2 Example B: Producer-Consumer Channel Program (Sections 4.2-4.3)

This example demonstrates channel lowering, task emission, and select lowering.

#### Safe Source (`pipeline.safe`)

```
package Pipeline is

   public type Measurement is range 0 .. 65535;

   channel Raw_Data : Measurement capacity 16;
   public channel Processed : Measurement capacity 8;

   task Producer with Priority = 10 is
   begin
      loop
         Sample : Measurement = Read_Sensor;
         send Raw_Data, Sample;
         delay 0.01;
      end loop;
   end Producer;

   task Consumer with Priority = 5 is
   begin
      loop
         M : Measurement;
         receive Raw_Data, M;
         Result : Measurement = ((M + 1) / 2 as Measurement);
         send Processed, Result;
      end loop;
   end Consumer;

   function Read_Sensor return Measurement is separate;

end Pipeline;
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
with Safe_Runtime; use type Safe_Runtime.Wide_Integer;

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
                  (Safe_Runtime.Wide_Integer(M) + 1) / 2
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

### 14.3 Example C: Ownership Transfer (Section 2.3)

This example demonstrates move semantics, automatic deallocation, and borrow/observe emission.

#### Safe Source (`ownership.safe`)

```
package Ownership is

   public type Node;
   public type Node_Ptr is access Node;
   public subtype Node_Ref is not null Node_Ptr;

   public type Node is record
      Value : Integer;
      Next  : Node_Ptr;
   end record;

   -- Move: caller's pointer is nulled after call
   public function Make_Node (V : Integer) return Node_Ptr is
   begin
      return new ((V, null) as Node);
   end Make_Node;

   -- Borrow: mutable temporary access via in-out parameter
   public procedure Set_Value (N : in out Node_Ref; V : Integer) is
   begin
      N.Value = V;
   end Set_Value;

   -- Observe: read-only access
   public function Get_Value (N : Node_Ref) return Integer
   is (N.Value);

   -- Demonstrates automatic deallocation at scope exit
   public procedure Demo is
   begin
      A : Node_Ptr = Make_Node(10);
      B : Node_Ptr = Make_Node(20);

      -- Move: A transferred to C, A becomes null
      C : Node_Ptr = A;

      -- Use C (which now owns the node)
      pragma Assert(C != null);
      Ref : Node_Ref = Node_Ref(C);
      Set_Value(Ref, 42);

      -- End of scope: C and B deallocated in reverse order
   end Demo;

end Ownership;
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

#### `safe_runtime.ads`

```ada
pragma SPARK_Mode;

package Safe_Runtime is
   type Wide_Integer is range -(2**63) .. (2**63 - 1);

   -- Monotonic elapsed time for select statement delay arms
   function Elapsed_Since (Start : Duration) return Duration;

   -- Select polling interval (configurable)
   Select_Poll_Interval : constant Duration := 0.001;
end Safe_Runtime;
```

#### `gnat.adc` (configuration file)

```ada
pragma Partition_Elaboration_Policy(Sequential);
pragma Profile(Jorvik);
```
