# 6. Conformance

This section specifies what constitutes a conforming Safe implementation, what constitutes a conforming Safe program, and the requirements on the compilation model, emitted Ada, and runtime environment.

---

## 6.1 Conforming Implementation

1. A conforming implementation of the Safe language shall:

   (a) Accept every conforming Safe program as defined in §6.2.

   (b) Reject every program that violates a legality rule stated in this specification, with a diagnostic identifying the violated rule.

   (c) Implement the single-pass compilation model described in §6.3.

   (d) Emit Ada 2022 / SPARK 2022 source code that meets the requirements of §6.4.

   (e) Generate SPARK annotations (`Global`, `Depends`, `Initializes`, `SPARK_Mode`) sufficient for GNATprove Bronze-level assurance on every conforming program.

   (f) Enforce the D27 language rules (§2.8) such that every conforming program, when emitted and submitted to GNATprove, passes AoRTE proof at Silver level.

   (g) Be written in Ada 2022 / SPARK 2022 and pass GNATprove at Silver level (AoRTE) with no unproven checks (D29). See §6.8.

---

## 6.2 Conforming Program

2. A conforming Safe program shall:

   (a) Consist of one or more compilation units, each in a `.safe` source file.

   (b) Use only the syntax defined in Section 8 of this specification.

   (c) Satisfy all legality rules stated in Sections 2 through 4 of this specification.

   (d) Use only the retained library units specified in Annex A (Section 7a) of this specification.

3. A conforming program is a program that a conforming implementation accepts without error.

4. **Clarification:** Conformance is a property of the Safe source. The Silver guarantee (§5.3) is a property of the emitted Ada — it states that when a conforming Safe program is emitted as Ada/SPARK and submitted to GNATprove, all runtime checks are provably safe. If a program is accepted by the compiler (conforming), the Silver guarantee applies to its emitted Ada. A conforming implementation shall not accept a program for which the Silver guarantee cannot be met.

---

## 6.3 Compilation Model

### 6.3.1 Single-Pass Compilation

5. The compiler shall process each compilation unit in a single pass as defined in D3. The compiler reads the token stream once, left to right. During this pass it builds an in-memory AST, resolves names, checks types, enforces legality rules, and accumulates analysis data (`Global`/`Depends` sets, ownership state, task-variable ownership).

6. After the token stream is consumed, the compiler walks the completed AST to emit Ada/SPARK output. This post-parse AST walk is not a "second pass" — it does not re-read source tokens.

7. What is prohibited is any design that requires re-parsing source text, multi-pass name resolution, or whole-program analysis across compilation units. Each compilation unit is compiled independently using only its source and the symbol files of its dependencies.

### 6.3.2 Symbol Files

8. The compiler shall produce a binary symbol file for each compiled package. The symbol file contains the information needed for separate compilation of dependent packages (see Section 3, §3.3).

9. The symbol file shall include: exported names, types (including size and alignment for opaque types), subprogram signatures, channel declarations, and a dependency fingerprint. The format shall be text-based (UTF-8, line-oriented, versioned header) for debuggability and diffability.

10. Deterministic ordering of entries within the symbol file is required for stable diffs and reproducible builds.

### 6.3.3 Separate Compilation

11. Each `.safe` file is compiled independently. The compiler reads the symbol files of packages named in `with` clauses. No whole-program analysis is performed during compilation.

12. Circular `with` dependencies are not permitted. The dependency graph shall be a directed acyclic graph. A conforming implementation shall reject any compilation unit that would create a circular dependency.

### 6.3.4 Library Units

13. A library unit shall be a package. Library-level subprograms are not permitted as compilation units.

---

## 6.4 Emitted Ada Requirements

### 6.4.1 File Structure

14. For each Safe package, the compiler shall emit a pair of Ada source files:

    - A `.ads` file (package specification) containing: `pragma SPARK_Mode (On);`, all public type declarations, public subprogram specifications, public constant declarations, public channel-backing protected object specifications, and task type specifications.

    - A `.adb` file (package body) containing: private declarations, subprogram bodies, task bodies, channel-backing protected object bodies, and compiler-generated deallocation code.

15. The emitted files shall be valid ISO/IEC 8652:2023 Ada source that compiles without error using GNAT.

16. The emitted files shall be valid SPARK 2022 source that is accepted by GNATprove with `pragma SPARK_Mode (On)`.

### 6.4.2 SPARK Annotations

17. **Stone guarantee:** Every emitted compilation unit shall include `pragma SPARK_Mode (On);`. This is true by construction — every Safe construct maps to a SPARK-legal Ada construct.

