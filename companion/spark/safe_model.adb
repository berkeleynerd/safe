--  Safe Language Annotated SPARK Companion
--  Source commit: 468cf72332724b04b7c193b4d2a3b02f1584125d
--  Generated: 2026-03-02
--  Generator: spec2spark v0.1.0
--  Clauses: 2.8.1 (p126-p130), 2.3 (p94-p108), 4.2-4.3 (p12-p31a),
--           4.5 (p45-p52), 5.3 (p12-p31), 5.4 (p32-p40)
--  Assumptions:
--    - Ghost bodies are minimal; they exist for proof, not execution.
--    - All function bodies match their expression-function specifications.

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package body Safe_Model is

   ---------------------------------------------------------------------------
   --  Assign_Owner body
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99
   ---------------------------------------------------------------------------

   function Assign_Owner
     (Var_Id  : Var_Id_Range;
      Task_Id : Task_Id_Range;
      Map     : Task_Var_Map) return Task_Var_Map
   is
      Result : Task_Var_Map := Map;
   begin
      Result (Var_Id) := Task_Id;
      return Result;
   end Assign_Owner;

   ---------------------------------------------------------------------------
   --  No_Shared_Variables body
   --
   --  The map stores exactly one task ID per variable, so by construction
   --  no variable can be simultaneously owned by two distinct tasks. This
   --  function always returns True for a well-formed map (which all maps
   --  are, since the type enforces single-valued entries).
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.4.1.p32:90d4f527
   ---------------------------------------------------------------------------

   function No_Shared_Variables (Map : Task_Var_Map) return Boolean is
      pragma Unreferenced (Map);
   begin
      --  By the type definition of Task_Var_Map, each variable index maps
      --  to at most one task ID. The "shared" violation would require the
      --  same variable to appear in two task effect sets simultaneously,
      --  which the single-valued map encoding prevents by construction.
      return True;
   end No_Shared_Variables;

end Safe_Model;
