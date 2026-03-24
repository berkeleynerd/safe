from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from _lib.attestation_compression import RETIRED_ARCHIVE_REPORT_PATHS, RETIRED_NODE_IDS
from _lib.gate_manifest import NODES, resolve_branch, validate_manifest


class GateManifestTests(unittest.TestCase):
    def test_manifest_is_acyclic(self) -> None:
        validate_manifest()

    def test_manifest_nodes_are_unique(self) -> None:
        node_ids = [node.id for node in NODES]
        self.assertEqual(len(node_ids), len(set(node_ids)))
        self.assertEqual(len(NODES), 37)

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
        manifest_reports.update(RETIRED_ARCHIVE_REPORT_PATHS.values())
        self.assertEqual(set(), tracker_reports - manifest_reports)

    def test_branch_resolution_pr10(self) -> None:
        self.assertEqual(
            [node.id for node in resolve_branch("codex/pr10-emitted-baseline")],
            [
                "validate_execution_state_preflight",
                "build_initial",
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

    def test_manifest_retires_historical_pr101_children(self) -> None:
        nodes = {node.id: node for node in NODES}
        for node_id in RETIRED_NODE_IDS:
            self.assertNotIn(node_id, nodes)
        self.assertIn("pr101_comprehensive_audit", nodes)
        self.assertEqual(
            nodes["pr101_comprehensive_audit"].depends_on,
            ("build_initial", "validate_execution_state_preflight"),
        )


if __name__ == "__main__":
    unittest.main()
