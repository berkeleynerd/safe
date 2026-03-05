--  Verified Emission Template: Floating-Point Safety
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139:d50bc714
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139b:5e20032b
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.5.p139d:56f1f36b
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.7a.p28a:5936dbea
--  Reference: compiler/translation_rules.md Section 8.4
--
--  Demonstrates the compiler emission patterns for floating-point
--  narrowing safety (D27 Rule 5):
--    1. Not-NaN check at narrowing point (V = V is IEEE 754 NaN idiom)
--    2. Finite check (not-NaN + not-infinity) at narrowing point
--    3. Safe FP division with nonzero, non-NaN, finite operands
--    4. Compound operation: intermediate sum, division, and narrowing
--
--  Under IEEE 754 non-trapping mode, NaN and infinity propagate silently
--  through intermediate computations. The compiler inserts safety checks
--  only at narrowing points (assignment, parameter passing, return).
--
--  PO hooks exercised: FP_Not_NaN, FP_Not_Infinity, FP_Safe_Div

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_FP_Safety
  with SPARK_Mode => On
is

   --  Helper predicates for floating-point value classification.
   function Is_Not_NaN (V : Long_Float) return Boolean is
     (V = V);

   function Is_Finite (V : Long_Float) return Boolean is
     (V = V
      and then V >= Long_Float'First
      and then V <= Long_Float'Last);

   --  Pattern: Not-NaN check at narrowing point.
   --  V = V is the IEEE 754 NaN idiom: NaN /= NaN.
   function Narrow_Not_NaN (V : Long_Float) return Long_Float
     with Pre  => Is_Not_NaN (V),
          Post => Narrow_Not_NaN'Result = V;

   --  Pattern: Finite check at narrowing point (not-NaN + not-infinity).
   function Narrow_Finite (V : Long_Float) return Long_Float
     with Pre  => Is_Finite (V),
          Post => Narrow_Finite'Result = V;

   --  Pattern: Safe floating-point division.
   --  Both operands must be finite and non-NaN; divisor must be nonzero.
   procedure Safe_FP_Divide
     (X : Long_Float;
      Y : Long_Float;
      R : out Long_Float)
     with Pre  => Is_Finite (X)
                  and then Is_Finite (Y)
                  and then Y /= 0.0,
          Post => R = X / Y;

   --  Pattern: Compound operation — intermediate sum, division,
   --  narrowing.  Models: result := narrow((A + B) / C).
   --  Half_Range is a proof harness bound — a sufficient condition
   --  ensuring A + B cannot overflow.  The compiler's actual range
   --  analysis may produce tighter or program-specific bounds; the
   --  emitter substitutes those bounds into this slot.
   Half_Range : constant Long_Float := Long_Float'Last / 2.0;

   procedure Compute_And_Narrow
     (A : Long_Float;
      B : Long_Float;
      C : Long_Float;
      R : out Long_Float)
     with Pre  => Is_Finite (A)
                  and then Is_Finite (B)
                  and then Is_Finite (C)
                  and then C /= 0.0
                  and then A >= -Half_Range
                  and then A <= Half_Range
                  and then B >= -Half_Range
                  and then B <= Half_Range,
          Post => R = (A + B) / C;

end Template_FP_Safety;
