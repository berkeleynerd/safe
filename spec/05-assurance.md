# Section 5 — Assurance

**This section is normative.**

This section specifies the language-level assurance guarantees provided by Safe. The defining characteristic of Safe is that the developer writes zero verification annotations and receives both Bronze and Silver assurance automatically through the type system and legality rules.

---

## 5.1 Overview of Assurance Levels

1. Safe's assurance model is described in terms of the following levels, consistent with established practice in the formal verification community:

| Level | Property | Safe Guarantee |
|-------|----------|---------------|
| Stone | Expressibility as valid Ada/SPARK source | By construction (D1, D2) |
| Bronze | Complete and correct flow information | Guaranteed — language design enables automatic derivation (D22, D26) |
| Silver | Absence of Runtime Errors (AoRTE) | Guaranteed — D27 Rules 1–5 (this section) |
| Gold | Functional correctness | Out of scope — requires developer-authored specifications |
| Platinum | Full formal verification with mathematical proof | Out of scope — requires developer-authored lemmas and ghost code |

2. Every conforming Safe program achieves Stone, Bronze, and Silver without developer-supplied annotations. Gold and Platinum require specifications that express functional intent ("the sort function produces a sorted output"), which cannot be derived from the language alone.

---

## 5.2 Bronze Guarantee

### 5.2.1 Normative Statement

3. Every conforming Safe program shall have complete and correct flow information — specifically, the equivalent of `Global`, `Depends`, and `Initializes` information — derivable from its source without user-supplied annotations.

4. The language restrictions that make this possible are:

   (a) No aliasing violations — the ownership model (Section 2, §2.3) ensures that mutable access to any object is exclusive.

   (b) No dispatching — every call resolves statically (D18), so the called subprogram's effects are known.

   (c) No exceptions — control flow is fully visible (D14).

   (d) No overloading — every name resolves to exactly one entity (D12).

### 5.2.2 Global Information

5. For each subprogram, a conforming implementation shall be able to determine the set of package-level variables read and written, including transitive effects through called subprograms. This is the `Global` equivalent.

6. **Algorithm (informative).** The implementation accumulates a read-set and write-set per subprogram during name resolution. For each variable reference encountered:

   (a) If the reference reads a package-level variable, add it to the read-set.

   (b) If the reference writes a package-level variable, add it to the write-set.

   (c) For each called subprogram, merge the callee's read-set and write-set into the caller's sets.

7. For mutually recursive subprograms, a fixed-point computation over the call graph yields the complete sets.

### 5.2.3 Depends Information

8. For each subprogram, a conforming implementation shall be able to determine which outputs depend on which inputs. This is the `Depends` equivalent.

9. **Algorithm (informative).** The implementation tracks data flow through assignments, expressions, and conditional control flow:

   (a) Direct assignment: `X = f(A, B)` creates a dependency from A and B to X.

   (b) Conditional: `if C then X = A; else X = B;` creates dependencies from C, A, and B to X.

   (c) Loop iteration: conservative over-approximation is acceptable.

10. **Over-approximation note.** Implementation-derived `Depends` information may be conservatively over-approximate (listing more dependencies than actually exist). An implementation may refine precision over time without affecting conformance. Over-approximate `Depends` information is sound for Bronze verification purposes.

### 5.2.4 Initializes Information

11. For each package, a conforming implementation shall be able to determine which package-level variables are initialised at elaboration. Since Safe requires mandatory initialisation at declaration (D7), every package-level variable with an initialiser is part of the `Initializes` set.

---

## 5.3 Silver Guarantee

### 5.3.1 Normative Statement

12. Every conforming Safe program shall be free of runtime errors. Specifically, every runtime check that the implementation must perform (by the semantics of 8652:2023) shall be dischargeable from static type and range information derivable from the program text, combined with the D27 legality rules.

