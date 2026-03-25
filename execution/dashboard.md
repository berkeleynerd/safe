# Execution Dashboard

- **Schema version:** `1`
- **Frozen spec SHA:** `468cf72332724b04b7c193b4d2a3b02f1584125d`
- **Active task:** `none`
- **Next task:** `PR11.8`
- **Updated at:** `2026-03-25T00:00:00Z`

## Repo Facts

- `tests/positive`: 67
- `tests/negative`: 134
- `tests/golden`: 3
- `tests/concurrency`: 14
- `tests/diagnostics_golden`: 22
- **Total test corpus entries:** 240

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
| PR06.7 | done | PR06.6 | 1 |
| PR06.8 | done | PR06.7 | 2 |
| PR06.9.1 | done | PR06.8 | 1 |
| PR06.9.2 | done | PR06.9.1 | 1 |
| PR06.9.3 | done | PR06.9.2 | 1 |
| PR06.9.4 | done | PR06.9.3 | 1 |
| PR06.9.5 | done | PR06.9.4 | 1 |
| PR06.9.6 | done | PR06.9.5 | 1 |
| PR06.9.7 | done | PR06.9.6 | 1 |
| PR06.9.8 | done | PR06.9.7 | 1 |
| PR06.9.9 | done | PR06.9.8 | 1 |
| PR06.9.10 | done | PR06.9.9 | 1 |
| PR06.9.11 | done | PR06.9.10 | 1 |
| PR06.9.12 | done | PR06.9.11 | 1 |
| PR06.9.13 | done | PR06.9.12 | 1 |
| PR07 | done | PR06.9.13 | 1 |
| PR08.1 | done | PR07 | 1 |
| PR08.2 | done | PR08.1 | 1 |
| PR08.3 | done | PR08.2 | 1 |
| PR08.3a | done | PR08.3 | 1 |
| PR08.4 | done | PR08.3 | 1 |
| PR08 | done | PR08.4 | 1 |
| PR09 | done | PR08 | 6 |
| PR10 | done | PR09 | 4 |
| PR10.1 | done | PR10 | 3 |
| PR10.2 | done | PR10.1 | 1 |
| PR10.3 | done | PR10.1 | 1 |
| PR10.4 | done | PR10.1 | 1 |
| PR10.5 | done | PR10.1 | 1 |
| PR10.6 | done | PR10.3 | 1 |
| PR11.1 | done | PR10.4, PR10.5, PR10.6 | 1 |
| PR11.2 | done | PR11.1 | 1 |
| PR11.3 | done | PR11.2 | 1 |
| PR11.3a | done | PR11.3 | 1 |
| PR11.4 | done | PR11.3a | 1 |
| PR11.5 | done | PR11.4 | 1 |
| PR11.6 | done | PR11.5 | 1 |
| PR11.6.1 | done | PR11.6 | 1 |
| PR11.6.2 | done | PR11.6.1 | 1 |
| PR11.7 | done | PR11.6.2 | 1 |
| PR11.8 | planned | PR11.7 | 0 |
| PR11.8a | planned | PR11.8, PR11.3a | 0 |
| PR11.8b | planned | PR10.5, PR10.6 | 0 |
| PR11.8c | planned | PR11.8a | 0 |
| PR11.8d | planned | PR11.8c | 0 |
| PR11.8e | planned | PR11.8d | 0 |
| PR11.8f | planned | PR11.8e | 0 |
| PR11.8g | planned | PR11.8f, PR11.8b | 0 |
| PR11.9 | planned | PR11.8g | 0 |
| PR11.10 | planned | PR11.9 | 0 |
| PR11.11 | planned | PR11.10 | 0 |

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
  - `execution/reports/execution-state-validation-report.json`
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

- **Status:** `done`
- **Depends on:** PR06.6
- **Blockers:** none
- **Acceptance:**
  - PR06.7 made safec check and safec check --diag-json Ada-native for the currently supported PR05 and PR06 subset; PR06.8 later removed the remaining Python runtime dependency from ast and emit.
  - Human stderr rendering and diagnostics-v0 output stay compatible with the existing PR05 and PR06 goldens and corpus harnesses.
  - Source constructs outside the current PR05 and PR06 subset are rejected deterministically by the Ada check path.
  - A dedicated pr067-ada-check-no-python CI job passes with python3 intentionally unavailable to the check command.
  - A committed execution/reports/pr067-ada-check-cutover-report.json artifact is listed in PR06.7 evidence.
- **Evidence:**
  - `execution/reports/pr067-ada-check-cutover-report.json`

### PR06.8 — Ada-native safec ast/emit cutover and Python-as-glue doctrine

- **Status:** `done`
- **Depends on:** PR06.7
- **Blockers:** none
- **Acceptance:**
  - The runtime policy explicitly states that Python is allowed only as glue/orchestration and may not own parser, lowering, semantic, diagnostic-selection, or emitted-artifact behavior for user-facing safec commands.
  - safec ast is Ada-native for the current PR05/PR06 subset and emits deterministic schema-true AST JSON for representative corpus inputs.
  - safec emit is Ada-native for the current PR05/PR06 subset and writes deterministic .ast.json, typed-v2, mir-v2, and safei-v0 artifacts without spawning Python.
  - safec emit fails before writing artifacts when source or MIR diagnostics exist.
  - A dedicated pr068-ada-ast-emit-no-python CI job passes with python3 intentionally unavailable to direct ast/emit command invocations, and a committed execution/reports/pr068-ada-ast-emit-no-python-report.json artifact is listed in PR06.8 evidence.
- **Evidence:**
  - `release/frontend_runtime_decision.md`
  - `execution/reports/pr068-ada-ast-emit-no-python-report.json`

### PR06.9.1 — Semantic correctness hardening

- **Status:** `done`
- **Depends on:** PR06.8
- **Blockers:** none
- **Acceptance:**
  - Range, ownership, return, and call semantics are revalidated across the current PR05/PR06 subset with targeted new regressions.
  - No current positive or negative corpus behavior regresses under safec check, safec emit, or safec analyze-mir.
  - The hardening evidence makes semantic parity the primary success criterion before PR07 begins.
