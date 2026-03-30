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