12a. **Scope of the Silver guarantee.** The Silver guarantee covers the runtime checks enumerable from the program text and the language semantics — those listed in the table at §5.3.8. It does not cover resource exhaustion conditions (allocation failure, stack overflow), which depend on the execution environment rather than the program text. Resource exhaustion is outside the scope of static reasoning in any language; the behaviour when it occurs is defined (runtime abort — Section 2, §2.3.5, paragraph 103a) but cannot be statically prevented by the language rules alone. This scoping is consistent with SPARK 2022, where AoRTE (Absence of Runtime Errors) does not cover `Storage_Error`. A future revision may tighten this boundary by introducing static allocation bounding (see TBD-03).

13. The following five rules collectively guarantee Silver (see Section 2, §2.8 for the formal legality rules):

### 5.3.2 64-Bit Integer Arithmetic (Rule 1)

14. All integer arithmetic expressions are evaluated in Safe's single predefined `integer` model. Every integer arithmetic result must be statically provable within the signed 64-bit range. Range checks are performed only at narrowing points: assignment, parameter passing, return, type conversion, and type annotation.

15. A conforming implementation shall reject any program where the static range of a declared integer type exceeds 64-bit signed range.

16. A conforming implementation shall reject any integer expression where it cannot establish that all intermediate subexpressions stay within 64-bit signed range.

17. **How this discharges overflow checks.** Integer overflow is not ignored or deferred to a support type. Instead, the implementation rejects any arithmetic expression whose possible results are not provably within signed 64-bit range. The remaining points where a range violation can occur are the narrowing points: assignment to a typed variable, return from a function, parameter passing, type conversion to a more restrictive type, and type annotation `(Expr as T)`. At these points, the implementation performs sound static range analysis on the computed result to establish that the value is within the target type's range.

18. Interval analysis is one permitted technique for range analysis; no specific algorithm is mandated.

18a. Fixed-width binary arithmetic is governed separately from Rule 1. For
    `binary (8)`, `binary (16)`, `binary (32)`, and `binary (64)`,
    arithmetic and bitwise operations use defined wraparound modulo `2^N`
    semantics and do not create integer-overflow proof obligations.

18b. Explicit conversions between `binary` and `integer`, explicit
    conversions between different binary widths, and shift counts for `<<`
    and `>>` remain subject to static checking. A conforming implementation
    shall reject a shift unless the count is provably within `0 .. N - 1`.
    `>>` on binary operands is a logical zero-fill right shift.

### 5.3.3 Provable Index Safety (Rule 2)

19. The index expression in an indexed component shall be provably within the array object's index bounds at compile time. The implementation accepts the indexing if: (a) the index expression's type or subtype range is statically contained within the array object's index constraint (type containment), or (b) the implementation can establish by sound static range analysis that the index value is within the array's bounds at that program point (e.g., after a conditional guard or when using bounds-derived expressions). If neither condition holds, the program is rejected.

20. **How this discharges index checks.** For full-range arrays indexed by a matching type (the common case), the index value is constrained by its type to be within the array bounds — no runtime check is needed. For arrays with narrower constraints or unconstrained array parameters with dynamic bounds, the implementation discharges the index check via static range analysis — the same machinery used for Rule 1's narrowing checks and Rule 3's division checks. The result is uniform: every index check is either discharged statically or the program is rejected.

### 5.3.4 Division by Provably Nonzero Divisor (Rule 3)

21. The right operand of `/`, `mod`, and `rem` shall be provably nonzero. The three accepted proof methods are: (a) nonzero type/subtype, (b) static nonzero value, (c) checked conversion to a nonzero subtype.

22. **How this discharges division-by-zero checks.** The divisor is constrained to be nonzero by type, value, or conversion. No runtime check for zero is needed.

### 5.3.5 Not-Null Dereference (Rule 4)

23. Dereference of an access value requires the access subtype to be `not null`. The implementation rejects any dereference of a nullable access type.

24. **How this discharges null dereference checks.** The access value is guaranteed non-null by its subtype at every dereference point. No runtime null check is needed.

