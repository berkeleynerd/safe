# Annex B — Implementation Advice

**This annex is informative.**

This annex provides implementation guidance for Safe conforming implementations. All recommendations use "should" rather than "shall" — compliance with this annex is not required for conformance. Requirements that are genuinely normative appear in Sections 2–6, not here.

---

## B.1 Dependency Interface Format

1. The dependency interface mechanism (Section 3, §3.5) is implementation-defined. As recommended practice, the per-package dependency interface file should be:

   (a) **Text-based.** UTF-8 encoded, line-oriented, with a versioned header line. Text formats are debuggable, diffable, and amenable to version control.

   (b) **Deterministic.** The same Safe source, compiled with the same implementation version, should always produce byte-identical interface files.

   (c) **Self-describing.** The file should include a version identifier for the format, allowing tools to detect and reject incompatible interface files.

2. The interface file should contain:

   (a) Exported names and their kinds (type, subtype, variable, constant, subprogram, channel).

   (b) Type information including size, alignment, and constraints. For opaque types, size and alignment without field layout.

   (c) Subprogram signatures: parameter names, types, modes, and default values.

   (d) Effect summaries: read-set and write-set for each exported subprogram.

   (e) Channel declarations: element type, capacity.

   (f) Dependency fingerprints: a hash of the interface content for change detection.

3. Deterministic ordering of declarations within the interface file is recommended for stable diffs across compilations.

---

## B.2 Diagnostic Messages

4. Diagnostic messages should follow a consistent format including:

   (a) Source file path.

   (b) Line number and column number.

   (c) Severity level (error, warning, note).

   (d) A human-readable description of the violation.

   (e) Where applicable, a reference to the specification paragraph or rule identifier.

5. Diagnostics should be stable: the same input should produce the same diagnostics in the same order. This supports automated testing and continuous integration.

6. When rejecting a program for a D27 rule violation, the diagnostic should identify:

   (a) Which rule was violated (Rule 1, 2, 3, 4, or 5).

   (b) The source location of the violation.

   (c) Where practical, a suggestion for remediation (e.g., "use a subtype that excludes zero" for Rule 3 violations).

---

## B.3 Incremental Recompilation

7. An implementation should support incremental recompilation: when a package's source changes, only that package and its dependents need recompilation.

8. The fingerprinting strategy for change detection should be:

   (a) Based on the dependency interface content (not the source text), so that changes to private declarations or subprogram bodies that do not affect the public interface do not trigger recompilation of dependents.

   (b) Transitively propagated: if package A depends on package B and B's interface fingerprint changes, A should be recompiled even if A's own source is unchanged.

9. The implementation should document its recompilation rules so that build systems can make correct incremental build decisions.

---

## B.4 Compilation Performance

10. A Safe implementation should target compilation performance suitable for interactive development. As a guideline, compilation throughput of 50,000 source lines per second (including legality checking and interface file generation) is achievable for a single-pass implementation and should be considered a reasonable target.

11. The single-pass compilation model described in the language design (D3 in SPEC-PROMPT.md) is recommended as the implementation strategy. Reading the source token stream once, left to right, building an AST, resolving names, checking types, and enforcing legality rules in a single pass, followed by a post-parse AST walk for output generation, is the intended compilation model.

---

## B.5 Output Quality

12. When an implementation produces intermediate output (Ada/SPARK source, C source, object code, or other representations), the output should be:

   (a) **Deterministic.** The same Safe source should always produce byte-identical output.

   (b) **Human-readable.** Where the output is source code in another language, it should be formatted with consistent indentation, meaningful identifier names, and comments indicating the correspondence to Safe source.

   (c) **Suitable for auditing.** Safety-critical development processes may require review of intermediate representations. Clear formatting and traceability to Safe source locations support this.

### B.5.1 Ada/SPARK Output

