# SPARK 25 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_25.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-25`

We present here a few highlights of the new features in SPARK 25.

## Improved Support for Delta Aggregates and Container Aggregates

SPARK 25 has seen some improvements related to Delta Aggregates, which allow specifying a record object, expressing how it is different from an existing record, and the introduction of the Ada 2022 Aggregate aspects for containers. Let’s take a closer look.

### Support for the GNAT Extension for Deep Delta Aggregates

As a GNAT-specific extension, subcomponents can be used as choices in delta aggregates, in addition to top-level components, when specifying which components have changed. As part of the experimental extensions in GNAT, this is allowed by using the switch `-gnatX0` or pragma `Extensions_Allowed(All)`. Both array and record subcomponents are supported, as can we seen in the following example:

    type Pair is record
       Left, Right : Integer;
    end record;

    type Index is range 1 .. 10;
    type Pairs is array (Index) of Pair;

    procedure Zero_Left_Of_Pair_At_Index (P : in out Pairs; I : Index) with
      Post => P = (P'Old with delta (I).Left => 0);

### Support for the Ada 2022 Aggregate Aspect

The Aggregate aspect makes it possible to define aggregates for complex data structures. They are called container aggregates. This aspect is now supported in SPARK, but requires additional annotations to be handled by GNATprove. The container library provided in the SPARKlib has been annotated with this aspect, so it is now possible to use aggregates for formal and functional containers:

    package Integer_Sets is new SPARK.Containers.Formal.Ordered_Sets (Integer);
    S : Integer_Sets.Set := [1, 2, 3, 4, 12, 42];

    package String_Lists is new
      SPARK.Containers.Formal.Unbounded_Doubly_Linked_Lists (String);
    L : String_Lists.List := ["foo", "bar", "foobar"];

    package Int_To_String_Maps is new
      SPARK.Containers.Functional.Maps (Integer, String);
    M : Int_To_String_Maps.Map := [1 => "one", 2 => "two", 3 => "three"];

## Program Specification

### Annotation for Functions with Side Effects

In general, functions in SPARK shall have no side effects. This is essential to be able to call functions in assertions and contracts, as we don’t expect specifications to have an effect. This restriction has now been partially lifted. It is possible to declare functions with side effects in SPARK ((in-)out parameters and globals, non-termination, raising exceptions) if they are annotated with the aspect `Side_Effects`.

A call to such a function can only occur in a list of statements, directly on the right-hand side of an assignment:

    function Increment_And_Return (X : in out Integer) return Integer
      with Side_Effects;

    procedure Call is
      X : Integer := 5;
      Y : Integer;
    begin
      Y := Increment_And_Return (X);
      --  The value of X is 6 here
    end Call;

This feature facilitates writing bindings to C libraries, which often contain functions with side effects and meaningful return values.

### Annotation for Mutable IN Parameters

In SPARK, parameters of mode IN and every object they designate are considered to be preserved by subprogram calls unless the parameters are of an access-to-variable type. In particular, IN parameters of a private type whose full view is an access-to-variable type are considered as entirely immutable in SPARK. However, it is rather common for existing Ada libraries to modify the value designated by such parameters.

The `Mutable_In_Parameter` annotation instructs the SPARK toolset that such parameters should be considered as potentially modified by a subprogram. This annotation is meant primarily to interact with existing Ada libraries from SPARK code.

### Annotation No_Bitwise_Operations on Modular Types

Mixing mathematical integers and bitvectors in some provers (cvc5 and z3) sometimes leads to difficult proofs. The annotation `No_Bitwise_Operations` on a modular type forces the use of mathematical integers in the prover for such a type, instead of a bitvector. Note that a type with the annotation cannot be used in bitwise operations (not, or, and, xor, shifts and rotates).

### Annotation for Access-To-Subprogram Types Used for Handlers

A new annotation has been designed for access-to-subprogram types used for handlers - for example for interrupts. Unlike other access-to-subprogram types, such types can designate subprograms that access or update global synchronized data. The subprograms designated by access values of such types cannot be called in SPARK code.

## New Contracts for SPARK-compatible Libraries

With SPARK 25 come new SPARK-compatibles libraries. `Ada.Strings.Unbounded` have a set of complete contracts, following what was implemented in `Ada.Strings.Fixed` and `Ada.Strings.Bounded`. A new SPARK-compatible library of wrappers for `Interfaces.C.Strings` has been developed and is available in SPARKlib, as `SPARK.C.Constant_Strings`. New Global contracts have been added to the functions in the `Ada.Generic_Elementary_Functions` package.

## Tool Automation

### New Prover Versions

The Z3 prover shipped with SPARK was updated to version 4.12.4. The cvc5 prover shipped with SPARK was updated to version 1.1.0.

### Improved Performance for Large Projects

Several performance improvements have been implemented in SPARK 25. In particular, units that contain or depend on a large number of declarations are processed faster now. Similarly, units that refer to large records without actually referencing any of the fields are processed faster.

### Unchecked_Conversion Precisely Checked in SPARK

When processing an instance of `Ada.Unchecked_Conversion`, SPARK was checking that the conversion makes sense: that it cannot generate an invalid value, that it always produces the same result given equal inputs, that the size of the source and target types are the same, etc.

In addition to taking the size and alignment of types from the representation data generated by the compiler for the specified target, which was added in SPARK 24, GNATprove now also models precisely how bit patterns in the source type map to bit patterns in the target type, for most cases.

### Managing Proof Context

By default, when verifying a part of a program, GNATprove chooses which information is available for proof based on a liberal notion of visibility: everything is visible except if it is declared in the body of another (possibly nested) unit.

It assumes values of global constants, postconditions of called subprograms, bodies of expression functions… This behavior can be tuned either globally or, in some cases, specifically for the analysis of a given unit, using the dual annotations `Hide_Info` and `Unhide_Info`. For now, these annotations cover 3 use cases:

- To hide the private part of withed units.
- To disclose the body of a local package.
- To remove bodies of expression function locally on a case by case basis.

Information hiding is decided at the level of an entity for which checks are generated. It cannot be refined in a smaller scope.

### Detection of Proof Cycles

In the past, SPARK had a documented tool limitation stating that undetected cycles in proof could result in an error message, as such cycles could cause unsoundness. SPARK 25 includes an automatic detection of such cycles caused by subtype predicates and type invariants, primitive equalities, Ownership and Iterable annotations among others.

## Tool Interaction

### Specify Subprogram by Name Instead of Location

The switch `--limit-subp` allows users to limit the analysis to a single subprogram, specified by a file and line number. However, when the line number changes, the command-line switch needs to be updated as well, which is cumbersome. What is more, previously GNATprove did not do a good job of alerting users that the argument to `--limit-subp` was incorrect after the change.

Two changes improve the situation in SPARK 25. First, SPARK now detects a `--limit-subp` argument that doesn’t correspond to a subprogram. Second, a new switch `--limit-name` has been introduced, which takes a subprogram name as an argument. This variant is more robust with respect to changes of location of the subprogram.

### Parallel Invocations

Previously, GNATprove could not be invoked in parallel on the same project file. This is now possible, assuming that each invocation works with different object directories. This can be achieved using scenario variables.

### Hard-to-Prove Checks Listed in the Log

The `gnatprove.out` file generated for a gnatprove run now contains information about the 10 checks that were the hardest to prove, based on the maximum time taken by a prover to prove a VC contributing to the check. Users can look up this information to focus their efforts in reducing proving time and increasing proof robustness.

## Incompatible Changes

### Removal of the CVC4 Prover

SPARK 24 still contained the now-obsolete CVC4 prover alongside its more modern variant, cvc5. In SPARK 25, CVC4 has now been removed.

### Removal of Interactive Proof in GNAT Studio

The interactive proof feature, allowing users to apply tactics inside GNAT Studio to formulas in order to get them proved, has been removed from the SPARK product. This feature was made obsolete by improvements to autoactive proof through ghost code combined with the ability to use interactive proof inside the Coq proof assistant, also from GNAT Studio.

### Command-Line Switches

The switch `--proof-warnings` now needs an argument `on` or `off`. Previous usage of the switch should be replaced by `--proof-warnings=on`.

### SPARK Library

The `Modulus` generic argument is now removed from the generic packages in `SPARK.Containers.Formal.Unbounded_Hashed_Maps` and `SPARK.Containers.Formal.Unbounded_Hashed_Sets`. This requires user code to change, for example instead of writing:

    package Sets is new SPARK.Containers.Formal.Unbounded_Hashed_Sets
    (String, Ada.Strings.Hash);

    S : Sets.Set (Default_Modulus (4));

one should now write simply:

    S : Sets.Set;

©AdaCore. | Powered by Sphinx & Alabaster.

