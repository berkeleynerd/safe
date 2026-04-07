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

# Run the embedded concurrency evidence lane
python3 scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency

# Check emitted Ada stability for refactoring work
python3 scripts/snapshot_emitted_ada.py --check
```

## Platform Policy

- Supported: local Linux and Ubuntu-based CI
- Unsupported: macOS and Windows

## Guidance

- The repo-local wrapper CLI in `scripts/safe_cli.py` supports:
  - `safe build [--clean] [--clean-proofs] [--no-prove] [--level 1|2 (default: 1)] [--target-bits 32|64] <file.safe>`
  - `safe run [--no-prove] [--level 1|2 (default: 1)] [--target-bits 32|64] <file.safe>`
  - `safe prove [--verbose] [--level 1|2 (default: 2)] [--target-bits 32|64] [file.safe]`
  - `safe deploy [--target stm32f4] --board stm32f4-discovery [--simulate] <file.safe>`
- `safe build`, `safe run`, and `safe prove` share the per-project
  incremental cache under `.safe-build/`.
- Shared emitted Ada support lives in `compiler_impl/stdlib/ada`, with
  `compiler_impl/stdlib/safe_stdlib.gpr` retained for manual integration.
- The current proof inventory and checkpoint ownership live in
  `scripts/_lib/proof_inventory.py`.
- The embedded/Jorvik evidence lane is the repo-local
  `scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency` flow.
- `docs/roadmap.md` is the current roadmap file.
- Keep `compiler/translation_rules.md` and `compiler/ast_schema.json` aligned
  with compiler-facing documentation changes.
- Treat `tests/`, `samples/rosetta/`, and `docs/` as the visible contract around
  the compiler.
- `scripts/safe_cli.py` and `scripts/safe_lsp.py` remain supported repo-local
  tooling and should continue to work.
- The current proof boundary is documented in
  `docs/emitted_output_verification_matrix.md`.
- For refactoring PRs that should preserve emitted Ada shape, run
  `python3 scripts/snapshot_emitted_ada.py --check`. If emitted Ada changes
  intentionally, regenerate `tests/emitted_ada_snapshot.json` with
  `python3 scripts/snapshot_emitted_ada.py`.
