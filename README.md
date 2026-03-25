# Safe

A systems programming language defined subtractively from Ada 2022, designed so programs can be proven free of runtime errors without developer annotations.

[![CI](https://github.com/agentc1/safe/actions/workflows/ci.yml/badge.svg)](https://github.com/agentc1/safe/actions/workflows/ci.yml)
![Spec version](https://img.shields.io/badge/spec-v0.1_working_draft-blue)

---

## Roadmap Snapshot

The canonical tracked ledger lives in [`execution/tracker.json`](execution/tracker.json) and
[`execution/dashboard.md`](execution/dashboard.md). Detailed `PR11.x` proposal text lives in
[`docs/PR11.x-series-proposed.md`](docs/PR11.x-series-proposed.md).

Completed rows use strikethrough. Italic rows are tracked planned milestones
that still live at the proposal/detail stage rather than in gate-backed CI.

| Series | Status | Focus |
|--------|--------|-------|
| ~~PR00–PR06.9.13~~ | `done` | Ledger, compiler bring-up, hardening |
| ~~PR07~~ | `done` | Rule 5 analyzer baseline |
| ~~PR08~~ | `done` | Ada-native frontend baseline |
| ~~PR09~~ | `done` | Ada/SPARK emission baseline |
| ~~PR10~~ | `done` | Emitted GNATprove baseline |
| ~~PR10.1~~ | `done` | Audit and residual normalization |
| ~~PR10.2~~ | `done` | Rule 5 proof closure |
| ~~PR10.3~~ | `done` | Ownership proof expansion |
| ~~PR10.4~~ | `done` | Evidence, parser, report hardening |
| ~~PR10.5~~ | `done` | Emitter maintenance hardening |
| ~~PR10.6~~ | `done` | Remaining sequential proof corpus |
| ~~PR11.1~~ | `done` | Build wrapper, editor grammar, Rosetta |
| ~~PR11.2~~ | `done` | Strings/chars and case statements |
| ~~PR11.3~~ | `done` | Discriminants, tuples, and structured returns |
| ~~PR11.3a~~ | `done` | Checkpoint 1 proof closure |
| ~~PR11.4~~ | `done` | Cut over to `function`, `returns`, `else if`, and `to` |
| ~~PR11.5~~ | `done` | Optional semicolons and statement-local `var` |
| ~~PR11.6~~ | `done` | Meaningful whitespace blocks |
| ~~PR11.6.1~~ | `done` | Attestation chain compression |
| ~~PR11.6.2~~ | `done` | Legacy Ada syntax removal |
| ~~PR11.7~~ | `done` | Reference-surface experiments |
| *PR11.8* | `planned` | Unified integer type |
| *PR11.8a* | `planned` | Unified integer proof checkpoint |
| *PR11.8b* | `planned` | Concurrency proof expansion plus channel constraints |
| *PR11.8c* | `planned` | Modular arithmetic |
| *PR11.8d* | `planned` | Value-type string |
| *PR11.8e* | `planned` | Inferred reference types and copy-only values |
| *PR11.8f* | `planned` | Value-type proof checkpoint |
| *PR11.8g* | `planned` | Value-type channel elements |
| *PR11.9* | `planned` | Artifact contract stabilization |
| *PR11.10* | `planned` | Monomorphic library layer |
| *PR11.11* | `planned` | Restricted generics |

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
| Test corpus entries | 159 |

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
├── tests/                       # 159 corpus entries (6 categories)
├── docs/                        # Technical documentation
├── scripts/                     # CI, validation, and automation helpers
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
| Template roadmap (M0–M7) | [`docs/template_plan.md`](docs/template_plan.md) |
| Assumption registry | [`companion/assumptions.yaml`](companion/assumptions.yaml) |
| Status report | [`release/status_report.md`](release/status_report.md) |

---

## Continuous Integration

CI runs a matrix of execution-guard checks, frontend smoke and regression/hardening gates through PR06.9.13, the PR08 frontend baseline jobs, the PR09 Ada-emission slice/baseline jobs, the PR10 emitted-output GNATprove contract/flow/prove/baseline jobs, the supplemental emitted hardening regression job, the PR10.1 comprehensive audit job, the PR11.1 language-evaluation harness job, the PR11.4 syntax-cutover gate, and the SPARK companion plus emission-template verification jobs.

The frontend matrix now enforces:

- Ada-native `safec lex` / `ast` / `validate-mir` / `analyze-mir` / `check` / `emit`
- the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern
- Python as glue/orchestration only around the compiler
- deterministic committed evidence for the PR06.9.x hardening series, the PR08 frontend baseline, the PR09 Ada-emission baseline, and the PR10 emitted-output GNATprove baseline
- selected emitted-output GNATprove `flow` / `prove` verification for Rules 1-5, ownership, and the current concurrency emission corpus under an all-proved-only policy
- supplemental emitted-output hardening regressions outside the frozen PR10 selected corpus, including ownership early-return ordering plus richer concurrency proof samples
- the PR10.1 comprehensive audit, which reruns the authoritative baselines, normalises the retained post-PR10 ledger, and advances the roadmap to `PR10.2`
- the PR11.1 language-evaluation harness, including the repo-local `safe` prototype, the disposable VSCode grammar/LSP surface, and the starter Rosetta compile-only gate

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the current workflow definition, [`docs/frontend_architecture_baseline.md`](docs/frontend_architecture_baseline.md) for the current compiler boundary, [`docs/frontend_scale_limits.md`](docs/frontend_scale_limits.md) for the current cliff-detection scale policy, and [`docs/emitted_output_verification_matrix.md`](docs/emitted_output_verification_matrix.md) for the canonical emitted-output assurance boundary.

For local milestone work, you can enforce the same serial gate verification before `git push`:

```bash
git config core.hooksPath .githooks
```

That tracked hook runs [`scripts/run_local_pre_push.py`](scripts/run_local_pre_push.py), which maps known `codex/pr08...`, `codex/pr09...`, and `codex/pr10...` branches, plus `codex/pr11...` branches, to the canonical local verify pipeline, then requires `git diff --exit-code` to remain clean. The hook is verify-only; it does not run `ratchet` for you. Unknown milestone branches fail closed until the mapping is updated.

When you intentionally want to advance ratchet-owned generated outputs, use the canonical pipeline commands directly:

```bash
python3 scripts/run_gate_pipeline.py ratchet --authority local
python3 scripts/run_gate_pipeline.py verify --authority local
```

Run `ratchet` to advance the tracked outputs under `execution/reports/` and `execution/dashboard.md`, review and commit any accepted generated diffs, then run `verify` before `git push`.

### Ratchet Recovery

If a prior `ratchet` left generated diffs behind, make an explicit operator choice before starting a fresh `ratchet`:

- `accept ratchet artifact`: review the ratchet-owned generated diffs and commit them.
- `restore ratchet baseline`: deliberately restore only `execution/reports/` and `execution/dashboard.md` to the committed baseline before retrying.

Example deliberate recovery action for `restore ratchet baseline` only:

```bash
git restore --source=HEAD --worktree -- execution/reports execution/dashboard.md
```

---

## Status

| Property | Value |
|----------|-------|
| Spec version | Working Draft v0.1 |
| Frozen spec commit | `468cf72332724b04b7c193b4d2a3b02f1584125d` |
| Generator | spec2spark v0.1.0 |
| Companion status | All 13 companion tasks complete |
| Emission templates | 14/14 proved (320 VCs, 0 unproved; M1–M7 complete) |
| Compiler frontend | `compiler_impl/` current baseline: the exact current Rule 5 fixture corpus, sequential ownership, the PR11.2 text/case slice, and the PR11.3 discriminant/tuple/structured-return slice, with Ada-native `safec lex` / `ast` / `validate-mir` / `analyze-mir` / `check` / `emit` |

The repository now includes an Ada-native compiler frontend under `compiler_impl/`. The current frontend supports the exact current Rule 5 fixture corpus, sequential ownership, the accepted local-only PR08.2 concurrency checking slice, the PR08.3 interface-contract slice for `safei-v1` emission plus imported resolution through explicit `--interface-search-dir` inputs, the PR08.3a additive constant slice for ordinary `X : constant T = Expr;` declarations plus imported integer/boolean constant values in the current static-expression sites, and the PR08.4 transitive integration slice for imported-summary consumption plus cross-package ownership/channel-ceiling analysis. It provides Ada-native `safec lex`, `ast`, `validate-mir`, `analyze-mir`, `check`, and `emit` for that supported surface, while Python remains glue/orchestration only around the compiler. The old shallow legacy frontend chain is gone. PR08 is now the supported frontend baseline, and later work continues on that live Ada-native path rather than reviving deleted packages. `safec emit --ada-out-dir` can now additionally write deterministic Ada/SPARK artifacts for the current PR09 subset, including `.ads` / `.adb`, optional `safe_runtime.ads`, and optional `gnat.adc`. PR10 adds selected emitted-output GNATprove verification for Rules 1-5, ownership, and the current concurrency emission corpus; supplemental hardening then extends emitted regression coverage outside that frozen PR10 corpus without changing the milestone claim. PR10.1 then audits the current post-PR10 claim surfaces, normalises the residual ledger, and defines the next tracked follow-on series starting at `PR10.2`. PR11.1 adds the repo-local `safe` prototype launcher, the disposable VSCode grammar and diagnostics shim under `editors/vscode/`, and the starter Rosetta corpus under `samples/rosetta/` while keeping that milestone compile-only rather than proof-bearing. PR11.2 then extends the Ada-native frontend with string and character literals, strict `case` statements, and a narrow immutable `string` surface lowered to Ada `String` for parameter, return, constant, and literal use sites. PR11.3 then broadens that frontend with general scalar record discriminants, explicit discriminant constraints, tuple types/returns/destructuring/channel elements, and the builtin structured-return `result` surface while keeping the milestone compile-only rather than proof-bearing. PR11.4 then completes the deliberate source-syntax cutover to all-`function` callables, `returns`, `else if`, and `to`, removes the legacy spellings from accepted Safe source, and keeps typing, MIR, `safei`, and emitted Ada semantics stable for already-supported programs. [`docs/emitted_output_verification_matrix.md`](docs/emitted_output_verification_matrix.md) is the canonical emitted-output coverage statement, [`docs/pr10_refinement_audit.md`](docs/pr10_refinement_audit.md) is the canonical audit record, and [`docs/post_pr10_scope.md`](docs/post_pr10_scope.md) records the retained residual backlog beyond the frozen selected proof corpus.

See [`docs/frontend_architecture_baseline.md`](docs/frontend_architecture_baseline.md) for the current compiler boundary, [`docs/frontend_scale_limits.md`](docs/frontend_scale_limits.md) for the current scale policy, [`docs/emitted_output_verification_matrix.md`](docs/emitted_output_verification_matrix.md) for emitted-output assurance coverage, and [`compiler_impl/README.md`](compiler_impl/README.md) for the workspace-level output and verification details.


---

## Contributing

Open an issue before submitting a pull request. Areas of particular interest:

- Compiler implementation
- Test cases for D27 rules and language features
- Specification review and feedback

---

## Licence

No licence file exists yet. All rights reserved until a licence is chosen.
