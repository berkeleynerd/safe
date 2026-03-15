# SafeC Frontend

This workspace hosts the current Safe compiler frontend baseline established by PR08 on top of the PR06.9.x hardening series, plus the PR09 Ada/SPARK emission layer, the PR10 selected emitted-output GNATprove layer, and the PR10.1 refinement audit layer on top of that baseline.

## Current Boundary

- `safec lex <file.safe>` lexes a Safe source file and writes versioned token JSON to stdout.
- `safec ast <file.safe> [--interface-search-dir <dir>]...` lexes, resolves, and writes AST JSON for the current supported subset.
- `safec validate-mir <file.mir.json>` validates emitted `mir-v1` / `mir-v2` structure in Ada and exits nonzero on structural contract failures.
- `safec analyze-mir <file.mir.json>` validates analyzable `mir-v2` input and exits nonzero if MIR-level diagnostics are emitted.
- `safec analyze-mir --diag-json <file.mir.json>` writes `diagnostics-v0` JSON for a `mir-v2` input.
- `safec check <file.safe> [--interface-search-dir <dir>]...` runs the Ada-native check pipeline for the currently supported subset and exits nonzero if diagnostics are emitted.
- `safec check --diag-json <file.safe> [--interface-search-dir <dir>]...` writes `diagnostics-v0` JSON for the Ada-native check pipeline.
- `safec emit <file.safe> --out-dir <dir> --interface-dir <dir> [--ada-out-dir <dir>] [--interface-search-dir <dir>]...` writes the current frontend artifacts for downstream inspection and regression checks, and optionally emits Ada/SPARK artifacts for the current PR09 subset.

The current frontend supports the exact current Rule 5 fixture corpus, sequential ownership, the current boolean result-record discriminant pattern, the local-only PR08.1/PR08.2 concurrency slice for single-package task declarations, channel declarations, send, receive, try_send, try_receive, select, and relative delay, the PR08.3 interface-contract slice for imported package-qualified resolution through explicit dependency interfaces, the PR08.3a additive constant slice for ordinary object constants plus imported integer/boolean constant values in the currently supported static-expression sites, and the PR08.4 transitive integration slice for imported-summary consumption, cross-package ownership/channel-ceiling analysis, and imported-call ownership semantics.

That current boundary includes:

- schema-true AST emission for the implemented subset
- `typed-v2`, self-sufficient `mir-v2`, and `safei-v1` emission for that subset
- deterministic Ada/SPARK emission through `--ada-out-dir` for the current PR09 subset
- Ada-native MIR validation and MIR analysis for that subset
- Ada-native `check` over the exact current Rule 5 fixture corpus, the sequential ownership corpus, the current boolean result-record discriminant pattern, and the accepted local-only concurrency corpus

All current user-facing `safec` commands are Ada-native for that supported surface. Python remains glue/orchestration only around the compiler.

PR06.9.12 is a cliff-detection gate, not a benchmark commitment, for that current frontend subset.

See [`../docs/frontend_architecture_baseline.md`](../docs/frontend_architecture_baseline.md) for the canonical frontend boundary, [`../docs/frontend_scale_limits.md`](../docs/frontend_scale_limits.md) for the current cliff-detection scale policy, and [`../docs/emitted_output_verification_matrix.md`](../docs/emitted_output_verification_matrix.md) for the emitted-output assurance boundary.
For a host-local end-to-end walkthrough from Safe source to a runnable native
binary, see [`../docs/safec_end_to_end_cli_tutorial.md`](../docs/safec_end_to_end_cli_tutorial.md).
On macOS, local emitted-Ada executable builds should use a generated project
file with the same linker `syslibroot` pattern as `safec.gpr`.

## Current Doctrine

- Ubuntu/Linux CI and local macOS are the supported environments for the current frontend.
- Windows is explicitly unsupported for PR06.9.x.
- On macOS, repo glue assumes an SDK is discoverable through `xcrun --show-sdk-path` or `SDKROOT`.
- Portability-sensitive repo glue uses PATH-based command discovery instead of hard-coded tool paths.
- Portability-sensitive gates use deterministic TemporaryDirectory prefixes for stable temp roots and evidence.
- Portability-sensitive glue scripts remain shell-free and do not rely on `shell=True` or `os.system`.
- Active Python glue is orchestration/validation only and stays argv-based.
- Safe source may only be read by glue scripts for fixture metadata extraction or inline negative/control cases, never as a second semantic source of truth.
- The recovery note in `../docs/macos_alire_toolchain_repair.md` is a developer recovery procedure, not a compiler runtime dependency.
- No-Python runtime enforcement covers `python`, `python3`, `python3.11`, `python3.<minor>`, and path-qualified Python invocations in compiler runtime sources.

