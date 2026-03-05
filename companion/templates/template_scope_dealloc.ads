--  Verified Emission Template: Scope-Exit Deallocation
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.5.p104:d9f9b8d9
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96c:0b45de01
--  Reference: compiler/translation_rules.md Section 9
--  Reference: tests/golden/golden_ownership.ada
--
--  Demonstrates the compiler emission pattern for automatic deallocation
--  at scope exit. When a scope containing owned pointer variables exits,
--  the compiler emits deallocation calls in reverse declaration order
--  for all non-null owned pointers. Moved pointers (null) are skipped.
--
--  PO hooks exercised: Check_Not_Moved, Check_Owned_For_Move

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Scope_Dealloc
  with SPARK_Mode => On
is

   --  Abstract model of an owned variable.
   --  State mapping: same as Template_Ownership_Move.
   type Var_Model is record
      Is_Null  : Boolean;
      Is_Moved : Boolean;
      Value    : Integer;
   end record;

   --  Pattern: Execute a scope with allocations, moves, and
   --  automatic deallocation at scope exit.
   --  Returns the final value read from the surviving owned pointer.
   procedure Run_Scope (Result : out Integer)
     with Post => Result = 42;

end Template_Scope_Dealloc;
