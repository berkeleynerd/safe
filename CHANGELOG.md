# CHANGELOG — Safe Language Specification Revision

This changelog documents all changes applied to `SPEC-PROMPT.md` based on the combined findings of the SPARK 2022 Faithfulness Review and the Standards Readiness Review.

---

## P0 — Must Fix (contradictions and missing requirements)

### P0-1. Task Termination vs. Jorvik Profile

**Problem:** D28 claimed "Tasks may terminate via `return`" and that this "stays within Jorvik's capabilities." This is false — Jorvik retains `No_Task_Termination` from Ravenscar.

**Before:**
> Tasks begin executing when the program starts, after all package-level initialization is complete. Each task declaration creates exactly one task — no dynamic spawning, no task types, no task arrays. Tasks may terminate via `return`; a terminated task cannot be restarted.

**After:**
> Tasks begin executing when the program starts, after all package-level initialization is complete. Each task declaration creates exactly one task — no dynamic spawning, no task types, no task arrays. Tasks shall not terminate — every task body must contain a non-terminating control structure (e.g., an unconditional `loop`). A conforming implementation shall reject any task body that is not syntactically non-terminating. This is required by the Jorvik profile, which retains the `No_Task_Termination` restriction from Ravenscar.

**Before (Task termination subsection):**
> Tasks may terminate via `return`. This goes beyond Ravenscar (which requires tasks to run forever) but stays within Jorvik's capabilities. A terminated task's owned package variables become inaccessible. Channel endpoints remain valid — a send to a channel whose only receiver has terminated will block indefinitely (detectable by static analysis as a potential deadlock).

**After (Non-termination requirement subsection):**
> Tasks shall not terminate. The Jorvik profile retains the `No_Task_Termination` restriction from Ravenscar — both profiles require tasks to run forever once started. Every task body must contain a non-terminating control structure (typically an unconditional `loop`). A conforming implementation shall reject any task body whose outermost statement sequence is not syntactically non-terminating. `return` statements are not permitted in task bodies.

**Additional locations patched:**
- Rationale renamed from "static tasks" to "static, non-terminating tasks" with added explanation of `No_Task_Termination`
- §04 drafting instructions: "Task termination" bullet replaced with "Non-termination requirement" bullet

### P0-2. `access all` in Grammar but Not in Ownership Rules

**Problem:** Grammar instructions included `access_type_definition` which would include `access all`, but D17's ownership rules only covered pool-specific access types. No legality rule addressed `access all` types.

**Changes:**
- D17 "Restrictions vs. full SPARK ownership" — added `access all` exclusion as first bullet: "General access types (`access all T`) are excluded. A conforming implementation shall reject access type definitions that include the reserved word `all`."
- §02 drafting instructions (Access types and ownership) — added explicit `access all` exclusion, `anonymous access` exclusion, and `access constant` exclusion bullets
- §08 grammar instructions — updated access type line to specify "pool-specific only — `access all` excluded" and added exclusion list

### P0-3. Silver Guarantee Not Closed as a Conformance Rule

**Problem:** D26/D27 asserted Silver-by-construction but no hard rejection rule prevented a program from being accepted in a non-Silver state. The "trivially discharged" claim for `Wide_Integer` intermediates was not universally true.

**Before (D26 Silver section):**
> These rules ensure that every runtime check in a conforming Safe program is provably safe from type information alone. No developer annotations are needed.

**After:**
> These rules ensure that every runtime check in a conforming Safe program is provably safe from type information alone. No developer annotations are needed.
>
> **Hard rejection rule:** If a conforming implementation cannot establish, from the specification's type rules and D27 legality rules, that a required runtime check will not fail, the program is nonconforming and the implementation shall reject it with a diagnostic. There is no "developer must restructure" advisory — failure to satisfy any Silver-level proof obligation is a compilation error, not a warning.

**Before (D27 Rule 1, Wide_Integer claim):**
> GNATprove discharges intermediate arithmetic trivially because `Wide_Integer` cannot overflow for any operation on narrower types, and discharges narrowing checks via interval analysis on the wide result.

**After:**
> For types whose range fits within 32 bits, intermediate `Wide_Integer` arithmetic cannot overflow for single operations. For chained operations or types with larger ranges (e.g., products of two values near the 32-bit boundary), intermediate `Wide_Integer` subexpressions may approach the 64-bit bounds. If the implementation's analysis determines that any intermediate `Wide_Integer` subexpression could overflow, the expression shall be rejected with a diagnostic.

**Additional locations patched:**
- §05 drafting instructions — added hard rejection rule bullet
- §06 drafting instructions — added conforming program definition with rejection rule

### P0-4. Try_Send / Try_Receive Signature Mismatch

**Problem:** D28 defined `try_send`/`try_receive` as statements with Boolean out-parameter, but implementation advice described them as functions returning Boolean. SPARK prohibits functions with out parameters.

**Change:** Added explicit procedure signatures to §07-annex-b drafting instructions:
```ada
procedure Try_Send (Item : in Element_Type; Success : out Boolean);
procedure Try_Receive (Item : out Element_Type; Success : out Boolean);
```

### P0-5. Symbol File Format Contradiction

**Problem:** D6 said "binary symbol file" while §07-annex-b said "text-based (UTF-8, line-oriented, versioned header)".

**Before (D6):**
> The compiler extracts the public interface into a binary symbol file for incremental compilation

**After (D6):**
> The compiler extracts the public interface into a symbol file for incremental compilation [...] The symbol file format is implementation-defined.

**Additional locations patched:**
- §06 drafting instructions — added: "symbol files are one permitted mechanism and their format is implementation-defined"
- §07-annex-b — reframed symbol file format as "recommended practice" and declared this section the single normative home for format guidance

---

## P1 — Should Fix (standards editorial structure and missing requirements)

### P1-1. Normative/Informative Split — Remove Toolchain Coupling from Conformance

**Problem:** §06 defined conformance in terms of GNAT/GNATprove. ISO Ada explicitly does not specify translation means. An ECMA-track standard should define conformance using language properties.

