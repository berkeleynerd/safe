--  Verified Emission Template: Division / Mod / Rem with Nonzero Guard
--  See template_division_nonzero.ads for clause references.

pragma SPARK_Mode (On);

with Safe_PO; use Safe_PO;

package body Template_Division_Nonzero
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Pattern 1: Division with nonzero guard
   --
   --  Emission pattern:
   --    1. Emit Nonzero ghost assertion for Y
   --    2. Delegate to Safe_Div PO procedure
   -------------------------------------------------------------------
   procedure Divide
     (X      : Long_Long_Integer;
      Y      : Long_Long_Integer;
      Result :    out Long_Long_Integer)
   is
   begin
      --  Ghost assertion: divisor is provably nonzero.
      Nonzero (Y);

      --  Safe division via PO hook.
      Safe_Div (X, Y, Result);
   end Divide;

   -------------------------------------------------------------------
   --  Pattern 2: Modulo with nonzero guard
   -------------------------------------------------------------------
   procedure Modulo
     (X      : Long_Long_Integer;
      Y      : Long_Long_Integer;
      Result :    out Long_Long_Integer)
   is
   begin
      --  Ghost assertion: divisor is provably nonzero.
      Nonzero (Y);

      --  Safe modulo via PO hook.
      Safe_Mod (X, Y, Result);
   end Modulo;

   -------------------------------------------------------------------
   --  Pattern 3: Remainder with nonzero guard
   -------------------------------------------------------------------
   procedure Remainder
     (X      : Long_Long_Integer;
      Y      : Long_Long_Integer;
      Result :    out Long_Long_Integer)
   is
   begin
      --  Ghost assertion: divisor is provably nonzero.
      Nonzero (Y);

      --  Safe remainder via PO hook.
      Safe_Rem (X, Y, Result);
   end Remainder;

   -------------------------------------------------------------------
   --  Pattern 4: Division by nonzero literal
   --
   --  The literal 2 is statically nonzero. The compiler emits a
   --  static Nonzero check that GNATprove discharges trivially.
   -------------------------------------------------------------------
   function Half (V : Long_Long_Integer) return Long_Long_Integer is
   begin
      --  Static nonzero check for literal divisor.
      Nonzero (2);

      return V / 2;
   end Half;

end Template_Division_Nonzero;
