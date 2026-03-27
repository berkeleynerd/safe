# Phase 0 Audit Packet — Milestone 0 Baseline

**Date:** 2026-03-03
**Auditor:** Claude Opus 4.6
**Scope:** Verified Emission Templates baseline audit per archive/TEMPLATE-IMPLEMENTATION-PLAN.md Milestone 0
**Result:** PASS

---

## 1. File Inventory

All required files exist and are properly configured.

| File | Status | Lines | Purpose |
|------|--------|-------|---------|
| `companion/spark/safe_model.ads` | EXISTS | 319 | Ghost model types: Range64, Ownership_State, Channel_State, Task_Var_Map |
| `companion/spark/safe_model.adb` | EXISTS | 55 | Bodies: Assign_Owner, No_Shared_Variables |
| `companion/spark/safe_po.ads` | EXISTS | 365 | 23 proof obligation procedures (D27 Rules 1-5, Ownership, Channels, Race-freedom) |
| `companion/spark/safe_po.adb` | EXISTS | 340 | PO implementations: 4 non-ghost with bodies, 19 ghost with null bodies |
| `companion/templates/templates.gpr` | EXISTS | 30 | GNAT project: Source_Dirs=("./","../spark/"), `--warnings=error` in Prove |
| `companion/templates/alire.toml` | EXISTS | 6 | Alire manifest: name=templates, version=0.1.0 |
| `companion/templates/prove_golden.txt` | EXISTS | 18 | Proof baseline: 184 VCs, 0 unproved |
| `companion/templates/safe_runtime.ads` | EXISTS | 25 | Wide_Integer type (64-bit range) |
| `companion/templates/README.md` | EXISTS | 93 | Emitter usage guide, dependency map |
| `companion/gen/companion.gpr` | EXISTS | 31 | Companion project: `--warnings=error` in Prove |
| `companion/assumptions.yaml` | EXISTS | 220 | 13 tracked assumptions (4 critical, 4 major, 5 minor) |
| `.github/workflows/ci.yml` | EXISTS | 250 | Two-job CI: spark-verify + templates-verify |
| `scripts/run_gnatprove_flow.sh` | EXISTS | 59 | Bronze gate script: `--warnings=error` |
| `scripts/run_gnatprove_prove.sh` | EXISTS | 82 | Silver gate script: `--warnings=error --checks-as-errors=on` |
| `scripts/extract_assumptions.sh` | EXISTS | 128 | Assumption extraction from GNATprove output |
| `scripts/diff_assumptions.sh` | EXISTS | 156 | Budget enforcement: 15 total max, 4 critical max |
| `docs/template_plan.md` | EXISTS | 152 | Design: 4-milestone architecture, clause mapping, risk register |
| `docs/template_inventory.md` | EXISTS | 51 | Proof summary: 8 templates, 95 VCs, all proved |
| `docs/gnatprove_profile.md` | EXISTS | 436 | GNATprove configuration policy |
| `docs/traceability_matrix.md` | EXISTS | 652 | 205 normative clauses mapped to artifacts |
| `compiler/translation_rules.md` | EXISTS | 1466 | Safe-to-Ada translation reference (14 sections) |
| `tests/golden/golden_sensors/` | EXISTS | N/A (directory) | D27 Rule 1: wide arithmetic averaging |
| `tests/golden/golden_ownership/` | EXISTS | N/A (directory) | Section 2.3: ownership move + deallocation |
| `tests/golden/golden_pipeline/` | EXISTS | N/A (directory) | Section 4.2-4.3: channel FIFO + task declarations |

## 2. Template Inventory

