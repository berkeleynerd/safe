--  Verified Emission Template: Task Declaration + Exclusive Ownership
--
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.4.1.p32:90d4f527
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.4.1.p33:0fc25399
--  Reference: compiler/translation_rules.md Section 6
--  Reference: tests/golden/golden_pipeline.ada
--
--  Demonstrates the compiler emission pattern for task-variable ownership.
--  Each mutable variable accessed by a task must be exclusively owned by
--  that task. The compiler emits Check_Exclusive_Ownership at each access
--  site to verify single-task ownership.
--
--  In emitted code, tasks become Ada task objects with priority aspects.
--  This template verifies the ownership invariant using the ghost model
--  Safe_Model.Task_Var_Map. All ownership tracking variables are ghost;
--  only the computed values are non-ghost.
--
--  PO hooks exercised: Check_Exclusive_Ownership

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Task_Decl
  with SPARK_Mode => On
is

   --  Pattern 1: Task accesses its own variable (should prove).
   procedure Task1_Access_Own_Var (Value : out Integer)
     with Post => Value = 100;

   --  Pattern 2: Task accesses its own variable (should prove).
   procedure Task2_Access_Own_Var (Value : out Integer)
     with Post => Value = 200;

   --  Pattern 3: Ghost-only ownership verification.
   --  Proves that a task can claim and re-access a variable.
   procedure Verify_Ownership_Claim
     with Ghost;

end Template_Task_Decl;