### 5.3.6 Range Checks at Narrowing Points

25. Range checks occur at every narrowing point: when an integer result is assigned to a typed variable, returned from a function, passed as a parameter, used as the operand of a type conversion to a more restrictive type, or used as the expression of a type annotation `(Expr as T)`. The implementation shall discharge these checks via sound static range analysis.

26. If a conforming implementation cannot establish that a narrowing point is safe (i.e., the computed range of the result does not fit within the target type), the program is nonconforming and shall be rejected with a diagnostic.

### 5.3.7 Discriminant Checks

27. Discriminant checks arise when accessing a variant component of a discriminated record. The discriminant type is discrete and static. The implementation shall verify that access to a variant component is consistent with the current discriminant value.

28. This is dischargeable because:

   (a) Discriminant values are set at object creation and cannot change for constrained objects.

   (b) Case statements and if statements that check discriminant values create branches where the discriminant value is known.

### 5.3.7a Floating-Point Non-Trapping Semantics (Rule 5)

28a. A conforming implementation shall ensure that all predefined floating-point types use IEEE 754 default non-trapping arithmetic (`Machine_Overflows = False`). Under this model, floating-point overflow produces ±infinity, division by zero produces ±infinity, and invalid operations produce NaN. These are defined values, not runtime errors.

28b. **How this discharges floating-point checks.** Since no floating-point operation raises `Constraint_Error` (the non-trapping model replaces exceptions with special values), floating-point arithmetic itself is never a source of runtime errors. The remaining concern is range checks at narrowing points: assigning ±infinity or NaN to a typed floating-point variable would violate the type's range constraint. These are discharged by the same static range analysis used for integer narrowing (Rule 1, §5.3.2): the implementation verifies at each narrowing point that the floating-point value is a finite number within the target type's model range. Programs where this cannot be established are rejected.

28c. **NaN and infinity propagation.** NaN and ±infinity are permitted as intermediate values in floating-point expressions — they are well-defined under IEEE 754 and do not constitute runtime errors. However, they cannot survive a narrowing point (assignment, parameter passing, return, type conversion, type annotation) because no finite floating-point type's range includes them. This provides a natural containment boundary: floating-point computations run under full IEEE 754 semantics, but values that cross type boundaries must be finite and in-range.

### 5.3.8 Complete Runtime Check Enumeration

29. The following table enumerates all categories of runtime check and how each is discharged in Safe:

