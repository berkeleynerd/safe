# Safe

A systems programming language defined subtractively from Ada 2022, designed so programs can be proven free of runtime errors without developer annotations.

[![CI](https://github.com/agentc1/safe/actions/workflows/ci.yml/badge.svg)](https://github.com/agentc1/safe/actions/workflows/ci.yml)
![Spec version](https://img.shields.io/badge/spec-v0.1_working_draft-blue)

---

## What Is Safe?

Safe is built on ISO/IEC 8652:2023 (Ada 2022). It is a curated subset -- removing exceptions, tagged types, and generics -- augmented with new constructs including static tasks and typed channels. Conforming Safe programs compile via any conforming Ada 2022 compiler after translation.

The language provides two assurance levels without annotations, contracts, or proof hints. **Bronze** (flow analysis) guarantees no data races and no uninitialised reads. **Silver** (absence of runtime errors) guarantees no overflow, no division by zero, no out-of-bounds indexing, no null dereference, and no double ownership. Programs that cannot be proved safe are rejected -- never accepted with warnings.

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

The `companion/` directory contains the SPARK companion and verified emission templates used by the proof workflow.

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
| Safe-to-Ada translation rules | [`compiler/translation_rules.md`](compiler/translation_rules.md) |
| Current frontend boundary | [`docs/frontend_architecture_baseline.md`](docs/frontend_architecture_baseline.md) |
| Frontend workspace + output formats | [`compiler_impl/README.md`](compiler_impl/README.md) |
| Frontend scale limits | [`docs/frontend_scale_limits.md`](docs/frontend_scale_limits.md) |
| Emitted output verification matrix | [`docs/emitted_output_verification_matrix.md`](docs/emitted_output_verification_matrix.md) |
| PR10.1 refinement audit | [`docs/pr10_refinement_audit.md`](docs/pr10_refinement_audit.md) |
| Post-PR10 residual ledger | [`docs/post_pr10_scope.md`](docs/post_pr10_scope.md) |
| SPARK companion overview | [`release/COMPANION_README.md`](release/COMPANION_README.md) |
| Full traceability | [`docs/traceability_matrix.md`](docs/traceability_matrix.md) |
| PO procedure index | [`docs/po_index.md`](docs/po_index.md) |
| GNATprove configuration | [`docs/gnatprove_profile.md`](docs/gnatprove_profile.md) |
| Template inventory | [`docs/template_inventory.md`](docs/template_inventory.md) |
| Template roadmap | [`docs/template_plan.md`](docs/template_plan.md) |

---

## Contributing

Open an issue before submitting a pull request. Areas of particular interest:

- Compiler implementation
- Test cases for D27 rules and language features
- Specification review and feedback

---

## Licence

No licence file exists yet. All rights reserved until a licence is chosen.
