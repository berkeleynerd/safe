# SPARK 26 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_26.html  
Fetched: 2026-03-01

You can access the complete list here (not mirrored): `https://docs.adacore.com/live/wave/features/txt/features-spark-26/features-spark-26`

The SPARK 26.0 release includes all the changes in 25.0 and the following new features.

## Language Extensions

- This version provides support for private with types. These can be used in SPARK and proved.
- A new attribute `.Old` is available in postconditions. Its interpretation is as described in the Ada RM. This attribute is currently only available on variables in global scope (either global variables or parameters).
- A new aspect `Exceptional_Cases` is available. Its interpretation is described in the SPARK User's Guide.

## New Mode for GNATcheck

A new option `--mode=spark` is available in GNATcheck. In this mode, GNATcheck will enforce the SPARK coding standard, and will also check restrictions specific to SPARK, such as the absence of side-effects in expressions and the coverage of all global variables by Global/Depends contracts.

## Improvements to Support for Contract Cases

In SPARK 25.0, contract cases were introduced, but not all supporting checks for this feature were performed by the tool. This version completes this support. In this version, the tool will:

- Add checks that in contract cases, the `then` keyword is present at most once.
- Add checks that the `then` keyword appears before any `elsif`.
- Remove the possibility for `then` to appear after any `elsif`.
- Add checks that no `then` keyword appears after any `else`.

## Improvements to Support for `finally` keyword in postconditions

Support for a `finally` keyword was introduced in SPARK 25.0. This version adds checks on the use of this keyword:

- The `finally` keyword can only appear once at the end of a postcondition.
- When the `finally` keyword appears, the else expression in conditional expressions cannot be omitted.
- Postconditions containing conditional expressions should always have their else branch (i.e. it cannot be omitted).

## Support for `SPARKlib_Defensive` in GNATproof

In SPARK 25.0, a new GNATcheck rule was introduced to enforce a new defensive programming mode in SPARK, requiring the use of full defensive checks and range checks for all scalar types. This version includes support for this mode in GNATproof.

## Other Bug Fixes

The SPARK 26.0 release includes a number of bug fixes to existing features, including:

- Provide support for aspects which are specifying using classwide types.
- Fix bug in proof of scalar array aggregate.
- Fix bug in proof for iterated component associations.
- Improve `-gnatw.t` by adding a warning when used in SPARK.
- Fix bug in discharge of checks in unsafe reclaim.
- Fix missing computation of globals for generic actuals.
- Improve security of the SPARK toolchain by further hardening the structure of log files.
- Fix soundness issue in proof of strict equality.
- Fix issue with overflow checking for bitwise operation.
- Fix issue with provenance of error messages on inlining.
- Fix issue with wrong location for warning about non-converging loops.
- Fix issue with generation of `raised` and `executed` checks in the event of unexpected errors.
- Fix issue with wrong location for split form of equality between arrays.
- Fix issue with wrong location for unused variable warnings.
- Fix issue in common misuse suggestions on exit statements.

© Copyright 2025, AdaCore.

