# SPARK 19 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_19.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-19`

We present here a few highlights of the new features in SPARK 19.

## Program Specification

### More Precise Support for ‘Image and ‘Img Attributes

To avoid spurious range checks on string operations involving occurrences of the `'Img`, `'Image`, `'Wide_Image`, and `'Wide_Wide_Image` attributes, GNATprove makes an assumption about the maximal length of the returned string. If the attribute applies to an integer type, the bounds are the maximal size of the result of the attribute as specified in the language. Otherwise, GNATprove assumes that the length of such a string cannot exceed 255 (the maximal number of characters in a line) times 8 (the maximal size of a `Wide_Wide_Character`).

### Support for More Fixed-Point Types and Operations

Fixed-point types with more values of small are now supported: instead of requiring that the small is a negative power of 2 or 5, it is sufficient now that the small is the reciprocal of an integer. For example, a value of small of (1.0 / 400.0) is now supported while it was previously rejected.

Operations that mix different fixed-point types are also supported now in some cases: multiplication and division between fixed-points which result in a fixed-point are supported when their respective smalls are compatible in the sense of Ada RM G.2.3(21). This ensures that the result is precisely computed.

### New SPARK-Compatible Libraries for Dimensional Analysis

It is now possible to rely on units from the GNAT library to do dimensional analysis on SPARK code. While the previous unit `System.Dim.Mks` based on `Long_Long_Float` is still not supported by GNATprove on platforms where `Long_Long_Float` is 128 bits, the new units `System.Dim.Float_Mks` and `System.Dim.Long_Mks`, based respectively on `Float` and `Long_Float`, are supported.

### New Lemmas for Exponentiation, Fixed-Point Arithmetic and Higher-Order Functions

The SPARK lemma library has been enriched with:

- two lemmas on the monotonicity of exponentiation on signed integers,
- three GNAT-specific lemmas about the monotonicity and rounding properties of division between a value of a fixed-point type and an integer, and
- a new unit providing higher order functions over arrays (`Map`, `Fold` and common instances of `Fold`, namely `Count` and `Sum`) with general purpose lemmas for `Count` and `Sum`.

## Tool Automation

### Automatic Detection of Array Initialization with Non-Static Bounds

GNATprove could already detect when an array is initialized in a FOR loop, but only for arrays with static bounds. Now it can also detect initialization of single-dimensional arrays with nonstatic bounds. For example, it does not issue a false alarm anymore on the following code, as it can detect that out parameter `S` is fully initialized in the loop:

    procedure Flush (S : out String) is
    begin
       for C in S'Range loop
          S (C) := ' ';
       end loop;
    end Flush;

### Automatic Unrolling of Loops with Dynamic Bounds or Executed Only Once

GNATprove can unroll more loops than previously. As before, this additional unrolling only applies to loops for which no loop invariant is provided, and it can be suppressed with switch `--no-loop-unrolling`.

GNATprove can now unroll loops with bounds that are not known statically, provided the maximum range given by their type is small (less than 20 possible values). For example, this allows proving the postcondition of function `Subtract` in the following program:

    package Types is
       subtype Small_Ints is Natural range 0 .. 10;
    end Types;

    with Types; use Types;
    function Subtract (Y, X : Small_Ints) return Small_Ints with
      Pre  => Y >= X,
      Post => Subtract'Result = Y - X
    is
       Result : Natural := 0;
    begin
       for K in X .. Y loop  --  no loop invariant is needed
          Result := Result + 1;
       end loop;

       return Result - 1;
    end Subtract;

GNATprove can also unroll loops of the form `for J in 1 .. 1` that are used to simulate forward gotos (not allowed in SPARK) with loop exits (which are allowed in SPARK). For example, this allows proving the postcondition of procedure `Check_Ordered` in the following program:

    procedure Check_Ordered (W, X, Y, Z : Integer; Success : out Boolean) with
      Post => Success = (W <= X and X <= Y and Y <= Z)
    is
    begin
       Success := False;
       for J in 1 .. 1 loop  --  no loop invariant is needed
          if W > X then
             exit;

          elsif X > Y then
             exit;
          end if;

          exit when Y > Z;

          Success := True;
       end loop;

       --  more code here...

    end Check_Ordered;

### Improved Support for Floating-Point Computations

CVC4 prover has been enhanced to deal natively with floating-point numbers. GNATprove now uses this native support when calling CVC4, which leads to more automatic proofs on floating-point programs.

## Tool Interaction

### Better Messages

#### Error Message Now Points at Root Cause for SPARK Violations

When an entity which is not in SPARK is used in a SPARK context, the error message now points to the root cause for the violation. It could be otherwise difficult to get this information when the root cause for a violation is at the end of a chain of entities (for example, the use of an access type inside an expression used in the definition of a type, itself further derived and used in the declaration of a variable).

