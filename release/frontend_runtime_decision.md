# Frontend Runtime Decision

## Decision

Python is transitional only in the compiler runtime. The Safe reference compiler must converge back to an Ada/SPARK frontend in staged replacement slices while permitting Python to remain only as glue/orchestration around the compiler.

PR06.5 and PR06.6 removed the MIR validator and MIR analyzer from the Python runtime path, PR06.7 cut `safec check` over to Ada for the current PR05/PR06 subset, and PR06.8 cuts `safec ast` and `safec emit` over to Ada for that same subset.

## Current Runtime Split

- Ada-native compiler commands:
  - `safec lex`
  - `safec ast`
  - `safec validate-mir`
  - `safec analyze-mir`
  - `safec check` for the current PR05/PR06 subset
  - `safec emit` for the current PR05/PR06 subset
- Python glue still allowed in-repo:
  - harness scripts
  - output validators
  - CI/report orchestration

## Locked Replacement Order

1. MIR model and validator
2. MIR analyzer parity
3. Ada-native `safec check` cutover for the current PR05/PR06 subset, including the D27 and ownership renderer
4. Ada-native `safec ast` / `safec emit` cutover and removal of the backend spawn path

## Rule for Later Milestones

Python may remain as glue/orchestration, but no later milestone may move parser, lowering, semantic analysis, diagnostic selection, or emitted artifact ownership back into Python. Every later milestone must preserve the rule that user-facing `safec` commands are Ada-native runtime surfaces.

## Immediate Follow-On

With PR06.8 complete, no user-facing `safec` command requires Python at runtime. `PR07` Rule 5 and discriminant/result safety work now follows a fully Ada-native compiler command surface for the current PR05/PR06 subset.

CI enforcement note: the PR06.7 and PR06.8 jobs still use Python to run gate scripts and validators, but those gates enforce the runtime boundary through `PATH` masking for direct `safec` invocations. PR06.8 masks both `python` and `python3`, and the jobs fail if `check`, `ast`, or `emit` attempt to spawn a Python backend.
