--  Verified Emission Template: Ownership Move Semantics
--  See template_ownership_move.ads for clause references.

pragma SPARK_Mode (On);

with Safe_Model; use Safe_Model;
with Safe_PO;    use Safe_PO;

package body Template_Ownership_Move
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
   --  Pattern: Move ownership from Source to Target
   --
   --  Emission pattern from translation_rules.md Section 7:
   --    1. Assert source is owned (Check_Owned_For_Move)
   --    2. Copy the access value: Target := Source
   --    3. Null the source: Source := null
   --    4. Update ownership state tracking
   -------------------------------------------------------------------
   procedure Move
     (Source : in out Ptr_Model;
      Target : in out Ptr_Model)
   is
   begin
      --  PO hook: verify source is owned before move.
      Check_Owned_For_Move (To_State (Source.Is_Null, Source.Is_Moved));

      --  Copy value (models: Target := Source).
      Target.Value := Source.Value;
      Target.Is_Null := False;
      Target.Is_Moved := False;

      --  Null source (models: Source := null).
      Source.Is_Null := True;
      Source.Is_Moved := True;
   end Move;

   -------------------------------------------------------------------
   --  Pattern: Read value with not-moved check
   --
   --  Before any use of a pointer variable, the compiler emits a
   --  Check_Not_Moved assertion to verify the variable has not been
   --  moved away.
   -------------------------------------------------------------------
   function Read_Value (P : Ptr_Model) return Integer is
   begin
      --  PO hook: verify the variable has not been moved.
      Check_Not_Moved (To_State (P.Is_Null, P.Is_Moved));

      return P.Value;
   end Read_Value;

end Template_Ownership_Move;
