# Phase 1 Audit Report — Spot-Check Deep-Dive

**Date:** 2026-03-03
**Auditor:** Claude Opus 4.6
**Scope:** 3 highest-priority templates (wide_arithmetic, channel_fifo, ownership_move)
**Prerequisite:** Phase 0 PASS (all remediation complete)
**GNATprove:** 184/184 VCs proved (0 unproved), max steps = 2

---

## 1. Template: `template_wide_arithmetic`

### A. Contract-Level Review

#### A1. PO Hook Call-Site Correctness — PASS

**`Narrow_Return` (adb:54-56):**
- Called with `Long_Long_Integer(Wide_Result)` and `Sensor_Value_Range = (Lo => 0, Hi => 1000)`.
- Hook precondition: `Is_Valid_Range(Return_Range) and then Contains(Return_Range, V)`.
- `Is_Valid_Range((0, 1000))` = True (0 <= 1000).
- `Wide_Result` is proven in 0..1000 by the preceding `pragma Assert` (adb:48-49).
- Conversion `Long_Long_Integer(Wide_Result)` is safe: `Wide_Integer` and `Long_Long_Integer` share the 64-bit range.
- `Contains((0, 1000), Long_Long_Integer(Wide_Result))` = True.

**`Narrow_Assignment` (adb:81-83):**
- Called with `Long_Long_Integer(Wide_Sum)` and `Sensor_Value_Range`.
- `Add_Clamped`'s precondition ensures `LLI(A) + LLI(B) <= 1000`.
- Since `A, B : Sensor_Value` (range 0..1000), the sum >= 0.
- So `Wide_Sum` is in 0..1000; `Contains` holds.

Both hook calls satisfy their preconditions at the call site.

#### A2. Pre/Post Contract Completeness — PASS

- **Average:** Post guarantees result in 0..1000 (D27 Rule 1 range obligation). Does not specify functional correctness (`= Sum/10`), which is by design — the template demonstrates range safety.
- **Add_Clamped:** Pre guards upper bound (`LLI(A) + LLI(B) <= 1000`); lower bound is implicit from `Sensor_Value` subtype (>= 0). Post establishes `Result = A + B`.
- All referenced D27 Rule 1 clauses (2.8.1.p126, p127, p130) and Silver AoRTE clause (5.3.6.p25) are exercised.

#### A3. Ghost Function Correctness — PASS

`Sensor_Value_Range : constant Range64 := (Lo => 0, Hi => 1000) with Ghost;`

Correctly maps `Sensor_Value` subtype (0..1000) to `Range64` model type. No other ghost functions in this template.

#### A4. Clause Traceability — PASS

| Clause | Content | Template Exercise |
|--------|---------|-------------------|
| 2.8.1.p126 | Wide intermediate arithmetic | Sum in `Wide_Integer` |
| 2.8.1.p127 | Narrowing points enumerated | Return (Average), Assignment (Add_Clamped) |
| 2.8.1.p130 | Range check at narrowing | `Narrow_Return`, `Narrow_Assignment` calls |
| 5.3.6.p25 | Silver AoRTE for narrowing | Proven by GNATprove |

### B. Golden File Comparison (`golden_sensors.ada`)

#### B1. Structural Alignment — PASS

- Both use fixed-size array (10 sensors), accumulate in wide integer, divide by 10, return narrowed result.
- Golden uses `Long_Long_Integer`; template uses `Safe_Runtime.Wide_Integer` (same 64-bit range).
- Template adds `Add_Clamped` (additional pattern demonstrating assignment narrowing; not in golden — this is an extension, not a discrepancy).
- Operation order matches: loop → accumulate → assert bounds → divide → return.

#### B2. Narrowing/Assertion Correspondence — PASS

| Golden | Template |
|--------|----------|
| `pragma Assert (Sum >= 0)` (pre-add) | `pragma Loop_Invariant (Sum >= 0)` (strengthened) |
| `pragma Assert (Sum <= LLI(I-1)*1000)` | `pragma Loop_Invariant (Sum <= Wide_Integer(I-1)*1000)` |
| `pragma Assert (Sum >= 0 and Sum <= 10_000)` | `pragma Assert (Sum >= 0 and then Sum <= 10_000)` |
| `pragma Assert (Sum/10 >= 0 and Sum/10 <= 1000)` | `pragma Assert (Wide_Result >= 0 and then Wide_Result <= 1000)` |
| (none — implicit at return) | `Narrow_Return(...)` PO hook |

Template uses loop invariants (SPARK-idiomatic) instead of per-iteration assertions, and PO hooks instead of ad-hoc assertions. Every golden assertion has a corresponding or stronger template construct.

