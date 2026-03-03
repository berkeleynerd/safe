# Mechanized Proof Scope

**Safe Language Annotated SPARK Companion**
Frozen spec commit: `4aecf219ffa5473bfc42b026a66c8bdea2ce5872`
Date: 2026-03-02

---

## 1. Introduction

### 1.1 Motivation

The SPARK companion verifies proof obligations derived from the Safe specification using GNATprove with CVC5, Z3, and Alt-Ergo as backend SMT solvers. At the current Silver gate (spec commit `4aecf21`), the companion achieves 64 total checks: 29 flow, 34 proved by CVC5, 1 justified (FP_Safe_Div float overflow, assumption A-05), and 0 unproved. This is a strong result for absence-of-runtime-errors (AoRTE) verification.

However, the SPARK companion operates at the level of individual procedure contracts. It verifies that each PO procedure's preconditions and postconditions are internally consistent and that the bodies satisfy their contracts. It does not -- and by design cannot -- verify certain deeper properties:

1. **Soundness of the models themselves.** The ghost models in `safe_model.ads` (Range64 interval arithmetic, Ownership_State transitions, Channel_State capacity tracking, Task_Var_Map exclusive ownership) are assumed to faithfully represent the Safe language semantics. GNATprove verifies contracts *within* these models but does not verify that the models correctly capture the specification's intent.

2. **Properties that span the entire language semantics.** The claim that "all integer arithmetic in Safe evaluates via 64-bit intermediates with overflow caught at narrowing points" is a statement about the language's evaluation semantics, not about any single procedure. SMT solvers reason about quantifier-free formulas over fixed theories; they do not reason about inductively-defined languages.

3. **Assumptions that are inherently outside SPARK's scope.** The companion tracks 13 assumptions in `assumptions.yaml`, of which 4 are critical and 4 are major. Some of these (notably A-03, B-01, B-02) could in principle be discharged by formal proof, but the proofs require induction over data structures or state machines that SMT solvers do not handle well.

Mechanized proof in Coq or Isabelle/HOL provides a complementary verification layer. A mechanized proof is a machine-checked mathematical argument whose correctness depends only on the proof assistant's trusted kernel (a small, audited piece of software), not on the heuristics of SMT solvers. Where SPARK gives confidence that specific runtime checks cannot fail, mechanized proofs give confidence that the underlying models are sound.

### 1.2 Complementary Role

The relationship between SPARK verification and mechanized proof is strictly complementary, not redundant:

| Layer | Tool | What It Verifies |
|-------|------|-----------------|
| Runtime error absence | GNATprove + CVC5/Z3/Alt-Ergo | Individual PO preconditions and postconditions hold; no runtime check failure in the companion code |
| Model soundness | Coq or Isabelle/HOL | The ghost models faithfully encode the Safe language semantics; key language-level invariants hold by construction |
| Assumption discharge | Coq or Isabelle/HOL | Tracked assumptions (A-03, B-01, B-02) can be converted from "open" to "mechanically verified" |

Neither layer subsumes the other. GNATprove operates on Ada/SPARK source and reasons about the actual compiled artifact. Mechanized proofs operate on mathematical models and reason about semantic properties. Together they close the assurance gap.

### 1.3 Scope Boundaries

**In scope for mechanized proofs:**

- Soundness of the Range64 interval arithmetic model and the narrowing-point insertion algorithm (D27 Rule 1)
- Completeness and safety of the Ownership_State transition system (no double ownership, borrow exclusivity, observe sharing)
- FIFO preservation for the channel model (extending the current length/capacity ghost model with a sequence type)
- Discharge of specific tracked assumptions (A-03, B-01, B-02)

**Out of scope for mechanized proofs (covered by SPARK):**

- Individual PO procedure contract satisfaction (already proved by CVC5)
- Flow analysis: initialization, data dependencies, termination (Bronze gate, 29/29 proved)
- Division safety (D27 Rule 3): simple arithmetic preconditions, fully discharged by CVC5
- Null safety (D27 Rule 4): trivial propositional reasoning on Boolean flags
- Floating-point safety (D27 Rule 5): depends on IEEE 754 hardware semantics (assumption A-02), not amenable to pure logical formalization without a validated FP model

---

## 2. Priority Theorems

### 2.1 Priority 1: D27 Rule 1 Soundness (Wide Arithmetic)

**Property.** All integer arithmetic in Safe evaluates via 64-bit signed intermediates. Range checks occur only at the five categories of narrowing point (assignment, parameter passing, return, type conversion, type annotation). If the compiler's static range analysis computes a conservative bound for every subexpression and verifies containment at every narrowing point, then no integer overflow reaches a program variable.

