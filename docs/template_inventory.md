# Verified Emission Templates — Inventory

**Status:** Complete
**Updated:** 2026-03-03

## Template Summary

| # | Template                    | Milestone | PO Hooks                                          | VCs | Status   |
|---|-----------------------------|-----------|----------------------------------------------------|-----|----------|
| 1 | `template_wide_arithmetic`  | M1        | `Narrow_Return`, `Narrow_Assignment`               | 16  | Proved   |
| 2 | `template_division_nonzero` | M1        | `Nonzero`, `Safe_Div`, `Safe_Mod`, `Safe_Rem`      | 17  | Proved   |
| 3 | `template_ownership_move`   | M2        | `Check_Owned_For_Move`, `Check_Not_Moved`           | 3   | Proved   |
| 4 | `template_scope_dealloc`    | M2        | `Check_Owned_For_Move`, `Check_Not_Moved`           | 13  | Proved   |
| 5 | `template_not_null_deref`   | M2        | `Not_Null_Ptr`, `Safe_Deref`                        | 7   | Proved   |
| 6 | `template_channel_fifo`     | M3        | `Check_Channel_Not_Full/Empty/Capacity_Positive`    | 13  | Proved   |
| 7 | `template_task_decl`        | M3        | `Check_Exclusive_Ownership`                          | 12  | Proved   |
| 8 | `template_index_safety`     | M4        | `Safe_Index`, `Narrow_Indexing`                      | 14  | Proved   |

**Total template VCs: 95** (all proved)

## Proof Summary

184 total VCs across 11 units (Safe_Model, Safe_PO, Safe_Runtime, 8 templates):
- Flow (Bronze): 54 checks (29%) — all passed
- Proof (Silver): 129 checks (70%) — all proved (CVC5 99%, Trivial 1%)
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

## Max Steps

Max steps used for successful proof: 2 (well within budget).

## Assumption Ledger (Template-specific)

No template-specific assumptions were required. All 8 templates prove
under the existing companion assumptions (see `companion/assumptions.yaml`).

| ID | Description | Clause | Introduced |
|----|-------------|--------|------------|
| —  | (none)      | —      | —          |

## Coverage Boundary (M0–M4 vs M5–M7)

This inventory covers the **M0–M4 template suite**. The table below maps
`compiler/translation_rules.md` sections to template coverage status.

**Covered by M0–M4 templates:**

| Rule / Section | Clauses | Template(s) |
|---------------|---------|-------------|
| Rule 1 — Wide arithmetic & narrowing | 2.8.1.p126-p130, 5.3.6.p25 | `template_wide_arithmetic` |
| Rule 2 — Safe indexing | 2.8.2.p131-p132, 5.3.1.p12 | `template_index_safety` |
| Rule 3 — Safe division | 2.8.3.p133-p134, 5.3.1.p12 | `template_division_nonzero` |
| Rule 4 — Not-null dereference | 2.8.4.p136, 5.3.1.p12 | `template_not_null_deref` |
| §2.3 — Ownership (move, scope dealloc) | 2.3.2.p96a-p96c, 2.3.5.p104 | `template_ownership_move`, `template_scope_dealloc` |
| §4.2-4.3 — Channel FIFO | 4.2.p15, 4.3.p27-p31 | `template_channel_fifo` |
| §4.5 — Task declaration | 4.5.p45, 5.4.1.p32-p33 | `template_task_decl` |

**Deferred to M5–M7 (see `docs/template_plan.md`):**

| Rule / Section | Clauses | Planned Template | Milestone |
|---------------|---------|-----------------|-----------|
| §5.2 — Effect summaries | 5.2.p5, 5.2.2.p6, 5.2.3.p10, 5.2.4.p11 | `template_effect_summary` | M5 |
| §3.1 — Package structure | 3.1.p1, 3.1.p6-p7, 3.2.6.p21-p24, 2.9.p140 | `template_package_structure` | M5 |
| §4.4 — Select polling | 4.4.p32-p44, 4.4.p39, 4.4.p41-p42 | `template_select_polling` | M6 |
| Rule 5 — FP safety | 2.8.5.p139-p139e, 5.3.7a.p28a | `template_fp_safety` | M6 |
| §2.3 — Borrow & observe | 2.3.3.p99b, 2.3.4a.p102a | `template_borrow_observe` | M6 |
| Rule 1 — Narrow conversion | 2.8.1.p127, 2.8.1.p130 | `template_narrow_conversion` | M7 |
