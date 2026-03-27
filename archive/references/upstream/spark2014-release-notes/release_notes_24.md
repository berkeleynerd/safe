# SPARK 24 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_24.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-24`

We present here a few highlights of the new features in SPARK 24.

## Vulnerability Report

From 24.2, you can download the SPARK vulnerability report from the Release Download section. It will provide you the list of the CVEs that can impact this product and the corresponding impact analysis describing whether the product is concerned by each CVE.

## Improved Support of Language Features

### Conditional Termination

Previously, GNATprove was designed to support primarily programs that always return normally. For SPARK 24, we extended the SPARK language and GNATprove to make termination explicit, by allowing fine-grained annotation of subprograms that propagate exceptions (see below) or that failing to terminate.

The new `Always_Terminates` aspect allows users to specify procedures that only terminate (return normally) or that raise an exception conditionally, in a fine-grained manner. This aspect can be used to specify a boolean condition on procedure inputs such that, if the condition evaluates to True, then the procedure must terminate.

    procedure P1 (...) with Always_Terminates;
    --  P1 shall terminate on all its inputs

    procedure P2 (...) with Always_Terminates => False;
    --  P2 might terminate on some of its input, but it does not need
    --  to.

    procedure P3 (...) with Always_Terminates => Condition;
    --  P3 shall terminate on all inputs for which Condition evaluates
    --  to True.

Functions in SPARK should still always terminate and therefore cannot be annotated with this aspect.

### Handling and Propagation of Exceptions

Previously, SPARK allowed exceptions to be raised but did not allow exceptions to be propagated or handled. GNATprove thus attempted to verify that raise statements could never be reached - i.e., that they were dead code.

For SPARK 24, we extended the SPARK language and GNATprove to support propagation of exceptions to outer secope and local handling of exceptions. Procedures that might propagate exceptions need to be annotated with the new `Exceptional_Cases` aspect, which allows the exceptions that might be propagated to be listed and associated with an exceptional postcondition.

This postcondition is used both to restrict the set of inputs on which the exception might be propagated and to verify callers when the exception is handled in outer scopes.

    procedure P1 (...) with
      Exceptional_Cases => (others => False);
    --  P1 cannot propagate exceptions. It is the default.

    procedure P2 (...) with
      Exceptional_Cases => (others => True);
    --  P2 might propagate an unspecified exception

    procedure P3 (X : T; Y : out T) with
      Exceptional_Cases =>
        (E1 => Cond1 (X),
         E2 => Cond2 (Y));
    --  P3 might propagate E1 or E2. The exceptional postconditions are
    --  used both to:
    --   * specify in which cases the exception might be raised - E1
    --     can only be propagated on inputs on which Cond1 evaluates to
    --     True.
    --   * describe the effect of the subprogram when the exception is
    --     propagated - when E2 is propagated, Cond2 (Y) evaluates to True.
    --  A mix of the two is also possible.

Functions in SPARK still cannot propagate exceptions, so the aspect cannot be specified for them.

### Enhanced Support for Relaxed_Initialization

The `Relaxed_Initialization` aspect can now be used to relax the initialization policy of SPARK on a case-by-case basis. The support for this feature has been extended to support types annotated with subtype predicates.

### Checks for Parameters of the Container Library

The formal parameters of the container library of SPARK are subject to requirements. For example, the provided equality function shall be an equivalence relation (symmetric, reflexive, and transitive). Previously, these requirements were treated as assumptions by the tool; the user was required to verify them by other means. The container library has been modified so these properties are now verified by the tool on every instance.

If the verification is complex, users can provide lemmas to help the tool as additional parameters of the generic packages.

## Program Specification

### Functional Multisets in the SPARK Library

Functional multisets have been added to the SPARK Library. They are particularly useful in modeling permutations, e.g., when verifying sorting routines.

### GNAT-specific Aspect Ghost_Predicate

Ghost functions cannot be used in subtype predicates for non-ghost types: the predicates may be evaluated as part of normal execution during, e.g., membership tests. To alleviate this restriction, it is now possible to supply a subtype predicate using the `Ghost_Predicate` aspect, making it possible to use ghost entities in its expression. Membership tests are not allowed if the right operand is a type with such a predicate.

## Tool Automation

### New Prover Versions

The Z3 prover shipped with SPARK was updated to version 4.12.2. The cvc5 prover shipped with SPARK was updated to version 1.0.5.

### Better Provability with Containers

The container library of SPARK has been modified to improve provability. In particular, contracts on procedures used to modify these containers now use logical equality instead of Ada equality. This is notably more efficient when both equalities do not coincide because the logical equality, unlike the Ada one, is handled natively by the underlying solvers.

### Better Provability when Using Size Attributes

GNATprove now calls GNAT to generate data representations in order to support more precisely size and alignment attributes in proof.

## Tool Interaction

### Explain Codes

GNATprove now has an option `gnatprove --explain` that prints to standard output a short explanation for emitted messages, similar to `rustc --explain`. This can be used for error messages, warnings, or check messages. When a message has a corresponding explanation, it includes an explanation code, such as `[E0001]`, in the message. Using the command `--gnatprove --explain E0001`, users can display the corresponding explanation.

Note that while the GNAT compiler may also issue messages with an “explain code” for messages related to the use of SPARK, the command to get the explanation is always `gnatprove --explain`.

### Fine-grained Specification of Analysis Mode

For customers who are migrating large bodies of code to SPARK, having to choose between disabling analysis entirely (i.e., setting the `SPARK_Mode` to `Off`) or committing to proof at Silver level (proof of absence of runtime errors) may not always be satisfactory. Previously, the analysis level could be set only at the project level, which is too coarse in such cases.

To help customers who are migrating large bodies of code to SPARK, we introduced two new ways to set a more fine-grained analysis level. First, users can select the analysis level for each unit, by setting the `--mode` switch for specific units in the GPR project file. Second, users can annotate their subprograms with one of two new annotations:

    pragma Annotate (GNATprove, Skip_Proof, Name_Of_Subprogram);
    pragma Annotate (GNATprove, Skip_Flow_And_Proof, Name_Of_Subprogram);

These annotations disable proof on a per-subprogram basis. The annotation `Skip_Proof` allows users to benefit from flow analysis on a subprogram, without having to go to full proof.

### Counterexamples for Floating Point Values

Counterexample checking now supports floating-point numbers, so that counterexamples computed by a prover can be checked before being displayed to the user, when a proof does not pass.

### Better Messages for Initialization and Incomplete Data Dependency

Messages emitted for reads of uninitialized data and incomplete Global and Depends contracts have been improved. Redundant messages are removed, initialization checks are condensed, and more errors are reported at once in case of incomplete contracts.

## Incompatible Changes

### Termination Annotations

The `Annotate` pragmas that used to be defined for termination are no longer supported. This includes `Always_Return`, `Might_Not_Return`, and `Terminating`. The `Always_Terminates` aspect should be used instead on procedures. Termination of functions is now checked by default.

### Command-line Switches

The switch `--checks-as-errors` now needs an argument `on` or `off`. Previous usage of the switch should be replaced by `--checks-as-errors=on`.

©AdaCore. | Powered by Sphinx & Alabaster.

