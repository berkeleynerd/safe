--  Safe Language Annotated SPARK Companion
--  Source commit: 468cf72332724b04b7c193b4d2a3b02f1584125d
--  Generated: 2026-03-02
--  Generator: spec2spark v0.1.0
--  Clauses: 2.8.1-2.8.5 (D27 Rules 1-5), 2.3.2-2.3.4a (Ownership),
--           4.2-4.3 (Channels), 4.5 (Task-Variable Ownership),
--           5.3.2-5.3.7a (Silver AoRTE), 5.4.1 (Race-freedom)
--  Assumptions:
--    - Proof-only procedures have minimal (null) bodies.
--    - Procedures with out parameters assign the computed value.
--    - Ghost procedures are never executed at runtime.

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package body Safe_PO is

   --========================================================================
   --  D27 Rule 1 -- Range Analysis
   --========================================================================

   ---------------------------------------------------------------------------
   --  Safe_Div
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126:812b54a8
   ---------------------------------------------------------------------------
   procedure Safe_Div
     (X : Long_Long_Integer;
      Y : Long_Long_Integer;
      R : out Long_Long_Integer)
   is
   begin
      R := X / Y;
   end Safe_Div;

   ---------------------------------------------------------------------------
   --  Narrow_Assignment
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   ---------------------------------------------------------------------------
   procedure Narrow_Assignment
     (V      : Long_Long_Integer;
      Target : Range64)
   is
      pragma Unreferenced (V, Target);
   begin
      null;
   end Narrow_Assignment;

   ---------------------------------------------------------------------------
   --  Narrow_Parameter
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   ---------------------------------------------------------------------------
   procedure Narrow_Parameter
     (V     : Long_Long_Integer;
      Param : Range64)
   is
      pragma Unreferenced (V, Param);
   begin
      null;
   end Narrow_Parameter;

   ---------------------------------------------------------------------------
   --  Narrow_Return
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   ---------------------------------------------------------------------------
   procedure Narrow_Return
     (V            : Long_Long_Integer;
      Return_Range : Range64)
   is
      pragma Unreferenced (V, Return_Range);
   begin
      null;
   end Narrow_Return;

   ---------------------------------------------------------------------------
   --  Narrow_Indexing
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   ---------------------------------------------------------------------------
   procedure Narrow_Indexing
     (V           : Long_Long_Integer;
      Index_Range : Range64)
   is
      pragma Unreferenced (V, Index_Range);
   begin
      null;
   end Narrow_Indexing;

   ---------------------------------------------------------------------------
   --  Narrow_Conversion
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   ---------------------------------------------------------------------------
   procedure Narrow_Conversion
     (V            : Long_Long_Integer;
      Target_Range : Range64)
   is
      pragma Unreferenced (V, Target_Range);
   begin
      null;
   end Narrow_Conversion;

   --========================================================================
   --  D27 Rule 2 -- Index Safety
   --========================================================================

   ---------------------------------------------------------------------------
   --  Safe_Index
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.2.p131:30aba5f5
   ---------------------------------------------------------------------------
   procedure Safe_Index
     (Arr_Lo : Long_Long_Integer;
      Arr_Hi : Long_Long_Integer;
      Idx    : Long_Long_Integer)
   is
   begin
      null;
   end Safe_Index;

   --========================================================================
   --  D27 Rule 3 -- Division by Zero
   --========================================================================

   ---------------------------------------------------------------------------
   --  Nonzero
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
   ---------------------------------------------------------------------------
   procedure Nonzero
     (V : Long_Long_Integer)
   is
   begin
      null;
   end Nonzero;

   ---------------------------------------------------------------------------
   --  Safe_Mod
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
   ---------------------------------------------------------------------------
   procedure Safe_Mod
     (X : Long_Long_Integer;
      Y : Long_Long_Integer;
      R : out Long_Long_Integer)
   is
   begin
      R := X mod Y;
   end Safe_Mod;

   ---------------------------------------------------------------------------
   --  Safe_Rem
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
   ---------------------------------------------------------------------------
   procedure Safe_Rem
     (X : Long_Long_Integer;
      Y : Long_Long_Integer;
      R : out Long_Long_Integer)
   is
   begin
      R := X rem Y;
   end Safe_Rem;

   --========================================================================
   --  D27 Rule 4 -- Not-Null
   --========================================================================

   ---------------------------------------------------------------------------
   --  Not_Null_Ptr
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.4.p136:fa5e94b7
   ---------------------------------------------------------------------------
   procedure Not_Null_Ptr
     (Is_Null : Boolean)
   is
   begin
      null;
   end Not_Null_Ptr;

   ---------------------------------------------------------------------------
   --  Safe_Deref
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.4.p136:fa5e94b7
   ---------------------------------------------------------------------------
   procedure Safe_Deref
     (Is_Null : Boolean)
   is
   begin
      null;
   end Safe_Deref;

   --========================================================================
   --  D27 Rule 5 -- Floating-Point Safety
   --========================================================================

   ---------------------------------------------------------------------------
   --  FP_Not_NaN
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139d:56f1f36b
   ---------------------------------------------------------------------------
   procedure FP_Not_NaN
     (V : Long_Float)
   is
   begin
      null;
   end FP_Not_NaN;

   ---------------------------------------------------------------------------
   --  FP_Not_Infinity
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139d:56f1f36b
   ---------------------------------------------------------------------------
   procedure FP_Not_Infinity
     (V : Long_Float)
   is
   begin
      null;
   end FP_Not_Infinity;

   ---------------------------------------------------------------------------
   --  FP_Safe_Div
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139:d50bc714
   ---------------------------------------------------------------------------
   procedure FP_Safe_Div
     (X : Long_Float;
      Y : Long_Float;
      R : out Long_Float)
   is
   begin
      R := X / Y;
      pragma Annotate
        (GNATprove, Intentional,
         "float overflow check might fail",
         "A-05: The compiler ensures the result is finite at " &
         "narrowing points via range analysis.  See " &
         "companion/assumptions.yaml A-05.");
   end FP_Safe_Div;

   --========================================================================
   --  Ownership Proof Obligations
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Not_Moved
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96c:0b45de01
   ---------------------------------------------------------------------------
   procedure Check_Not_Moved
     (State : Ownership_State)
   is
      pragma Unreferenced (State);
   begin
      null;
   end Check_Not_Moved;

   ---------------------------------------------------------------------------
   --  Check_Owned_For_Move
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96a:0eaf48aa
   ---------------------------------------------------------------------------
   procedure Check_Owned_For_Move
     (State : Ownership_State)
   is
      pragma Unreferenced (State);
   begin
      null;
   end Check_Owned_For_Move;

   ---------------------------------------------------------------------------
   --  Check_Borrow_Exclusive
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.3.p99b:47108b45
   ---------------------------------------------------------------------------
   procedure Check_Borrow_Exclusive
     (State : Ownership_State)
   is
      pragma Unreferenced (State);
   begin
      null;
   end Check_Borrow_Exclusive;

   ---------------------------------------------------------------------------
   --  Check_Observe_Shared
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.4a.p102a:5bc5ab8b
   ---------------------------------------------------------------------------
   procedure Check_Observe_Shared
     (State : Ownership_State)
   is
      pragma Unreferenced (State);
   begin
      null;
   end Check_Observe_Shared;

   --========================================================================
   --  Channel Proof Obligations
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Channel_Not_Full
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p27:ef0ce6bd
   ---------------------------------------------------------------------------
   procedure Check_Channel_Not_Full
     (Length   : Natural;
      Capacity : Natural)
   is
      pragma Unreferenced (Length, Capacity);
   begin
      null;
   end Check_Channel_Not_Full;

   ---------------------------------------------------------------------------
   --  Check_Channel_Not_Empty
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p28:ea6bd13c
   ---------------------------------------------------------------------------
   procedure Check_Channel_Not_Empty
     (Length : Natural)
   is
      pragma Unreferenced (Length);
   begin
      null;
   end Check_Channel_Not_Empty;

   ---------------------------------------------------------------------------
   --  Check_Channel_Capacity_Positive
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p15:b5b29b0e
   ---------------------------------------------------------------------------
   procedure Check_Channel_Capacity_Positive
     (Capacity : Natural)
   is
      pragma Unreferenced (Capacity);
   begin
      null;
   end Check_Channel_Capacity_Positive;

   --========================================================================
   --  Race-Freedom Proof Obligations
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Exclusive_Ownership
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99
   ---------------------------------------------------------------------------
   procedure Check_Exclusive_Ownership
     (Var_Id  : Var_Id_Range;
      Task_Id : Task_Id_Range;
      Map     : Task_Var_Map)
   is
      pragma Unreferenced (Var_Id, Task_Id, Map);
   begin
      null;
   end Check_Exclusive_Ownership;

   --========================================================================
   --  Discriminant Check
   --========================================================================

   ---------------------------------------------------------------------------
   --  Check_Discriminant
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.6.p139f
   ---------------------------------------------------------------------------
   procedure Check_Discriminant
     (Actual   : Boolean;
      Expected : Boolean)
   is
      pragma Unreferenced (Actual, Expected);
   begin
      null;
   end Check_Discriminant;

end Safe_PO;