**Changes:**
- Added new "Conformance Note" section to front matter: "Language conformance in this specification is defined in terms of language properties and legality rules, not specific tools or compilers."
- D29 reframed from "Compiler Written in Silver-Level SPARK" to "Reference Implementation in Silver-Level SPARK (Project Requirement)" with explicit statement that this is not a language conformance requirement
- §06 drafting instructions restructured into:
  - **Normative conformance requirements** — expressed in terms of language properties (accept conforming, reject nonconforming, implement dynamic semantics correctly)
  - **Conformance levels** (Safe/Core, Safe/Assured) — see P2-3
  - **Informative implementation guidance** — relocated GNAT/GNATprove material with explicit "informative" labels
  - D29 reframed as "Reference implementation profile (project requirement)"
- §05 drafting instructions: Bronze guarantee statement reframed from "submitted to GNATprove" to language property with informative GNATprove validation

### P1-2. Partition_Elaboration_Policy(Sequential) Requirement

**Problem:** D28 promises tasks start after elaboration completes, but the spec didn't mention `Partition_Elaboration_Policy(Sequential)`, which SPARK requires for task/protected usage under Jorvik.

**Changes:**
- D28 SPARK emission subsection — added `pragma Partition_Elaboration_Policy(Sequential)` as first emitted configuration item
- §04 drafting instructions — Task startup bullet expanded with elaboration policy language-level requirement and emitted pragma
- §07-annex-b — added "Elaboration and tasking configuration" bullet with rationale

### P1-3. `Wide_Integer` Intermediate Overflow Qualification

**Problem:** D27 Rule 1 claimed "`Wide_Integer` cannot overflow for any operation on narrower types" — misleading for multiplication of large-range types.

**Before:**
> GNATprove discharges intermediate arithmetic trivially because `Wide_Integer` cannot overflow for any operation on narrower types

**After:**
> For types whose range fits within 32 bits, intermediate `Wide_Integer` arithmetic cannot overflow for single operations. For chained operations or types with larger ranges [...] the expression shall be rejected with a diagnostic.

**Additional change:** Added explicit "Intermediate overflow legality rule" paragraph to D27 Rule 1.

### P1-4. Deallocation Emission Implementation Note

**Problem:** D17 specifies automatic deallocation but doesn't mention that emitted Ada must use `Ada.Unchecked_Deallocation` (a generic instantiation) or that deallocation must be emitted at every scope exit point.

**Changes:**
- D17 — added "Implementation note (deallocation emission)" paragraph covering: `Ada.Unchecked_Deallocation` usage in emitted code, D16 exclusion applies to Safe source only, deallocation at every scope exit point, GNATprove leak checking as independent verification
- §07-annex-b — added "Deallocation emission" bullet with same content

---

## P2 — Nice to Have (additional clarifications)

### P2-1. TBD Register

**Change:** Added TBD Register to §00 front matter drafting instructions listing 8 unresolved items:
- Target platform constraints
- Performance targets
- Memory model constraints
- Floating-point semantics
- Diagnostic catalog and localization
- `Constant_After_Elaboration` aspect
- Abort handler behavior
- AST/IR interchange format

### P2-2. `Depends` Over-Approximation Note

**Change:** Added note to §05 drafting instructions: compiler-generated `Depends` contracts may be conservatively over-approximate. GNATprove accepts supersets of actual dependencies for Bronze. Implementations may refine precision over time.

### P2-3. Conformance Levels

**Change:** Added conformance levels to §06 drafting instructions:
- **Safe/Core:** Language rules and legality checking only
- **Safe/Assured:** Language rules plus verification that every conforming program is free of runtime errors (the Silver guarantee as a language property)

### P2-4. `select` Emission Pattern Latency Note

**Change:** Added latency note to D28 `select` emission bullet: the polling-with-sleep pattern introduces latency equal to the sleep interval. Implementations may use more efficient patterns provided observable semantics are preserved.

---

## Consistency Pass

After all patches, the following consistency checks were performed:

1. **Task termination references:** All removed or updated. No remaining references to task `return`, terminated tasks, or post-termination semantics.
2. **GNATprove in normative requirements:** §06 conformance section now defines conformance via language properties. All remaining GNATprove references are in design decisions (informative rationale), §05 (informative validation), or §07-annex-b (implementation advice).
3. **"binary symbol file":** Does not appear anywhere in the spec.
4. **§08 grammar instructions:** Updated to reflect `access all` exclusion and full exclusion list.
5. **D28 examples:** Both task examples (Sensor_Reader, Sampler, Evaluator) use unconditional `loop` — no task termination shown.
6. **D17 ownership table:** Consistent with `access all` exclusion — only pool-specific access types shown.
7. **D26/D27 Silver guarantee:** Hard rejection rule added. `Wide_Integer` overflow claim qualified. "Three legality rules" corrected to "four" (Rule 4: not-null dereference was already present but not counted in the heading).

---

## Round 2

Changes applied based on an independent ECMA-track readiness review and deferred items from the Round 1 consistency pass.

### P0-R2-1. Toolchain Baseline Contradicts Conformance Note

**Problem:** Toolchain Baseline used normative "shall" voice binding conformance to GNATprove invocation, contradicting the Conformance Note and ECMA policy.

**Before (section introduction):**
> All compiler and proof requirements in this specification are defined relative to the following baseline:

**After:**
> This section defines the reference toolchain profile used by the project to validate the language guarantees. It is informative and does not define language conformance. Language conformance is defined solely in §06.

**Before (proof acceptance policy introduction):**
> For the purposes of this specification, "passes Bronze" and "passes Silver" mean:

**After:**
> For the purposes of the reference toolchain profile, "passes Bronze" and "passes Silver" mean:

**Before (proof acceptance policy closing):**
> These are the acceptance criteria for D26's guarantees. Every conforming Safe program, when compiled and emitted as Ada/SPARK, shall meet both criteria without any developer-supplied SPARK annotations in the emitted code.

**After:**
> These are the acceptance criteria used to validate D26's guarantees for the reference implementation. The language conformance rules in §06 are stated without mandating any specific tool invocation. A conforming Safe program is one that satisfies the language's legality rules (including D27 Rules 1–4); the reference toolchain profile provides one method of validating that the language guarantees hold.

**Additional fix:** "the implementation shall document" softened to "the reference implementation should document" in the Jorvik-unavailable paragraph.

### P0-R2-2. "Syntactically Non-Terminating" Is Ambiguous

**Problem:** D28 required implementations to "reject any task body that is not syntactically non-terminating" without defining what syntactic forms qualify.

