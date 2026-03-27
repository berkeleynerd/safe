# SPARK 21 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_21.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-21`

We present here a few highlights of the new features in SPARK 21.

## Improved Support of Language Features

### Support for Ada 202X Features

GNATprove now supports many new features introduced by the upcoming standard Ada 202X:

- Declare expressions, which allow users to declare constants inside an expression. This is one of the features users were expecting the most in the new standard, as it makes complicated contracts easier to read.
- Delta aggregates, which are the standard version of the existing `Update` attribute which was introduced for SPARK. As a result, attribute `Update` is now considered deprecated in SPARK and candidate for removal in a future release. It is recommended to use compiler switch `-gnatj` to warn about use of deprecated features, and replace occurrences of attribute `Update` with equivalent delta aggregate syntax.
- Contracts on access-to-subprogram types, which make it possible to support access-to-subprogram types in SPARK, for declaring objects of such a type, creating references to the `Access` attribute whose prefix is a subprogram name, and calling through dereferences.
- The `@` symbol, used to stand for the target name in the right hand side of an assignment.
- Iterated component associations which can be used inside an array aggregate to specify values that depend on the associated index. Only associations with a discrete choice list (as opposed to an iterator specification) are currently supported.

### Detection of Memory Leaks by Proof

A well-known caveat of using dynamic memory allocation is that it’s extremely hard to properly manually deallocate memory, which results in so-called memory leaks where memory is no longer usable by the program, possibly resulting in exhausting all available memory after some time. The support for pointers in SPARK 20 allowed users to protect programs against all memory-related errors except for memory leaks.

Now, GNATprove reports when a piece of memory is still owned by a variable being assigned or whose scope is ending. Unless the ownership of the underlying memory is passed on to another variable, the memory should be released by calling (directly or indirectly) `Ada.Unchecked_Deallocation` or an equivalent procedure releasing the memory.

### Improved Checking for Data Validity

GNATprove now detects uses of `Unchecked_Conversion` or overlays (two variables having the same memory address) that can introduce invalid values. This is achieved by checking that the target type has all the right properties that ensure invalid values cannot appear. Otherwise GNATprove issues a check message to notify the user.

### Support for Raise Expressions

Raise expressions are now supported by GNATprove. As for raise statements, checks are generated to make sure that no exceptions can be raised during execution. As a special case, raise expressions in preconditions are considered to be failures of the precondition, and not run-time errors. This allows one to introduce specific exceptions for the failure of each part of a precondition, like in the following example:

    procedure Add_To_Total (Incr : in Integer) with
      Pre => (Incr >= 0 or else raise Negative_Increment)
        and then (Total in 0 .. Integer'Last - Incr
                    or else raise Total_Out_Of_Bounds);

which GNATprove treats like the equivalent:

    procedure Add_To_Total (Incr : in Integer) with
      Pre => Incr >= 0
        and then Total in 0 .. Integer'Last - Incr;

### Support for Forward Goto

It is now possible to use the infamous goto in SPARK. While generally frowned upon, the use of goto is essential for providing some finalization in the absence of other mechanisms (for example on embedded targets where the Ravenscar runtime does not support controlled types).

## Program Specification

### Support for Partially Initialized Data in Proof

It is now possible to opt out of the strong data initialization policy of SPARK on a case by case basis using the new aspect `Relaxed_Initialization`. Parts of objects subjected to this aspect only need to be initialized when actually read. Using `Relaxed_Initialization` requires specifying data initialization through contracts that are verified by proof (as opposed to flow analysis), based on the new attribute `Initialized` for specifying which data is initialized.

