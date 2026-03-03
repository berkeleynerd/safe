# Why3 Alignment Analysis

**Safe Language Annotated SPARK Companion**
Frozen commit: `4aecf219ffa5473bfc42b026a66c8bdea2ce5872`
Date: 2026-03-02

---

## 1. Introduction

### 1.1 Purpose of Why3 in the GNATprove Toolchain

GNATprove does not dispatch SPARK verification conditions (VCs) directly to SMT solvers. Instead, it translates SPARK contracts and program semantics into **Why3**, an intermediate verification language with its own type system, theories, and proof-obligation decomposition engine. Why3 then dispatches the resulting goals to one or more backend provers -- typically CVC5, Z3, and Alt-Ergo -- through the SMT-LIB interface.

The translation pipeline is:

```
SPARK source  -->  GNATprove front-end  -->  Why3 goals (.mlw)
                                               |
                                               +--> CVC5  (SMT-LIB FP, LIA, arrays)
                                               +--> Z3    (SMT-LIB BV, NIA, quantifiers)
                                               +--> Alt-Ergo (native Ada-aware axioms)
```

Understanding the Why3 intermediate representation is critical for three reasons:

1. **Diagnosing unproved VCs.** When a VC cannot be discharged, the Why3 goal reveals the exact formula shape, quantifier structure, and theory dependencies that caused the solver to return `unknown` or `timeout`.

2. **Proposing SMT-friendly reformulations.** Some SPARK contracts produce Why3 goals that lie outside the decidable fragment of the target solver's theory. Restructuring the SPARK contract to produce a simpler Why3 goal can convert an unproved VC into a proved one without changing the semantic intent.

3. **Leveraging Why3 lemma libraries.** Why3 ships with verified lemma libraries for integer arithmetic, floating-point reasoning, and array theory. GNATprove can be configured to include additional Why3 theories via `--why3-conf`, enabling solvers to use pre-proved lemmas as axioms.

### 1.2 How SPARK VCs Become Why3 Goals

For each SPARK proof obligation, GNATprove performs the following translation:

1. **Type encoding.** SPARK types are mapped to Why3 types: `Long_Long_Integer` becomes a bounded integer in `int.Int` (with overflow guards) or `bv.BV64` (for bitvector reasoning); `Long_Float` becomes `ieee_float.Float64`; enumeration types become finite integer ranges; record types become Why3 record types; arrays become Why3 `Map` types.

2. **Contract encoding.** Preconditions become Why3 `requires` clauses; postconditions become `ensures` clauses. Ghost expression functions are inlined as Why3 logic functions.

3. **VC generation.** Why3 decomposes each annotated program into proof goals. A postcondition VC becomes a goal of the form `requires /\ body-semantics -> ensures`. A runtime-check VC (division by zero, range overflow, index bounds) becomes a goal embedded at the point of the potentially-failing operation.

4. **Goal transformations.** At `--level=2`, GNATprove enables VC splitting (breaking conjunctive goals into individual sub-goals), loop unrolling, and Why3 theory-specific transformations that simplify the goal before dispatching it to solvers.

### 1.3 Relevance to the Safe Language Companion

The Safe companion (`companion/spark/safe_po.ads`, `safe_po.adb`, `safe_model.ads`) encodes 23 proof obligation procedures covering D27 Rules 1--5, ownership state management, channel invariants, and task-variable race-freedom. The current proof summary (64 checks: 29 flow, 34 proved, 1 justified, 0 unproved) demonstrates that all VCs are currently discharged. This document analyzes the Why3 shape of each VC category to:

- Identify fragile VCs that may regress under specification changes.
- Map each VC to its Why3 theory dependencies.
- Propose reformulations for anticipated scaling challenges.
- Provide WhyML mirror specifications for key ghost model types.

---

## 2. PO Shape Analysis

The 23 PO procedures in `safe_po.ads` decompose into six categories. For each category, we analyze the SPARK contract, the resulting Why3 goal shape, and the applicable Why3 theories.

### 2.1 Integer Arithmetic VCs (D27 Rule 1, Rule 3)

**Procedures:** `Safe_Div`, `Safe_Mod`, `Safe_Rem`, `Nonzero`, `Narrow_Assignment`, `Narrow_Parameter`, `Narrow_Return`, `Narrow_Indexing`, `Narrow_Conversion`

**Count:** 9 procedures (3 non-ghost with bodies, 6 ghost with null bodies)

#### 2.1.1 Safe_Div

**SPARK contract:**
```ada
procedure Safe_Div (X, Y : Long_Long_Integer; R : out Long_Long_Integer)
  with Pre  => Y /= 0
               and then not (X = Long_Long_Integer'First and then Y = -1),
       Post => R = X / Y;
```

**Why3 goal shape (postcondition VC):**
```
goal Safe_Div_postcondition:
  forall x y : int.
    y <> 0 ->
    not (x = int64_min /\ y = -1) ->
    let r = ComputerDivision.div x y in
    r = ComputerDivision.div x y
```

