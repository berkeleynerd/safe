# GNATprove Configuration Profile

**Safe Language Annotated SPARK Companion**
Spec commit: `468cf72332724b04b7c193b4d2a3b02f1584125d`
Date: 2026-03-02

---

## 1. Overview

This document records the GNATprove configuration choices, prover settings, and verification policy for the Safe Language Annotated SPARK Companion. The companion encodes proof obligations (POs) derived from the Safe specification as SPARK contracts and verifies them under GNATprove at two assurance gates:

- **Bronze gate** -- flow analysis (data-flow, initialization, termination)
- **Silver gate** -- absence of runtime errors (AoRTE) via formal proof

The configuration is designed so that Bronze verification runs on every CI cycle and spec regeneration, while Silver verification runs at milestone boundaries and before release. All switches, solver choices, and expected results are documented here so that any qualified engineer can reproduce the verification from a clean checkout.

---

## 2. Toolchain Requirements

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| GNAT Pro or GNAT Community | >= 14.x | Ada 2022 language level required (`-gnat2022`) |
| SPARK Discovery (GNATprove) | >= 25.x | Needed for full SPARK 2022 Ghost and contract support |
| Why3 | >= 1.7 | Intermediate verification condition (VC) language backend |
| CVC5 | >= 1.0.8 | Primary SMT solver for arithmetic VCs |
| Z3 | >= 4.12 | Backup solver for bitvector and combinatorial reasoning |
| Alt-Ergo | >= 2.5 | Ada/SPARK-native solver for type system reasoning |

**Project file:** `companion/gen/companion.gpr`

The project file sets Ada 2022 mode, enables all warnings as errors, enables assertions, and configures the Prove package with `--mode=prove --level=2 --report=all --warnings=error`.

---

## 3. Bronze Gate (Flow Analysis)

### 3.1 Mode

```
gnatprove -P companion/gen/companion.gpr --mode=flow --report=all --warnings=error
```

### 3.2 What It Proves

Flow analysis (`--mode=flow`) verifies the following properties without invoking SMT solvers:

| Property | Description |
|----------|-------------|
| **Initialization** | Every variable and `out` parameter is assigned before it is read. The 4 initialization checks cover the `out` parameters of `Safe_Div`, `Safe_Mod`, `Safe_Rem`, and `FP_Safe_Div`. |
| **Data dependencies** | Computed `Global` and `Depends` contracts are internally consistent. No hidden data flow exists. |
| **Termination** | Each subprogram is verified to terminate. The 25 termination checks cover every subprogram in `Safe_Model` (26 expression functions, all trivially terminating) and `Safe_PO` (23 procedures plus the package elaboration). Since `Safe_Model` is a Pure Ghost package of expression functions, its termination is immediate. |
| **Information flow** | No information leak through unintended output dependencies. |

### 3.3 Expected Results

```
Phase 1 of 2: checking of data and information flow ...
  safe_model.ads             -- 26 subprograms analyzed
  safe_po.ads / safe_po.adb  -- 24 subprograms analyzed (1 package + 23 procedures)

Summary:
  29 / 29 flow checks proved
  0 errors
  0 warnings

  Breakdown:
    4 initialization checks proved    (Safe_Div, Safe_Mod, Safe_Rem, FP_Safe_Div)
    25 termination checks proved
```

### 3.4 When to Run

- **Every CI cycle.** Flow analysis is fast (seconds on a modern workstation) and catches data-flow regressions immediately.
- **Every spec regeneration.** After running `spec2spark`, re-run flow analysis before attempting proof mode.
- **On every merge to main.** Flow analysis is a merge-gate requirement.

### 3.5 Success Criteria

The Bronze gate passes if and only if:

1. GNATprove exits with return code 0.
2. The summary reports **0 errors** and **0 warnings** in flow analysis mode.
3. All 29 flow checks are proved.

