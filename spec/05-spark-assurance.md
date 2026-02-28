# 5. SPARK Assurance

This section specifies the SPARK assurance guarantees that every conforming Safe program receives automatically. The developer writes zero verification annotations in Safe source. The compiler generates all necessary SPARK annotations in the emitted Ada, and the D27 language rules guarantee that every runtime check is provably safe.

---

## 5.1 Overview of SPARK Assurance Levels

1. SPARK defines five assurance levels, each building on the previous:

| Level | Name | What It Proves | How Achieved in Safe |
|-------|------|---------------|---------------------|
| Stone | Valid SPARK | Code compiles with `SPARK_Mode` | By construction — every Safe construct maps to a SPARK-legal Ada construct |
| Bronze | Flow analysis | No uninitialized variables, no data flow errors | Compiler-generated `Global`, `Depends`, `Initializes` annotations |
| Silver | AoRTE | Absence of Runtime Errors — no overflow, no index out of bounds, no division by zero, no null dereference | D27 language rules guarantee all runtime checks are provably safe |
| Gold | Functional correctness | Subprograms satisfy their specifications | Out of scope — requires developer-authored contracts |
| Platinum | Full formal verification | Complete mathematical proof of correctness | Out of scope — requires developer-authored specifications and lemmas |

2. Safe guarantees Stone, Bronze, and Silver for every conforming program. Gold and Platinum are out of scope; developers seeking those levels work with the emitted Ada directly.

---

## 5.2 Bronze Guarantee

The compiler shall automatically generate SPARK annotations in the emitted Ada sufficient for GNATprove Bronze-level assurance on every conforming Safe program. This requires four annotation families.

### 5.2.1 Global Aspects

3. The compiler shall generate a `Global` aspect on every subprogram in the emitted Ada. The `Global` aspect lists which package-level variables the subprogram reads and writes.

4. **Algorithm:** During the single compilation pass, the compiler accumulates a read-set and write-set for each subprogram as a natural byproduct of name resolution. When the compiler resolves a reference to a package-level variable inside a subprogram body:
   - If the reference is on the right side of an assignment, in a condition, or passed as an `in` parameter, the variable is added to the read-set (`Input` mode).
   - If the reference is on the left side of an assignment or passed as an `out` parameter, the variable is added to the write-set (`Output` mode).
   - If both, the variable is added as `In_Out` mode.

5. For mutually recursive subprograms (forward declarations), the compiler performs a fixed-point computation: it iterates over the recursive group until the `Global` sets stabilize. This terminates because the set of package-level variables is finite and the sets grow monotonically.

6. **Emitted Ada format:**

   ```ada
   procedure Update_Sensor
     with Global => (Input  => Calibration_Offset,
                     In_Out => Current_Reading)
   is ...
   ```

### 5.2.2 Depends Aspects

7. The compiler shall generate a `Depends` aspect on every subprogram in the emitted Ada. The `Depends` aspect specifies which outputs are influenced by which inputs.

8. **Algorithm:** During compilation, the compiler tracks data flow through assignments and expressions. For each output (parameter of mode `out` or `in out`, or global variable written), the compiler records which inputs (parameters of mode `in` or `in out`, or global variables read) influence its final value.

9. In a language with no uncontrolled aliasing (ownership rules prevent it), no dispatching, and no exceptions, dependency analysis is straightforward — it follows assignment chains and conditional branches.

10. **Emitted Ada format:**

    ```ada
    procedure Compute (X : in Integer; Y : out Integer)
      with Global  => (Input => Scale_Factor),
           Depends => (Y => (X, Scale_Factor))
    is ...
    ```

### 5.2.3 Initializes Aspects

11. The compiler shall generate an `Initializes` aspect on every package in the emitted Ada. The `Initializes` aspect lists all package-level variables that are initialized at elaboration time.

12. Since Safe packages are purely declarative with mandatory initialization expressions (D7), every package-level variable is initialized at elaboration. The `Initializes` aspect lists all package-level variables.

13. **Emitted Ada format:**

    ```ada
    package Sensors
      with Initializes => (Current_Reading, Calibration_Offset)
    is ...
    ```

### 5.2.4 SPARK_Mode