#### B3. Semantic Gap Analysis — PASS (no gaps)

1. **Wide type:** Golden uses `Long_Long_Integer`; template uses `Wide_Integer`. Both are 64-bit signed. Semantically equivalent.
2. **Index type:** Golden uses `Sensor_Count` subtype; template uses literal range `1..10`. Equivalent.
3. **Add_Clamped:** Extra pattern in template, not in golden. Extension only.
4. **Short-circuit:** Golden uses `and` in some assertions; template consistently uses `and then`. Template is stricter.

### C. SPARK 2022 Compliance — PASS

- `pragma SPARK_Mode (On)`: Present at file and package level.
- `pragma Assertion_Policy (Check)`: Present.
- Ghost aspect on `Sensor_Value_Range`: Correct, no runtime leakage.
- Loop invariants (INIT/PRESERVE): `Sum >= 0` ✓ `Sum <= (I-1)*1000` ✓ (verified by GNATprove).
- Short-circuit `and then` in all contracts.
- `'Result` used correctly in `Average` postcondition.
- No access types, tasking, or exceptions.

### GNATprove Results

- `Average`: 12 proof VCs (4 loop invariant, 1 overflow, 3 assertions, 1 precondition, 2 range checks, 1 postcondition) — all proved by CVC5.
- `Add_Clamped`: 4 proof VCs (1 range check, 1 precondition, 1 range check, 1 postcondition) — all proved by CVC5.

---

## 2. Template: `template_channel_fifo`

### A. Contract-Level Review

#### A1. PO Hook Call-Site Correctness — PASS

**`Check_Channel_Capacity_Positive` (adb:22):**
- Called with `Cap : Capacity_Range` where `Capacity_Range is Positive range 1..Max_Capacity`.
- Hook precondition: `Capacity > 0`. Since `Cap >= 1 > 0`, satisfied.

**`Check_Channel_Not_Full` (adb:45):**
- Called with `(Ch.Count, Ch.Capacity)`.
- Hook precondition: `Length < Capacity`.
- `Send`'s precondition includes `Ch.Count < Ch.Capacity`, which holds at this point.

**`Check_Channel_Not_Empty` (adb:70):**
- Called with `Ch.Count`.
- Hook precondition: `Length > 0`.
- `Receive`'s precondition includes `Ch.Count > 0`, which holds at this point.

#### A2. Pre/Post Contract Completeness — PASS

**Make:**
- Post: `Is_Valid(Make'Result) and then Make'Result.Count = 0 and then Make'Result.Capacity = Cap`.
- Complete specification of empty channel construction.

**Send:**
- Pre: `Is_Valid(Ch) and then Ch.Count < Ch.Capacity`.
- Post covers: validity preserved, count incremented, FIFO ordering (`Buffer(Tail'Old) = Item`), Head unchanged, Tail advances circularly, frame condition (all other buffer slots preserved via universal quantifier).
- This is a complete FIFO send specification including frame conditions.

**Receive:**
- Pre: `Is_Valid(Ch) and then Ch.Count > 0`.
- Post covers: validity preserved, count decremented, FIFO ordering (`Item = Buffer'Old(Head'Old)`), Tail unchanged, Head advances circularly, full buffer preservation.
- Complete FIFO receive specification.

#### A3. Ghost Function Correctness — PASS

**`Is_Valid`** (ads:58-61): Correctly captures structural invariant (Head/Tail within 1..Capacity, Count <= Capacity). Not marked Ghost — correct, since it is evaluated at runtime via `Assertion_Policy(Check)`.

**`Next_Index`** (ads:64-69): Correctly models circular advancement `(if Idx = Cap then 1 else Idx + 1)`. Marked Ghost (used only in postconditions). Pre `Idx <= Cap` ensures no overflow on `Idx + 1`. Range check on result (1..Max_Capacity) proven by GNATprove.

#### A4. Clause Traceability — PASS

| Clause | Content | Template Exercise |
|--------|---------|-------------------|
| 4.2.p15 | Channel capacity positive | `Check_Channel_Capacity_Positive` in `Make` |
| 4.2.p20 | Bounded buffer semantics | Channel type with Capacity discriminant |
| 4.3.p27 | Send requires not full | `Check_Channel_Not_Full` + Pre |
| 4.3.p28 | Receive requires not empty | `Check_Channel_Not_Empty` + Pre |
| 4.3.p31 | FIFO ordering | `Buffer(Tail'Old) = Item` / `Item = Buffer'Old(Head'Old)` |