13. An implementation that produces Ada/SPARK source output should:

   (a) Generate valid ISO/IEC 8652:2023 source that compiles with SPARK mode enabled.

   (b) Generate `Global`, `Depends`, and `Initializes` aspects automatically, derived from the Safe source analysis.

   (c) Emit `SPARK_Mode` on every generated unit.

   (d) For the tasking model, emit Ada task types with single instances and `Priority` aspects under an appropriate tasking profile.

   (e) For channels, emit synchronisation constructs (e.g., protected objects) with ceiling priority assignment derived from channel-access summaries (Section 3, §3.3.1(i)) and task priorities (Section 4, §4.2, paragraph 21a).

   (f) Emit integer arithmetic directly in a 64-bit signed type and preserve explicit subtype-narrowing checks at the Safe narrowing points.

   (g) Ensure the target platform's floating-point implementation provides IEEE 754 non-trapping semantics (`Machine_Overflows = False` for all predefined floating-point types), as required by D27 Rule 5 (Section 2, §2.8.5). If the target Ada compiler's `Machine_Overflows` is `True` by default, the implementation should configure the floating-point unit for non-trapping mode or document the incompatibility.

   (h) Emit deallocation calls at every scope exit point for pool-specific access objects (both owning and named access-to-constant), including early returns, loop exits, and gotos out of scope.

### B.5.2 C Output

14. An implementation that produces C source output should:

   (a) Generate valid C99 (or later) source.

   (b) Emit range checks as runtime assertions or abort-on-violation checks.

   (c) Emit integer arithmetic using `int64_t` and preserve explicit subtype-narrowing checks at the Safe narrowing points.

   (d) For tasking, emit thread creation using platform-appropriate threading primitives.

   (e) For channels, emit bounded FIFO queues with appropriate synchronisation.

---

## B.6 Elaboration and Tasking Configuration

15. When targeting Ada/SPARK tasking under Ravenscar or Jorvik profile restrictions, the implementation should emit `pragma Partition_Elaboration_Policy(Sequential)` in the configuration file. This defers library-level task activation until all library units are elaborated, preventing elaboration-time data races.

16. Channel-backing synchronisation constructs should use procedures (not functions) for non-blocking operations, as SPARK does not permit functions with `out` parameters:

```ada
-- Recommended pattern for channel try operations
procedure Try_Send (Item : in Element_Type; Success : out Boolean);
procedure Try_Receive (Item : out Element_Type; Success : out Boolean);
```

---

## B.7 Deallocation

17. Automatic deallocation of pool-specific access objects — both owning access-to-variable and named access-to-constant — at scope exit (Section 2, §2.3.5) should be emitted at every scope exit point:

   (a) Normal scope end.

   (b) Early `return` statements.

   (c) `exit` statements that transfer control out of the owning scope.

18. When multiple pool-specific access objects exit scope simultaneously, deallocation should occur in reverse declaration order.

19. The implementation should verify completeness of deallocation logic, either through internal testing or by leveraging external leak-checking capabilities of the target environment.

---

## B.8 Defence-in-Depth

20. Even though the D27 rules guarantee absence of runtime errors for conforming programs, an implementation should consider retaining runtime checks in the generated output as a defence-in-depth measure, particularly:

   (a) During development and testing, to catch implementation bugs in the compiler's legality checking.

   (b) For safety-critical deployments where independent verification of the compiler is incomplete.

21. The decision to retain or remove runtime checks in generated output should be configurable and documented.

---

## B.9 Error Recovery

22. An implementation should attempt to continue parsing and checking after encountering the first error, to report multiple diagnostics in a single compilation pass.

23. Error recovery should not produce cascading false positives. If the implementation cannot recover reliably from a particular error, it should stop with a clear diagnostic rather than emit misleading secondary errors.

---

## B.10 Cross-Compilation

24. An implementation should support cross-compilation: compiling on a host platform for a different target platform. The dependency interface mechanism should be platform-independent to the extent practical.

25. Platform-specific aspects (word size, endianness, alignment requirements) should be configurable through implementation-defined means.

---

## B.11 Testing

26. An implementation should be accompanied by a test suite that exercises:

   (a) Acceptance of representative conforming programs.

   (b) Rejection of representative non-conforming programs, with correct identification of the violated rule.

   (c) Each D27 rule independently.

   (d) Task-variable ownership checking.

   (e) Channel operations including blocking, non-blocking, and select.

   (f) Correct dynamic semantics for accepted programs.

27. The test suite should include golden-file tests where the expected output (diagnostics, interface files, or generated code) is compared against stored expected output.