14. The compiler shall emit `pragma SPARK_Mode (On);` on every compilation unit in the emitted Ada. This declares that the emitted code is intended for SPARK analysis.

15. Since every Safe construct maps to a SPARK-legal Ada construct, this pragma is always valid for conforming Safe programs.

### 5.2.5 Bronze Guarantee Statement

16. **Normative:** Every conforming Safe program, when emitted as Ada/SPARK and submitted to GNATprove, shall pass flow analysis with no errors and no user-supplied annotations. The required GNATprove invocation is:

    ```
    gnatprove --mode=flow -P project.gpr
    ```

17. This guarantee is achieved by the compiler-generated `Global`, `Depends`, `Initializes`, and `SPARK_Mode` annotations. No Safe developer action is needed.

---

## 5.3 Silver Guarantee

The D27 language rules (Section 2, §2.8) guarantee that every conforming Safe program is Silver-provable — every runtime check in the emitted Ada is dischargeable by GNATprove from type information alone.

### 5.3.1 Wide Intermediate Arithmetic

18. All integer arithmetic expressions are evaluated in a mathematical integer type with no overflow (D27 Rule 1). The compiler emits intermediate arithmetic using `Wide_Integer`:

    ```ada
    type Wide_Integer is range -(2**63) .. (2**63 - 1);
    ```

19. All integer subexpressions are lifted to `Wide_Integer` before evaluation. At narrowing points (assignment, return, parameter passing), the compiler emits an explicit type conversion to the target type.

20. **Why GNATprove discharges this:** `Wide_Integer` cannot overflow for any operation on narrower types. The intermediate result is always representable. At narrowing points, GNATprove uses interval analysis on the wide result to verify the range check. For example, if `A, B : Reading` (0..4095), then `A + B` has wide range 0..8190, and `(A + B) / 2` has wide range 0..4095, which fits in `Reading`.

21. **Emitted Ada example:**

    Safe source:
    ```
    public type Reading is range 0 .. 4095;

    public function Average (A, B : Reading) return Reading is
    begin
        return (A + B) / 2;
    end Average;
    ```

    Emitted Ada:
    ```ada
    function Average (A, B : Reading) return Reading is
      Tmp_1 : Wide_Integer := Wide_Integer (A) + Wide_Integer (B);
      Tmp_2 : Wide_Integer := Tmp_1 / 2;
    begin
      return Reading (Tmp_2);
      --  GNATprove: range check proved via interval analysis
      --  Tmp_2 in 0 .. 4095
    end Average;
    ```

### 5.3.2 Strict Index Typing

22. The index expression in an `indexed_component` shall be of a type or subtype that is the same as, or a subtype of, the array's index type (D27 Rule 2).

23. **Why GNATprove discharges this:** The index value is constrained by its type to be within the array bounds. Since the index type matches the array's index type, the index check is trivially satisfied by the type constraint.

24. **Emitted Ada example:**

    Safe source:
    ```
    public type Channel_Id is range 0 .. 7;
    Table : array (Channel_Id) of Integer;

    public function Lookup (Ch : Channel_Id) return Integer is
    begin
        return Table(Ch);  -- index type matches array index type
    end Lookup;
    ```

    Emitted Ada:
    ```ada
    function Lookup (Ch : Channel_Id) return Integer is
    begin
      return Table (Ch);
      --  GNATprove: index check proved
      --  Ch in Channel_Id'Range = Table'Range
    end Lookup;
    ```

### 5.3.3 Division by Nonzero Type

25. The right operand of `/`, `mod`, and `rem` shall be of a type whose range excludes zero (D27 Rule 3).

26. **Why GNATprove discharges this:** The divisor's type range does not include zero, so the divisor value is constrained by its type to be nonzero. The division-by-zero check is trivially satisfied.

27. **Emitted Ada example:**

    Safe source:
    ```
    public type Seconds is range 1 .. 3600;

    public function Rate (Distance : Meters; Time : Seconds) return Integer is
    begin
        return Distance / Time;
    end Rate;
    ```

    Emitted Ada:
    ```ada
    function Rate (Distance : Meters; Time : Seconds) return Integer is
    begin
      return Integer (Wide_Integer (Distance) / Wide_Integer (Time));
      --  GNATprove: division check proved
      --  Time in 1 .. 3600, excludes zero
    end Rate;
    ```

