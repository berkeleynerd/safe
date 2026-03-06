# Execution Dashboard

- **Schema version:** `1`
- **Frozen spec SHA:** `468cf72332724b04b7c193b4d2a3b02f1584125d`
- **Active task:** `none`
- **Next task:** `PR05`
- **Updated at:** `2026-03-06T13:50:00Z`

## Repo Facts

- `tests/positive`: 32
- `tests/negative`: 35
- `tests/golden`: 3
- `tests/concurrency`: 5
- `tests/diagnostics_golden`: 5
- **Total test files:** 80

## Task Ledger

| Task | Status | Depends On | Evidence |
|------|--------|------------|----------|
| PR00 | done | -- | 2 |
| PR01 | done | PR00 | 4 |
| PR02 | done | PR01 | 3 |
| PR03 | done | PR02 | 4 |
| PR04 | done | PR03 | 5 |
| PR05 | ready | PR04 | 0 |
| PR06 | planned | PR05 | 0 |
| PR07 | planned | PR06 | 0 |
| PR08 | planned | PR07 | 0 |
| PR09 | planned | PR08 | 0 |
| PR10 | planned | PR09 | 0 |

## Acceptance Snapshot

### PR00 — Execution ledger, drift reconciliation, and CI guard

- **Status:** `done`
- **Depends on:** --
- **Blockers:** none
- **Acceptance:**
  - Frozen-SHA references in README.md, release/status_report.md, and release/COMPANION_README.md match meta/commit.txt.
  - execution/tracker.json validates and execution/dashboard.md is freshly rendered.
  - scripts/validate_execution_state.py passes schema, dependency, evidence, frozen-SHA, and test-distribution checks.
  - CI contains a uniquely named execution-guard job.
- **Evidence:**
  - `execution/reports/pr00-pr04-verification.md`
  - `execution/sessions/20260306-1148-pr00-pr04.md`

### PR01 — compiler_impl workspace, safec CLI, and harness entrypoint

- **Status:** `done`
- **Depends on:** PR00
- **Blockers:** none
- **Acceptance:**
  - compiler_impl contains alire.toml, a GPR project, and a buildable SafeC source tree.
  - safec ast/check/emit exist with stable exit codes and deterministic diagnostics.
  - A repository harness can invoke the compiler on representative corpus inputs.
- **Evidence:**
  - `compiler_impl/alire.toml`
  - `compiler_impl/compiler_impl.gpr`
  - `scripts/run_frontend_smoke.py`
  - `execution/reports/pr00-pr04-frontend-smoke.json`

### PR02 — Lexer with exact spans and deterministic lex diagnostics

- **Status:** `done`
- **Depends on:** PR01
- **Blockers:** none
- **Acceptance:**
  - Lexer tokenizes current Safe syntax with exact source spans.
  - Lex diagnostics are deterministic for repeated runs on the same input.
  - Representative tests cover current syntax and banned legacy tokens.
- **Evidence:**
  - `compiler_impl/src/safe_frontend-lexer.ads`
  - `compiler_impl/src/safe_frontend-lexer.adb`
  - `execution/reports/pr00-pr04-frontend-smoke.json`

### PR03 — Parser, AST JSON export, and schema validation

- **Status:** `done`
- **Depends on:** PR02
- **Blockers:** none
- **Acceptance:**
  - Recursive-descent parser recovers at semicolon and end boundaries.
  - safec ast emits deterministic JSON for representative corpus inputs.
  - AST JSON validates against compiler/ast_schema.json using the repo validation script.
- **Evidence:**
  - `compiler_impl/src/safe_frontend-parser.ads`
  - `compiler_impl/src/safe_frontend-parser.adb`
  - `scripts/validate_ast_output.py`
  - `execution/reports/pr00-pr04-frontend-smoke.json`

### PR04 — Typed AST, .safei.json v0, and MIR/CFG lowering

- **Status:** `done`
- **Depends on:** PR03
- **Blockers:** none
- **Acceptance:**
  - Name resolution and retained-library/removed-feature checks run deterministically.
  - safec emit writes deterministic .safei.json output.
  - typed AST lowers to MIR/CFG and MIR serialization is stable across repeated runs.
  - Later analysis entrypoints consume MIR instead of parser AST.
- **Evidence:**
  - `compiler_impl/src/safe_frontend-semantics.ads`
  - `compiler_impl/src/safe_frontend-semantics.adb`
  - `compiler_impl/src/safe_frontend-mir.ads`
  - `compiler_impl/src/safe_frontend-mir.adb`
  - `execution/reports/pr00-pr04-frontend-smoke.json`

### PR05 — D27 Rules 1-4 diagnostics on MIR

- **Status:** `ready`
- **Depends on:** PR04
- **Blockers:** none
- **Acceptance:**
  - Rules 1-4 diagnostics match existing diagnostics goldens byte-for-byte.

### PR06 — Ownership, lifetime, and deallocation planning on MIR

- **Status:** `planned`
- **Depends on:** PR05
- **Blockers:** none
- **Acceptance:**
  - Ownership diagnostics are deterministic and double-move golden matches byte-for-byte.

### PR07 — Rule 5 and discriminant/result safety

- **Status:** `planned`
- **Depends on:** PR06
- **Blockers:** none
- **Acceptance:**
  - A canonical Rule 5 diagnostic golden exists and matches byte-for-byte.

### PR08 — Concurrency legality and Bronze summaries

- **Status:** `planned`
- **Depends on:** PR07
- **Blockers:** none
- **Acceptance:**
  - Task/channel/select legality checks and deterministic Bronze summaries exist.

### PR09 — Ada/SPARK emission and snapshot refresh

- **Status:** `planned`
- **Depends on:** PR08
- **Blockers:** none
- **Acceptance:**
  - PR09a emitter MVP is deterministic on a narrow subset.
  - PR09b replaces historical golden Ada snapshots once emitter output is stable.
  - Concurrency-enabled output includes gnat.adc with sequential elaboration and Jorvik profile pragmas.

### PR10 — GNATprove flow/prove gate on emitted output

- **Status:** `planned`
- **Depends on:** PR09
- **Blockers:** none
- **Acceptance:**
  - Selected emitted outputs build and pass GNATprove flow/prove with zero unproved checks.