- **Evidence:**
  - `execution/reports/pr0691-semantic-correctness-report.json`

### PR06.9.2 — Lowering and CFG integrity hardening

- **Status:** `done`
- **Depends on:** PR06.9.1
- **Blockers:** none
- **Acceptance:**
  - Lowering preserves declared types, declaration-init semantics, scope structure, and package-global visibility into MIR.
  - Reachable blocks are always terminated, and any unreachable structural patching is explicit and regression-covered.
  - Direct emit, check, and analyze-mir gates enforce CFG and lowering invariants beyond schema validity.
- **Evidence:**
  - `execution/reports/pr0692-lowering-cfg-integrity-report.json`

### PR06.9.3 — Runtime-boundary enforcement hardening

- **Status:** `done`
- **Depends on:** PR06.9.2
- **Blockers:** none
- **Acceptance:**
  - No user-facing safec path can spawn Python or reintroduce removed backend glue.
  - Static and dynamic guardrails catch runtime-boundary regressions early in local verification and CI.
  - Docs and gates clearly distinguish Ada-native runtime surfaces from Python glue.
- **Evidence:**
  - `execution/reports/pr0693-runtime-boundary-report.json`

### PR06.9.4 — Output contract stability hardening

- **Status:** `done`
- **Depends on:** PR06.9.3
- **Blockers:** none
- **Acceptance:**
  - ast, typed-v2, mir-v2, and safei-v0 remain deterministic and contract-valid on representative samples.
  - Contract drift is caught by dedicated validation and repeated-run comparisons.
  - Artifact ordering, path handling, and format-tag behavior stay stable for current consumers.
- **Evidence:**
  - `execution/reports/pr0694-output-contract-stability-report.json`

### PR06.9.5 — Diagnostic stability hardening

- **Status:** `done`
- **Depends on:** PR06.9.4
- **Blockers:** none
- **Acceptance:**
  - Human stderr and diagnostics-v0 remain stable for current goldens and reason mappings.
  - First-diagnostic selection, exit codes, spans, highlight spans, and source_path behavior are regression-covered.
  - Direct check and analyze-mir paths do not diverge in reason selection or payload shape.
- **Evidence:**
  - `execution/reports/pr0695-diagnostic-stability-report.json`

### PR06.9.6 — Unsupported-feature boundary hardening

- **Status:** `done`
- **Depends on:** PR06.9.5
- **Blockers:** none
- **Acceptance:**
  - Out-of-subset constructs reject deterministically as unsupported_source_construct or source_frontend_error according to documented rules.
  - No unsupported construct falls through to partial lowering or an internal failure on representative fixtures.
  - Unsupported-feature coverage is widened across parser, resolver, and emitter entrypoints.
- **Evidence:**
  - `execution/reports/pr0696-unsupported-feature-boundary-report.json`

### PR06.9.7 — Regression coverage and gate quality

- **Status:** `done`
- **Depends on:** PR06.9.6
- **Blockers:** none
- **Acceptance:**
  - Existing gates remain the parity proof where appropriate, and direct command gates gain targeted negative and invariant cases.
  - Hardening checks cover lex, parse, resolve, lower, analyze, and export boundaries rather than only end-to-end happy paths.
  - Execution reports remain deterministic and high-signal.
- **Evidence:**
  - `execution/reports/pr0697-gate-quality-report.json`

### PR06.9.8 — Dormant legacy package cleanup

- **Status:** `done`
- **Depends on:** PR06.9.7
- **Blockers:** none
- **Acceptance:**
  - A reachability audit proves which legacy frontend packages are still on any live safec runtime path.
  - Truly dead legacy packages are removed, and any temporarily retained inactive package is explicitly marked non-runtime.
  - The live safec runtime path no longer references dormant parser, semantics, or MIR packages unnecessarily.
- **Evidence:**
  - `execution/reports/pr0698-legacy-package-cleanup-report.json`

### PR06.9.9 — Build and reproducibility hardening

- **Status:** `done`
- **Depends on:** PR06.9.8
- **Blockers:** none
- **Acceptance:**
  - alr build, project wiring, and report generation remain deterministic across repeated local and CI runs.
  - No milestone evidence depends on transient timing, unordered JSON, or host-specific file layout.
  - Repeated command runs produce byte-stable outputs where the contract requires determinism.
- **Evidence:**
  - `execution/reports/pr0699-build-reproducibility-report.json`

### PR06.9.10 — Portability and environment assumptions

- **Status:** `done`
- **Depends on:** PR06.9.9
- **Blockers:** none
- **Acceptance:**
  - PATH lookup, temp-dir use, SDK or tool discovery, and shell assumptions are explicit and documented.
  - The supported-platform policy for compiler and glue gates is written down and tested where practical.
  - No-Python runtime enforcement covers the documented interpreter names and invocation patterns.
- **Evidence:**
  - `execution/reports/pr06910-portability-environment-report.json`

### PR06.9.11 — Glue-script safety

- **Status:** `done`
- **Depends on:** PR06.9.10
- **Blockers:** none
- **Acceptance:**
  - Python glue remains argv-based, shell-free by default, and limited to orchestration and validation duties.
  - Temporary files, subprocess handling, and report writes follow deterministic and safe patterns.
  - No glue script becomes a second semantic source of truth for Safe source or compiler decisions.
- **Evidence:**
  - `execution/reports/pr06911-glue-script-safety-report.json`

### PR06.9.12 — Performance and scale sanity

- **Status:** `done`
- **Depends on:** PR06.9.11
- **Blockers:** none
- **Acceptance:**
  - Representative repeated check, emit, and analyze-mir runs are measured enough to catch obvious regression cliffs.
  - Serialization and analysis paths avoid pathological behavior on current corpus sizes.
  - Any known scale limits for the current frontend subset are documented.