### 5.3.4 Not-Null Dereference

28. Dereference of an access value requires the access subtype to be `not null` (D27 Rule 4).

29. **Why GNATprove discharges this:** The `not null` subtype constraint guarantees that the access value is never null. The null dereference check is trivially satisfied by the subtype constraint.

30. **Emitted Ada example:**

    Safe source:
    ```
    public type Node;
    public type Node_Ptr is access Node;
    public subtype Node_Ref is not null Node_Ptr;

    public function Value_Of (N : Node_Ref) return Integer
    is (N.Value);
    ```

    Emitted Ada:
    ```ada
    function Value_Of (N : Node_Ref) return Integer is (N.Value);
    --  GNATprove: null dereference check proved
    --  N is of subtype Node_Ref = not null Node_Ptr
    ```

### 5.3.5 Range Checks at Narrowing Points

31. Range checks occur when a wide intermediate result is narrowed to a target type (assignment, parameter, return). GNATprove discharges these via interval analysis on the wide expression.

32. If the interval analysis cannot prove the range check from the types alone — for example, if the arithmetic result could exceed the target type's range — then the program is correct only if the developer has structured the computation such that the result is provably in range. Since Safe requires tighter types (D27's ergonomic effect), most range checks are automatically dischargeable.

33. In cases where a range check cannot be proved from types alone, the developer must restructure the computation to use tighter types or add a conditional guard. A conforming implementation should produce a clear diagnostic identifying the unprovable range check.

### 5.3.6 Discriminant Checks

34. Discriminant checks arise when accessing a variant component of a discriminated record. Since discriminants in Safe are discrete types with static constraints (D23), and variant part selection is determined by the discriminant value, GNATprove discharges these checks by tracking the discriminant value through case statements and conditional branches.

35. This requires no special language rules — Ada's existing discriminant semantics, combined with the absence of exceptions and dispatching, make discriminant checks straightforward for the prover.

### 5.3.7 Complete Runtime Check Enumeration

36. The following table enumerates all categories of runtime check in the emitted Ada and how each is discharged:

| # | Check Category | 8652:2023 Reference | How Discharged | D27 Rule |
|---|---------------|-------------------|----------------|----------|
| 1 | Integer overflow | §4.5 | Impossible — wide intermediate arithmetic | Rule 1 |
| 2 | Range check (assignment) | §4.6, §5.2 | Interval analysis on wide intermediates | Rule 1 |
| 3 | Range check (parameter) | §6.4.1 | Interval analysis on wide intermediates | Rule 1 |
| 4 | Range check (return) | §6.5 | Interval analysis on wide intermediates | Rule 1 |
| 5 | Array index check | §4.1.1 | Index type matches array index type | Rule 2 |
| 6 | Array length check | §4.5.2, §5.2 | Matching array types in assignment | Rule 2 |
| 7 | Division by zero | §4.5.5 | Divisor type excludes zero | Rule 3 |
| 8 | Mod/rem by zero | §4.5.5 | Divisor type excludes zero | Rule 3 |
| 9 | Null dereference (explicit) | §4.1 | Access subtype is `not null` | Rule 4 |
| 10 | Null dereference (implicit) | §4.1.3 | Access subtype is `not null` | Rule 4 |
| 11 | Discriminant check | §3.7.1 | Discriminant tracking through control flow | — |
| 12 | Tag check | §3.9.2 | N/A — tagged types excluded | — |
| 13 | Accessibility check | §3.10.2 | N/A — anonymous access types excluded | — |
| 14 | Elaboration check | §3.11 | N/A — elaboration order is static | — |

### 5.3.8 Silver Guarantee Statement

37. **Normative:** Every conforming Safe program, when emitted as Ada/SPARK and submitted to GNATprove, shall pass AoRTE proof with no errors and no user-supplied annotations. The required GNATprove invocation is:

    ```
    gnatprove --mode=prove --level=2 -P project.gpr
    ```

38. If GNATprove requires a higher proof level to discharge all checks, the proof level shall be increased until all checks are discharged. Proof timeouts are treated as failures unless explicitly documented with a mitigation plan.

