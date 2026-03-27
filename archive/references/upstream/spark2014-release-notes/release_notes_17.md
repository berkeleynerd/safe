# SPARK 17 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_17.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-17`

We present here a few highlights of the new features in SPARK 17.

## Proof Automation

### Integration of CodePeer

The engine of static analyzer CodePeer (www.adacore.com) is now part of SPARK Pro, and can be used to prove run-time checks and assertions, in addition to the other distributed provers Alt-Ergo, CVC4 and Z3. It is activated by using the switch `--codepeer=on` on the command line, or by selecting the checkbox CodePeer Static Analysis in the proof dialog opened in GPS after selecting the SPARK ‣ Prove All, SPARK ‣ Prove File and similar menu entries.

CodePeer is particularly effective for proving range checks and overflow checks, in particular for run-time checks involving floating point variables that other provers have difficulties to handle.

In the summary of analysis results in file `gnatprove.out`, checks proved by CodePeer appear in a separate column. For example, here are the results of a specific run of GNATprove on Tokeneer test:

Image (not mirrored): `_images/gnatprove_out_results.png`

See also the blog post “SPARK and CodePeer, a good match!” (www.spark-2014.org).

### Handling of Floating-point Arithmetic

Checks involving floating-point arithmetic were particularly difficult to prove automatically previously. This has been much improved by the use of the native support for floating-point arithmetic in the automatic prover Z3. Thus, it is recommended to use Z3 prover (with `--prover=z3` or in conjunction with other provers, or equivalently by using a proof level greater than zero) for programs that involve floating-point arithmetic.

The previously described integration of CodePeer also helps proving checks involving floating-point arithmetic. See also the blog post “GNATprove Tips and Tricks: What’s Provable for Real Now?” (www.spark-2014.org).

### Generation of Loop Invariants

Depending on the proof objective (verification of absence of run-time errors, proof that implementation complies with contracts), GNATprove may require users to provide a loop invariant to summarize the effect of a loop. A tedious part of the loop invariant called the frame condition is the specification that parts of a record not modified in a loop, and array cells not yet reached in an array traversal, are not modified in a given iteration of the loop.

As it may seem obvious to the user, the frame condition is unfortunately often forgotten when writing a loop invariant, leading to unprovable checks.

GNATprove now generates automatically frame conditions for unmodified fields of record variables, and unmodified fields of array components in two cases:

- If an array is assigned at an index which is constant through the loop iterations, all the other components are preserved.
- If an array is assigned at the loop index, all the following components (or preceding components if the loop is reversed) are preserved.

See also the blog posts “Automatic Generation of Frame Conditions for Record Components” and “Automatic Generation of Frame Conditions for Array Components” (www.spark-2014.org).

### Library of Lemmas

Some checks (both related to run-time errors and assertions/contracts) are particularly difficult to prove automatically, for example when they depend on multiplication or division between scalar variables. This is related to the weaker support for the so-called non-linear arithmetic operators (like multiplication and division) in provers, compared to the support of linear arithmetic operators (like addition and subtraction).

GNATprove now provides a library of lemmas that can be used to prove such properties. Each lemma in the library is a separate ghost procedure (hence it has no impact on the final executable) with a suitable postcondition expressing the desired property. Each lemma has been separately proved, either using automatic provers or using the Coq interactive prover.

The use of lemmas allows to address more complex properties than cannot be proved fully automatically, with manageable complexity for the user, represented by the ghost code label in the following diagram:

Image (not mirrored): `_images/degree_of_automation.png`

See also the blog posts “GNATprove Tips and Tricks: Using the Lemma Library” and “GNATprove Tips and Tricks: a Lemma for Sorted Arrays” (www.spark-2014.org).

### Automatic Splitting of Conjunctions

Assertions, loop invariants and pre- and postconditions which consist of several parts combined with `and` or `and then`, are now proved separately by SPARK. Previously, this was only done when the proof mode was set to `per_path` or `progressive`, or equivalently at higher proof levels.

This allows better reporting of which part of a check is unproved, and it also allows better interaction between provers, where one prover may be able to prove one part of the check, and another one the remaining part.

## Proof Interaction

### Counterexamples

More values are now displayed in the counterexamples generated by GNATprove on failed proof attempts:

