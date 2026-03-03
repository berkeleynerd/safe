# Verified Emission Templates — Design Document

**Status:** Active
**Created:** 2026-03-03
**Source Commit:** 4aecf219ffa5473bfc42b026a66c8bdea2ce5872

## 1. Purpose

The Verified Emission Templates are compilable, provable SPARK packages that
demonstrate each emission pattern from the Safe Language compiler. Each template
is wired to `Safe_PO` proof hooks and verified by GNATprove at Silver level.

Templates serve as:
- **Executable specifications** of compiler translation rules
- **Proof harnesses** confirming that emitted patterns satisfy D27 proof obligations
- **Regression anchors** ensuring emitter changes do not break verification
- **Documentation** mapping Safe constructs to Ada/SPARK via `translation_rules.md`

## 2. Architecture

```
companion/templates/
├── alire.toml                      Alire crate (no external deps)
├── templates.gpr                   GNAT project (Source_Dirs: ./, ../spark/)
├── safe_runtime.ads                Wide_Integer type definition
├── template_wide_arithmetic.ads    M1: Wide intermediate + narrowing
├── template_wide_arithmetic.adb
├── template_division_nonzero.ads   M1: Safe division/mod/rem
├── template_division_nonzero.adb
├── template_ownership_move.ads     M2: Move semantics
├── template_ownership_move.adb
├── template_scope_dealloc.ads      M2: Scope-exit deallocation
├── template_scope_dealloc.adb
├── template_not_null_deref.ads     M2: Not-null assertion
├── template_not_null_deref.adb
├── template_channel_fifo.ads       M3: Protected object FIFO
├── template_channel_fifo.adb
├── template_task_decl.ads          M3: Task type with priority
├── template_task_decl.adb
├── template_index_safety.ads       M4: Safe array indexing
├── template_index_safety.adb
├── template_effect_summary.ads     M5: Global/Depends/Initializes
├── template_effect_summary.adb
├── template_package_structure.ads  M5: ads/adb split + interleaved decls
├── template_package_structure.adb
├── template_select_polling.ads     M6: Select-to-polling-loop
├── template_select_polling.adb
├── template_fp_safety.ads          M6: Floating-point narrowing
├── template_fp_safety.adb
├── template_borrow_observe.ads     M6: Borrow + observe ownership
├── template_borrow_observe.adb
├── template_narrow_conversion.ads  M7: Type-conversion narrowing
├── template_narrow_conversion.adb
└── prove_golden.txt                Proof summary golden baseline
```

### 2.1 Dependency Graph

Templates depend on `Safe_Model` (ghost predicates) and `Safe_PO` (proof
obligation procedures) via `Source_Dirs => ("./", "../spark/")`. No external
Alire dependencies are required.

### 2.2 Compiler Switches

| Switch       | Purpose                            |
|-------------|------------------------------------|
| `-gnat2022` | Ada 2022 language level            |
| `-gnatwa`   | All warnings enabled               |
| `-gnatwe`   | Warnings as errors                 |
| `-gnata`    | Enable assertions                  |
| `-gnatVa`   | All validity checks                |
| `-gnatyg`   | GNAT style checks                  |
| `-gnatQ`    | Generate ALI even on errors        |

### 2.3 GNATprove Profile

| Setting               | Value                         |
|----------------------|-------------------------------|
| `--mode`             | `prove`                       |
| `--level`            | `2`                           |
| `--report`           | `all`                         |
| `--warnings`         | `error`                       |
| `--checks-as-errors` | `on` (CI enforcement)         |
| `--prover`           | `cvc5,z3,altergo`             |
| `--timeout`          | `120`                         |

## 3. Milestone Plan

### M0: Baseline + Design Packet
- Create `companion/templates/` directory structure
- Create `alire.toml`, `templates.gpr`, `safe_runtime.ads`
- Create `docs/template_plan.md` (this document) and `docs/template_inventory.md`
- Add `companion/templates/obj/` to `.gitignore`
- Verify `alr build` succeeds with `safe_runtime.ads`

### M1: Arithmetic + Narrowing Templates
- `template_wide_arithmetic.ads/.adb` — Wide intermediate arithmetic with
  narrowing at assignment and return points. Hooks: `Narrow_Return`,
  `Narrow_Assignment`. Expected ~12-15 VCs.
- `template_division_nonzero.ads/.adb` — Safe division, mod, rem with nonzero
  guard. Hooks: `Nonzero`, `Safe_Div`, `Safe_Mod`, `Safe_Rem`. Expected ~8-10 VCs.
- Create `prove_golden.txt` (proof summary baseline)
- Add `templates-verify` CI job parallel to `spark-verify`

