# SPARK 20 Release Notes

Source: https://docs.adacore.com/live/wave/spark2014-release-notes/html/spark2014_release_note/release_notes_20.html  
Fetched: 2026-03-01

Complete list (not mirrored): `https://docs.adacore.com/R/relnotes/features-spark-20`

We present here a few highlights of the new features in SPARK 20.

## Improved Support of Language Features

### Support for Pointers Through Ownership

SPARK now supports pointers (a.k.a. values of access type) through the restrictions provided by ownership rules. These rules guarantee that, at any given point in the program, there is a unique name to refer to mutable data, which makes formal verification possible without requiring a huge annotation effort from users.

It makes it possible to implement in SPARK data structures that could only previously be implemented in Ada and made available to SPARK analysis through an interface (private types with an API):

- data structures whose size evolves;
- data structure containing indefinite elements, such as `String`;
- recursive data structures (lists, trees).

The detailed ownership rules are defined in the SPARK 2014 Reference Manual. They revolve around the three key notions of move, borrow and observe, which correspond respectively to the notions of move, mutable borrow and borrow in the Rust programming language. A brief introduction to the SPARK ownership policy is provided in the SPARK User’s Guide. With respect to the rules presented in SPARK RM, the initial support in GNATprove does not yet attempt to verify absence of memory leaks.

See also the blog post “Using Pointers in SPARK” (blog.adacore.com).

### Allow SPARK_Mode Off Inside Subprograms

Aspect or pragma `SPARK_Mode` is now allowed with the value `Off` inside a subprogram, on a local package or subprogram spec/body. It is particularly useful for instantiating a generic whose body is marked `SPARK_Mode Off` inside a subprogram.

Here is a simple example of use, on which GNATprove proves the postcondition of SPARK procedure `Wrapper` using the postcondition of the non-SPARK local procedure `Update_X` (which cannot be in SPARK because it uses attribute `Access`, which remains outside of the SPARK subset even with the new support for pointers):

    procedure Wrapper (X : aliased out Integer) with
      SPARK_Mode,
      Post => X = 42
    is
       procedure Update_X with
         Global => (Output => X),
         Post   => X = 42;

       procedure Update_X with
         SPARK_Mode => Off
       is
          A : access Integer := X'Access;
       begin
          A.all := 421;
       end Update_X;

    begin
       Update_X;
    end Wrapper;

## Program Specification

### Support for Volatile Variables to Prevent Compiler Optimizations

SPARK now supports volatile variables whose aim is not to interact with the physical world, but simply to prevent compiler optimizations. Such variables are used for example to defend against fault injections by duplicating the guards to access a critical section of the code. This is now possible in SPARK when the volatile variable is marked with aspect or pragma `No_Caching`. Here is an example of use to defend against fault injection attacks:

    Cond : Boolean with Volatile, No_Caching := Some_Computation;

    if not Cond then
        return;
    end if;

    if not Cond then
        return;
    end if;

    if Cond then
        -- here do some critical work
    end if;

### Contracts Added to Ada Standard Library

Multiple units of the Ada Standard Library were enhanced with contracts specifying their effects (using `Abstract_State` on packages and `Global` on subprograms) and their functionality (using `Pre` and `Post` on subprograms):

- An abstract state `File_System` is declared in `Ada.Text_IO` to represent interactions between the program and a file system. The API of `Ada.Text_IO` and its child packages has been enhanced to indicate where the file system is read or written. As a result, GNATprove no longer raises warnings about missing global contracts when using subprograms from `Ada.Text_IO`. Additionally `Status_Error` and `Mode_Error` are modelled in preconditions and postconditions, leading to corresponding Verification Conditions on user code calling the API.
- String manipulation units `Ada.Strings.Fixed`, `Ada.Strings.Bounded` and `Ada.Strings.Unbounded` have been enhanced with preconditions and postconditions, leading to corresponding Verification Conditions on user code calling the API.
- Subprograms from unit `Ada.Task_Identification` have been enhanced with preconditions, leading to corresponding Verification Conditions on user code calling the API.

## Tool Automation

### Improved Floating-Point Support in Alt-Ergo Prover