- values of attributes `First` and `Last` for values of array types
- enumeration literals for variables of enumeration types
- universally quantified variables (in loop invariants for example)

### Proof Results

Switch `--report` now takes two additional values `provers` and `statistics` for outputting additional information on proved checks.

With `--report=all`, messages like the following are output:

    linear_search.ads:39:33: info: discriminant check proved

With `--report=provers`, messages like the following are output:

    linear_search.ads:39:33: info: discriminant check proved (CVC4 : 13 VC;
      altergo : 2 VC)

With `--report=statistics`, messages like the following are output:

    linear_search.ads:39:33: info: discriminant check proved (CVC4: 13 VC
      proved in max 2.3 seconds and 120 steps; altergo: 2 VC proved in max
      10 seconds and 200 steps)

### Display and Replay Modes

It is now possible to display the previous results of proof without rerunning GNATprove (the display mode), and to rerun GNATprove with the same prover being used for each check previously proved (the replay mode).

The display mode is most useful during development, to quickly find out which checks are proved or not without rerunning the proof. This mode is available by adding the switch `--output-msg-only` on the command line, or by selecting the checkbox Display previous results in the proof dialog opened in GPS after selecting the SPARK ‣ Prove All, SPARK ‣ Prove File and similar menu entries.

The replay mode is most useful during (daily or nightly) validation runs, to repeat the proofs previously performed and stored in the session files. See the SPARK User’s Guide for instructions on sharing of session files. This mode is available by adding the switch `--replay` on the command line.

If this switch is passed to GNATprove, it will attempt to replay the proofs of all checks that are marked as proved in the session files, using for each VC the same prover that succeeded in proving it, and a step limit that was sufficient to make the proof succeed. This feature provides an efficient way of checking that all proofs still go through, e.g. after pervasive but minor code modifications, or an upgrade of the SPARK tools.

### Manual Provers

The interface between SPARK toolset and manual provers has been improved:

- It is now possible to use the external why3ide tool on session files generated by GNATprove.
- Transformations stored in session files through the use of the external why3ide tool are now reexecuted by GNATprove.
- A Coq configuration is predefined in the default `why3.conf` configuration file.

Various problems when calling manual provers from GPS have been fixed.

## Improved Support of Language Features

### Type Invariants

Type invariants are now supported in SPARK, with some limitations compared to Ada 2012 in order to make them fully reliable in SPARK. In particular, type invariants in SPARK cannot refer to the value of variables except for the special current variable on which the type invariant is defined, as this would allow a type invariant to be violated as soon as the external variable is modified.

For example, here is a type invariant defining that a type `Tree` indeed defines a tree structure:

    type Tree is record
       Top : Extended_Index_Type := 0;
       C   : Cell_Array;
    end record
      with Type_Invariant => Tree_Structure (Tree);

    function Tree_Structure (T : Tree) return Boolean is
      ((if T.Top /= 0 then T.C (T.Top).Parent = 0
        and then T.C (T.Top).Position = Top)
       and then
         (for all I in Index_Type =>
              (if T.C (I).Left /= 0
               then T.C (T.C (I).Left).Position = Left
                 and then T.C (T.C (I).Left).Parent = I))
       and then
         ...

See also the blog post “SPARK 2014 Rationale: Support for Type Invariants” (www.spark-2014.org).

### Extended Ravenscar Profile

The new GNAT Extended Ravenscar profile is supported in SPARK. This profile relaxes some of the restrictions from the Ravenscar profile, and the use of GNATprove still allows to prove the safety of concurrent accesses and absence of deadlocks (or corresponding run-time errors). The main changes compared to Ravenscar are that:

- protected types can define more than one entry, which is convenient for defining message stores,
- expressions in entry barriers are no longer restricted to simple Boolean variables,
- relative delay statements like `delay 1.0` are now allowed,
- package `Ada.Calendar` can be used, which is handy for log messages.

See also the blog post “Verifying tasking in extended, relaxed style” (www.spark-2014.org).

### Object Oriented Programming

There was a change of semantics in Ada for calls to primitive operations in class-wide preconditions and postconditions, following Ada Issue 12-0113 (www.ada-auth.org). Instead of considering such calls as dispatching, they are specialized for each level of descendant type that inherits the contract. GNATprove now follows the updated semantics for such calls.

©AdaCore. | Powered by Sphinx & Alabaster.

