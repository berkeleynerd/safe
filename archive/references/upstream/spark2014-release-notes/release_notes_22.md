# SPARK 22 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_22.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-22`

We present here a few highlights of the new features in SPARK 22.

## Improved Support of Language Features

### Extended Support for Access Types

SPARK 22 introduces a new model for access types. This model is built on a set of restrictions that guarantee that every access value has a single owner. It provides support for heap allocation and recursive data structures without violating the soundness of the proof. Unlike other ownership models, it is local and does not require whole-program analysis. It can thus be used on subprogram bodies without having to prove callers.

In this model, access values have move semantics. Copying an access value assigns null to the old value:

    type List is record
       Value : Integer;
       Next  : access List;
    end record;

    L1 : access List := new List'(Value => 1, Next => null);
    L2 : access List := L1;
    --  L1 is null here

Access values can also be borrowed or observed in subprogram calls. A borrowed access value allows the access object itself or any object it designates to be modified in a subprogram call. An observed access value allows read-only access to the access object and any object it designates. The lifetime of the borrowed or observed access value is the duration of the subprogram call. During this time, the owned access value cannot be modified or copied. This prevents accidental aliasing.

The model comes with support for:

- Named access-to-constant types, which are treated as observed.
- General access types.
- `'Access` of an object of an anonymous access type.
- `'Access` of an object of a general access-to-variable type.
- `'Access` of an object of a named access-to-constant type.
- Owning components in tagged root types.

### Support for Address Clauses and Overlays

GNATprove can now be used to analyze programs which make use of address clauses. In particular, it can now handle overlays.

### Access Elements in Formal Containers Without Copy

GNATprove can now access elements in formal containers without copying.

### Support for Iterator Filters

GNATprove now supports iterator filters, a new feature of Ada 2022, such as:

    for X of A when X > 0 loop
       ...
    end loop;

## Program Specification

### Functional Contracts on Standard Library Units

In order to help users prove properties of code using the Ada standard library, functional contracts are provided on more library units, which extends the existing set of contracts on the Ada standard library.

## Tool Automation

### New Warnings by Flow Analysis

Flow analysis now includes additional warnings:

- warning on unused initial values of OUT parameters
- warning on dead code due to assertions
- warning on more cases of potentially useless statements
- warning on more cases of potentially incorrect self assignments
- warning on possibly unintended implicit property

In addition, the warning on unused assignments is now issued by flow analysis on constant objects, whereas it was previously issued by proof.

### Improved Reporting of Data Races for Abstract State

Flow analysis can now output messages about possible data races on abstract state, in addition to variables. This can be useful when proving code at the Silver level.

### Additional Automatic Prover COLIBRI

The automatic prover COLIBRI is now shipped with SPARK. This prover can be used with `--prover=colibri` or `--prover=all`. It is also used by default when level 0 is requested with `--level=0`, because it is usually faster than other provers on easy verification conditions.

### New Prover Versions

The Z3 prover shipped with SPARK was updated to version 4.8.16.

## Tool Interaction

### Distinguished Error Messages With `error:` Tag

Error messages, which may correspond to incorrect use of the tool itself, are now distinguished on the command line by the `error:` prefix.

### Better Display of Messages on the Command Line

The output of GNATprove on the command line can now be formatted as a table with the option `--output=pretty`. This output format is now the default.

Image (not mirrored): `_images/command_line_display.png`

### More Precise Identification of Failed Proofs

When running GNATprove with `--report=all` or `--report=provers`, it lists failed proofs. There are now some additional information in these messages:

- for checks in inlined subprograms, the messages are now pointing to the inlined code, not to the original definition.
- similarly, for checks in the expanded code, the messages are pointing to the expanded code.
- a message is now listing which provers failed the check.

### Improved Suggestions for a Fix on Unproved Checks

Suggestion messages have been improved on unproved checks. For example:

- It suggests as a fix to add a precondition that a parameter is non-null if it cannot prove that it is non-null.
- It suggests as a fix to add a precondition that a parameter is in range if it cannot prove that it is in range.
- It suggests as a fix to add a precondition that a parameter is non-zero if it cannot prove that it is non-zero.
- It suggests as a fix to add a precondition that a parameter is in the bounds of an array if it cannot prove it.

It also suggests to add loop invariants or intermediate assertions when it cannot prove a loop.

### Improved Counterexamples on Unproved Checks

Counterexamples have been improved on unproved checks. Counterexample checking is now switched off by default (use switch `--counterexamples=on` to switch it on). Users can now ask GNATprove to generate counterexamples without checking (use switch `--counterexamples=uncheck`), which is faster but might generate incorrect counterexamples. See the User’s Guide for details.

### Display of Generated Global Contracts in GNAT Studio

The global variables used by a subprogram, as computed by flow analysis, can now be displayed in GNAT Studio, by selecting the contextual menu entry “Show Generated Globals” on the corresponding check message.

©AdaCore. | Powered by Sphinx & Alabaster.