- **Evidence:**
  - `execution/reports/pr06912-performance-scale-sanity-report.json`

### PR06.9.13 — Documentation and architectural clarity

- **Status:** `done`
- **Depends on:** PR06.9.12
- **Blockers:** none
- **Acceptance:**
  - Runtime path, supported subset, no-Python doctrine, and legacy-versus-live package ownership are documented consistently.
  - The roadmap, dashboard, and frontend docs agree on the current compiler boundary before PR07 begins.
  - PR07 starts from the cleaned architectural baseline established by the PR06.9 hardening series.
- **Evidence:**
  - `execution/reports/pr06913-documentation-architecture-clarity-report.json`

### PR07 — Rule 5 and discriminant/result safety

- **Status:** `done`
- **Depends on:** PR06.9.13
- **Blockers:** none
- **Acceptance:**
  - The supported frontend subset is the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern.
  - All frozen Rule 5 positives accept, and all frozen Rule 5 negatives reject with their current expected reasons.
  - result_guarded_access.safe accepts, while neg_result_unguarded.safe and neg_result_mutated.safe reject with discriminant_check_not_established.
  - Representative check --diag-json and analyze-mir --diag-json cases match exactly on normalized first-diagnostic reason, message, span, highlight_span, notes, suggestions, and path.
  - Representative Rule 5 and result-record emitted AST, typed, MIR, and safei outputs remain valid under validate_ast_output.py, validate_output_contracts.py, and safec validate-mir, with additive-only float and discriminant metadata.
  - Only the newly supported floating-point Rule 5 cases and the current boolean result-record cases are removed from the unsupported boundary; fixed-point remains unsupported.
  - Canonical Rule 5 and result/discriminant goldens match byte-for-byte and are wired into the canonical golden map.
  - Tracker, dashboard, and frontend docs agree on the frozen PR07 subset and hand off the next planned work to the PR08 concurrency series.
- **Evidence:**
  - `execution/reports/pr07-rule5-result-safety-report.json`

### PR08.1 — Local concurrency frontend

- **Status:** `done`
- **Depends on:** PR07
- **Blockers:** none
- **Acceptance:**
  - Single-package task/channel/select sources parse, resolve, lower, and emit deterministically on the live Ada-native frontend path.
  - safec ast, emit, and validate-mir handle local task declarations, channel declarations, send, receive, try_send, try_receive, select, and relative delay.
  - Task/channel/select legality and task non-termination restrictions reject malformed local concurrency sources deterministically.
  - typed-v2 and mir-v2 gain additive local task/channel metadata and explicit concurrency ops without changing the dependency-interface artifact.
- **Evidence:**
  - `execution/archive/pr081_local_concurrency_frontend/report.json`

### PR08.2 — Local concurrency Bronze and Silver analysis

- **Status:** `done`
- **Depends on:** PR08.1
- **Blockers:** none
- **Acceptance:**
  - Local-only Bronze summaries exist for task/channel programs, covering deterministic Global, Depends, and Initializes equivalents, task-variable ownership, and local channel-access and ceiling summaries.
  - Channel declarations reject access-typed element types and composite element types containing access-type subcomponents.
  - Representative local concurrency cases stay in parity between safec check --diag-json and emitted safec analyze-mir --diag-json.
  - The accepted local concurrency corpus includes exclusive_variable.safe, channel_pingpong.safe, and select_priority.safe.
- **Evidence:**
  - `execution/archive/pr082_local_concurrency_analysis/report.json`

### PR08.3 — Interface contracts and cross-package resolution

- **Status:** `done`
- **Depends on:** PR08.2
- **Blockers:** none
- **Acceptance:**
  - safec ast, check, and emit accept repeatable --interface-search-dir flags while emit keeps --interface-dir for output.
  - safei-v1 is emitted with public declaration data plus effect and channel-access summaries derived from the local Bronze pass.
  - Package-qualified resolution can consume imported interfaces for public types, subtypes, channels, objects, and subprogram signatures without reading dependency source.
  - Missing interfaces and duplicate same-package matches in one search dir fail deterministically as source_frontend_error.
  - safei-v1.objects[] remains additively extensible for later constant payload fields without requiring another format bump.
- **Evidence:**
  - `execution/archive/pr083_interface_contracts/report.json`

### PR08.3a — Public constants and imported constant values

- **Status:** `done`
- **Depends on:** PR08.3
- **Blockers:** none
- **Acceptance:**
  - Ordinary package-level X : constant T = Expr declarations are supported on the live Ada-native path and preserve constant-ness through parse, resolve, and emit.
  - safei-v1.objects[] grows additively with is_constant plus optional static_value and static_value_kind fields for the supported static subset.
  - Provider/client fixtures prove imported public constants work in package-qualified static contexts without changing typed-v2, mir-v2, or adding new CLI JSON surfaces.
  - Missing or invalid imported constant values fail deterministically and safei-v1 constant payloads remain validator-covered and deterministic.
  - A dedicated PR08.3a gate and report cover imported public constants and keep committed evidence up to date.
- **Evidence:**
  - `execution/archive/pr083a_public_constants/report.json`

### PR08.4 — Transitive concurrency integration and baseline flip

- **Status:** `done`
- **Depends on:** PR08.3
- **Blockers:** none
- **Acceptance:**
  - Imported safei-v1 summaries are consumed transitively for cross-package task ownership, channel-access, and channel ceiling analysis.
  - Representative imported concurrency cases preserve parity between safec check --diag-json and emitted safec analyze-mir --diag-json.
  - A dedicated PR08 gate and report plus CI wiring exist, and unsupported-boundary expectations are updated for the newly supported concurrency surfaces.
  - Tracker, dashboard, and frontend docs flip the supported baseline from PR07 to PR08 and advance next_task_id to PR09.
- **Evidence:**
  - `execution/archive/pr084_transitive_concurrency/report.json`

### PR08 — Concurrency legality and Bronze summaries

