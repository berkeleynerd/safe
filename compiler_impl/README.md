# SafeC Frontend

This workspace hosts the current Safe compiler frontend through PR06.8.

## Scope

- `safec lex <file.safe>` lexes a Safe source file and writes versioned token JSON to stdout.
- `safec validate-mir <file.mir.json>` validates emitted `mir-v1` / `mir-v2` structure in Ada and exits nonzero on structural contract failures.
- `safec analyze-mir <file.mir.json>` validates analyzable `mir-v2` input and exits nonzero if MIR-level diagnostics are emitted.
- `safec analyze-mir --diag-json <file.mir.json>` writes `diagnostics-v0` JSON for a `mir-v2` input.
- `safec ast <file.safe>` lexes and parses a Safe source file and writes AST JSON to stdout.
- `safec check <file.safe>` runs the Ada-native PR05/PR06 check pipeline and exits nonzero if diagnostics are emitted.
- `safec check --diag-json <file.safe>` writes `diagnostics-v0` JSON for the Ada-native PR05/PR06 check pipeline.
- `safec emit <file.safe> --out-dir <dir> --interface-dir <dir>` writes the current frontend artifacts for downstream inspection and regression checks.

The current frontend implements the sequential Rule 1-4 subset plus the sequential ownership model used by the current PR06 corpus. It parses executable bodies, emits schema-true AST for the implemented subset, emits `typed-v2` and self-sufficient `mir-v2`, checks the current Rule 1-4 corpus, and checks the sequential ownership corpus through `safec check`. It is still not the concurrency frontend or the Ada/SPARK emitter.

All current `safec` commands are now Ada-native for the implemented PR05/PR06 subset. Python remains allowed in the repository only as glue around the compiler, such as validation helpers, harness scripts, and CI/report orchestration.

PR06.8 runtime doctrine: Python may be used as glue/orchestration, but it may not own any user-facing compiler command and may not participate in parsing, lowering, semantic decisions, diagnostic selection, or emitted compiler artifacts.

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