**Spec reference.** Section 2.8.1, paragraphs 126--130 (`spec/02-restrictions.md`).
Canonical clause IDs: `SAFE@4aecf21:spec/02-restrictions.md#2.8.1.p126:812b54a8` through `#2.8.1.p130:2289e5b2`.

**Companion anchor.** `safe_model.ads` Part 1 (Range64, Contains, Subset, Intersect, Widen, Excludes_Zero); `safe_po.ads` procedures Narrow_Assignment, Narrow_Parameter, Narrow_Return, Narrow_Indexing, Narrow_Conversion.

#### Formalization Approach

1. **Define Safe integer expressions as an inductive type.** The expression language includes literals, variables, binary operations (+, -, *, /, mod, rem), unary negation, and narrowing annotations. Each variable and narrowing annotation carries a Range64 constraint.

   ```
   Inductive safe_expr :=
   | Lit   : Z -> safe_expr
   | Var   : var_id -> Range64 -> safe_expr
   | BinOp : binop -> safe_expr -> safe_expr -> safe_expr
   | UnNeg : safe_expr -> safe_expr
   | Narrow : safe_expr -> Range64 -> safe_expr.
   ```

2. **Define evaluation semantics with Long_Long_Integer intermediates.** Evaluation maps expressions to `Z` (mathematical integers). The key semantic rule is that binary operations compute in `Z` with no overflow; overflow is only possible at Narrow nodes.

   ```
   Fixpoint eval (env : var_id -> Z) (e : safe_expr) : option Z :=
   match e with
   | Lit n       => Some n
   | Var x r     => let v := env x in
                    if contains r v then Some v else None
   | BinOp op l r => ...  (* compute in Z, check div-by-zero for /, mod, rem *)
   | UnNeg e     => option_map Z.opp (eval env e)
   | Narrow e r  => match eval env e with
                    | Some v => if contains r v then Some v else None
                    | None   => None
                    end
   end.
   ```

3. **Define the narrowing-point insertion algorithm.** Given an undecorated expression tree, the algorithm inserts Narrow nodes at exactly the five narrowing-point categories. The algorithm is parameterized by a range-analysis oracle that assigns a Range64 to every subexpression.

4. **State and prove the soundness theorem.**

   **Theorem (Narrowing Soundness).** For all well-typed Safe expressions `e`, environments `env`, and range-analysis results `R` such that `R` is conservative (i.e., for every subexpression `s` of `e`, the actual value of `s` under `env` is contained in `R(s)`):

   - If `eval env (insert_narrows R e) = Some v`, then `v` is within the target Range64 of the outermost narrowing point.
   - If `eval env (insert_narrows R e) = None`, then some narrowing check failed, which corresponds to a compile-time rejection by the Safe compiler.

   **Corollary.** No integer overflow reaches a program variable in a conforming Safe program, assuming the range-analysis oracle is sound (assumption A-03).

#### Key Types from the Companion

| Companion Type/Function | Coq/Isabelle Counterpart |
|------------------------|-------------------------|
| `Range64` record (Lo, Hi : Long_Long_Integer) | `Record Range64 := { lo : Z; hi : Z }` |
| `Is_Valid_Range (R)` = `R.Lo <= R.Hi` | `Definition is_valid (r : Range64) := r.(lo) <=? r.(hi)` |
| `Contains (R, V)` = `V >= R.Lo /\ V <= R.Hi` | `Definition contains (r : Range64) (v : Z) := r.(lo) <=? v && v <=? r.(hi)` |
| `Subset (A, B)` = `A.Lo >= B.Lo /\ A.Hi <= B.Hi` | `Definition subset (a b : Range64) := b.(lo) <=? a.(lo) && a.(hi) <=? b.(hi)` |
| `Intersect (A, B)` | `Definition intersect (a b : Range64) := {| lo := Z.max ... |}` |
| `Widen (A, B)` | `Definition widen (a b : Range64) := {| lo := Z.min ... |}` |

#### Estimated Complexity

- **Lines of specification:** ~200 (inductive types, evaluation, insertion algorithm)
- **Lines of proof:** ~500--800
- **Total:** ~700--1000 lines
- **Person-months:** 1.5--2.5
- **Prerequisites:** Coq standard library (ZArith) or Isabelle/HOL (Int, Word libraries). No exotic dependencies.
- **Confidence that the theorem holds:** High. The property is a direct consequence of the wide-arithmetic evaluation model. The main proof effort is in the induction over expression structure and case analysis on binary operators.

#### Tool Recommendation

