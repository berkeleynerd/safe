# SPARK 23 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_23.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-23`

We present here a few highlights of the new features in SPARK 23.

## Improved Support of Language Features

### Better Support for Arithmetic on Address

Low-level operations from standard unit `System.Storage_Elements` are now supported more precisely. In particular, GNATprove can track the value of an address through arithmetic operations on addresses and offsets, as well as calls to conversion functions `To_Integer` and `To_Address`.

### Better Support of Unchecked Conversions

GNATprove now accepts unchecked conversions between access types and integer types, which could be:

- Calls to an instance of `Ada.Unchecked_Conversion`, or
- Calls to an instance of function `To_Pointer` from `System.Address_To_Access_Conversions`.

In both cases, it issues a warning about the limitations of the analysis, similarly to what is done for overlays.

### Better Warnings on Address Clauses

Because an object with an Address clause could be written outside of the program being analyzed (e.g. by another thread or a hardware driver), GNATprove issues by default a warning on such objects, to let users know about potential implicit writes that it cannot analyze. A user can now explicitly state that there are no other writes to such an object with annotation `Async_Writers => False`, so that no warning is issued on that object. Similarly, GNATprove no longer warns about implicit reads when the object is annotated with `Async_Readers => False`.

## Program Specification

### Better Specification and Verification of Termination

The user can specify that a procedure returns normally (i.e. not through raising an exception or terminating the program) always, or not always, or never, with different aspects:

    procedure Proc_Returns_Always with
      Annotate => (GNATprove, Always_Return);

    procedure Proc_Might_Not_Return with
      Annotate => (GNATprove, Might_Not_Return);

    procedure Proc_Signaling_Error with
      No_Return;

When one of these contracts is specified on a subprogram, GNATprove will try to prove that the subprogram respects its contract, and issue a message otherwise. Note that only `Always_Return` can be specified for functions, as a confirming annotation, as functions should always return in SPARK.

The misnamed `Terminating` annotation has been renamed into `Always_Return`, to indicate clearly that this concerns only termination by normal return from the procedure.

To prove that a loop or a recursive subprogram terminates, GNATprove uses loop or subprogram variants. Up until now, variants were composed of one or several discrete expressions, along with a direction `Increases` or `Decreases`. We have added the possibility to supply a value of the `Big_Integer` type in a variant along with the direction `Decreases`. In this case, GNATprove will check that the `Big_Integer` value decreases and stays non-negative.

It is also possible to use a value of a composite type along with the new direction `Structural`. Structural variants are generally used on recursive data structures. GNATprove checks that the composite value is set to a strict subcomponent of the initial structure at each loop iteration or recursive call. Since it is not possible to create circular data structures in SPARK due to ownership, this is enough to ensure that the loop or recursive subprogram terminates.

### SPARK Library

The SPARK library, previously called SPARK lemma library, was augmented and reorganized. SPARK containers libraries are no longer distributed through GNAT run-time library, but are instead part of the SPARK library. The units are renamed as follows:

- `Ada.Containers.Functional_*` are renamed `SPARK.Containers.Functional.*`.
- `Ada.Containers.Formal_*` are renamed `SPARK.Containers.Formal.*`.
- Types defined in `Ada.Containers` are available in `SPARK.Containers.Types`.

### Unbounded Functional Containers

Functional sets and maps useful for specification used to be bounded. It is no longer the case, as the function computing the number of elements they contain now returns a value of type `Big_Integer`. A new version of the functional vectors, called infinite sequences, has also been introduced. It is indexed by type `Big_Integer`. Note that the functional vectors themselves remain unchanged.

### Cut Operations for Driving Provers Inside Assertions

The SPARK library now includes boolean cut operations that can be used to manually help the proof of complicated assertions. It provides two boolean functions named `By` and `So` that are handled in a specific way by GNATprove. They introduce a boolean expression that acts as a cut for the proof of the assertion. The boolean expression is proved first, and then it is used as an intermediate step to prove the assertion itself.

### Lemmas for Accuracy of Floating-Point Computations

New lemmas have been added to the lemma library of SPARK. They allow bounding the basic floating-point operations `(+ , - , * , /)` with respect to their real counterpart. They also state that floating-point operations are exact on small-enough integers.

## Tool Automation

### New Prover Versions

The Z3 prover shipped with SPARK was updated to version 4.8.17. The CVC4 prover shipped with SPARK was updated to its successor cvc5 at version 1.0.

### Improved use of Parallelism

The scheduling of provers has changed, and one can expect a better usage of multiple cores in most scenarios. This leads to a shorter running time of SPARK.

## Tool Interaction

### Support for Visual Studio Code

The Ada/SPARK extension for Visual Studio Code now supports the following tasks to run GNATprove interactively:

- Examine project, Examine file and Examine subprogram to run GNATprove in flow analysis mode on all or part of a project.
- Prove project, Prove file, Prove subprogram, Prove selected region and Prove line to run GNATprove in proof mode on all or part of a project.

### Redesigned Advanced User and Properties Panels in GNAT Studio

In GNAT Studio, selecting the advanced profile in the Preferences leads to a more detailed proof panel when clicking on the SPARK menus, which allows selecting switches that are not present when the basic profile is selected. This panel has been redesigned so that it contains the most useful switches for advanced interactive use. Similarly, the panel for GNATprove project properties has been redesigned so that it contains the most useful switches for project settings (stored in the project file).

Tooltips have also been added to all panels.

Image (not mirrored): `_images/redesigned_advanced_proof_panel.png`

### Better Source Location for Unproved Checks

GNATprove already pointed at the precise property that could not be proved in a number of cases where multiple properties are checked. For example, on the incorrect code:

    type T is record
       X, Y : Integer;
    end record
      with Predicate => X > 0 and then Y > 0 and then X < Y;

    X : T := (10, 9);

GNATprove issues a predicate check message pointing at the failing conjunct `X < Y`:

    loc.adb:8:13: medium: predicate check might fail, cannot prove X < y
      8 |   X : T := (10, 9);
        |            ^~~~~~

Now, GNATprove also points to the source code for the failing property:

    loc.adb:8:13: medium: predicate check might fail, cannot prove X < y
      8 |   X : T := (10, 9);
        |            ^~~~~~
    in inlined predicate at loc.adb:6

This is useful to understand where a property originates in assertions, in particular for implicit checks like predicate checks and checks related to the default value of types.

### More Counterexamples on Unproved Checks

After the introduction of concrete execution of counterexamples in the last release, to avoid displaying incorrect counterexamples, many valid counterexamples were not displayed anymore because they could not be shown to correspond to a concrete execution. We have completed the two levels of concrete execution on which this feature is based (at the level of Why3 intermediate language, and at the level of the SPARK program) so that GNATprove can more often display valid counterexamples generated by the underlying automatic prover.

### Generation of a Default Project File

GNATprove now supports being called on the command line without a project file. The tool automatically uses the project file of the current folder, or creates a trivial project file if the current directory does not contain one.

### Justified Check Messages Listed on Standard Output

GNATprove now lists justified check messages, together with messages for proved/unproved checks, when using switch `--report` with the values “all”, “provers” or “statistics”. For every pragma `Annotate` that justifies a check message with the reason `Intentional` or `False_Positive`, a message of the form:

    file:line:col: info: <check kind> justified

is generated on standard output. This helps with reviewing justified messages, and completes the existing information in the generated `gnatprove.out` file.

©AdaCore. | Powered by Sphinx & Alabaster.