Any flow warning (even a "medium" severity) is treated as a gate failure because CI runs GNATprove with `--warnings=error`, which treats any GNATprove warning as a gate failure.

---

## 4. Silver Gate (Proof Mode)

### 4.1 Mode

```
gnatprove -P companion/gen/companion.gpr \
  --mode=prove \
  --level=2 \
  --prover=cvc5,z3,altergo \
  --steps=0 \
  --timeout=120 \
  --report=all \
  --warnings=error \
  --checks-as-errors=on
```

### 4.2 What It Proves

Proof mode (`--mode=prove`) includes all flow analysis checks plus formal verification of:

| Property | Spec Reference |
|----------|---------------|
| **Precondition contracts (Pre)** | Every call to a PO procedure must satisfy its `Pre` aspect. |
| **Postcondition contracts (Post)** | Every non-Ghost procedure with a `Post` aspect must satisfy it. |
| **Range checks** | Integer and floating-point values stay within declared type ranges (D27 Rule 1, Rule 5). |
| **Division safety** | Divisors are provably nonzero before division, `mod`, and `rem` (D27 Rule 3). |
| **Index bounds** | Array indices are provably within array bounds (D27 Rule 2). |
| **Overflow checks** | No intermediate integer overflow in the 64-bit evaluation model (D27 Rule 1). |

### 4.3 Prover Configuration

| Switch | Value | Rationale |
|--------|-------|-----------|
| `--prover` | `cvc5,z3,altergo` | Try CVC5 first (strongest on linear arithmetic), then Z3 (good for bitvectors and combinatorial), then Alt-Ergo (Ada-native type reasoning). |
| `--steps` | `0` | Unlimited solver steps; rely on timeout instead. Prevents premature abandonment of solvable VCs. |
| `--timeout` | `120` | 120 seconds per VC. Generous for a companion of this size; ensures FP arithmetic VCs are not prematurely timed out. |
| `--level` | `2` | Medium effort: enables loop unrolling, split VCs, and Why3 transformations beyond level 1. Sufficient for the linear contracts in this companion. |
| `--report` | `all` | Report every VC result (proved, unproved, error) for audit trail. |
| `--warnings` | `error` | Treat all GNATprove warnings as errors. Any warning fails the gate. |

### 4.4 Expected VCs Per Procedure

The following table enumerates the verification conditions (VCs) expected from each non-trivial procedure. Ghost procedures with null bodies and simple preconditions generate only precondition VCs at call sites; they do not generate body VCs.

#### 4.4.1 Non-Ghost Procedures (4 procedures with actual computation)

| Procedure | D27 Rule | Expected VCs |
|-----------|----------|-------------|
| `Safe_Div` | Rule 1 + Rule 3 | **Precondition VC:** `Y /= 0` (caller must prove). **Division safety VC:** `Y /= 0` holds at `R := X / Y`. **Postcondition VC:** `R = X / Y`. **Overflow check VC:** division result fits `Long_Long_Integer`. |
| `Safe_Mod` | Rule 3 | **Precondition VC:** `Y /= 0`. **Division safety VC:** `Y /= 0` at `R := X mod Y`. **Postcondition VC:** `R = X mod Y`. **Overflow check VC:** mod result in range. |
| `Safe_Rem` | Rule 3 | **Precondition VC:** `Y /= 0`. **Division safety VC:** `Y /= 0` at `R := X rem Y`. **Postcondition VC:** `R = X rem Y`. **Overflow check VC:** rem result in range. |
| `FP_Safe_Div` | Rule 5 | **Precondition VC:** `Y /= 0.0 and then Y = Y and then X = X`. **Division safety VC:** `Y /= 0.0` at `R := X / Y`. **Postcondition VC:** `R = X / Y`. **Float overflow VC:** result representable in `Long_Float`. |

#### 4.4.2 Ghost Procedures (19 procedures -- null bodies)

