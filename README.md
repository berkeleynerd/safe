# Safe

A systems programming language built around SPARK-class safety guarantees, with a smaller surface designed to avoid sharp edges rather than expose them.

[![CI](https://github.com/berkeleynerd/safe/actions/workflows/ci.yml/badge.svg)](https://github.com/berkeleynerd/safe/actions/workflows/ci.yml)
![Spec version](https://img.shields.io/badge/spec-v0.1_working_draft-blue)

---

## What Is Safe?

Safe is a language in its own right. The current toolchain compiles it through Ada/SPARK-oriented artifacts, but the user-facing goal is not to preserve Ada as a source language. The design keeps the parts that support proof-oriented systems programming and removes or redesigns the parts that create avoidable sharp edges.

Safe inherits its safety posture from the SPARK tradition: the compiler and proof tooling are expected to establish strong safety properties without developer-authored verification scaffolding. The language provides two assurance levels without annotations, contracts, or proof hints. **Bronze** (flow analysis) guarantees no data races and no uninitialised reads. **Silver** (absence of runtime errors) guarantees no overflow, no division by zero, no out-of-bounds indexing, no null dereference, and no double ownership. Programs that cannot be proved safe are rejected -- never accepted with warnings.

These guarantees are enforced by five D27 rules constraining arithmetic, indexing, division, dereference, and floating-point so that every runtime check is provably safe from static type and range information alone. See [`spec/05-assurance.md`](spec/05-assurance.md) for the D27 rules and [`spec/04-tasks-and-channels.md`](spec/04-tasks-and-channels.md) for the concurrency model.

---

## What Does This Repository Contain?

### Language Specification

The `spec/` directory contains the Safe language specification. Entry point: [`spec/00-front-matter.md`](spec/00-front-matter.md).

### Compiler Translation Rules

The `compiler/` directory contains [`translation_rules.md`](compiler/translation_rules.md) and [`ast_schema.json`](compiler/ast_schema.json), which define the translation and AST contracts a compiler must satisfy.

### Reference Compiler

The `compiler_impl/` directory contains the reference compiler workspace and the `safec` frontend implementation.

### Proof Artifacts

The `companion/` directory contains the SPARK companion and emission templates used by the proof workflow.

### Tests and Samples

The `tests/` directory contains the compiler fixture corpus, and `samples/rosetta/` contains sample programs used by the development workflow.

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

## Development

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

## Roadmap

See `spec/` for the language specification and `docs/` for the current design direction.

---

## Documentation Guide

| Looking for... | Go to |
|----------------|-------|
| Language specification | [`spec/00-front-matter.md`](spec/00-front-matter.md) |
| Tutorial | [`docs/tutorial.md`](docs/tutorial.md) |
| Design direction | [`docs/vision.md`](docs/vision.md) |
| Current roadmap notes | [`docs/PR11.x-series-proposed.md`](docs/PR11.x-series-proposed.md) |
| Safe-to-Ada translation rules | [`compiler/translation_rules.md`](compiler/translation_rules.md) |
| Frontend workspace + output formats | [`compiler_impl/README.md`](compiler_impl/README.md) |
| End-to-end CLI walkthrough | [`docs/safec_end_to_end_cli_tutorial.md`](docs/safec_end_to_end_cli_tutorial.md) |
| VS Code extension | [`editors/vscode/README.md`](editors/vscode/README.md) |
| SPARK companion overview | [`release/COMPANION_README.md`](release/COMPANION_README.md) |

---

## Contributing

Open an issue before submitting a pull request. Areas of particular interest:

- Compiler implementation
- Test cases for D27 rules and language features
- Specification review and feedback

---

## Licence

No licence file exists yet. All rights reserved until a licence is chosen.
