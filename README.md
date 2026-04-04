# Safe

A systems programming language built around SPARK-class safety guarantees, with
a smaller surface designed to avoid sharp edges rather than expose them.

[![CI](https://github.com/berkeleynerd/safe/actions/workflows/ci.yml/badge.svg)](https://github.com/berkeleynerd/safe/actions/workflows/ci.yml)
![Spec version](https://img.shields.io/badge/spec-v0.1_working_draft-blue)
![Proved fixtures](https://img.shields.io/badge/proved_fixtures-161-brightgreen)

Safe is a language in its own right. The current toolchain compiles it through
Ada/SPARK-oriented artifacts, but the user-facing goal is not to preserve Ada
as a source language. The design keeps the parts that support proof-oriented
systems programming and removes or redesigns the parts that create avoidable
sharp edges.

The current admitted source surface is fully lowercase, with underscores as the
word separator for multiword spellings.

---

## What Safe Guarantees

### Flow Safety (Bronze)

The compiler derives complete flow information — the equivalent of SPARK's
`Global`, `Depends`, and `Initializes` contracts — automatically from the
source, without annotations. This guarantees:

- **No uninitialized reads.** Every variable must be initialized at declaration.
- **No data races.** Inter-task communication is channel-only. Each package
  variable is accessed by at most one task.
- **No aliasing violations.** The ownership model prevents mutable aliasing
  at all call sites.

### Absence of Runtime Errors (Silver)

Five rules constrain the type system so that every runtime check is provably
safe from static type and range information alone:

| Rule | What It Prevents | How |
|------|-----------------|-----|
| Rule 1 | Integer overflow | All arithmetic widened to 64-bit; narrowing proved at assignment |
| Rule 2 | Out-of-bounds indexing | Index type must be contained in array bounds type |
| Rule 3 | Division by zero | Divisor type must exclude zero, or a guard must precede the operation |
| Rule 4 | Null dereference | Only `not null` reference subtypes can be dereferenced |
| Rule 5 | Floating-point traps | IEEE 754 non-trapping mode; NaN/infinity caught at narrowing points |

Programs that cannot be proved safe are **rejected** — never accepted with
warnings. The guards the programmer writes to satisfy these rules are the same
defensive checks an AI agent would naturally generate: range checks, null
checks, and bounds guards. In Safe, those guards *are* the proof.

### Memory Safety

Safe implements an ownership model with three access patterns:

- **Move** — ownership transfer with automatic nulling of the source
- **Borrow** (default parameters) — shared read-only access
- **Mut borrow** (`mut` parameters) — exclusive mutable access, caller frozen

Automatic deallocation at scope exit. No dangling pointers, no double-free, no
use-after-move — all enforced at compile time without lifetime annotations.

### Concurrency Safety

- **Static tasks** with bounded FIFO channels as the sole communication
  mechanism.
- **Nonblocking send** — the language rejects blocking `send`; all sends use
  the three-argument form with explicit full-channel handling.
- **Blocking operations** — on the admitted concurrency surface, blocking is
  confined to `receive` and `select`.
- **Dispatcher-based fair select** — on the admitted subset (same-unit,
  non-public channels in unit-scope statements and direct task bodies), channel
  arms are checked in rotating order with blocking entry barriers, not polling.
  Delay arms use absolute deadlines.
- **Priority ceiling protocol** computed automatically from task access
  patterns.

### Structured Error Handling

`try` propagates failures through `(result, T)` tuples without boilerplate.
`match` destructures results into `when ok (value)` and `when fail (err)` arms.
Errors are values, not exceptions — no stack unwinding, no hidden control flow,
and the prover handles error paths the same as success paths.

---

## What Safe Does Not Guarantee

Honesty about limits is part of the safety story:

- **Deadlock freedom** — circular dependencies among receive-side blocking
  operations (`receive` and `select`) remain possible. Nonblocking send
  eliminates the most common deadlock pattern (send/receive circular chains).
  Static receive-dependency graph analysis is deferred future work.
- **Resource exhaustion** — stack overflow and allocation failure are outside
  the proof model.
- **Functional correctness** — the compiler proves absence of runtime errors,
  not that the program computes the right answer. Gold/Platinum-level
  correctness requires SPARK annotations, which Safe does not expose.
- **Broader runtime guarantees** — timing, fairness, and scheduling claims
  beyond the admitted STM32F4/Jorvik subset are not part of the current
  evidence base.

---

## Evidence

Two independent evidence channels back the safety claims:

**Emitted proof corpus.** The blocking emitted-proof inventory currently covers
161 fixtures with 4 explicit exclusions and 0 uncovered fixtures. These
fixtures are emitted as Ada/SPARK and verified by GNATprove through the
repository proof lane.

**Companion emission templates.** The companion inventory currently reports 325
total VCs across 17 units: 107 Bronze flow checks passed, 217 Silver proof VCs
proved, 1 Silver VC justified, and 0 unproved.

| Metric | Value |
|--------|-------|
| Proved emitted fixtures | 161 (4 exclusions, 0 uncovered) |
| Companion template VCs | 325 total (217 proved, 1 justified, 0 unproved, 107 flow passed) |
| Tracked proof assumptions | 12 |
| Test corpus | 418+ files (positive, negative, build, concurrency, interfaces, embedded) |
| Embedded evidence lane | STM32F4 / Jorvik / Renode (blocking in CI) |
| Compiler size | ~54K LOC Ada across 62 source files |

---

## What Does This Repository Contain?

| Directory | Contents |
|-----------|----------|
| `spec/` | Language specification. Entry: [`spec/00-front-matter.md`](spec/00-front-matter.md) |
| `compiler/` | Translation rules and AST schema |
| `compiler_impl/` | Reference compiler (`safec`) and shared stdlib (`compiler_impl/stdlib/ada/`) |
| `companion/` | SPARK companion: emission templates, ghost model, assumptions ledger |
| `tests/` | Compiler fixture corpus (positive, negative, build, concurrency, interfaces, embedded) |
| `samples/rosetta/` | Sample programs used by the development workflow |
| `scripts/` | `safe` CLI, test/proof/sample runners, incremental build cache, embedded smoke lane |
| `docs/` | Design direction, tutorial, roadmap, proof journals, verification matrix |

---

## Quick Start

### Prerequisites

| Tool | Minimum Version |
|------|----------------|
| GNAT | >= 14.x (Ada 2022) |
| GNATprove | >= 25.x |
| Alire | >= 2.x |
| CVC5 | >= 1.0.8 |
| Z3 | >= 4.12 |
| Alt-Ergo | >= 2.5 |

### Development

```bash
# Build the compiler
(cd compiler_impl && alr build)

# Run tests
python3 scripts/run_tests.py

# Run proofs (requires GNATprove)
python3 scripts/run_proofs.py

# Check, emit, prove, build, and run samples
python3 scripts/run_samples.py

# Build a Safe program (handles multi-file imported roots)
python3 scripts/safe_cli.py build samples/rosetta/text/hello_print.safe

# Build and execute
python3 scripts/safe_cli.py run samples/rosetta/text/hello_print.safe

# Prove emitted Ada for a Safe source file
python3 scripts/safe_cli.py prove tests/build/pr118k_try_build.safe

# Force a clean rebuild
python3 scripts/safe_cli.py build --clean samples/rosetta/text/hello_print.safe

# Run the embedded Renode concurrency evidence lane
python3 scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency

# Deploy to STM32F4 Discovery (Renode simulation)
python3 scripts/safe_cli.py deploy --board stm32f4-discovery --simulate tests/embedded/entry_integer_result.safe

# Prototype REPL
python3 scripts/safe_repl.py
```

---

## Roadmap

Recent milestones cover artifact-contract stabilization, dispatcher-based fair
`select`, structured error handling, user-defined enumerations, and
incremental multi-file builds. The next larger milestones are:

- **PR11.10** — Built-in parameterized containers (`list of T`, `map of (K, V)`,
  `optional T`)
- **PR11.11** — User-defined generics

See [`docs/roadmap.md`](docs/roadmap.md) for the
full roadmap.

---

## Documentation Guide

| Looking for... | Go to |
|----------------|-------|
| Language specification | [`spec/00-front-matter.md`](spec/00-front-matter.md) |
| Tutorial | [`docs/tutorial.md`](docs/tutorial.md) |
| Design direction | [`docs/vision.md`](docs/vision.md) |
| Current roadmap | [`docs/roadmap.md`](docs/roadmap.md) |
| Translation rules | [`compiler/translation_rules.md`](compiler/translation_rules.md) |
| Compiler workspace | [`compiler_impl/README.md`](compiler_impl/README.md) |
| CLI walkthrough | [`docs/safec_end_to_end_cli_tutorial.md`](docs/safec_end_to_end_cli_tutorial.md) |
| Proof verification matrix | [`docs/emitted_output_verification_matrix.md`](docs/emitted_output_verification_matrix.md) |
| Concurrency contract | [`docs/jorvik_concurrency_contract.md`](docs/jorvik_concurrency_contract.md) |
| Embedded simulation | [`docs/embedded_simulation.md`](docs/embedded_simulation.md) |
| Embedded deploy | [`docs/embedded_deploy.md`](docs/embedded_deploy.md) |
| VS Code extension | [`editors/vscode/README.md`](editors/vscode/README.md) |
| SPARK companion | [`companion/release/COMPANION_README.md`](companion/release/COMPANION_README.md) |

---

## Contributing

Open an issue before submitting a pull request. Areas of particular interest:

- Compiler implementation
- Test cases for D27 rules and language features
- Specification review and feedback

---

## Licence

No licence file exists yet. All rights reserved until a licence is chosen.
