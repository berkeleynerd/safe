--  Verified Emission Template: Division / Mod / Rem with Nonzero Guard
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p134:90a17a3b
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.1.p12:99a94209
--  Reference: compiler/translation_rules.md Section 8
--
--  Demonstrates the compiler emission pattern for safe division, modulo,
--  and remainder operations. The right operand of /, mod, and rem must be
--  provably nonzero. The compiler inserts a Nonzero ghost assertion before
--  each operation, and uses Safe_Div / Safe_Mod / Safe_Rem PO procedures
--  for the actual computation.
--
--  PO hooks exercised: Nonzero, Safe_Div, Safe_Mod, Safe_Rem

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Division_Nonzero
  with SPARK_Mode => On
is

   --  Pattern 1: Integer division with nonzero guard.
   --  Precondition ensures divisor is nonzero.
   procedure Divide
     (X      : Long_Long_Integer;
      Y      : Long_Long_Integer;
      Result :    out Long_Long_Integer)
     with Pre  => Y /= 0
                  and then not (X = Long_Long_Integer'First and then Y = -1),
          Post => Result = X / Y;

   --  Pattern 2: Modulo with nonzero guard.
   procedure Modulo
     (X      : Long_Long_Integer;
      Y      : Long_Long_Integer;
      Result :    out Long_Long_Integer)
     with Pre  => Y /= 0,
          Post => Result = X mod Y;

   --  Pattern 3: Remainder with nonzero guard.
   procedure Remainder
     (X      : Long_Long_Integer;
      Y      : Long_Long_Integer;
      Result :    out Long_Long_Integer)
     with Pre  => Y /= 0,
          Post => Result = X rem Y;

   --  Pattern 4: Division by nonzero literal (compile-time known).
   --  No runtime guard needed; the compiler emits a static Nonzero check.
   function Half (V : Long_Long_Integer) return Long_Long_Integer
     with Post => Half'Result = V / 2;

end Template_Division_Nonzero;