### B. Golden File Comparison (`golden_pipeline.ada`)

#### B1. Structural Alignment — PASS (with documented divergence)

- Golden uses a protected type (`Channel_Sample_4`) with entries and ceiling priority; template uses a sequential record type. This is documented: "The model is sequential (not a protected object) to enable full GNATprove functional verification."
- Both implement FIFO with circular buffer (Head/Tail/Count).
- Golden uses `Tail := (Tail mod 4) + 1`; template uses `if Tail = Capacity then 1 else Tail + 1`. Both are circular advancement; template is parametric over capacity.
- Golden has task declarations; template omits tasks (covered by `template_task_decl`).

#### B2. Narrowing/Assertion Correspondence — PASS

| Golden | Template |
|--------|----------|
| `when Count < 4` (entry barrier) | `Ch.Count < Ch.Capacity` (precondition) |
| `when Count > 0` (entry barrier) | `Ch.Count > 0` (precondition) |
| (no assertions) | Full postconditions: FIFO ordering, frame conditions, circular advancement |

Template is strictly stronger than golden — every golden barrier has a corresponding precondition, and the template adds postconditions that the golden does not have.

#### B3. Semantic Gap Analysis — PASS (documented gaps only)

1. **Concurrency model:** Golden uses protected types with ceiling priority; template uses sequential model. **Documented — concurrency safety guaranteed by Jorvik runtime model, not this template.**
2. **Capacity parametric:** Golden hardcodes capacity 4; template parameterizes. Template is more general.
3. **Element type:** Golden uses `Sample is range 0..10_000`; template uses `Element_Type is Integer`. Template is more general.
4. **Task bodies:** Golden has Producer/Filter/Consumer tasks; template has no tasks. Covered by `template_task_decl`.

### C. SPARK 2022 Compliance — PASS

- `pragma SPARK_Mode (On)` and `pragma Assertion_Policy (Check)`: Present.
- Ghost on `Next_Index`: Correct, only used in postconditions.
- Short-circuit `and then` throughout all Pre/Post expressions.
- `'Old` used correctly: `Ch.Count'Old`, `Ch.Head'Old`, `Ch.Tail'Old`, `Ch.Buffer'Old`, `Ch.Buffer'Old(I)`.
- Universal quantifier in Send postcondition: `(for all I in Index_Range => ...)` — valid SPARK.
- No access types, tasking, or exceptions.
- Aggregate syntax `[others => 0]` in Make: valid Ada 2022 / SPARK 2022.

### GNATprove Results

- `Make`: 2 proof VCs (precondition, postcondition) — all proved.
- `Next_Index`: 1 proof VC (range check) — proved.
- `Send`: 5 proof VCs (precondition, 2 range checks, postcondition, Next_Index Pre in Post) — all proved.
- `Receive`: 5 proof VCs (precondition, 2 range checks, postcondition, Next_Index Pre in Post) — all proved.

---

## 3. Template: `template_ownership_move`

### A. Contract-Level Review

#### A1. PO Hook Call-Site Correctness — PASS

**`Check_Owned_For_Move` (adb:36):**
- Called with `To_State(Source.Is_Null, Source.Is_Moved)`.
- Hook precondition: `State = Owned`.
- `Move`'s precondition: `not Source.Is_Null and then not Source.Is_Moved`.
- `To_State(False, False)` = `Owned` (by ghost function: neither moved nor null → Owned).

**`Check_Not_Moved` (adb:58):**
- Called with `To_State(P.Is_Null, P.Is_Moved)`.
- Hook precondition: `State /= Moved`.
- `Read_Value`'s precondition: `not P.Is_Moved and then not P.Is_Null`.
- `To_State(False, False)` = `Owned`, which `/= Moved`.

#### A2. Pre/Post Contract Completeness — PASS

**Move:**
- Pre: `not Source.Is_Null and then not Source.Is_Moved and then Target.Is_Null` — encodes "source is Owned, target is Null_State (empty slot)."
- Post: Source becomes Moved (`Is_Null=True, Is_Moved=True`), Target becomes Owned (`Is_Null=False, Is_Moved=False`), value transferred (`Target.Value = Source.Value'Old`).
- Complete specification of ownership transfer.

**Read_Value:**
- Pre: `not P.Is_Moved and then not P.Is_Null` — encodes "P is Owned (dereferenceable)."
- Returns `P.Value`.
- Simple but correct; the pre-dereference ownership check is the key obligation.

#### A3. Ghost Function Correctness — PASS

**`To_State` (adb:14-18):**

```
if Is_Moved then Moved
elsif Is_Null then Null_State
else Owned
```

