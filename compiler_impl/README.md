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

The current PR11.8e reference/parameter surface is also active:

- direct self-recursive record types are inferred as references
- source `access`, `new`, `.all`, `.access`, `in`, `out`, and `in out` are removed
- parameters are either ordinary immutable borrows or `mut` mutable borrows
- `null` and `not null` apply only to inferred reference-typed bindings
- task bodies may use only locals and channels

The current PR11.8d text/array surface is shipped and buildable end to end
with these explicit boundaries:

- `string (N)` is the stack-backed bounded string form
- plain `string` is supported in locals, params/results, tuple
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
- `safec ast [--target-bits 32|64] <file.safe> [--interface-search-dir <dir>]...`
- `safec check [--target-bits 32|64] <file.safe> [--interface-search-dir <dir>]...`
- `safec check --diag-json [--target-bits 32|64] <file.safe> [--interface-search-dir <dir>]...`
- `safec emit [--target-bits 32|64] <file.safe> --out-dir <dir> --interface-dir <dir> [--ada-out-dir <dir>] [--interface-search-dir <dir>]...`
- `safec validate-mir <file.mir.json>`
- `safec analyze-mir <file.mir.json>`
- `safec analyze-mir --diag-json <file.mir.json>`

The repo also keeps a small wrapper CLI at `../scripts/safe_cli.py`:

- `python3 ../scripts/safe_cli.py build [--clean] [--clean-proofs] [--no-prove] [--level 1|2] [--target-bits 32|64] <file.safe>`
- `python3 ../scripts/safe_cli.py deploy [--target stm32f4] --board stm32f4-discovery [--simulate] <file.safe>`
- `python3 ../scripts/safe_cli.py run [--no-prove] [--level 1|2] [--target-bits 32|64] <file.safe>`
- `python3 ../scripts/safe_cli.py prove [--verbose] [--level 1|2] [--target-bits 32|64] [file.safe]`
- `python3 ../scripts/safe_cli.py check ...`
- `python3 ../scripts/safe_cli.py emit ...`

`safe build`, `safe run`, and `safe prove` are still root-file wrappers in
this branch. They support:

- explicit-package roots, including local imported roots with leading `with`
  clauses when sibling dependency sources are present
- packageless entry roots through the generated driver path
- a shared per-directory incremental cache under `PROJECT/.safe-build/`
  partitioned by `target-32` / `target-64` for both `safe build`/`safe run`
  and `safe prove`
- proof-on-build for the current repo-local wrapper flow:
  `safe build` and `safe run` run the cached root proof step by default,
  `--no-prove` skips it, and `--level` selects GNATprove depth

The current model is still root-file based, not workspace mode. `safe deploy`
remains narrower: it is currently limited to `stm32f4-discovery`, and roots
with leading `with` clauses still require the manual emitted-Ada flow there.
`--simulate` runs through Renode; omitting it uses OpenOCD + ST-LINK with the
same generated embedded driver and startup-status protocol.

The repo also now includes a prototype single-file REPL:

- `python3 ../scripts/safe_repl.py`

## Compiler Outputs

`safec emit` always writes four machine-readable artifacts. The normative
contract is documented in [`../docs/artifact_contract.md`](../docs/artifact_contract.md):

- `<stem>.ast.json`
  The parser AST, shaped to [`../compiler/ast_schema.json`](../compiler/ast_schema.json).
- `<stem>.typed.json`
  The typed frontend snapshot (`typed-v6`).
- `<stem>.mir.json`
  The lowered MIR document (`mir-v4`).
- `<stem>.safei.json`
  The dependency interface contract (`safei-v5`).

When `--ada-out-dir <dir>` is provided, `safec emit` also writes emitted
Ada/SPARK artifacts:

- `<unit>.ads`
- `<unit>.adb`
- optional `main.adb` for packageless entry roots
- optional `gnat.adc`

Emitted Ada builds and proof runs must include the shared stdlib support
source directory `compiler_impl/stdlib/ada` rather than expecting copied
runtime or `_safe_io` files in each output directory. The repository still
ships `compiler_impl/stdlib/safe_stdlib.gpr` for manual integration, but the
repo-local validation harnesses build emitted units and shared stdlib sources
in one flat project.

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

# Check, emit, prove, build, and run the Rosetta samples
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
- emitted proof via the same helper path used by `safe prove`
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
- Cross-unit resolution uses emitted `safei-v5` interfaces plus
  `--interface-search-dir`.
- [`../docs/emitted_output_verification_matrix.md`](../docs/emitted_output_verification_matrix.md)
  is the current statement of what is compile-only versus `flow` / `prove`
  verified.
