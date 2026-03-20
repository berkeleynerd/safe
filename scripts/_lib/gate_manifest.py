"""Canonical gate pipeline manifest."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from .harness_common import REPO_ROOT


REPORTS_ROOT = REPO_ROOT / "execution" / "reports"
SCRIPTS_ROOT = REPO_ROOT / "scripts"


class NodeKind(str, Enum):
    BUILD = "build"
    GATE = "gate"
    VALIDATION = "validation"


class DeterminismClass(str, Enum):
    BYTE_EXACT = "byte_exact"
    CI_AUTHORITATIVE = "ci_authoritative"


@dataclass(frozen=True)
class Node:
    id: str
    kind: NodeKind
    script: Path | None = None
    report_path: Path | None = None
    depends_on: tuple[str, ...] = ()
    supports_pipeline_input: bool = False
    supports_generated_root: bool = False
    supports_authority: bool = False
    argv: tuple[str, ...] = ()
    determinism_class: DeterminismClass = DeterminismClass.BYTE_EXACT
    clean_profile: str | None = None
    child_order: tuple[str, ...] = ()


VALIDATE_EXECUTION_STATE_PREFLIGHT = "validate_execution_state_preflight"
VALIDATE_EXECUTION_STATE_FINAL = "validate_execution_state_final"
BUILD_INITIAL = "build_initial"
BUILD_STATEFUL = "build_stateful"
BUILD_POST_REPRO = "build_post_repro"


def _report(name: str) -> Path:
    return REPORTS_ROOT / name


def _script(name: str) -> Path:
    return SCRIPTS_ROOT / name


NODES: tuple[Node, ...] = (
    Node(
        id=VALIDATE_EXECUTION_STATE_PREFLIGHT,
        kind=NodeKind.VALIDATION,
        script=_script("validate_execution_state.py"),
        supports_authority=True,
        argv=("--phase", "preflight"),
    ),
    Node(
        id=BUILD_INITIAL,
        kind=NodeKind.BUILD,
        depends_on=(VALIDATE_EXECUTION_STATE_PREFLIGHT,),
        clean_profile="frontend_build",
    ),
    Node(
        id="pr102_rule5_boundary_closure",
        kind=NodeKind.GATE,
        script=_script("run_pr102_rule5_boundary_closure.py"),
        report_path=_report("pr102-rule5-boundary-closure-report.json"),
        depends_on=(BUILD_INITIAL,),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr103_sequential_proof_expansion",
        kind=NodeKind.GATE,
        script=_script("run_pr103_sequential_proof_expansion.py"),
        report_path=_report("pr103-sequential-proof-expansion-report.json"),
        depends_on=(BUILD_INITIAL,),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr104_gnatprove_evidence",
        kind=NodeKind.GATE,
        script=_script("run_pr104_gnatprove_evidence_parser_hardening.py"),
        report_path=_report("pr104-gnatprove-evidence-parser-hardening-report.json"),
        depends_on=(BUILD_INITIAL,),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr105_ada_emitter_maintenance",
        kind=NodeKind.GATE,
        script=_script("run_pr105_ada_emitter_maintenance_hardening.py"),
        report_path=_report("pr105-ada-emitter-maintenance-hardening-report.json"),
        depends_on=(BUILD_INITIAL,),
    ),
    Node(
        id="pr106_sequential_proof_corpus",
        kind=NodeKind.GATE,
        script=_script("run_pr106_sequential_proof_corpus_expansion.py"),
        report_path=_report("pr106-sequential-proof-corpus-expansion-report.json"),
        depends_on=(BUILD_INITIAL,),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr111_language_eval",
        kind=NodeKind.GATE,
        script=_script("run_pr111_language_evaluation_harness.py"),
        report_path=_report("pr111-language-evaluation-harness-report.json"),
        depends_on=(BUILD_INITIAL,),
    ),
    Node(
        id="pr112_parser_completeness",
        kind=NodeKind.GATE,
        script=_script("run_pr112_parser_completeness_phase1.py"),
        report_path=_report("pr112-parser-completeness-phase1-report.json"),
        depends_on=("pr111_language_eval",),
    ),
    Node(
        id="pr113_discriminated_types",
        kind=NodeKind.GATE,
        script=_script("run_pr113_discriminated_types_tuples_structured_returns.py"),
        report_path=_report("pr113-discriminated-types-tuples-structured-returns-report.json"),
        depends_on=("pr112_parser_completeness",),
    ),
    Node(
        id="pr113a_proof_checkpoint",
        kind=NodeKind.GATE,
        script=_script("run_pr113a_proof_checkpoint1.py"),
        report_path=_report("pr113a-proof-checkpoint1-report.json"),
        depends_on=("pr113_discriminated_types",),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr114_signature_control_flow",
        kind=NodeKind.GATE,
        script=_script("run_pr114_signature_control_flow_syntax.py"),
        report_path=_report("pr114-signature-control-flow-syntax-report.json"),
        depends_on=("pr113a_proof_checkpoint",),
    ),
    Node(
        id=BUILD_STATEFUL,
        kind=NodeKind.BUILD,
        depends_on=(BUILD_INITIAL,),
    ),
    Node(
        id="pr081_local_concurrency_frontend",
        kind=NodeKind.GATE,
        script=_script("run_pr081_local_concurrency_frontend.py"),
        report_path=_report("pr081-local-concurrency-frontend-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr082_local_concurrency_analysis",
        kind=NodeKind.GATE,
        script=_script("run_pr082_local_concurrency_analysis.py"),
        report_path=_report("pr082-local-concurrency-analysis-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr083_interface_contracts",
        kind=NodeKind.GATE,
        script=_script("run_pr083_interface_contracts.py"),
        report_path=_report("pr083-interface-contracts-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr083a_public_constants",
        kind=NodeKind.GATE,
        script=_script("run_pr083a_public_constants.py"),
        report_path=_report("pr083a-public-constants-report.json"),
        depends_on=("pr083_interface_contracts",),
    ),
    Node(
        id="pr084_transitive_concurrency",
        kind=NodeKind.GATE,
        script=_script("run_pr084_transitive_concurrency_integration.py"),
        report_path=_report("pr084-transitive-concurrency-integration-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr08_frontend_baseline",
        kind=NodeKind.GATE,
        script=_script("run_pr08_frontend_baseline.py"),
        report_path=_report("pr08-frontend-baseline-report.json"),
        depends_on=(
            BUILD_STATEFUL,
            "pr081_local_concurrency_frontend",
            "pr082_local_concurrency_analysis",
            "pr083_interface_contracts",
            "pr083a_public_constants",
            "pr084_transitive_concurrency",
        ),
        supports_pipeline_input=True,
        supports_generated_root=True,
    ),
    Node(
        id="pr09a_emitter_surface",
        kind=NodeKind.GATE,
        script=_script("run_pr09a_emitter_surface.py"),
        report_path=_report("pr09a-emitter-surface-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr09a_emitter_mvp",
        kind=NodeKind.GATE,
        script=_script("run_pr09a_emitter_mvp.py"),
        report_path=_report("pr09a-emitter-mvp-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr09b_sequential_semantics",
        kind=NodeKind.GATE,
        script=_script("run_pr09b_sequential_semantics.py"),
        report_path=_report("pr09b-sequential-semantics-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr09b_concurrency_output",
        kind=NodeKind.GATE,
        script=_script("run_pr09b_concurrency_output.py"),
        report_path=_report("pr09b-concurrency-output-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr09b_snapshot_refresh",
        kind=NodeKind.GATE,
        script=_script("run_pr09b_snapshot_refresh.py"),
        report_path=_report("pr09b-snapshot-refresh-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr09_ada_emission_baseline",
        kind=NodeKind.GATE,
        script=_script("run_pr09_ada_emission_baseline.py"),
        report_path=_report("pr09-ada-emission-baseline-report.json"),
        depends_on=(
            BUILD_STATEFUL,
            "pr09a_emitter_surface",
            "pr09a_emitter_mvp",
            "pr09b_sequential_semantics",
            "pr09b_concurrency_output",
            "pr09b_snapshot_refresh",
        ),
        supports_pipeline_input=True,
        supports_generated_root=True,
        child_order=(
            "pr09a_emitter_surface",
            "pr09a_emitter_mvp",
            "pr09b_sequential_semantics",
            "pr09b_concurrency_output",
            "pr09b_snapshot_refresh",
        ),
    ),
    Node(
        id="pr10_contract_baseline",
        kind=NodeKind.GATE,
        script=_script("run_pr10_contract_baseline.py"),
        report_path=_report("pr10-contract-baseline-report.json"),
        depends_on=(BUILD_STATEFUL,),
    ),
    Node(
        id="pr10_emitted_flow",
        kind=NodeKind.GATE,
        script=_script("run_pr10_emitted_flow.py"),
        report_path=_report("pr10-emitted-flow-report.json"),
        depends_on=(BUILD_STATEFUL,),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr10_emitted_prove",
        kind=NodeKind.GATE,
        script=_script("run_pr10_emitted_prove.py"),
        report_path=_report("pr10-emitted-prove-report.json"),
        depends_on=(BUILD_STATEFUL,),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr10_emitted_baseline",
        kind=NodeKind.GATE,
        script=_script("run_pr10_emitted_baseline.py"),
        report_path=_report("pr10-emitted-baseline-report.json"),
        depends_on=(
            BUILD_STATEFUL,
            "pr10_contract_baseline",
            "pr10_emitted_flow",
            "pr10_emitted_prove",
        ),
        supports_pipeline_input=True,
        supports_generated_root=True,
        child_order=(
            "pr10_contract_baseline",
            "pr10_emitted_flow",
            "pr10_emitted_prove",
        ),
    ),
    Node(
        id="emitted_hardening_regressions",
        kind=NodeKind.GATE,
        script=_script("run_emitted_hardening_regressions.py"),
        report_path=_report("emitted-hardening-regressions-report.json"),
        depends_on=(BUILD_STATEFUL,),
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
    ),
    Node(
        id="pr101_comprehensive_audit",
        kind=NodeKind.GATE,
        script=_script("run_pr101_comprehensive_audit.py"),
        report_path=_report("pr101-comprehensive-audit-report.json"),
        depends_on=(
            BUILD_STATEFUL,
            VALIDATE_EXECUTION_STATE_PREFLIGHT,
            "pr08_frontend_baseline",
            "pr09_ada_emission_baseline",
            "pr10_emitted_baseline",
            "emitted_hardening_regressions",
        ),
        supports_pipeline_input=True,
        supports_generated_root=True,
        determinism_class=DeterminismClass.CI_AUTHORITATIVE,
        child_order=(
            "pr08_frontend_baseline",
            "pr09_ada_emission_baseline",
            "pr10_emitted_baseline",
            "emitted_hardening_regressions",
        ),
    ),
    Node(
        id="pr0694_output_contract_stability",
        kind=NodeKind.GATE,
        script=_script("run_pr0694_output_contract_stability.py"),
        report_path=_report("pr0694-output-contract-stability-report.json"),
        depends_on=("pr101_comprehensive_audit",),
    ),
    Node(
        id="pr0697_gate_quality",
        kind=NodeKind.GATE,
        script=_script("run_pr0697_gate_quality.py"),
        report_path=_report("pr0697-gate-quality-report.json"),
        depends_on=("pr0694_output_contract_stability",),
    ),
    Node(
        id=BUILD_POST_REPRO,
        kind=NodeKind.BUILD,
        depends_on=("pr0697_gate_quality",),
        clean_profile="post_repro_build",
    ),
    Node(
        id="pr0699_build_reproducibility",
        kind=NodeKind.GATE,
        script=_script("run_pr0699_build_reproducibility.py"),
        report_path=_report("pr0699-build-reproducibility-report.json"),
        supports_authority=True,
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr0693_runtime_boundary",
        kind=NodeKind.GATE,
        script=_script("run_pr0693_runtime_boundary.py"),
        report_path=_report("pr0693-runtime-boundary-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr068_ada_ast_emit_no_python",
        kind=NodeKind.GATE,
        script=_script("run_pr068_ada_ast_emit_no_python.py"),
        report_path=_report("pr068-ada-ast-emit-no-python-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr06910_portability_environment",
        kind=NodeKind.GATE,
        script=_script("run_pr06910_portability_environment.py"),
        report_path=_report("pr06910-portability-environment-report.json"),
        depends_on=(
            VALIDATE_EXECUTION_STATE_PREFLIGHT,
            "pr0693_runtime_boundary",
            "pr068_ada_ast_emit_no_python",
        ),
        supports_pipeline_input=True,
        supports_generated_root=True,
    ),
    Node(
        id="frontend_smoke",
        kind=NodeKind.GATE,
        script=_script("run_frontend_smoke.py"),
        report_path=_report("pr00-pr04-frontend-smoke.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr0698_legacy_package_cleanup",
        kind=NodeKind.GATE,
        script=_script("run_pr0698_legacy_package_cleanup.py"),
        report_path=_report("pr0698-legacy-package-cleanup-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr06912_performance_scale_sanity",
        kind=NodeKind.GATE,
        script=_script("run_pr06912_performance_scale_sanity.py"),
        report_path=_report("pr06912-performance-scale-sanity-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr06911_glue_script_safety",
        kind=NodeKind.GATE,
        script=_script("run_pr06911_glue_script_safety.py"),
        report_path=_report("pr06911-glue-script-safety-report.json"),
        depends_on=(
            VALIDATE_EXECUTION_STATE_PREFLIGHT,
            "pr0693_runtime_boundary",
            "pr0697_gate_quality",
            "pr06910_portability_environment",
            "frontend_smoke",
            "pr0699_build_reproducibility",
        ),
        supports_pipeline_input=True,
        supports_generated_root=True,
    ),
    Node(
        id="pr06913_documentation_architecture_clarity",
        kind=NodeKind.GATE,
        script=_script("run_pr06913_documentation_architecture_clarity.py"),
        report_path=_report("pr06913-documentation-architecture-clarity-report.json"),
        depends_on=(
            VALIDATE_EXECUTION_STATE_PREFLIGHT,
            "pr0693_runtime_boundary",
            "pr0697_gate_quality",
            "pr0698_legacy_package_cleanup",
            "pr06910_portability_environment",
            "pr06912_performance_scale_sanity",
            "pr06911_glue_script_safety",
        ),
        supports_pipeline_input=True,
        supports_generated_root=True,
    ),
    Node(
        id="pr0695_diagnostic_stability",
        kind=NodeKind.GATE,
        script=_script("run_pr0695_diagnostic_stability.py"),
        report_path=_report("pr0695-diagnostic-stability-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr0696_unsupported_feature_boundary",
        kind=NodeKind.GATE,
        script=_script("run_pr0696_unsupported_feature_boundary.py"),
        report_path=_report("pr0696-unsupported-feature-boundary-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr065_ada_mir_validator",
        kind=NodeKind.GATE,
        script=_script("run_pr065_ada_mir_validator.py"),
        report_path=_report("pr065-ada-mir-validator-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr066_ada_mir_analyzer",
        kind=NodeKind.GATE,
        script=_script("run_pr066_ada_mir_analyzer.py"),
        report_path=_report("pr066-ada-mir-analyzer-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr067_ada_check_cutover",
        kind=NodeKind.GATE,
        script=_script("run_pr067_ada_check_cutover.py"),
        report_path=_report("pr067-ada-check-cutover-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr05_d27_harness",
        kind=NodeKind.GATE,
        script=_script("run_pr05_d27_harness.py"),
        report_path=_report("pr05-d27-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr06_ownership_harness",
        kind=NodeKind.GATE,
        script=_script("run_pr06_ownership_harness.py"),
        report_path=_report("pr06-ownership-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr07_rule5_result_safety",
        kind=NodeKind.GATE,
        script=_script("run_pr07_rule5_result_safety.py"),
        report_path=_report("pr07-rule5-result-safety-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr0691_semantic_correctness",
        kind=NodeKind.GATE,
        script=_script("run_pr0691_semantic_correctness.py"),
        report_path=_report("pr0691-semantic-correctness-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id="pr0692_lowering_cfg_integrity",
        kind=NodeKind.GATE,
        script=_script("run_pr0692_lowering_cfg_integrity.py"),
        report_path=_report("pr0692-lowering-cfg-integrity-report.json"),
        depends_on=(BUILD_POST_REPRO,),
    ),
    Node(
        id=VALIDATE_EXECUTION_STATE_FINAL,
        kind=NodeKind.GATE,
        script=_script("validate_execution_state.py"),
        report_path=_report("execution-state-validation-report.json"),
        depends_on=("pr06913_documentation_architecture_clarity",),
        supports_authority=True,
        supports_generated_root=True,
        argv=("--phase", "final"),
    ),
)


NODES_BY_ID = {node.id: node for node in NODES}


BRANCH_ROOTS: tuple[tuple[str, tuple[str, ...]], ...] = (
    (
        "codex/pr081",
        (
            "pr081_local_concurrency_frontend",
            "pr09_ada_emission_baseline",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr082",
        (
            "pr082_local_concurrency_analysis",
            "pr09_ada_emission_baseline",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr083",
        (
            "pr083_interface_contracts",
            "pr09_ada_emission_baseline",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr083a",
        (
            "pr083_interface_contracts",
            "pr083a_public_constants",
            "pr09_ada_emission_baseline",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr084",
        (
            "pr084_transitive_concurrency",
            "pr08_frontend_baseline",
            "pr09_ada_emission_baseline",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr09",
        (
            "pr09_ada_emission_baseline",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr10",
        (
            "pr10_emitted_baseline",
            "emitted_hardening_regressions",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr101",
        (
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr102",
        (
            "pr102_rule5_boundary_closure",
            "pr10_contract_baseline",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr103",
        (
            "pr103_sequential_proof_expansion",
            "pr10_emitted_baseline",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr104",
        (
            "pr104_gnatprove_evidence",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr105",
        (
            "pr105_ada_emitter_maintenance",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr106",
        (
            "pr106_sequential_proof_corpus",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr111",
        (
            "pr111_language_eval",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr112",
        (
            "pr112_parser_completeness",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr113",
        (
            "pr113_discriminated_types",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr113a",
        (
            "pr113a_proof_checkpoint",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
    (
        "codex/pr114",
        (
            "pr111_language_eval",
            "pr112_parser_completeness",
            "pr113_discriminated_types",
            "pr113a_proof_checkpoint",
            "pr114_signature_control_flow",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        ),
    ),
)


def branch_roots(branch: str) -> tuple[str, ...]:
    for prefix, roots in BRANCH_ROOTS:
        if branch == prefix or branch.startswith(prefix + "-"):
            return roots
    if branch.startswith("codex/pr11"):
        return (
            "frontend_smoke",
            "pr101_comprehensive_audit",
            "pr0694_output_contract_stability",
            "pr0697_gate_quality",
            "pr0699_build_reproducibility",
            "pr06910_portability_environment",
            "pr06911_glue_script_safety",
            "pr06913_documentation_architecture_clarity",
        )
    if branch.startswith("codex/pr08") or branch.startswith("codex/pr09") or branch.startswith("codex/pr10"):
        raise RuntimeError(
            f"{branch}: no local pre-push plan is defined yet; update scripts/_lib/gate_manifest.py"
        )
    return ()


def resolve_branch(branch: str) -> list[Node]:
    roots = branch_roots(branch)
    if not roots:
        return []

    included: set[str] = set()

    def visit(node_id: str) -> None:
        if node_id in included:
            return
        node = NODES_BY_ID[node_id]
        for dependency in node.depends_on:
            visit(dependency)
        included.add(node_id)

    for root in roots:
        visit(root)

    return [node for node in NODES if node.id in included]


def validate_manifest() -> None:
    node_ids = [node.id for node in NODES]
    if len(node_ids) != len(set(node_ids)):
        raise ValueError("manifest node ids must be unique")

    seen: set[str] = set()
    for node in NODES:
        for dependency in node.depends_on:
            if dependency not in NODES_BY_ID:
                raise ValueError(f"{node.id}: unknown dependency {dependency}")
        if any(dependency not in seen for dependency in node.depends_on):
            raise ValueError(f"{node.id}: dependencies must appear earlier in NODES")
        seen.add(node.id)

    for _prefix, roots in BRANCH_ROOTS:
        for node_id in roots:
            if node_id not in NODES_BY_ID:
                raise ValueError(f"branch roots reference unknown node {node_id}")

    visiting: set[str] = set()
    visited: set[str] = set()

    def walk(node_id: str) -> None:
        if node_id in visited:
            return
        if node_id in visiting:
            raise ValueError(f"dependency cycle detected at {node_id}")
        visiting.add(node_id)
        for dependency in NODES_BY_ID[node_id].depends_on:
            walk(dependency)
        visiting.remove(node_id)
        visited.add(node_id)

    for node in NODES:
        walk(node.id)


validate_manifest()