**Coq** is recommended for this theorem. The ZArith library provides well-developed support for reasoning about mathematical integers (`Z`), and Coq's `omega`/`lia` tactics handle linear integer arithmetic goals automatically. The inductive structure of the expression language maps naturally to Coq's `Inductive` types and `Fixpoint` recursion.

Isabelle/HOL is a viable alternative with comparable library support (`Int.thy`, `Word.thy`). The choice may depend on team expertise.

---

### 2.2 Priority 2: Ownership No-Double-Ownership Invariant

**Property.** At any program point in a conforming Safe program:

1. Each designated object reachable through an owning access value has exactly one owner.
2. A move invalidates the source (sets it to Null_State/Moved); the target becomes the new owner.
3. A borrow grants temporary exclusive mutable access; the lender is frozen (no read, write, or move) for the duration.
4. An observe grants temporary shared read access; the observed object is frozen against writes and moves but readable.
5. No designated object is simultaneously Owned by two distinct variables.

**Spec reference.** Section 2.3, paragraphs 94--113 (`spec/02-restrictions.md`). Specifically: 2.3.2 (move semantics, paragraphs 96--97c), 2.3.3 (borrowing, paragraphs 98--100a), 2.3.4 (observing, paragraphs 101--102), 2.3.4a (lifetime containment, paragraphs 102a--102b).
Key canonical clause IDs: `SAFE@4aecf21:spec/02-restrictions.md#2.3.2.p96a:0eaf48aa`, `#2.3.2.p96c:0b45de01`, `#2.3.3.p99b:47108b45`, `#2.3.4a.p102a:5bc5ab8b`, `#2.3.4a.p102b:2ed757bd`.

**Companion anchor.** `safe_model.ads` Part 3 (Ownership_State enumeration, Is_Accessible, Is_Movable, Is_Borrowable, Is_Observable, Is_Valid_Transition); `safe_po.ads` procedures Check_Not_Moved, Check_Owned_For_Move, Check_Borrow_Exclusive, Check_Observe_Shared.

#### Formalization Approach

1. **Define ownership states.**

   ```
   Inductive ownership_state :=
   | Null_State | Owned | Moved | Borrowed | Observed.
   ```

   This directly mirrors `Safe_Model.Ownership_State`.

2. **Define the ownership transition relation.** The valid transitions are specified in `Is_Valid_Transition` in `safe_model.ads`:

   | From | To (valid) |
   |------|-----------|
   | Null_State | Owned |
   | Owned | Moved, Borrowed, Observed, Null_State |
   | Moved | Owned, Null_State |
   | Borrowed | Owned |
   | Observed | Owned, Observed |

   ```
   Inductive valid_transition : ownership_state -> ownership_state -> Prop :=
   | t_null_owned    : valid_transition Null_State Owned
   | t_owned_moved   : valid_transition Owned Moved
   | t_owned_borrow  : valid_transition Owned Borrowed
   | t_owned_observe : valid_transition Owned Observed
   | t_owned_null    : valid_transition Owned Null_State
   | t_moved_owned   : valid_transition Moved Owned
   | t_moved_null    : valid_transition Moved Null_State
   | t_borrow_owned  : valid_transition Borrowed Owned
   | t_observe_owned : valid_transition Observed Owned
   | t_observe_observe : valid_transition Observed Observed.
   ```

3. **Define a program state as a mapping from variable identifiers to ownership states, paired with a mapping from variable identifiers to designated-object identifiers.** The key invariant is: for any designated-object identifier `d`, at most one variable maps to `(Owned, d)`.

   ```
   Definition program_state := var_id -> (ownership_state * option obj_id).

   Definition no_double_ownership (st : program_state) :=
     forall x y d,
       x <> y ->
       snd (st x) = Some d -> fst (st x) = Owned ->
       snd (st y) = Some d -> fst (st y) <> Owned.
   ```

4. **Define ownership operations** (move, borrow-start, borrow-end, observe-start, observe-end, allocate, deallocate) and prove that each operation preserves the `no_double_ownership` invariant.

5. **State and prove the key theorems.**

   **Theorem (No Double Ownership).** If `no_double_ownership st` holds and `st'` is obtained from `st` by any valid ownership operation, then `no_double_ownership st'` holds.

   **Theorem (Borrow Exclusivity).** If variable `x` is in state `Borrowed` with designated object `d`, then no other variable `y` has mutable access to `d` (i.e., `fst (st y)` is not `Owned` or `Borrowed` for the same `d`).

   **Theorem (Observe Sharing Safety).** If variable `x` is in state `Observed` with designated object `d`, then no variable `y` has mutable access to `d`. Multiple variables may be in `Observed` state for the same `d`.

   **Theorem (Transition Completeness).** The ten transitions listed in `Is_Valid_Transition` are the only transitions reachable from any initial state `Null_State`. (This addresses assumption B-01.)

