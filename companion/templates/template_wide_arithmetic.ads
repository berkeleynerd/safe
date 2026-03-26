--  Verified Emission Template: 64-Bit Integer Arithmetic + Narrowing
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126:812b54a8
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p130:2289e5b2
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.6.p25:e8253bd7
--  Reference: compiler/translation_rules.md Section 8
--  Reference: tests/golden/golden_sensors/
--
--  Demonstrates the compiler emission pattern for PR11.8 integer
--  arithmetic. Safe `integer` emits directly as `Long_Long_Integer`.
--  Narrowing occurs at:
--    - Assignment (Narrow_Assignment)
--    - Return (Narrow_Return)
--  No support-package lifting step remains in emitted Ada.
--
--  PO hooks exercised: Narrow_Return, Narrow_Assignment

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with Safe_Model; use Safe_Model;

package Template_Wide_Arithmetic
  with SPARK_Mode => On
is

   --  Application types: narrow targets for narrowing points.
   --  These represent the Ada types that Safe source types map to.
   subtype Sensor_Value is Long_Long_Integer range 0 .. 1000;

   --  Ghost range constant for PO hook calls.
   Sensor_Value_Range : constant Range64 :=
     (Lo => 0, Hi => 1000)
     with Ghost;

   type Sensor_Array is array (1 .. 10) of Sensor_Value;

   --  Pattern 1: Accumulate-and-average.
   --  Sum is computed in Long_Long_Integer.
   --  Division result is narrowed to Sensor_Value at return.
   function Average (Data : Sensor_Array) return Sensor_Value
     with Post => Average'Result >= 0
                  and then Average'Result <= 1000;

   --  Pattern 2: Simple addition with narrowing at assignment.
   --  Operands are evaluated directly in Long_Long_Integer, result narrowed on
   --  assignment back to Sensor_Value.
   procedure Add_Clamped
     (A      : Sensor_Value;
      B      : Sensor_Value;
      Result :    out Sensor_Value)
     with Pre  => Long_Long_Integer (A)
                  + Long_Long_Integer (B) <= 1000,
          Post => Result = A + B;

end Template_Wide_Arithmetic;