**Before (D28 task declarations):**
> Tasks shall not terminate — every task body must contain a non-terminating control structure (e.g., an unconditional `loop`). A conforming implementation shall reject any task body that is not syntactically non-terminating.

**After:**
> Tasks shall not terminate. [...]
>
> **Non-termination legality rule:** The outermost statement of a task body's `handled_sequence_of_statements` shall be an unconditional `loop` statement (`loop ... end loop;`). Declarations may precede the loop. A `return` statement shall not appear anywhere within a task body. No `exit` statement within the task body shall name or otherwise target the outermost loop. A conforming implementation shall reject any task body that violates these constraints. This is a syntactic restriction checkable without control-flow or whole-program analysis.

**Before (D28 non-termination requirement subsection):**
> Tasks shall not terminate. [...] A conforming implementation shall reject any task body whose outermost statement sequence is not syntactically non-terminating. `return` statements are not permitted in task bodies.

**After:**
> The non-termination legality rule (stated in the task declarations section above) requires that: (a) the outermost statement of the task body is an unconditional `loop ... end loop;`, (b) no `return` statement appears anywhere in the task body, and (c) no `exit` statement names or targets the outermost loop. [...] This is a conservative syntactic restriction. Some theoretically non-terminating forms (e.g., `while True loop ... end loop;`) are excluded because "non-terminating" is not decidable in general; the unconditional `loop` form is trivially checkable by any implementation.

**§04 drafting instructions:** "Non-termination requirement" bullet replaced with "Non-termination legality rule" bullet specifying the precise syntactic constraints.

### P0-R2-3. Quick Reference Example Nonconforming Under D27