#### New Switch `--info` for Investigating Proof Failures

When using switch `--info`, GNATprove issues information messages regarding internal decisions that could influence provability:

- whether candidate loops for automatic unrolling are effectively unrolled or not,
- whether candidate subprograms for contextual analysis (a.k.a. inlining for proof) are effectively inlined for proof or not, and
- whether possible subprogram nontermination impacts the proof of calls to that subprogram.

Here are examples of information messages displayed by GNATprove:

Image (not mirrored): `_images/info_messages.png`

#### Explanation Part in Messages to Investigate Unproved Checks

GNATprove may emit a tentative explanation for an unprovable property when it suspects a missing precondition, postcondition or loop invariant to be the cause of the unprovability. The explanation part follows the usual message of the form:

    file:line:col: severity: check might fail

with a part in square brackets such as:

    [possible explanation: subprogram at line xxx should mention Var in a precondition]
    [possible explanation: loop at line xxx should mention Var in a loop invariant]
    [possible explanation: call at line xxx should mention Var in a postcondition]

as shown in this case of a missing precondition:

Image (not mirrored): `_images/missing_precondition_explanation.png`

and this other case of a missing loop invariant:

Image (not mirrored): `_images/missing_loop_invariant_explanation.png`

#### Warnings Issued by Proof to Detect Inconsistencies

GNATprove can issue warnings as part of proof on:

- preconditions or postconditions that are always false,
- dead code after loops, and
- unreachable branches in assertions and contracts.

These warnings are not enabled by default, as they require calling a prover for each potential warning, which incurs a small cost (1 sec for each property thus checked). They can be enabled with switch `--proof-warnings`, and their effect is controlled by switch `--warnings` and pragma `Warnings` like other warnings.

Here are examples of such warnings issued on the code of Tokeneer (www.adacore.com), showing parts of postconditions that could be effectively removed as they correspond to unreachable branches:

Image (not mirrored): `_images/unreachable_branch_warnings.png`

### Better Counterexamples

#### Counterexamples Now Include Values for Private Types and Floats

Counterexamples that are generated by GNATprove when a check is not proved now include values of private types and floating-point types. For example, the postcondition of `Add_Floats` below is unprovable and GNATprove displays values of `Float` parameters that violate the postcondition:

Image (not mirrored): `_images/float_counterexample.png`

#### Counterexamples on Individual Paths Through Subprograms

Counterexamples are now always displayed for a single path inside the subprogram. For example, no values are displayed for the statements inside the first branches of the if-statement and case-statement (pointed to by the red arrows) in the program that follows, when displaying the counterexample corresponding to the unproved check at the bottom:

Image (not mirrored): `_images/counterexample_on_single_path.png`

### Better Integration in GPS

#### Path for Missing Dependency Can Be Displayed

GNATprove can now highlight in GPS the path for a dependency missing from the Depends contract. Like other paths, it is displayed when clicking on the magnify icon associated with the corresponding message.

#### Possibility to Run Analysis on Region of Code in GPS

A new switch `--limit-region` has been added to limit analysis to a range of lines inside a given file. This option is accessible from GPS through the contextual menu SPARK ‣ Prove Selected Region, available whenever a region is selected.

Image (not mirrored): `_images/prove_selected_region.png`

#### New Analysis Report Panel in GPS

GPS can display an interactive view reporting the results of the analysis, with a count of issues per file, subprogram and severity, as well as filters to selectively view a subset of the issues only. This interactive view is displayed using the menu SPARK ‣ Show Report. This menu becomes available after the checkbox `Display analysis report` is checked in the SPARK section of the Preferences dialog - menu Edit ‣ Preferences, and only if GNATprove was run so that there are results to display.

Here is an example of this view:

Image (not mirrored): `_images/analysis_report_panel.png`

## Tool Usability

### New Switches

GNATprove comes with a few additional switches, beyond those mentioned previously:

- switch `--memlimit` to limit the memory used by provers,
- switch `--checks-as-errors` to treat failed checks as errors, and
- support for switches `--subdirs` and `--no-subprojects` already used in other AdaCore tools, to respectively create all artifacts under a specific subdirectory, and to analyse only the root project.

### Better Predictability of Running Time with `--level` Switch

Switch `--level` used to change the strategy for generating formulas between levels, which could lead to very long running time at levels 3 and 4. This is not the case anymore, all levels now use the same strategy but increase the prover timeout instead, leading to more predictable comparative slowdown between levels.

### Speedup on Large Projects

When analyzing a unit, GNATprove does not process anymore unused entities of other units. As a consequence, large projects with code that is mostly not in SPARK, or which does contain very few `SPARK_Mode` annotations, are processed much faster by GNATprove.

©AdaCore. | Powered by Sphinx & Alabaster.

