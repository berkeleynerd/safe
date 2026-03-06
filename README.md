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

The `spec/` directory contains 10 Markdown files (4,451 lines) forming a delta document that references Ada 2022 (ISO/IEC 8652:2023). Entry point: [`spec/00-front-matter.md`](spec/00-front-matter.md).

### Compiler Translation Rules

The `compiler/` directory contains [`translation_rules.md`](compiler/translation_rules.md) (14-section Safe-to-Ada translation reference) and [`ast_schema.json`](compiler/ast_schema.json) (JSON AST schema). Together they define the interface a future compiler must satisfy.

### SPARK Companion

The `companion/spark/` directory contains a formal verification artefact: 25 ghost functions and 23 proof obligation procedures, verified at Silver level. The companion encodes the Safe specification's normative clauses as SPARK 2022 contracts. See [`release/COMPANION_README.md`](release/COMPANION_README.md) for the full overview.

### Verified Emission Templates

The `companion/templates/` directory contains 14 templates (M1–M7 complete) demonstrating how a Safe compiler would emit provably correct Ada/SPARK for each D27 rule category. 325 verification conditions across 17 units, 0 unproved. All 23 `Safe_PO` proof obligation hooks are exercised. See [`docs/template_plan.md`](docs/template_plan.md) for milestone details and [`docs/template_inventory.md`](docs/template_inventory.md) for the full proof inventory.

---

## Key Statistics

| Metric | Value |
|--------|-------|
| Spec files | 10 (4,451 lines) |
| Normative clauses | 205 |
| Ghost functions / PO procedures | 25 / 23 |
| Companion VCs (flow / proved / justified / unproved) | 29 / 34 / 1 / 0 (64 total) |
| Template VCs (flow / proved / justified / unproved) | 107 / 217 / 1 / 0 (325 total, 17 units) |
| Tracked assumptions | 14 (4 critical, 4 major, 5 minor, 1 template) |
| Test files | 79 |

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

### Run the Pipeline

```bash
# Full 5-step pipeline (compile -> flow -> prove -> extract -> diff)
scripts/run_all.sh

# Individual steps
scripts/run_gnatprove_flow.sh   # Bronze gate
scripts/run_gnatprove_prove.sh  # Silver gate
```

For the expanded pipeline description, see [`release/COMPANION_README.md`](release/COMPANION_README.md) Section 2.

---

## Repository Structure

```
safe/
├── spec/                        # Language specification (10 files)
├── compiler/                    # Translation rules + AST schema
├── companion/
│   ├── spark/                   # Safe_Model + Safe_PO
│   ├── gen/                     # Build config, proof golden
│   ├── templates/               # 14 verified emission templates (M1–M7 complete)
│   └── assumptions.yaml         # 14 tracked assumptions
├── compiler_impl/               # Reference compiler workspace (early frontend)
├── clauses/                     # 205 clauses + PO mappings
├── execution/                   # Execution ledger, dashboard, and session notes
├── tests/                       # 79 test files (5 categories)
├── docs/                        # Technical documentation
├── scripts/                     # CI and automation (13 scripts)
├── meta/                        # Frozen commit SHA, generator version
├── release/                     # Companion README, status report
├── references/                  # SPARK RM extracts, Ada standards
├── audit/                       # Phase 0/1 audit reports
└── archive/                     # Historical artefacts
```

---

## Documentation Guide

| Looking for... | Go to |
|----------------|-------|
| Language specification | [`spec/00-front-matter.md`](spec/00-front-matter.md) |
| Safe-to-Ada translation rules | [`compiler/translation_rules.md`](compiler/translation_rules.md) |
| Early frontend workspace + output formats | [`compiler_impl/README.md`](compiler_impl/README.md) |
| SPARK companion overview | [`release/COMPANION_README.md`](release/COMPANION_README.md) |
| Full traceability | [`docs/traceability_matrix.md`](docs/traceability_matrix.md) |
| PO procedure index | [`docs/po_index.md`](docs/po_index.md) |
| GNATprove configuration | [`docs/gnatprove_profile.md`](docs/gnatprove_profile.md) |
| Template inventory | [`docs/template_inventory.md`](docs/template_inventory.md) |
| Template roadmap (M0–M7) | [`docs/template_plan.md`](docs/template_plan.md) |
| Assumption registry | [`companion/assumptions.yaml`](companion/assumptions.yaml) |
| Status report | [`release/status_report.md`](release/status_report.md) |
| Spec generation decisions | [`EXEC_SUMMARY.md`](EXEC_SUMMARY.md) |
| Spec change log | [`CHANGELOG.md`](CHANGELOG.md) |

---

## Continuous Integration

Six CI jobs run on every push and pull request to `main`:

- **`execution-guard`** -- Ledger, dashboard, frozen-SHA, and test-distribution checks
- **`lint-safe-syntax`** -- Surface-syntax guard across the `.safe` corpus
- **`frontend-smoke`** -- Early frontend build, lexer regression checks, AST validation, and deterministic emit smoke checks
- **`pr05-d27-harness`** -- Sequential Rule 1-4 golden diffs, corpus gating, and deterministic emit checks
- **`spark-verify`** -- Companion: 64 VCs, 0 unproved
- **`templates-verify`** -- Templates pipeline: 320 VCs, 0 unproved

The SPARK companion and template jobs execute the 5-step verification pipeline (compile, flow, prove, extract, diff) and fail on any unproved check or assumption budget violation.

See [`release/COMPANION_README.md`](release/COMPANION_README.md) Section 8 for the pipeline diagram and [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the workflow definition.

---

## Status

| Property | Value |
|----------|-------|
| Spec version | Working Draft v0.1 |
| Frozen spec commit | `468cf72332724b04b7c193b4d2a3b02f1584125d` |
| Generator | spec2spark v0.1.0 |
| Companion status | All 13 companion tasks complete |
| Emission templates | 14/14 proved (320 VCs, 0 unproved; M1–M7 complete) |
| Compiler frontend | `compiler_impl/` PR00–PR05 sequential Rule 1–4 frontend landed |

The repository now includes a sequential compiler frontend under `compiler_impl/`. It can lex `.safe` inputs via `safec lex`, emit schema-true AST for the implemented Rule 1–4 subset, emit `typed-v1` and `mir-v1`, run D27 Rule 1–4 checking over the current sequential corpus, and reproduce the four committed D27 diagnostics goldens. The translation rules and AST schema in `compiler/` remain the contract the later compiler phases must satisfy.


---

## Contributing

Open an issue before submitting a pull request. Areas of particular interest:

- Compiler implementation
- Test cases for D27 rules and language features
- Specification review and feedback

---

## Licence

No licence file exists yet. All rights reserved until a licence is chosen.