Ghost procedures have null bodies, so GNATprove generates no body VCs for them. The VCs arise at call sites where the compiler emits calls to these PO procedures. In the companion itself (which has no main program and no inter-PO calls), the VCs are the precondition validity checks that GNATprove performs on the contract expressions themselves.

| Category | Procedures | Contract Pattern |
|----------|-----------|-----------------|
| Narrowing (Rule 1) | `Narrow_Assignment`, `Narrow_Parameter`, `Narrow_Return`, `Narrow_Indexing`, `Narrow_Conversion` | `Pre => Is_Valid_Range(T) and then Contains(T, V)` |
| Index safety (Rule 2) | `Safe_Index` | `Pre => Arr_Lo <= Arr_Hi and then Idx >= Arr_Lo and then Idx <= Arr_Hi` |
| Nonzero (Rule 3) | `Nonzero` | `Pre => V /= 0` |
| Not-null (Rule 4) | `Not_Null_Ptr`, `Safe_Deref` | `Pre => not Is_Null` |
| FP safety (Rule 5) | `FP_Not_NaN`, `FP_Not_Infinity` | `Pre => V = V` / `Pre => V = V and then V in range` |
| Ownership | `Check_Not_Moved`, `Check_Owned_For_Move`, `Check_Borrow_Exclusive`, `Check_Observe_Shared` | Pre on `Ownership_State` enumeration |
| Channel | `Check_Channel_Not_Full`, `Check_Channel_Not_Empty`, `Check_Channel_Capacity_Positive` | Pre on `Natural` length/capacity |
| Race-freedom | `Check_Exclusive_Ownership` | Pre on `Task_Var_Map` array lookup |

### 4.5 Unproved VCs

As of spec commit `468cf72`, the Silver gate produces **132 total checks: 32 flow, 99 proved (CVC5), 1 justified (FP_Safe_Div float overflow -- see assumption A-05), 0 unproved**. The companion is intentionally structured so that:

- All Ghost procedure bodies are null, generating no body VCs.
- All non-Ghost procedures (`Safe_Div`, `Safe_Mod`, `Safe_Rem`, `FP_Safe_Div`) have postconditions that are tautological given the body (the body literally computes the postcondition expression).

**Known areas of potential difficulty:**

| Area | Risk | Mitigation |
|------|------|-----------|
| `FP_Safe_Div` postcondition | Floating-point `R = X / Y` equality may challenge solvers due to IEEE 754 rounding semantics. | CVC5 and Z3 both support the `FP` theory. If the VC is unproved, consider adding `--level=3` or a manual `pragma Assume`. Any such assumption must be recorded in `companion/assumptions.yaml`. |
| Nonlinear integer arithmetic | Not currently present. If future POs introduce multiplication-dependent contracts, CVC5 may require `--level=3` or `--steps=0 --timeout=300`. | Monitor VC results at each regeneration. |

If any VC becomes unproved, the engineer must either:
1. Increase prover effort (`--level=3` or `--timeout=300`).
2. Add a justified `pragma Assume` and record a new assumption in `assumptions.yaml` with severity >= major.
3. Restructure the contract to make the VC more solver-friendly, provided the restructuring preserves semantic equivalence.

### 4.6 When to Run

- **At milestone boundaries** (M1, M2, M3, etc.).
- **Before any release** to external consumers.
- **After any change** to `safe_model.ads`, `safe_po.ads`, or `safe_po.adb`.
- **Optionally in CI** with a reduced timeout (`--timeout=30`) for early warning.

### 4.7 Emitted-Proof Reproducibility Contract

The emitted-output proof gates used by `PR10`, `PR10.2`, `PR10.3`, and later emitted-proof follow-ons reuse one enforced profile:

`--mode=prove --level=2 --prover=cvc5,z3,altergo --steps=0 --timeout=120 --report=all --warnings=error --checks-as-errors=on`

For those emitted gates, the committed reproducibility contract is:

