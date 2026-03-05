--  Verified Emission Template: Ownership Move Semantics
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96a:0eaf48aa
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96c:0b45de01
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p97a:8d0214d5
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.5.p104:d9f9b8d9
--  Reference: compiler/translation_rules.md Section 7
--  Reference: tests/golden/golden_ownership.ada
--
--  Demonstrates the compiler emission pattern for ownership move:
--    1. Source must be Owned (Check_Owned_For_Move)
--    2. Copy access value to target
--    3. Set source to null (Moved state)
--    4. After move, source is Moved and cannot be used (Check_Not_Moved)
--
--  SPARK restriction: access types and ghost types from Safe_Model cannot
--  appear in non-ghost record fields. We model ownership state using
--  Boolean flags (Is_Null, Is_Moved) and map to Safe_Model.Ownership_State
--  only in ghost PO hook calls.
--
--  PO hooks exercised: Check_Owned_For_Move, Check_Not_Moved

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Ownership_Move
  with SPARK_Mode => On
is

   --  Abstract model of an owned pointer variable.
   --  In emitted code, this corresponds to an access type variable.
   --  Is_Null = True, Is_Moved = False -> Null_State
   --  Is_Null = False, Is_Moved = False -> Owned
   --  Is_Null = True, Is_Moved = True -> Moved
   type Ptr_Model is record
      Is_Null  : Boolean;
      Is_Moved : Boolean;
      Value    : Integer;
   end record;

   --  Pattern: Move ownership from Source to Target.
   --  Source becomes Moved (null), Target becomes Owned.
   procedure Move
     (Source : in out Ptr_Model;
      Target : in out Ptr_Model)
     with Pre  => not Source.Is_Null
                  and then not Source.Is_Moved
                  and then Target.Is_Null,
          Post => Source.Is_Null
                  and then Source.Is_Moved
                  and then not Target.Is_Null
                  and then not Target.Is_Moved
                  and then Target.Value = Source.Value'Old;

   --  Pattern: Use a value after verifying it has not been moved.
   function Read_Value (P : Ptr_Model) return Integer
     with Pre => not P.Is_Moved and then not P.Is_Null;

end Template_Ownership_Move;