- **Status:** `done`
- **Depends on:** PR08.4
- **Blockers:** none
- **Acceptance:**
  - PR08.1 through PR08.4, plus PR08.3a, complete the concurrency frontend, local analysis, interface contracts, ordinary-constant interface coverage, and transitive integration work on the live Ada-native path.
  - The supported frontend subset expands from the PR07 sequential baseline to the PR08 concurrency baseline without reviving deleted legacy packages.
- **Evidence:**
  - `execution/archive/pr08_frontend_baseline/report.json`

### PR09 — Ada/SPARK emission and snapshot refresh

- **Status:** `done`
- **Depends on:** PR08
- **Blockers:** none
- **Acceptance:**
  - PR09a emitter MVP is deterministic on a narrow subset.
  - PR09b replaces historical golden Ada snapshots once emitter output is stable.
  - Concurrency-enabled output includes gnat.adc with sequential elaboration and Jorvik profile pragmas.
- **Evidence:**
  - `execution/archive/pr09a_emitter_surface/report.json`
  - `execution/archive/pr09a_emitter_mvp/report.json`
  - `execution/archive/pr09b_sequential_semantics/report.json`
  - `execution/archive/pr09b_concurrency_output/report.json`
  - `execution/archive/pr09b_snapshot_refresh/report.json`
  - `execution/archive/pr09_ada_emission_baseline/report.json`

### PR10 — GNATprove flow/prove gate on emitted output

- **Status:** `done`
- **Depends on:** PR09
- **Blockers:** none
- **Acceptance:**
  - The selected emitted corpus spans Rules 1-5, ownership, and concurrency through the named PR10 fixtures.
  - Selected emitted outputs build and pass GNATprove flow/prove with zero warnings, zero justified checks, and zero unproved checks.
  - docs/emitted_output_verification_matrix.md is the canonical emitted-output coverage statement, and docs/post_pr10_scope.md records every residual gap beyond the selected corpus.
- **Evidence:**
  - `execution/archive/pr10_contract_baseline/report.json`
  - `execution/archive/pr10_emitted_flow/report.json`
  - `execution/archive/pr10_emitted_prove/report.json`
  - `execution/archive/pr10_emitted_baseline/report.json`

### PR10.1 — Comprehensive assessment and refinement audit

- **Status:** `done`
- **Depends on:** PR10
- **Blockers:** none
- **Acceptance:**
  - Authoritative PR08, PR09, PR10, supplemental hardening, companion/template verification, and execution-state baselines rerun serially and establish the audit truth baseline.
  - docs/pr10_refinement_audit.md classifies every current post-PR10 residual and current PR10/post-PR10 claim surface using the required finding schema and allowed dispositions.
  - docs/post_pr10_scope.md and docs/emitted_output_verification_matrix.md are normalized to the audit outcome, and the first concrete PR10.2+ follow-on tasks are defined in execution/tracker.json.
- **Evidence:**
  - `execution/archive/pr101a_companion_proof_verification/report.json`
  - `execution/archive/pr101b_template_proof_verification/report.json`
  - `execution/reports/pr101-comprehensive-audit-report.json`

### PR10.2 — Rule 5 proof-boundary closure and loop-termination diagnostics

- **Status:** `done`
- **Depends on:** PR10.1
- **Blockers:** none
- **Acceptance:**
  - The exact six-fixture PR10.2 Rule 5 positive corpus is tests/positive/rule5_filter.safe, tests/positive/rule5_interpolate.safe, tests/positive/rule5_normalize.safe, tests/positive/rule5_statistics.safe, tests/positive/rule5_temperature.safe, and tests/positive/rule5_vector_normalize.safe; that merged PR07-plus-PR10 set is non-shrinkable and each fixture is frontend-accepted, Ada-emitted, compile-valid, and passes emitted GNATprove flow and prove under the all-proved-only policy.
  - The source-level Rule 5 negative contract remains tests/negative/neg_rule5_div_zero.safe -> fp_division_by_zero, tests/negative/neg_rule5_infinity.safe -> infinity_at_narrowing, tests/negative/neg_rule5_nan.safe -> nan_at_narrowing, tests/negative/neg_rule5_overflow.safe -> fp_overflow_at_narrowing, and tests/negative/neg_rule5_uninitialized.safe -> fp_uninitialized_at_narrowing; unsupported float-evaluator shapes use the new fp_unsupported_expression_at_narrowing reason under MIR analysis parity coverage instead of being mislabeled as overflow.
  - While loops outside the current derivable Loop_Variant proof surface are rejected during safec check with loop_variant_not_derivable, and a dedicated PR10.2 gate, report, CI job, tracker/docs update, and deterministic diagnostics-golden set capture the resulting Rule 5 plus convergence-loop boundary without weakening the frozen PR10 claim.
- **Evidence:**
  - `execution/reports/pr102-rule5-boundary-closure-report.json`

### PR10.3 — Sequential emitted proof-corpus expansion beyond PR10

- **Status:** `done`
- **Depends on:** PR10.1
- **Blockers:** none
- **Acceptance:**
  - The first PR10.3 ownership expansion corpus consists of tests/positive/ownership_borrow.safe, tests/positive/ownership_observe.safe, tests/positive/ownership_observe_access.safe, tests/positive/ownership_return.safe, tests/positive/ownership_inout.safe, and tests/positive/ownership_early_return.safe, and that named set may not be silently shrunk.
  - Those six ownership fixtures pass compile, GNATprove flow, and GNATprove prove under the all-proved-only policy.
  - docs/emitted_output_verification_matrix.md and related audit/docs surfaces distinguish the frozen PR10 claim from the now-proved PR10.3 ownership expansion set and retarget remaining sequential proof expansion to PR10.6.
  - A dedicated PR10.3 gate, report, and CI wiring keep the expanded sequential proof corpus deterministic and evidence-backed.
- **Evidence:**
  - `execution/reports/pr103-sequential-proof-expansion-report.json`