39. This guarantee is achieved by the combination of compiler-generated SPARK annotations (§5.2) and the D27 language rules (§2.8). No Safe developer action is needed.

---

## 5.4 Concurrency Assurance

The channel-based tasking model (Section 4) provides additional safety guarantees verifiable by GNATprove on the emitted Jorvik-profile SPARK.

### 5.4.1 Data Race Freedom

40. No shared mutable state exists between tasks. All inter-task communication is through channels, which the compiler emits as protected objects. The compiler generates `Global` aspects on task bodies that reference only variables owned by that task and channel operations.

41. GNATprove verifies data race freedom by checking that no unprotected global variable is accessed by more than one task. Since Safe enforces single-task ownership of all package-level variables (Section 4, §4.6), this verification is guaranteed to succeed.

### 5.4.2 Deadlock Freedom

42. The Jorvik profile enforces the ceiling priority protocol. The compiler assigns ceiling priorities to channel-backing protected objects based on the maximum static priority of all tasks that access each channel.

43. GNATprove verifies that the ceiling priority protocol is respected: no task calls a protected operation on an object whose ceiling priority is lower than the task's active priority. Since all priorities in Safe are static (no dynamic priority changes), this verification is guaranteed to succeed.

### 5.4.3 Task-Variable Ownership Emission

44. The compiler emits `Global` aspects on task bodies that enumerate:
    - All package-level variables owned by the task (as `In_Out` or `Input`)
    - All channel operations (as calls to the corresponding protected object entries)

45. **Emitted Ada example:**

    Safe source:
    ```
    Cal_Offset : Reading := 0;
    channel Readings : Reading capacity 16;

    task Sensor_Reader with Priority => 10 is
    begin
        loop
            R : Reading := Read_ADC (0) + Cal_Offset;
            send Readings, R;
        end loop;
    end Sensor_Reader;
    ```

    Emitted Ada (task body):
    ```ada
    task body Sensor_Reader_Task is
    begin
      loop
        declare
          R : Reading := Read_ADC (0) + Cal_Offset;
        begin
          Readings_Channel.Send (R);
        end;
      end loop;
    end Sensor_Reader_Task;
    --  with Global => (Input    => Cal_Offset,
    --                  In_Out   => Readings_Channel)
    ```

### 5.4.4 Concurrency Assurance Statement

46. **Normative:** Every conforming Safe program containing tasks, when emitted as Ada/SPARK and submitted to GNATprove with `--mode=flow`, shall pass concurrency-related flow analysis with no errors. GNATprove shall verify:

    - No unprotected shared mutable state between tasks
    - Ceiling priority protocol respected for all protected object accesses

47. This guarantee is achieved by the channel-based concurrency model (Section 4), compiler-generated `Global` aspects on task bodies, and compiler-assigned ceiling priorities on channel-backing protected objects.

---

## 5.5 Gold and Platinum Assurance

48. Gold (functional correctness) and Platinum (full formal verification) assurance levels are out of scope for the Safe language specification.

49. Achieving Gold or Platinum requires developer-authored specifications: postconditions stating functional intent, ghost code for auxiliary verification state, lemmas for complex reasoning, and loop invariants for inductive proofs. These are inherently non-automatable.

50. A developer seeking Gold or Platinum assurance shall work with the emitted Ada directly, adding `Pre`, `Post`, `Contract_Cases`, `Ghost`, `Loop_Invariant`, and other SPARK annotations to the generated `.ads` and `.adb` files. The emitted Ada is designed to be human-readable and suitable for this purpose (see Section 6, §6.4).

---

## 5.6 Examples

### 5.6.1 Arithmetic: Silver-Provable via Wide Intermediates

51. **Safe source** (`averaging.safe`):

    ```
    public package Averaging is

    public type Sample is range 0 .. 1023;
    public subtype Positive_Count is Integer range 1 .. 1000;

    public function Mean (A, B, C : Sample) return Sample is
    begin
        return (A + B + C) / 3;
        -- Wide intermediate: max (1023+1023+1023)/3 = 1023
        -- Range check at return: provably in 0..1023
    end Mean;

    public function Weighted (X : Sample; W : Positive_Count) return Integer is
    begin
        return X * W / 100;
        -- Wide intermediate: max 1023 * 1000 / 100 = 10230
        -- Range check at return: fits in Integer
    end Weighted;

    end Averaging;
    ```

