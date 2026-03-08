# Execution Dashboard

- **Schema version:** `1`
- **Frozen spec SHA:** `468cf72332724b04b7c193b4d2a3b02f1584125d`
- **Active task:** `PR06.7`
- **Next task:** `PR06.7`
- **Updated at:** `2026-03-07T23:55:13Z`

## Repo Facts

- `tests/positive`: 35
- `tests/negative`: 43
- `tests/golden`: 3
- `tests/concurrency`: 5
- `tests/diagnostics_golden`: 14
- **Total test files:** 100

## Task Ledger

| Task | Status | Depends On | Evidence |
|------|--------|------------|----------|
| PR00 | done | -- | 2 |
| PR01 | done | PR00 | 4 |
| PR02 | done | PR01 | 3 |
| PR03 | done | PR02 | 4 |
| PR04 | done | PR03 | 5 |
| PR05 | done | PR04 | 3 |
| PR06 | done | PR05 | 2 |
| PR06.5 | done | PR06 | 3 |
| PR06.6 | done | PR06.5 | 1 |
| PR06.7 | in_progress | PR06.6 | 0 |
| PR07 | planned | PR06.7 | 0 |
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

### PR05 — Real sequential AST/MIR and D27 Rules 1-4 with moved/freed overlap

- **Status:** `done`
- **Depends on:** PR04
- **Blockers:** none
- **Acceptance:**
  - safec ast emits schema-true executable bodies and expressions for the sequential Rule 1–4 subset (no stub bodies).
  - scripts/validate_ast_output.py enforces recursive NodeRef validation for implemented sequential nodes.
  - safec emit produces deterministic typed-v1 and mir-v1 outputs on representative sequential Rule 1–4 inputs.
  - All D27 Rule 1–4 analysis runs on mir-v1 only; the statement-walk semantic path is no longer used for Rule 1–4 checking.
  - safec validate-mir validates representative mir-v1 outputs and the PR05 harness fails on MIR contract violations.
  - Byte-for-byte stderr match for tests/diagnostics_golden: diag_overflow.txt, diag_index_oob.txt, diag_zero_div.txt, diag_null_deref.txt.
  - All Rule 1–4 semantic failures use the D27 renderer for human stderr, while `safec check --diag-json` provides machine-readable diagnostics for harness and CI.
  - Whole current Rule 1–4 corpus gating: all tests/positive/rule1*..rule4* accept; all tests/negative/neg_rule1*..neg_rule4* reject with expected primary reason mapping.
  - Minimal ownership overlap implemented for Rule 4: neg_rule4_moved.safe and neg_rule4_freed.safe behave as expected, while other ownership legality remains PR06 scope.
  - A committed PR05 harness evidence report exists under execution/reports/ and is referenced in tracker.json.
- **Evidence:**
  - `execution/reports/pr05-d27-report.json`
  - `execution/sessions/20260306-1948-pr05.md`
  - `execution/sessions/20260306-2358-pr05-completion.md`

### PR06 — Full sequential ownership legality and diagnostics on MIR

- **Status:** `done`
- **Depends on:** PR05
- **Blockers:** none
- **Acceptance:**
  - Full sequential ownership legality on MIR is implemented for spec/02-restrictions.md section 2.3, excluding channel-triggered move forms deferred to later concurrency milestones.
  - Ownership legality covers move assignment, access-valued returns, out/in out access parameter flows, null-before-move, borrow freeze, observe freeze, anonymous-access initialisation-only, and lifetime containment.
  - safec emit produces deterministic typed-v2 and mir-v2 outputs for representative ownership samples.
  - safec validate-mir validates representative mir-v2 outputs, while remaining compatible with the existing PR05 mir-v1 gate.
  - All ownership semantic failures use the rich code-frame renderer for human stderr, and `safec check --diag-json` exposes stable ownership reasons.
  - Ownership negative diagnostics match committed goldens byte-for-byte, including diag_double_move.txt and the expanded ownership diagnostics set.
  - Ownership positive and negative corpus gating passes, including the expanded tests for null-before-move, anonymous-access reassignment, spec-aligned observe via .Access, observe freeze, access-valued return moves, and in out access moves.
  - A dedicated pr06-ownership-harness CI job passes and a committed execution/reports/pr06-ownership-report.json artifact is listed in PR06 evidence.
- **Evidence:**
  - `execution/reports/pr06-ownership-report.json`
  - `execution/sessions/20260307-1510-pr06.md`

### PR06.5 — Frontend runtime decision and Ada MIR validator cutover

- **Status:** `done`
- **Depends on:** PR06
- **Blockers:** none
- **Acceptance:**
  - A recorded decision document states that Python is transitional only and locks the staged Ada replacement order for the frontend runtime.
  - safec validate-mir exists as an Ada-native MIR contract validator for mir-v1 and mir-v2.
  - The Ada validator enforces the same structural MIR checks as the prior Python validator for representative fixtures and emitted MIR samples.
  - PR05 and PR06 harnesses, CI jobs, and repository docs use safec validate-mir instead of depending on the legacy Python MIR validator.
  - A dedicated pr065-ada-mir-validator CI job passes and a committed execution/reports/pr065-ada-mir-validator-report.json artifact is listed in PR06.5 evidence.
- **Evidence:**
  - `release/frontend_runtime_decision.md`
  - `execution/reports/pr065-ada-mir-validator-report.json`
  - `execution/sessions/20260307-1617-pr065.md`

### PR06.6 — Ada MIR analyzer parity and Python analysis delegation removal

- **Status:** `done`
- **Depends on:** PR06.5
- **Blockers:** none
- **Acceptance:**
  - A typed Ada MIR model exists for mir-v1 and mir-v2 and is used by both safec validate-mir and safec analyze-mir.
  - safec analyze-mir and safec analyze-mir --diag-json consume MIR only and emit diagnostics-v0 compatible with the existing PR05 and PR06 corpus expectations.
  - The Python backend no longer calls its in-process MIR analyzer and instead delegates MIR analysis to safec analyze-mir.
  - Existing PR05 and PR06 harnesses stay green without diagnostic golden changes after the analysis delegation cutover.
  - A dedicated pr066-ada-mir-analyzer CI job passes and a committed execution/reports/pr066-ada-mir-analyzer-report.json artifact is listed in PR06.6 evidence.
- **Evidence:**
  - `execution/reports/pr066-ada-mir-analyzer-report.json`

### PR06.7 — Ada-native safec check cutover for the PR05/PR06 subset

- **Status:** `in_progress`
- **Depends on:** PR06.6
- **Blockers:** none
- **Acceptance:**
  - safec check and safec check --diag-json are Ada-native for the currently supported PR05 and PR06 subset, while ast and emit remain Python-backed.
  - Human stderr rendering and diagnostics-v0 output stay compatible with the existing PR05 and PR06 goldens and corpus harnesses.
  - Source constructs outside the current PR05 and PR06 subset are rejected deterministically by the Ada check path.
  - A dedicated pr067-ada-check-no-python CI job passes with python3 intentionally unavailable to the check command.
  - A committed execution/reports/pr067-ada-check-cutover-report.json artifact is listed in PR06.7 evidence.

### PR07 — Rule 5 and discriminant/result safety

- **Status:** `planned`
- **Depends on:** PR06.7
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
