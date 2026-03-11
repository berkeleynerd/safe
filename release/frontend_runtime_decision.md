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

Before `PR07`, the roadmap now inserts a `PR06.9.1` through `PR06.9.13` stabilization series covering semantic correctness, lowering/CFG integrity, runtime-boundary enforcement, output and diagnostic stability, unsupported-feature handling, gate quality, dormant legacy package cleanup, reproducibility, portability assumptions, glue-script safety, performance sanity, and documentation clarity.

`PR07` Rule 5 and discriminant/result safety work now follows that hardening series rather than starting immediately after PR06.8.

CI enforcement note: the PR06.7 and PR06.8 jobs still use Python to run gate scripts and validators, but those gates enforce the runtime boundary through `PATH` masking for direct `safec` invocations. PR06.8 masks both `python` and `python3`, and the jobs fail if `check`, `ast`, or `emit` attempt to spawn a Python backend.

PR06.9.3 extends that policy with a fast static denylist in `scripts/validate_execution_state.py` and a full-CLI masked-runtime gate for `lex`, `ast`, `validate-mir`, `analyze-mir`, `check`, and `emit`. The runtime rule is now explicit: those user-facing `safec` commands are Ada-native surfaces, while Python remains allowed only as glue around the compiler.

PR06.9.6 makes the unsupported-feature boundary explicit across the Ada-native frontend surfaces:
- `unsupported_source_construct` is reserved for recognized constructs that are outside the current PR05/PR06 subset.
- `source_frontend_error` remains the reason for genuine frontend failures such as malformed syntax, identifier/package-name mismatches, and oversized literals.
- `check`, `ast`, and `emit` are all regression-covered so unsupported inputs fail consistently and never leak into partial lowering or emitted artifacts.

PR06.9.8 removes the old shallow `Safe_Frontend.Ast` / `Parser` / `Semantics` / `Mir` chain from the tree entirely. The only live compiler frontend path is the Ada-native `Check_*` plus `Mir_*` pipeline, and later milestones must extend that live path instead of reintroducing the deleted legacy chain.

PR06.9.10 makes the platform policy explicit:
- Ubuntu/Linux CI and local macOS are the supported environments for the current frontend.
- Windows is explicitly unsupported for PR06.9.x.
- On macOS, repo glue assumes an SDK is discoverable through `xcrun --show-sdk-path` or `SDKROOT`.
- Portability-sensitive repo glue uses PATH-based command discovery instead of hard-coded tool paths.
- Portability-sensitive gates use deterministic TemporaryDirectory prefixes for stable temp roots and evidence.
- Portability-sensitive glue scripts remain shell-free and do not rely on `shell=True` or `os.system`.
- Active Python glue remains argv-based orchestration and validation only.
- Glue scripts may read `.safe` files only for fixture metadata extraction or inline temporary negative/control cases, never to duplicate compiler semantics.
- The note in `docs/macos_alire_toolchain_repair.md` is a developer recovery procedure, not a compiler runtime dependency.
- No-Python runtime enforcement covers `python`, `python3`, `python3.11`, `python3.<minor>`, and path-qualified Python invocations in compiler runtime sources.

PR06.9.11 turns that glue policy into an audited invariant:
- active Python glue stays argv-based and shell-free
- tempdir, subprocess, tool lookup, and report-writing paths are centralized and deterministic
- Python glue may orchestrate and validate, but it may not become a second semantic source of truth for Safe source