### M2: Ownership Templates
- `template_ownership_move.ads/.adb` — Move semantics modeled via ownership
  state tracking. Hooks: `Check_Owned_For_Move`, `Check_Not_Moved`. ~6-8 VCs.
- `template_scope_dealloc.ads/.adb` — Scope-exit deallocation in reverse
  declaration order. Hook: `Check_Not_Moved`.
- `template_not_null_deref.ads/.adb` — Not-null assertion before dereference.
  Hooks: `Not_Null_Ptr`, `Safe_Deref`.

### M3: Channel + Concurrency Templates
- ~~Add `gnat.adc` with Jorvik profile + Sequential elaboration pragmas~~ —
  **Deferred.** Templates verify functional properties using a sequential proof
  model; `gnat.adc` (`pragma Profile(Jorvik)` and
  `pragma Partition_Elaboration_Policy(Sequential)`) is a compiler-output
  artifact generated per `compiler/translation_rules.md` Section 12
  (lines 942-943), not a template artifact. All 184 VCs prove without it.
- `template_channel_fifo.ads/.adb` — Protected object bounded FIFO with
  ceiling priority. Hooks: `Check_Channel_Not_Full`, `Check_Channel_Not_Empty`,
  `Check_Channel_Capacity_Positive`. Expected ~15-25 VCs.
- `template_task_decl.ads/.adb` — Task type with priority, composes with
  channel FIFO. Hook: `Check_Exclusive_Ownership`.

### M4: Hardening + Audit
- `template_index_safety.ads/.adb` — Safe array indexing with bounds
  assertions. Hooks: `Safe_Index`, `Narrow_Indexing`.
- Harden CI: golden diff test, assumption budget check
- Complete `docs/template_inventory.md`
- Create audit bundle: VC counts, assumption ledger, traceability matrix

### M5: Effect Summaries + Package Structure
- `template_effect_summary.ads/.adb` — Demonstrates emitter-generated
  `Global`, `Depends`, and `Initializes` aspects on a package with
  package-level state, multiple subprograms with cross-variable data flow,
  and a `Constant_After_Elaboration` variable. This is primarily a Bronze-gate
  template: GNATprove flow analysis verifies the contracts, while proof-mode
  confirms that the runtime behavior is consistent with the declared effects.
  Hooks: none (flow aspects are verified by GNATprove itself, not PO hooks).
  Clauses: 5.2.p5, 5.2.2.p6, 5.2.3.p10, 5.2.4.p11.
  Expected ~4-8 VCs (flow checks dominate; proof VCs from any range checks in
  the example subprograms).
- `template_package_structure.ads/.adb` — Demonstrates the `.ads`/`.adb` split
  pattern, opaque type emission (`type T is private` in visible part, full
  record in private part), and interleaved-declaration-to-declare-block
  lowering. Includes a subprogram whose body uses nested `declare` blocks to
  model Safe's interleaved declarations. Hooks: `Narrow_Parameter` (exercising
  narrowing at a parameter-passing point, currently unexercised).
  Clauses: 3.1.p1, 3.1.p6-p7, 3.2.6.p21-p24, 2.9.p140.
  Expected ~3-6 VCs.
- Verify M1-M4 templates still pass with the new units added
- Update `prove_golden.txt` baseline
- Update `docs/template_inventory.md` with new template entries

### M6: Select Lowering + Floating-Point
- `template_select_polling.ads/.adb` — Demonstrates the select-to-polling-loop
  lowering pattern. Models a two-arm select with ordered channel arms and a
  delay arm. The template uses `Try_Receive`-style non-blocking receives
  (modeled as procedures with Boolean success flags), a `Select_Done` loop
  variable, and a deadline check for the delay arm.
  SPARK constraint: `Ada.Real_Time` and `delay` statements are not provable
  in SPARK mode. The template models the polling structure and arm-priority
  logic sequentially, using a loop with invariant tracking which arms have
  been tested. The timing/delay mechanism is abstracted to a Boolean flag
  (deadline elapsed) whose value is an assumption.
  Hooks: `Check_Channel_Not_Empty` (at each Try_Receive point).
  New assumption required: T-01 "Select polling deadline check is faithful
  to wall-clock elapsed time" (severity: minor, category: B).
  Clauses: 4.4.p32-p44 (select semantics), 4.4.p39 (polling pattern),
  4.4.p41 (arm priority), 4.4.p42 (no-delay variant).
  Expected ~8-15 VCs (loop invariant for arm ordering, assertions for
  Select_Done termination, preconditions on Try_Receive calls).
- `template_fp_safety.ads/.adb` — Demonstrates floating-point narrowing
  patterns: not-NaN check, not-infinity check, and safe FP division. Models
  the emission pattern where the compiler inserts FP safety assertions at
  narrowing points, mirroring the integer narrowing pattern from M1.
  Hooks: `FP_Not_NaN`, `FP_Not_Infinity`, `FP_Safe_Div`.
  Clauses: 2.8.5.p139-p139e, 5.3.7a.p28a.
  Expected ~6-10 VCs.
