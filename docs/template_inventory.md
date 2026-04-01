# Verified Emission Templates — Inventory

**Status:** Complete
**Updated:** 2026-04-01

## Template Summary

| # | Template                    | Milestone | PO Hooks                                          | VCs\* | Status   |
|---|-----------------------------|-----------|----------------------------------------------------|-------|----------|
| 1 | `template_wide_arithmetic`  | M1        | `Narrow_Return`, `Narrow_Assignment`               | 16  | Proved   |
| 2 | `template_division_nonzero` | M1        | `Nonzero`, `Safe_Div`, `Safe_Mod`, `Safe_Rem`      | 17  | Proved   |
| 3 | `template_ownership_move`   | M2        | `Check_Owned_For_Move`, `Check_Not_Moved`           | 3   | Proved   |
| 4 | `template_scope_dealloc`    | M2        | `Check_Owned_For_Move`, `Check_Not_Moved`           | 13  | Proved   |
| 5 | `template_not_null_deref`   | M2        | `Not_Null_Ptr`, `Safe_Deref`                        | 7   | Proved   |
| 6 | `template_channel_fifo`     | M3        | `Check_Channel_Not_Full/Empty/Capacity_Positive`    | 13  | Proved   |
| 7 | `template_task_decl`        | M3        | `Check_Exclusive_Ownership`                          | 12  | Proved   |
| 8 | `template_index_safety`     | M4        | `Safe_Index`, `Narrow_Indexing`                      | 14  | Proved   |
| 9 | `template_effect_summary`   | M5        | (none -- flow-analysis template)                     | 3   | Proved   |
| 10| `template_package_structure` | M5       | `Narrow_Parameter`                                   | 6   | Proved   |
| 11| `template_borrow_observe`   | M6       | `Check_Borrow_Exclusive`, `Check_Observe_Shared`     | 13  | Proved   |
| 12| `template_fp_safety`        | M6       | `FP_Not_NaN`, `FP_Not_Infinity`, `FP_Safe_Div`       | 17  | Proved   |
| 13| `template_select_dispatcher`| M6       | `Check_Channel_Not_Empty`                             | 32  | Proved   |
| 14| `template_narrow_conversion`| M7       | `Narrow_Conversion`                                   | 17  | Proved   |

\* VCs = proof checks discharged by SMT provers (Silver level); flow
checks (Bronze level) are reported separately in the Proof Summary below.

**Total template proof VCs: 183** (all proved)

## Proof Summary

325 total VCs across 17 units (Safe_Model, Safe_PO, Safe_Runtime, 14 templates):
- Flow (Bronze): 107 checks (33%) — all passed
- Proof (Silver): 217 proved + 1 justified (67%) (CVC5 99%, Trivial 1%)
- Justified: 1 (FP_Safe_Div float overflow, see A-05)
- Unproved: 0

| Template                    | Flow | Proof | Total | Provers |
|-----------------------------|------|-------|-------|---------|
| `template_wide_arithmetic`  | 2    | 16    | 18    | CVC5    |
| `template_division_nonzero` | 4    | 17    | 21    | CVC5    |
| `template_ownership_move`   | 2    | 3     | 5     | CVC5    |
| `template_scope_dealloc`    | 2    | 13    | 15    | CVC5    |
| `template_not_null_deref`   | 2    | 7     | 9     | CVC5    |
| `template_channel_fifo`     | 7    | 13    | 20    | CVC5    |
| `template_task_decl`        | 2    | 12    | 14    | CVC5    |
| `template_index_safety`     | 4    | 14    | 18    | CVC5    |
| `template_effect_summary`   | 19   | 3     | 22    | CVC5    |
| `template_package_structure` | 3   | 6     | 9     | CVC5    |
| `template_borrow_observe`   | 7    | 13    | 20    | CVC5    |
| `template_fp_safety`        | 7    | 17    | 24    | CVC5    |
| `template_select_dispatcher`| 14   | 32    | 46    | CVC5    |
| `template_narrow_conversion`| 3    | 17    | 20    | CVC5    |

## Max Steps

Max steps used for successful proof: 2 (well within budget).

## Assumption Ledger (Template-specific)

No template-specific assumptions are currently tracked. The dispatcher-based
select template proves under the baseline companion assumptions in
`companion/assumptions.yaml`.

## Coverage Boundary (M0–M7 Complete)

This inventory covers the **M0–M7 template suite** (all milestones complete).
The table below maps `compiler/translation_rules.md` sections to template
coverage. All 23 `Safe_PO` hooks are exercised.

**Covered by M0–M7 templates:**

| Rule / Section | Clauses | Template(s) |
|---------------|---------|-------------|
| Rule 1 — Wide arithmetic & narrowing | 2.8.1.p126-p130, 5.3.6.p25 | `template_wide_arithmetic` |
| Rule 2 — Safe indexing | 2.8.2.p131-p132, 5.3.1.p12 | `template_index_safety` |
| Rule 3 — Safe division | 2.8.3.p133-p134, 5.3.1.p12 | `template_division_nonzero` |
| Rule 4 — Not-null dereference | 2.8.4.p136, 5.3.1.p12 | `template_not_null_deref` |
| Rule 5 — FP safety | 2.8.5.p139-p139e, 5.3.7a.p28a | `template_fp_safety` |
| §2.3 — Ownership (move, scope dealloc) | 2.3.2.p96a-p96c, 2.3.5.p104 | `template_ownership_move`, `template_scope_dealloc` |
| §2.3 — Borrow & observe | 2.3.3.p99b, 2.3.4a.p102a | `template_borrow_observe` |
| §4.2-4.3 — Channel FIFO | 4.2.p15, 4.3.p27-p31 | `template_channel_fifo` |
| §4.4 — Dispatcher-based select | 4.4.p33-p42 | `template_select_dispatcher` |
| §4.5 — Task declaration | 4.5.p45, 5.4.1.p32-p33 | `template_task_decl` |
| §5.2 — Effect summaries | 5.2.2.p5, 5.2.3.p8, 5.2.4.p11 | `template_effect_summary` |
| §3.1 — Package structure | 3.2.6.p23-p24, 2.9.p140 | `template_package_structure` |
| Rule 1 — Narrow conversion | 2.8.1.p127, 2.8.1.p130 | `template_narrow_conversion` |
