--  Verified Emission Template: Narrow Conversion (Type Conversion)
--  See template_narrow_conversion.ads for clause references.

pragma SPARK_Mode (On);

with Safe_Runtime; use Safe_Runtime;
with Safe_PO;      use Safe_PO;

package body Template_Narrow_Conversion
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Pattern 1: Percentage to Ratio conversion
   --
   --  Emission pattern from translation_rules.md Section 8.3:
   --    1. Lift Percentage operand to Wide_Integer
   --    2. Multiply in Wide_Integer (no overflow possible)
   --    3. Narrow via type conversion to Ratio
   --  The Narrow_Conversion hook fires at the type-conversion point.
   -------------------------------------------------------------------
   function Percent_To_Ratio (P : Percentage) return Ratio is
      Wide_Result : constant Wide_Integer :=
        Wide_Integer (P) * 100;
   begin
      pragma Assert
        (Wide_Result >= 0 and then Wide_Result <= 10_000);

      --  Narrowing point (type conversion):
      Narrow_Conversion
        (Long_Long_Integer (Wide_Result), Ratio_Range);

      return Ratio (Long_Long_Integer (Wide_Result));
   end Percent_To_Ratio;

   -------------------------------------------------------------------
   --  Pattern 2: Scale and convert with wide intermediate
   --
   --  Emission pattern:
   --    1. Lift Value and Scale to Wide_Integer
   --    2. Compute Value * Scale in wide intermediate
   --    3. Divide by 100
   --    4. Narrow via type conversion to Percentage
   --  The Narrow_Conversion hook fires at the type-conversion point.
   -------------------------------------------------------------------
   procedure Scale_And_Convert
     (Value  : Percentage;
      Scale  : Percentage;
      Result :    out Percentage)
   is
      Wide_Product : constant Wide_Integer :=
        Wide_Integer (Value) * Wide_Integer (Scale);
      Wide_Result  : constant Wide_Integer :=
        Wide_Product / 100;
   begin
      pragma Assert
        (Wide_Result >= 0 and then Wide_Result <= 100);

      --  Narrowing point (type conversion):
      Narrow_Conversion
        (Long_Long_Integer (Wide_Result), Percentage_Range);

      Result := Percentage (Long_Long_Integer (Wide_Result));
   end Scale_And_Convert;

   -------------------------------------------------------------------
   --  Pattern 3: Wide input narrowed by explicit precondition
   --
   --  Emission pattern:
   --    1. Caller-side range analysis establishes X in 0 .. 100
   --    2. Narrow via type conversion to Percentage
   --  Unlike Patterns 1-2 where narrow input types make the
   --  conversion trivially safe, here the Pre is essential:
   --  without it, X could be any Long_Long_Integer value and the
   --  Narrow_Conversion hook would be unprovable.
   -------------------------------------------------------------------
   procedure Narrow_From_Wide
     (X      : Long_Long_Integer;
      Result :    out Percentage)
   is
   begin
      --  Narrowing point (type conversion):
      Narrow_Conversion (X, Percentage_Range);

      Result := Percentage (X);
   end Narrow_From_Wide;

end Template_Narrow_Conversion;