| Check Category | 8652:2023 Reference | How Discharged |
|---------------|--------------------:|----------------|
| Integer overflow | §4.5 | Rejected unless every integer arithmetic result is provably within signed 64-bit range (Rule 1) |
| Range check — integer (assignment) | §4.6, §5.2 | Sound static range analysis on integer results (Rule 1) |
| Range check — integer (return) | §6.5 | Sound static range analysis on integer results (Rule 1) |
| Range check — integer (parameter) | §6.4 | Sound static range analysis on integer results (Rule 1) |
| Range check — integer (type conversion) | §4.6 | Sound static range analysis on integer results (Rule 1) |
| Range check — integer (type annotation) | §4.7 | Sound static range analysis on integer results (Rule 1) |
| Binary overflow | §4.5 | Not applicable — `binary (8|16|32|64)` arithmetic wraps modulo `2^N` by definition |
| Range check — binary to integer conversion | §4.6 | Sound static range analysis on explicit conversion result; reject if not provably within signed 64-bit `integer` |
| Shift count check — binary `<<` / `>>` | §4.5 | Reject unless the count is provably within `0 .. N - 1`; `>>` is logical zero-fill right shift |
| Floating-point overflow | §A.5.3, §4.5 | Non-exceptional — produces ±infinity under IEEE 754 non-trapping mode; caught at narrowing points (Rule 5) |
| Floating-point division by zero | §A.5.3, §4.5.5 | Non-exceptional — produces ±infinity under IEEE 754 non-trapping mode; caught at narrowing points (Rule 5) |
| Floating-point invalid operation (NaN) | §A.5.3 | Non-exceptional — produces NaN under IEEE 754 non-trapping mode; caught at narrowing points (Rule 5) |
| Range check — float (assignment/return/parameter/conversion/annotation) | §4.6, §5.2, §6.4, §6.5, §4.7 | Sound static range analysis; value must be finite and within target type's model range (Rule 5) |
| Index check | §4.1.1 | Index provably within array object's bounds — by type containment or static range analysis (Rule 2) |
| Division by zero (integer) | §4.5.5 | Divisor provably nonzero (Rule 3) |
| Null dereference (explicit) | §4.1 | Access subtype is `not null` (Rule 4) |
| Null dereference (implicit) | §4.1.3 | Access subtype is `not null` (Rule 4) |
| Discriminant check | §4.1.3 | Discriminant type is discrete; access consistent with value |
| Accessibility check | §3.10.2 | Compile-time only — Ada accessibility rules retained as legality rules; no runtime check needed (Section 2, §2.3.8, paragraph 113) |
| Tag check | §3.9 | Not applicable — no tagged types |
| Allocation check | §4.8 | Outside Silver scope — resource exhaustion (paragraph 12a); defined behaviour is runtime abort (Section 2, §2.3.5, paragraph 103a) |
| Elaboration check | §3.11 | Not applicable — no circular dependencies; topological order |
| Length check (array assignment) | §4.6 | Static bounds or matching subtypes |
| Constraint check (subtype) | §3.2.2 | Sound static range analysis |

### 5.3.9 Hard Rejection Rule

30. If a conforming implementation cannot establish, from the specification's type rules and D27 legality rules, that a required runtime check will not fail, the program is nonconforming and the implementation shall reject it with a diagnostic.

31. There is no "developer must restructure" advisory — failure to satisfy any Silver-level proof obligation is a compilation error, not a warning.

31a. The built-in `print` statement is permitted even though it causes visible
output. A conforming implementation may realize `print` through generated
support code marked `SPARK_Mode => Off`, and may emit the immediately enclosing
Ada subprogram with `SPARK_Mode => Off`, so the I/O side effect is isolated
from the proved Safe body. This does not admit `Ada.Text_IO` into Safe source,
and for concurrent tasks the relative ordering of printed lines is unspecified.

---

## 5.4 Concurrency Assurance

### 5.4.1 Data Race Freedom

32. The tasking model guarantees data race freedom as a language property: user-declared unprotected shared mutable state is excluded, and any admitted `shared` root is lowered to a compiler-generated protected wrapper with copy-based operations (Section 4, §4.5). Inter-task communication is therefore through channels plus the narrow `shared` subset admitted in `PR11.12a` through `PR11.12e`.

33. The implementation shall verify this through task-variable ownership analysis (Section 4, §4.5): each package-level variable is accessed by at most one task.

33a. **No designated-object transfer through channels.** Channel element types exclude access types and composite types containing access-type subcomponents (Section 4, §4.2, paragraph 14). Data-race-freedom for concurrency therefore relies on copy-only channel communication plus task-variable ownership; channels are not a mechanism for transferring heap ownership between tasks.

### 5.4.2 Priority Inversion Avoidance

34. When mapping channels to underlying synchronisation mechanisms, the implementation shall use ceiling priority rules (or equivalent) to prevent priority inversion (Section 4, §4.2, paragraph 21). The ceiling priority of each channel is computed from the priorities of all tasks that access it, including tasks in other packages that access the channel transitively through public subprogram calls. Channel-access summaries in the dependency interface information (Section 3, §3.3.1(i)) provide the cross-package information needed for this computation (Section 4, §4.2, paragraph 21a).

### 5.4.3 Deadlock Freedom — Not Guaranteed

