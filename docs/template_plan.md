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
├── gnat.adc                        M3: Jorvik profile pragmas
└── prove_golden.txt                M1: Proof summary golden baseline
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
| `--warnings`         | `on`                          |
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
- Add `gnat.adc` with Jorvik profile + Sequential elaboration pragmas
- Verify M1/M2 templates still pass under Jorvik
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