**Problem:** `Get_Reading` assigned `Raw + Cal_Table(Channel).Offset` to `Adjusted : Reading` where the intermediate could reach 8190 (exceeds `Reading`'s 0..4095 range), making the program nonconforming under D27 Rule 1.

**Before:**
```ada
public function Get_Reading (Channel : Channel_Id) return Reading is
begin
    pragma Assert (Initialized);
    Raw : Reading := Read_ADC (Channel);
    Adjusted : Reading := Raw + Cal_Table (Channel).Offset;
    return Adjusted;
end Get_Reading;
```

**After:**
```ada
public function Get_Reading (Channel : Channel_Id) return Reading is
begin
    pragma Assert (Initialized);
    Raw : Reading := Read_ADC (Channel);
    return Raw;  -- D27: no narrowing needed, already Reading type
end Get_Reading;
```

**Additional changes:**
- `Calibration` record simplified: `Offset : Reading` removed, replaced with `Bias : Integer`
- `Cal_Table` aggregate updated to match
- `Initialize` default updated to match
- Emitted Ada `Get_Reading` signature updated (no longer depends on `Cal_Table`)
- D27 note updated to focus on `Average_Reading`'s wide intermediate division
- Editorial Convention item 6 added: all examples must be conforming; nonconforming examples must be labeled

### P1-R2-1. Cross-Unit Effect Analysis Requires Symbol-File Specification

**Problem:** D3 prohibits whole-program analysis, but task-variable ownership (D28) and Bronze assurance (D26) require cross-package effect analysis. The spec did not specify what symbol files must carry to enable this.

**Changes:**
- §03 Static Semantics bullet — added: symbol files shall include `Global` effect summaries (read-set/write-set) for all exported subprograms; rejection if effect summary unavailable
- §04 Task-variable ownership bullet — added: cross-package transitivity uses `Global` effect summaries from dependency symbol files; ownership check completable without dependency source code

### P1-R2-2. D27 Rule 1 Redundant Paragraphs

**Problem:** The example paragraph after the "Intermediate overflow legality rule" still contained residual overlap from Round 1.

**Before:**
> This means `A + B` where `A, B : Reading` (0..4095) computes in `Wide_Integer` — the intermediate result 8190 does not overflow. A range check fires only if the result is stored back into a `Reading`.

**After:**
> For example, `A + B` where `A, B : Reading` (0..4095) computes in `Wide_Integer` — the intermediate result 8190 does not overflow, and a range check fires only when the result is narrowed to `Reading` at an assignment, return, or parameter point. GNATprove discharges narrowing checks via interval analysis on the wide result.

### P1-R2-3. D17 Deallocation Scope Exits Wording

**Problem:** Improved `goto` wording to specify "transfer control out of the owning scope" instead of "leave the scope" for precision.

**Before (D17):**
> `goto` statements that leave the scope

**After (D17):**
> `goto` statements that transfer control out of the owning scope

**Same change applied in §07-annex-b deallocation emission bullet.**

### P2-R2-1. ECMA Editorial Constraint

**Change:** Added Editorial Conventions item 7: "No normative paragraph shall mandate invocation of a specific tool, compiler, or prover by name."

### P2-R2-2. Design Decisions Heading

**Change:** Section heading changed from `## Design Decisions and Rationale` to `## Design Decisions` to match ECMA-style section naming conventions.

---

## Round 2 Consistency Pass

1. **Toolchain Baseline voice:** No "shall" in the Toolchain Baseline section binds conformance to tool invocation. The remaining "shall" instances in §06 and elsewhere are normative language-property requirements. ✓
2. **Task non-termination:** Zero occurrences of "syntactically non-terminating". All references use the precise legality rule (outermost unconditional `loop`, no `return`, no `exit` targeting outermost loop). ✓
3. **Quick Reference examples:** `Get_Reading` no longer performs arithmetic that would be rejected under D27. All examples conforming. ✓
4. **Scope exit completeness:** Both D17 and §07-annex-b include `goto` alongside `return` and `exit` with "transfer control out of the owning scope" wording. ✓
5. **D27 Rule 1:** Example paragraph is short and focused, no duplication of legality rule text. ✓
6. **Editorial Conventions:** Items 6 (example conformance) and 7 (tool independence) present. ✓
7. **Design Decisions heading:** `## Design Decisions` heading present before D1. ✓
8. **§03 and §04 drafting instructions:** Symbol-file `Global` effect summaries and cross-package ownership checking requirements present. ✓

---

## Round 3

Changes applied based on a second independent ECMA-track readiness review.

### P0-R3-1. D27 Rule 3 — Division by Integer Literal Is Illegal Under Current Rule

**Problem:** Under wide intermediate arithmetic (Rule 1), integer literals like `2` are lifted to `Wide_Integer` whose range includes zero. Therefore `(A + B) / 2` was illegal under the type-only rule. The D27 `Average` example was nonconforming.

**Before:**
> **Rule 3: Division by Nonzero Type**
>
> The right operand of the operators `/`, `mod`, and `rem` shall be of a type or subtype whose range does not include zero. If the divisor's type range includes zero, the program is rejected at compile time.

**After:**
> **Rule 3: Division by Provably Nonzero Divisor**
>
> The right operand of the operators `/`, `mod`, and `rem` shall be provably nonzero at compile time. A conforming implementation shall accept a divisor expression as provably nonzero if any of the following conditions holds:
> (a) The divisor expression has a type or subtype whose range excludes zero.
> (b) The divisor expression is a static expression whose value is nonzero (e.g., a literal `2`, a named number).
> (c) The divisor expression is an explicit conversion to a nonzero subtype where the conversion is provably valid at that program point.

**Additional locations patched:**
- D26 four-rule summary item 3 updated to "Division-by-provably-nonzero-divisor"
- Combined effect table row updated
- §02 drafting instructions Rule 3 updated
- §05 drafting instructions updated
- Two new example blocks added (static literal, named number)

### P1-R3-1. Reserved Words — Ambiguous "Not Associated with Excluded Features"

**Problem:** "Safe retains all Ada 2022 reserved words that are not associated with excluded features" is not a well-defined lexical rule.

**Before:**
> Safe retains all Ada 2022 reserved words that are not associated with excluded features. Safe adds the following context-sensitive keywords that are reserved in Safe source but not Ada reserved words:

**After:**
> Safe reserves all ISO/IEC 8652:2023 (Ada 2022) reserved words (8652:2023 §2.9), regardless of whether the corresponding language feature is excluded in Safe. This preserves lexical clarity, simplifies the lexer, and ensures forward compatibility if excluded features are reconsidered in future revisions.
>
> Safe also adds the following reserved words that are not Ada reserved words:

### P1-R3-2. `Average_Reading` Quick Reference Example — Return Narrowing Not Provably Safe

**Problem:** `Average_Reading` did `return Reading(Total / Count)` where the result range (0..32760) exceeds `Reading` (0..4095). Interval analysis alone cannot prove the narrowing is safe.

**Before:**
```ada
public function Average_Reading (Count : Channel_Count) return Reading is
begin
    Total : Integer := 0;
    for I in Channel_Id.First .. Channel_Id(Count - 1) loop
        Total := Total + Integer(Get_Reading(I));
    end loop;
    return Reading(Total / Count);
end Average_Reading;
```

**After:** Replaced with two simpler functions:
```ada
public function Average (A, B : Reading) return Reading is
begin
    return (A + B) / 2;  -- Rule 1 + Rule 3(b)
end Average;

public function Scale (R : Reading; Divisor : Channel_Count) return Integer is
begin
    return Integer(R) / Integer(Divisor);  -- Rule 3(a)
end Scale;
```

**Additional locations patched:**
- D27 note below Quick Reference updated
- Emitted Ada example updated (Average, Scale instead of Average_Reading)

### P1-R3-3. §07-annex-b Drafting Instructions Use Normative "shall" Voice

**Problem:** §07-annex-b is informative but used "shall" for several items, creating "shall leakage" that ECMA reviewers would flag.

**Changes:**
- Added drafting note at top of §07-annex-b: "This annex is informative. Use 'should' rather than 'shall' throughout."
- "Emitted Ada conventions" → "(informative)", "shall" → "should"
- "Elaboration and tasking configuration" → "(informative)", "shall" → "should"
- Deallocation emission "must" → "should"
- Diagnostic messages "shall" → "should"

### P2-R3-1. ECMA Submission Shaping Constraints

**Change:** Added new section between Conformance Note and Toolchain Baseline with 5 constraints:
1. UK English drafting language
2. Per-file normative/informative declarations
3. Code examples are non-normative
4. Avoid normative pseudo-code
5. No normative software mandates

**Additional change:** Added normative/informative status bullet to §00 front matter drafting instructions.

---

## Round 3 Consistency Pass

1. **D27 Rule 3 name:** "Division by Nonzero Type" does not appear as a rule name. All references use "Division by Provably Nonzero Divisor" or equivalent. ✓
2. **D27 Rule 3 examples:** Conditions (a), (b), and (c) all exemplified. ✓
3. **D26 summary:** Item 3 updated to "Division-by-provably-nonzero-divisor." ✓
4. **Reserved words:** "not associated with excluded features" does not appear. ✓
5. **Quick Reference examples:** `Average_Reading` replaced by `Average` and `Scale`, both conforming. ✓
6. **Emitted Ada example:** Matches new function signatures with consistent `Global`/`Depends`. ✓
7. **§07-annex-b voice:** No "shall" in annex-b content (only in the drafting note explaining the convention). ✓
8. **ECMA shaping section:** Present between Conformance Note and Toolchain Baseline with all 5 constraints. ✓
9. **§00 front matter:** Includes normative/informative status bullet. ✓

---

## Round 4

Structural revision to separate the language specification drafter prompt from implementation-profile content. `SPEC-PROMPT.md` now contains only language-level definitions and drafting instructions. All implementation-profile content (GNAT, GNATprove, emitted Ada, single-pass compiler internals, SPARK emission patterns, runtime details, compiler cost estimates) has been moved to `DEFERRED-IMPL-CONTENT.md` for use in companion documents and informative annexes.

### Patch 1. Compatibility Note — remove emission backend and GNAT references

**Before:** Referenced "Ada 2022 / SPARK 2022 emission (D4, D25)" and "portability is delegated to GNAT (D5)."

**After:** States only that earlier C99 backend and OpenBSD requirements are removed and C FFI is excluded.

### Patch 2. Conformance Note — remove GNAT/GNATprove/toolchain-profile references

**Before:** Referenced "GNAT, GNATprove, and other tools" and "Toolchain profiles (e.g., GNAT/GNATprove guidance)."

**After:** States conformance is defined by language properties and legality rules, full stop.

### Patch 3. ECMA Shaping Constraints item 3 — remove emitted Ada / GNATprove from code examples note

**Before:** "All code examples (Safe source, emitted Ada, GNATprove output)."

**After:** "All code examples."

### Patch 4. Toolchain Baseline — remove entire section

Moved to `DEFERRED-IMPL-CONTENT.md`. This included GNAT/GNATprove version requirements, proof level, runtime profile, and proof acceptance policy.

### Patch 5. Reserved Words — remove emission mapping paragraph

**Before:** Included paragraph about emitted Ada mapping channel names to protected objects.

**After:** Paragraph removed; content preserved in deferred file.

### Patch 6. D3 (Single-Pass Recursive Descent Compiler) — remove entire decision

Moved to `DEFERRED-IMPL-CONTENT.md`. This was a compiler-architecture decision, not a language definition.

### Patch 7. D4 (Ada/SPARK as Sole Code Generation Target) — remove entire decision

Moved to `DEFERRED-IMPL-CONTENT.md`. Backend choice is an implementation decision.

### Patch 8. D5 (Platform-Independent via GNAT) — remove entire decision

Moved to `DEFERRED-IMPL-CONTENT.md`. Platform targeting via GNAT is an implementation detail.

### Patch 9. D6 — rewrite to remove emission details

**Before:** Referenced `.ads`/`.adb` emission, GNAT compilation, GNATprove verification, DO-178C certification.

**After:** States language-level single-file package model with implementation-defined symbol files.

### Patch 10. D7 — remove emitted Ada elaboration details

**Before:** Referenced `pragma Preelaborate`, `pragma Pure`, GNAT's static elaboration model, and "enforced by the emitted Ada's elaboration model."

**After:** States language-level sequencing guarantees without specifying emission mechanism.

### Patch 11. D11 — remove single-pass compiler reference

**Before:** "the compiler processes declarations when it encounters them, which is exactly what single-pass compilation does."

**After:** "declarations are visible from their point of declaration to the end of the enclosing scope."

### Patch 12. D12 — remove single-pass compiler references

**Before:** "always known in a single-pass compiler at the point of use" and "single biggest obstacle to single-pass compilation in Ada."

**After:** "always known at the point of use due to declaration-before-use" and "single biggest source of name-resolution complexity in Ada."

### Patch 13. D15 — remove emitted Ada and GNAT runtime details

**Before:** Referenced "compiles to Jorvik-profile SPARK," "compiler-generated protected objects," "GNAT's Jorvik-profile runtime."

**After:** States language-level guarantees only.

### Patch 14. D17 — remove emitted Ada ownership table and deallocation emission note

**Before:** Table had "Ada access kind in emitted code" column. Included implementation note about `Ada.Unchecked_Deallocation` generic instantiations and GNATprove leak checking.

**After:** Table shows only "Safe construct" and "Ownership semantics." Deallocation emission note removed.

### Patch 15. D19 — remove emitted Ada annotation generation detail

**Before:** Referenced "500–800 lines of compiler code for contract lowering" and "compiler automatically generates Global, Depends, and Initializes in the emitted Ada."

**After:** States language rules guarantee Bronze and Silver assurance without developer-authored contracts.

### Patch 16. D22 — remove emitted Ada annotation generation detail

**Before:** Referenced "compiler automatically generates Global, Depends, and Initializes in the emitted Ada from the compiler's name resolution and data flow analysis."

**After:** States language guarantees assurance through type system and legality rules.

### Patch 17. D23 — remove single-pass compilable and C FFI Silver guarantee references

**Before:** "trivially single-pass compilable" and "imported C function is an unverifiable hole in the Silver guarantee."

**After:** "trivially compilable" and references removed.

### Patch 18. D24 — remove GNATprove reference

**Before:** "since GNATprove cannot analyze foreign code."

**After:** "since foreign code cannot be analysed by the language's verification rules."

### Patch 19. D25 (Ada/SPARK Emission Backend) — remove entire decision

Moved to `DEFERRED-IMPL-CONTENT.md`. Backend specification is an implementation decision.

### Patch 20. D26 — rewrite as pure language-property guarantees

**Before:** Detailed compiler mechanism (single-pass analysis, emitter formatting, GNATprove validation, compiler cost estimates).

**After:** States Stone/Bronze/Silver/Concurrency guarantees as language properties. Removes all implementation-mechanism detail.

### Patch 21. D27 Rule 1 — remove emitted Ada idiom

**Before:** Included "Emitted Ada idiom" paragraph about `Wide_Integer` type, GNATprove interval analysis discharge.

**After:** States language-level wide intermediate arithmetic semantics without specifying emission mechanism.

### Patch 22. D28 — remove SPARK emission, runtime, and compiler cost subsections

**Before:** Included SPARK emission subsection (Jorvik-profile SPARK generation, protected objects, entry calls), runtime subsection (GNAT's Jorvik runtime), and compiler cost table (1,350–2,000 LOC).

**After:** Retains only language-level semantics (task declarations, channels, select, ownership, non-termination rule, grammar).

### Patch 23. D29 (Reference Implementation in Silver-Level SPARK) — remove entire decision

Moved to `DEFERRED-IMPL-CONTENT.md`. Reference implementation requirements are a project decision, not a language definition.

### Patch 24. Specification Document Structure — remove implementation-profile content from all section drafting instructions

Changes across §00–§08:
- §00: D1–D29 → D1–D28; GNATprove TBD item generalised
- §02: Removed Jorvik-profile SPARK note; generalised contract exclusion rationale
- §03: Removed emitted Ada implementation requirements; generalised effect summaries
- §04: Removed Jorvik/Ravenscar references; removed emitted Ada pragma; generalised effect analysis
- §05: Renamed from `05-spark-assurance.md` to `05-assurance.md`; rewrote all bullets as language properties
- §06: Removed "single-pass" from compilation model; removed entire informative implementation guidance block
- §07-annex-b: Replaced detailed content with stub referencing `DEFERRED-IMPL-CONTENT.md`
- Workflow: Updated §05 reference
- Quick Reference: Removed emitted Ada example block; generalised "compiler enforces" to "implementation enforces"
- Editorial Convention 7: Removed GNAT/GNATprove product names

**Additional consistency fixes during patch application:**
- D10 rationale: "single-pass compilation" → "declaration-before-use compilation"; "compiler extracts" → "implementation extracts"
- D17 rationale: "compatible with single-pass compilation" → "compatible with separate compilation"
- D2: Removed Jorvik/Ravenscar profile names from decision and rationale

---

## Round 4 Consistency Pass

1. **GNAT/GNATprove references:** Zero occurrences in SPEC-PROMPT.md. ✓
2. **"emitted Ada" / "emitted code":** Zero occurrences. ✓
3. **"single-pass" / "single pass":** Zero occurrences. ✓
4. **Jorvik/Ravenscar references:** Zero occurrences. ✓
5. **Wide_Integer references:** Zero occurrences. ✓
6. **.ads/.adb file references:** Zero occurrences. ✓
7. **SPARK_Mode:** One occurrence in D22 (excluded aspect list) — correct, this is a language-level exclusion. ✓
8. **Unchecked_Deallocation:** Three occurrences in D17/§02 exclusion lists — correct, language-level exclusions. ✓
9. **References to removed decisions (D3, D4, D5, D25, D29):** Zero occurrences. D1–D28 range used. ✓
10. **"the compiler" wording:** Remaining occurrences are generic (any conforming implementation), not tool-specific. ✓
11. **Toolchain Baseline section:** Zero references. Section fully removed. ✓
12. **Partition_Elaboration_Policy pragma:** Zero occurrences. Moved to deferred content. ✓
13. **Protected object / ceiling priority:** Remaining references are in language-level context (D15 rationale, D26 concurrency guarantees, D28 channel rationale, §04 drafting instructions). ✓
14. **§05 filename:** All references use `05-assurance.md`, not `05-spark-assurance.md`. ✓

---

## Round 5

Technical-correctness and standards-readiness fixes identified by two independent ECMA-track readiness reviews of the post-R4 document.

### P0-R5-1. Deadlock Freedom Overclaim

**Problem:** SPEC-PROMPT.md claimed "deadlock freedom by construction" in D2, D15, D26, and D28. The ceiling priority protocol prevents priority inversion but does NOT prevent application-level deadlock from circular blocking channel operations (e.g., two tasks each blocking on `send` to a full channel, waiting for the other to `receive`).

**Changes (7 edits):**
- D2 rationale: "provable deadlock freedom" → "determinism and analysability"
- D15 rationale: "data-race freedom and deadlock freedom by construction" → "data-race freedom by construction" with explicit note that deadlock freedom is not guaranteed
- D26 concurrency safety: "Deadlock freedom" bullet → "Priority inversion avoidance" with explicit statement that application-level deadlock freedom is NOT guaranteed and depends on communication topology
- D28 channel rationale: "data-race freedom and deadlock freedom by construction" → "data-race freedom by construction" with deadlock qualification
- §05 concurrency assurance: "Deadlock freedom" → "Priority inversion avoidance" plus explicit note about circular-wait risk
- §05 examples: deadlock freedom example → data-race freedom example plus informative deadlock topology note
- TBD register: added deadlock freedom future work item

### P1-R5-1. §04 Task Startup — Informative Mapping Note

**Change:** Added informative note about `pragma Partition_Elaboration_Policy(Sequential)` as the standard Ada/SPARK mechanism for the task-startup guarantee. Explicitly marked as informative.

### P1-R5-2. Editorial Convention 6 — Diagnostic Wording

**Before:** "accompanied by the expected diagnostic message."

**After:** "accompanied by identification of the violated rule and the source location of the violation. Do not mandate specific diagnostic wording in normative text."

### P1-R5-3. §03 Static Semantics — Symbol-File Language

**Before:** "Symbol files shall include effect summaries..."

**After:** Structured list of interface information requirements (visibility, types, signatures, effect summaries) with mechanism explicitly implementation-defined.

### P1-R5-4. §05 Rejected-Program Example — Diagnostic Wording

**Before:** "with the expected diagnostic message"

**After:** "with identification of the violated D27 rule for each rejection"

### P2-R5-1. D23 Unresolved Conditionals

**Change:** D23 entries for declare expressions and delta aggregates now reference TBD register. TBD register includes confirmation item.

### P2-R5-2. D6 Mechanism Neutrality

**Before:** "A conforming implementation extracts the public interface into a symbol file for separate compilation."

**After:** "A conforming implementation shall make the public interface available to dependent compilation units for separate compilation. The mechanism (e.g., symbol files, compiler databases) is implementation-defined."

### P2-R5-3. §03 Implementation Requirements

**Before:** "symbol file emission, incremental recompilation rules"

**After:** "interface information emission (mechanism is implementation-defined), incremental recompilation expectations"

### P2-R5-4. §04 Task-Variable Ownership

**Before:** Referenced "dependency symbol files" and "compile-time checking algorithm."

**After:** References "dependency interface information" and states the rule as a "legality rule."

### P2-R5-5. §06 Stone/Representability

**Before:** "Every conforming Safe program is expressible as valid Ada 2022 / SPARK 2022 source"

**After:** "Every conforming Safe program uses only constructs defined by ISO/IEC 8652:2023 as restricted and modified by this specification." With informative note about Ada mapping.

**Additional consistency fixes:**
- §06 compilation model: removed "symbol files" from opening clause, replaced with mechanism-neutral language
- D7 across-packages: "symbol file does not yet exist" → "circular `with` dependencies are prohibited"
- D9 rationale: "exports the type name to the symbol file" → "exports the type name to dependent units"
- D10 rationale: "extracts the signature for the symbol file" → "extracts the signature for separate compilation"

---

## Round 5 Consistency Pass

1. **"Deadlock freedom" as language guarantee:** Zero unqualified claims. All occurrences explicitly state deadlock freedom is NOT a language guarantee, or appear in TBD register/§05 instructions discussing it as a non-guarantee. ✓
2. **"Data-race freedom" preserved:** All locations that previously said "data-race freedom and deadlock freedom" now say "data-race freedom" without the deadlock claim. Data-race freedom remains guaranteed. ✓
3. **Priority inversion avoidance:** D26 concurrency safety says "Priority inversion avoidance" not "Deadlock freedom." ✓
4. **§04 informative mapping note:** Task startup instructions include informative note about `Partition_Elaboration_Policy(Sequential)`. ✓
5. **Editorial Convention 6:** Says "identification of the violated rule" not "expected diagnostic message." ✓
6. **§03 Static Semantics:** Specifies information requirements with "mechanism is implementation-defined." No "symbol files shall include." ✓
7. **§05 rejected-program example:** Says "identification of the violated D27 rule" not "expected diagnostic message." ✓
8. **TBD register:** Contains deadlock freedom future work item and declare expressions/delta aggregates confirmation item. ✓
9. **§06 Representability:** Guarantee is about Safe's own rules, not Ada expressibility. Informative note preserved. ✓
10. **D23 conditional entries:** Both reference TBD register. ✓
11. **D6 mechanism neutrality:** Says "make the public interface available" with mechanism implementation-defined. No "extracts into a symbol file." ✓
12. **§03 Implementation Requirements:** Says "interface information emission" not "symbol file emission." ✓
13. **§04 task-variable ownership:** Says "dependency interface information" not "dependency symbol files." Says "legality rule" not "checking algorithm." ✓
14. **"Symbol file" as requirement:** Three remaining occurrences — all are "e.g., symbol files" (example of mechanism) or annex-b stub (informative). Zero normative mandates. ✓

---

## Round 6

Technical-correctness and SPARK 2022 alignment fixes identified by a fifth independent ECMA-track readiness review. Verification of SPARK 21 and SPARK 22 release notes confirmed declare expressions/delta aggregates as SPARK 21 features and confirmed SPARK 22's expanded access type support. This round brings Safe into alignment with the full SPARK 2022 ownership model.

### P0-R6-1. Align Safe's Access Type Model with Full SPARK 2022 Ownership

**Problem:** D17 excluded three access type kinds that SPARK 2022 supports with well-defined ownership semantics: anonymous access types (used for local borrowing/observing and traversal functions), general access types (`access all T`, subject to ownership checking), and named access-to-constant types (exempt from ownership checking). Without these, Safe could not express in-place traversal of linked data structures, local borrower variables, safe read-only sharing, or moving ownership of aliased objects into pointers.

**Changes (9 edits):**
- D2 rationale: expanded SPARK 2022 description to mention all access type kinds; added "Safe retains the full SPARK 2022 ownership model for access-to-object types"
- D17 Decision: rewritten to list all retained access-to-object type kinds; access-to-subprogram exclusion rationale now references D18
- D17 Ownership model table: expanded from 7 rows to 12, adding local borrow, local observe, named access-to-constant, general access-to-variable, and general access move entries
- D17 Restrictions: heading changed from "Restrictions vs. full SPARK ownership" to "Restrictions vs. full Ada access types"; exclusion list reduced to access-to-subprogram, `Unchecked_Access`, and `Unchecked_Deallocation`; added "Retained SPARK 2022 access type kinds" list
- D17 Rationale: expanded to mention all extended access type kinds; added drafting constraint referencing SPARK RM/UG §5.9
- D23 Retained features: access type entry expanded to list all kinds; `'Access` attribute and aliased objects added as retained
- §02 Restrictions drafting instructions: access-to-object section rewritten to retain all SPARK 2022 kinds; only access-to-subprogram excluded; `'Access` retained; SPARK UG §5.9 referenced
- §08 Syntax summary: "pool-specific only — `access all` excluded" → "all access-to-object kinds per SPARK 2022 ownership model"; exclusion note updated

### P0-R6-2. Quick Reference `Scale` Function — Nonzero Proof Discarded

**Problem:** `Scale` converted `Divisor` from `Channel_Count` (1..8) to `Integer` before division. The conversion discards the nonzero proof: `Integer` range includes zero, and the conversion result is not a static expression. The divisor was nonconforming under D27 Rule 3.

**Before:**
```ada
return Integer(R) / Integer(Divisor);
```

**After:**
```ada
return Integer(R) / Divisor;
```

`Divisor` stays in `Channel_Count` (range 1..8, excludes zero, satisfying Rule 3(a)). Wide intermediate arithmetic handles the mixed-type operands.

### P1-R6-1. "Interval Analysis" as Mandated Technique in D27

**Problem:** D27 used "interval analysis" as if it were the required analysis method. Standards should state what must be true, not how an implementation proves it.

**Changes (3 edits):**
- D27 Rule 1, intermediate overflow paragraph: "the implementation's interval analysis determines" → "a conforming implementation cannot establish (by sound static range analysis)"; "discharged via interval analysis" → "discharged via sound static range analysis"; added "Interval analysis is one permitted technique; no specific analysis algorithm is mandated"
- D27 Combined effect table: "Interval analysis on wide intermediates" → "Sound static range analysis on wide intermediates"
- §05 AoRTE bullet: "interval arithmetic on wide intermediates makes these provable" → "sound static range analysis on wide intermediates makes these decidable" with non-mandate note

### P1-R6-2. Effect Summaries Must Be Explicitly Interprocedural

**Problem:** §03 Static Semantics said effect summaries provide "the set of package-level variables read and written" without specifying whether this is the direct or interprocedural (transitive) set. D28 requires transitivity for task-variable ownership checking.

**Before:**
> Effect summaries: for each exported subprogram, the set of package-level variables read and written (needed for callers to compute their own flow information and for task-variable ownership checking across packages)

**After:**
> Effect summaries: for each exported subprogram, a conservative interprocedural summary (including transitive callees) of the package-level variables read and written. This is needed for callers to compute their own flow information and for task-variable ownership checking across packages. The summary may be conservatively over-approximate; precision may improve over time without affecting conformance.

### P1-R6-3. D26 "Type Information Alone" Needs Precision

**Problem:** D26 said runtime checks are "provably safe from type information alone." The checks are provable from static type information, subtype bounds, and static expressions — not types alone.

**Before:**
> provably safe from type information alone

**After:**
> provably safe from static type and range information derivable from the program text (including subtype bounds, static expressions, and checked conversions)

### P2-R6-1. Resolve D23 TBD — Declare Expressions and Delta Aggregates

**Problem:** D23 had two entries marked "retained if confirmed as part of SPARK 2022 (see TBD register)." SPARK 21 release notes (2021) confirm both features.

**Changes (2 edits):**
- D23 entries: "retained if confirmed as part of SPARK 2022 (see TBD register)" → "retained; confirmed as part of the SPARK subset since SPARK 21" (delta aggregates also noted as replacement for deprecated `'Update`)
- TBD register: declare expressions/delta aggregates item removed

### P2-R6-2. §03 Implementation Requirements — Incremental Recompilation

**Problem:** §03 Implementation Requirements said "incremental recompilation expectations." ISO Ada does not mandate recompilation strategy.

**Before:**
> interface information emission (mechanism is implementation-defined), incremental recompilation expectations

**After:**
> interface information mechanism requirements (implementation-defined). Do not mandate incremental recompilation in normative text; performance/build-system advice belongs in Annex B (informative).

### P2-R6-3. §00 TBD Register — Missing Items

**Change:** Added two items to TBD register:
- Numeric model: required ranges/representation assumptions for predefined integer types given the 64-bit signed bound in D27 Rule 1
- Automatic deallocation semantics for owned access objects (ordering at scope exit, interaction with early return/goto, multiple owned objects exiting scope simultaneously)

---

## Round 6 Consistency Pass

1. **D17 access type kinds:** All five access-to-object kinds listed. Access-to-subprogram is the only excluded access type kind. ✓
2. **D17 ownership table:** Includes local borrow, local observe, named access-to-constant (exempt), general access-to-variable (ownership checked, cannot deallocate). ✓
3. **D17 restrictions section:** Heading says "Restrictions vs. full Ada access types." Anonymous access, general access, and access-to-constant NOT in exclusion list. "Retained SPARK 2022 access type kinds" list present. ✓
4. **D2 SPARK alignment:** Says Safe retains "the full SPARK 2022 ownership model for access-to-object types." ✓
5. **D23 retained features:** Access type entry includes all retained kinds. `'Access` attribute listed as retained. Aliased objects listed as retained. ✓
6. **§02 restrictions drafting instructions:** Access-to-object types listed as retained (all kinds per SPARK 2022). Only access-to-subprogram excluded. ✓
7. **§08 syntax summary:** "all access-to-object kinds per SPARK 2022 ownership model." ✓
8. **Quick Reference `Scale` function:** Divisor is `Divisor` (type `Channel_Count`), not `Integer(Divisor)`. ✓
9. **D27 "interval analysis" replaced:** Zero occurrences as normative requirement. One informative mention ("one permitted technique") retained. ✓
10. **§03 effect summaries:** "conservative interprocedural summary (including transitive callees)." ✓
11. **D26 precision:** "static type and range information derivable from the program text." ✓
12. **D23 resolved:** Both entries say "retained; confirmed as part of the SPARK subset since SPARK 21." TBD item removed. ✓
13. **§03 Implementation Requirements:** No normative incremental recompilation mandate. ✓
14. **§00 TBD register:** New items (numeric model, automatic deallocation semantics) present. Declare expressions/delta aggregates item removed. ✓
15. **No new GNAT/GNATprove references:** Zero occurrences in normative content. ✓
16. **`Unchecked_Access` still excluded:** Explicitly excluded in D17 and §02. `'Access` retained separately. ✓
17. **Access-to-subprogram exclusion rationale:** References D18 (static call resolution), not ownership. ✓

### Round 6 Residual

- Propagated D26 precision fix to D27 combined effect table and §06 conformance Silver bullet
- "type information alone" → "static type and range information derivable from the program text" (2 edits)
- Consistency check: zero occurrences of "type information alone" remain

---

## Round 7

ECMA-track fitness fixes: self-containment of normative references and implementation-strategy neutrality. No technical design decisions changed.

### P0-R7-1. SPARK References: "Authoritative" → "Informative Precedent"

**Problem:** D17 drafting constraint and §02 restrictions drafting instructions told the drafter to treat SPARK RM/UG as "authoritative" for ownership rules. For ECMA submission, the generated Safe LRM must be self-contained — its legality rules cannot depend on external non-ISO vendor documentation.

**Changes (2 edits):**
- D17 Drafting constraint: "You may cite SPARK RM/UG as the authoritative design reference" → "You may cite SPARK RM/UG as informative precedent"; added "The Safe LRM shall be self-contained: a reader shall not need to consult any external (non-ISO) specification"; added corner-case coverage requirement (scope exit, early return, goto interactions, reborrowing depth)
- §02 access types instruction: "Reference the SPARK RM and SPARK UG §5.9 ownership rules" → "Specify Safe ownership rules directly and self-containedly within this LRM. Use SPARK RM/UG §5.9 as informative design precedent"

### P0-R7-2. Channel Buffer: "Statically Allocated" → Observable Property

**Problem:** D28 said channel buffers are "statically allocated." This prescribes an allocation strategy. Language standards define observable properties, not implementation strategies.

**Changes (2 edits):**
- D28 Channel declarations: "the buffer is statically allocated" → "the required storage bound for any channel is fixed for a given program. The allocation strategy (static, pre-allocated heap, or other) is implementation-defined"
- §04 Channel declarations instruction: "static allocation of channel buffers" → "storage bound fixed at compile time; allocation strategy is implementation-defined"

### P1-R7-1. TBD Register Discipline

**Problem:** TBD register had no ownership, resolution plan, or target milestone tracking.

**Change (1 edit):**
- §00 TBD register heading: added "Each item should be resolved before baselining. When resolution ownership is assigned, annotate each item with: owner, resolution plan, and target milestone."

### P2-R7-1. TBD Register — New Items from SPARK 21–26 Feature Review

**Problem:** A review of SPARK 21–26 release features identified three capabilities that Safe's current design does not address. Added to TBD register for tracking.

**Change (1 edit):**
- §00 TBD register: added three items:
  - Modular arithmetic wrapping semantics (annotated "High priority" — natural extension of D27's philosophy; SPARK 21 `No_Wrap_Around` and SPARK 25 `No_Bitwise_Operations` as design precedent)
  - Limited/private type views across packages (SPARK 26 `with type` mechanism as design precedent)
  - Partial initialisation facility (SPARK 21–24 `Relaxed_Initialization` and `Initialized` aspects as design precedent)

---

## Round 7 Consistency Pass

1. **"authoritative" only refers to Safe grammar (§08), not SPARK.** ✓
2. **D17 drafting constraint says "self-contained."** ✓
3. **D17 says "informative precedent," not "authoritative design reference."** ✓
4. **§02 says "Use SPARK RM/UG §5.9 as informative design precedent."** ✓
5. **Zero "statically allocated" in channel text; "implementation-defined" present.** ✓
6. **§04 channel instruction updated to "storage bound fixed at compile time; allocation strategy is implementation-defined."** ✓
7. **TBD register heading includes "owner, resolution plan, and target milestone."** ✓
8. **No new GNAT/GNATprove references.** ✓
9. **Reference Documents section still lists SPARK RM and UG (correctly, as drafter resources).** ✓
10. **New TBD items present:** modular arithmetic wrapping semantics (with "High priority" annotation), limited/private type views, partial initialisation facility. ✓