#### Key Types from the Companion

| Companion Type/Function | Mechanized Counterpart |
|------------------------|----------------------|
| `Ownership_State` (5-value enum) | `ownership_state` inductive type |
| `Is_Valid_Transition(From, To)` | `valid_transition` inductive relation |
| `Is_Accessible(S)` = `S in {Owned, Borrowed, Observed}` | `Definition is_accessible s := ...` |
| `Is_Movable(S)` = `S = Owned` | `Definition is_movable s := s = Owned` |
| `Is_Borrowable(S)` = `S = Owned` | `Definition is_borrowable s := s = Owned` |
| `Is_Observable(S)` = `S in {Owned, Observed}` | `Definition is_observable s := ...` |

#### Estimated Complexity

- **Lines of specification:** ~250 (states, transitions, program state, operations)
- **Lines of proof:** ~800--1200
- **Total:** ~1050--1450 lines
- **Person-months:** 2.0--3.5
- **Prerequisites:** Standard library for finite maps. In Isabelle, the Nominal Isabelle package may simplify reasoning about variable binding and scope, though it is not strictly required. In Coq, the `FMapInterface` or `Coq.FSets` libraries suffice.
- **Confidence that the theorem holds:** High. The ownership state machine is deliberately simple (5 states, 10 transitions). The main proof challenge is the invariant preservation argument across all operations, particularly for borrow/observe interactions where multiple variables may reference the same designated object.

#### Tool Recommendation

**Isabelle/HOL** is recommended for this theorem. Isabelle's `Nominal2` library provides infrastructure for reasoning about names and binding, which is useful for variable scoping in the lifetime-containment proofs. Isabelle's `inductive_set` and `inductive` commands handle state-machine reasoning cleanly, and the `auto`/`blast` tactics are effective on the case-analysis goals that dominate ownership proofs.

Coq is a viable alternative, particularly if the Priority 1 proof is already in Coq and the team prefers a single tool.

---

### 2.3 Priority 3: Channel FIFO Preservation

**Property.** Messages sent on a Safe channel are received in the same order they were sent. Specifically, for any sequence of Send and Receive operations serialized by the runtime (assumption A-04), the sequence of values returned by Receive is a prefix of the sequence of values passed to Send, in the same order.

**Spec reference.** Section 4.2, paragraph 20: "A channel is a FIFO queue: elements are dequeued in the order they were enqueued." Section 4.3, paragraphs 27--31 (`spec/04-tasks-and-channels.md`).
Key canonical clause IDs: `SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p20:8aa1a21e`, `#4.3.p27:ef0ce6bd`, `#4.3.p28:ea6bd13c`, `#4.3.p31:a7297e97`.

**Companion anchor.** `safe_model.ads` Part 2 (Channel_State, Is_Valid_Channel, After_Append, After_Remove, Make_Channel); `safe_po.ads` procedures Check_Channel_Not_Full, Check_Channel_Not_Empty, Check_Channel_Capacity_Positive. Note: the current companion ghost model tracks only length and capacity, not element ordering. Assumption B-02 records this gap.

#### Formalization Approach

1. **Extend the channel model with a sequence type.** The current `Channel_State` tracks `(Length, Capacity)`. The mechanized model extends this to `(Queue : list T, Capacity : nat)` where `Length = length Queue`.

   ```
   Record channel (T : Type) := {
     queue    : list T;
     capacity : nat;
     cap_pos  : capacity >= 1;
     bounded  : length queue <= capacity
   }.
   ```

2. **Define Send and Receive operations.**

   ```
   Definition send {T} (ch : channel T) (v : T)
     (not_full : length ch.(queue) < ch.(capacity)) : channel T :=
     {| queue := ch.(queue) ++ [v];
        capacity := ch.(capacity);
        ... |}.

   Definition receive {T} (ch : channel T)
     (not_empty : length ch.(queue) > 0) : T * channel T :=
     match ch.(queue) with
     | h :: t => (h, {| queue := t; capacity := ch.(capacity); ... |})
     | []     => (* absurd by not_empty *)
     end.
   ```

3. **Define a trace model.** A trace is a sequence of operations `Op := Send T | Receive`. Given a sequence of operations, define the resulting sequence of received values.