Thus, it is possible to specify a type for stacks that hold `Top` initialized elements in their `Content` array, without having to initialize the rest of the array:

    type Content_Type is array (Positive range 1 .. 100) of Integer with
      Relaxed_Initialization;

    type Stack is record
       Top     : Natural := 0;
       Content : Content_Type;
    end record
      with Predicate => Top in 0 .. 100
        and then (for all I in 1 .. Top => Content (I)'Initialized);

See the SPARK User’s Guide for more details.

### Support for Infinite Precision Arithmetic

GNATprove support was added for the new infinite precision integer/real arithmetic units added in Ada 202X, called `Ada.Numerics.Big_Numbers.Big_Integers` and `Ada.Numerics.Big_Numbers.Big_Reals`. In particular, the type `Big_Integer` and its associated arithmetic operations can be used in specifications (contracts, invariants, etc.) when machine integer arithmetic could lead to overflows.

This provides a more powerful solution than the use of pragma `Overflow_Mode`, as it allows to use unbounded integers not only for intermediate computations inside expressions, but also as the type of parameters and function results.

See the SPARK User’s Guide for more details.

### New Annotation Might_Not_Return on Procedures

Procedures which may not return for legitimate reasons can now be analyzed safely by marking them with a GNATprove annotation `Might_Not_Return` (either the pragma or aspect form). It is legitimate for such procedures to call procedures marked `No_Return`, and callers of such procedures must also be marked `Might_Not_Return`. In particular, a function cannot call such a procedure.

See the SPARK User’s Guide for more details.

### Volatility Refinement Aspects Supported for Types

Previously, the four volatility refinement aspects (`Async_Readers`, `Async_Writers`, `Effective_Reads`, and `Effective_Writes`) could only be specified for volatile variables and for state abstractions. These aspects can now be specified for volatile types as well.

The notion of volatility in SPARK has been refined to distinguish objects that can be read without considering a side-effect (with both `Effective_Reads` and `Async_Writers` properties set to False), so that they can be read from non-volatile functions.

### Detection of Wrap-Around on Modular Arithmetic

GNATprove now reports when an arithmetic operation over modular types wraps around, when the modular type has the annotation `(GNATprove, No_Wrap_Around)`. This allows one to use modular types, but still consider it an error to go beyond the bounds of the type.

See the SPARK User’s Guide for more details.

### Variants for Termination of Recursive Subprograms

GNATprove now supports using aspect `Subprogram_Variant` to prove the termination of (mutually) recursive subprograms. This is similar to how loops can be proved to terminate using pragma `Loop_Variant`.

See the SPARK User’s Guide for more details.

## Tool Automation

### Update of CVC4 prover

The CVC4 prover packaged with GNATprove has been updated to version 1.8.

## Tool Interaction

### New SPARK Submenus and Key Shortcuts in GNAT Studio

Some submenus from the contextual SPARK menu have been added to the main SPARK menu in GNAT Studio, for easier access: Examine Subprogram, Prove Subprogram, Prove Selected Region, and Prove Line. Default key shortcuts have been added for Prove File/Subprogram/Region/Line using `Ctrl+Alt+<letter>` where letter is `f/s/r/l`.

### Reason for index/overflow/length/range Checks Now Displayed

Some check messages are harder for users to understand, in particular index/overflow/length/range checks. GNATprove now displays an explanation in the form of a “reason for check” part of some of the check messages, similar to other explanations whose role is to help in understanding the cause for a message. Here are a few examples:

    reason for check: result of addition must fit in a 32-bits machine integer
    reason for check: value must be convertible to the target type of the conversion

    reason for check: result of addition must be a valid index into the array

    reason for check: value must fit in the designated type of the allocator

    reason for check: result of floating-point addition must be bounded

### New Suggested Fix for Missing Postcondition on Function

Functions that are used in specifications need in general to be known to the prover, in order to be able to prove that the program respects the corresponding specification. That knowledge can take the form of an explicit postcondition, or an implicit one in the case of an expression function. GNATprove now issues such information as a suggested fix when encountering an unprovable check where this applies. For example on the following code:

    package Math is
       function Add_One (X : Integer) return Integer;
       procedure Incr (X : in out Integer) with
         Post => X = Add_One (X'Old);
    end Math;

GNATprove issues the following information associated to the message about the unprovable postcondition for `Incr`:

    possible fix: you should consider adding a postcondition to function Add_One
    or turning it into an expression function

### Better Diagnostics from Flow Analysis

GNATprove messages related to flow analysis have been improved in various cases:

- Check messages about potentially nonterminating subprograms are now located on the offending loops or calls and the explanation is more precise.
- Error messages about volatile effects within nonvolatile functions now include which precise volatile variables are referenced within the function body.
- Warnings about subprogram with no effect are now emitted only once on the subprogram itself, instead of on every call.

## Tool Usability

### Prove Line/Region Menu Inside Inlined Subprograms

The Prove Line/Region menus in GNAT Studio are now working to prove a single line or a set of lines from a subprogram, even when the subprogram is inlined for proof. This is especially convenient for proofs inside inlined ghost procedures.

### More Informative and Readable Command-Line Messages

Messages from GNATprove on the command-line are now displayed over multiple lines when they give extra information, instead of a single line. A new switch `--output` has been added, which default to value `pretty` for this multi-line display, and can be set to `brief` to only display the check message without additional information. The multi-line display also shows the corresponding source code for both the main message location and for the locations mentioned in subsequent associated messages.

Here is an example of a multi-line message:

    math.adb:9:14: medium: overflow check might fail
      9 |      X := X + 1;
        |             ^ here
    e.g. when X = Integer'Last
    reason for check: result of addition must fit in a 32-bits machine integer
    possible fix: subprogram at math.ads:3 should mention X in a precondition
      3 |   procedure Incr (X : in out Integer) with
        |   ^ here

### Lemma Library Available Through GNAT Studio Help

The header files for the SPARK Lemma Library are now available through menu `Help` → `SPARK` → `Lemmas` in GNAT Studio. This can be useful to decide whether to include these files as part of a project.

©AdaCore. | Powered by Sphinx & Alabaster.

