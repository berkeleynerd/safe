--  Verified Emission Template: Narrow Conversion (Type Conversion)
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p130:2289e5b2
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.6.p25:e8253bd7
--  Reference: compiler/translation_rules.md Section 8.3 (row 4)
--
--  Demonstrates narrowing at the type-conversion point — the fifth
--  narrowing point from Section 8.3 of translation_rules.md. This is
--  distinct from narrowing at assignment (Narrow_Assignment) or return
--  (Narrow_Return); here the Narrow_Conversion hook fires when a 64-bit
--  integer result is explicitly converted to a narrower target type.
--
--  PO hooks exercised: Narrow_Conversion

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with Safe_Model; use Safe_Model;

package Template_Narrow_Conversion
  with SPARK_Mode => On
is

   --  Application types: narrow targets for type-conversion narrowing.
   subtype Percentage is Long_Long_Integer range 0 .. 100;

   --  Ghost range constant for Percentage PO hook calls.
   Percentage_Range : constant Range64 :=
     (Lo => 0, Hi => 100)
     with Ghost;

   subtype Ratio is Long_Long_Integer range 0 .. 10_000;

   --  Ghost range constant for Ratio PO hook calls.
   Ratio_Range : constant Range64 :=
     (Lo => 0, Hi => 10_000)
     with Ghost;

   --  Pattern 1: Percentage to Ratio conversion.
   --  Convert Percentage (0..100) to Ratio (0..10_000) via P * 100.
   --  Type-conversion narrowing at return.
   function Percent_To_Ratio (P : Percentage) return Ratio
     with Post => Percent_To_Ratio'Result =
                  Long_Long_Integer (P) * 100;

   --  Pattern 2: Scale and convert with 64-bit integer arithmetic.
   --  Compute Value * Scale in Long_Long_Integer, divide by 100,
   --  narrow to Percentage via type conversion at assignment.
   procedure Scale_And_Convert
     (Value  : Percentage;
      Scale  : Percentage;
      Result :    out Percentage)
     with Post => Result = (Long_Long_Integer (Value)
                            * Long_Long_Integer (Scale)) / 100;

   --  Pattern 3: Long_Long_Integer input narrowed by explicit precondition.
   --  Demonstrates a conversion that would fail without a guard:
   --  Long_Long_Integer has range far exceeding Percentage, so the
   --  Pre is the only thing making the Narrow_Conversion hook provable.
   --  This is the realistic emitter pattern — the compiler's range
   --  analysis supplies the Pre bound that the proof then discharges.
   procedure Narrow_From_Wide
     (X      : Long_Long_Integer;
      Result :    out Percentage)
     with Pre  => X in 0 .. 100,
          Post => Result = Percentage (X);

end Template_Narrow_Conversion;