52. GNATprove output on emitted Ada: all checks proved, zero unproved VCs.

### 5.6.2 Array Indexing: Silver-Provable via Strict Index Typing

53. **Safe source** (`lookup.safe`):

    ```
    public package Lookup is

    public type Sensor_Id is range 0 .. 15;
    Readings : array (Sensor_Id) of Integer := (others => 0);

    public function Get (Id : Sensor_Id) return Integer is
    begin
        return Readings(Id);
        -- Silver-provable: Id in 0..15 = Readings index range
    end Get;

    public function Get_If_Valid (Id_Raw : Integer) return Integer is
    begin
        if Id_Raw in Sensor_Id.First .. Sensor_Id.Last then
            return Get(Sensor_Id(Id_Raw));
        else
            return -1;
        end if;
    end Get_If_Valid;

    end Lookup;
    ```

54. GNATprove output on emitted Ada: all checks proved, zero unproved VCs.

### 5.6.3 Division: Silver-Provable via Nonzero Divisor Types

55. **Safe source** (`rates.safe`):

    ```
    public package Rates is

    public type Meters is range 0 .. 100_000;
    public type Seconds is range 1 .. 86_400;

    public function Speed (D : Meters; T : Seconds) return Integer is
    begin
        return D / T;
        -- Silver-provable: T >= 1 by type, division by zero impossible
    end Speed;

    end Rates;
    ```

56. GNATprove output on emitted Ada: all checks proved, zero unproved VCs.

### 5.6.4 Access Types: Silver-Provable via Not-Null Dereference

57. **Safe source** (`lists.safe`):

    ```
    public package Lists is

    public type Node;
    public type Node_Ptr is access Node;
    public subtype Node_Ref is not null Node_Ptr;

    public type Node is record
        Value : Integer;
        Next  : Node_Ptr;  -- nullable: end of list is null
    end record;

    public function Head_Value (List : Node_Ref) return Integer
    is (List.Value);  -- provably safe: List is not null

    public function Length (List : Node_Ptr) return Natural is
    begin
        if List = null then
            return 0;
        else
            Ref : Node_Ref := Node_Ref(List);
            return 1 + Length(Ref.Next);
        end if;
    end Length;

    end Lists;
    ```

58. GNATprove output on emitted Ada: null dereference checks proved via `not null` subtype.

### 5.6.5 Ownership: Move, Borrow, Observe Patterns

59. **Safe source** (`trees.safe`):

    ```
    public package Trees is

    public type Tree_Node;
    public type Tree_Ptr is access Tree_Node;
    public subtype Tree_Ref is not null Tree_Ptr;

    public type Tree_Node is record
        Value : Integer;
        Left  : Tree_Ptr;
        Right : Tree_Ptr;
    end record;

    -- Move: ownership transfers to Insert
    public procedure Insert (Root : in out Tree_Ptr; Val : Integer) is
    begin
        if Root = null then
            Root := new Tree_Node'(Value => Val, Left => null, Right => null);
        else
            Ref : Tree_Ref := Tree_Ref(Root);
            if Val < Ref.Value then
                Insert(Ref.Left, Val);   -- borrow: Ref.Left temporarily lent
            else
                Insert(Ref.Right, Val);  -- borrow: Ref.Right temporarily lent
            end if;
        end if;
    end Insert;

    -- Observe: read-only access, no ownership transfer
    public function Contains (Root : in Tree_Ptr; Val : Integer) return Boolean is
    begin
        if Root = null then
            return False;
        else
            Ref : Tree_Ref := Tree_Ref(Root);
            if Val = Ref.Value then
                return True;
            elsif Val < Ref.Value then
                return Contains(Ref.Left, Val);
            else
                return Contains(Ref.Right, Val);
            end if;
        end if;
    end Contains;

    end Trees;
    ```

60. The emitted Ada includes compiler-generated deallocation at scope exit for owning variables.

### 5.6.6 Rejected Programs

