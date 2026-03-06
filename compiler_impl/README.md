# SafeC Early Frontend

This workspace hosts the PR00-PR04 bootstrap frontend for the Safe compiler.

## Scope

- `safec ast <file.safe>` lexes and parses a Safe source file and writes AST JSON to stdout.
- `safec check <file.safe>` runs the early semantic pipeline and exits nonzero if diagnostics are emitted.
- `safec emit <file.safe> --out-dir <dir> --interface-dir <dir>` writes the current frontend artifacts for downstream inspection and regression checks.

The current frontend is intentionally an early slice. It proves out workspace layout, deterministic diagnostics, versioned JSON outputs, and the typed-AST to MIR handoff. It is not yet the D27 analyzer or the Ada/SPARK emitter.

## Output Formats

`safec emit` currently writes four JSON artifacts:

- `<stem>.ast.json`
  Format: parser AST shaped to the contract in `compiler/ast_schema.json`.
  Validation path: `python3 scripts/validate_ast_output.py`.

- `<stem>.typed.json`
  Format tag: `typed-v0`.
  Contents: package identity, typed declaration summaries, executable summaries, and the underlying AST snapshot used to derive later phases.

- `<stem>.mir.json`
  Format tag: `mir-v0`.
  Contents: package-level graph data, blocks, successors, and placeholder statement payloads.
  Status: debug and regression artifact only. This MIR is a scaffold for PR05 and later semantic passes, not yet a stable compatibility surface.

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

The smoke run checks AST validation, representative `check` runs, deterministic repeated `emit` output, and records hashes in `execution/reports/pr00-pr04-frontend-smoke.json`.
