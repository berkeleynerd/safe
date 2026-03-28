# Safe Compiler Workspace

This directory contains the reference compiler workspace and the `safec`
frontend.

The old milestone pipeline and execution-report workflow are not part of this
branch. The active development loop is build the compiler, run the fixture
suite, run the sample sweep, and run proofs.

The current Safe source surface is lowercase-only. Keywords, predefined names,
aspect names, and user-defined identifiers are all written in lowercase, with
underscores as the word separator for multiword spellings.

The current numeric surface is split between signed `integer` and fixed-width
`binary (8|16|32|64)`. Emitted Ada maps binary values to
`Interfaces.Unsigned_*`.

The current PR11.8d text/array surface is shipped and buildable end to end
with these explicit boundaries:

- `string (N)` is the stack-backed bounded string form
- plain `string` is supported in locals, params/results, out formals, tuple
  elements, record fields, and fixed-array components
- `array of T` is supported in locals, params/results, record fields, and
  fixed-array components
- `for item of values` is implemented for array object names
- fixed -> growable array conversion is supported through normal target typing
- growable -> fixed array narrowing is supported only for bracket literals and
  static name-based slices
- string iteration, proof-based exact-length narrowing, string `case`, string
  discriminants, and string/growable channel elements remain deferred

## Build

From the repository root:

```bash
cd compiler_impl
alr build
```

The compiler binary is written to `compiler_impl/bin/safec`. Alire and GPRBuild
artifacts belong under `compiler_impl/obj/` and `compiler_impl/bin/`.

## Supported Hosts

- Supported: local Linux and Ubuntu-based CI
- Unsupported: macOS and Windows

## CLI Surface

The current repo-local compiler commands are:

- `safec lex <file.safe>`
- `safec ast <file.safe> [--interface-search-dir <dir>]...`
- `safec check <file.safe> [--interface-search-dir <dir>]...`
- `safec check --diag-json <file.safe> [--interface-search-dir <dir>]...`
- `safec emit <file.safe> --out-dir <dir> --interface-dir <dir> [--ada-out-dir <dir>] [--interface-search-dir <dir>]...`
- `safec validate-mir <file.mir.json>`
- `safec analyze-mir <file.mir.json>`
- `safec analyze-mir --diag-json <file.mir.json>`

The repo also keeps a small wrapper CLI at `../scripts/safe_cli.py`:

- `python3 ../scripts/safe_cli.py build <file.safe>`
- `python3 ../scripts/safe_cli.py deploy --board stm32f4-discovery [--simulate] <file.safe>`
- `python3 ../scripts/safe_cli.py run <file.safe>`
- `python3 ../scripts/safe_cli.py check ...`
- `python3 ../scripts/safe_cli.py emit ...`

`safe build`, `safe run`, and `safe deploy` are still single-file wrappers in
this branch. They support:

- explicit-package roots with no leading `with` clauses, built through the
  existing generated-driver path
- packageless entry roots with no leading `with` clauses, built through an
  emitted `main.adb`

If the root file begins with `with`, the wrapper rejects it and points users to
`safec emit` plus manual `gprbuild` for the current multi-file flow.

`safe deploy` is currently limited to `stm32f4-discovery`. `--simulate` runs
through Renode; omitting it uses OpenOCD + ST-LINK with the same generated
embedded driver and startup-status protocol.

The repo also now includes a prototype single-file REPL:

- `python3 ../scripts/safe_repl.py`

## Compiler Outputs

`safec emit` always writes four machine-readable artifacts:

- `<stem>.ast.json`
  The parser AST, shaped to [`../compiler/ast_schema.json`](../compiler/ast_schema.json).
- `<stem>.typed.json`
  The typed frontend snapshot (`typed-v2`).
- `<stem>.mir.json`
  The lowered MIR document (`mir-v2`).
- `<stem>.safei.json`
  The dependency interface contract (`safei-v1`).

When `--ada-out-dir <dir>` is provided, `safec emit` also writes emitted
Ada/SPARK artifacts:

- `<unit>.ads`
- `<unit>.adb`
- optional `main.adb` for packageless entry roots
- optional `<unit>_safe_io.ads`
- optional `<unit>_safe_io.adb`
- optional `gnat.adc`

Useful repo-local validators from the repository root:

- `python3 scripts/validate_ast_output.py`
- `python3 scripts/validate_mir_output.py`
- `python3 scripts/validate_output_contracts.py`

If you are already inside `compiler_impl/`, use the same commands as
`python3 ../scripts/...`.

## Development Workflow

Build once, then run the top-level workflow scripts from the repository root:

```bash
# Build the compiler
(cd compiler_impl && alr build)

# Run fixture tests
python3 scripts/run_tests.py

# Check, build, and run the Rosetta samples
python3 scripts/run_samples.py

# Run proofs (requires GNATprove)
python3 scripts/run_proofs.py
```

`run_tests.py` covers:

- `tests/positive/`
- `tests/negative/`
- `tests/concurrency/`
- `tests/interfaces/`
- `tests/diagnostics_golden/`

`run_samples.py` covers `samples/rosetta/**/*.safe` with an end-to-end sweep:

- `safec check`
- `safec emit`
- emitted Ada build through `gprbuild`
- native execution of the produced binary

For packageless entry samples, the sweep uses the emitted `main.adb` directly.
For explicit-package samples, it still generates the small Ada driver needed to
run the unit.

`run_proofs.py` covers:

- `companion/gen`
- `companion/templates`
- the current emitted proof-bearing fixture subset

## Useful References

- [`../docs/frontend_architecture_baseline.md`](../docs/frontend_architecture_baseline.md)
- [`../docs/emitted_output_verification_matrix.md`](../docs/emitted_output_verification_matrix.md)
- [`../docs/safec_end_to_end_cli_tutorial.md`](../docs/safec_end_to_end_cli_tutorial.md)
- [`../compiler/translation_rules.md`](../compiler/translation_rules.md)
- [`../compiler/ast_schema.json`](../compiler/ast_schema.json)

## Notes

- Python remains repo glue and orchestration only. The compiler itself is the
  Ada-native `safec` binary.
- Cross-unit resolution uses emitted `safei-v1` interfaces plus
  `--interface-search-dir`.
- [`../docs/emitted_output_verification_matrix.md`](../docs/emitted_output_verification_matrix.md)
  is the current statement of what is compile-only versus `flow` / `prove`
  verified.
