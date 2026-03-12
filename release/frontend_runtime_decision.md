# Frontend Runtime Decision

## Decision

Python is glue/orchestration only.

No user-facing `safec` command depends on Python at runtime.

## Current Frontend Boundary

The current frontend supports the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern.

Ada-native runtime commands:

- `safec lex`
- `safec ast`
- `safec validate-mir`
- `safec analyze-mir`
- `safec check`
- `safec emit`

Python is glue/orchestration only.

Current environment policy:

- Ubuntu/Linux CI and local macOS are the supported environments for the current frontend.
- Windows is explicitly unsupported for PR06.9.x.
- Omitted task `Priority` aspects currently lower to the documented frontend default priority `31` so emitted typed/MIR artifacts remain stable across the supported hosts; explicit priorities are still checked against `System.Any_Priority`.
- On macOS, repo glue assumes an SDK is discoverable through `xcrun --show-sdk-path` or `SDKROOT`.
- Portability-sensitive repo glue uses PATH-based command discovery instead of hard-coded tool paths.
- Portability-sensitive gates use deterministic TemporaryDirectory prefixes for stable temp roots and evidence.
- Portability-sensitive glue scripts remain shell-free and do not rely on `shell=True` or `os.system`.
- Active Python glue remains argv-based orchestration and validation only.
- Glue scripts may read `.safe` files only for fixture metadata extraction or inline temporary negative/control cases, never to duplicate compiler semantics.
- The note in `../docs/macos_alire_toolchain_repair.md` is a developer recovery procedure, not a compiler runtime dependency.
- No-Python runtime enforcement covers `python`, `python3`, `python3.11`, `python3.<minor>`, and path-qualified Python invocations in compiler runtime sources.

The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.

The only live compiler frontend path is the Ada-native `Check_*` plus `Mir_*` pipeline, with `Lexer`, `Source`, `Types`, `Diagnostics`, and `Json` supporting that path.

See [`../docs/frontend_architecture_baseline.md`](../docs/frontend_architecture_baseline.md) for the canonical boundary statement and [`../docs/frontend_scale_limits.md`](../docs/frontend_scale_limits.md) for the current scale policy.

## PR07 Baseline

PR06.9.1 through PR06.9.13 established the hardened pre-PR07 baseline, and PR07 extends that same live path.

PR08 starts from this cleaned PR07 baseline and must extend the live path rather than revive deleted legacy packages.
