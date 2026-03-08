# Frontend Runtime Decision

## Decision

Python is transitional only. The Safe reference compiler must remove the Python execution dependency and converge back to an Ada/SPARK frontend in staged replacement slices.

PR06.5 and PR06.6 removed the MIR validator and MIR analyzer from the Python runtime path, and PR06.7 cut `safec check` over to Ada for the current PR05/PR06 subset.

## Current Runtime Split

- Ada-native:
  - `safec lex`
  - `safec validate-mir`
  - `safec analyze-mir`
  - `safec check` for the current PR05/PR06 subset
- Python-backed reference frontend:
  - `safec ast`
  - `safec emit`

## Locked Replacement Order

1. MIR model and validator
2. MIR analyzer parity
3. Ada-native `safec check` cutover for the current PR05/PR06 subset, including the D27 and ownership renderer
4. Parser, resolver, typed model, and emit pipeline parity

## Rule for Later Milestones

Each later milestone must remove a concrete Python-owned slice. Parity scaffolding without a runtime cutover is not enough to close the Python dependency.

## Immediate Follow-On

With PR06.7 complete, Python remains required only for `ast` and `emit`. Current `PR07` Rule 5 and discriminant/result safety work follows these runtime-reduction milestones.
