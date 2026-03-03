--  Verified Emission Template: Wide Intermediate Arithmetic + Narrowing
--
--  Clause: SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p126:812b54a8
--  Clause: SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p127:d5d93439
--  Clause: SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p130:2289e5b2
--  Clause: SAFE@4aecf21:spec/05-assurance.md#5.3.6.p25:e8253bd7
--  Reference: compiler/translation_rules.md Section 8
--  Reference: tests/golden/golden_sensors.ada
--
--  Demonstrates the compiler emission pattern for wide intermediate
--  arithmetic. All integer operands are lifted to Long_Long_Integer
--  (Wide_Integer) before computation. Narrowing occurs at:
--    - Assignment (Narrow_Assignment)
--    - Return (Narrow_Return)
--
--  PO hooks exercised: Narrow_Return, Narrow_Assignment

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with Safe_Model; use Safe_Model;

package Template_Wide_Arithmetic
  with SPARK_Mode => On
is

   --  Application types: narrow target ranges for narrowing points.
   subtype Sensor_Value is Long_Long_Integer range 0 .. 1000;
   subtype Sensor_Count is Long_Long_Integer range 1 .. 10;

   --  Ghost range constants for PO hook calls.
   Sensor_Value_Range : constant Range64 := (Lo => 0, Hi => 1000)
     with Ghost;

   type Sensor_Array is array (1 .. 10) of Sensor_Value;

   --  Pattern 1: Accumulate-and-average.
   --  Sum is computed in Long_Long_Integer (wide intermediate).
   --  Division result is narrowed to Sensor_Value at return.
   function Average (Data : Sensor_Array) return Sensor_Value
     with Post => Average'Result >= 0
                  and then Average'Result <= 1000;

   --  Pattern 2: Simple addition with narrowing at assignment.
   --  Both operands are narrow, result is wide, narrowed on assignment.
   procedure Add_Clamped
     (A      : Sensor_Value;
      B      : Sensor_Value;
      Result :    out Sensor_Value)
     with Pre  => Long_Long_Integer (A) + Long_Long_Integer (B) <= 1000,
          Post => Result = A + B;

end Template_Wide_Arithmetic;
