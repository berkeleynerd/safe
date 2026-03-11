# SafeC Frontend

This workspace hosts the current pre-PR07 Safe compiler frontend baseline established by PR06.9.1 through PR06.9.13.

## Current Boundary

- `safec lex <file.safe>` lexes a Safe source file and writes versioned token JSON to stdout.
- `safec ast <file.safe>` lexes and parses a Safe source file and writes AST JSON to stdout.
- `safec validate-mir <file.mir.json>` validates emitted `mir-v1` / `mir-v2` structure in Ada and exits nonzero on structural contract failures.
- `safec analyze-mir <file.mir.json>` validates analyzable `mir-v2` input and exits nonzero if MIR-level diagnostics are emitted.
- `safec analyze-mir --diag-json <file.mir.json>` writes `diagnostics-v0` JSON for a `mir-v2` input.
- `safec check <file.safe>` runs the Ada-native PR05/PR06 check pipeline and exits nonzero if diagnostics are emitted.
- `safec check --diag-json <file.safe>` writes `diagnostics-v0` JSON for the Ada-native PR05/PR06 check pipeline.
- `safec emit <file.safe> --out-dir <dir> --interface-dir <dir>` writes the current frontend artifacts for downstream inspection and regression checks.

The current frontend supports PR05/PR06 sequential Rule 1-4 plus sequential ownership only.

That current boundary includes:

- schema-true AST emission for the implemented subset
- `typed-v2`, self-sufficient `mir-v2`, and `safei-v0` emission for that subset
- Ada-native MIR validation and MIR analysis for that subset
- Ada-native `check` over the PR05 Rule 1-4 corpus and the PR06 sequential ownership corpus

All current user-facing `safec` commands are Ada-native for that subset. Python remains glue/orchestration only around the compiler.

PR06.9.12 is a cliff-detection gate, not a benchmark commitment, for that current frontend subset.

See [`../docs/frontend_architecture_baseline.md`](../docs/frontend_architecture_baseline.md) for the canonical frontend boundary and [`../docs/frontend_scale_limits.md`](../docs/frontend_scale_limits.md) for the current cliff-detection scale policy.

## Current Doctrine

- Ubuntu/Linux CI and local macOS are the supported environments for the current frontend.
- Windows is explicitly unsupported for PR06.9.x.
- On macOS, repo glue assumes an SDK is discoverable through `xcrun --show-sdk-path` or `SDKROOT`.
- Portability-sensitive repo glue uses PATH-based command discovery instead of hard-coded tool paths.
- Portability-sensitive gates use deterministic TemporaryDirectory prefixes for stable temp roots and evidence.
- Portability-sensitive glue scripts remain shell-free and do not rely on `shell=True` or `os.system`.
- Active Python glue is orchestration/validation only and stays argv-based.
- Safe source may only be read by glue scripts for fixture metadata extraction or inline negative/control cases, never as a second semantic source of truth.
- The recovery note in `../docs/macos_alire_toolchain_repair.md` is a developer recovery procedure, not a compiler runtime dependency.
- No-Python runtime enforcement covers `python`, `python3`, `python3.11`, `python3.<minor>`, and path-qualified Python invocations in compiler runtime sources.

The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.

The only live frontend path is now the Ada-native `Check_*` plus `Mir_*` pipeline, with `Lexer`, `Source`, `Types`, `Diagnostics`, and `Json` supporting that path.

PR07 must extend the live `Check_*` + `Mir_*` pipeline.

Unsupported-feature classification rule:
- `unsupported_source_construct` means the Ada-native frontend recognized a construct that is outside the current PR05/PR06 subset.
- `source_frontend_error` means a true frontend failure inside the current subset boundary, such as malformed syntax, bad package end names, missing identifiers, or oversized integer literals.
- The PR06.9.6 gate proves those classifications and also proves unsupported `emit` calls do not write partial artifacts.

## Dependency Policy

PR06.5 intentionally adopts `GNATCOLL.JSON` for Ada-side JSON parsing in `safec validate-mir`.
This dependency is accepted for the current compiler workspace because it removes Python from one
real contract gate without reopening parser/analyzer work. It is not a license decision for the
entire repository, and any broader reuse or future distribution-policy change should revisit this
dependency explicitly rather than allowing it to spread by default.

## Output Formats

`safec lex` currently writes one JSON artifact to stdout:

- token dump
  Format tag: `tokens-v0`.
  Contents: `tokens[]`, where each token includes `kind`, `lexeme`, and `span`.
  Notes: the synthetic EOF token is intentionally omitted so the dump remains source-derived.
  Compatibility: incompatible changes require a new format tag.

`safec emit` currently writes four JSON artifacts:

- `<stem>.ast.json`
  Format: parser AST shaped to the contract in `compiler/ast_schema.json`.
  Validation path: `python3 scripts/validate_ast_output.py` as repo glue around the Ada-native `safec ast` / `safec emit` path.

- `<stem>.typed.json`
  Format tag: `typed-v2`.
  Contents: package identity, resolved type inventory, executable summaries, public declarations, the AST snapshot used to derive lowering and diagnostics, and ownership-oriented access-role metadata for the sequential ownership model.