The Alt-Ergo prover that is shipped with GNATprove has been updated. It now includes improved support for reasoning about computations that involve floating point numbers. This enhancement may result in fewer unproved checks. To benefit from the enhancement, a level higher than 0 should be selected via the `--level` switch, or the alt-ergo prover should be selected explicitly by including it in the provers provided via the `--prover` switch.

For an example of properties that become provable with this enhanced support, see the blog post “Floating-Point Computations in SPARK” (blog.adacore.com).

### Precise Proof of Initial_Condition Across Units

When the proof of the `Initial_Condition` for a unit depends on the `Initial_Condition` of another with’ed unit being satisfied, GNATprove can now use the condition of the with’ed unit in the proof provided the elaboration of this other unit is “known to precede” (as defined in SPARK RM 7.7(2)) the elaboration of the current unit.

### Better Support for Recursive Functions

GNATprove now assumes the postcondition of recursive functions annotated with `Terminating` in more cases. In particular, it now assumes it for functions called from non-mutually recursive subprograms, and so, even when the function is called from a contract, while still preserving soundness.

### Parallel Analysis of Subprograms

Subprograms in the same unit are now analyzed in parallel. This can lead to speedups especially in the case of few large units with many subprograms, or when analyzing a single unit during development.

For example, analysis at level 2 of the example SPARKSkein distributed with GNATprove takes 3 minutes 36 seconds with SPARK Pro 19 and only 2 minutes 33 seconds with SPARK Pro 20, using 4 cores at 2.4 GHz of an Intel Xeon CPU running Linux 64 bits (average over two runs), for a decrease of 30% in running time.

As another example, analysis at level 2 of the largest file `enclave.adb` of example Tokeneer distributed with GNATprove takes 50 seconds with SPARK Pro 19 and only 23 seconds with SPARK Pro 20, using 8 cores at 2.4 GHz of an Intel Xeon CPU running Linux 64 bits (average over three runs), for a decrease of 54% in running time.

## Tool Interaction

### Better Messages From Flow Analysis

GNATprove now emits info messages “data dependencies proved” and “flow dependencies proved” respectively for every `Global` and `Depends` contract that have been verified.

GNATprove now emits either a check on each access to a possibly uninitialized object, or a single info message on the object’s declaration when all accesses happen after the object has been initialized. Previously GNATprove could emit both info messages and checks, which was confusing, especially for arrays and objects accessed from different subprograms.

### Summary Table Now Lists All Check Messages

Now all checks verified by GNATprove are accounted for in the summary table printed at the top of the log file `gnatprove.out`, whether the check comes from flow analysis or from proof. New categories of checks have been added:

- “Data Dependencies” for `Global` contracts
- “Flow Dependencies” for `Depends` contracts
- “Termination” for subprogram termination
- “Concurrency” for concurrency-related checks

Note that the categories “Run-time Checks” and “Termination” may contain checks from both flow analysis and proof. Here is an example of summary table generated for the Tokeneer example distributed with GNATprove:

    -----------------------------------------------------------------------------------------------------------------------------
    SPARK Analysis results        Total          Flow   Interval   CodePeer                        Provers   Justified   Unproved
    -----------------------------------------------------------------------------------------------------------------------------
    Data Dependencies               281           281          .          .                              .           .          .
    Flow Dependencies               228           228          .          .                              .           .          .
    Initialization                  693           692          .          .                              .           1          .
    Non-Aliasing                      .             .          .          .                              .           .          .
    Run-time Checks                 474             .          .          .     458 (CVC4 95%, Trivial 5%)          16          .
    Assertions                       45             .          .          .     45 (CVC4 82%, Trivial 18%)           .          .
    Functional Contracts            304             .          .          .    302 (CVC4 82%, Trivial 18%)           2          .
    LSP Verification                  .             .          .          .                              .           .          .
    Termination                       .             .          .          .                              .           .          .
    Concurrency                       .             .          .          .                              .           .          .
    -----------------------------------------------------------------------------------------------------------------------------
    Total                          2025    1201 (59%)          .          .                      805 (40%)     19 (1%)          .

Note the use of “Trivial” prover to denote checks proved by GNATprove without calling any automatic prover.

### Dead Code Detected by Proof Warnings

