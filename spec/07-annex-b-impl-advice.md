# 7b. Implementation Advice

This annex provides non-normative implementation advice for Safe compilers. The requirements in this annex use "should" (recommendation) rather than "shall" (requirement) unless explicitly stated otherwise.

---

## 7b.1 Emitted Ada Conventions

### 7b.1.1 Determinism

1. The emitted `.ads`/`.adb` files shall be deterministic — the same Safe source, compiled with the same compiler version, shall always produce byte-identical Ada output. This is a normative requirement (see §6.9).

2. Determinism enables:
   - Golden test suites that compare emitted Ada against expected output
   - Reproducible builds for certification
   - Meaningful diffs when the compiler is updated

### 7b.1.2 Naming Conventions

3. The following naming conventions are recommended for generated entities in the emitted Ada:

| Safe Construct | Emitted Ada Name | Example |
|---------------|-----------------|---------|
| Package `Foo` | `Foo` (unchanged) | `package Foo is ...` |
| Public type `Bar` | `Bar` (unchanged) | `type Bar is ...` |
| Private type `Baz` | `Baz` (unchanged, in body) | `type Baz is ...` |
| Channel `Ch` | `Ch_Channel` | `protected Ch_Channel is ...` |
| Task `Worker` | `Worker_Task` / `Worker_Instance` | `task type Worker_Task; Worker_Instance : Worker_Task;` |
| Wide integer type | `Safe_Wide_Integer` | `type Safe_Wide_Integer is range -(2**63) .. (2**63 - 1);` |
| Wide intermediates | `Tmp_1`, `Tmp_2`, ... | Sequential per subprogram body |
| Deallocation procedure | `Free_<Type>` | `procedure Free_Node is new Ada.Unchecked_Deallocation (Node, Node_Ptr);` |
| Channel buffer array | `<Channel>_Buffer` | `Buffer : array (0 .. 7) of Sample;` |
| Channel count | `<Channel>_Count` | `Count : Natural := 0;` |

4. The naming scheme should avoid conflicts with user-defined names. Since Safe programs cannot define names ending in `_Channel` or `_Task` (these are not reserved, but the convention should be documented so users can avoid them), the implementation should issue a warning if a user-defined name conflicts with a generated name.

### 7b.1.3 Formatting

5. The emitted Ada should follow consistent formatting conventions:

   - Indentation: 3 spaces per level (GNAT standard)
   - Line width: 79 characters maximum
   - One declaration per line
   - Blank line between subprogram bodies
   - Aspect specifications on the line following the subprogram specification, indented
   - Comments preserving Safe source file and line references where practical

6. The formatting should be stable across compiler versions — changes to the emitter should not gratuitously reformat existing output.

### 7b.1.4 Source Traceability

7. The emitted Ada should include comments that trace back to the Safe source:

   ```ada
   --  Generated from sensors.safe:15
   function Read_Sensor (Id : Sensor_Id) return Reading
     with Global => (Input => Calibration),
          Depends => (Read_Sensor'Result => (Id, Calibration))
   is
   ```

8. These traceability comments support code review, debugging, and DO-178C certification traceability requirements.

---

## 7b.2 Symbol File Format

### 7b.2.1 Format Requirements

9. The symbol file format should be text-based (UTF-8, line-oriented) for debuggability and diffability.

10. The symbol file should begin with a versioned header:

    ```
    SAFE-SYM v1
    package Sensors
    fingerprint a1b2c3d4e5f6
    ```

11. The version number (`v1`) allows the format to evolve without breaking existing symbol files.

### 7b.2.2 Contents

12. The symbol file should contain the following categories of information:

    (a) **Package name** — the fully qualified package name

    (b) **Dependencies** — the list of packages named in `with` clauses, with their fingerprints

    (c) **Public types** — for each public type: name, kind (scalar/array/record/access), size, alignment, and for opaque types: size and alignment only (no component information)

    (d) **Public subtypes** — for each public subtype: name, parent type, constraints

    (e) **Public constants** — for each public constant: name, type, value (if static)

    (f) **Public subprograms** — for each public subprogram: name, parameter list (names, modes, types), return type (for functions)

    (g) **Public channels** — for each public channel: name, element type, capacity

    (h) **Dependency fingerprint** — a hash of all exported information, used for incremental recompilation

### 7b.2.3 Fingerprinting

13. The dependency fingerprint should be computed as a cryptographic hash (e.g., SHA-256) of the normalized symbol file contents (excluding the fingerprint line itself and comments).

14. When a symbol file's fingerprint changes, all dependent units must be recompiled. When the fingerprint is unchanged (e.g., a private implementation change that does not affect the public interface), dependent units need not be recompiled.

### 7b.2.4 Deterministic Ordering

15. Entries within the symbol file should be ordered deterministically:
    - Types before subtypes before constants before subprograms before channels
    - Within each category, alphabetical by name
    - This ensures stable diffs when the symbol file is regenerated

### 7b.2.5 Example Symbol File

16. Example:

    ```
    SAFE-SYM v1
    package Sensors
    fingerprint 7f3a9c2e1d4b

    depends Calibration 4e8b1a3c
    depends Ada.Real_Time 0000000000

    type Reading scalar size=16 alignment=2 range=0..4095
    type Sensor_Id scalar size=8 alignment=1 range=0..15

    subtype Positive_Reading Reading range=1..4095

    constant Max_Sensors : Sensor_Id = 15

    function Get_Reading (Id : in Sensor_Id) return Reading
    procedure Calibrate (Id : in Sensor_Id; Offset : in Reading)

    channel Readings : Reading capacity=16
    ```

---

## 7b.3 Diagnostic Messages

### 7b.3.1 Format

17. Diagnostic messages should follow the format:

    ```
    <file>:<line>:<column>: <severity>: <message> [<rule>]
    ```

