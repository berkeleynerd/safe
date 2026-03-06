# SafeC Frontend

This workspace hosts the current Safe compiler frontend through PR05.

## Scope

- `safec lex <file.safe>` lexes a Safe source file and writes versioned token JSON to stdout.
- `safec ast <file.safe>` lexes and parses a Safe source file and writes AST JSON to stdout.
- `safec check <file.safe>` runs the early semantic pipeline and exits nonzero if diagnostics are emitted.
- `safec emit <file.safe> --out-dir <dir> --interface-dir <dir>` writes the current frontend artifacts for downstream inspection and regression checks.

The current frontend implements the sequential Rule 1-4 subset used by the existing D27 corpus. It now parses executable bodies, emits schema-true AST for the implemented subset, emits `typed-v1` and `mir-v1`, and checks the current Rule 1-4 corpus through `safec check`. It is still not the concurrency frontend or the Ada/SPARK emitter.

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
  Validation path: `python3 scripts/validate_ast_output.py`.

- `<stem>.typed.json`
  Format tag: `typed-v1`.
  Contents: package identity, resolved type inventory, executable summaries, public declarations, and the AST snapshot used to derive lowering and diagnostics.

- `<stem>.mir.json`
  Format tag: `mir-v1`.
  Contents: package-level graph data, deterministic locals tables, blocks, typed ops, and explicit terminators for the implemented sequential subset.
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