The switch `--proof-warnings` which was introduced in SPARK Pro 19 to detect inconsistencies now triggers detection of dead code after branches in the program (in if-statements, case-statements and loops) where previously only dead code after loops was detected. Unreachable branches in all expressions are also detected where previously this was restricted to expressions inside assertions and contracts. For example, GNATprove now issues the following messages:

    dead.adb:6:18: warning: unreachable branch
    dead.adb:8:12: warning: unreachable code
    dead.adb:13:09: warning: unreachable code

when run with switch `--proof-warnings` on the following code:

     1 procedure Dead (X : Integer; R : out Boolean) with SPARK_Mode is
     2   Y : Natural := abs (X / 2);
     3 begin
     4   if X < Y then
     5      if X in 1 .. 100
     6        and then Y > 42
     7      then
     8         R := True;
     9      end if;
    10   elsif X >= 0 then
    11      R := True;
    12   else
    13      R := False;
    14   end if;
    15 end Dead;

### Decrease Occurrences of Spurious Counterexamples

Counterexamples displayed by GNATprove when a check is not proved are best efforts by the underlying provers, which may turn out to be spurious in some cases. This was often the case for counterexamples of “all zeroes”, where each variable gets a value of zero (or the equivalent enumeration value for enumerated types). These counterexamples are not presented to the user anymore.

### Unproved Parts of Preconditions Identified

When the precondition of a call is unproved, GNATprove can now identify the part of the precondition which was not proved. This feature was already available for other assertion types, but not for preconditions. For example, GNATprove now issues the following messages:

    context.adb:8:07: medium: precondition might fail, cannot prove X > 0
    context.adb:9:07: medium: precondition might fail, cannot prove X > Y
    context.adb:10:07: medium: precondition might fail, cannot prove Y < 100

when run on the following code:

     1 package Context
     2  with SPARK_Mode
     3 is
     4   procedure Do_Action (X, Y : Integer) with
     5     Global => null,
     6     Pre => X > 0 and then X > Y and then Y < 100;
     7
     8   procedure Call_Action;
     9
    10 end Context;
     1 package body Context
     2  with SPARK_Mode
     3 is
     4   procedure Do_Action (X, Y : Integer) is null;
     5
     6   procedure Call_Action is
     7   begin
     8      Do_Action (-1, -2);
     9      Do_Action (42, 99);
    10      Do_Action (1000, 100);
    11   end Call_Action;
    12
    13 end Context;

## Tool Usability

### Automatic Target Configuration for GNAT Runtimes

If the runtime used for a project analyzed with GNATprove has a target configuration file (this is the case for recent GNAT runtimes), GNATprove can use this file automatically to configure the analysis for the target and runtime. In that case, manual target configuration via the `-gnateT` switch is not necessary anymore. The project file needs to specify attributes `Target` and `Runtime`.

### Better Warnings on Useless Code

GNATprove no longer emits warnings about statements having no effect for assignments to objects whose name contains one of the substrings DISCARD, DUMMY, IGNORE, JUNK, UNUSED in any casing. Similar warnings were already suppressed when compiling the code with GNAT; now they are also suppressed when analyzing the code with GNATprove.

GNATprove now emits warnings about ineffective statements in ghost subprograms. Previously such warnings were only emitted for non-ghost subprograms.

### GNATprove Now Defines GPR_TOOL Variable

The `GPR_TOOL` variable is set by various AdaCore tools and can be used to define tool-specific values of variables in the project file. GNATprove now also sets this variable; it is set to the value `gnatprove`.

### Ability to Specify File-Specific Switches

A subset of GNATprove switches can now be specified for specific files of a project, typically to adjust the proof effort (prover timeout, steps and memory limit). To this end, a new project file attribute `Proof_Switches` has been introduced. It can be used in this way:

    package Prove is
       for Proof_Switches ("Ada") use ("--report=all");
       for Proof_Switches ("file.adb") use ("--timeout=10");
    end Prove;

The existing `Switches` attribute is now deprecated and `Proof_Switches` should be used instead.

### New Switch `--prover=all`

The existing switch `--prover` of SPARK now accepts the special string `all`, which is equivalent to the provers cvc4, z3 and alt-ergo for SPARK Pro, and equivalent to alt-ergo for SPARK Discovery.

©AdaCore. | Powered by Sphinx & Alabaster.

