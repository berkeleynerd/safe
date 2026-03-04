--  Verified Emission Template: Effect Summary Generation
--  See template_effect_summary.ads for clause references.

pragma SPARK_Mode (On);

package body Template_Effect_Summary
  with SPARK_Mode => On
is

   ----------------------------------------------------------------
   --  Pattern 1: Single In_Out variable
   --
   --  Emission pattern:
   --    counter += 1 -> Global => (In_Out => Counter)
   --  Guard against overflow at Natural'Last.
   ----------------------------------------------------------------
   procedure Increment is
   begin
      if Counter < Natural'Last then
         Counter := Counter + 1;
      end if;
   end Increment;

   ----------------------------------------------------------------
   --  Pattern 2: Two outputs, one depends on input parameter
   --
   --  Emission pattern:
   --    accumulate(amount) ->
   --      Global => (In_Out => Accumulator,
   --                 Output => Last_Delta)
   --  No overflow: precondition bounds Accumulator, and Integer
   --  fits in Long_Long_Integer for the widening conversion.
   ----------------------------------------------------------------
   procedure Accumulate (Amount : Integer) is
   begin
      Accumulator :=
        Accumulator + Long_Long_Integer (Amount);
      Last_Delta := Amount;
   end Accumulate;

   ----------------------------------------------------------------
   --  Pattern 3: Two Input globals, result depends on both
   --
   --  Emission pattern:
   --    is_above_threshold() ->
   --      Global => (Input => (Accumulator, Threshold))
   ----------------------------------------------------------------
   function Is_Above_Threshold return Boolean is
   begin
      return Accumulator > Long_Long_Integer (Threshold);
   end Is_Above_Threshold;

   ----------------------------------------------------------------
   --  Pattern 4: Single Input global
   --
   --  Emission pattern:
   --    get_last_delta() -> Global => (Input => Last_Delta)
   ----------------------------------------------------------------
   function Get_Last_Delta return Integer is
   begin
      return Last_Delta;
   end Get_Last_Delta;

   ----------------------------------------------------------------
   --  Pattern 5: Two Output globals, null dependencies
   --
   --  Emission pattern:
   --    reset() ->
   --      Global => (Output => (Counter, Accumulator))
   ----------------------------------------------------------------
   procedure Reset is
   begin
      Counter := 0;
      Accumulator := 0;
   end Reset;

   ----------------------------------------------------------------
   --  Pattern 6: Caller propagates callee effects
   --
   --  Emission pattern:
   --    bump_and_accumulate(amount) ->
   --      calls Increment then Accumulate; caller's
   --      Global/Depends is the composition of both callees.
   ----------------------------------------------------------------
   procedure Bump_And_Accumulate (Amount : Integer) is
   begin
      Increment;
      Accumulate (Amount);
   end Bump_And_Accumulate;

end Template_Effect_Summary;
