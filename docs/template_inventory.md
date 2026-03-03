# Verified Emission Templates — Inventory

**Status:** Complete
**Updated:** 2026-03-03

## Template Summary

| # | Template                    | Milestone | PO Hooks                                          | VCs | Status   |
|---|-----------------------------|-----------|----------------------------------------------------|-----|----------|
| 1 | `template_wide_arithmetic`  | M1        | `Narrow_Return`, `Narrow_Assignment`               | 14  | Proved   |
| 2 | `template_division_nonzero` | M1        | `Nonzero`, `Safe_Div`, `Safe_Mod`, `Safe_Rem`      | 17  | Proved   |
| 3 | `template_ownership_move`   | M2        | `Check_Owned_For_Move`, `Check_Not_Moved`           | 3   | Proved   |
| 4 | `template_scope_dealloc`    | M2        | `Check_Owned_For_Move`, `Check_Not_Moved`           | 7   | Proved   |
| 5 | `template_not_null_deref`   | M2        | `Not_Null_Ptr`, `Safe_Deref`                        | 7   | Proved   |
| 6 | `template_channel_fifo`     | M3        | `Check_Channel_Not_Full/Empty/Capacity_Positive`    | 10  | Proved   |
| 7 | `template_task_decl`        | M3        | `Check_Exclusive_Ownership`                          | 12  | Proved   |
| 8 | `template_index_safety`     | M4        | `Safe_Index`, `Narrow_Indexing`                      | 14  | Proved   |

**Total template VCs: 84** (all proved)

## Proof Summary

172 total VCs across 11 units (Safe_Model, Safe_PO, Safe_Runtime, 8 templates):
- Flow (Bronze): 53 checks (31%) — all passed
- Proof (Silver): 118 checks (69%) — all proved (CVC5 99%, Trivial 1%)
- Justified: 1 (FP_Safe_Div float overflow, see A-05)
- Unproved: 0

| Template                    | Flow | Proof | Total | Provers |
|-----------------------------|------|-------|-------|---------|
| `template_wide_arithmetic`  | 4    | 14    | 18    | CVC5    |
| `template_division_nonzero` | 4    | 17    | 21    | CVC5    |
| `template_ownership_move`   | 2    | 3     | 5     | CVC5    |
| `template_scope_dealloc`    | 2    | 7     | 9     | CVC5    |
| `template_not_null_deref`   | 2    | 7     | 9     | CVC5    |
| `template_channel_fifo`     | 4    | 10    | 14    | CVC5    |
| `template_task_decl`        | 2    | 12    | 14    | CVC5    |
| `template_index_safety`     | 2    | 14    | 16    | CVC5    |

## Max Steps

Max steps used for successful proof: 2 (well within budget).

## Assumption Ledger (Template-specific)

No template-specific assumptions were required. All 8 templates prove
under the existing companion assumptions (see `companion/assumptions.yaml`).

| ID | Description | Clause | Introduced |
|----|-------------|--------|------------|
| —  | (none)      | —      | —          |
