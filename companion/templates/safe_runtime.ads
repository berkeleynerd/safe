--  Safe Language Runtime Type Definitions
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126:812b54a8
--  Reference: compiler/translation_rules.md Section 8.1
--
--  Every integer arithmetic expression in the Safe language is evaluated
--  in a mathematical integer type. The compiler emits all intermediate
--  computations using Wide_Integer, which provides at least 64-bit signed
--  range. Range checks occur only at narrowing points: assignment,
--  parameter passing, return, type conversion, and type annotation.

pragma SPARK_Mode (On);

package Safe_Runtime
  with Pure
is

   type Wide_Integer is range -(2 ** 63) .. (2 ** 63 - 1);
   --  Wide intermediate type for all integer arithmetic in emitted code.
   --  Corresponds to the mathematical integer semantics of the Safe language.
   --  The compiler lifts all integer operands to Wide_Integer before
   --  performing arithmetic, then narrows at the five defined narrowing
   --  points (assignment, parameter, return, conversion, annotation).

end Safe_Runtime;