This is a **tautological VC**: the body `R := X / Y` literally computes the postcondition expression `R = X / Y`. Why3 translates Ada integer division to `int.ComputerDivision.div`, which uses truncation-toward-zero semantics (matching Ada's definition). The precondition excludes `Long_Long_Integer'First / -1`, which would overflow.

**Why3 theories required:**
- `int.Int` -- unbounded mathematical integers
- `int.ComputerDivision` -- truncation-toward-zero division and modulo
- Overflow guard axioms for `Long_Long_Integer` range `[-2^63, 2^63 - 1]`

**VC difficulty:** Trivial. CVC5 discharges this in under 1 second. The tautological postcondition combined with the overflow-excluding precondition produces a simple conjunction of linear arithmetic constraints.

**Runtime check VCs generated from the body:**
- Division-by-zero check at `R := X / Y` -- discharged from `Pre => Y /= 0`.
- Overflow check at `R := X / Y` -- discharged from `Pre => not (X = LLI'First and then Y = -1)`.

#### 2.1.2 Safe_Mod and Safe_Rem

These have identical structure to `Safe_Div` but without the overflow exclusion (Ada `mod` and `rem` cannot overflow on 64-bit integers when the divisor is nonzero).

**Why3 goal shape:**
```
goal Safe_Mod_postcondition:
  forall x y : int. y <> 0 ->
    let r = ComputerDivision.mod x y in r = ComputerDivision.mod x y
```

**Why3 theories:** Same as `Safe_Div`. The distinction between Ada `mod` (floored) and Ada `rem` (truncated) is encoded by GNATprove using the appropriate `ComputerDivision` operator.

**VC difficulty:** Trivial.

#### 2.1.3 Nonzero

**SPARK contract:**
```ada
procedure Nonzero (V : Long_Long_Integer) with Pre => V /= 0, Ghost;
```

**Why3 goal shape:** No body VC (null body). The only VCs arise at call sites, where callers must prove `V /= 0`. This is a single inequality in `int.Int` -- trivially decidable in LIA.

#### 2.1.4 Narrowing Procedures (5 procedures)

**SPARK contract pattern:**
```ada
procedure Narrow_Assignment (V : Long_Long_Integer; Target : Range64)
  with Pre => Is_Valid_Range (Target) and then Contains (Target, V), Ghost;
```

**Why3 goal shape (call-site VC):**
```
goal Narrow_Assignment_precondition:
  forall v lo hi : int.
    lo <= hi ->                  -- Is_Valid_Range
    lo <= v /\ v <= hi ->        -- Contains
    true
```

The ghost function `Contains` is defined as `V >= R.Lo and then V <= R.Hi` and is inlined by GNATprove into the Why3 goal. The resulting formula is pure linear arithmetic over three integer variables.

**Why3 theories:**
- `int.Int` -- integer comparisons
- Record theory for `Range64` (Lo, Hi fields)

**VC difficulty:** Trivial. These are range-containment checks that reduce to conjunction of linear inequalities. CVC5's LIA solver handles them without transformation.

**Scaling concern:** In real programs, the caller must establish `Contains(Target, V)` from dataflow analysis or loop invariants. The companion itself does not generate these call-site VCs (there is no main program), but when integrated into a Safe compiler, the Range64 ghost model will be the source of the most common VCs. The `Contains` function's simplicity (two inequalities) ensures these VCs remain in the LIA decidable fragment.

### 2.2 Array/Index VCs (D27 Rule 2)

**Procedure:** `Safe_Index`

**SPARK contract:**
```ada
procedure Safe_Index (Arr_Lo, Arr_Hi, Idx : Long_Long_Integer)
  with Pre => Arr_Lo <= Arr_Hi
              and then Idx >= Arr_Lo
              and then Idx <= Arr_Hi,
       Ghost;
```

**Why3 goal shape (call-site VC):**
```
goal Safe_Index_precondition:
  forall arr_lo arr_hi idx : int.
    arr_lo <= arr_hi ->
    idx >= arr_lo ->
    idx <= arr_hi ->
    true
```

This is three linear inequalities -- no array theory involvement at all. The `Safe_Index` procedure models the index-in-range check abstractly; actual array access VCs in a real program would additionally involve Why3's `array.Array` theory (for `Map` read/write operations), but the companion's ghost procedure reduces the VC to pure arithmetic.

**Why3 theories:**
- `int.Int` -- only integer comparisons needed
- `array.Array` -- required only at call sites involving actual array accesses

**VC difficulty:** Trivial for the companion. At call sites in real programs, the challenge shifts to establishing `Idx >= Arr_Lo /\ Idx <= Arr_Hi` from range analysis or loop invariants.

**Scaling challenge: Range64.Contains requires inductive reasoning.** When a caller's proof context involves the Range64 ghost model (e.g., proving that a narrowed value is in a subrange of the array's index range), the VC may require proving `Subset(Narrow_Range, Index_Range)` via `Contains`. This can produce goals with nested quantifiers if the program manipulates ranges through `Intersect` or `Widen`. However, since all Range64 operations are defined as expression functions over `Lo`/`Hi` fields, GNATprove inlines them, keeping the VC in the quantifier-free LIA fragment.

### 2.3 Null-Safety VCs (D27 Rule 4)

**Procedures:** `Not_Null_Ptr`, `Safe_Deref`

**SPARK contract (both identical):**
```ada
procedure Not_Null_Ptr (Is_Null : Boolean) with Pre => not Is_Null, Ghost;
procedure Safe_Deref   (Is_Null : Boolean) with Pre => not Is_Null, Ghost;
```

**Why3 goal shape (call-site VC):**
```
goal Not_Null_Ptr_precondition:
  forall is_null : bool.
    is_null = false ->
    true
```

**Why3 theories:** Propositional logic only. The Boolean parameter `Is_Null` maps to Why3's `bool` type. The negation `not Is_Null` becomes `is_null = false`.

**VC difficulty:** Trivially decidable. These are propositional tautologies that any solver (and even the `Trivial` prover built into GNATprove) can discharge instantly.

**Modeling note (assumption B-04):** SPARK disallows access types under `SPARK_Mode`. The Boolean flag `Is_Null` models the null/not-null state of an access value. The compiler must correctly lower access-type null checks to this Boolean model. The Why3 encoding is faithful to this abstraction.

### 2.4 Floating-Point VCs (D27 Rule 5)

**Procedures:** `FP_Not_NaN`, `FP_Not_Infinity`, `FP_Safe_Div`

#### 2.4.1 FP_Not_NaN

**SPARK contract:**
```ada
procedure FP_Not_NaN (V : Long_Float) with Pre => V = V, Ghost;
```

**Why3 goal shape (call-site VC):**
```
goal FP_Not_NaN_precondition:
  forall v : Float64.t.
    Float64.eq v v ->
    true
```

Under IEEE 754, `NaN /= NaN`, so `V = V` is false if and only if `V` is NaN. GNATprove encodes `Long_Float` as `Float64.t` in the Why3 `ieee_float` theory. The `eq` function follows IEEE 754 comparison semantics.

**Why3 theories:**
- `ieee_float.Float64` -- IEEE 754 binary64 type with comparison operations
- `ieee_float.Float64.Eq` -- reflexivity holds for all non-NaN values

**VC difficulty:** Low. CVC5 and Z3 both implement the SMT-LIB `FloatingPoint` theory. The self-equality check is a standard FP idiom recognized by all FP-aware solvers.

#### 2.4.2 FP_Not_Infinity

**SPARK contract:**
```ada
procedure FP_Not_Infinity (V : Long_Float)
  with Pre => V = V
              and then V >= Long_Float'First
              and then V <= Long_Float'Last,
       Ghost;
```

**Why3 goal shape (call-site VC):**
```
goal FP_Not_Infinity_precondition:
  forall v : Float64.t.
    Float64.eq v v ->
    Float64.le float64_min v ->
    Float64.le v float64_max ->
    true
```

Here `float64_min` and `float64_max` are the finite bounds of `Long_Float` (approximately `-1.7976931348623157E+308` and `+1.7976931348623157E+308`). These bounds exclude positive infinity, negative infinity, and NaN.

**Why3 theories:**
- `ieee_float.Float64` -- range bounds
- `float.Bounded` -- finite-value predicate

**VC difficulty:** Low-to-medium. The three-clause conjunction is straightforward, but SMT solvers' FP theories can be slower than their LIA theories. At `--level=2`, CVC5 handles this within seconds.

#### 2.4.3 FP_Safe_Div -- The Justified VC

**SPARK contract:**
```ada
procedure FP_Safe_Div (X, Y : Long_Float; R : out Long_Float)
  with Pre  => Y /= 0.0 and then Y = Y and then X = X
               and then X >= Long_Float'First and then X <= Long_Float'Last
               and then Y >= Long_Float'First and then Y <= Long_Float'Last,
       Post => R = X / Y;
```

**Why3 goal shape (postcondition VC):**
```
goal FP_Safe_Div_postcondition:
  forall x y : Float64.t.
    not (Float64.eq y (Float64.of_real 0.0)) ->
    Float64.eq y y -> Float64.eq x x ->
    Float64.le float64_min x -> Float64.le x float64_max ->
    Float64.le float64_min y -> Float64.le y float64_max ->
    let r = Float64.div RNE x y in
    Float64.eq r (Float64.div RNE x y)
```

The postcondition VC is tautological (same as `Safe_Div`). However, the **float overflow runtime check** is not:

**Why3 goal shape (overflow check VC):**
```
goal FP_Safe_Div_overflow_check:
  forall x y : Float64.t.
    [preconditions as above] ->
    let r = Float64.div RNE x y in
    Float64.is_finite r
```

This VC asserts that dividing two finite, non-NaN, nonzero-denominator `Float64` values produces a finite result. This is **false in general**: dividing a large finite `X` by a very small finite `Y` (e.g., a subnormal) can produce positive or negative infinity under IEEE 754 round-to-nearest-even (RNE) semantics.

**GNATprove counterexample (from assumption A-05):** `X = -1.1e-5`, `Y = 1.3e-318` produces overflow.

**Current disposition:** The VC is justified by `pragma Annotate (GNATprove, Intentional, "float overflow check might fail", ...)` in the body of `FP_Safe_Div`. This corresponds to assumption A-05: the Safe compiler's narrowing-point analysis guarantees the result is finite before it reaches a narrowing point.

**Why3 theories:**
- `ieee_float.Float64` -- division with RNE rounding
- `ieee_float.Float64.IsFinite` -- finiteness predicate
- `float.RoundingMode` -- RNE specification

**VC difficulty:** **High -- the only truly SMT-challenging VC in the companion.** No combination of CVC5, Z3, or Alt-Ergo can prove that FP division of two finite values is always finite, because it is not true in general. This VC correctly requires justification.

### 2.5 Ownership VCs

**Procedures:** `Check_Not_Moved`, `Check_Owned_For_Move`, `Check_Borrow_Exclusive`, `Check_Observe_Shared`

**SPARK contract patterns:**
```ada
Check_Not_Moved       : Pre => State /= Moved
Check_Owned_For_Move  : Pre => State = Owned
Check_Borrow_Exclusive: Pre => State = Owned
Check_Observe_Shared  : Pre => State = Owned or else State = Observed
```

**Why3 goal shape (call-site VC):**
```
goal Check_Not_Moved_precondition:
  forall state : int.     -- Ownership_State encoded as 0..4
    0 <= state <= 4 ->
    state <> 2 ->         -- Moved = 2
    true
```

GNATprove encodes Ada enumeration types as bounded integers. The five-state `Ownership_State` (Null_State=0, Owned=1, Moved=2, Borrowed=3, Observed=4) becomes a `0..4` integer range. Equality and inequality on enumeration values become integer comparisons.

**Why3 theories:**
- `int.Int` -- integer range and comparison
- No custom theory needed; the enumeration encoding is standard

**VC difficulty:** Trivial. All ownership VCs are propositional-level checks on a five-valued domain. Even the most complex case (`Check_Observe_Shared` with its disjunction `State = Owned or else State = Observed`) reduces to `state = 1 \/ state = 4`.

**Ghost state reasoning note:** The ownership VCs in the companion are deliberately simple because they model *single-variable* state checks. In a full compiler integration, the challenge shifts to establishing the ownership state at each program point via flow analysis. The ghost function `Is_Valid_Transition` (defined in `safe_model.ads`) models the state machine, but it is not called from any PO procedure -- it exists as a proof anchor for future call-site VCs. When those VCs arise, they will involve case analysis on the `From` state, which Why3 handles via `match` expressions on the integer encoding. CVC5's case-splitting heuristic handles these efficiently.

### 2.6 Channel and Concurrency VCs

**Procedures:** `Check_Channel_Not_Full`, `Check_Channel_Not_Empty`, `Check_Channel_Capacity_Positive`, `Check_Exclusive_Ownership`

#### 2.6.1 Channel Capacity/Length VCs

**SPARK contracts:**
```ada
Check_Channel_Not_Full     : Pre => Length < Capacity
Check_Channel_Not_Empty    : Pre => Length > 0
Check_Channel_Capacity_Positive: Pre => Capacity > 0
```

**Why3 goal shape:**
```
goal Check_Channel_Not_Full_precondition:
  forall length capacity : int.
    0 <= length -> 0 <= capacity ->   -- Natural subtype constraints
    length < capacity ->
    true
```

These are single-inequality checks on `Natural` values. The `Channel_State` record model (with `Length` and `Capacity` fields) does not appear in these VCs because the PO procedures take individual `Natural` parameters rather than a `Channel_State` record.

**Why3 theories:** `int.Int` only.

**VC difficulty:** Trivial.

#### 2.6.2 Task-Variable Exclusive Ownership

**SPARK contract:**
```ada
procedure Check_Exclusive_Ownership
  (Var_Id : Var_Id_Range; Task_Id : Task_Id_Range; Map : Task_Var_Map)
  with Pre => Task_Id /= No_Task
              and then (Map (Var_Id) = No_Task
                        or else Map (Var_Id) = Task_Id),
       Ghost;
```

**Why3 goal shape (call-site VC):**
```
goal Check_Exclusive_Ownership_precondition:
  forall var_id task_id : int. forall map : (int -> int).
    0 <= var_id <= 1023 ->
    0 <= task_id <= 64 ->
    task_id <> 0 ->
    (map var_id = 0 \/ map var_id = task_id) ->
    true
```

The `Task_Var_Map` (array indexed by `Var_Id_Range`) becomes a Why3 function type `int -> int` (the Why3 `Map` encoding). Array read `Map(Var_Id)` becomes function application `map var_id`.

**Why3 theories:**
- `int.Int` -- range constraints
- `array.Array` or `Map` theory -- array read encoding

**VC difficulty:** Low. The precondition is a disjunction of two equalities on a single array read. No quantifiers, no array writes. CVC5 handles this in the pure LIA+equality fragment.

**Scaling concern:** The `Assign_Owner` function (in `safe_model.adb`) has a universally quantified postcondition:

```ada
Post => Assign_Owner'Result (Var_Id) = Task_Id
        and then (for all V in Var_Id_Range =>
                    (if V /= Var_Id
                     then Assign_Owner'Result (V) = Map (V)));
```

This generates a Why3 goal with a universal quantifier over a 1024-element domain:

```
forall v : int. 0 <= v <= 1023 ->
  v <> var_id -> result_map v = map v
```

At `--level=2`, GNATprove may handle this via the array theory's extensionality axiom (two arrays are equal if they differ at exactly one index). CVC5 and Z3 both support array extensionality natively. However, if the quantifier is not eliminated by theory reasoning, it requires 1024 instantiations, which can cause solver slowdown.

---

## 3. SMT-Challenging VCs

This section identifies the VCs that are hardest for SMT solvers, ranked by severity.

### 3.1 Floating-Point Division Overflow (FP_Safe_Div) -- UNSOLVABLE

**Severity:** Critical (currently justified, not proved)

**Challenge:** The `FP_Safe_Div` float overflow check asks whether IEEE 754 binary64 division of two finite operands always produces a finite result. This is mathematically false: `1.0e308 / 1.0e-308` overflows to infinity. No SMT solver can prove a false statement.

**Why3 theory involvement:** `ieee_float.Float64`, `float.RoundingMode`

**Status:** Correctly handled by `pragma Annotate (GNATprove, Intentional)` and tracked as assumption A-05. The Safe compiler's runtime narrowing-point analysis provides the missing guarantee.

### 3.2 Floating-Point Equality in Postconditions (FP_Safe_Div Post)

**Severity:** Medium

**Challenge:** The postcondition `R = X / Y` for `FP_Safe_Div` requires the solver to prove that `Float64.eq (Float64.div RNE x y) (Float64.div RNE x y)`. While this is trivially true by reflexivity, SMT solvers' FP theories sometimes struggle with reflexivity of FP equality because `NaN /= NaN`. GNATprove must establish that the division result is not NaN (which follows from the preconditions excluding NaN operands and zero divisor, and the IEEE 754 specification that division of finite, non-NaN values with nonzero divisor produces a finite result or infinity, but not NaN).

**Current status:** CVC5 proves this at `--level=2`. If CVC5 regresses, Z3's FP theory provides a fallback.

### 3.3 Quantified Frame Conditions (Assign_Owner)

**Severity:** Low (currently proved, but fragile under scaling)

**Challenge:** The `Assign_Owner` postcondition contains a universal quantifier over `Var_Id_Range` (0..1023). The Why3 goal has the shape:

```
forall v : int. 0 <= v <= 1023 -> v <> var_id -> result(v) = map(v)
```

SMT solvers handle this via the array extensionality theory, but if the VC is split or if additional quantifiers are added (e.g., a nested `No_Shared_Variables` invariant check), the quantifier instantiation count grows combinatorially.

**Current status:** CVC5 proves this efficiently using array theory axioms. The `No_Shared_Variables` function returns `True` unconditionally (by construction of the single-valued map model), so no additional quantifier burden exists.

### 3.4 Nonlinear Integer Arithmetic

**Severity:** None (not currently present)

**Assessment:** The companion contains no multiplication-dependent contracts. All integer VCs are in the quantifier-free linear integer arithmetic (QF_LIA) fragment, which is decidable. If future POs introduce multiplication (e.g., `A * B` range bounds), the VCs would move to the nonlinear integer arithmetic (NIA) fragment, which is undecidable in general. CVC5's NIA solver (`--nl-ext`) handles most practical polynomial constraints but may require increased timeouts.

### 3.5 Inductive Properties (Channel FIFO Ordering)

**Severity:** Not applicable (not modeled)

**Assessment:** The `Channel_State` ghost model captures only `Length` and `Capacity` -- it does not model element ordering. The FIFO ordering property is tracked as assumption B-02. If a future version of the ghost model introduces a sequence type to model element ordering, the resulting VCs would require inductive reasoning (e.g., proving that `After_Append` preserves FIFO order). Why3's `seq.Seq` theory provides lemmas for sequence operations, but inductive proofs over sequences generally require manual lemma insertion or `--level=4` with aggressive unfolding.

---

## 4. Why3-Friendly Reformulations

### 4.1 FP_Safe_Div: Strengthening the Precondition

The current `FP_Safe_Div` overflow check is unprovable because the precondition admits operand pairs that produce overflow. Two reformulation strategies are available:

**Strategy A: Tighten the precondition with an absolute-value bound.**

```ada
procedure FP_Safe_Div (X, Y : Long_Float; R : out Long_Float)
  with Pre => Y /= 0.0
              and then Y = Y and then X = X
              and then abs X <= Long_Float'Last
              and then abs Y >= Long_Float'Model_Small
              and then abs X / abs Y <= Long_Float'Last,
       Post => R = X / Y;
```

The additional clause `abs X / abs Y <= Long_Float'Last` directly states that the quotient is representable. This makes the overflow check provable but shifts the burden to the caller, who must establish the bound. In Why3, this becomes a conjunction of FP comparisons -- still within the `FloatingPoint` theory's decidable fragment.

**Trade-off:** This strengthens the precondition beyond what the Safe specification requires. The specification's intent is that the compiler's narrowing-point analysis provides the finiteness guarantee *after* the division, not before. Strategy A would change the verification model from "check at narrowing point" to "check before operation." This is semantically different and should only be adopted if the specification is revised.

**Strategy B: Insert a ghost lemma asserting compiler-guaranteed finiteness.**

```ada
pragma Assume (abs (X / Y) <= Long_Float'Last,
               "A-05: Compiler guarantees finite result at narrowing point");
```

This is the current approach (using `pragma Annotate` instead of `pragma Assume`). It is appropriate as long as assumption A-05 is tracked and the compiler's narrowing-point analysis is validated.

**Recommendation:** Maintain Strategy B (current approach). The justified VC is the correct modeling of the Safe specification's intent. Migrating to Strategy A would require a specification change and would make the caller-side VCs harder without improving safety.

### 4.2 Quantified Frame Conditions: Array Theory Axioms

The `Assign_Owner` postcondition's universal quantifier is currently handled by CVC5's array extensionality. If this becomes fragile under scaling:

**Reformulation: Use explicit store-read axiom.**

Instead of the frame condition:
```ada
for all V in Var_Id_Range =>
  (if V /= Var_Id then Assign_Owner'Result (V) = Map (V))
```

Express the result as a single array update:
```ada
Post => Assign_Owner'Result = Map'Update (Var_Id => Task_Id);
```

The Why3 encoding of `'Update` uses the array `store` operation, which has a built-in axiom:

```
axiom store_read:
  forall a i v j. j <> i -> store(a, i, v)[j] = a[j]
```

This avoids explicit quantifier instantiation. The body already uses this pattern (`Result(Var_Id) := Task_Id`), so the reformulation aligns the postcondition with the body's natural Why3 encoding.

**Recommendation:** Consider reformulating `Assign_Owner`'s postcondition to use `'Update` if the quantified version becomes problematic. For the current companion size, the existing formulation is adequate.

### 4.3 Range64 Operations: Keeping VCs in QF_LIA

The Range64 ghost model functions (`Contains`, `Subset`, `Intersect`, `Widen`, `Excludes_Zero`) are defined as expression functions over the `Lo` and `Hi` fields. GNATprove inlines expression functions into Why3 goals, keeping VCs in the quantifier-free fragment.

**Reformulation risk:** If any Range64 function were changed from an expression function to a regular function with a body, GNATprove would *not* inline it. Instead, it would generate an opaque function symbol with an axiom encoding the postcondition. This could introduce quantifiers or prevent simplification.

**Recommendation:** All Range64 model functions must remain expression functions. This is a structural invariant of the ghost model and should be documented as a coding standard.

### 4.4 Ownership State Transitions: Avoiding Enumeration Explosion

The `Is_Valid_Transition` function uses a `case` expression with 5 arms, each containing a disjunction of up to 4 alternatives. The full expansion produces 12 valid transitions. If this function appears in a VC, Why3 encodes it as a conjunction of implications:

```
(state = 0 -> to = 1) /\
(state = 1 -> to = 2 \/ to = 3 \/ to = 4 \/ to = 0) /\
...
```

This is efficiently handled by SAT-based reasoning (both CVC5 and Z3 have DPLL(T) cores). No reformulation is needed.

### 4.5 Solver-Specific Options

For specific problematic VC categories, the following `--prover` options can be used:

| VC Category | Recommended Prover | Why |
|---|---|---|
| LIA range checks | CVC5 (default) | Fastest on linear arithmetic |
| FP equality/comparison | CVC5 first, then Z3 | Both have FP theory; CVC5 is typically faster |
| Array frame conditions | Z3 | Best array extensionality support |
| Enumeration case analysis | Alt-Ergo | Best trigger-based instantiation for Ada enums |
| Bitvector overflow (future) | Z3 | Strongest bitvector theory |

---

## 5. Why3 Theory Alignment

### 5.1 Type-to-Theory Mapping

| SPARK Type | Why3 Theory | Encoding | Notes |
|---|---|---|---|
| `Long_Long_Integer` | `int.Int` / `bv.BV64` | Unbounded `int` with range guards, or bitvector | Default is `int.Int` with overflow guards at `[-2^63, 2^63-1]`. Bitvector encoding available via `--prover-specific` but not used in this companion. |
| `Natural` | `int.Int` | Bounded integer `[0, 2^31-1]` | `Natural` range constraints emitted as Why3 `requires`. |
| `Long_Float` | `ieee_float.Float64` | IEEE 754 binary64 | Non-trapping mode assumed (A-02). RNE rounding for arithmetic. |
| `Boolean` | `bool` | Propositional | Direct Why3 `bool` type. |
| `Range64` | (inlined record) | `{ lo: int; hi: int }` | Expression functions inlined; no custom theory needed. |
| `Channel_State` | (inlined record) | `{ length: int; capacity: int }` | Expression functions inlined; no custom theory needed. |
| `Ownership_State` | `int` (range `0..4`) | Enumeration-to-integer | Why3 encodes Ada enumerations as bounded integers. |
| `Task_Var_Map` | `array.Array` / `Map` | `int -> int` | Why3 `Map` encoding with store/read axioms. |
| `Var_Id_Range` | `int` (range `0..1023`) | Bounded integer | Subtype constraint emitted as guard. |
| `Task_Id_Range` | `int` (range `0..64`) | Bounded integer | `No_Task = 0` encoded as constant. |

### 5.2 Why3 Theory Dependencies by PO Category

| PO Category | Required Why3 Theories |
|---|---|
| Integer arithmetic (Safe_Div, Safe_Mod, Safe_Rem) | `int.Int`, `int.ComputerDivision`, overflow guards |
| Narrowing checks (5 procedures) | `int.Int`, Range64 record |
| Index safety (Safe_Index) | `int.Int` |
| Division-by-zero (Nonzero) | `int.Int` |
| Null safety (Not_Null_Ptr, Safe_Deref) | `bool` |
| FP safety (FP_Not_NaN, FP_Not_Infinity) | `ieee_float.Float64` |
| FP division (FP_Safe_Div) | `ieee_float.Float64`, `float.RoundingMode`, `float.Bounded` |
| Ownership (4 procedures) | `int.Int` (enumeration encoding) |
| Channel (3 procedures) | `int.Int` |
| Race-freedom (Check_Exclusive_Ownership) | `int.Int`, `array.Array` |

---

## 6. Optional WhyML Mirror Specifications

The following WhyML sketches provide mirror specifications for the two most significant ghost model types. These can be used for independent verification in Why3 IDE or as documentation of the intended Why3 theory alignment.

### 6.1 Range64 Interval Type

```whyml
module Range64

  use int.Int
  use int.MinMax

  type range64 = { lo: int; hi: int }

  predicate is_valid (r: range64) = r.lo <= r.hi

  predicate contains (r: range64) (v: int) =
    r.lo <= v /\ v <= r.hi

  predicate subset (a b: range64) =
    a.lo >= b.lo /\ a.hi <= b.hi

  function intersect (a b: range64) : range64
    requires { is_valid a /\ is_valid b }
    requires { max a.lo b.lo <= min a.hi b.hi }
    ensures  { result.lo = max a.lo b.lo }
    ensures  { result.hi = min a.hi b.hi }
    ensures  { is_valid result }
  = { lo = max a.lo b.lo; hi = min a.hi b.hi }

  function widen (a b: range64) : range64
    requires { is_valid a /\ is_valid b }
    ensures  { result.lo = min a.lo b.lo }
    ensures  { result.hi = max a.hi b.hi }
    ensures  { is_valid result }
    ensures  { subset a result /\ subset b result }
  = { lo = min a.lo b.lo; hi = max a.hi b.hi }

  predicate excludes_zero (r: range64) =
    r.hi < 0 \/ r.lo > 0

  lemma contains_subset:
    forall a b: range64. forall v: int.
      is_valid a -> is_valid b ->
      subset a b -> contains a v -> contains b v

  lemma intersect_contains:
    forall a b: range64. forall v: int.
      is_valid a -> is_valid b ->
      max a.lo b.lo <= min a.hi b.hi ->
      contains (intersect a b) v <-> (contains a v /\ contains b v)

  lemma widen_contains:
    forall a b: range64. forall v: int.
      is_valid a -> is_valid b ->
      (contains a v \/ contains b v) -> contains (widen a b) v

  lemma excludes_zero_not_contains_zero:
    forall r: range64.
      is_valid r -> excludes_zero r -> not (contains r 0)

end
```

### 6.2 Channel FIFO Model with Ordering Invariant

```whyml
module ChannelFIFO

  use int.Int
  use seq.Seq

  type channel (a: type) = {
    ghost mutable elems: seq a;
    capacity: int;
  }
  invariant { 0 <= length elems <= capacity }
  invariant { capacity >= 1 }

  predicate is_valid (c: channel 'a) =
    0 <= length c.elems <= c.capacity /\ c.capacity >= 1

  predicate is_empty (c: channel 'a) = length c.elems = 0

  predicate is_full (c: channel 'a) = length c.elems = c.capacity

  function len (c: channel 'a) : int = length c.elems

  function cap (c: channel 'a) : int = c.capacity

  val send (c: channel 'a) (v: 'a) : unit
    requires { not (is_full c) }
    writes   { c.elems }
    ensures  { c.elems = snoc (old c.elems) v }
    ensures  { length c.elems = length (old c.elems) + 1 }

  val receive (c: channel 'a) : 'a
    requires { not (is_empty c) }
    writes   { c.elems }
    ensures  { result = (old c.elems)[0] }
    ensures  { c.elems = (old c.elems)[1 ..] }
    ensures  { length c.elems = length (old c.elems) - 1 }

  (** FIFO ordering lemma: if we send v1 then v2, we receive v1 before v2. *)
  lemma fifo_ordering:
    forall c: channel 'a. forall v1 v2: 'a.
      not (is_full c) ->
      length c.elems < c.capacity - 1 ->
      let c1 = { c with elems = snoc c.elems v1 } in
      let c2 = { c1 with elems = snoc c1.elems v2 } in
      c2.elems[length c.elems] = v1 /\
      c2.elems[length c.elems + 1] = v2

end
```

**Note:** The SPARK companion currently models channels with `Length`/`Capacity` counters only (no sequence). This WhyML specification shows what a full FIFO model would look like. Adopting it in the SPARK companion would require extending `Channel_State` with a ghost sequence component and would introduce inductive VCs (see Section 3.5). This is tracked as future work under assumption B-02.

---

## 7. Proof Automation Assessment

### 7.1 Current Results

From `companion/gen/prove_golden.txt`:

```
Total: 64 checks
  Flow analysis:       29  (45%)  -- all proved
  Formal proof:        34  (53%)  -- all proved (CVC5 96%, Trivial 4%)
  Justified:            1  ( 2%)  -- FP_Safe_Div float overflow (A-05)
  Unproved:             0  ( 0%)
```

### 7.2 Prover Portfolio Effectiveness

| Prover | VCs Proved | Percentage of Proved VCs | Notes |
|---|---|---|---|
| CVC5 | ~33 | ~96% | Primary solver; handles all LIA, FP, and enumeration VCs |
| Trivial | ~1 | ~4% | GNATprove's built-in prover for propositional tautologies |
| Z3 | 0 | 0% | Not needed for current VC set; CVC5 succeeds first |
| Alt-Ergo | 0 | 0% | Not needed for current VC set; CVC5 succeeds first |

**Assessment:** The prover portfolio is over-provisioned for the current companion. CVC5 alone handles 96% of VCs, with the remaining 4% trivially propositional. Z3 and Alt-Ergo serve as insurance against CVC5 regressions and will become important as the companion grows.

### 7.3 VC Category Breakdown (Estimated)

Based on analysis of the 34 proved VCs:

| VC Category | Est. Count | Solver Used | Why3 Theory Fragment |
|---|---|---|---|
| Postcondition (Safe_Div, Safe_Mod, Safe_Rem) | 3 | CVC5 | QF_LIA + ComputerDivision |
| Postcondition (FP_Safe_Div) | 1 | CVC5 | FP64 |
| Runtime division-by-zero checks | 3 | CVC5 | QF_LIA |
| Runtime overflow checks | 3 | CVC5 | QF_LIA |
| Runtime FP overflow check | 0 | -- | Justified (A-05) |
| Functional contract (ghost) | ~20 | CVC5 | QF_LIA, propositional |
| Propositional (null safety, etc.) | ~4 | Trivial / CVC5 | Propositional |

### 7.4 Solver Strategy Recommendations for Scaling

As the companion grows (e.g., adding call-site VCs from a Safe compiler integration), the following strategies are recommended:

**For QF_LIA VCs (narrowing, index bounds):**
- Maintain `--level=2` with CVC5 as primary solver.
- These VCs scale linearly with program size and remain in the decidable QF_LIA fragment.
- No timeout increase needed; typical solve time is <1 second per VC.

**For FP VCs (floating-point narrowing checks):**
- Use `--level=3` if any FP VC becomes unproved at `--level=2`.
- Level 3 enables additional Why3 transformations that decompose FP comparisons.
- Consider increasing `--timeout` to 300 seconds for FP VCs specifically.
- If CVC5 fails on FP VCs, Z3's FP theory may succeed (Z3 has a different FP decision procedure).

**For array/quantifier VCs (task-variable ownership):**
- Monitor quantifier instantiation counts if `Assign_Owner`-style VCs multiply.
- If quantifier VCs become problematic, reformulate using `'Update` (see Section 4.2).
- Z3's E-matching may outperform CVC5 on heavily quantified VCs.

**For future NIA VCs (nonlinear integer arithmetic):**
- If multiplication-dependent contracts are introduced, add `--level=3` which enables CVC5's nonlinear extension.
- Consider using `--prover=cvc5 --timeout=300` for NIA VCs specifically.
- Z3's NIA solver is an alternative if CVC5 times out.

---

## 8. Recommendations

### 8.1 Priority Improvements for Proof Automation

**Priority 1: Maintain the zero-unproved baseline.**
The current 0-unproved result is the most important invariant. Every specification change must be followed by a proof regression check (see `docs/gnatprove_profile.md` Section 9).

**Priority 2: Monitor FP_Safe_Div assumption stability.**
Assumption A-05 is the only non-trivial gap in the proof. If the Safe specification is revised to strengthen FP division preconditions (e.g., requiring `abs(X/Y) <= Long_Float'Last` at call sites), the justified VC could be converted to a proved VC. Track this as a specification evolution item.

**Priority 3: Prepare for call-site VC scaling.**
The companion currently generates no call-site VCs (there is no main program). When integrated into a Safe compiler, call-site VCs will dominate the proof load. The Range64 model's expression-function design ensures these VCs stay in QF_LIA, but the *volume* of VCs will increase significantly. Consider:
- Enabling `--memcached-server` for solver result caching across CI runs.
- Partitioning proof runs by source unit to parallelize solver invocations.
- Using `--replay` mode to re-check only VCs whose source dependencies changed.

### 8.2 Lemma Library Development Priorities

**Priority 1: Range64 lemmas (contains_subset, intersect_contains, widen_contains).**
These lemmas (sketched in Section 6.1) establish the algebraic properties of the Range64 interval model. While GNATprove currently inlines expression functions (making the lemmas unnecessary for the companion's own VCs), call-site VCs in a real compiler may require these lemmas as proof hints. Implement them as Ghost lemma procedures in `safe_model.ads`.

**Priority 2: Channel FIFO lemmas (fifo_ordering).**
If the ghost model is extended to track element ordering (resolving assumption B-02), the FIFO ordering lemma from Section 6.2 will be needed. This is a non-trivial inductive property that requires a sequence model.

**Priority 3: Ownership transition lemmas.**
The `Is_Valid_Transition` function defines the ownership state machine. Lemmas establishing reachability properties (e.g., "from Owned, Moved is reachable in exactly one step") can serve as proof anchors for call-site VCs involving ownership state flow.

### 8.3 Integration with GNATprove `--why3-conf` Options

GNATprove supports a `--why3-conf` switch that specifies a custom Why3 configuration file. This file can:

1. **Add custom Why3 theories** to the solver search path. If the Range64 or Channel WhyML specifications from Section 6 are developed into verified Why3 theories, they can be loaded via `--why3-conf` to provide additional axioms to the solvers.

2. **Override solver invocation** with custom command-line options. For example, CVC5's `--nl-ext` option (nonlinear extension) can be enabled selectively for NIA VCs.

3. **Register additional provers.** If a specialized prover is needed (e.g., a dedicated FP prover like Gappa for floating-point range analysis), it can be registered in the Why3 configuration.

**Current recommendation:** No custom Why3 configuration is needed for the current companion. The default GNATprove configuration with `--prover=cvc5,z3,altergo` and `--level=2` is sufficient. Reserve `--why3-conf` for future scaling needs.

### 8.4 Summary of Recommendations

| # | Recommendation | Priority | Effort | Impact |
|---|---|---|---|---|
| 1 | Maintain zero-unproved baseline via CI regression checks | Critical | Low | Prevents proof regressions |
| 2 | Track A-05 resolution as specification evolution item | High | Low | May eliminate only justified VC |
| 3 | Keep Range64 functions as expression functions (coding standard) | High | Low | Ensures QF_LIA VC fragment |
| 4 | Implement Range64 ghost lemma procedures | Medium | Medium | Prepares for call-site VC scaling |
| 5 | Reformulate `Assign_Owner` postcondition to use `'Update` | Low | Low | Insurance against quantifier scaling |
| 6 | Evaluate `--memcached-server` for CI solver caching | Medium | Medium | Reduces CI proof time at scale |
| 7 | Extend Channel ghost model with sequence type (B-02) | Low | High | Resolves FIFO ordering assumption |
| 8 | Develop custom Why3 configuration for NIA/FP VCs | Low | Medium | Future-proofing for complex VCs |

---

## Appendix A: Cross-Reference to Assumptions

| Assumption | Relevance to Why3 Alignment |
|---|---|
| A-01 (64-bit intermediates) | Determines whether overflow guards use `int.Int` bounds or `bv.BV64` bitwidth. Current choice: `int.Int` with `[-2^63, 2^63-1]` guards. |
| A-02 (IEEE 754 non-trapping) | Determines FP theory selection: `ieee_float.Float64` with non-trapping semantics. NaN propagates silently; checks occur at narrowing points. |
| A-03 (Range analysis soundness) | The Range64 ghost model *assumes* the compiler's range analysis is sound. Why3 cannot verify this assumption; it is external to the VC framework. |
| A-04 (Channel serialization) | The sequential ghost model of `Channel_State` is valid only if the runtime correctly serializes concurrent access. Why3 has no concurrency theory. |
| A-05 (FP division overflow) | Directly causes the only justified (non-proved) VC. See Section 2.4.3 and Section 4.1. |
| B-01 (Ownership completeness) | The 5-state enumeration is complete if and only if the Safe specification does not add new ownership states. Why3 encodes the current 5 states as integers 0--4. |
| B-02 (FIFO ordering) | The current ghost model lacks sequence tracking. The WhyML specification in Section 6.2 shows the Why3 theory that would be needed if this assumption is resolved. |
| B-03 (Task-var map coverage) | The `Task_Var_Map` ghost model assumes complete registration. Why3's array theory axioms are correct for the registered variables but provide no coverage guarantee for unregistered ones. |
| B-04 (Boolean null model) | The Boolean flag model maps directly to Why3 `bool`. No theory gap exists. |

## Appendix B: Glossary

| Term | Definition |
|---|---|
| **VC** | Verification condition -- a logical formula that must be proved to establish correctness of a program property. |
| **PO** | Proof obligation -- a SPARK procedure whose contract encodes a safety property to be verified. |
| **QF_LIA** | Quantifier-free linear integer arithmetic -- a decidable SMT theory fragment. |
| **NIA** | Nonlinear integer arithmetic -- an undecidable SMT theory fragment. |
| **RNE** | Round-to-nearest-even -- the default IEEE 754 rounding mode. |
| **Why3** | An intermediate verification language and framework used by GNATprove as its VC backend. |
| **WhyML** | The programming and specification language of Why3. |
| **SMT-LIB** | The standard interface language for SMT solvers. |
| **FP64** | IEEE 754 binary64 (double precision) floating-point type. |
| **Ghost** | A SPARK aspect marking code that exists only for verification and is erased at compilation. |