### PR10.4 — GNATprove evidence and parser hardening

- **Status:** `done`
- **Depends on:** PR10.1
- **Blockers:** none
- **Acceptance:**
  - Pure-Python regression tests cover scripts/run_pr101_comprehensive_audit.py parsing helpers (split_table_row, parse_findings, parse_residuals, parse_summary_counts), including malformed-table cases and multi-target target-cell parsing.
  - The emitted proof and audit harnesses verify explicit gnat.adc application and fail deterministically if concurrency compile/flow/prove commands lose the concrete -gnatec=<ada_dir>/gnat.adc argument.
  - The GNATprove evidence path documents and enforces the repo's proof-repeatability policy for emitted gates, including the current --steps=0 plus bounded-timeout profile and an explicit statement about whether committed session artifacts are part of the reproducibility contract.
  - parse_task_id() is extended to handle three-level milestone IDs (e.g., PR06.9.8) that already exist in the tracker's own task list, so forward-stability checks match the project's actual ID convention rather than silently rejecting valid historical IDs.
  - Dependent deterministic report rollups are de-cascaded so parent reports do not churn solely because child report hashes changed: freshness checks rerun child gates into comparison artifacts or validate stable path-level invariants, and portability/glue/doc hardening reports avoid repo-wide unittest-count summaries that change for unrelated test additions.
  - A dedicated PR10.4 gate, report, and CI job keep the hardened evidence path and parser-regression surface under committed deterministic coverage.
- **Evidence:**
  - `execution/reports/pr104-gnatprove-evidence-parser-hardening-report.json`

### PR10.5 — Ada emitter maintenance hardening

- **Status:** `done`
- **Depends on:** PR10.1
- **Blockers:** none
- **Acceptance:**
  - The three broad Constraint_Error catch-alls in compiler_impl/src/safe_frontend-ada_emit.adb are removed or narrowed so malformed-state failures are not collapsed into generic emitter internal errors.
  - Unreachable post-Raise_Unsupported fallback returns are removed, integer-type classification is made subtype-aware, name-based type lookup/render helpers are unified, and the duplicated Render_Object_Decl_Text bodies are consolidated into one shared implementation path.
  - String-based alias-postcondition 'Old insertion is replaced with AST-aware rendering, with focused regression coverage for similar-name, nested-selector, and repeated-target cases.
  - A dedicated PR10.5 gate, report, and CI job keep the emitter-maintenance refactor deterministic and evidence-backed.
- **Evidence:**
  - `execution/reports/pr105-ada-emitter-maintenance-hardening-report.json`

### PR10.6 — Remaining sequential emitted proof-corpus expansion beyond ownership

- **Status:** `done`
- **Depends on:** PR10.3
- **Blockers:** none
- **Acceptance:**
  - The PR10.6 sequential proof corpus is the exact 27-fixture set consisting of tests/positive/constant_access_deref_write.safe, tests/positive/constant_channel_capacity.safe, tests/positive/constant_discriminant_default.safe, tests/positive/constant_range_bound.safe, tests/positive/constant_shadow_mutable.safe, tests/positive/constant_task_priority.safe, tests/positive/emitter_surface_proc.safe, tests/positive/emitter_surface_record.safe, tests/positive/result_equality_check.safe, tests/positive/result_guarded_access.safe, tests/positive/rule1_accumulate.safe, tests/positive/rule1_conversion.safe, tests/positive/rule1_return.safe, tests/positive/rule2_binary_search.safe, tests/positive/rule2_iteration.safe, tests/positive/rule2_lookup.safe, tests/positive/rule2_matrix.safe, tests/positive/rule2_slice.safe, tests/positive/rule3_average.safe, tests/positive/rule3_modulo.safe, tests/positive/rule3_percent.safe, tests/positive/rule3_remainder.safe, tests/positive/rule4_conditional.safe, tests/positive/rule4_deref.safe, tests/positive/rule4_factory.safe, tests/positive/rule4_linked_list.safe, and tests/positive/rule4_optional.safe; that set may not be silently shrunk.
  - The positive-path concurrency fixtures tests/positive/channel_pingpong.safe, tests/positive/channel_pipeline_compute.safe, and tests/positive/channel_pipeline.safe are explicitly excluded from PR10.6 and remain outside this sequential proof corpus.
  - That exact 27-fixture sequential subset passes compile, GNATprove flow, and GNATprove prove under the all-proved-only policy with dedicated deterministic evidence and emitted-structure/source-fragment assertions.
  - docs/emitted_output_verification_matrix.md, docs/pr10_refinement_audit.md, execution/tracker.json, README.md, and the dedicated PR10.6 gate/CI/local-workflow surfaces distinguish the completed PR10.6 sequential closure from the still-open concurrency/runtime residuals.
- **Evidence:**
  - `execution/reports/pr106-sequential-proof-corpus-expansion-report.json`

### PR11.1 — Language Evaluation Harness

- **Status:** `done`
- **Depends on:** PR10.4, PR10.5, PR10.6
- **Blockers:** none
- **Acceptance:**
  - A one-command `safe build <file.safe>` wrapper, static VSCode grammar, and disposable diagnostics shim exist as explicitly non-frozen tooling surfaces for language evaluation.
  - PR11.1 creates and validates a starter Rosetta/sample corpus consisting of fibonacci.safe, gcd.safe, factorial.safe, collatz_bounded.safe, bubble_sort.safe, binary_search.safe, bounded_stack.safe, and producer_consumer.safe; linked_list_reverse.safe and prime_sieve_pipeline.safe remain candidate expansions, while trapezoidal_rule.safe and newton_sqrt_bounded.safe remain deferred to later numeric work.
  - None of the PR11.1 starter-corpus candidates depend on PR11.2 string/case support, and PR11.1 remains a `safec check` -> `safec emit --ada-out-dir` -> `gprbuild` compile milestone rather than emitted-proof expansion; proof re-enters later via PR11.3a, PR11.8a, and the parallel PR11.8b concurrency track.