- `template_borrow_observe.ads/.adb` — Demonstrates borrow and observe
  ownership patterns. Models exclusive borrow (mutable temporary lend) and
  shared observe (read-only temporary lend), exercising the two remaining
  unexercised ownership PO hooks.
  Hooks: `Check_Borrow_Exclusive`, `Check_Observe_Shared`.
  Clauses: 2.3.3.p99b (borrow), 2.3.4a.p102a (observe).
  Expected ~4-8 VCs.
- Update `prove_golden.txt` baseline
- Update `docs/template_inventory.md` with new template entries
- Update `docs/traceability_matrix.md` with new clause coverage
- Verify assumption budget remains within limits (target: <=15 total)

### M7: Narrowing Completeness + Final Audit
- `template_narrow_conversion.ads/.adb` — Demonstrates narrowing at the
  type-conversion point, exercising the last unexercised narrowing hook.
  Hooks: `Narrow_Conversion`.
  Clauses: 2.8.1.p127, 2.8.1.p130.
  Expected ~3-5 VCs.
- Final PO hook coverage audit: confirm all 23 Safe_PO procedures are
  exercised by at least one template.
- Final `docs/template_inventory.md` update with complete VC counts.
- Final `prove_golden.txt` baseline update.
- Final audit bundle: complete coverage matrix, assumption ledger,
  traceability matrix update, CI verification.

## 4. Clause Traceability

Each template traces to specific D27 specification clauses:

| Template                  | D27 Rule | Clauses                     |
|--------------------------|----------|-----------------------------|
| `template_wide_arithmetic` | Rule 1   | 2.8.1.p126-p130, 5.3.6.p25 |
| `template_division_nonzero`| Rule 3   | 2.8.3.p133-p134, 5.3.1.p12 |
| `template_ownership_move`  | §2.3     | 2.3.2.p96a-p96c, 2.3.5.p104|
| `template_scope_dealloc`   | §2.3     | 2.3.5.p104, 2.3.2.p96c     |
| `template_not_null_deref`  | Rule 4   | 2.8.4.p136, 5.3.1.p12      |
| `template_channel_fifo`    | §4.2-4.3 | 4.2.p15, 4.3.p27-p31       |
| `template_task_decl`       | §4.5     | 4.5.p45, 5.4.1.p32-p33     |
| `template_index_safety`    | Rule 2   | 2.8.2.p131-p132, 5.3.1.p12 |
| `template_effect_summary`  | §5.2     | 5.2.p5, 5.2.2.p6, 5.2.3.p10, 5.2.4.p11 |
| `template_package_structure`| §3.1    | 3.1.p1, 3.1.p6-p7, 3.2.6.p21-p24, 2.9.p140 |
| `template_select_polling`  | §4.4     | 4.4.p32-p44, 4.4.p39, 4.4.p41-p42 |
| `template_fp_safety`       | Rule 5   | 2.8.5.p139-p139e, 5.3.7a.p28a |
| `template_borrow_observe`  | §2.3     | 2.3.3.p99b, 2.3.4a.p102a |
| `template_narrow_conversion`| Rule 1  | 2.8.1.p127, 2.8.1.p130 |

## 5. Assumption Governance

The companion assumption baseline is tracked in `companion/assumptions.yaml`.
Templates may introduce new assumptions (prefixed `T-xx`). The total budget
is 13-15 assumptions across the entire companion + templates suite.

New template assumptions require:
1. Documentation in `assumptions.yaml` with clause reference
2. CI gate via `scripts/diff_assumptions.sh`
3. Review approval before baseline update

## 6. Risk Register

| Risk                          | Mitigation                                           |
|-------------------------------|------------------------------------------------------|
| SPARK restricts access types  | Model ownership via Boolean flags (M2)               |
| Proof fragility at level 2    | Escalate to level 3 or add loop invariants           |
| Jorvik breaks existing proofs | Verify M1/M2 pass before M3 additions                |
| CI runtime explosion          | Separate `templates-verify` job, cache GNATprove     |
| Assumption creep              | Budget of 13-15, CI-gated diff                       |
| Template-translation drift    | Each template references `translation_rules.md`      |
| Select timing not provable    | Abstract deadline to Boolean flag; track as T-01 (M6)|
| FP solver difficulty          | CVC5/Z3 FP theory; escalate to level 3 if needed    |
| Polling loop termination      | Loop invariant + bounded iteration or pragma variant |
| Declare-block nesting depth   | Limit example to 2-3 levels; mirrors typical Safe src|
