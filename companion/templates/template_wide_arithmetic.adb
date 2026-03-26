--  Verified Emission Template: 64-Bit Integer Arithmetic + Narrowing
--  See template_wide_arithmetic.ads for clause references.

pragma SPARK_Mode (On);

with Safe_PO;      use Safe_PO;

package body Template_Wide_Arithmetic
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Pattern 1: Accumulate-and-average
   --
   --  Emission pattern from translation_rules.md Section 8:
   --    1. Convert each Sensor_Value to Long_Long_Integer
   --    2. Accumulate in Long_Long_Integer
   --    3. Divide (by nonzero literal 10)
   --    4. Narrow the result at the return point
   -------------------------------------------------------------------
   function Average
     (Data : Sensor_Array) return Sensor_Value
   is
      Sum : Long_Long_Integer := 0;
   begin
      for I in 1 .. 10 loop
         --  Loop invariant: Sum tracks accumulated values.
         --  Each Data element is in 0..1000, so after I
         --  iterations Sum is in 0 .. I * 1000.
         pragma Loop_Invariant (Sum >= 0);
         pragma Loop_Invariant
           (Sum <= Long_Long_Integer (I - 1) * 1000);

         Sum := Sum + Long_Long_Integer (Data (I));
      end loop;

      --  Post-loop: Sum is in 0 .. 10_000.
      pragma Assert (Sum >= 0 and then Sum <= 10_000);

      --  Division by nonzero literal 10.
      --  Result is in 0 .. 1000 = Sensor_Value range.
      declare
         Wide_Result : constant Long_Long_Integer := Sum / 10;
      begin
         pragma Assert
           (Wide_Result >= 0 and then Wide_Result <= 1000);

         Narrow_Return (Wide_Result, Sensor_Value_Range);

         return Sensor_Value (Wide_Result);
      end;
   end Average;

   -------------------------------------------------------------------
   --  Pattern 2: Simple addition with narrowing at assignment
   --
   --  Emission pattern:
   --    1. Convert A and B to Long_Long_Integer
   --    2. Compute A + B in 64-bit integer arithmetic
   --    3. Narrow at assignment to Result
   -------------------------------------------------------------------
   procedure Add_Clamped
     (A      : Sensor_Value;
      B      : Sensor_Value;
      Result :    out Sensor_Value)
   is
      Wide_Sum : constant Long_Long_Integer :=
        Long_Long_Integer (A) + Long_Long_Integer (B);
   begin
      Narrow_Assignment (Wide_Sum, Sensor_Value_Range);

      Result := Sensor_Value (Wide_Sum);
   end Add_Clamped;

end Template_Wide_Arithmetic;
