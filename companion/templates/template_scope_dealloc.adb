--  Verified Emission Template: Scope-Exit Deallocation
--  See template_scope_dealloc.ads for clause references.

pragma SPARK_Mode (On);

with Safe_Model; use Safe_Model;
with Safe_PO;    use Safe_PO;

package body Template_Scope_Dealloc
  with SPARK_Mode => On
is

   --  Ghost helper: map Boolean state to Ownership_State for PO hooks.
   function To_State (Is_Null : Boolean; Is_Moved : Boolean)
     return Ownership_State
   is (if Is_Moved then Moved
       elsif Is_Null then Null_State
       else Owned)
     with Ghost;

   -------------------------------------------------------------------
   --  Helper: model deallocation of a single variable.
   --  In emitted code, this is Unchecked_Deallocation.
   --  Only deallocates if the pointer is non-null and owned.
   -------------------------------------------------------------------
   procedure Dealloc (V : in out Var_Model)
     with Pre  => not V.Is_Moved or else V.Is_Null,
          Post => V.Is_Null and then not V.Is_Moved;

   procedure Dealloc (V : in out Var_Model)
   is
   begin
      if not V.Is_Null and then not V.Is_Moved then
         --  Model: Free(V); V := null;
         V.Is_Null := True;
         V.Is_Moved := False;
         V.Value := 0;
      else
         --  Already null/moved: no deallocation needed.
         V.Is_Null := True;
         V.Is_Moved := False;
      end if;
   end Dealloc;

   -------------------------------------------------------------------
   --  Pattern: Scope with allocations, move, and auto-deallocation
   --
   --  Emission pattern from translation_rules.md Section 9:
   --    1. Allocate variables in declaration order
   --    2. Perform operations (including moves)
   --    3. At scope exit, deallocate in reverse declaration order
   --    4. Skip null/moved variables
   -------------------------------------------------------------------
   procedure Run_Scope (Result : out Integer) is
      --  Declaration order: A first, then B.
      A : Var_Model :=
        (Is_Null => False, Is_Moved => False, Value => 42);
      B : Var_Model :=
        (Is_Null => False, Is_Moved => False, Value => 99);
   begin
      --  Move A to C (a local target).
      --  After move: A is Moved (null), C is Owned.
      Check_Owned_For_Move (To_State (A.Is_Null, A.Is_Moved));

      declare
         C : Var_Model :=
           (Is_Null => True, Is_Moved => False, Value => 0);
      begin
         C.Value := A.Value;
         C.Is_Null := False;
         C.Is_Moved := False;

         A.Is_Null := True;
         A.Is_Moved := True;

         --  Read from C (not moved).
         Check_Not_Moved (To_State (C.Is_Null, C.Is_Moved));
         Result := C.Value;

         --  Scope exit for inner block: deallocate C.
         Dealloc (C);
      end;

      --  Scope exit: deallocate in reverse declaration order.
      --  B is Owned -> deallocate.
      Dealloc (B);
      --  A is Moved (null) -> the Dealloc guard handles this.
      --  A.Is_Moved is True, so we need to clear it for Dealloc precondition.
      --  In emitted code, this is: if A /= null then Free(A); end if;
      --  Since A is null (moved), the guard skips deallocation.
      A.Is_Moved := False;  --  Model: moved -> null_state for dealloc
      Dealloc (A);
   end Run_Scope;

end Template_Scope_Dealloc;