18. Severity levels:
    - `error` — the program is rejected; compilation fails
    - `warning` — the program is accepted but a potential issue is identified
    - `note` — additional information related to a preceding error or warning

### 7b.3.2 Rule References

19. Every diagnostic for a D27 rule violation should include the rule reference in brackets:

    ```
    foo.safe:10:15: error: index type Integer is not a subtype of
        array index type Channel_Id [D27 Rule 2]
    foo.safe:10:15: note: use Channel_Id or a subtype of it as the index
    ```

20. Every diagnostic for a restriction violation should reference the corresponding design decision:

    ```
    bar.safe:5:1: error: generic declarations are not permitted [D16]
    bar.safe:5:1: note: Safe excludes generics; write monomorphic code instead
    ```

### 7b.3.3 Suggestions

21. Where practical, diagnostics should include a suggestion for how to fix the issue:

    ```
    baz.safe:8:20: error: right operand of "/" has type Integer whose
        range includes zero [D27 Rule 3]
    baz.safe:8:20: note: use subtype Positive (range 1 .. Integer'Last)
        or define a custom nonzero subtype
    ```

### 7b.3.4 Stability

22. Diagnostics should be stable: the same input should produce the same diagnostics across runs and across platforms. This enables automated testing with expected-output comparison.

---

## 7b.4 Incremental Recompilation

### 7b.4.1 Change Detection

23. The compiler should detect changes to source files using content hashing rather than timestamps alone. Content hashing avoids unnecessary recompilation when a file is touched but not modified (e.g., by version control operations).

### 7b.4.2 Minimal Recompilation

24. When a symbol file changes, only the units that directly `with` the changed package need recompilation. Transitive recompilation should occur only if the directly dependent unit's symbol file also changes as a result.

25. Example: If package A `with`s package B, and package B `with`s package C, a change to C's private implementation (no symbol file change) triggers no recompilation. A change to C's public interface (symbol file change) triggers recompilation of B. If B's symbol file changes as a result, A is also recompiled. If B's symbol file is unchanged, A is not recompiled.

### 7b.4.3 Build Integration

26. The compiler should support integration with standard build tools. Recommended approach:

    - Each `.safe` file produces a `.sym` (symbol file) and a `.ads`/`.adb` pair
    - The build system (e.g., GPRbuild) tracks dependencies via the `.sym` files
    - The compiler can be invoked per-file, enabling parallel compilation of independent units

---

## 7b.5 Emitted Ada Quality

### 7b.5.1 Readability

27. The emitted Ada should be readable by an Ada programmer who has not used Safe. This means:
    - Meaningful variable names (not obfuscated)
    - Clear structure matching the Safe source organization
    - Standard Ada idioms for the generated patterns

28. The emitted Ada serves multiple purposes:
    - Input to GNAT for compilation to machine code
    - Input to GNATprove for formal verification
    - Artifact for code review and certification
    - Base for Gold/Platinum annotation by developers

### 7b.5.2 Generated Annotation Style

29. Generated `Global` and `Depends` aspects should use the most specific mode qualifiers:
    - `Input` for read-only access
    - `Output` for write-only access
    - `In_Out` for read-write access
    - `Proof_In` should not be used (it is for ghost variables, which are excluded)

30. Generated `Initializes` aspects should list all package-level variables in declaration order.

### 7b.5.3 Channel-Backing Protected Objects

31. The generated protected objects for channels should follow a consistent pattern:

    ```ada
    protected <Name>_Channel
      with Priority => <ceiling_priority>
    is
      entry Send (Item : in <Element_Type>);
      entry Receive (Item : out <Element_Type>);
      function Try_Send (Item : in <Element_Type>) return Boolean;
      function Try_Receive (Item : out <Element_Type>) return Boolean;
    private
      Buffer : array (0 .. <Capacity> - 1) of <Element_Type>;
      Count  : Natural := 0;
      Head   : Natural := 0;
      Tail   : Natural := 0;
    end <Name>_Channel;
    ```

32. The `Send` entry barrier should be `Count < <Capacity>` (block when full). The `Receive` entry barrier should be `Count > 0` (block when empty).

### 7b.5.4 Wide Arithmetic Pattern

33. The generated wide arithmetic pattern should be consistent:

    ```ada
    --  Safe source: return (A + B) / 2;
    declare
      Tmp_1 : Safe_Wide_Integer := Safe_Wide_Integer (A) + Safe_Wide_Integer (B);
      Tmp_2 : Safe_Wide_Integer := Tmp_1 / 2;
    begin
      return Reading (Tmp_2);
    end;
    ```

34. The compiler may optimize away intermediate `Wide_Integer` conversions when it can statically determine that no overflow is possible in the target type. However, the default should be to emit the wide pattern for predictability and provability.

---

## 7b.6 Testing

### 7b.6.1 Golden Tests

35. The implementation should maintain a suite of golden tests: Safe source files paired with expected emitted Ada output. Any change to the emitter that alters the output should be reviewed and the golden tests updated.

36. Golden tests should cover:
    - Every syntactic construct in the grammar
    - Every D27 rule (positive and negative cases)
    - Every channel operation pattern
    - Select statement emission
    - Ownership patterns (move, borrow, observe, deallocation)
    - Interleaved declarations
    - Dot notation for all retained attributes
    - Type annotation syntax

### 7b.6.2 GNATprove Regression Tests

37. The implementation should maintain a suite of Safe programs for which:
    - The emitted Ada is submitted to GNATprove
    - Bronze (flow analysis) passes with no errors
    - Silver (AoRTE) passes with no unproved checks
    - Any future regression is detected immediately

38. This suite should include programs exercising all D27 rules, all channel patterns, and ownership edge cases.