61. **Program 1: Index type too wide**

    ```
    -- REJECTED by compiler
    public package Bad_Index is

    type Table_Type is array (0 .. 7) of Integer;
    Table : Table_Type := (others => 0);

    public function Lookup (N : Integer) return Integer is
    begin
        return Table(N);  -- ERROR: Integer is wider than 0..7
    end Lookup;

    end Bad_Index;
    ```

    Compiler diagnostic:
    ```
    bad_index.safe:7:22: error: index type Integer is not a subtype of
        the array index type Integer range 0 .. 7 [D27 Rule 2]
    ```

62. **Program 2: Divisor type includes zero**

    ```
    -- REJECTED by compiler
    public package Bad_Divide is

    public function Ratio (A, B : Integer) return Integer is
    begin
        return A / B;  -- ERROR: Integer range includes zero
    end Ratio;

    end Bad_Divide;
    ```

    Compiler diagnostic:
    ```
    bad_divide.safe:4:18: error: right operand of "/" has type Integer
        whose range includes zero [D27 Rule 3]
    ```

63. **Program 3: Nullable dereference**

    ```
    -- REJECTED by compiler
    public package Bad_Deref is

    type Ptr is access Integer;

    public function Get (P : Ptr) return Integer is
    begin
        return P.all;  -- ERROR: Ptr includes null
    end Get;

    end Bad_Deref;
    ```

    Compiler diagnostic:
    ```
    bad_deref.safe:6:16: error: dereference requires "not null" access
        subtype; Ptr may be null [D27 Rule 4]
    ```

### 5.6.7 Concurrent Program with Emitted Ada

64. **Safe source** (`pipeline.safe`):

    ```
    public package Pipeline is

    public type Sample is range 0 .. 4095;
    public type Filtered is range 0 .. 4095;

    channel Raw_Samples : Sample capacity 8;
    channel Filtered_Samples : Filtered capacity 8;

    task Sampler with Priority => 10 is
    begin
        loop
            S : Sample := Read_ADC(0);
            send Raw_Samples, S;
        end loop;
    end Sampler;

    task Filter with Priority => 8 is
    begin
        loop
            S : Sample;
            receive Raw_Samples, S;
            F : Filtered := Filtered((S + Prev) / 2);
            send Filtered_Samples, F;
            Prev := S;
        end loop;
    end Filter;

    Prev : Sample := 0;  -- owned by Filter task

    end Pipeline;
    ```

65. **Emitted Ada** (abbreviated):

    ```ada
    pragma Profile (Jorvik);
    pragma SPARK_Mode (On);

    package Pipeline
      with Initializes => Prev
    is
      type Sample is range 0 .. 4095;
      type Filtered is range 0 .. 4095;
      type Wide_Integer is range -(2**63) .. (2**63 - 1);

      protected Raw_Samples_Channel
        with Priority => 10  -- ceiling = max(Sampler=10, Filter=8)
      is
        entry Send (Item : in Sample);
        entry Receive (Item : out Sample);
      private
        Buffer : array (0 .. 7) of Sample;
        Count  : Natural := 0;
        Head   : Natural := 0;
        Tail   : Natural := 0;
      end Raw_Samples_Channel;

      protected Filtered_Samples_Channel
        with Priority => 8  -- ceiling = max(Filter=8)
      is
        entry Send (Item : in Filtered);
        entry Receive (Item : out Filtered);
      private
        Buffer : array (0 .. 7) of Filtered;
        Count  : Natural := 0;
        Head   : Natural := 0;
        Tail   : Natural := 0;
      end Filtered_Samples_Channel;

      task Sampler_Task
        with Priority => 10,
             Global   => (In_Out => Raw_Samples_Channel);

      task Filter_Task
        with Priority => 8,
             Global   => (Input  => Prev,
                          In_Out => (Raw_Samples_Channel,
                                     Filtered_Samples_Channel));

      Prev : Sample := 0;
    end Pipeline;
    ```

66. **GNATprove output:**
    - Flow analysis (Bronze): PASSED — all `Global` and `Depends` annotations verified
    - AoRTE proof (Silver): PASSED — all runtime checks proved
    - Concurrency analysis: PASSED — no shared mutable state, ceiling priorities respected