35. Application-level deadlock freedom is NOT guaranteed by the language rules for arbitrary channel programs that block on receive operations or form circular wait patterns through higher-level protocols.

36. Deadlock can still occur when tasks form a circular chain of blocking dependencies through `receive`, `select`, or protocol-level waiting. For example: task A blocks on `receive` from a channel only task B can send on, while task B blocks on `receive` from a channel only task A can send on.

37. Deadlock freedom is a program-level property dependent on the communication topology — specifically, on the absence of circular blocking dependencies between tasks and channels. The language does not currently specify restrictions sufficient to guarantee deadlock freedom statically.

38. **Informative note (deadlock topology).** The following communication pattern can deadlock:

```ada
-- INFORMATIVE: Example of a topology that CAN deadlock
-- This is NOT a conforming program guarantee — it illustrates a hazard.

channel A_to_B : Integer capacity 1;
channel B_to_A : Integer capacity 1;

task T_A with Priority = 5 is
begin
    loop
        X : Integer;
        receive B_to_A, X;   -- blocks if B_to_A empty
        Sent_A : Boolean = False;
        send A_to_B, X, Sent_A;
    end loop;
end T_A;

task T_B with Priority = 5 is
begin
    loop
        Y : Integer;
        receive A_to_B, Y;   -- blocks if A_to_B empty
        Sent_B : Boolean = False;
        send B_to_A, Y, Sent_B;
    end loop;
end T_B;

-- If neither channel is seeded before task start, both tasks can block on
-- their initial receive forever. This is the remaining deadlock-analysis gap.
```

39. This is noted as a potential area for future specification work (see TBD register in §00).

### 5.4.4 Task-Variable Ownership

40. Effect summaries on task bodies shall reference only owned variables and channel operations. The implementation verifies this using the task-variable ownership analysis (Section 4, §4.5).

---

## 5.5 Gold and Platinum

41. Gold (functional correctness) and Platinum (full formal verification with mathematical proof) are out of scope for this specification.

42. These levels require developer-authored specifications — postconditions stating functional intent, ghost code, and lemmas. These are inherently non-automatable: one cannot derive "this sort function produces a sorted output" from the type system alone.

43. A developer seeking Gold or Platinum assurance may work with the implementation's intermediate representations or emitted code directly, adding specifications as appropriate for their verification toolchain.

---

## 5.6 Examples

### 5.6.1 Example: Arithmetic — Silver-Provable via 64-Bit Range Analysis

**Conforming Example.**

```safe
-- averaging.safe

package averaging

    public subtype sample is integer (0 to 10000)
    public subtype sample_count is integer (1 to 100)
    -- sample_count excludes zero: valid divisor (Rule 3a)

    public function average_two (a, b : sample) returns sample
        return (a + b) / 2
        -- Rule 1: max (10000+10000)/2 = 10000
        -- Rule 3(b): literal 2 is static nonzero
        -- D27 proof: result in 0..10000

    public function average_n (sum : integer; count : sample_count)
        returns sample
        return sample (sum / count)
        -- Rule 3(a): sample_count excludes zero
        -- Narrowing at return: range check to sample
        -- D27 proof: implementation verifies sum / count in 0..10000

```

### 5.6.2 Example: Array Indexing — Silver-Provable via Provable Index Safety

**Conforming Example — full-range array, type containment (condition a).**

```ada
-- lookup.safe

package Lookup is

    public type Sensor_Id is range 0 .. 15;
    Calibration : array (Sensor_Id) of Float = (others = 1.0);

    public function Get_Cal (Id : Sensor_Id) return Float is
    begin
        return Calibration(Id);
        -- Rule 2(a): Sensor_Id 0..15 matches array bounds 0..15
        -- D27 proof: Id in Sensor_Id.First .. Sensor_Id.Last by type
    end Get_Cal;

end Lookup;
```

**Conforming Example — unconstrained array, guarded index (condition b).**

