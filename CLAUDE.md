# CLAUDE.md

## Repository Shape

Safe is maintained here as a minimal development workflow:

- `compiler_impl/` contains the reference compiler workspace
- `tests/` contains the fixture corpus
- `samples/rosetta/` contains sample programs
- `companion/` contains the SPARK companion and emission templates
- `spec/` and `docs/` contain the language and design documentation
- `scripts/run_tests.py`, `scripts/run_samples.py`, and `scripts/run_proofs.py`
  are the active repo workflows

The old milestone pipeline, execution reports, and `run_pr*.py` scripts are
intentionally gone.

## Development Commands

```bash
# Build the compiler
(cd compiler_impl && alr build)

# Run tests
python3 scripts/run_tests.py

# Run proofs (requires GNATprove)
python3 scripts/run_proofs.py

# Check samples
python3 scripts/run_samples.py
```

## Platform Policy

- Supported: local Linux and Ubuntu-based CI
- Unsupported: macOS and Windows

## Guidance

- Keep `compiler/translation_rules.md` and `compiler/ast_schema.json` aligned
  with compiler-facing documentation changes.
- Treat `tests/`, `samples/rosetta/`, and `docs/` as the visible contract around
  the compiler.
- `scripts/safe_cli.py` and `scripts/safe_lsp.py` remain supported repo-local
  tooling and should continue to work.
- The current proof boundary is documented in
  `docs/emitted_output_verification_matrix.md`.
