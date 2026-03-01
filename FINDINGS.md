# Findings — Issues Discovered in SPEC-PROMPT.md

**These findings are flagged for human review. No patches have been applied to SPEC-PROMPT.md.**

---

## F1. `abstract` in Grammar Despite Being Excluded — RESOLVED

**Location:** D18 (No Tagged Types), D23 (Retained Ada Features)

**Issue:** The 8652:2023 grammar for `record_type_definition` includes `[ 'abstract' ] 'limited'` as an optional prefix. Since abstract types are excluded by D18, the `abstract` keyword should not appear in the Safe grammar's record type productions. However, removing it creates a divergence from the 8652:2023 production structure that could confuse readers comparing the two grammars.

**Resolution:** Removed `abstract` from the `record_type_definition` production in §08 (syntax summary). The production now reads `[ 'limited' ] record_definition`. The `abstract` keyword remains reserved (per the policy that all Ada 2022 reserved words stay reserved in Safe) but no longer appears in any grammar production. The §02 paragraph 7 legality rule rejecting `abstract` type declarations is unchanged — it now serves as belt-and-suspenders reinforcement rather than the sole enforcement mechanism. This is consistent with how every other excluded feature (generics, tagged types, exceptions, etc.) was handled: productions removed from §08, legality rules in §02 for completeness.

---

## F2. `delay until` Time Type Unspecified

**Location:** D23 (Retained Ada Features), D28 (section on delay in select arms)

**Issue:** `delay until` is retained and appears in the grammar and in §04 select statement delay arms. However, `delay until` in 8652:2023 requires a time value (typically `Ada.Calendar.Clock` or `Ada.Real_Time.Clock`). Both `Ada.Calendar` and `Ada.Real_Time` are excluded (Annex A). SPEC-PROMPT.md retains `delay Duration_Expression` but does not explicitly address the time type for `delay until`.

**Recommendation:** Either (a) exclude `delay until` and retain only `delay Duration;`, or (b) add a TBD item specifying what time type is available for `delay until`, or (c) state that the time type for `delay until` is implementation-defined. The generated spec took approach (c) in §02 paragraph 86 and Annex A §58–60.

---

## F3. Quantified Expressions Exclusion vs. SPARK Subset

**Location:** D23 (Retained Ada Features), implied by "All Ada 2022 features in the SPARK 2022 subset not otherwise excluded"

**Issue:** Quantified expressions (`for all`, `for some`) are part of the SPARK 2022 subset. D23 states "All Ada 2022 features in the SPARK 2022 subset not otherwise excluded" are retained. However, quantified expressions are primarily useful in contracts, which are excluded (D19). The generated spec excludes them (§02 paragraph 22), but SPEC-PROMPT.md does not explicitly list them as excluded.

**Recommendation:** Add `quantified expressions` to D19 or create a new decision explicitly excluding them, with rationale: "useful only in contracts; excluding contracts makes quantified expressions superfluous."

---

## F4. D17 Ownership Table Column for Emitted Ada

**Location:** D17 Ownership model summary table

**Issue:** The D17 table in SPEC-PROMPT.md has two columns: "Safe construct" and "Ownership semantics." Previous revisions (per CHANGELOG.md) removed the "Emitted Ada" column as part of the tool-independence refactoring. However, the table entry for `X := new ((...) : T)` uses the type annotation syntax form, but the entry for `procedure P (A : in T_Ptr)` says "Read-only access: caller's ownership frozen" — this is described as "observing" in §2.3 but the table says "Read-only access." The terminology is inconsistent between the table summary and the detailed ownership rules.

**Recommendation:** Align the D17 table terminology with the ownership model definitions: use "Observe" instead of "Read-only access" and "Borrow" instead of "Temporary mutable access" for consistency with §2.3 and with the SPARK precedent terminology.

---

## F5. `Convention` Pragma Listed in Both Retained and Excluded

**Location:** §02 Pragma Inventory generation

**Issue:** SPEC-PROMPT.md §D24 excludes all foreign language interface including `pragma Convention`. However, `Convention` could be argued as retained for the `Convention(Ada, ...)` case, which is the default. The spec-analysis.md from a prior generation noted similar confusion. The generated spec lists it as excluded (under paragraph 84, Annex B exclusion), but its presence in the retained pragmas table (§2.6.1 paragraph 121) with a cross-reference "Excluded — see paragraph 84" could be confusing.

