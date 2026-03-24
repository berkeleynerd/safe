from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from _lib.gate_manifest import NODES, resolve_branch, validate_manifest


class GateManifestTests(unittest.TestCase):
    def test_manifest_is_acyclic(self) -> None:
        validate_manifest()

    def test_manifest_nodes_are_unique(self) -> None:
        node_ids = [node.id for node in NODES]
        self.assertEqual(len(node_ids), len(set(node_ids)))

    def test_manifest_topologically_valid(self) -> None:
        positions = {node.id: index for index, node in enumerate(NODES)}
        for node in NODES:
            for dependency in node.depends_on:
                self.assertLess(positions[dependency], positions[node.id])

    def test_all_report_paths_exist(self) -> None:
        repo_root = SCRIPTS_DIR.parent
        generated_root_env = os.environ.get("SAFE_GENERATED_ROOT")
        generated_root = Path(generated_root_env) if generated_root_env else None
        for node in NODES:
            if node.report_path is not None:
                report_exists = node.report_path.exists()
                if not report_exists and generated_root is not None:
                    generated_path = generated_root / node.report_path.relative_to(repo_root)
                    report_exists = generated_path.exists()
                self.assertTrue(report_exists, node.report_path)

    def test_manifest_covers_done_tracker_evidence_reports(self) -> None:
        tracker = json.loads((SCRIPTS_DIR.parent / "execution" / "tracker.json").read_text(encoding="utf-8"))
        tracker_reports = {
            SCRIPTS_DIR.parent / evidence
            for task in tracker["tasks"]
            if task.get("status") == "done"
            for evidence in task.get("evidence", [])
            if evidence.endswith(".json")
        }
        manifest_reports = {node.report_path for node in NODES if node.report_path is not None}
        self.assertEqual(set(), tracker_reports - manifest_reports)

    def test_branch_resolution_pr10(self) -> None:
        self.assertEqual(
            [node.id for node in resolve_branch("codex/pr10-emitted-baseline")],
            [
                "validate_execution_state_preflight",
                "build_initial",
                "pr081_local_concurrency_frontend",
                "pr082_local_concurrency_analysis",
                "pr083_interface_contracts",
                "pr083a_public_constants",
                "pr084_transitive_concurrency",
                "pr08_frontend_baseline",
                "pr09a_emitter_surface",
                "pr09a_emitter_mvp",
                "pr09b_sequential_semantics",
                "pr09b_concurrency_output",
                "pr09b_snapshot_refresh",
                "pr09_ada_emission_baseline",
                "pr10_contract_baseline",
                "pr10_emitted_flow",
                "pr10_emitted_prove",
                "pr10_emitted_baseline",
                "emitted_hardening_regressions",
                "pr101a_companion_proof_verification",
                "pr101b_template_proof_verification",
                "pr101_comprehensive_audit",
                "pr0694_output_contract_stability",
                "pr0697_gate_quality",
                "frontend_smoke",
                "pr0699_build_reproducibility",
                "pr0693_runtime_boundary",
                "pr068_ada_ast_emit_no_python",
                "pr06910_portability_environment",
                "pr0698_legacy_package_cleanup",
                "pr06912_performance_scale_sanity",
                "pr06911_glue_script_safety",
                "pr06913_documentation_architecture_clarity",
            ],
        )

    def test_branch_resolution_pr111(self) -> None:
        self.assertEqual(
            [node.id for node in resolve_branch("codex/pr111-language-eval-harness")],
            [
                "validate_execution_state_preflight",
                "build_initial",
                "pr111_language_eval",
                "pr081_local_concurrency_frontend",
                "pr082_local_concurrency_analysis",
                "pr083_interface_contracts",
                "pr083a_public_constants",
                "pr084_transitive_concurrency",
                "pr08_frontend_baseline",
                "pr09a_emitter_surface",
                "pr09a_emitter_mvp",
                "pr09b_sequential_semantics",
                "pr09b_concurrency_output",
                "pr09b_snapshot_refresh",
                "pr09_ada_emission_baseline",
                "pr10_contract_baseline",
                "pr10_emitted_flow",
                "pr10_emitted_prove",
                "pr10_emitted_baseline",
                "emitted_hardening_regressions",
                "pr101a_companion_proof_verification",
                "pr101b_template_proof_verification",
                "pr101_comprehensive_audit",
                "pr0694_output_contract_stability",
                "pr0697_gate_quality",
                "frontend_smoke",
                "pr0699_build_reproducibility",
                "pr0693_runtime_boundary",
                "pr068_ada_ast_emit_no_python",
                "pr06910_portability_environment",
                "pr0698_legacy_package_cleanup",
                "pr06912_performance_scale_sanity",
                "pr06911_glue_script_safety",
                "pr06913_documentation_architecture_clarity",
            ],
        )

    def test_branch_resolution_pr114(self) -> None:
        self.assertEqual(
            [node.id for node in resolve_branch("codex/pr114-signature-control-flow-syntax")],
            [
                "validate_execution_state_preflight",
                "build_initial",
                "pr111_language_eval",
                "pr112_parser_completeness",
                "pr113_discriminated_types",
                "pr113a_proof_checkpoint",
                "pr114_signature_control_flow",
                "pr081_local_concurrency_frontend",
                "pr082_local_concurrency_analysis",
                "pr083_interface_contracts",
                "pr083a_public_constants",
                "pr084_transitive_concurrency",
                "pr08_frontend_baseline",
                "pr09a_emitter_surface",
                "pr09a_emitter_mvp",
                "pr09b_sequential_semantics",
                "pr09b_concurrency_output",
                "pr09b_snapshot_refresh",
                "pr09_ada_emission_baseline",
                "pr10_contract_baseline",
                "pr10_emitted_flow",
                "pr10_emitted_prove",
                "pr10_emitted_baseline",
                "emitted_hardening_regressions",
                "pr101a_companion_proof_verification",
                "pr101b_template_proof_verification",
                "pr101_comprehensive_audit",
                "pr0694_output_contract_stability",
                "pr0697_gate_quality",
                "frontend_smoke",
                "pr0699_build_reproducibility",
                "pr0693_runtime_boundary",
                "pr068_ada_ast_emit_no_python",
                "pr06910_portability_environment",
                "pr0698_legacy_package_cleanup",
                "pr06912_performance_scale_sanity",
                "pr06911_glue_script_safety",
                "pr06913_documentation_architecture_clarity",
            ],
        )

    def test_branch_resolution_pr115(self) -> None:
        self.assertEqual(
            [node.id for node in resolve_branch("codex/pr115-statement-ergonomics")],
            [
                "validate_execution_state_preflight",
                "build_initial",
                "pr111_language_eval",
                "pr112_parser_completeness",
                "pr113_discriminated_types",
                "pr113a_proof_checkpoint",
                "pr114_signature_control_flow",
                "pr115_statement_ergonomics",
                "pr081_local_concurrency_frontend",
                "pr082_local_concurrency_analysis",
                "pr083_interface_contracts",
                "pr083a_public_constants",
                "pr084_transitive_concurrency",
                "pr08_frontend_baseline",
                "pr09a_emitter_surface",
                "pr09a_emitter_mvp",
                "pr09b_sequential_semantics",
                "pr09b_concurrency_output",
                "pr09b_snapshot_refresh",
                "pr09_ada_emission_baseline",
                "pr10_contract_baseline",
                "pr10_emitted_flow",
                "pr10_emitted_prove",
                "pr10_emitted_baseline",
                "emitted_hardening_regressions",
                "pr101a_companion_proof_verification",
                "pr101b_template_proof_verification",
                "pr101_comprehensive_audit",
                "pr0694_output_contract_stability",
                "pr0697_gate_quality",
                "frontend_smoke",
                "pr0699_build_reproducibility",
                "pr0693_runtime_boundary",
                "pr068_ada_ast_emit_no_python",
                "pr06910_portability_environment",
                "pr0698_legacy_package_cleanup",
                "pr06912_performance_scale_sanity",
                "pr06911_glue_script_safety",
                "pr06913_documentation_architecture_clarity",
            ],
        )

    def test_branch_resolution_pr116(self) -> None:
        self.assertEqual(
            [node.id for node in resolve_branch("codex/pr116-meaningful-whitespace")],
            [
                "validate_execution_state_preflight",
                "build_initial",
                "pr111_language_eval",
                "pr112_parser_completeness",
                "pr113_discriminated_types",
                "pr113a_proof_checkpoint",
                "pr114_signature_control_flow",
                "pr115_statement_ergonomics",
                "pr116_meaningful_whitespace",
                "pr081_local_concurrency_frontend",
                "pr082_local_concurrency_analysis",
                "pr083_interface_contracts",
                "pr083a_public_constants",
                "pr084_transitive_concurrency",
                "pr08_frontend_baseline",
                "pr09a_emitter_surface",
                "pr09a_emitter_mvp",
                "pr09b_sequential_semantics",
                "pr09b_concurrency_output",
                "pr09b_snapshot_refresh",
                "pr09_ada_emission_baseline",
                "pr10_contract_baseline",
                "pr10_emitted_flow",
                "pr10_emitted_prove",
                "pr10_emitted_baseline",
                "emitted_hardening_regressions",
                "pr101a_companion_proof_verification",
                "pr101b_template_proof_verification",
                "pr101_comprehensive_audit",
                "pr0694_output_contract_stability",
                "pr0697_gate_quality",
                "frontend_smoke",
                "pr0699_build_reproducibility",
                "pr0693_runtime_boundary",
                "pr068_ada_ast_emit_no_python",
                "pr06910_portability_environment",
                "pr0698_legacy_package_cleanup",
                "pr06912_performance_scale_sanity",
                "pr06911_glue_script_safety",
                "pr06913_documentation_architecture_clarity",
            ],
        )

    def test_manifest_assigns_companion_and_template_clean_profiles(self) -> None:
        nodes = {node.id: node for node in NODES}
        self.assertEqual(
            nodes["pr101a_companion_proof_verification"].repo_clean_profile,
            "companion_gen_proof",
        )
        self.assertEqual(
            nodes["pr101b_template_proof_verification"].repo_clean_profile,
            "companion_template_proof",
        )
        self.assertTrue(nodes["pr09a_emitter_surface"].supports_scratch_root)
        self.assertEqual(nodes["pr09a_emitter_surface"].scratch_profile, "surface_emit_workspace")


if __name__ == "__main__":
    unittest.main()