4. **State and prove the FIFO theorem.**

   **Theorem (FIFO Preservation).** For any sequence of operations `ops` applied to an initially-empty channel, the sequence of values returned by Receive operations is equal to a prefix of the sequence of values passed to Send operations, preserving order.

   Formally: let `sent := filter_sends ops` and `received := filter_receives ops`. Then `received` is a prefix of `sent` and the elements match pointwise.

   **Theorem (Capacity Invariant).** For any reachable channel state `ch`, `0 <= length ch.(queue) <= ch.(capacity)`.

   **Theorem (Consistency with Ghost Model).** For any reachable channel state `ch`, the projection `(length ch.(queue), ch.(capacity))` satisfies all contracts of the companion's `Channel_State` model (Is_Valid_Channel, After_Append postcondition, After_Remove postcondition).

#### Key Types from the Companion

| Companion Type/Function | Mechanized Counterpart |
|------------------------|----------------------|
| `Channel_State` (Length, Capacity) | `channel T` (queue : list T, capacity : nat) |
| `Is_Valid_Channel(S)` = `Capacity >= 1 /\ Length <= Capacity` | `cap_pos` and `bounded` record fields |
| `After_Append(S)` = `(Length + 1, Capacity)` | `send` function (appends to tail) |
| `After_Remove(S)` = `(Length - 1, Capacity)` | `receive` function (removes from head) |
| `Make_Channel(Cap)` = `(0, Cap)` | `{| queue := []; capacity := Cap; ... |}` |

#### Estimated Complexity

- **Lines of specification:** ~100 (channel type, operations, trace model)
- **Lines of proof:** ~300--500
- **Total:** ~400--600 lines
- **Person-months:** 0.5--1.0
- **Prerequisites:** Standard list library (available in both Coq and Isabelle). No exotic dependencies.
- **Confidence that the theorem holds:** Very high. Bounded queues with append-to-tail and remove-from-head are a standard data structure with well-known FIFO properties. The proof is essentially textbook.

#### Tool Recommendation

**Either Coq or Isabelle** is suitable. The proof is straightforward and does not require specialized libraries. If the other priority theorems are already being developed in one tool, use the same tool for consistency.

---

## 3. Secondary Theorems (Lower Priority)

The following theorems are lower priority because the corresponding properties are either straightforward enough that SMT solvers handle them well, or they depend on implementation details that are harder to formalize.

### 3.1 Array Index Safety (D27 Rule 2)

**Property.** `Safe_Index` with the precondition `Arr_Lo <= Arr_Hi /\ Idx >= Arr_Lo /\ Idx <= Arr_Hi` guarantees that no array access is out of bounds.

**Why lower priority.** The precondition is a conjunction of three linear integer inequalities. CVC5 proves this trivially. The Range64 `Contains` check at the narrowing point (Narrow_Indexing) subsumes this under Priority 1's soundness theorem: if Range64 containment is sound (Priority 1), then index safety follows as a special case.

**Estimated effort if pursued.** ~100--200 lines of proof, 0.5 person-months.

### 3.2 Division Safety (D27 Rule 3)

**Property.** `Safe_Div` (Pre: `Y /= 0 /\ not (X = LLI'First /\ Y = -1)`), `Safe_Mod` (Pre: `Y /= 0`), and `Safe_Rem` (Pre: `Y /= 0`) prevent division by zero and the unique signed division overflow case.

**Why lower priority.** The preconditions are simple arithmetic facts. All 3 division VCs and their postconditions (`R = X / Y`, `R = X mod Y`, `R = X rem Y`) are fully proved by CVC5 at level 2. The `Excludes_Zero` function in `safe_model.ads` (`R.Hi < 0 \/ R.Lo > 0`) correctly characterizes Range64 intervals that do not contain zero.

**Estimated effort if pursued.** ~50--100 lines of proof, 0.25 person-months.

### 3.3 Null-Safety (D27 Rule 4)

**Property.** `Not_Null_Ptr(Is_Null)` with `Pre => not Is_Null` and `Safe_Deref(Is_Null)` with `Pre => not Is_Null` prevent null dereference.