| # | Template | Emission Pattern | PO Hooks | Clause IDs | Golden |
|---|----------|-----------------|----------|------------|--------|
| 1 | `template_wide_arithmetic` | Wide intermediate arithmetic + narrowing | `Narrow_Return`, `Narrow_Assignment` | 2.8.1.p126-p130, 5.3.6.p25 | golden_sensors/ |
| 2 | `template_division_nonzero` | Division/mod/rem with nonzero guard | `Nonzero`, `Safe_Div`, `Safe_Mod`, `Safe_Rem` | 2.8.3.p133-p134, 5.3.1.p12 | golden_sensors/ |
| 3 | `template_ownership_move` | Ownership move: copy + null source | `Check_Owned_For_Move`, `Check_Not_Moved` | 2.3.2.p96a-p97a, 2.3.5.p104 | golden_ownership/ |
| 4 | `template_scope_dealloc` | Scope-exit deallocation in reverse order | `Check_Owned_For_Move`, `Check_Not_Moved` | 2.3.5.p104, 2.3.2.p96c | golden_ownership/ |
| 5 | `template_not_null_deref` | Not-null assertion before dereference | `Not_Null_Ptr`, `Safe_Deref` | 2.8.4.p136, 5.3.1.p12 | golden_ownership/ |
| 6 | `template_channel_fifo` | Bounded FIFO: send/receive/capacity | `Check_Channel_Not_Full/Empty/Capacity_Positive` | 4.2.p15-p20, 4.3.p27-p31 | golden_pipeline/ |
| 7 | `template_task_decl` | Task-variable exclusive ownership | `Check_Exclusive_Ownership` | 4.5.p45, 5.4.1.p32-p33 | golden_pipeline/ |
| 8 | `template_index_safety` | Safe array indexing with bounds proof | `Safe_Index`, `Narrow_Indexing` | 2.8.2.p131-p132, 5.3.1.p12 | golden_sensors/ |

## 3. Proof / VC Summary

```
=========================
Summary of SPARK analysis
=========================
SPARK Analysis results        Total        Flow                      Provers   Justified   Unproved
Initialization                   12          12                            .           .          .
Run-time Checks                  35           .                    34 (CVC5)           1          .
Assertions                       15           .                    15 (CVC5)           .          .
Functional Contracts             80           .    80 (CVC5 99%, Trivial 1%)           .          .
Termination                      42          42                            .           .          .
Total                           184    54 (29%)                    129 (70%)      1 (1%)          .

max steps used for successful proof: 2
```

**Result:** 184/184 VCs proved. 0 unproved. Max steps: 2.

Per-template proof VCs:

| Template | Flow | Proof | Total |
|----------|------|-------|-------|
| `template_wide_arithmetic` | 2 | 16 | 18 |
| `template_division_nonzero` | 4 | 17 | 21 |
| `template_ownership_move` | 2 | 3 | 5 |
| `template_scope_dealloc` | 2 | 13 | 15 |
| `template_not_null_deref` | 2 | 7 | 9 |
| `template_channel_fifo` | 7 | 13 | 20 |
| `template_task_decl` | 2 | 12 | 14 |
| `template_index_safety` | 4 | 14 | 18 |

## 4. Commands Run

### Templates project (companion/templates/)

```bash
# Compile
alr build                                                        # OK

# Flow analysis (Bronze gate)
alr exec -- gnatprove -P templates.gpr \
  --mode=flow --report=all --warnings=error                      # OK, 54 flow checks

# Proof (Silver gate)
alr exec -- gnatprove -P templates.gpr \
  --mode=prove --level=2 --prover=cvc5,z3,altergo \
  --steps=0 --timeout=120 --report=all \
  --warnings=error --checks-as-errors=on                         # OK, 184/184 proved
```

### Companion project (companion/gen/)

```bash
alr exec -- gnatprove -P companion.gpr \
  --mode=prove --level=2 --prover=cvc5,z3,altergo \
  --steps=0 --timeout=120 --report=all \
  --warnings=error --checks-as-errors=on                         # OK, 64/64 proved
```

### Assumption governance

