--  Verified Emission Template: Effect Summary Generation
--
--  Clause: SAFE@4aecf21:spec/05-assurance.md#5.2.2.p5:a07e15ef
--  Clause: SAFE@4aecf21:spec/05-assurance.md#5.2.3.p8:dfb93f2c
--  Clause: SAFE@4aecf21:spec/05-assurance.md#5.2.4.p11:b89bd341
--  Reference: compiler/translation_rules.md Section 10
--
--  Demonstrates emitter-generated Global, Depends, Initializes,
--  and Constant_After_Elaboration aspects.  GNATprove flow
--  analysis verifies the contracts; no PO hooks are needed.
--
--  PO hooks exercised: (none -- pure flow-analysis template)

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Effect_Summary
  with SPARK_Mode  => On,
       Initializes =>
         (Counter, Accumulator, Last_Delta, Threshold)
is

   --  Package-level state: four variables demonstrating
   --  different Global/Depends patterns.

   Counter : Natural := 0;

   Accumulator : Long_Long_Integer := 0;

   Last_Delta : Integer := 0;

   Threshold : Positive := 100
     with Constant_After_Elaboration;

   --  Pattern 1: Single In_Out variable.
   procedure Increment
     with Global  => (In_Out => Counter),
          Depends => (Counter => Counter);

   --  Pattern 2: Two outputs, one depends on input parameter.
   procedure Accumulate (Amount : Integer)
     with Global  => (In_Out => Accumulator,
                      Output => Last_Delta),
          Depends => (Accumulator => (Accumulator, Amount),
                      Last_Delta  => Amount),
          Pre     => Accumulator in
                       -4_000_000_000_000_000_000 ..
                        4_000_000_000_000_000_000
                     and then Amount in
                       -2_000_000_000 ..
                        2_000_000_000;

   --  Pattern 3: Two Input globals, result depends on both.
   function Is_Above_Threshold return Boolean
     with Global  =>
            (Input => (Accumulator, Threshold)),
          Depends =>
            (Is_Above_Threshold'Result =>
               (Accumulator, Threshold));

   --  Pattern 4: Single Input global, result depends on it.
   function Get_Last_Delta return Integer
     with Global  => (Input => Last_Delta),
          Depends =>
            (Get_Last_Delta'Result => Last_Delta);

   --  Pattern 5: Two Output globals, null dependencies.
   procedure Reset
     with Global  =>
            (Output => (Counter, Accumulator)),
          Depends =>
            (Counter     => null,
             Accumulator => null);

   --  Pattern 6: Caller propagates callee effects (composition).
   --  The emitter must merge Global/Depends from Increment and
   --  Accumulate into the caller's declared aspects.
   procedure Bump_And_Accumulate (Amount : Integer)
     with Global  => (In_Out => (Counter, Accumulator),
                      Output => Last_Delta),
          Depends => (Counter     => Counter,
                      Accumulator => (Accumulator, Amount),
                      Last_Delta  => Amount),
          Pre     => Accumulator in
                       -4_000_000_000_000_000_000 ..
                        4_000_000_000_000_000_000
                     and then Amount in
                       -2_000_000_000 ..
                        2_000_000_000;

end Template_Effect_Summary;