The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.

The only live frontend path is now the Ada-native `Check_*` plus `Mir_*` pipeline, with `Lexer`, `Source`, `Types`, `Diagnostics`, and `Json` supporting that path.

PR08 extends the live `Check_*` + `Mir_*` pipeline, and the current frontend baseline is now PR08.
PR09 layers deterministic Ada/SPARK emission on top of that frontend baseline through the optional `--ada-out-dir` path.
PR10 layers selected emitted-output GNATprove verification on top of that emitted surface; [`../docs/emitted_output_verification_matrix.md`](../docs/emitted_output_verification_matrix.md) is the canonical statement of what is compile-only versus `flow` / `prove` verified, [`../docs/pr10_refinement_audit.md`](../docs/pr10_refinement_audit.md) is the canonical audit/disposition record, and [`../docs/post_pr10_scope.md`](../docs/post_pr10_scope.md) records everything still retained after the selected proof corpus. Supplemental emitted hardening regressions can extend coverage outside that frozen PR10 corpus without changing the milestone claim.

Unsupported-feature classification rule:
- `unsupported_source_construct` means the Ada-native frontend recognized a construct that is outside the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern.
- `source_frontend_error` means a true frontend failure inside the current subset boundary, such as malformed syntax, bad package end names, missing identifiers, or oversized integer literals.
- The PR06.9.6 gate proves those classifications and also proves unsupported `emit` calls do not write partial artifacts.

## Dependency Policy

PR06.5 intentionally adopts `GNATCOLL.JSON` for Ada-side JSON parsing in `safec validate-mir`.
This dependency is accepted for the current compiler workspace because it removes Python from one
real contract gate without reopening parser/analyzer work. It is not a license decision for the
entire repository, and any broader reuse or future distribution-policy change should revisit this
dependency explicitly rather than allowing it to spread by default.

## Output Formats

`safec lex` currently writes one JSON artifact to stdout:

- token dump
  Format tag: `tokens-v0`.
  Contents: `tokens[]`, where each token includes `kind`, `lexeme`, and `span`.
  Notes: the synthetic EOF token is intentionally omitted so the dump remains source-derived.
  Compatibility: incompatible changes require a new format tag.

`safec emit` always writes four JSON artifacts:

- `<stem>.ast.json`
  Format: parser AST shaped to the contract in `compiler/ast_schema.json`.
  Validation path: `python3 scripts/validate_ast_output.py` as repo glue around the Ada-native `safec ast` / `safec emit` path.

- `<stem>.typed.json`
  Format tag: `typed-v2`.
  Contents: package identity, resolved type inventory, executable summaries, public declarations, the AST snapshot used to derive lowering and diagnostics, ownership-oriented access-role metadata for the sequential ownership model, and additive local `channels[]` / `tasks[]` metadata for the PR08.1 concurrency frontend slice. Constantness for ordinary object constants is reflected through the embedded AST payload; PR08.3a does not add a new top-level typed-v2 constant table.

- `<stem>.mir.json`
  Format tag: `mir-v2`.
  Contents: `source_path`, resolved `types[]`, package-level graph data, deterministic locals tables, `scopes[]`, blocks with `active_scope_id`, typed ops, explicit terminators, graph `return_type`, and ownership-effect metadata for the implemented sequential subset. PR08.1 extends this additively with top-level `channels[]`, task graphs with priority metadata, channel op kinds, and `select` terminators for the local concurrency frontend slice. PR08.4 extends it additively with optional `externals[]` entries for imported subprogram signatures plus imported effect/channel summaries, and with additive `required_ceiling` metadata on channels when available.
  Validation path: `safec validate-mir <stem>.mir.json`.
  Status: debug and regression artifact for the current sequential platform. Incompatible structural changes require a format-tag bump.

- `<stem>.safei.json`
  Format tag: `safei-v1`.
  Contents:
  - `dependencies[]`
  - `package_name`
  - `executables[]`
  - `public_declarations[]`
  - `types[]`
  - `subtypes[]`
  - `channels[]`
  - `objects[]`
  - `subprograms[]`
  - `effect_summaries[]`
  - `channel_access_summaries[]`
  Public subprogram entries carry structured parameter and return-type descriptors, and the summary arrays are populated from the local Bronze pass for public subprograms. PR08.3a extends `objects[]` additively with `is_constant` plus optional `static_value_kind` / `static_value` for the supported integer and boolean constant subset. PR08.4 extends public `channels[]` additively with optional `required_ceiling` so provider channel ceilings can compose with client task priorities.