| Is_Null | Is_Moved | To_State Result | Template Semantic |
|---------|----------|-----------------|-------------------|
| False   | False    | Owned           | Variable owns its object |
| True    | False    | Null_State      | Variable is null (no object) |
| True    | True     | Moved           | Ownership transferred away |
| False   | True     | Moved           | (Unreachable — Move always sets Is_Null=True) |

The (False, True) combination maps to Moved, which is safe since it cannot be reached by the template's Move procedure (which always sets `Is_Null := True` alongside `Is_Moved := True`). **Minor advisory:** This implicit invariant (Is_Moved implies Is_Null) is not enforced by a type predicate, but it is upheld by the only procedure that sets Is_Moved (Move at adb:44-45). Acceptable.

#### A4. Clause Traceability — PASS

| Clause | Content | Template Exercise |
|--------|---------|-------------------|
| 2.3.2.p96a | Move source must be Owned | `Check_Owned_For_Move` call in Move |
| 2.3.2.p96c | After move, source cannot be used | Source becomes Moved; `Check_Not_Moved` at use |
| 2.3.2.p97a | Move transfers ownership | `Move` postcondition (Target.Value = Source.Value'Old) |
| 2.3.5.p104 | Scope-exit deallocation | Referenced; exercised in `template_scope_dealloc` |

### B. Golden File Comparison (`golden_ownership.ada`)

#### B1. Structural Alignment — PASS (with documented divergence)

- Golden uses actual access types (`Payload_Ptr is access Payload`); template uses Boolean-flag model (`Ptr_Model`). **Documented in template header:** "SPARK restriction: access types and ghost types from Safe_Model cannot appear in non-ghost record fields."
- Both model the same pattern: verify owned → copy → null source.
- Golden includes scope-exit deallocation; template focuses on move (deallocation is in `template_scope_dealloc`).

#### B2. Narrowing/Assertion Correspondence — PASS

| Golden | Template |
|--------|----------|
| `pragma Assert (Target = null)` | `Move` Pre: `Target.Is_Null` |
| `Target := Source; Source := null;` | Move body: copy Value, set flags |
| `pragma Assert (Target /= null)` | `Read_Value` Pre: `not P.Is_Null` |
| `if Target /= null then Free(Target); end if;` | In `template_scope_dealloc` |

Every golden assertion has a corresponding or stronger template precondition/hook.

#### B3. Semantic Gap Analysis — PASS (documented gaps only)

1. **Access types vs Boolean flags:** Golden uses real access types; template uses `(Is_Null, Is_Moved, Value)` model. This is the primary modeling gap. The Boolean model faithfully represents the ownership state machine but does not model pointer aliasing or heap allocation. **Documented as assumption B-04 ("Boolean null model").**
2. **Deallocation:** Golden includes `Unchecked_Deallocation`; template omits it. Covered by `template_scope_dealloc`.
3. **Allocator:** Golden uses `new Payload'(Value => 42)`; template initializes record directly. Consequence of the no-access-types constraint.

### C. SPARK 2022 Compliance — PASS

- `pragma SPARK_Mode (On)` and `pragma Assertion_Policy (Check)`: Present.
- Ghost on `To_State`: Correct, only called in ghost PO hook contexts.
- Short-circuit `and then` in all Pre/Post.
- `'Old` used correctly: `Source.Value'Old` in Move postcondition.
- No access types, tasking, or exceptions.

### GNATprove Results

- `Move`: 2 proof VCs (precondition of `Check_Owned_For_Move`, postcondition) — all proved.
- `Read_Value`: 1 proof VC (precondition of `Check_Not_Moved`) — proved.
- `To_State`: 0 proof VCs (expression function, Ghost) — flow only.

---

## 4. Cross-Template SPARK 2022 Compliance Summary

| Check | wide_arithmetic | channel_fifo | ownership_move | Result |
|-------|-----------------|--------------|----------------|--------|
| Ghost aspect usage | `Sensor_Value_Range` constant | `Next_Index` function | `To_State` function | PASS |
| No runtime leakage | Ghost only in PO calls | Ghost only in Post | Ghost only in PO calls | PASS |
| Short-circuit `and then` | All contracts | All contracts | All contracts | PASS |
| Loop invariants INIT/PRESERVE | 2 invariants, both verified | N/A | N/A | PASS |
| `'Old` usage | N/A | Ch fields in Post | Source.Value in Post | PASS |
| `'Result` usage | Average Post | Make Post | N/A | PASS |
| `Assertion_Policy (Check)` | Present | Present | Present | PASS |
| No access types | Confirmed | Confirmed | Confirmed | PASS |
| No tasking constructs | Confirmed | Confirmed | Confirmed | PASS |
| No exceptions | Confirmed | Confirmed | Confirmed | PASS |

---

## 5. Documentation Drift (D) — Fixes Applied

### `docs/template_inventory.md`

| Line | Old | New | Rationale |
|------|-----|-----|-----------|
| 10 | `wide_arithmetic` VCs: 14 | 16 | GNATprove actual: Average(12) + Add_Clamped(4) |
| 13 | `scope_dealloc` VCs: 7 | 13 | GNATprove actual: Dealloc(1) + Run_Scope(12) |
| 15 | `channel_fifo` VCs: 10 | 13 | GNATprove actual: Make(2) + Next_Index(1) + Send(5) + Receive(5) |
| 19 | Total template VCs: 84 | 95 | Sum of all 8 template proof VCs |
| 23 | 178 total VCs | 184 | GNATprove summary |
| 24 | Flow: 54 (30%) | 54 (29%) | Percentage recalculated |
| 25 | Proof: 123 (69%) | 129 (70%) | GNATprove summary |
| 31 | wide_arithmetic: Flow=4, Proof=14, Total=18 | Flow=2, Proof=16, Total=18 | Actual flow/proof recount |
| 34 | scope_dealloc: Proof=7, Total=9 | Proof=13, Total=15 | GNATprove actual |
| 36 | channel_fifo: Flow=4, Proof=10, Total=14 | Flow=7, Proof=13, Total=20 | GNATprove actual |
| 38 | index_safety: Flow=2, Total=16 | Flow=4, Total=18 | Actual flow recount |

### `docs/gnatprove_profile.md`

| Line | Old | New | Rationale |
|------|-----|-----|-----------|
| 33 | `...--warnings=on` | `--warnings=error` | Unified to `--warnings=error` throughout |

**Note:** Lines 42, 103, and 370 now also use `--warnings=error` for `companion.gpr`, matching the `templates.gpr` Prove package and the CI configuration.

---

## 6. Finding Register

| # | Severity | Template | Category | Finding | Status |
|---|----------|----------|----------|---------|--------|
| F-01 | Advisory | ownership_move | A3 (ghost) | `To_State` maps (Is_Null=F, Is_Moved=T) to Moved. This combination is unreachable by template code but not enforced by a type predicate. The implicit invariant (Is_Moved → Is_Null) is upheld by the Move procedure. | Accepted |
| F-02 | Advisory | channel_fifo | B1 (golden) | Template models channel as sequential record; golden uses protected type with ceiling priority. Concurrency safety comes from Jorvik runtime model, not this template. | Documented |
| F-03 | Advisory | ownership_move | B3 (golden) | Template uses Boolean flags instead of access types (SPARK restriction). Documented as assumption B-04. | Documented |
| F-04 | Minor | inventory | D (docs) | Template inventory had incorrect VC counts across 4 templates (wide_arithmetic, scope_dealloc, channel_fifo, index_safety). Fixed in this audit. | Fixed |
| F-05 | Minor | gnatprove_profile | D (docs) | Line 33 described Prove package as `--warnings=on` without noting CI override to `--warnings=error`. Fixed. | Fixed |

**Severity summary:** 0 blocking, 0 major, 2 minor (fixed), 3 advisory (accepted/documented).

---

## 7. Verification

```
GNATprove run: 184/184 VCs proved, 0 unproved, 1 justified (A-05).
Max steps: 2.
Provers: CVC5 99%, Trivial 1%.
All 3 target templates: PASS.
prove_golden.txt: matches GNATprove output.
```

---

## 8. Conclusion

**Phase 1 audit result: PASS**

All three high-priority templates pass the spot-check deep-dive across all three review dimensions:

- **Contract-level review (A):** All PO hook calls satisfy their preconditions at every call site. Pre/Post contracts capture the full behavioral specification. Ghost functions faithfully map implementation state to model types. All clause IDs trace to real Safe spec clauses.

- **Golden file comparison (B):** Templates structurally align with golden outputs. Every assertion in the golden files has a corresponding or stronger contract in the templates. Documented semantic gaps (sequential vs protected, Boolean vs access) are justified and tracked as assumptions.

- **SPARK 2022 compliance (C):** All templates correctly use Ghost aspects, short-circuit contract expressions, loop invariants (where applicable), and `'Old`/`'Result` attributes. No SPARK restriction violations found. `Assertion_Policy(Check)` is consistent.

Documentation drift has been corrected. No blocking or major findings.