```ada
-- strings.safe

package Strings is

    public type Buffer is array (Positive range <>) of Character;

    public function Char_At (B : Buffer; I : Positive) return Character is
    begin
        if I in B.First .. B.Last then
            return B(I);
            -- Rule 2(b): I narrowed to B.First .. B.Last by guard
        else
            return ' ';
        end if;
    end Char_At;

    public function First_Char (B : Buffer) return Character is
    begin
        return B(B.First);
        -- Rule 2(b): B.First provably within B.First .. B.Last
    end First_Char;

end Strings;
```

### 5.6.3 Example: Division — Silver-Provable via Nonzero Divisor Types

**Conforming Example.**

```ada
-- rates.safe

package Rates is

    public type Distance is range 0 .. 1_000_000;
    public type Duration_Positive is range 1 .. 86_400;
    -- Duration_Positive excludes zero: valid divisor (Rule 3a)

    public function Speed (D : Distance; T : Duration_Positive) return Integer is
    begin
        return Integer(D) / Integer(T);
        -- Rule 3(a): Duration_Positive excludes zero
        -- Integer(T) is at least 1
        -- D27 proof: no division by zero possible
    end Speed;

end Rates;
```

### 5.6.4 Example: Access Types — Silver-Provable via Not-Null Subtypes

**Conforming Example.**

```ada
-- lists.safe

package Lists is

    public type Node;
    public type Node_Ptr is access Node;
    public subtype Node_Ref is not null Node_Ptr;

    public type Node is record
        Value : Integer;
        Next  : Node_Ptr;  -- nullable: may be end of list
    end record;

    public function Head_Value (List : Node_Ref) return Integer
    is (List.Value);
    -- Rule 4: Node_Ref is not null; dereference provably safe
    -- D27 proof: List != null by subtype

    public function Has_Next (N : Node_Ref) return Boolean
    is (N.Next != null);
    -- Null comparison is always legal; no dereference here

    public function Next_Value (N : Node_Ref) return Integer is
    begin
        pragma Assert (N.Next != null);
        Ref : Node_Ref = Node_Ref(N.Next);
        return Ref.Value;
        -- Rule 4: Ref is Node_Ref (not null); dereference safe
        -- D27 proof: Ref != null by conversion from checked non-null
    end Next_Value;

end Lists;
```

### 5.6.5 Example: Ownership — Move, Borrow, Observe

**Conforming Example.**

```ada
-- trees.safe

package Trees is

    public type Tree_Node;
    public type Tree_Ptr is access Tree_Node;
    public subtype Tree_Ref is not null Tree_Ptr;

    public type Tree_Node is record
        Value : Integer;
        Left  : Tree_Ptr;  -- nullable: may be empty subtree
        Right : Tree_Ptr;
    end record;

    -- Move: ownership transfers from caller to new node
    public function Make_Leaf (V : Integer) return Tree_Ptr is
    begin
        return new ((V, null, null) as Tree_Node);
        -- D27 proof: aggregate fields match Tree_Node
    end Make_Leaf;

    -- Borrow: mutable temporary access
    public procedure Set_Value (T : in out Tree_Ref; V : Integer) is
    begin
        T.Value = V;
        -- T is borrowed (in out mode); caller frozen during call
        -- D27 proof: Tree_Ref is not null; dereference safe
    end Set_Value;

    -- Observe: read-only temporary access
    public function Get_Value (T : Tree_Ref) return Integer
    is (T.Value);
    -- T is observed (in mode); caller frozen for reads only
    -- D27 proof: Tree_Ref is not null; dereference safe

    -- Automatic deallocation: when owner goes out of scope
    public procedure Example_Scope is
    begin
        N : Tree_Ptr = Make_Leaf(42);
        -- N owns the allocated node
        pragma Assert (N != null);
        Ref : Tree_Ref = Tree_Ref(N);
        V : Integer = Get_Value(Ref);
        -- N is automatically deallocated when Example_Scope returns
    end Example_Scope;

end Trees;
```