```bash
PROVE_GOLDEN=companion/templates/prove_golden.txt \
PROVE_OUT=companion/templates/obj/gnatprove/gnatprove.out \
  bash scripts/diff_assumptions.sh                               # OK, matches golden
```

Output:
```
Tracked assumptions: 13 (4 critical, 4 major, 5 minor)
Proof summary: MATCHES golden baseline.
Budget: within limits.
ASSUMPTION DIFF: OK
```

## 5. CI Parity Check

The `templates-verify` job in `.github/workflows/ci.yml` runs:

| Step | CI Command | Local Equivalent | Match? |
|------|-----------|------------------|--------|
| 1 | `alr build` | `alr build` | YES |
| 2 | `gnatprove -P templates.gpr --mode=flow --report=all --warnings=error` | Same | YES |
| 3 | `gnatprove -P templates.gpr --mode=prove --level=2 --prover=cvc5,z3,altergo --steps=0 --timeout=120 --report=all --warnings=error --checks-as-errors=on` | Same | YES |
| 4 | `scripts/extract_assumptions.sh` (PROVE_OUT=companion/templates/obj/gnatprove) | Same | YES |
| 5 | `scripts/diff_assumptions.sh` (PROVE_GOLDEN=companion/templates/prove_golden.txt) | Same | YES |

**CI enforces `--warnings=error` on all invocations.** Scripts and project files are now consistent.

## 6. Assumption Budget Status

| ID | Summary | Severity | Status |
|----|---------|----------|--------|
| A-01 | 64-bit intermediate integer evaluation | critical | open |
| A-02 | IEEE 754 non-trapping mode | critical | open |
| A-03 | Static range analysis soundness | critical | open |
| A-04 | Channel serialization correctness | critical | open |
| A-05 | FP division result finiteness | major | open (justified) |
| B-01 | Ownership state completeness | major | open |
| B-02 | FIFO ordering preservation | major | open |
| B-03 | Task-variable map coverage | major | open |
| B-04 | Boolean null model fidelity | minor | open |
| C-01 | Flow analysis sufficiency | minor | open |
| C-02 | Ghost erasure correctness | minor | open |
| D-01 | Select polling conformance | minor | open |
| D-02 | Frozen spec commit authority | minor | open |

**Template-specific assumptions:** 0. All templates prove under existing companion assumptions.
**Budget:** 13/15 total, 4/4 critical. Within limits.

## 7. Gaps vs translation_rules.md

| Translation Rule Section | Template Coverage | Gap? |
|--------------------------|-------------------|------|
| Section 4: Channel lowering | `template_channel_fifo` | NO |
| Section 5: Task emission | `template_task_decl` | NO |
| Section 7: Ownership move | `template_ownership_move` | NO |
| Section 8: Wide arithmetic | `template_wide_arithmetic`, `template_index_safety` | NO |
| Section 9: Scope deallocation | `template_scope_dealloc` | NO |
| Section 8.3: Division safety | `template_division_nonzero` | NO |
| Section 8.4: Not-null deref | `template_not_null_deref` | NO |
| Section 6: Floating-point | Covered by `Safe_PO.FP_*` procedures (no template) | DEFERRED |
| Section 10-14: Select, etc. | Not yet templated | DEFERRED |

Sections 6 and 10-14 are deferred per docs/template_plan.md priority ordering. All high-priority emission patterns (Sections 4, 5, 7, 8, 9) have template coverage.

## 8. Conclusion

**Phase 0 / Milestone 0: PASS**

All acceptance criteria from archive/TEMPLATE-IMPLEMENTATION-PLAN.md Milestone 0 are met:
- File inventory complete (24/24 files present)
- Template verification reproduced locally (184/184 VCs, 0 unproved)
- CI parity confirmed (templates-verify job matches local commands)
- Golden proof baseline stable (prove_golden.txt matches output)
- Assumption diff/budget gates pass (13 assumptions, within limits)
- No unaddressed gaps in high-priority translation rules coverage