**Why lower priority.** This is propositional tautology: `not Is_Null` implies `not Is_Null`. The Boolean-flag model (necessitated by SPARK's exclusion of access types under SPARK_Mode) is a trivial abstraction. The only nontrivial property is that the compiler correctly lowers access-type null checks to this Boolean model (assumption B-04, severity minor).

**Estimated effort if pursued.** ~20--50 lines of proof, negligible.

### 3.4 Select Determinism

**Property.** The Safe `select` statement selects the first ready channel arm in declaration order (spec Section 4.4, paragraph 41). Given a deterministic serialization of channel operations, the select outcome is deterministic.

**Why lower priority.** This property depends on the runtime implementation of select (assumption D-01, which records that polling-based lowering is assumed conformant). Formalizing it would require modeling the runtime's channel-polling loop, which is outside the scope of the SPARK companion. The property is interesting from a language-semantics perspective but is more naturally addressed by runtime testing or model checking than by mechanized proof.

**Estimated effort if pursued.** ~300--500 lines of proof, 1.5--2.0 person-months (high due to concurrency modeling).

---

## 4. Formalization Infrastructure

### 4.1 Coq Development Structure

```
coq/
  Safe_Types.v          -- Base types: Z-based integers, ownership_state enum,
                        -- var_id, obj_id, task_id definitions
  Safe_Range64.v        -- Range64 record, is_valid, contains, subset,
                        -- intersect, widen, excludes_zero
                        -- Lemmas: subset_transitivity, intersect_validity,
                        -- widen_monotonicity, contains_decidability
  Safe_Expr.v           -- Inductive type for Safe integer expressions
                        -- Evaluation semantics (eval function)
  Safe_Narrowing.v      -- Narrowing-point insertion algorithm
                        -- Range-analysis oracle interface (axiomatized)
  Safe_Arithmetic.v     -- D27 Rule 1 soundness theorem
                        -- Narrowing soundness proof
                        -- Corollary: no overflow reaches program variables
  Safe_Ownership.v      -- Ownership states, transitions, program state
                        -- no_double_ownership invariant
                        -- Borrow exclusivity, observe sharing theorems
                        -- Transition completeness (B-01 discharge)
  Safe_Channel.v        -- Parameterized channel type with sequence
                        -- Send/Receive operations
                        -- FIFO preservation theorem
                        -- Capacity invariant
                        -- Consistency with ghost model
  Safe_Assumptions.v    -- Explicit statement of discharged assumptions
                        -- A-03 (partial), B-01, B-02 as proved lemmas
  Makefile              -- Coq compilation targets
  _CoqProject           -- Coq project file
```

**Build requirements.** Coq >= 8.18, coq-stdlib. No additional opam packages required for the core development. If Equations plugin is used for well-founded recursion on expressions, add `coq-equations`.

### 4.2 Isabelle Development Structure

```
isabelle/
  Safe_Types.thy        -- Base type definitions, type_synonym declarations
  Safe_Range64.thy      -- Range64 record, interval arithmetic lemmas
  Safe_Expr.thy         -- Expression datatype, evaluation function
  Safe_Narrowing.thy    -- Narrowing insertion, range-analysis locale
  Safe_Arithmetic.thy   -- D27 Rule 1 soundness theorem and proof
  Safe_Ownership.thy    -- Ownership inductive type, transition relation
                        -- State machine invariant proofs
  Safe_Channel.thy      -- Channel type, FIFO theorem
  Safe_Assumptions.thy  -- Discharged assumptions
  ROOT                  -- Isabelle session root file
  document/root.tex     -- LaTeX document generation template
```

**Build requirements.** Isabelle >= 2024, HOL session. No additional AFP entries required for the core development. If Nominal2 is used for the ownership proof, add the Nominal2 AFP entry.

### 4.3 Shared Infrastructure

Both developments share the following design principles:

1. **No axioms beyond the range-analysis oracle.** The Priority 1 proof takes the range-analysis oracle as an axiom (reflecting assumption A-03). All other theorems are proved from definitions only.

2. **Extraction targets.** The Coq development should be structured to support extraction to OCaml or Haskell if a verified reference implementation of the range checker is desired in the future.

3. **Documentation.** Each theory file includes a header comment mapping its definitions back to the companion source files (`safe_model.ads`, `safe_po.ads`) and spec sections.

4. **Regression testing.** The `Makefile` / `ROOT` file compiles the entire development in CI. A failed proof is a CI failure.

---

## 5. Assumptions That Mechanized Proofs Could Discharge

The companion tracks 13 assumptions in `companion/assumptions.yaml`. The following table identifies which assumptions could be moved from status `open` to status `mechanically verified` by the proofs described in this document.

| Assumption | Summary | Severity | Current Status | Mechanized Proof | Discharge Scope |
|-----------|---------|----------|---------------|-----------------|----------------|
| **A-03** | Static range analysis is sound | Critical | Open | Priority 1 (D27 Rule 1 Soundness) | **Partial.** The mechanized proof verifies that *if* the range-analysis oracle produces conservative bounds, *then* no overflow reaches program variables. It does not verify the oracle itself (the compiler's actual range-analysis pass). To fully discharge A-03, one would also need to formalize and verify the specific range-analysis algorithm, which is a compiler verification task beyond this scope. |
| **B-01** | Ownership state enumeration is complete | Major | Open | Priority 2 (Ownership Invariant) | **Full.** The Transition Completeness theorem proves that the 5 states and 10 transitions in `Is_Valid_Transition` cover all reachable ownership states from any initial `Null_State`. If the specification adds new states (e.g., partially-moved aggregates), the mechanized proof would fail to compile, providing an automatic regression signal. |
| **B-02** | Channel FIFO ordering preserved by implementation | Major | Open | Priority 3 (Channel FIFO) | **Partial.** The mechanized proof verifies that the *mathematical model* of a bounded queue preserves FIFO ordering. It does not verify the runtime implementation (Ada protected objects or equivalent). To fully discharge B-02, one would need either (a) verified code extraction from the mechanized model, or (b) a separate proof that the runtime implementation refines the mathematical model. |
| **B-03** | Task-variable map covers all shared variables | Major | Open | Not addressed | **Not addressable by mechanized proof alone.** This assumption concerns the compiler's analysis pass (does it register all shared variables in the Task_Var_Map?). Discharging it would require formalizing the compiler's task-variable analysis, which depends on the compiler's IR and call-graph construction. |
| **A-01** | 64-bit intermediate integer evaluation | Critical | Open | Not addressed | **Not addressable.** This is a hardware/implementation assumption. Mechanized proof cannot verify that the target provides 64-bit intermediates. |
| **A-02** | IEEE 754 non-trapping floating-point mode | Critical | Open | Not addressed | **Not addressable.** Hardware assumption. |
| **A-04** | Channel implementation correctly serializes access | Critical | Open | Not addressed | **Not directly addressable.** This is a runtime implementation assumption. The Priority 3 proof assumes serialized access (matching A-04's statement) and proves FIFO under that assumption. A-04 itself would require runtime verification. |
| **A-05** | FP division result is finite when operands are finite | Major | Open | Not addressed | **Potentially addressable** with a formalized IEEE 754 model (e.g., Flocq library for Coq), but the effort would be substantial and the property is already justified in the companion via `pragma Annotate`. Low priority. |

### Summary of Assumption Discharge

| Status After Mechanized Proofs | Count | IDs |
|-------------------------------|-------|-----|
| Fully discharged | 1 | B-01 |
| Partially discharged (model-level) | 2 | A-03, B-02 |
| Not addressable by mechanized proof | 10 | A-01, A-02, A-04, A-05, B-03, B-04, C-01, C-02, D-01, D-02 |

---

## 6. Effort Estimates and Recommendations

### 6.1 Summary Table

| Priority | Theorem | Lines of Proof (est.) | Person-Months (est.) | Prerequisites | Confidence |
|----------|---------|----------------------|---------------------|--------------|-----------|
| **P1** | D27 Rule 1 Soundness | 700--1000 | 1.5--2.5 | Coq ZArith or Isabelle Int/Word; expertise in inductive proofs over expression languages | High |
| **P2** | Ownership No-Double-Ownership | 1050--1450 | 2.0--3.5 | Finite map library; expertise in state-machine invariant proofs | High |
| **P3** | Channel FIFO Preservation | 400--600 | 0.5--1.0 | Standard list library; basic expertise in mechanized proof | Very High |
| Total | | 2150--3050 | 4.0--7.0 | | |

### 6.2 Recommended Execution Order

1. **Start with Priority 3 (Channel FIFO).** This is the simplest theorem with the highest confidence. It serves as a warm-up that establishes the development infrastructure (build system, CI integration, naming conventions, documentation standards) while delivering a concrete result: discharging assumption B-02 at the model level.

2. **Proceed to Priority 1 (D27 Rule 1).** This is the highest-value theorem for the Safe language's assurance story, as it addresses the central novelty of Safe's arithmetic model. The Range64 formalization can be validated against the companion's ghost model. Partial discharge of the critical assumption A-03 is a significant assurance improvement.

3. **Conclude with Priority 2 (Ownership).** This is the most complex theorem due to the multi-variable state-space reasoning. By the time this is attempted, the team will have experience with the proof assistant and the Safe formalization patterns.

### 6.3 Staffing and Expertise

- **Minimum team:** 1 engineer with prior experience in Coq or Isabelle/HOL and familiarity with programming language formalization (e.g., POPLmark challenge, Software Foundations).
- **Recommended team:** 1 lead proof engineer + 1 reviewer with SPARK and Safe language expertise (to validate that the formalization accurately reflects the specification).
- **Calendar time:** 6--10 months for all three priorities at 50% allocation, or 3--5 months at full-time allocation.

### 6.4 Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|-----------|
| Range-analysis oracle axiom is too weak or too strong | P1 theorem is vacuously true or unprovable | Low | Validate oracle axiom against concrete examples from the spec; have a SPARK engineer review the axiom |
| Ownership formalization misses a case from the spec | P2 theorem does not match actual Safe semantics | Medium | Cross-reference every transition against spec paragraphs 96--102b; run the formalization past a Safe language designer |
| Proof assistant version upgrade breaks proofs | CI regression | Low | Pin proof assistant version; upgrade deliberately with dedicated regression pass |
| Team lacks proof assistant expertise | Schedule slippage | Medium | Allocate ramp-up time (2--4 weeks for an engineer with formal methods background but no Coq/Isabelle experience) |

---

## 7. Relationship to SPARK Proofs

### 7.1 What SPARK Proves

GNATprove operating on the SPARK companion at the Silver gate proves:

- **Absence of runtime errors (AoRTE).** All 15 runtime checks pass (14 proved by CVC5, 1 justified). This means: no integer overflow in the companion's own computations, no division by zero, no range-check failures on the 4 non-Ghost procedure bodies.
- **Functional contract satisfaction.** All 20 functional contract VCs are proved (96% by CVC5, 4% trivially). This means: every postcondition on Safe_Div, Safe_Mod, Safe_Rem, and FP_Safe_Div is satisfied by its body.
- **Flow correctness.** All 29 flow checks pass (4 initialization, 25 termination). This means: all `out` parameters are assigned, all subprograms terminate, and no hidden data flow exists.

These results are strong evidence that the companion code is correct. They do not, however, constitute evidence that the companion's *models* (Range64, Ownership_State, Channel_State, Task_Var_Map) correctly capture the Safe language semantics.

### 7.2 What Mechanized Proofs Add

Mechanized proofs verify the models that SPARK relies on:

| SPARK Proves | Mechanized Proofs Verify |
|-------------|------------------------|
| `Contains(Target, V)` holds at each narrowing-point call site | The Range64 model and narrowing-point algorithm are *sound*: if Contains holds, then no overflow actually occurs in the mathematical evaluation semantics |
| `State /= Moved` holds before every dereference | The Ownership_State transition system *preserves the no-double-ownership invariant*: the 5 states and 10 transitions are sufficient and complete |
| `Length < Capacity` holds before every send | The Channel_State model, extended with a sequence type, *preserves FIFO ordering*: elements come out in the order they went in |

### 7.3 The Assurance Stack

Together, SPARK and mechanized proofs create a two-layer assurance stack:

```
Layer 2: Mechanized Proofs (Coq / Isabelle)
  - Verifies: model soundness, language-level invariants
  - Trusted base: proof assistant kernel
  - Coverage: Range64 arithmetic, ownership transitions, FIFO ordering

Layer 1: SPARK / GNATprove (CVC5 / Z3 / Alt-Ergo)
  - Verifies: contract satisfaction, runtime error absence
  - Trusted base: GNATprove + Why3 + SMT solvers
  - Coverage: 23 PO procedures, 26 ghost functions, Silver gate (64 checks)

Layer 0: Safe Language Specification (spec commit 4aecf21)
  - Defines: D27 Silver-by-construction rules, ownership model, channel semantics
  - Trusted base: specification review process
  - Coverage: Sections 2.3, 2.8, 4.2-4.5, 5.3-5.4
```

The mechanized proofs do not replace any SPARK verification. They add a higher-assurance layer that verifies the foundational models. If a mechanized proof fails (because the model is changed or the specification evolves), this signals that the SPARK companion's models may need revision -- even if the SPARK proofs still pass. Conversely, if a SPARK proof fails, this signals an implementation error in the companion code -- even if the mechanized proofs confirm the model is sound.

### 7.4 Long-Term Vision

As the Safe language matures, the mechanized proof development could be extended to:

1. **Verified range-analysis algorithm.** Formalize and verify the specific interval-analysis algorithm used by the Safe compiler. This would fully discharge assumption A-03 (currently only partially addressed by Priority 1).

2. **Verified channel implementation.** Extract a verified FIFO queue implementation from the Priority 3 Coq development. This would bridge the gap between the mathematical model and the runtime, partially discharging assumption A-04.

3. **Compiler correctness.** Formalize the translation rules from Safe source to the intermediate representation, proving that the compiler preserves the properties established by the mechanized proofs. This is a multi-year effort but follows naturally from the foundation laid here.

4. **Connection to CompCert or CakeML.** If the Safe compiler targets C or another backend with an existing verified compiler, the mechanized proofs could be connected to CompCert (Coq) or CakeML (HOL4/Isabelle) to provide end-to-end assurance from Safe source to machine code.
