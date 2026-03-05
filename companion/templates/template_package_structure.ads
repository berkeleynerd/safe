--  Verified Emission Template: Package Structure Emission
--
--  Clause: SAFE@468cf72:spec/03-single-file-packages.md
--          #3.2.6.p23:26dc2217
--  Clause: SAFE@468cf72:spec/03-single-file-packages.md
--          #3.2.6.p24:12e57227
--  Clause: SAFE@468cf72:spec/02-restrictions.md
--          #2.9.p140:7eeb1bb6
--  Reference: compiler/translation_rules.md Section 11
--
--  Demonstrates the .ads/.adb split pattern, opaque type
--  emission (type T is private in visible part, full record
--  in private part), and interleaved-declaration-to-declare-
--  block lowering.
--
--  PO hooks exercised: Narrow_Parameter

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with Safe_Model; use Safe_Model;

package Template_Package_Structure
  with SPARK_Mode => On
is

   --  Constrained subtypes keep overflow proofs tractable.
   subtype Meas_Value is Integer
     range -1_000_000 .. 1_000_000;
   subtype Meas_Scale is Integer range 1 .. 1_000;

   --  Opaque type: visible part declares private type.
   type Measurement is private;

   --  Ghost range constants for Narrow_Parameter PO hook.
   Value_Range : constant Range64 :=
     (Lo => -1_000_000, Hi => 1_000_000)
     with Ghost;
   Scale_Range : constant Range64 :=
     (Lo => 1, Hi => 1_000)
     with Ghost;

   --  Pattern 1: Constructor with parameter narrowing.
   --  The compiler emits Narrow_Parameter for each
   --  constrained formal.
   function Make
     (Value : Integer;
      Scale : Integer) return Measurement
     with Pre => Value >= -1_000_000
                 and then Value <= 1_000_000
                 and then Scale >= 1
                 and then Scale <= 1_000;

   --  Pattern 2: Single declare block
   --  (interleaved declaration lowering).
   function Scaled_Value
     (M : Measurement) return Long_Long_Integer;

   --  Pattern 3: Nested declare blocks (2 levels).
   procedure Combine
     (A, B   : Measurement;
      Result : out Long_Long_Integer);

private

   --  Full record definition in private section.
   type Measurement is record
      Value : Meas_Value;
      Scale : Meas_Scale;
   end record;

end Template_Package_Structure;
