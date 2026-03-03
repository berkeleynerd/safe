# Verified Emission Templates

This directory contains 8 SPARK 2022 packages that demonstrate, and formally
verify, the Ada/SPARK code shapes a Safe compiler emitter must produce. Each
template is a concrete, stand-alone package (no generics) that a compiler
instantiates by substituting application-specific types, bounds, and constants
into its public API.

## How the compiler emitter uses these templates

A Safe compiler translates Safe source into Ada/SPARK by assembling fragments
that correspond to the patterns proved here. The emitter does **not** generate
arbitrary SPARK. Instead, for each Safe construct it:

1. Selects the matching template (e.g. `Template_Wide_Arithmetic` for integer
   expressions, `Template_Channel_FIFO` for channel declarations).
2. Substitutes concrete types and bounds into the template's public API slots
   (subtypes, capacity constants, range bounds).
3. Emits the resulting Ada code, which inherits the proof guarantees
   established by GNATprove over the template.

The mapping from Safe constructs to templates is defined in
[`compiler/translation_rules.md`](../../compiler/translation_rules.md).

## Template inventory

| Template | D27 Rule | Emission pattern | PO hooks |
|----------|----------|-----------------|----------|
| `template_wide_arithmetic` | Rule 1 | Wide intermediate arithmetic + narrowing at assignment/return | `Narrow_Return`, `Narrow_Assignment` |
| `template_division_nonzero` | Rule 3 | Safe division, mod, rem with nonzero guard | `Nonzero`, `Safe_Div`, `Safe_Mod`, `Safe_Rem` |
| `template_ownership_move` | Section 2.3 | Ownership transfer via move semantics | `Check_Owned_For_Move`, `Check_Not_Moved` |
| `template_scope_dealloc` | Section 2.3 | Scope-exit deallocation in reverse declaration order | `Check_Owned_For_Move`, `Check_Not_Moved` |
| `template_not_null_deref` | Rule 4 | Not-null assertion before pointer dereference | `Not_Null_Ptr`, `Safe_Deref` |
| `template_channel_fifo` | Section 4.2-4.3 | Bounded FIFO channel (protected object model) | `Check_Channel_Not_Full`, `Check_Channel_Not_Empty`, `Check_Channel_Capacity_Positive` |
| `template_task_decl` | Section 4.5 | Task-variable exclusive ownership | `Check_Exclusive_Ownership` |
| `template_index_safety` | Rule 2 | Safe array indexing with bounds assertion | `Safe_Index`, `Narrow_Indexing` |

Each `.ads` file carries clause IDs in its header comment tracing to the
frozen spec commit (`4aecf21`).

## Dependencies

Templates depend only on packages from `companion/spark/`:

- **`Safe_Model`** -- Ghost predicates and types (ownership state, range
  bounds, task-variable maps)
- **`Safe_PO`** -- Proof obligation procedures that the emitter inserts at
  runtime-check sites
- **`Safe_Runtime`** -- `Wide_Integer` type definition for wide intermediate
  arithmetic

No external Alire dependencies are required. The project file
(`templates.gpr`) pulls in `companion/spark/` via `Source_Dirs`.

## Building and proving locally

```bash
cd companion/templates

# Compile
alr build

# GNATprove flow analysis (Bronze gate)
alr exec -- gnatprove -P templates.gpr --mode=flow --report=all --warnings=on

# GNATprove proof (Silver gate)
alr exec -- gnatprove -P templates.gpr \
  --mode=prove --level=2 \
  --prover=cvc5,z3,altergo \
  --steps=0 --timeout=120 \
  --report=all --warnings=on --checks-as-errors=on
```

## Proof status

178 total VCs across 11 units, 0 unproved. The checked-in baseline is
`prove_golden.txt`. CI diffs every run against this baseline and fails on
drift.

## Assumptions

No template-specific assumptions were introduced. All 8 templates prove under
the existing companion assumptions tracked in
[`companion/assumptions.yaml`](../assumptions.yaml).

## Further reading

- [`docs/template_plan.md`](../../docs/template_plan.md) -- Design document
  with milestones, risk register, and reviewer packet
- [`docs/template_inventory.md`](../../docs/template_inventory.md) -- Full
  proof inventory with per-template VC counts
- [`compiler/translation_rules.md`](../../compiler/translation_rules.md) --
  Safe-to-Ada translation reference (14 sections)