- deterministic reports plus normalized GNATprove summaries
- explicit command-line enforcement of the profile above
- explicit `-cargs -gnatec=<ada_dir>/gnat.adc` application on emitted compile/flow/prove commands when `gnat.adc` is present

GNATprove session artifacts are not committed and are not part of the reproducibility contract. The repo intentionally treats transient session files as tool-local scratch output rather than stable evidence.

---

## 5. Concurrency Profile

### 5.1 Safe Spec Concurrency Model

The Safe specification defines a concurrency model based on:

- **Static tasks** with priority annotations (Section 4, D28).
- **Channels** as the primary inter-task communication mechanism (Section 4, 4.2--4.3).
- **No unprotected shared mutable state** between tasks, with only the compiler-generated `shared` wrapper subset admitted (Section 4, 4.5; Section 5, 5.4.1).
- **No Ada tasking constructs** -- no `task type`, no `protected type`, no `entry`, no `accept`, no `select` (as user-declared constructs).

The Safe spec references Ravenscar/Jorvik profile constraints as design precedent:

| Constraint | Safe Equivalent |
|-----------|----------------|
| Static task creation | Tasks declared at package level with `task ... is ... end` syntax |
| No dynamic priorities | Priority is a static aspect on task declarations |
| No task termination | Non-termination legality rule (D28) |
| No shared variables between tasks | Task-variable ownership analysis (Section 4, 4.5) |
| Sequential elaboration | All package-level initialization completes before any task starts |
| Ceiling priority protocol | Implementation uses ceiling priority for channel protected objects |

### 5.2 Sequential Elaboration Policy

Safe requires that all package-level elaboration completes before any task begins execution. This is the `Sequential` elaboration policy from Annex D. The companion models this by having no task-related elaboration code; all ghost models are Pure and require no runtime elaboration.

### 5.3 How the Companion Models Concurrency

The companion does **not** declare Ada tasks. Instead, it models concurrency abstractly:

- **`Task_Var_Map`** (in `Safe_Model`): A ghost array mapping variable IDs to task IDs. This models the task-variable ownership invariant without creating actual Ada tasks.
- **`Channel_State`** (in `Safe_Model`): A ghost record with `Length` and `Capacity` fields modeling bounded FIFO channel state.
- **`Check_Exclusive_Ownership`** (in `Safe_PO`): A ghost procedure whose precondition encodes the single-owner invariant.

All of these are Ghost-annotated and erased at compilation. The companion is a fully sequential SPARK program.

### 5.4 GNATprove Concurrency Checks

GNATprove can perform concurrency-specific checks (e.g., data race detection via tasking-aware flow analysis) when the analyzed program contains Ada tasks. Since the companion contains **no Ada tasks**, no protected objects, and no entries:

- **No concurrency-specific checks apply.**
- GNATprove treats the companion as a sequential program.
- The `Ravenscar` or `Jorvik` profile pragmas are not used in the companion project file.

If a future version of the companion introduces task-modeling constructs that GNATprove can analyze for concurrency, this section must be updated.

---

## 6. Assumption Budget

### 6.1 Reference

All tracked assumptions are recorded in:

```
companion/assumptions.yaml
```

Each assumption documents a dependency that the SPARK companion relies on but cannot verify within SPARK itself. If an assumption is invalidated, the proof obligations that depend on it may become unsound.

### 6.2 Categories

| Category | Meaning | Count |
|----------|---------|-------|
| **A** -- Implementation/Target | Properties of the compiler, runtime, or hardware (e.g., 64-bit arithmetic, IEEE 754 mode, FP overflow guard, heap runtime contracts) | 6 |
| **B** -- Modeling | Fidelity of the ghost model to the real system (e.g., ownership state completeness, task-var map coverage) | 4 tracked (3 open, 1 resolved) |
| **C** -- Proof-Mode | Properties of the GNATprove verification methodology (e.g., flow analysis sufficiency, Ghost erasure) | 2 |
| **D** -- Specification | Properties of the Safe specification text itself (e.g., frozen commit authority) | 1 |