**Recommendation:** Clarify in SPEC-PROMPT.md whether `pragma Convention(Ada, ...)` is retained (since it is the default convention and doesn't introduce foreign interfaces) or excluded along with all Annex B features. If retained, state so explicitly. If excluded, remove it from the retained table.

---

## F6. `Normalize_Scalars` Ambiguity

**Location:** Pragma inventory

**Issue:** The prior spec-analysis.md noted that `Normalize_Scalars` appeared in both retained and excluded categories in a previous generation. SPEC-PROMPT.md does not explicitly classify it. Annex H is mostly excluded (§02 paragraph 90), but `Normalize_Scalars` is a standalone pragma (§H.1) that could be useful for initialisation safety.

**Decision taken:** Excluded in the generated spec (§02 paragraph 122) with rationale: "may mask uninitialised reads." This is a judgement call.

**Recommendation:** Add `Normalize_Scalars` to SPEC-PROMPT.md's explicit exclusion list with rationale, or explicitly retain it with justification.

---

## F7. `from` as Reserved Word

**Location:** D28 grammar additions, Reserved Words section

**Issue:** SPEC-PROMPT.md's reserved words section lists `public`, `channel`, `send`, `receive`, `try_send`, `try_receive`, `capacity` as new reserved words. However, the D28 grammar for `channel_arm` uses `from` as a keyword: `'when' identifier ':' type_mark 'from' channel_name`. The reserved words section does not list `from` as a new reserved word.

`from` is not an Ada 2022 reserved word either (it does not appear in 8652:2023 §2.9).

**Recommendation:** Add `from` to the Safe additional reserved words list in SPEC-PROMPT.md, or redesign the select arm syntax to use only existing reserved words (e.g., replace `from` with `of` or restructure the grammar).

---

## F8. Subprogram Forward Declaration `public` Placement

**Location:** D10 (Subprogram Bodies at Point of Declaration)

**Issue:** SPEC-PROMPT.md states forward declarations are permitted for mutual recursion but does not specify whether the `public` keyword appears on the forward declaration, the completing body, or both. This is an ambiguity that the generated spec resolved (§03 paragraph 14: `public` appears on the forward declaration).

**Recommendation:** Add a sentence to D10 specifying where `public` appears in the forward declaration + body pattern.

---

## F9. Task Body Declarative Part Placement

**Location:** D28 task declaration grammar

**Issue:** D28's task declaration grammar shows:
```
task_declaration ::=
    'task' identifier [ 'with' 'Priority' '=>' static_expression ] 'is'
    'begin'
        handled_sequence_of_statements
    'end' identifier ';'
```

This grammar has no declarative part before `begin`. However, the D28 text says "Declarations may precede the loop." The non-termination rule also says "Declarations may precede the outermost loop." This implies declarations go *inside* the handled_sequence_of_statements (as interleaved declarations after `begin`), not before `begin`.

The generated spec grammar (§08, §8.12) includes `[ declarative_part ]` before `begin` in the task declaration, matching the Ada task body pattern, but SPEC-PROMPT.md's grammar does not show this.

**Recommendation:** Clarify whether task bodies have a declarative part before `begin` (Ada-style) or whether all declarations are interleaved after `begin` (matching D11's interleaved declaration model). The generated spec chose to allow both: a pre-`begin` declarative part and interleaved declarations after `begin`, consistent with D11's rule for subprogram bodies.

---

## F10. Allocation Failure Semantics

**Location:** D17, D27

**Issue:** SPEC-PROMPT.md specifies automatic deallocation but does not address what happens when `new` fails to allocate memory. In 8652:2023, this raises `Storage_Error`, which is an exception — and exceptions are excluded. The Silver guarantee (D27) does not address allocation failure.

The TBD register includes TBD-03 "Memory model constraints (stack bounds, heap bounds, allocation failure handling)" but this is a gap in the current specification.

**Recommendation:** Either (a) make allocation failure a hard abort (consistent with `pragma Assert` failure), (b) require implementations to statically bound all allocation (ambitious), or (c) define allocation failure as undefined behaviour subject to TBD resolution. This needs explicit attention before baselining.

---

## F11. `Channel_Id.Range` Attribute

**Location:** Quick Reference example in SPEC-PROMPT.md

**Issue:** The quick reference example uses `Channel_Id.Range` as an attribute in a for loop: `for I in Channel_Id.Range loop`. In 8652:2023, `Range` is an attribute of array objects and types with array-related semantics (§3.6.2), not of scalar types. For scalar types, the loop form is `for I in Channel_Id loop` or `for I in Channel_Id.First .. Channel_Id.Last loop`.

Using `Channel_Id.Range` on a scalar type would require `Range` to be a general-purpose attribute producing a range value, which is not its standard meaning.

**Recommendation:** Correct the quick reference example to use `for I in Channel_Id loop` or `for I in Channel_Id.First .. Channel_Id.Last loop`. The attribute `Range` on scalar types would need explicit specification if intended.

---

## F12. Missing D3/D4/D5/D25/D29 in Specification

**Location:** SPEC-PROMPT.md Design Decisions

**Issue:** SPEC-PROMPT.md defines decisions D1, D2, D6–D28 in the main Design Decisions section. D3 (Single-Pass Compiler), D4 (Ada/SPARK Emission), D5 (Platform-Independent via GNAT), D25 (Ada/SPARK Emission Backend), and D29 (Reference Implementation in Silver SPARK) were moved to DEFERRED-IMPL-CONTENT.md as implementation-profile decisions. The D-number sequence has gaps (no D3, D4, D5, D25, D29 in SPEC-PROMPT.md).

This is intentional (per the Round 4 revision documented in CHANGELOG.md), but the §0.7 Design Decision Summary in the generated front matter refers to D1, D2, D6–D28 with gaps that might confuse readers unfamiliar with the revision history.

**Recommendation:** Consider renumbering the design decisions to be contiguous, or add a note in SPEC-PROMPT.md explaining the numbering gaps.