`safei-v1` is the versioned dependency-interface contract for cross-unit resolution. It carries structured public declarations, local Bronze-derived effect/channel summaries, and additive object constant metadata while remaining the base for later named-number extensions. If the schema changes incompatibly, the format tag must change as well.

When `--ada-out-dir <dir>` is provided, `safec emit` additionally writes deterministic Ada/SPARK artifacts for the current PR09 subset:

- `<unit>.ads`
  Contents: package spec with `pragma SPARK_Mode (On);`, source-ordered public declarations, and currently supported public aspects.

- `<unit>.adb`
  Contents: package body for the current supported emitter subset, including arithmetic lowering, ownership/deallocation lowering, and concurrency lowering on the supported PR08 subset.

- `safe_runtime.ads` (optional)
  Emitted when wide-integer lowering is required.
  Contract: must remain byte-identical to `../companion/templates/safe_runtime.ads`.

- `gnat.adc` (optional)
  Emitted when concurrency constructs are present.
  Contents:
  - `pragma Partition_Elaboration_Policy(Sequential);`
  - `pragma Profile(Jorvik);`

Managed artifact set for `safec emit`:

- Always managed:
  - `<stem>.ast.json`
  - `<stem>.typed.json`
  - `<stem>.mir.json`
  - `<stem>.safei.json`
- Managed only when `--ada-out-dir <dir>` is provided:
  - `<unit>.ads`
  - `<unit>.adb`
  - optional `safe_runtime.ads`
  - optional `gnat.adc`

`safec emit` outcome contract:

- Exit `0` (`Exit_Success`)
  - Full success.
  - All managed artifacts for the invocation are written deterministically.
  - Optional Ada support files (`safe_runtime.ads`, `gnat.adc`) are written when needed and otherwise preserved if already present in the target Ada output directory.

- Exit `1` (`Exit_Diagnostics`)
  - Source/frontend/analyzer diagnostics, including `unsupported_source_construct`.
  - Diagnostics are reported before any artifact writes, so the managed artifact set is left untouched.

- Exit `3` (`Exit_Internal`)
  - Internal compiler failures, including serialization or filesystem I/O failures.
  - The driver computes all managed artifact text before beginning filesystem mutation.
  - If an Ada artifact write fails after `--ada-out-dir <dir>` was requested, the driver removes the managed unit files for that invocation (`<unit>.ads`, `<unit>.adb`) before returning.
  - JSON/interface writes remain direct writes rather than a transactional multi-directory commit.

## Verification

The current smoke path is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_frontend_smoke.py
python3 scripts/validate_execution_state.py
```

The smoke run checks lexer regressions for current and legacy two-character operators, AST validation, representative sequential `check` runs, deterministic repeated `emit` output, and records results in `execution/reports/pr00-pr04-frontend-smoke.json`.

The PR05 D27 gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr05_d27_harness.py
```

That harness diffs the four canonical diagnostics goldens byte-for-byte, runs the full current Rule 1-4 corpus gate, verifies deterministic repeated `emit` output on loop and short-circuit samples, and records results in `execution/reports/pr05-d27-report.json`.
It also validates representative MIR artifacts and drives corpus reason matching through `safec check --diag-json` rather than parsing human stderr.

The PR06 ownership gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr06_ownership_harness.py
```

That harness diffs the committed ownership diagnostics goldens byte-for-byte, runs the sequential ownership corpus gate, validates representative `typed-v2`/`mir-v2` outputs, checks deterministic repeated `emit` output on ownership samples, and records results in `execution/reports/pr06-ownership-report.json`.

The PR06.5 Ada MIR validation gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr065_ada_mir_validator.py
```

That gate validates committed `mir-v1` / `mir-v2` fixtures plus representative emitted MIR from the PR05 and PR06 corpora, and records results in `execution/reports/pr065-ada-mir-validator-report.json`.

The PR06.6 MIR analyzer gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr066_ada_mir_analyzer.py
```

That gate runs committed `analyze-mir` fixtures for no-diagnostic, PR05, and PR06 cases, checks invalid-input rejection, confirms emitted PR05 / PR06 MIR stays clean under `safec analyze-mir --diag-json`, reruns the existing PR05 / PR06 harnesses unchanged, and records results in `execution/reports/pr066-ada-mir-analyzer-report.json`.

The PR06.7 Ada check cutover gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr067_ada_check_cutover.py
```