- **Evidence:**
  - `execution/reports/pr111-language-evaluation-harness-report.json`

### PR11.2 — Parser Completeness Phase 1

- **Status:** `done`
- **Depends on:** PR11.1
- **Blockers:** none
- **Acceptance:**
  - The parser is extended for string/character literals and case statements without absorbing richer constant-evaluation work (`PS-001`) or named-number support (`PS-010`).
  - Resolver/emitter support and positive/negative tests are added for the accepted string/character and case-statement surface.
  - The Rosetta/sample corpus grows with programs unlocked by strings/chars and case statements after the PR11.1 starter set lands.
- **Evidence:**
  - `execution/reports/pr112-parser-completeness-phase1-report.json`

### PR11.3 — Discriminated Types, Tuples, and Structured Returns

- **Status:** `done`
- **Depends on:** PR11.2
- **Blockers:** none
- **Acceptance:**
  - The accepted subset covers record discriminants only, including multiple scalar discriminants, defaults, explicit constraints on objects/parameters/results, bounded variant-part support, and a compile-only emitted corpus that locks those semantics.
  - Anonymous tuple types, tuple returns/destructuring/field access/channel elements, and the predefined builtin `result` plus `ok` / `fail(String)` conventions are admitted for the current value-type subset rather than being deferred beyond PR11.3.
  - Access discriminants, nested tuples, access/task/channel tuple elements, richer variant alternatives, generic `result` forms, and general user-declared `String` fields remain explicitly deferred rather than being absorbed into the milestone.
- **Evidence:**
  - `execution/reports/pr113-discriminated-types-tuples-structured-returns-report.json`

### PR11.3a — Proof checkpoint 1 for parser, tuple, and discriminant expansion

- **Status:** `done`
- **Depends on:** PR11.3
- **Blockers:** none
- **Acceptance:**
  - The PR11.3a sequential proof checkpoint corpus is the exact 11-fixture set consisting of tests/positive/pr112_character_case.safe, tests/positive/pr112_discrete_case.safe, tests/positive/pr112_string_param.safe, tests/positive/pr112_case_scrutinee_once.safe, tests/positive/pr113_discriminant_constraints.safe, tests/positive/pr113_tuple_destructure.safe, tests/positive/pr113_structured_result.safe, tests/positive/pr113_variant_guard.safe, tests/positive/constant_discriminant_default.safe, tests/positive/result_equality_check.safe, and tests/positive/result_guarded_access.safe; tests/positive/pr113_tuple_channel.safe is explicitly excluded from this sequential checkpoint and its proof debt stays on PR11.8b.
  - That exact checkpoint corpus passes compile, GNATprove flow, and GNATprove prove under the all-proved-only policy with dedicated deterministic evidence, and the checkpoint gate keeps the corpus non-shrinkable with emitted-structure assertions for the PR11.2/PR11.3 surfaces it covers.
  - PR11.3a remains a value-only sequential checkpoint: Rosetta samples stay compile-only, tuple-channel proof remains deferred to PR11.8b, and `PS-029` is explicitly bounded rather than broadened before this checkpoint claims proof closure.
- **Evidence:**
  - `execution/reports/pr113a-proof-checkpoint1-report.json`

### PR11.4 — Full Syntax Cutover for Signatures, Branches, and Ranges

- **Status:** `done`
- **Depends on:** PR11.3a
- **Blockers:** none
- **Acceptance:**
  - PR11.4 is a deliberate cutover rather than a coexistence milestone: legacy `procedure`, signature `return`, `elsif`, and `..` spellings are removed from the admitted Safe source surface once the milestone lands.
  - The full PR11.4 quartet lands together: all callables use `function`, result-bearing signatures use `returns`, conditional chains use `else if`, and source-level inclusive ranges use `to`, while typing/MIR/safei/emitted Ada semantics remain stable for already-supported programs.
  - The `.safe` corpus, Rosetta samples, docs/examples, VSCode grammar/docs, and a dedicated deterministic PR11.4 gate are migrated together, with explicit negative coverage that locks rejection of each removed legacy spelling.
- **Evidence:**
  - `execution/reports/pr114-signature-control-flow-syntax-report.json`

### PR11.5 — Statement Ergonomics

- **Status:** `done`
- **Depends on:** PR11.4
- **Blockers:** none
- **Acceptance:**
  - Optional semicolons and statement-local `var` declarations are the only syntax admissions in scope for this milestone.
  - Semicolon omission is parser-side and bounded to executable statement terminators; declaration semicolons, same-line statement separators, and `case` arm `end when;` separators remain explicit.
  - A dedicated deterministic gate, selective corpus migration, and Rosetta readability evidence demonstrate the additive statement-ergonomics surface while deferring task channel direction constraints and scoped-binding `receive` to PR11.8b.
- **Evidence:**
  - `execution/reports/pr115-statement-ergonomics-report.json`

### PR11.6 — Meaningful Whitespace Blocks

- **Status:** `done`
- **Depends on:** PR11.5
- **Blockers:** none
- **Acceptance:**
  - Meaningful whitespace is the admitted block-structuring surface for covered constructs, and legacy explicit block-closing syntax for those constructs is rejected.
  - The compiler enforces deterministic indentation rules: spaces only, fixed 3-space indentation steps, no accidental mixed-syntax acceptance, and stable structural parsing via indentation tokens.
  - A mechanical migration path and deterministic corpus evidence exist for the shipped whitespace surface for the covered block forms, while deferred post-PR11.6 cleanup of retained Ada spellings lands separately.
- **Evidence:**
  - `execution/reports/pr116-meaningful-whitespace-report.json`

### PR11.6.1 — Attestation Chain Compression

