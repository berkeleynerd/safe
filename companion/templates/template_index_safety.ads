--  Verified Emission Template: Safe Array Indexing
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.2.p131:30aba5f5
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.2.p132:8613ecf4
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.1.p12:99a94209
--  Reference: compiler/translation_rules.md Section 8
--  Reference: tests/golden/golden_sensors.ada
--
--  Demonstrates the compiler emission pattern for safe array indexing.
--  The index expression in an indexed component must be provably within
--  the array object's index bounds at compile time. The compiler emits:
--    1. Safe_Index ghost assertion (bounds check)
--    2. Narrow_Indexing ghost assertion (range narrowing for the index)
--
--  PO hooks exercised: Safe_Index, Narrow_Indexing

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with Safe_Model; use Safe_Model;

package Template_Index_Safety
  with SPARK_Mode => On
is

   --  Application types for array indexing patterns.
   subtype Data_Index is Integer range 1 .. 100;
   type Data_Array is array (Data_Index) of Integer;

   --  Ghost range constant for Narrow_Indexing PO hook.
   Data_Index_Range : constant Range64 := (Lo => 1, Hi => 100)
     with Ghost;

   --  Pattern 1: Direct index with compile-time known bounds.
   --  Index is a literal or constant within bounds.
   function Read_First (Arr : Data_Array) return Integer
     with Post => Read_First'Result = Arr (1);

   --  Pattern 2: Index from loop variable (bounds proved by loop range).
   function Sum (Arr : Data_Array) return Long_Long_Integer;

   --  Pattern 3: Computed index with precondition-based bounds proof.
   --  The caller guarantees the index is in bounds.
   function Read_At
     (Arr : Data_Array;
      Idx : Integer) return Integer
     with Pre => Idx >= 1 and then Idx <= 100;

   --  Pattern 4: Conditional indexing with runtime guard.
   --  The compiler emits a bounds check inside the guard.
   function Safe_Read_At
     (Arr     : Data_Array;
      Idx     : Integer;
      Default : Integer) return Integer;

end Template_Index_Safety;
