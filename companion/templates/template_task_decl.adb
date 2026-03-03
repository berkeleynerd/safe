--  Verified Emission Template: Task Declaration + Exclusive Ownership
--  See template_task_decl.ads for clause references.

pragma SPARK_Mode (On);

with Safe_Model; use Safe_Model;
with Safe_PO;    use Safe_PO;

package body Template_Task_Decl
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Pattern 1: Task 1 accesses its exclusively owned variable.
   --
   --  Emission pattern from translation_rules.md Section 6:
   --    task T { var x : Int = 100; ... x ... }
   --  At each access to x, the compiler emits:
   --    Check_Exclusive_Ownership(var_id, task_id, map)
   --  The map initially has No_Task for all variables. On first access,
   --  the variable is claimed by the task.
   -------------------------------------------------------------------
   procedure Task1_Access_Own_Var (Value : out Integer) is
      Map : Task_Var_Map := [others => No_Task] with Ghost;
      --  Task 1 = ID 1, Var 0 = variable being accessed.
      Task1 : constant Task_Id_Range := 1 with Ghost;
      Var0  : constant Var_Id_Range  := 0 with Ghost;
   begin
      --  First access: Var0 is unowned (No_Task), so Task1 can claim it.
      Check_Exclusive_Ownership (Var0, Task1, Map);
      Map := Assign_Owner (Var0, Task1, Map);

      --  Subsequent access: Var0 is owned by Task1, still OK.
      Check_Exclusive_Ownership (Var0, Task1, Map);

      Value := 100;
   end Task1_Access_Own_Var;

   -------------------------------------------------------------------
   --  Pattern 2: Task 2 accesses its exclusively owned variable.
   -------------------------------------------------------------------
   procedure Task2_Access_Own_Var (Value : out Integer) is
      Map   : Task_Var_Map := [others => No_Task] with Ghost;
      Task2 : constant Task_Id_Range := 2 with Ghost;
      Var1  : constant Var_Id_Range  := 1 with Ghost;
   begin
      --  First access: claim Var1 for Task2.
      Check_Exclusive_Ownership (Var1, Task2, Map);
      Map := Assign_Owner (Var1, Task2, Map);

      --  Subsequent access: still owned by Task2.
      Check_Exclusive_Ownership (Var1, Task2, Map);

      Value := 200;
   end Task2_Access_Own_Var;

   -------------------------------------------------------------------
   --  Pattern 3: Ghost-only ownership verification.
   --
   --  Proves the full sequence: initial claim, re-access, and
   --  the postcondition of Assign_Owner that guarantees single-owner.
   -------------------------------------------------------------------
   procedure Verify_Ownership_Claim is
      Map   : Task_Var_Map := [others => No_Task];
      Task1 : constant Task_Id_Range := 1;
      Var0  : constant Var_Id_Range  := 0;
   begin
      --  Var0 is unowned -> Task1 can claim.
      Check_Exclusive_Ownership (Var0, Task1, Map);
      Map := Assign_Owner (Var0, Task1, Map);

      --  Verify ownership postcondition.
      pragma Assert (Map (Var0) = Task1);

      --  Re-access by same task succeeds.
      Check_Exclusive_Ownership (Var0, Task1, Map);
   end Verify_Ownership_Claim;

end Template_Task_Decl;