- **Status:** `done`
- **Depends on:** PR11.6
- **Blockers:** none
- **Acceptance:**
  - A generic Merkle tree module computes SHA-256 binary Merkle roots over sorted report paths, with inclusion proof extraction and verification.
  - A compress tool identifies the 19 historically subsumed gate nodes (pr081-pr084, pr09a/pr09b slices, pr10 contract/flow/prove, the pr08/pr09/pr10 baseline rollups, emitted hardening, and pr101a/pr101b companion/template verification) and validates each is transitively subsumed by a live downstream gate.
  - Compression archives each retired report to execution/archive/<gate_id>/ with provenance.json containing report_sha256, Merkle inclusion proof, subsumed_by, and timestamp.
  - The gate manifest is rewritten with retired nodes removed and live-node dependencies rewired to the subsumer.
  - A compaction receipt in execution/compaction-receipts/ binds pre-compaction and post-compaction Merkle roots, retired gate inclusion proofs, and git commit SHAs.
  - The compressed pipeline (37 nodes) passes verify --authority ci with no regressions.
  - Replay: checking out the pre-compaction commit and recomputing the Merkle root reproduces the receipt's pre_merkle_root; each archived report's inclusion proof verifies against that root.
  - Gate scripts for retired nodes remain on disk for replay but are not executed in the active pipeline.
- **Evidence:**
  - `execution/compaction-receipts/pr1161-attestation-chain-compression.json`

### PR11.6.2 — Legacy Ada Syntax Removal

- **Status:** `done`
- **Depends on:** PR11.6.1
- **Blockers:** none
- **Acceptance:**
  - Statement-level `declare` blocks and `declare_expression` are removed from the admitted Safe source surface; straightforward former uses migrate to enclosing-suite `var` declarations and explicit negative coverage locks the removed forms.
  - Source `null` statements, named `exit`, `goto`, `aliased`, and legacy representation-clause syntax are removed from the admitted Safe surface, while empty suites and existing structured control flow remain the only accepted replacements.
  - A dedicated PR11.6.2 gate, migration helper, corpus/docs/spec refresh, and full pipeline verify evidence demonstrate the narrowed post-whitespace source surface without weakening emitted Ada implementation detail.
- **Evidence:**
  - `execution/reports/pr1162-legacy-ada-syntax-removal-report.json`

### PR11.7 — Reference-Surface Experiments

- **Status:** `done`
- **Depends on:** PR11.6.2
- **Blockers:** none
- **Acceptance:**
  - PR11.7 records separate decision outcomes for Capitalisation as Reference Signal and Implicit Dereference rather than silently bundling them into a default syntax cutover.
  - The milestone ships an experiment-only compiler path and deterministic gate/report that evaluate reference-signal casing over a fixed ownership/reference corpus without changing the default admitted source surface.
  - PR11.7 explicitly defers Capitalisation as Reference Signal because it requires case-significant user-name resolution and migration/tooling churn, and it also defers any stronger Implicit Dereference endorsement because the fixed corpus still exposes emitted-Ada divergence from explicit `.all` spellings; Capitalisation as Export Signal and the `move` keyword remain out of scope and unscheduled.
- **Evidence:**
  - `execution/reports/pr117-reference-surface-experiments-report.json`

### PR11.8 — Unified Integer Type

- **Status:** `planned`
- **Depends on:** PR11.7
- **Blockers:** none
- **Acceptance:**
  - A single predefined `integer` type replaces all other predefined integer types; it is 64-bit signed with full range by default.
  - `integer (A to B)` provides inline range constraints at binding sites for parameters, fields, and locals; `subtype` provides named range aliases.
  - Existing `type X is range A to B` becomes equivalent to `subtype X is integer (A to B)`.
  - Wide-intermediate lifting is removed; the default integer is already 64-bit.
  - Integer literals have type `integer` with no conversion required.
  - Array index types must be constrained (bounded).
  - The corpus, samples, and documentation are migrated to the single integer model.

### PR11.8a — Proof checkpoint 2 for numeric-model revalidation

- **Status:** `planned`
- **Depends on:** PR11.8, PR11.3a
- **Blockers:** none
- **Acceptance:**
  - All numeric-sensitive proof fixtures from pr102, pr103, pr106, and pr113a recompile and reprove under the single-integer model.
  - Emitted Ada narrowing assertions adjust to the single-type model.
  - Zero unproved VCs under the all-proved-only policy.

### PR11.8b — Concurrency proof expansion

- **Status:** `planned`
- **Depends on:** PR10.5, PR10.6
- **Blockers:** none
- **Acceptance:**
  - The currently accepted emitted concurrency subset beyond the frozen PR10 representatives and the already-proved supplemental hardening fixture is explicitly enumerated as a non-shrinkable proof corpus: channel_ceiling_priority.safe, exclusive_variable.safe, fifo_ordering.safe, multi_task_channel.safe, select_delay_local_scope.safe, select_priority.safe, task_global_owner.safe, task_priority_delay.safe, and try_ops.safe.
  - Task channel direction constraints (`sends` / `receives`) and scoped-binding `receive` / `try_receive` land alongside PR11.8b's concurrency proof expansion, with legality boundaries and emitted/proof coverage aligned to the admitted concurrency subset rather than staged earlier in PR11.5.
  - That bounded concurrency corpus, plus the admitted PR11.8b source-surface additions, passes compile, GNATprove flow, and GNATprove prove under the all-proved-only policy with dedicated deterministic evidence, without restating spec-excluded fixtures as proof debt.
  - Tracker/docs surfaces keep source-level select semantics (`PS-007`), I/O seam wrapper obligations (`PS-019`), and Jorvik/Ravenscar runtime obligations (`PS-031`) explicitly open even as emitted concurrency proof coverage expands.

### PR11.8c — Modular Arithmetic

- **Status:** `planned`
- **Depends on:** PR11.8a
- **Blockers:** none
- **Acceptance:**
  - `modular (N)` is the sole modular integer kind, wrapping at 2^N for standard widths (8, 16, 32, 64).
  - Explicit conversion is required between `integer` and `modular`; no implicit mixing.
  - Bitwise operations (`and`, `or`, `xor`, `not`, shift) are admitted on `modular` only.
  - No overflow proof obligations for `modular` operations; wraparound is defined behavior.
  - PS-030 is resolved: modular semantics are defined as wraps-at-2^N with explicit boundary conversion.