### 6.3 Budget Summary

| Severity | Count | IDs |
|----------|-------|-----|
| **Critical** | 5 | A-01 (64-bit intermediates), A-02 (IEEE 754 non-trapping), A-03 (range analysis soundness), A-04 (channel serialization), A-06 (heap runtime contracts) |
| **Major** | 4 tracked (3 open, 1 resolved) | A-05 (FP division overflow guard), B-01 (ownership state completeness), B-02 (FIFO ordering, resolved), B-03 (task-var map coverage) |
| **Minor** | 4 | B-04 (Boolean null model), C-01 (flow analysis sufficiency), C-02 (Ghost erasure), D-02 (frozen spec commit) |
| **Total** | **13 tracked (12 open, 1 resolved)** | |

### 6.4 Assumption Extraction and Diffing

After each spec regeneration, the assumption budget should be reviewed:

1. **Extract**: Run `scripts/extract_assumptions.sh` which parses GNATprove output and writes `companion/assumptions_extracted.txt`.
2. **Diff**: Run `scripts/diff_assumptions.sh` which:
   - Verifies the GNATprove proof summary matches the committed golden baseline (`companion/gen/prove_golden.txt`).
   - Counts tracked/open/resolved assumptions and severities from `companion/assumptions.yaml`.
   - Enforces budget limits against **open** assumptions only (max 15 open, max 5 open critical).
   - Exits with a nonzero code if drift or budget violations are detected.
3. **Review**: Any new assumption must be explicitly justified in a review comment before the change is merged.

### 6.5 Budget Growth Policy

- **New assumptions require explicit justification.** No assumption may be added to `assumptions.yaml` without a review that documents the rationale, the affected procedures, and the severity classification.
- **Critical assumptions require sign-off** from at least two engineers.
- **Assumption removal** (resolution) is encouraged and should be tracked with a `status: resolved` field and a note explaining how the assumption was discharged.
- **Target**: The total assumption count should not grow beyond 15 without a formal budget review. Any growth in open critical assumptions beyond 5 requires escalation.

---

## 7. SMT Solver Notes

### 7.1 CVC5 -- Primary Solver

CVC5 is the primary solver for the companion. It excels at:

- **Linear integer arithmetic** (LIA): All D27 Rule 1 range checks, Rule 2 index bounds, and Rule 3 nonzero checks are linear inequalities over `Long_Long_Integer`.
- **Nonlinear integer arithmetic** (NIA): If future POs introduce multiplication, CVC5's NLSAT-based reasoning handles most cases.
- **Enumeration types**: CVC5 handles `Ownership_State` enumeration constraints efficiently.
- **Array theory**: The `Task_Var_Map` ghost model uses SPARK arrays; CVC5's array theory handles the `for all V in Var_Id_Range => ...` quantifiers in `Assign_Owner`'s postcondition.

CVC5 is tried first in the prover chain because it has the best success rate on the VC patterns generated by GNATprove for this companion.

### 7.2 Z3 -- Backup Solver

Z3 serves as the backup solver when CVC5 times out or returns unknown. Z3 is particularly effective for:

- **Bitvector reasoning**: If future POs model fixed-width arithmetic, Z3's bitvector theory is stronger than CVC5's.
- **Combinatorial constraints**: Z3's SAT-based core can handle large disjunctive constraints (e.g., case expressions on `Ownership_State`).
- **Quantifier instantiation**: Z3's E-matching handles universally quantified postconditions (e.g., `Assign_Owner`'s frame condition).

### 7.3 Alt-Ergo -- Ada/SPARK Native Solver

Alt-Ergo is the solver historically bundled with GNATprove and is tuned for the VC patterns generated by the SPARK toolchain:

- **Type system reasoning**: Alt-Ergo understands Ada subtype constraints natively, which helps with range checks.
- **Record types**: Alt-Ergo handles the `Range64` and `Channel_State` record types well.
- **Triggers**: Alt-Ergo's trigger-based instantiation works well with GNATprove's generated axioms.

Alt-Ergo is tried last because CVC5 and Z3 generally prove more VCs faster, but Alt-Ergo occasionally proves VCs that the other two cannot, particularly for type-system-heavy reasoning.

### 7.4 Known Challenging VCs

| VC | Challenge | Solver Notes |
|----|-----------|-------------|
| `FP_Safe_Div` postcondition (`R = X / Y`) | IEEE 754 floating-point division equality. The `R = X / Y` postcondition requires the solver to reason about floating-point semantics, not just real arithmetic. | CVC5 and Z3 both support the SMT-LIB `FloatingPoint` theory. GNATprove translates `Long_Float` operations to FP64 theory VCs. At `--level=2`, this VC should be provable. If not, increase to `--level=3` which enables additional Why3 transformations for float VCs. |
| `FP_Not_Infinity` precondition chain (`V = V and then V >= Long_Float'First and then V <= Long_Float'Last`) | Encoding the "V is finite" property requires the solver to understand that `Long_Float'First` and `Long_Float'Last` exclude infinity and NaN. | GNATprove encodes `Long_Float'First` and `Long_Float'Last` as the finite bounds of the IEEE 754 binary64 range. CVC5 handles this natively. |
| `Assign_Owner` postcondition (universal quantifier) | The frame condition `for all V in Var_Id_Range => (if V /= Var_Id then Result(V) = Map(V))` is a universally quantified formula over a 1024-element domain. | At `--level=2`, GNATprove may split this into individual VCs or use array theory axioms. CVC5 and Z3 both handle this efficiently with their array extensionality support. |
| Nonlinear integer arithmetic | Not currently present in the companion. Future POs involving multiplication (e.g., `A * B` range analysis) would introduce NIA VCs. | CVC5's `--nl-ext` reasoning handles polynomial constraints. If needed, increase `--timeout` to 300 seconds for NIA VCs. |

---

## 8. Configuration Reference Table

The following table consolidates all GNATprove switches used across both gates.

| Switch | Value | Gate | Purpose |
|--------|-------|------|---------|
| `-P` | `companion/gen/companion.gpr` | Both | Project file specifying source directories, compiler options, and default proof switches. |
| `--mode` | `flow` | Bronze | Run flow analysis only: initialization, data dependencies, termination, information flow. No SMT solvers invoked. |
| `--mode` | `prove` | Silver | Run flow analysis plus formal proof of all contracts (Pre, Post, runtime checks). Invokes SMT solvers. |
| `--level` | `2` | Silver | Medium proof effort. Enables VC splitting, loop unrolling, and Why3 transformations. Levels: 0 (fast/shallow) to 4 (slow/deep). |
| `--prover` | `cvc5,z3,altergo` | Silver | Ordered list of SMT solvers. Each VC is tried on CVC5 first, then Z3, then Alt-Ergo. |
| `--steps` | `0` | Silver | Unlimited solver steps. Combined with `--timeout`, this ensures solvers use wall-clock time as the bound rather than step count. |
| `--timeout` | `120` | Silver | Maximum wall-clock seconds per VC per solver. 120s is generous for the current companion size. |
| `--report` | `all` | Both | Report every check result (proved, not proved, error). Required for audit trail and golden-output comparison. |
| `--warnings` | `error` | Both | Enable all GNATprove warnings and treat them as errors. When CI passes `--warnings=error`, any GNATprove warning becomes a gate failure. |
| `--checks-as-errors` | `on` | Silver | Treat unproved check messages as errors. Ensures the Silver gate fails if any VC is unproved (or not justified). |

### 8.1 Project File Compiler Switches

These switches are set in `companion/gen/companion.gpr` and apply to both gates:

| Switch | Purpose |
|--------|---------|
| `-gnat2022` | Ada 2022 language level (required for SPARK 2022 features). |
| `-gnatwa` | Enable all compiler warnings. |
| `-gnatwe` | Treat warnings as errors. |
| `-gnata` | Enable assertions (`pragma Assert`, `Assertion_Policy`). |
| `-gnatVa` | Enable all validity checks. |
| `-gnatyg` | GNAT style checks. |
| `-gnatQ` | Generate ALI files even on errors (for tooling). |

### 8.2 Project File Prove Switches

Default prove switches in `companion/gen/companion.gpr`:

```ada
package Prove is
   for Proof_Switches ("Ada") use
     ("--mode=prove",
      "--level=2",
      "--report=all",
      "--warnings=error");
end Prove;
```

These defaults can be overridden on the command line. The Bronze gate overrides `--mode` to `flow`. The Silver gate adds `--prover`, `--steps`, and `--timeout`.

---

## 9. Regression Policy

### 9.1 No New Unproved VCs

Every proved VC is a regression baseline. **No new unproved VC may be introduced without documented justification.** Specifically:

1. After any change to the companion source or spec regeneration, run both the Bronze gate and the Silver gate.
2. Compare the results against the previous run's summary.
3. If any previously proved VC becomes unproved:
   - Investigate the root cause (spec change, contract change, solver regression).
   - If the VC is genuinely harder: increase prover effort or restructure the contract.
   - If the VC represents a real specification gap: add a `pragma Assume` and record the assumption in `assumptions.yaml`.
   - **Never suppress a failed VC silently.**

### 9.2 Assumption Drift Detection

Assumptions are tracked in `companion/assumptions.yaml`. To detect drift:

```bash
# Run extraction from GNATprove output
scripts/extract_assumptions.sh

# Diff against golden baseline and enforce budget
scripts/diff_assumptions.sh
```

The `scripts/diff_assumptions.sh` script:
- Compares the GNATprove proof summary against the committed golden baseline (`companion/gen/prove_golden.txt`).
- Parses the YAML to extract assumption IDs and severities.
- Enforces budget limits (max 15 open, max 5 open critical per gnatprove_profile.md Section 6.5).
- Exits nonzero if drift or budget violations are detected.

### 9.3 Golden Output Comparison

The flow analysis summary output is deterministic for a given toolchain version. To detect regressions:

1. After a successful Bronze gate run, save the summary as a golden reference:
   ```bash
   gnatprove -P companion/gen/companion.gpr --mode=flow --report=all 2>&1 \
     | tail -n 20 > companion/gen/flow_golden.txt
   ```

2. On subsequent runs, compare:
   ```bash
   gnatprove -P companion/gen/companion.gpr --mode=flow --report=all 2>&1 \
     | tail -n 20 > /tmp/flow_current.txt
   diff companion/gen/flow_golden.txt /tmp/flow_current.txt
   ```

3. Any difference (even a change in check count) requires investigation. Legitimate changes (e.g., new PO procedures after spec update) require updating the golden file with a commit message explaining the delta.

### 9.4 CI Integration Summary

| Gate | Trigger | Command | Pass Criteria | Blocking? |
|------|---------|---------|--------------|-----------|
| Bronze (flow) | Every push, every PR | `gnatprove -P ... --mode=flow --report=all --warnings=error` | 0 errors, 0 warnings, all flow checks proved | Yes -- merge blocking |
| Silver (proof) | Every push, every PR | `gnatprove -P ... --mode=prove --level=2 --prover=cvc5,z3,altergo --steps=0 --timeout=120 --report=all --warnings=error --checks-as-errors=on` | All VCs proved or justified (0 unproved) | Yes -- merge blocking |
| Assumption diff | Every CI cycle | `scripts/diff_assumptions.sh` | Proof summary matches golden; assumption budget within limits | Yes -- merge blocking |