18. **Bronze guarantee:** The compiler shall generate the following annotations in the emitted Ada:

    - `Global` aspects on every subprogram, listing package-level variables accessed (§5.2.1)
    - `Depends` aspects on every subprogram, specifying data dependencies (§5.2.2)
    - `Initializes` aspects on every package, listing initialized variables (§5.2.3)

19. **Silver guarantee:** The D27 language rules (§2.8) ensure all runtime checks are provably safe. The emitted Ada shall use `Wide_Integer` for intermediate arithmetic (§2.8.1), and all type constraints in the emitted Ada shall preserve the D27 guarantees.

### 6.4.3 Tasking Emission

20. The emitted Ada shall use the Jorvik tasking profile:

    ```ada
    pragma Profile (Jorvik);
    ```

21. Each Safe `task` declaration shall be emitted as an Ada task type with a single instance and a `Priority` aspect.

22. Each Safe `channel` declaration shall be emitted as a protected object with:
    - A ceiling priority equal to the maximum static priority of all tasks that access the channel
    - `Send` and `Receive` entries implementing blocking channel operations
    - `Try_Send` and `Try_Receive` procedures implementing non-blocking channel operations
    - An internal bounded buffer of the declared capacity

23. Channel operations (`send`, `receive`, `try_send`, `try_receive`) shall be emitted as entry calls or procedure calls on the corresponding protected object.

24. `select` statements on channels shall be emitted as conditional entry call patterns that implement the first-ready-wins semantics.

25. Task-variable ownership shall be emitted as `Global` aspects on task bodies, referencing only owned variables and channel operations.

### 6.4.4 Wide Intermediate Arithmetic

26. The emitted Ada shall include a declaration of `Wide_Integer`:

    ```ada
    type Wide_Integer is range -(2**63) .. (2**63 - 1);
    ```

27. All integer subexpressions in the emitted Ada shall be lifted to `Wide_Integer`. At narrowing points, explicit type conversions shall be emitted.

### 6.4.5 Ownership and Deallocation

28. Access type ownership shall be tracked by the compiler. At every scope exit where an owning access variable goes out of scope, the compiler shall emit deallocation code equivalent to:

    ```ada
    declare
      procedure Free is new Ada.Unchecked_Deallocation (T, T_Ptr);
    begin
      if X /= null then
        Free (X);
      end if;
    end;
    ```

29. Move semantics on access assignment shall be emitted as assignment followed by null-assignment of the source:

    ```ada
    Y := X;
    X := null;
    ```

### 6.4.6 Dot Notation and Type Annotations

30. All dot-notation attribute references in Safe source (`X.First`) shall be emitted as tick-notation attribute references in Ada (`X'First`).

31. All type annotation expressions in Safe source (`(Expr : T)`) shall be emitted as qualified expressions in Ada (`T'(Expr)`).

---

## 6.5 Runtime Requirements

32. The emitted Ada uses GNAT's Jorvik-profile runtime. No custom runtime is required for the Safe language.

33. GNAT provides task scheduling, protected object implementation, delay support, and memory allocation. The Safe compiler's responsibility ends at emitting correct Jorvik-profile Ada.

34. For bare-metal or restricted targets where the Jorvik profile is not available, the implementation shall document: (a) the chosen alternative profile (e.g., Ravenscar), (b) any restricted channel or select features, and (c) any impact on proof obligations.

---

## 6.6 Target Platforms

35. Safe targets any platform supported by GNAT. The compiler emits Ada/SPARK source; GNAT handles all platform-specific code generation, linking, and runtime support.

36. No platform-specific requirements are imposed by the Safe language definition. Platform targeting is entirely GNAT's responsibility.

---

## 6.7 Diagnostic Requirements

### 6.7.1 Diagnostic Format

37. Compiler diagnostics shall include:
    - The Safe source file name
    - The line number and column number
    - The severity (error, warning, note)
    - A human-readable message describing the issue
    - A reference to the relevant specification rule (e.g., `[D27 Rule 2]`, `[§2.1.9]`)

38. Example format:

    ```
    sensors.safe:42:18: error: right operand of "/" has type Integer
        whose range includes zero [D27 Rule 3]
    sensors.safe:42:18: note: use a subtype excluding zero, e.g., Positive
    ```

### 6.7.2 Diagnostic Stability

39. Compiler diagnostics shall be stable: the same Safe source, compiled with the same compiler version, shall always produce identical diagnostics. This enables automated testing and regression detection.