That gate masks `python3` on `PATH` specifically for accidental `safec check` backend spawns, proves representative direct PR05 / PR06 checks still pass, reruns the existing PR05 / PR06 harnesses with that masked check path, verifies deterministic `unsupported_source_construct` rejection for out-of-subset sources, and records results in `execution/reports/pr067-ada-check-cutover-report.json`.

PR06.7 no-Python guarantee: Python may still run the gate script and the unchanged harnesses around `safec check`, but `safec check` itself must stay Ada-native and must not spawn the Python backend.

The PR06.8 Ada `ast` / `emit` cutover gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr068_ada_ast_emit_no_python.py
```

That gate masks `python` and `python3` on `PATH` for direct `safec ast` and `safec emit` invocations, validates the emitted AST through the existing validator script, checks deterministic repeated `emit` output on representative samples, verifies emitted MIR stays valid and analyzable, confirms `emit` writes no artifacts when diagnostics exist, adds direct package-global lowering regressions plus CFG termination checks, and records results in `execution/reports/pr068-ada-ast-emit-no-python-report.json`.

PR06.8 no-Python guarantee: Python may still run the gate script and validation helpers around the compiler, but no `safec` command may spawn Python at runtime. CI enforces this through `PATH` masking for direct compiler invocations rather than by removing Python from the runner entirely.

The PR06.9.1 semantic correctness hardening gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr0691_semantic_correctness.py
```

That gate revalidates range, ownership, return, and call semantics across targeted PR05 / PR06 seam cases, proves representative positive sources stay clean under both `safec check --diag-json` and emitted `safec analyze-mir --diag-json`, preserves primary reasons for representative negative sources, cross-checks committed analyzer fixtures against paired source failures, adds inline package-global semantic regressions, and records results in `execution/reports/pr0691-semantic-correctness-report.json`.

The PR06.9.2 lowering/CFG integrity gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr0692_lowering_cfg_integrity.py
```

That gate proves package-global visibility, declaration-init semantics, scope metadata, and CFG termination invariants on emitted MIR beyond schema validity, and records results in `execution/reports/pr0692-lowering-cfg-integrity-report.json`.

The PR06.9.3 runtime-boundary hardening gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr0693_runtime_boundary.py
```

That gate masks `python` and `python3` on `PATH` for every direct user-facing `safec` command, proves the CLI still behaves correctly for representative success and failure cases, confirms the blocked-spawn log stays empty, and records results in `execution/reports/pr0693-runtime-boundary-report.json`.

The PR08.1 local concurrency frontend gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr081_local_concurrency_frontend.py
```

That gate validates the local-only concurrency emit corpus on `safec ast`, `emit`, `validate-mir`, and `analyze-mir`, exercises the new source-legality negatives, checks deterministic repeated `emit` output on representative task/channel/select samples, validates the concurrency-bearing MIR fixtures, and records results in `execution/reports/pr081-local-concurrency-frontend-report.json`.

The PR08.2 local concurrency analysis gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr082_local_concurrency_analysis.py
```

That gate promotes the accepted local concurrency corpus to a clean `safec check --diag-json` surface, checks direct `check` versus emitted `analyze-mir` first-diagnostic parity on representative concurrency negatives, re-derives deterministic Bronze evidence from emitted MIR, guards representative sequential parity cases against analyzer regressions, and records results in `execution/reports/pr082-local-concurrency-analysis-report.json`.

The PR08.3 interface contracts gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr083_interface_contracts.py
```

That gate emits provider interfaces, compiles clients through explicit `--interface-search-dir` inputs, validates `safei-v1`, exercises deterministic lookup failures and search-order behavior, proves `--interface-dir` is output-only, and records results in `execution/reports/pr083-interface-contracts-report.json`.

The PR08.3a public constants gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr083a_public_constants.py
```

That gate promotes ordinary object constants to the live Ada-native path, validates additive `safei-v1` constant payloads, proves imported integer/boolean constants work in the current static-expression sites, checks local `write_to_constant` parity between direct `check` and emitted `analyze-mir`, and records results in `execution/reports/pr083a-public-constants-report.json`.
The supported static subset in PR08.3a is intentionally narrow: direct integer/boolean constant references (plus unary minus on integers) in the currently supported static sites. Imported constants without a supported exported static value remain readable objects but fail deterministically when a required static site tries to use them.

