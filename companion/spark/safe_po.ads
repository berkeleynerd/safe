--  Safe Language Annotated SPARK Companion
--  Source commit: 468cf72332724b04b7c193b4d2a3b02f1584125d
--  Generated: 2026-03-02
--  Generator: spec2spark v0.1.0
--  Clauses: 2.8.1-2.8.5 (D27 Rules 1-5), 2.3.2-2.3.4a (Ownership),
--           4.2-4.3 (Channels), 4.5 (Task-Variable Ownership),
--           5.3.2-5.3.7a (Silver AoRTE), 5.4.1 (Race-freedom)
--  Assumptions:
--    - Implementation provides at least 64-bit intermediate evaluation
--    - Target hardware supports IEEE 754 non-trapping mode
--    - Static range analysis is sound
--    - Channel implementation correctly serializes access

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with Safe_Model; use Safe_Model;

package Safe_PO is

   --========================================================================
   --  D27 Rule 1 -- Range Analysis (Wide Arithmetic, No Integer Overflow)
   --
   --  Every integer arithmetic expression is evaluated in a mathematical
   --  integer type. Intermediate results cannot overflow. Range checks occur
   --  only at narrowing points: assignment, parameter passing, return,
   --  type conversion, and type annotation.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Safe_Div: Division with provably nonzero divisor.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126:812b54a8
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.1.p12:99a94209
   ---------------------------------------------------------------------------
   procedure Safe_Div
     (X : Long_Long_Integer;
      Y : Long_Long_Integer;
      R : out Long_Long_Integer)
   with Pre  => Y /= 0
                and then not (X = Long_Long_Integer'First and then Y = -1),
        Post => R = X / Y;

   ---------------------------------------------------------------------------
   --  Narrow_Assignment: Range check at assignment narrowing point.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p130:2289e5b2
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.6.p25:e8253bd7
   ---------------------------------------------------------------------------
   procedure Narrow_Assignment
     (V      : Long_Long_Integer;
      Target : Range64)
   with Pre => Is_Valid_Range (Target)
               and then Contains (Target, V),
        Ghost;

   ---------------------------------------------------------------------------
   --  Narrow_Parameter: Range check at parameter passing narrowing point.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p130:2289e5b2
   ---------------------------------------------------------------------------
   procedure Narrow_Parameter
     (V     : Long_Long_Integer;
      Param : Range64)
   with Pre => Is_Valid_Range (Param)
               and then Contains (Param, V),
        Ghost;

   ---------------------------------------------------------------------------
   --  Narrow_Return: Range check at function return narrowing point.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.6.p25:e8253bd7
   ---------------------------------------------------------------------------
   procedure Narrow_Return
     (V            : Long_Long_Integer;
      Return_Range : Range64)
   with Pre => Is_Valid_Range (Return_Range)
               and then Contains (Return_Range, V),
        Ghost;

   ---------------------------------------------------------------------------
   --  Narrow_Indexing: Range check at array indexing narrowing point.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.2.p131:30aba5f5
   ---------------------------------------------------------------------------
   procedure Narrow_Indexing
     (V           : Long_Long_Integer;
      Index_Range : Range64)
   with Pre => Is_Valid_Range (Index_Range)
               and then Contains (Index_Range, V),
        Ghost;

   ---------------------------------------------------------------------------
   --  Narrow_Conversion: Range check at type conversion narrowing point.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p130:2289e5b2
   ---------------------------------------------------------------------------
   procedure Narrow_Conversion
     (V            : Long_Long_Integer;
      Target_Range : Range64)
   with Pre => Is_Valid_Range (Target_Range)
               and then Contains (Target_Range, V),
        Ghost;

   --========================================================================
   --  D27 Rule 2 -- Index Safety
   --
   --  The index expression in an indexed component shall be provably within
   --  the array object's index bounds at compile time.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Safe_Index: Index expression provably within array bounds.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.2.p131:30aba5f5
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.2.p132:8613ecf4
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.1.p12:99a94209
   ---------------------------------------------------------------------------
   procedure Safe_Index
     (Arr_Lo : Long_Long_Integer;
      Arr_Hi : Long_Long_Integer;
      Idx    : Long_Long_Integer)
   with Pre => Arr_Lo <= Arr_Hi
               and then Idx >= Arr_Lo
               and then Idx <= Arr_Hi,
        Ghost;

   --========================================================================
   --  D27 Rule 3 -- Division by Zero
   --
   --  The right operand of /, mod, and rem shall be provably nonzero.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Nonzero: Divisor is provably nonzero.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p134:90a17a3b
   ---------------------------------------------------------------------------
   procedure Nonzero
     (V : Long_Long_Integer)
   with Pre => V /= 0,
        Ghost;

   ---------------------------------------------------------------------------
   --  Safe_Mod: Modulo with provably nonzero divisor.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
   ---------------------------------------------------------------------------
   procedure Safe_Mod
     (X : Long_Long_Integer;
      Y : Long_Long_Integer;
      R : out Long_Long_Integer)
   with Pre  => Y /= 0,
        Post => R = X mod Y;

   ---------------------------------------------------------------------------
   --  Safe_Rem: Remainder with provably nonzero divisor.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
   ---------------------------------------------------------------------------
   procedure Safe_Rem
     (X : Long_Long_Integer;
      Y : Long_Long_Integer;
      R : out Long_Long_Integer)
   with Pre  => Y /= 0,
        Post => R = X rem Y;

   --========================================================================
   --  D27 Rule 4 -- Not-Null
   --
   --  Dereference of an access value requires the access subtype to be
   --  not null. SPARK disallows access types in SPARK_Mode; we model
   --  null state with a Boolean flag.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Not_Null_Ptr: Access subtype excludes null at dereference.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.4.p136:fa5e94b7
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.1.p12:99a94209
   ---------------------------------------------------------------------------
   procedure Not_Null_Ptr
     (Is_Null : Boolean)
   with Pre => not Is_Null,
        Ghost;

   ---------------------------------------------------------------------------
   --  Safe_Deref: Dereference with not-null guarantee.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.4.p136:fa5e94b7
   ---------------------------------------------------------------------------
   procedure Safe_Deref
     (Is_Null : Boolean)
   with Pre => not Is_Null,
        Ghost;

   --========================================================================
   --  D27 Rule 5 -- Floating-Point Safety
   --
   --  IEEE 754 non-trapping arithmetic. NaN and infinity are permitted
   --  as intermediates but cannot survive narrowing points.
   --========================================================================

   ---------------------------------------------------------------------------
   --  FP_Not_NaN: Floating-point value is not NaN.
   --  NaN is the unique float value where V /= V.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139d:56f1f36b
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.7a.p28a:5936dbea
   ---------------------------------------------------------------------------
   procedure FP_Not_NaN
     (V : Long_Float)
   with Pre => V = V,
        Ghost;

   ---------------------------------------------------------------------------
   --  FP_Not_Infinity: Floating-point value is finite.
   --  Under IEEE 754, Long_Float'First <= V <= Long_Float'Last implies finite.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139b:5e20032b
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139d:56f1f36b
   ---------------------------------------------------------------------------
   procedure FP_Not_Infinity
     (V : Long_Float)
   with Pre => V = V
               and then V >= Long_Float'First
               and then V <= Long_Float'Last,
        Ghost;

   ---------------------------------------------------------------------------
   --  FP_Safe_Div: Floating-point division with nonzero, non-NaN divisor.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139:d50bc714
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139b:5e20032b
   ---------------------------------------------------------------------------
   procedure FP_Safe_Div
     (X : Long_Float;
      Y : Long_Float;
      R : out Long_Float)
   with Pre  => Y /= 0.0
                and then Y = Y
                and then X = X
                and then X >= Long_Float'First
                and then X <= Long_Float'Last
                and then Y >= Long_Float'First
                and then Y <= Long_Float'Last,
        Post => R = X / Y;

   --========================================================================
   --  Ownership Proof Obligations (Section 2.3)
   --
   --  These POs verify ownership state transitions and access legality.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Not_Moved: Verify the access value has not been moved.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96c:0b45de01
   ---------------------------------------------------------------------------
   procedure Check_Not_Moved
     (State : Ownership_State)
   with Pre => State /= Moved,
        Ghost;

   ---------------------------------------------------------------------------
   --  Check_Owned_For_Move: Verify the access value is owned before move.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96a:0eaf48aa
   ---------------------------------------------------------------------------
   procedure Check_Owned_For_Move
     (State : Ownership_State)
   with Pre => State = Owned,
        Ghost;

   ---------------------------------------------------------------------------
   --  Check_Borrow_Exclusive: Verify exclusive ownership before borrow.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.3.p99b:47108b45
   ---------------------------------------------------------------------------
   procedure Check_Borrow_Exclusive
     (State : Ownership_State)
   with Pre => State = Owned,
        Ghost;

   ---------------------------------------------------------------------------
   --  Check_Observe_Shared: Verify state allows observation.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.4a.p102a:5bc5ab8b
   ---------------------------------------------------------------------------
   procedure Check_Observe_Shared
     (State : Ownership_State)
   with Pre => State = Owned or else State = Observed,
        Ghost;

   --========================================================================
   --  Channel Proof Obligations (Sections 4.2 - 4.3)
   --
   --  These POs verify channel operation preconditions.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Channel_Not_Full: Channel has space for send.
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p27:ef0ce6bd
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p29:f792d704
   ---------------------------------------------------------------------------
   procedure Check_Channel_Not_Full
     (Length   : Natural;
      Capacity : Natural)
   with Pre => Length < Capacity,
        Ghost;

   ---------------------------------------------------------------------------
   --  Check_Channel_Not_Empty: Channel has data for receive.
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p28:ea6bd13c
   ---------------------------------------------------------------------------
   procedure Check_Channel_Not_Empty
     (Length : Natural)
   with Pre => Length > 0,
        Ghost;

   ---------------------------------------------------------------------------
   --  Check_Channel_Capacity_Positive: Channel capacity is at least 1.
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p15:b5b29b0e
   ---------------------------------------------------------------------------
   procedure Check_Channel_Capacity_Positive
     (Capacity : Natural)
   with Pre => Capacity > 0,
        Ghost;

   --========================================================================
   --  Race-Freedom Proof Obligations (Section 4.5)
   --
   --  These POs verify the task-variable exclusive ownership invariant.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Exclusive_Ownership: Verify single-task ownership of a variable.
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.4.1.p32:90d4f527
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.4.1.p33:0fc25399
   ---------------------------------------------------------------------------
   procedure Check_Exclusive_Ownership
     (Var_Id  : Var_Id_Range;
      Task_Id : Task_Id_Range;
      Map     : Task_Var_Map)
   with Pre => Task_Id /= No_Task
               and then (Map (Var_Id) = No_Task
                         or else Map (Var_Id) = Task_Id),
        Ghost;
   --  Verifies that Var_Id is either unowned (first access) or already
   --  owned by the same task. If a different task claims ownership, the
   --  precondition fails, corresponding to a data-race violation.

   --========================================================================
   --  Discriminant Check
   --
   --  Variant field access requires the discriminant to match the
   --  selected variant.  The compiler inserts a ghost assertion before
   --  each variant field access.
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Discriminant: Assert that the discriminant has the expected value
   --  before accessing a variant field.
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.6.p139f
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.12.p148
   ---------------------------------------------------------------------------
   procedure Check_Discriminant
     (Actual   : Boolean;
      Expected : Boolean)
   with Pre => Actual = Expected,
        Ghost;
   --  Verifies that the discriminant value (Actual) matches the variant
   --  being accessed (Expected).  A conditional branch on the discriminant
   --  establishes Actual = Expected within that branch; the fact is
   --  invalidated by assignment or in-out calls on the discriminated object.

end Safe_PO;