---

## 6.8 Compiler Verification Requirement (D29)

40. A conforming implementation shall be written in Ada 2022 / SPARK 2022.

41. All compiler source code shall pass GNATprove at Silver level (Absence of Runtime Errors) with no unproven checks. The build process is:

    (a) Compile the compiler source with GNAT.
    (b) Run GNATprove on the compiler source at Silver level.
    (c) All runtime checks in the compiler must be proved. Proof timeouts are treated as failures.

42. This means the compiler cannot crash due to a buffer overrun, null dereference, integer overflow, or type conversion error when processing any input — including malformed or adversarial Safe source files.

43. **What this does NOT mean:**
    - The compiler is not written in Safe. It is written in Ada/SPARK.
    - The compiler does not need to be Gold-level (functional correctness). Silver proves the compiler will not crash; proving it compiles correctly would require Gold or Platinum and is significantly harder.
    - Self-hosting is not required.

44. **Estimated compiler structure:**

    | Component | Approximate LOC | Silver Challenge |
    |-----------|----------------|-----------------|
    | Lexer | 800–1,200 | Low — character-level, bounded buffers |
    | Parser | 2,500–3,500 | Low — recursive descent, predictable control flow |
    | Semantic analysis | 2,000–3,000 | Medium — symbol table lookups, type checking |
    | Ownership checker | 800–1,200 | Medium — access type tracking |
    | D27 rule enforcement | 500–800 | Low — interval arithmetic, type range queries |
    | Task/channel compilation | 1,350–2,000 | Medium — task-variable ownership, select emission |
    | Ada/SPARK emitter | 1,500–2,500 | Low — string building, annotation generation |
    | Driver and I/O | 500–800 | Low — file handling, command line |
    | **Total** | **10,000–14,000** | |

---

## 6.9 Emitted Ada Quality

45. The emitted `.ads`/`.adb` files shall be:

    (a) **Deterministic:** The same Safe source, compiled with the same compiler version, shall always produce byte-identical Ada output.

    (b) **Human-readable:** The emitted Ada shall use meaningful identifier names, consistent indentation, and clear structure suitable for manual inspection.

    (c) **Suitable for certification:** The emitted Ada shall be suitable for review in DO-178C and similar certification processes.

    (d) **Suitable for Gold/Platinum annotation:** Developers shall be able to add SPARK annotations (Pre, Post, Ghost, Loop_Invariant, etc.) to the emitted Ada for Gold and Platinum assurance without restructuring the code.

46. **Naming conventions:** The compiler shall use deterministic, documented naming conventions for generated entities:
    - Channel-backing protected objects: `<channel_name>_Channel`
    - Task types: `<task_name>_Task`
    - Wide integer intermediates: `Tmp_<N>` with sequential numbering per subprogram
    - Deallocation procedures: `Free_<type_name>`

---

## 6.10 Incremental Recompilation

47. The compiler shall support incremental recompilation. A compilation unit shall be recompiled when:

    (a) Its `.safe` source file has been modified (detected by timestamp or content hash).

    (b) The symbol file of any package named in its `with` clauses has changed (detected by comparing the symbol file's dependency fingerprint).

48. When a symbol file changes, all units that `with` the corresponding package shall be recompiled. This cascade is bounded by the acyclic dependency graph.

49. The compiler may cache intermediate results (AST, symbol tables) to accelerate incremental compilation, but such caches are advisory — the compiler shall produce identical output whether compiling from cache or from source.

---

## 6.11 Conformance Summary

50. The following table summarizes the conformance requirements:

| Requirement | Section | Normative Level |
|------------|---------|-----------------|
| Accept conforming programs | §6.1(a) | Shall |
| Reject non-conforming programs with diagnostic | §6.1(b) | Shall |
| Single-pass compilation | §6.3.1 | Shall |
| Symbol file emission | §6.3.2 | Shall |
| Emit valid Ada 2022 / SPARK 2022 | §6.4.1 | Shall |
| Generate Bronze annotations | §6.4.2 | Shall |
| Enforce D27 for Silver | §6.4.2 | Shall |
| Jorvik-profile tasking | §6.4.3 | Shall |
| Wide intermediate arithmetic | §6.4.4 | Shall |
| Automatic deallocation | §6.4.5 | Shall |
| Stable diagnostics | §6.7.2 | Shall |
| Compiler written in Silver SPARK | §6.8 | Shall |
| Deterministic emitted Ada | §6.9(a) | Shall |
| Incremental recompilation | §6.10 | Shall |