- `<stem>.mir.json`
  Format tag: `mir-v2`.
  Contents: `source_path`, resolved `types[]`, package-level graph data, deterministic locals tables, `scopes[]`, blocks with `active_scope_id`, typed ops, explicit terminators, graph `return_type`, and ownership-effect metadata for the implemented sequential subset.
  Validation path: `safec validate-mir <stem>.mir.json`.
  Status: debug and regression artifact for the current sequential platform. Incompatible structural changes require a format-tag bump.

- `<stem>.safei.json`
  Format tag: `safei-v0`.
  Contents:
  - `package_name`
  - `public_declarations[]`
  - `executables[]`
  Each summary entry includes `name`, `kind`, `signature`, and `span`.

`safei-v0` is the versioned dependency-interface seed for later cross-unit resolution and interprocedural analysis. If the schema changes incompatibly, the format tag must change as well.

## Verification

The current smoke path is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_frontend_smoke.py
python3 scripts/validate_execution_state.py
```

The smoke run checks lexer regressions for current and legacy two-character operators, AST validation, representative sequential `check` runs, deterministic repeated `emit` output, and records results in `execution/reports/pr00-pr04-frontend-smoke.json`.

The PR05 D27 gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr05_d27_harness.py
```

That harness diffs the four canonical diagnostics goldens byte-for-byte, runs the full current Rule 1-4 corpus gate, verifies deterministic repeated `emit` output on loop and short-circuit samples, and records results in `execution/reports/pr05-d27-report.json`.
It also validates representative MIR artifacts and drives corpus reason matching through `safec check --diag-json` rather than parsing human stderr.

The PR06 ownership gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr06_ownership_harness.py
```

That harness diffs the committed ownership diagnostics goldens byte-for-byte, runs the sequential ownership corpus gate, validates representative `typed-v2`/`mir-v2` outputs, checks deterministic repeated `emit` output on ownership samples, and records results in `execution/reports/pr06-ownership-report.json`.

The PR06.5 Ada MIR validation gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr065_ada_mir_validator.py
```

That gate validates committed `mir-v1` / `mir-v2` fixtures plus representative emitted MIR from the PR05 and PR06 corpora, and records results in `execution/reports/pr065-ada-mir-validator-report.json`.

The PR06.6 MIR analyzer gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr066_ada_mir_analyzer.py
```

That gate runs committed `analyze-mir` fixtures for no-diagnostic, PR05, and PR06 cases, checks invalid-input rejection, confirms emitted PR05 / PR06 MIR stays clean under `safec analyze-mir --diag-json`, reruns the existing PR05 / PR06 harnesses unchanged, and records results in `execution/reports/pr066-ada-mir-analyzer-report.json`.

The PR06.7 Ada check cutover gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr067_ada_check_cutover.py
```

That gate masks `python3` on `PATH` specifically for accidental `safec check` backend spawns, proves representative direct PR05 / PR06 checks still pass, reruns the existing PR05 / PR06 harnesses with that masked check path, verifies deterministic `unsupported_source_construct` rejection for out-of-subset sources, and records results in `execution/reports/pr067-ada-check-cutover-report.json`.

PR06.7 no-Python guarantee: Python may still run the gate script and the unchanged harnesses around `safec check`, but `safec check` itself must stay Ada-native and must not spawn the Python backend.

The PR06.8 Ada `ast` / `emit` cutover gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr068_ada_ast_emit_no_python.py
```

That gate masks `python` and `python3` on `PATH` for direct `safec ast` and `safec emit` invocations, validates the emitted AST through the existing validator script, checks deterministic repeated `emit` output on representative samples, verifies emitted MIR stays valid and analyzable, confirms `emit` writes no artifacts when diagnostics exist, adds direct package-global lowering regressions plus CFG termination checks, and records results in `execution/reports/pr068-ada-ast-emit-no-python-report.json`.

PR06.8 no-Python guarantee: Python may still run the gate script and validation helpers around the compiler, but no `safec` command may spawn Python at runtime. CI enforces this through `PATH` masking for direct compiler invocations rather than by removing Python from the runner entirely.

The PR06.9.1 semantic correctness hardening gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr0691_semantic_correctness.py
```

That gate revalidates range, ownership, return, and call semantics across targeted PR05 / PR06 seam cases, proves representative positive sources stay clean under both `safec check --diag-json` and emitted `safec analyze-mir --diag-json`, preserves primary reasons for representative negative sources, cross-checks committed analyzer fixtures against paired source failures, adds inline package-global semantic regressions, and records results in `execution/reports/pr0691-semantic-correctness-report.json`.

The PR06.9.2 lowering/CFG integrity gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr0692_lowering_cfg_integrity.py
```

That gate proves package-global visibility, declaration-init semantics, scope metadata, and CFG termination invariants on emitted MIR beyond schema validity, and records results in `execution/reports/pr0692-lowering-cfg-integrity-report.json`.

The PR06.9.3 runtime-boundary hardening gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr0693_runtime_boundary.py
```

That gate masks `python` and `python3` on `PATH` for every direct user-facing `safec` command, proves the CLI still behaves correctly for representative success and failure cases, confirms the blocked-spawn log stays empty, and records results in `execution/reports/pr0693-runtime-boundary-report.json`.
