from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr08_frontend_baseline
import run_pr09_ada_emission_baseline
import run_pr10_emitted_baseline
import run_pr06910_portability_environment
import run_pr06911_glue_script_safety
import run_pr06913_documentation_architecture_clarity
import run_pr101_comprehensive_audit
from _lib.pr101_verification import normalized_gnatprove_summary_hash


class Pr101AuditHardeningTests(unittest.TestCase):
    def load_fixture_section(self, name: str) -> str:
        text = (FIXTURES_DIR / "pr101_audit_tables.txt").read_text(encoding="utf-8")
        marker = f"[{name}]"
        start = text.index(marker) + len(marker)
        next_section = text.find("\n[", start)
        if next_section == -1:
            next_section = len(text)
        return text[start:next_section].strip() + "\n"

    def test_pr08_baseline_parser_accepts_letter_suffixed_minor_ids(self) -> None:
        self.assertEqual(run_pr08_frontend_baseline.parse_task_id("PR09.1a"), (9, 1))
        self.assertEqual(run_pr08_frontend_baseline.parse_task_id("PR06.9.8"), (6, 9))
        self.assertTrue(run_pr08_frontend_baseline.next_task_is_at_or_beyond_pr09("PR10.3a"))
        self.assertFalse(run_pr08_frontend_baseline.next_task_is_at_or_beyond_pr09("PR08.4a"))

    def test_pr09_baseline_parser_accepts_letter_suffixed_minor_ids(self) -> None:
        self.assertEqual(run_pr09_ada_emission_baseline.parse_task_id("PR10.3a"), (10, 3))
        self.assertEqual(run_pr09_ada_emission_baseline.parse_task_id("PR06.9.10"), (6, 9))
        self.assertTrue(run_pr09_ada_emission_baseline.next_task_is_at_or_beyond_pr10("PR11.1a"))
        self.assertFalse(run_pr09_ada_emission_baseline.next_task_is_at_or_beyond_pr10("PR09.9a"))

    def test_pr10_baseline_parser_accepts_letter_suffixed_minor_ids(self) -> None:
        self.assertEqual(run_pr10_emitted_baseline.parse_task_id("PR10.3a"), (10, 3))
        self.assertEqual(run_pr10_emitted_baseline.parse_task_id("PR06.9.8"), (6, 9))
        self.assertTrue(run_pr10_emitted_baseline.next_task_is_at_or_beyond_pr10("PR10.11a"))
        self.assertFalse(run_pr10_emitted_baseline.next_task_is_at_or_beyond_pr10("PR09.9a"))

    def test_pr101_audit_parser_accepts_three_level_ids(self) -> None:
        self.assertEqual(run_pr101_comprehensive_audit.parse_task_id("PR06.9.8"), (6, 9))
        self.assertEqual(run_pr101_comprehensive_audit.parse_task_id("PR06.9.10"), (6, 9))
        self.assertEqual(run_pr101_comprehensive_audit.parse_task_id("PR10.3a"), (10, 3))

    def test_pr101_audit_next_task_guard_accepts_pr112_and_beyond(self) -> None:
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr112("PR11.2"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr112("PR11.3a"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr112("PR12.1"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr112("PR11.1"))

    def test_pr101_audit_next_task_guard_accepts_pr113_and_beyond(self) -> None:
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113("PR11.3"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113("PR11.3a"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113("PR12.1"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113("PR11.2"))

    def test_pr101_audit_next_task_guard_accepts_pr113a_and_beyond(self) -> None:
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113a("PR11.3a"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113a("PR11.3b"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113a("PR11.4"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113a("PR12.1"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113a("PR11.3"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr113a("PR11.2"))

    def test_pr101_audit_next_task_guard_accepts_pr114_and_beyond(self) -> None:
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr114("PR11.4"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr114("PR11.4a"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr114("PR12.1"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr114("PR11.3a"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr114("PR11.3"))

    def test_pr101_audit_next_task_guard_accepts_pr115_and_beyond(self) -> None:
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr115("PR11.5"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr115("PR11.5a"))
        self.assertTrue(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr115("PR12.1"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr115("PR11.4"))
        self.assertFalse(run_pr101_comprehensive_audit.task_is_at_or_beyond_pr115("PR11.3a"))

    def test_pr101_audit_tracks_pr111_acceptance_and_evidence(self) -> None:
        self.assertEqual(
            run_pr101_comprehensive_audit.EXPECTED_PR111_EVIDENCE,
            ["execution/reports/pr111-language-evaluation-harness-report.json"],
        )
        self.assertEqual(len(run_pr101_comprehensive_audit.EXPECTED_PR111_ACCEPTANCE), 3)
        self.assertIn(
            "safe build <file.safe>",
            run_pr101_comprehensive_audit.EXPECTED_PR111_ACCEPTANCE[0],
        )

    def test_pr101_audit_tracks_pr112_acceptance_and_evidence(self) -> None:
        self.assertEqual(
            run_pr101_comprehensive_audit.EXPECTED_PR112_EVIDENCE,
            ["execution/reports/pr112-parser-completeness-phase1-report.json"],
        )
        self.assertEqual(len(run_pr101_comprehensive_audit.EXPECTED_PR112_ACCEPTANCE), 3)
        self.assertIn(
            "string/character literals and case statements",
            run_pr101_comprehensive_audit.EXPECTED_PR112_ACCEPTANCE[0],
        )

    def test_pr101_audit_tracks_pr113_acceptance_and_evidence(self) -> None:
        self.assertEqual(
            run_pr101_comprehensive_audit.EXPECTED_PR113_EVIDENCE,
            ["execution/reports/pr113-discriminated-types-tuples-structured-returns-report.json"],
        )
        self.assertEqual(len(run_pr101_comprehensive_audit.EXPECTED_PR113_ACCEPTANCE), 3)
        self.assertIn(
            "tuple returns/destructuring/field access/channel elements",
            run_pr101_comprehensive_audit.EXPECTED_PR113_ACCEPTANCE[1],
        )
        self.assertEqual(len(run_pr101_comprehensive_audit.EXPECTED_PR113A_ACCEPTANCE), 3)
        self.assertIn(
            "tests/positive/pr113_tuple_channel.safe is explicitly excluded",
            run_pr101_comprehensive_audit.EXPECTED_PR113A_ACCEPTANCE[0],
        )
        self.assertEqual(
            run_pr101_comprehensive_audit.EXPECTED_PR113A_EVIDENCE,
            ["execution/reports/pr113a-proof-checkpoint1-report.json"],
        )
        self.assertEqual(
            run_pr101_comprehensive_audit.EXPECTED_PR114_EVIDENCE,
            ["execution/reports/pr114-signature-control-flow-syntax-report.json"],
        )
        self.assertEqual(len(run_pr101_comprehensive_audit.EXPECTED_PR114_ACCEPTANCE), 3)
        self.assertIn(
            "legacy `procedure`, signature `return`, `elsif`, and `..` spellings are removed",
            run_pr101_comprehensive_audit.EXPECTED_PR114_ACCEPTANCE[0],
        )

    def test_pr08_pipeline_subgates_reuse_cached_results(self) -> None:
        results = run_pr08_frontend_baseline.pipeline_subgates(
            pipeline_input={
                "pr081_local_concurrency_frontend": {
                    "result": {
                        "command": [
                            "python3",
                            "scripts/run_pr081_local_concurrency_frontend.py",
                            "--report",
                            "$TMPDIR/pr081_local_concurrency_frontend.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                        "stdout": "pr08.1 local concurrency frontend: OK ($TMPDIR/pr081_local_concurrency_frontend.json)\n",
                        "stderr": "",
                    }
                },
                "pr082_local_concurrency_analysis": {
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "ok", "stderr": ""}
                },
                "pr083_interface_contracts": {
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "ok", "stderr": ""}
                },
                "pr083a_public_constants": {
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "ok", "stderr": ""}
                },
                "pr084_transitive_concurrency": {
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "ok", "stderr": ""}
                },
            }
        )
        self.assertEqual(len(results), 5)
        self.assertEqual(results["run_pr081_local_concurrency_frontend.py"]["returncode"], 0)
        self.assertEqual(
            results["run_pr081_local_concurrency_frontend.py"]["command"],
            ["python3", "scripts/run_pr081_local_concurrency_frontend.py"],
        )
        self.assertEqual(
            results["run_pr081_local_concurrency_frontend.py"]["stdout"],
            "pr08.1 local concurrency frontend: OK (execution/reports/pr081-local-concurrency-frontend-report.json)\n",
        )

    def test_pr09_pipeline_slice_reports_reuse_cached_stdout_and_hash(self) -> None:
        results = run_pr09_ada_emission_baseline.build_slice_reports_from_pipeline(
            pipeline_input={
                "pr09a_emitter_surface": {
                    "result": {"stdout": "pr09a emitter surface: OK ($TMPDIR/pr09a_emitter_surface.json)\n"},
                    "report": {"report_sha256": "1" * 64, "deterministic": True},
                },
                "pr09a_emitter_mvp": {
                    "result": {"stdout": "pr09a emitter MVP: OK ($TMPDIR/pr09a_emitter_mvp.json)\n"},
                    "report": {"report_sha256": "2" * 64, "deterministic": True},
                },
                "pr09b_sequential_semantics": {
                    "result": {"stdout": "pr09b sequential semantics: OK ($TMPDIR/pr09b_sequential_semantics.json)\n"},
                    "report": {"report_sha256": "3" * 64, "deterministic": True},
                },
                "pr09b_concurrency_output": {
                    "result": {"stdout": "pr09b concurrency output: OK ($TMPDIR/pr09b_concurrency_output.json)\n"},
                    "report": {"report_sha256": "4" * 64, "deterministic": True},
                },
                "pr09b_snapshot_refresh": {
                    "result": {"stdout": "pr09b snapshot refresh: OK ($TMPDIR/pr09b_snapshot_refresh.json)\n"},
                    "report": {"report_sha256": "5" * 64, "deterministic": True},
                },
            }
        )
        self.assertEqual(
            results[0]["stdout"],
            "pr09a emitter surface: OK ($TMPDIR/run_pr09a_emitter_surface.json)\n",
        )
        self.assertEqual(results[-1]["report_sha256"], "5" * 64)

    def test_pr10_pipeline_slice_reports_reuse_cached_stdout_and_hash(self) -> None:
        results = run_pr10_emitted_baseline.build_slice_reports_from_pipeline(
            pipeline_input={
                "pr10_contract_baseline": {
                    "result": {"stdout": "pr10 contract baseline: OK ($TMPDIR/pr10_contract_baseline.json)\n"},
                    "report": {"report_sha256": "1" * 64, "deterministic": True},
                },
                "pr10_emitted_flow": {
                    "result": {"stdout": "pr10 emitted flow: OK ($TMPDIR/pr10_emitted_flow.json)\n"},
                    "report": {"report_sha256": "2" * 64, "deterministic": True},
                },
                "pr10_emitted_prove": {
                    "result": {"stdout": "pr10 emitted prove: OK ($TMPDIR/pr10_emitted_prove.json)\n"},
                    "report": {"report_sha256": "3" * 64, "deterministic": True},
                },
            }
        )
        self.assertEqual(
            results[1]["stdout"],
            "pr10 emitted flow: OK ($TMPDIR/run_pr10_emitted_flow.json)\n",
        )
        self.assertEqual(results[2]["deterministic"], True)

    def test_pr101_semantic_floor_tracks_baseline_hashes_and_anchor_hashes(self) -> None:
        baseline_truth = {
            "python_gates": [
                {
                    "script": "scripts/run_pr08_frontend_baseline.py",
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "", "stderr": ""},
                    "report_sha256": "1" * 64,
                    "deterministic": True,
                },
                {
                    "script": "scripts/run_pr09_ada_emission_baseline.py",
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "", "stderr": ""},
                    "report_sha256": "2" * 64,
                    "deterministic": True,
                },
                {
                    "script": "scripts/run_pr10_emitted_baseline.py",
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "", "stderr": ""},
                    "report_sha256": "3" * 64,
                    "deterministic": True,
                },
                {
                    "script": "scripts/run_emitted_hardening_regressions.py",
                    "result": {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "", "stderr": ""},
                    "report_sha256": "4" * 64,
                    "deterministic": True,
                },
            ],
            "verification_reports": [
                {
                    "node_id": "pr101a_companion_proof_verification",
                    "script": "scripts/run_pr101a_companion_proof_verification.py",
                    "report_sha256": "5" * 64,
                    "deterministic": True,
                },
                {
                    "node_id": "pr101b_template_proof_verification",
                    "script": "scripts/run_pr101b_template_proof_verification.py",
                    "report_sha256": "6" * 64,
                    "deterministic": True,
                },
            ],
        }
        self.assertEqual(
            run_pr101_comprehensive_audit.semantic_floor_from_baseline_truth(baseline_truth=baseline_truth),
            {
                "baseline_gate_hashes": {
                    "pr08_frontend_baseline": "1" * 64,
                    "pr09_ada_emission_baseline": "2" * 64,
                    "pr10_emitted_baseline": "3" * 64,
                    "emitted_hardening_regressions": "4" * 64,
                },
                "child_report_hashes": {
                    "pr101a_companion_proof_verification": "5" * 64,
                    "pr101b_template_proof_verification": "6" * 64,
                },
            },
        )

    def test_pr101_split_baseline_truth_moves_raw_transport_to_machine_sensitive(self) -> None:
        baseline_truth = {
            "python_gates": [
                {
                    "script": "scripts/run_pr08_frontend_baseline.py",
                    "result": {
                        "command": ["python3", "scripts/run_pr08_frontend_baseline.py", "--report", "$TMPDIR/pr08.json"],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                        "stdout": "ok\n",
                        "stderr": "",
                    },
                    "report_sha256": "1" * 64,
                    "deterministic": True,
                }
            ],
            "verification_reports": [
                {
                    "node_id": "pr101a_companion_proof_verification",
                    "script": "scripts/run_pr101a_companion_proof_verification.py",
                    "report_sha256": "2" * 64,
                    "deterministic": True,
                },
                {
                    "node_id": "pr101b_template_proof_verification",
                    "script": "scripts/run_pr101b_template_proof_verification.py",
                    "report_sha256": "3" * 64,
                    "deterministic": True,
                },
            ],
        }
        canonical, machine = run_pr101_comprehensive_audit.split_baseline_truth(
            baseline_truth=baseline_truth
        )
        self.assertEqual(canonical["python_gates"][0]["result"]["returncode"], 0)
        self.assertIn("command_profile", canonical["python_gates"][0]["result"])
        self.assertNotIn("command", canonical["python_gates"][0]["result"])
        self.assertEqual(
            machine["python_gates"][0]["result"]["command"],
            ["python3", "scripts/run_pr08_frontend_baseline.py", "--report", "$TMPDIR/pr08.json"],
        )
        self.assertEqual(canonical["verification_reports"][0]["report_sha256"], "2" * 64)
        self.assertNotIn("verification_reports", machine)

    def test_pr06910_pipeline_rerun_reuses_cached_result(self) -> None:
        rerun = run_pr06910_portability_environment.pipeline_rerun(
            pipeline_input={
                "pr0693_runtime_boundary": {
                    "result": {
                        "command": [
                            "python3",
                            "scripts/run_pr0693_runtime_boundary.py",
                            "--report",
                            "$TMPDIR/pr0693_runtime_boundary.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                    }
                }
            },
            node_id="pr0693_runtime_boundary",
            script=run_pr06910_portability_environment.RUNTIME_BOUNDARY_SCRIPT,
            committed_report_path=run_pr06910_portability_environment.RUNTIME_BOUNDARY_REPORT,
        )
        self.assertTrue(rerun["matches_committed_report"])
        self.assertEqual(rerun["rerun"]["returncode"], 0)
        self.assertEqual(
            rerun["rerun"]["command"],
            [
                "python3",
                "scripts/run_pr0693_runtime_boundary.py",
                "--report",
                "$TMPDIR/pr0693-runtime-boundary-report.json",
            ],
        )

    def test_pr06911_does_not_embed_inline_validate_execution_state(self) -> None:
        with mock.patch.object(
            run_pr06911_glue_script_safety,
            "glue_script_safety_report",
            return_value={
                "subprocess_import_violations": [],
                "subprocess_call_violations": [],
                "shell_assumption_violations": [],
                "tempdir_violations": [],
                "report_helper_violations": [],
                "command_lookup_violations": [],
                "unauthorized_safe_source_readers": [],
            },
        ), mock.patch.object(
            run_pr06911_glue_script_safety,
            "check_glue_script_safety",
        ), mock.patch.object(
            run_pr06911_glue_script_safety,
            "require_repo_command",
        ), mock.patch.object(
            run_pr06911_glue_script_safety,
            "reference_committed_report",
            return_value={"matches_committed_report": True},
        ), mock.patch.object(
            run_pr06911_glue_script_safety,
            "run",
            side_effect=AssertionError("unexpected subprocess rerun"),
        ):
            report = run_pr06911_glue_script_safety.generate_report(
                python="python3",
                env={},
                pipeline_input={},
                generated_root=None,
            )
        self.assertNotIn("validate_execution_state", report["reruns"])

    def test_pr06913_does_not_embed_inline_validate_execution_state(self) -> None:
        with mock.patch.object(
            run_pr06913_documentation_architecture_clarity,
            "documentation_architecture_clarity_report",
            return_value={},
        ), mock.patch.object(
            run_pr06913_documentation_architecture_clarity,
            "check_documentation_architecture_clarity",
        ), mock.patch.object(
            run_pr06913_documentation_architecture_clarity,
            "reference_committed_report",
            return_value={"matches_committed_report": True},
        ):
            final_report = run_pr06913_documentation_architecture_clarity.build_report(
                clarity_report={},
                runtime_boundary={"matches_committed_report": True},
                legacy_cleanup={"matches_committed_report": True},
                portability_environment={"matches_committed_report": True},
                gate_quality={"matches_committed_report": True},
                glue_script_safety={"matches_committed_report": True},
                performance_scale_sanity={"matches_committed_report": True},
            )
        self.assertNotIn("validate_execution_state", final_report["reruns"])

    def test_pr101_pipeline_baseline_truth_uses_cached_python_gates_only(self) -> None:
        baseline_truth = run_pr101_comprehensive_audit.pipeline_baseline_truth(
            env={},
            pipeline_input={
                "pr08_frontend_baseline": {
                    "result": {
                        "command": [
                            "python3",
                            "scripts/run_pr08_frontend_baseline.py",
                            "--pipeline-input",
                            "$TMPDIR/pipeline-input.json",
                            "--report",
                            "$TMPDIR/pr08_frontend_baseline.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                    },
                    "report": {"report_sha256": "1" * 64, "deterministic": True},
                },
                "pr09_ada_emission_baseline": {
                    "result": {
                        "command": [
                            "python3",
                            "scripts/run_pr09_ada_emission_baseline.py",
                            "--pipeline-input",
                            "$TMPDIR/pipeline-input.json",
                            "--report",
                            "$TMPDIR/pr09_ada_emission_baseline.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                    },
                    "report": {"report_sha256": "2" * 64, "deterministic": True},
                },
                "pr10_emitted_baseline": {
                    "result": {
                        "command": [
                            "python3",
                            "scripts/run_pr10_emitted_baseline.py",
                            "--pipeline-input",
                            "$TMPDIR/pipeline-input.json",
                            "--report",
                            "$TMPDIR/pr10_emitted_baseline.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                    },
                    "report": {"report_sha256": "3" * 64, "deterministic": True},
                },
                "emitted_hardening_regressions": {
                    "result": {
                        "command": [
                            "python3",
                            "scripts/run_emitted_hardening_regressions.py",
                            "--report",
                            "$TMPDIR/emitted_hardening_regressions.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                    },
                    "report": {"report_sha256": "4" * 64, "deterministic": True},
                },
                "pr101a_companion_proof_verification": {
                    "report": {"report_sha256": "5" * 64, "deterministic": True},
                },
                "pr101b_template_proof_verification": {
                    "report": {"report_sha256": "6" * 64, "deterministic": True},
                },
            },
        )
        self.assertEqual(len(baseline_truth["python_gates"]), 4)
        self.assertEqual(len(baseline_truth["verification_reports"]), 2)
        self.assertEqual(
            baseline_truth["verification_reports"][0]["node_id"],
            "pr101a_companion_proof_verification",
        )
        self.assertEqual(
            baseline_truth["python_gates"][0]["result"]["command"],
            [
                "python3",
                "scripts/run_pr08_frontend_baseline.py",
                "--report",
                "$TMPDIR/run_pr08_frontend_baseline.json",
            ],
        )

    def test_split_table_row_rejects_non_data_rows(self) -> None:
        self.assertEqual(
            run_pr101_comprehensive_audit.split_table_row("| `PR101-030` | `tooling` |"),
            ["`PR101-030`", "`tooling`"],
        )
        self.assertIsNone(
            run_pr101_comprehensive_audit.split_table_row("| ----------- | --------- |")
        )
        self.assertIsNone(run_pr101_comprehensive_audit.split_table_row("not a table row"))

    def test_parse_findings_ignores_malformed_rows_and_keeps_multi_target_cells(self) -> None:
        findings = run_pr101_comprehensive_audit.parse_findings(self.load_fixture_section("findings"))
        self.assertEqual(len(findings), 2)
        self.assertEqual(findings[0]["id"], "PR101-030")
        self.assertEqual(findings[0]["area"], "tooling")
        self.assertEqual(findings[0]["target"], "PR10.4; PR10.5")
        self.assertEqual(findings[1]["id"], "PR101-031")
        self.assertEqual(findings[1]["target"], "PR10.4")

    def test_parse_residuals_ignores_malformed_rows(self) -> None:
        residuals = run_pr101_comprehensive_audit.parse_residuals(self.load_fixture_section("residuals"))
        self.assertEqual(
            residuals,
            [
                {
                    "id": "PS-001",
                    "item": "Named numbers and richer constant evaluation",
                    "source": "Spec retained residual",
                    "area": "frontend",
                    "priority": "blocking-if-needed",
                },
                {
                    "id": "PS-002",
                    "item": "Fixed-point Rule 5 coverage",
                    "source": "Spec retained residual",
                    "area": "analysis",
                    "priority": "nice-to-have",
                },
                {
                    "id": "PS-026",
                    "item": "Broader floating semantics",
                    "source": "Spec retained residual",
                    "area": "analysis",
                    "priority": "long-term",
                },
            ],
        )

    def test_parse_summary_counts_extracts_known_priority_rows(self) -> None:
        self.assertEqual(
            run_pr101_comprehensive_audit.parse_summary_counts(self.load_fixture_section("summary")),
            {
                "blocking-if-needed": 14,
                "nice-to-have": 3,
                "long-term": 16,
                "Total": 33,
            },
        )

    def test_normalized_gnatprove_summary_hash_ignores_percentage_drift(self) -> None:
        first = """tool chatter
Summary of SPARK analysis
=========================

---------------------------------------------------------------------------------------------------
SPARK Analysis results        Total        Flow                      Provers   Justified   Unproved
---------------------------------------------------------------------------------------------------
Run-time Checks                  15           .                    14 (CVC5)           1          .
Functional Contracts             20           .    20 (CVC5 96%, Trivial 4%)           .          .
---------------------------------------------------------------------------------------------------
Total                            64    29 (45%)                     34 (53%)      1 (2%)          .
"""
        second = """other chatter
Summary of SPARK analysis
=========================

---------------------------------------------------------------------------------------------------
SPARK Analysis results        Total        Flow                      Provers   Justified   Unproved
---------------------------------------------------------------------------------------------------
Run-time Checks                  15           .                    14 (CVC5)           1          .
Functional Contracts             20           .    20 (CVC5 100%, Trivial 0%)           .          .
---------------------------------------------------------------------------------------------------
Total                            64    29 (46%)                     34 (52%)      1 (2%)          .
"""
        with tempfile.TemporaryDirectory() as temp_dir:
            first_path = Path(temp_dir) / "first.out"
            second_path = Path(temp_dir) / "second.out"
            first_path.write_text(first, encoding="utf-8")
            second_path.write_text(second, encoding="utf-8")
            self.assertEqual(
                normalized_gnatprove_summary_hash(first_path),
                normalized_gnatprove_summary_hash(second_path),
            )

    def test_normalized_gnatprove_summary_hash_requires_summary_block(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "missing.out"
            output_path.write_text("no summary here\n", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                normalized_gnatprove_summary_hash(output_path)


if __name__ == "__main__":
    unittest.main()