### PR11.8d — Value-Type String

- **Status:** `planned`
- **Depends on:** PR11.8c
- **Blockers:** none
- **Acceptance:**
  - `string` is a first-class value type: heap-backed, growable, copied on assignment, freed on scope exit.
  - `character` is removed as a separate type; character literals `'A'` produce a single-character string.
  - String literals construct `string` values directly; `&` concatenates and returns a new owned string.
  - `string (N)` provides a compile-time-bounded stack-allocated variant.
  - `.length`, indexing `s(3)`, slicing `s(1 to 5)`, and value equality `==` are built in.
  - `in` parameters borrow without copying; `in out` borrows mutably; assignment copies.
  - The corpus, samples, and documentation are migrated to the unified string model.

### PR11.8e — Copy-Only Value Types

- **Status:** `planned`
- **Depends on:** PR11.8d
- **Blockers:** none
- **Acceptance:**
  - All types are value types by default: assignment copies, no ownership tracking, no move semantics.
  - The compiler infers reference semantics automatically for self-referential types: a record type whose fields directly or transitively contain its own type is a reference type.
  - No `access`, `ref`, or `?` annotation exists in the language surface. The programmer writes `next : node` in a record definition; the compiler infers that the field is heap-indirect, nullable, and ownership-tracked.
  - The capitalization signal enforces reference-type awareness: bindings, fields, and parameters whose type is inferred as reference-typed must start with an uppercase letter. Value-typed bindings must start with a lowercase letter. The compiler rejects violations with a diagnostic that explains why the type is reference-typed.
  - `null` is valid only for reference-typed bindings. Value-typed bindings cannot be null.
  - Assignment of reference-typed bindings moves (source becomes null). Assignment of value-typed bindings copies.
  - `in` parameters borrow (both value and reference types). `in out` borrows mutably.
  - `new` is removed from the language surface. Construction of reference-typed values uses the record constructor directly: `var Head = node (value = 1, Next = null)`. The compiler allocates on the heap automatically.
  - `.all` remains removed from source (PR11.7). Implicit dereference is the only access path.
  - `.access` / `.Access` is removed from the source surface. The compiler handles access-level operations internally.
  - The ownership model (move, borrow, observe, deallocation on scope exit) applies only to reference-typed bindings. The prover tracks ownership only for these bindings.
  - Records and arrays that contain no reference-typed fields (directly or transitively) are pure value types with no ownership, no null, and no move semantics.
  - The language consumer sees: `integer`, `string`, `boolean`, arrays, and records as plain values. Self-referential records automatically become reference types. Uppercase casing is the only visible signal of this distinction.
  - The admitted Safe source, grammar, and documentation remove explicit access-surface constructs: `access`, `ref`, named access types, `new`, `.access` / `.Access`, explicit access parameter modes, explicit deallocation, and value-typed `null`; these remain emitter-internal Ada implementation details only.

### PR11.8f — Proof Checkpoint for Value-Type Model

- **Status:** `planned`
- **Depends on:** PR11.8e
- **Blockers:** none
- **Acceptance:**
  - All proof-bearing fixtures recompile and reprove under the copy-by-default model.
  - Emitted Ada correctly maps value-type copies to Ada assignment and ref-type moves to SPARK ownership transfers.
  - Zero unproved VCs under the all-proved-only policy.
  - Explicit decision record for what remains deferred (generics, fixed-point, broader floating-point).

### PR11.8g — Value-Type Channel Elements

- **Status:** `planned`
- **Depends on:** PR11.8f, PR11.8b
- **Blockers:** none
- **Acceptance:**
  - Channel element types must be value types. The compiler rejects channel declarations whose element type is reference-typed (self-referential, directly or transitively).
  - send copies the value into the channel buffer. receive copies it out. No ownership transfer, no move semantics, no null-before-receive requirement.
  - The diagnostic for rejected reference-typed channel elements explains why the type is reference-typed and suggests flattening the structure into a value-typed representation.
  - Existing concurrency fixtures are updated: any fixture that relied on ownership transfer through channels is rewritten to use value-typed elements.
  - The prover never needs to reason about cross-task ownership transfer through channels.
  - Channel direction constraints (sends/receives from PR11.8b) remain valid and unchanged; they restrict which tasks can send or receive, independent of element type.

### PR11.9 — Artifact Contract Stabilization

- **Status:** `planned`
- **Depends on:** PR11.8g
- **Blockers:** none
- **Acceptance:**
  - Compatibility policy and version-bump rules are documented for diagnostics-v0, safei-v1, and mir-v2.
  - The milestone resolves `PS-021` by defining what is additive-only versus breaking for the machine-facing artifacts.
  - Tooling introduced earlier in the roadmap can move from explicitly disposable to stable-interface consumer status only after this contract lands.

### PR11.10 — Monomorphic Library Layer

- **Status:** `planned`
- **Depends on:** PR11.9
- **Blockers:** none
- **Acceptance:**
  - A monomorphic bounded string buffer and concrete bounded vector/map/set types for built-in element types are available without generics.
  - The accepted container surface is copy-semantics-only in this milestone; move-semantic container elements stay deferred.
  - The concrete library layer serves as the pre-generic baseline that later lifts into PR11.11 generic instantiations.

### PR11.11 — Restricted Generics

- **Status:** `planned`
- **Depends on:** PR11.10
- **Blockers:** none
- **Acceptance:**
  - Generic package declarations and monomorphic instantiation are supported as the first generic capability milestone.
  - Standard generic bounded containers land, and String_Buffer becomes a generic instantiation rather than a monomorphic special case.
  - Emitter-based instantiation and the related generic-scope TBDs are resolved or explicitly version-targeted while copy-semantics-only element support remains the v1 baseline.