The PR08.4 transitive concurrency integration gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr084_transitive_concurrency_integration.py
```

That gate validates imported-summary consumption on provider/client interface pairs, checks cross-package ownership and imported-call parity between direct `check` and emitted `analyze-mir`, proves composed imported channel ceilings from provider `required_ceiling` plus client task priorities, and records results in `execution/reports/pr084-transitive-concurrency-integration-report.json`.

The PR08 frontend baseline gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr08_frontend_baseline.py
```

That gate reruns the PR08 milestone gates, verifies tracker/dashboard/docs all describe PR08 as the supported frontend baseline, and records results in `execution/reports/pr08-frontend-baseline-report.json`.

The PR09a emitter surface gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr09a_emitter_surface.py
```

That gate validates deterministic package skeleton emission on the slice-1 subset, compiles the emitted Ada, proves unsupported emitter-only constructs fail without partial output, and records results in `execution/reports/pr09a-emitter-surface-report.json`.

The PR09a arithmetic MVP gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr09a_emitter_mvp.py
```

That gate validates deterministic Rule 1 arithmetic emission, compile-only Ada/SPARK output on the PR09a subset, `Safe_Runtime.Wide_Integer` lowering, narrowing assertions, and `safe_runtime.ads` byte identity against the companion template, then records results in `execution/reports/pr09a-emitter-mvp-report.json`.

The PR09b sequential semantics gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr09b_sequential_semantics.py
```

That gate validates deterministic emitted ownership/deallocation shapes plus public `Global` / `Depends` / `Initializes` aspects on the supported sequential subset, compiles the emitted Ada, and records results in `execution/reports/pr09b-sequential-semantics-report.json`.

The PR09b concurrency output gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr09b_concurrency_output.py
```

That gate validates deterministic task/channel/select lowering on the supported PR08 concurrency subset, compiles emitted Ada with `gnat.adc` applied explicitly, checks the fixed `gnat.adc` content, and records results in `execution/reports/pr09b-concurrency-output-report.json`.

The PR09b snapshot refresh gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr09b_snapshot_refresh.py
```

That gate compares emitted Ada artifacts against the committed golden directories under `tests/golden/`, proves the retired monolithic `.ada` snapshots are gone, and records results in `execution/reports/pr09b-snapshot-refresh-report.json`.

The PR09 Ada-emission baseline gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr09_ada_emission_baseline.py
```

That gate reruns the PR09 slice gates, verifies tracker/dashboard/docs describe PR09 as complete while later `PR10` milestones may exist, and records results in `execution/reports/pr09-ada-emission-baseline-report.json`.

The PR10 contract baseline gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr10_contract_baseline.py
```

That gate verifies the PR10 acceptance contract, selected emitted proof corpus, emitted-output verification matrix, README cross-links, and post-PR10 residual ledger, then records results in `execution/reports/pr10-contract-baseline-report.json`.

The PR10 emitted flow gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr10_emitted_flow.py
```

That gate emits the selected PR10 corpus, compiles each emitted package, runs `gnatprove --mode=flow --warnings=error`, and records results in `execution/reports/pr10-emitted-flow-report.json`.

The PR10 emitted prove gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr10_emitted_prove.py
```

That gate emits the selected PR10 corpus, compiles each emitted package, runs `gnatprove --mode=prove` under the fixed prover profile, requires zero warnings plus zero justified and zero unproved checks, and records results in `execution/reports/pr10-emitted-prove-report.json`.

The PR10 emitted baseline gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr10_emitted_baseline.py
```

That gate reruns the PR10 contract, flow, and prove gates, verifies tracker/dashboard/docs still describe PR10 as complete even when later tracked milestones may exist, and records results in `execution/reports/pr10-emitted-baseline-report.json`.

The supplemental emitted hardening gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_emitted_hardening_regressions.py
```

That gate keeps the frozen PR10 selected corpus intact while hardening emitted regressions beyond it, including ownership early-return ordering plus supplemental concurrency proof samples, and records results in `execution/reports/emitted-hardening-regressions-report.json`.

The PR10.1 comprehensive audit gate is:

```bash
cd compiler_impl && $HOME/bin/alr build
python3 scripts/run_pr101_comprehensive_audit.py
```

That gate reruns the authoritative PR08, PR09, PR10, supplemental hardening, companion, template, and execution-state baselines; reconciles tracker/dashboard/docs against the committed audit findings; and records results in `execution/reports/pr101-comprehensive-audit-report.json`.

To enforce the local pre-push gate chain in this clone, enable the tracked hook once:

```bash
git config core.hooksPath .githooks
```

That hook runs [`scripts/run_local_pre_push.py`](../scripts/run_local_pre_push.py), which executes the mapped milestone gate and downstream evidence-refresh chain serially before allowing `git push`.