### 5.6.6 Example: Rejected Programs

**Nonconforming Example — Rule 2 violation (index type too wide).**

```ada
-- NONCONFORMING
package Bad_Index is
    type Sensor_Id is range 0 .. 15;
    Table : array (Sensor_Id) of Integer;

    public function Bad (N : Integer) return Integer is
    begin
        return Table(N);
        -- REJECTED: Integer range not contained in Sensor_Id (0..15)
        -- and no static analysis can narrow N to 0..15 at this point
        -- Violated rule: D27 Rule 2 (provable index safety)
        -- Source location: indexed_component Table(N)
    end Bad;
end Bad_Index;
```

**Nonconforming Example — Rule 2 violation (unguarded unconstrained array index).**

```ada
-- NONCONFORMING
package Bad_Buffer is
    type Buffer is array (Positive range <>) of Character;

    public function Bad_Char (B : Buffer; I : Positive) return Character is
    begin
        return B(I);
        -- REJECTED: Positive range not provably within B's dynamic bounds
        -- Violated rule: D27 Rule 2 (provable index safety)
        -- Fix: guard with "if I in B.First .. B.Last then"
    end Bad_Char;
end Bad_Buffer;
```

**Nonconforming Example — Rule 3 violation (divisor type includes zero).**

```ada
-- NONCONFORMING
package Bad_Division is
    public function Divide (A, B : Integer) return Integer is
    begin
        return A / B;
        -- REJECTED: Integer range includes zero
        -- Violated rule: D27 Rule 3 (division by provably nonzero divisor)
        -- Source location: division operator A / B
    end Divide;
end Bad_Division;
```

**Nonconforming Example — Rule 4 violation (nullable dereference).**

```ada
-- NONCONFORMING
package Bad_Deref is
    type Ptr is access Integer;

    public function Deref (P : Ptr) return Integer
    is (P.all);
    -- REJECTED: Ptr includes null; dereference of nullable access type
    -- Violated rule: D27 Rule 4 (not-null dereference)
    -- Source location: explicit dereference P.all
end Bad_Deref;
```

### 5.6.7 Example: Concurrent Program with Tasks and Channels

**Conforming Example.**

```ada
-- monitor.safe

with Sensors;

package Monitor is

    public type Alarm_Level is (None, Warning, Critical);

    channel Readings : Sensors.Reading capacity 32;
    channel Alarms   : Alarm_Level capacity 8;

    task Sampler with Priority = 10 is
    begin
        loop
            R : Sensors.Reading = Sensors.Get_Reading(0);
            Sent : Boolean = False;
            send Readings, R, Sent;
            if not Sent then
                delay 0.001;
            end if;
            delay 0.1;
        end loop;
    end Sampler;

    Threshold : Sensors.Reading = 3000;
    -- Owned by Evaluator (only task accessing it)

    task Evaluator with Priority = 5 is
    begin
        loop
            R : Sensors.Reading;
            receive Readings, R;
            if R > Threshold then
                Sent : Boolean = False;
                send Alarms, Critical, Sent;
                if not Sent then
                    delay 0.001;
                end if;
            elsif R > Threshold / 2 then
                -- D27 Rule 3(b): literal 2 is static nonzero
                Sent : Boolean = False;
                send Alarms, Warning, Sent;
                if not Sent then
                    delay 0.001;
                end if;
            end if;
        end loop;
    end Evaluator;

    public function Next_Alarm return Alarm_Level is
    begin
        Level : Alarm_Level;
        receive Alarms, Level;
        return Level;
        -- D27 proof: Alarm_Level is enumeration; no runtime error
    end Next_Alarm;

    -- Data race freedom: Threshold accessed only by Evaluator.
    -- Sampler accesses only Readings (channel) and Sensors package.
    -- Evaluator accesses Threshold, Readings, and Alarms.
    -- No shared mutable state between tasks.

end Monitor;
```
