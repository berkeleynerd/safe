--  Verified Emission Template: Discriminant-Check Safety on Result Records
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.6.p139f
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.12.p148
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.1.p12:99a94209
--  Reference: compiler/translation_rules.md Section 7
--
--  Demonstrates the compiler emission pattern for discriminant-check
--  safety on discriminated result records:
--    1. Conditional branch on discriminant establishes the variant
--    2. Variant field access is legal only within the established branch
--    3. Assignment to the record invalidates the discriminant fact
--    4. Re-guarding after mutation re-establishes the fact
--    5. GNATprove verifies statically that discriminant checks pass
--
--  This closes the last gap in the §2.8.6 proof-discharge table:
--  the "Discriminant" row.
--
--  PO hooks exercised: Check_Discriminant

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Discriminant_Result
  with SPARK_Mode => On
is

   --  Model of a discriminated Result record (§2.12 ¶146).
   --  OK = True  -> Value field is active.
   --  OK = False -> Error_Code field is active.
   type Result_Model (OK : Boolean := False) is record
      case OK is
         when True  => Value      : Integer;
         when False => Error_Code : Integer;
      end case;
   end record;

   --  Pattern 1: Guarded access — branch on discriminant, then read.
   --  GNATprove proves the discriminant check within each branch.
   function Get_Value_Or_Default
     (R       : Result_Model;
      Default : Integer) return Integer;

   --  Pattern 2: Caller-established precondition.
   --  The caller must prove R.OK = True before calling.
   function Unwrap_Value (R : Result_Model) return Integer
     with Pre => R.OK;

   --  Pattern 3: Mutation invalidation.
   --  Demonstrates that re-assignment requires re-guarding.
   --  The function creates a result, assigns to a local, then safely
   --  accesses the value only after re-establishing the guard.
   function Parse_Then_Reparse (First, Second : Integer) return Integer;

end Template_Discriminant_Result;
