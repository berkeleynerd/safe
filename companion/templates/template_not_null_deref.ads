--  Verified Emission Template: Not-Null Assertion Before Dereference
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.4.p136:fa5e94b7
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.1.p12:99a94209
--  Reference: compiler/translation_rules.md Section 7
--  Reference: tests/golden/golden_ownership.ada
--
--  Demonstrates the compiler emission pattern for not-null dereference:
--    1. Before every dereference, assert the pointer is not null
--    2. The assertion is a proof obligation (Not_Null_Ptr / Safe_Deref)
--    3. GNATprove verifies statically that the pointer cannot be null
--
--  SPARK restriction: access types are not in SPARK_Mode. We model
--  the null state with a Boolean flag, matching Safe_PO.Not_Null_Ptr.
--
--  PO hooks exercised: Not_Null_Ptr, Safe_Deref

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Not_Null_Deref
  with SPARK_Mode => On
is

   --  Abstract model of a pointer variable.
   type Ptr_Model is record
      Is_Null : Boolean;
      Value   : Integer;
   end record;

   --  Pattern 1: Dereference to read a value.
   --  Precondition: pointer is not null.
   function Deref_Read (P : Ptr_Model) return Integer
     with Pre => not P.Is_Null;

   --  Pattern 2: Dereference to write a value.
   --  Precondition: pointer is not null.
   procedure Deref_Write
     (P         : in out Ptr_Model;
      New_Value : Integer)
     with Pre  => not P.Is_Null,
          Post => P.Value = New_Value and then not P.Is_Null;

   --  Pattern 3: Conditional dereference (guarded by null check).
   --  The compiler emits a guard; if null, returns a default.
   function Safe_Read (P : Ptr_Model; Default : Integer) return Integer;

end Template_Not_Null_Deref;
