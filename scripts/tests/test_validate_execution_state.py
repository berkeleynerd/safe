from __future__ import annotations

import io
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import validate_execution_state
from validate_execution_state import (
    EVIDENCE_POLICY_SHA256,
    GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS,
    GLUE_SAFETY_AUDITED_SCRIPTS,
    GLUE_SAFETY_REPORT_SCRIPTS,
    check_pr101_report_sync,
    check_report_sync,
    check_dependencies,
    check_documentation_architecture_clarity,
    check_environment_assumptions,
    check_evidence_reproducibility,
    check_glue_script_safety,
    check_performance_scale_sanity,
    check_status_rules,
    check_test_distribution,
    count_test_files,
    documentation_architecture_clarity_report,
    environment_assumptions_report,
    evidence_reproducibility_report,
    glue_script_safety_report,
    legacy_frontend_cleanup_report,
    performance_scale_sanity_report,
    report_sync_report,
    resolve_tool_command,
    run_final_phase,
    run_preflight_phase,
    runtime_boundary_report,
)
from _lib.platform_assumptions import (
    PATH_LOOKUP_POLICY_TEXT,
    SHELL_POLICY_TEXT,
    SUPPORTED_PLATFORM_POLICY_TEXT,
    TEMPDIR_POLICY_TEXT,
    UNSUPPORTED_PLATFORM_POLICY_TEXT,
)


class ValidateExecutionStateTests(unittest.TestCase):
    @staticmethod
    def _serialize_report(payload: dict[str, object]) -> str:
        return json.dumps(payload, indent=2, sort_keys=True) + "\n"

    @classmethod
    def _write_finalized_report(cls, path: Path, payload: dict[str, object]) -> str:
        report_sha = hashlib.sha256(cls._serialize_report(payload).encode("utf-8")).hexdigest()
        finalized = dict(payload)
        finalized["deterministic"] = True
        finalized["report_sha256"] = report_sha
        finalized["repeat_sha256"] = report_sha
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(cls._serialize_report(finalized), encoding="utf-8")
        return report_sha

    def test_pr111_glue_scripts_are_registered_for_safety_audit(self) -> None:
        self.assertIn("safe", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/safe_cli.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/safe_lsp.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_rosetta_corpus.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr111_language_evaluation_harness.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr112_parser_completeness_phase1.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_rosetta_corpus.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn("scripts/run_pr111_language_evaluation_harness.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn("scripts/run_pr112_parser_completeness_phase1.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn(
            "scripts/run_pr113_discriminated_types_tuples_structured_returns.py",
            GLUE_SAFETY_AUDITED_SCRIPTS,
        )
        self.assertIn(
            "scripts/run_pr113_discriminated_types_tuples_structured_returns.py",
            GLUE_SAFETY_REPORT_SCRIPTS,
        )
        self.assertIn("scripts/run_pr113a_proof_checkpoint1.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr113a_proof_checkpoint1.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn("scripts/run_pr113a_proof_checkpoint1.py", GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS)
        self.assertIn("scripts/run_pr114_signature_control_flow_syntax.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr114_signature_control_flow_syntax.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn("scripts/_lib/pr101_verification.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr101a_companion_proof_verification.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr101a_companion_proof_verification.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn("scripts/run_pr101b_template_proof_verification.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr101b_template_proof_verification.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn("scripts/run_pr101_comprehensive_audit.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_pr101_comprehensive_audit.py", GLUE_SAFETY_REPORT_SCRIPTS)
        self.assertIn("scripts/_lib/gate_manifest.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn("scripts/run_gate_pipeline.py", GLUE_SAFETY_AUDITED_SCRIPTS)
        self.assertIn(
            "scripts/run_pr114_signature_control_flow_syntax.py",
            GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS,
        )

    def test_report_sync_report_accepts_matching_child_reports(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            child_path = repo_root / "execution" / "reports" / "child.json"
            child_sha = self._write_finalized_report(child_path, {"status": "ok"})
            umbrella_path = repo_root / "execution" / "reports" / "umbrella.json"
            self._write_finalized_report(
                umbrella_path,
                {
                    "slice_reports": [
                        {
                            "script": "scripts/run_child.py",
                            "report_sha256": child_sha,
                        }
                    ]
                },
            )
            report_specs = {
                "execution/reports/umbrella.json": {
                    "entry_list_key": "slice_reports",
                    "entry_id_key": "script",
                    "entry_sha_key": "report_sha256",
                    "children": {"scripts/run_child.py": "execution/reports/child.json"},
                }
            }
            report = report_sync_report(repo_root=repo_root, report_specs=report_specs)
            self.assertEqual(report["child_report_sha_mismatches"], [])
            check_report_sync(repo_root=repo_root, report_specs=report_specs)

    def test_check_report_sync_rejects_stale_child_report_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            child_path = repo_root / "execution" / "reports" / "child.json"
            self._write_finalized_report(child_path, {"status": "ok"})
            umbrella_path = repo_root / "execution" / "reports" / "umbrella.json"
            self._write_finalized_report(
                umbrella_path,
                {
                    "slice_reports": [
                        {
                            "script": "scripts/run_child.py",
                            "report_sha256": "0" * 64,
                        }
                    ]
                },
            )
            report_specs = {
                "execution/reports/umbrella.json": {
                    "entry_list_key": "slice_reports",
                    "entry_id_key": "script",
                    "entry_sha_key": "report_sha256",
                    "children": {"scripts/run_child.py": "execution/reports/child.json"},
                }
            }
            report = report_sync_report(repo_root=repo_root, report_specs=report_specs)
            self.assertEqual(len(report["child_report_sha_mismatches"]), 1)
            with self.assertRaises(ValueError):
                check_report_sync(repo_root=repo_root, report_specs=report_specs)

    def test_check_pr101_report_sync_accepts_matching_child_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            report_root = repo_root / "execution" / "reports"
            baseline_reports = {
                "pr08_frontend_baseline": "pr08-frontend-baseline-report.json",
                "pr09_ada_emission_baseline": "pr09-ada-emission-baseline-report.json",
                "pr10_emitted_baseline": "pr10-emitted-baseline-report.json",
                "emitted_hardening_regressions": "emitted-hardening-regressions-report.json",
            }
            baseline_hashes = {
                node_id: self._write_finalized_report(report_root / filename, {"status": node_id})
                for node_id, filename in baseline_reports.items()
            }
            child_hashes = {
                "pr101a_companion_proof_verification": self._write_finalized_report(
                    report_root / "pr101a-companion-proof-verification-report.json",
                    {
                        "task": "PR10.1",
                        "verification": "companion",
                        "semantic_floor": {
                            "build_returncode": 0,
                            "flow_returncode": 0,
                            "prove_returncode": 0,
                            "extract_assumptions_returncode": 0,
                            "diff_assumptions_returncode": 0,
                            "assumptions_extracted_sha256": "1" * 64,
                            "prove_golden_sha256": "2" * 64,
                            "gnatprove_summary_sha256": "3" * 64,
                        },
                        "canonical_proof_detail": {},
                        "machine_sensitive": {},
                    },
                ),
                "pr101b_template_proof_verification": self._write_finalized_report(
                    report_root / "pr101b-template-proof-verification-report.json",
                    {
                        "task": "PR10.1",
                        "verification": "templates",
                        "semantic_floor": {
                            "build_returncode": 0,
                            "flow_returncode": 0,
                            "prove_returncode": 0,
                            "extract_assumptions_returncode": 0,
                            "diff_assumptions_returncode": 0,
                            "assumptions_extracted_sha256": "4" * 64,
                            "prove_golden_sha256": "5" * 64,
                            "gnatprove_summary_sha256": "6" * 64,
                        },
                        "canonical_proof_detail": {},
                        "machine_sensitive": {},
                    },
                ),
            }
            self._write_finalized_report(
                report_root / "pr101-comprehensive-audit-report.json",
                {
                    "task": "PR10.1",
                    "semantic_floor": {
                        "baseline_gate_hashes": baseline_hashes,
                        "child_report_hashes": child_hashes,
                    },
                    "canonical_proof_detail": {},
                    "machine_sensitive": {},
                },
            )
            check_pr101_report_sync(repo_root=repo_root)

    def test_report_sync_report_rejects_non_object_umbrella_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            umbrella_path = repo_root / "execution" / "reports" / "umbrella.json"
            umbrella_path.parent.mkdir(parents=True, exist_ok=True)
            umbrella_path.write_text("[]\n", encoding="utf-8")
            report_specs = {
                "execution/reports/umbrella.json": {
                    "entry_list_key": "slice_reports",
                    "entry_id_key": "script",
                    "entry_sha_key": "report_sha256",
                    "children": {},
                }
            }
            report = report_sync_report(repo_root=repo_root, report_specs=report_specs)
            self.assertEqual(
                report["invalid_reports"],
                ["execution/reports/umbrella.json: report root must be an object"],
            )

    def test_report_sync_report_rejects_non_object_child_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            child_path = repo_root / "execution" / "reports" / "child.json"
            child_path.parent.mkdir(parents=True, exist_ok=True)
            child_path.write_text("[]\n", encoding="utf-8")
            umbrella_path = repo_root / "execution" / "reports" / "umbrella.json"
            self._write_finalized_report(
                umbrella_path,
                {
                    "slice_reports": [
                        {
                            "script": "scripts/run_child.py",
                            "report_sha256": "0" * 64,
                        }
                    ]
                },
            )
            report_specs = {
                "execution/reports/umbrella.json": {
                    "entry_list_key": "slice_reports",
                    "entry_id_key": "script",
                    "entry_sha_key": "report_sha256",
                    "children": {"scripts/run_child.py": "execution/reports/child.json"},
                }
            }
            report = report_sync_report(repo_root=repo_root, report_specs=report_specs)
            self.assertEqual(
                report["invalid_reports"],
                ["execution/reports/child.json: report root must be an object"],
            )

    def test_check_dependencies_rejects_cycles(self) -> None:
        tasks = [
            {"id": "A", "depends_on": ["B"]},
            {"id": "B", "depends_on": ["A"]},
        ]
        with self.assertRaises(ValueError):
            check_dependencies(tasks)

    def test_check_status_rules_requires_evidence_for_done(self) -> None:
        tracker = {"active_task_id": None}
        tasks = [{"id": "A", "status": "done", "evidence": [], "depends_on": []}]
        with self.assertRaises(ValueError):
            check_status_rules(tracker, tasks)

    def test_check_test_distribution_uses_explicit_tests_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            tests_root = Path(temp_dir)
            for name, count in {
                "positive": 1,
                "negative": 2,
                "golden": 1,
                "concurrency": 0,
                "diagnostics_golden": 3,
            }.items():
                directory = tests_root / name
                directory.mkdir()
                for index in range(count):
                    if name == "golden":
                        (directory / f"case_{index}").mkdir()
                    else:
                        (directory / f"case_{index}.safe").write_text("", encoding="utf-8")

            tracker = {
                "repo_facts": {
                    "tests": {
                        "positive": 1,
                        "negative": 2,
                        "golden": 1,
                        "concurrency": 0,
                        "diagnostics_golden": 3,
                        "total": 7,
                    }
                }
            }
            self.assertEqual(count_test_files(tests_root), tracker["repo_facts"]["tests"])
            check_test_distribution(tracker, tests_root=tests_root)

    def test_runtime_boundary_report_scans_explicit_repo_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            source_dir = repo_root / "compiler_impl" / "src"
            source_dir.mkdir(parents=True)
            (source_dir / "safe_frontend-sample.adb").write_text(
                "procedure Sample is begin Spawn; end Sample;\n",
                encoding="utf-8",
            )
            (source_dir / "safec.adb").write_text(
                "with GNAT.OS_Lib;\nprocedure Safec is begin GNAT.OS_Lib.OS_Exit (0); end Safec;\n",
                encoding="utf-8",
            )
            report = runtime_boundary_report(
                repo_root=repo_root,
                runtime_boundary_patterns=[
                    ("compiler_impl/src/safe_frontend-*.adb", [r"\bSpawn\b"]),
                    ("compiler_impl/src/safec.adb", []),
                ],
            )
            self.assertFalse(report["legacy_backend_present"])
            self.assertEqual(report["scanned_files"], ["compiler_impl/src/safe_frontend-sample.adb", "compiler_impl/src/safec.adb"])
            self.assertIn("compiler_impl/src/safe_frontend-sample.adb:\\bSpawn\\b", report["violations"])

    def test_legacy_frontend_cleanup_report_scans_explicit_repo_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            source_dir = repo_root / "compiler_impl" / "src"
            source_dir.mkdir(parents=True)
            (source_dir / "safe_frontend-ast.ads").write_text(
                "package Safe_Frontend.Ast is end Safe_Frontend.Ast;\n",
                encoding="utf-8",
            )
            (source_dir / "safe_frontend-driver.adb").write_text(
                "with SAFE_FRONTEND.AST;\npackage body Safe_Frontend.Driver is end Safe_Frontend.Driver;\n",
                encoding="utf-8",
            )
            (source_dir / "safe_frontend-sample.adb").write_text(
                "with safe_frontend.ast;\nprocedure Sample is begin null; end Sample;\n",
                encoding="utf-8",
            )
            (source_dir / "safec.adb").write_text(
                "procedure Safec is begin null; end Safec;\n",
                encoding="utf-8",
            )
            report = legacy_frontend_cleanup_report(
                repo_root=repo_root,
                package_names=["Safe_Frontend.Ast"],
                file_names=["safe_frontend-ast.ads", "safe_frontend-ast.adb"],
                live_root_patterns=["compiler_impl/src/safe_frontend-driver.adb"],
            )
            self.assertEqual(report["present_files"], ["compiler_impl/src/safe_frontend-ast.ads"])
            self.assertEqual(report["missing_files"], ["compiler_impl/src/safe_frontend-ast.adb"])
            self.assertIn("compiler_impl/src/safe_frontend-ast.ads:Safe_Frontend.Ast", report["forbidden_references"])
            self.assertIn(
                "compiler_impl/src/safe_frontend-sample.adb:Safe_Frontend.Ast",
                report["forbidden_references"],
            )
            self.assertIn(
                "compiler_impl/src/safe_frontend-driver.adb:Safe_Frontend.Ast",
                report["live_runtime_reference_violations"],
            )

    def test_evidence_reproducibility_report_detects_noncanonical_and_markers(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            execution_dir = repo_root / "execution" / "reports"
            execution_dir.mkdir(parents=True)
            report_path = execution_dir / "sample.json"
            report_path.write_text(
                '{\n  "tool_versions": {"python3": "Python 3.11"},\n  "stdout": "Build finished successfully in 0.10 seconds. /Users/test"\n}\n',
                encoding="utf-8",
            )
            tracker = {
                "tasks": [
                    {
                        "id": "PRX",
                        "status": "done",
                        "evidence": ["execution/reports/sample.json"],
                    }
                ]
            }
            report = evidence_reproducibility_report(tracker=tracker, repo_root=repo_root)
            self.assertEqual(report["evidence_files"], ["execution/reports/sample.json"])
            self.assertEqual(report["noncanonical_files"], ["execution/reports/sample.json"])
            self.assertEqual(
                report["tool_version_fields"],
                ["execution/reports/sample.json:tool_versions"],
            )
            self.assertIn(
                "execution/reports/sample.json:Build finished successfully in",
                report["marker_violations"],
            )
            self.assertIn(
                "execution/reports/sample.json:Python ",
                report["marker_violations"],
            )
            self.assertIn(
                "execution/reports/sample.json:/Users/",
                report["marker_violations"],
            )

    def test_evidence_reproducibility_report_reports_invalid_json_with_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            execution_dir = repo_root / "execution" / "reports"
            execution_dir.mkdir(parents=True)
            report_path = execution_dir / "sample.json"
            report_path.write_text('{"status": "ok"\n', encoding="utf-8")
            tracker = {
                "tasks": [
                    {
                        "id": "PRX",
                        "status": "done",
                        "evidence": ["execution/reports/sample.json"],
                    }
                ]
            }
            report = evidence_reproducibility_report(tracker=tracker, repo_root=repo_root)
            self.assertEqual(
                report["noncanonical_files"],
                ["execution/reports/sample.json: invalid JSON (Expecting ',' delimiter)"],
            )

    def test_check_evidence_reproducibility_accepts_canonical_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            execution_dir = repo_root / "execution" / "reports"
            execution_dir.mkdir(parents=True)
            report_path = execution_dir / "sample.json"
            report_path.write_text('{\n  "status": "ok"\n}\n', encoding="utf-8")
            tracker = {
                "tasks": [
                    {
                        "id": "PRX",
                        "status": "done",
                        "evidence": ["execution/reports/sample.json"],
                    }
                ]
            }
            check_evidence_reproducibility(tracker, repo_root=repo_root)

    def test_evidence_reproducibility_report_ignores_in_flight_execution_state_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            tracker = {
                "tasks": [
                    {
                        "id": "PR00",
                        "status": "done",
                        "evidence": ["execution/reports/execution-state-validation-report.json"],
                    }
                ]
            }
            report = evidence_reproducibility_report(
                tracker=tracker,
                repo_root=repo_root,
                ignored_evidence=("execution/reports/execution-state-validation-report.json",),
            )
            self.assertEqual(report["evidence_files"], [])
            self.assertEqual(report["missing_files"], [])

    def test_environment_assumptions_report_detects_python_variants(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            source_dir = repo_root / "compiler_impl" / "src"
            source_dir.mkdir(parents=True)
            (source_dir / "safe_frontend-a.adb").write_text('python\n', encoding="utf-8")
            (source_dir / "safe_frontend-b.adb").write_text('python3\n', encoding="utf-8")
            (source_dir / "safe_frontend-c.adb").write_text('python3.11\n', encoding="utf-8")
            (source_dir / "safe_frontend-d.adb").write_text('bin/python3\n', encoding="utf-8")
            (source_dir / "safe_frontend-e.adb").write_text('./python3.11\n', encoding="utf-8")
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "policy.md").write_text(
                f"{SUPPORTED_PLATFORM_POLICY_TEXT}\n{UNSUPPORTED_PLATFORM_POLICY_TEXT}\n",
                encoding="utf-8",
            )
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from _lib.platform_assumptions import MASKED_PYTHON_INTERPRETERS\n"
                "from tempfile import TemporaryDirectory\n"
                "with TemporaryDirectory(prefix='ok-'):\n"
                "    pass\n"
                "find_command('python3')\n",
                encoding="utf-8",
            )
            report = environment_assumptions_report(
                repo_root=repo_root,
                doc_requirements={"docs/policy.md": [SUPPORTED_PLATFORM_POLICY_TEXT, UNSUPPORTED_PLATFORM_POLICY_TEXT]},
                runtime_source_globs=("compiler_impl/src/*.adb",),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )
            self.assertEqual(len(report["runtime_source_violations"]), 5)
            self.assertFalse(report["doc_policy_violations"])
            self.assertFalse(report["portability_module_violations"])

    def test_environment_assumptions_report_detects_policy_and_alignment_gaps(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "policy.md").write_text("local macOS only\n", encoding="utf-8")
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text("print('hello')\n", encoding="utf-8")
            report = environment_assumptions_report(
                repo_root=repo_root,
                doc_requirements={
                    "docs/policy.md": [
                        SUPPORTED_PLATFORM_POLICY_TEXT,
                        UNSUPPORTED_PLATFORM_POLICY_TEXT,
                        PATH_LOOKUP_POLICY_TEXT,
                        TEMPDIR_POLICY_TEXT,
                        SHELL_POLICY_TEXT,
                    ]
                },
                runtime_source_globs=(),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )
            self.assertIn(
                f"docs/policy.md:{SUPPORTED_PLATFORM_POLICY_TEXT}",
                report["doc_policy_violations"],
            )
            self.assertIn(
                "scripts/runtime_gate.py:platform_assumptions import missing",
                report["portability_module_violations"],
            )
            self.assertIn("scripts/runtime_gate.py", report["tempdir_convention_violations"])
            self.assertIn("scripts/runtime_gate.py", report["path_lookup_violations"])
            self.assertFalse(report["shell_assumption_violations"])

    def test_environment_assumptions_report_detects_shell_usage(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "policy.md").write_text(
                f"{SUPPORTED_PLATFORM_POLICY_TEXT}\n"
                f"{UNSUPPORTED_PLATFORM_POLICY_TEXT}\n"
                f"{PATH_LOOKUP_POLICY_TEXT}\n"
                f"{TEMPDIR_POLICY_TEXT}\n"
                f"{SHELL_POLICY_TEXT}\n",
                encoding="utf-8",
            )
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from _lib.platform_assumptions import MASKED_PYTHON_INTERPRETERS\n"
                "from tempfile import TemporaryDirectory\n"
                "import subprocess\n"
                "with TemporaryDirectory(prefix='ok-'):\n"
                "    pass\n"
                "find_command('python3')\n"
                "subprocess.run('echo hi', shell=True)\n",
                encoding="utf-8",
            )
            report = environment_assumptions_report(
                repo_root=repo_root,
                doc_requirements={
                    "docs/policy.md": [
                        SUPPORTED_PLATFORM_POLICY_TEXT,
                        UNSUPPORTED_PLATFORM_POLICY_TEXT,
                        PATH_LOOKUP_POLICY_TEXT,
                        TEMPDIR_POLICY_TEXT,
                        SHELL_POLICY_TEXT,
                    ]
                },
                runtime_source_globs=(),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )
            self.assertIn(
                "scripts/runtime_gate.py:shell=True",
                report["shell_assumption_violations"],
            )

    def test_check_environment_assumptions_accepts_valid_repo(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "policy.md").write_text(
                f"{SUPPORTED_PLATFORM_POLICY_TEXT}\n"
                f"{UNSUPPORTED_PLATFORM_POLICY_TEXT}\n"
                f"{PATH_LOOKUP_POLICY_TEXT}\n"
                f"{TEMPDIR_POLICY_TEXT}\n"
                f"{SHELL_POLICY_TEXT}\n"
                "`python`\n",
                encoding="utf-8",
            )
            source_dir = repo_root / "compiler_impl" / "src"
            source_dir.mkdir(parents=True)
            (source_dir / "safe_frontend-sample.adb").write_text("null;\n", encoding="utf-8")
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from _lib.platform_assumptions import MASKED_PYTHON_INTERPRETERS\n"
                "from tempfile import TemporaryDirectory\n"
                "with TemporaryDirectory(prefix='ok-'):\n"
                "    pass\n"
                "find_command('python3')\n",
                encoding="utf-8",
            )
            report = environment_assumptions_report(
                repo_root=repo_root,
                doc_requirements={
                    "docs/policy.md": [
                        SUPPORTED_PLATFORM_POLICY_TEXT,
                        UNSUPPORTED_PLATFORM_POLICY_TEXT,
                        PATH_LOOKUP_POLICY_TEXT,
                        TEMPDIR_POLICY_TEXT,
                        SHELL_POLICY_TEXT,
                    ]
                },
                runtime_source_globs=("compiler_impl/src/*.adb",),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )
            self.assertFalse(report["runtime_source_violations"])
            check_environment_assumptions(
                repo_root=repo_root,
                doc_requirements={
                    "docs/policy.md": [
                        SUPPORTED_PLATFORM_POLICY_TEXT,
                        UNSUPPORTED_PLATFORM_POLICY_TEXT,
                        PATH_LOOKUP_POLICY_TEXT,
                        TEMPDIR_POLICY_TEXT,
                        SHELL_POLICY_TEXT,
                    ]
                },
                runtime_source_globs=("compiler_impl/src/*.adb",),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )

    def test_environment_assumptions_report_accepts_managed_scratch_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "policy.md").write_text(
                f"{SUPPORTED_PLATFORM_POLICY_TEXT}\n"
                f"{UNSUPPORTED_PLATFORM_POLICY_TEXT}\n"
                f"{PATH_LOOKUP_POLICY_TEXT}\n"
                f"{TEMPDIR_POLICY_TEXT}\n"
                f"{SHELL_POLICY_TEXT}\n",
                encoding="utf-8",
            )
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from _lib.platform_assumptions import MASKED_PYTHON_INTERPRETERS\n"
                "from _lib.harness_common import managed_scratch_root\n"
                "with managed_scratch_root(scratch_root=None, prefix='ok-'):\n"
                "    pass\n"
                "find_command('python3')\n",
                encoding="utf-8",
            )
            report = environment_assumptions_report(
                repo_root=repo_root,
                doc_requirements={
                    "docs/policy.md": [
                        SUPPORTED_PLATFORM_POLICY_TEXT,
                        UNSUPPORTED_PLATFORM_POLICY_TEXT,
                        PATH_LOOKUP_POLICY_TEXT,
                        TEMPDIR_POLICY_TEXT,
                        SHELL_POLICY_TEXT,
                    ]
                },
                runtime_source_globs=(),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )
            self.assertFalse(report["tempdir_convention_violations"])

    def test_glue_script_safety_report_accepts_valid_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from pathlib import Path\n"
                "import tempfile\n"
                "from _lib.harness_common import finalize_deterministic_report, find_command, require_repo_command, run, write_report\n"
                "DEFAULT_REPORT = Path('execution/reports/sample.json')\n"
                "COMPILER_ROOT = Path('compiler_impl')\n"
                "with tempfile.TemporaryDirectory(prefix='ok-') as temp_dir:\n"
                "    pass\n"
                "git = find_command('git')\n"
                "require_repo_command(COMPILER_ROOT / 'bin' / 'safec', 'safec')\n"
                "run([git, 'status'], cwd=Path('.'))\n"
                "report = finalize_deterministic_report(lambda: {'status': 'ok'}, label='sample')\n"
                "write_report(DEFAULT_REPORT, report)\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=("scripts/runtime_gate.py",),
                path_commands=("git",),
            )
            self.assertFalse(report["subprocess_import_violations"])
            self.assertFalse(report["tempdir_violations"])
            self.assertFalse(report["command_lookup_violations"])
            self.assertFalse(report["report_helper_violations"])
            check_glue_script_safety(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=("scripts/runtime_gate.py",),
                path_commands=("git",),
            )

    def test_glue_script_safety_report_detects_shell_and_subprocess_usage(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "import os\n"
                "import subprocess\n"
                "subprocess.run(['echo'])\n"
                "subprocess.run('echo hi', shell=True)\n"
                "os.system('echo hi')\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=(),
            )
            self.assertIn("scripts/runtime_gate.py:subprocess", report["subprocess_import_violations"])
            self.assertIn("scripts/runtime_gate.py:subprocess.run", report["subprocess_call_violations"])
            self.assertIn("scripts/runtime_gate.py:shell=True", report["shell_assumption_violations"])
            self.assertIn("scripts/runtime_gate.py:os.system", report["shell_assumption_violations"])

    def test_glue_script_safety_report_detects_aliased_os_shell_calls(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from os import system as sh\n"
                "sh('echo hi')\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=(),
            )
            self.assertIn("scripts/runtime_gate.py:os.system", report["shell_assumption_violations"])

    def test_glue_script_safety_report_detects_missing_prefix_and_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "import tempfile\n"
                "from pathlib import Path\n"
                "from _lib.harness_common import finalize_deterministic_report, run, write_report\n"
                "DEFAULT_REPORT = Path('execution/reports/sample.json')\n"
                "COMPILER_ROOT = Path('compiler_impl')\n"
                "with tempfile.TemporaryDirectory() as temp_dir:\n"
                "    pass\n"
                "safec = COMPILER_ROOT / 'bin' / 'safec'\n"
                "run([str(safec), 'check'], cwd=Path('.'))\n"
                "run(['git', 'status'], cwd=Path('.'))\n"
                "report = finalize_deterministic_report(lambda: {'status': 'ok'}, label='sample')\n"
                "write_report(DEFAULT_REPORT, report)\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=("scripts/runtime_gate.py",),
                path_commands=("git",),
            )
            self.assertIn("scripts/runtime_gate.py:TemporaryDirectory", report["tempdir_violations"])
            self.assertIn("scripts/runtime_gate.py:git", report["command_lookup_violations"])
            self.assertIn("scripts/runtime_gate.py:safec", report["command_lookup_violations"])

    def test_glue_script_safety_report_allows_cleanup_only_repo_local_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from pathlib import Path\n"
                "from _lib.harness_common import finalize_deterministic_report, write_report\n"
                "DEFAULT_REPORT = Path('execution/reports/sample.json')\n"
                "COMPILER_ROOT = Path('compiler_impl')\n"
                "safec = COMPILER_ROOT / 'bin' / 'safec'\n"
                "if safec.exists():\n"
                "    safec.unlink()\n"
                "report = finalize_deterministic_report(lambda: {'status': 'ok'}, label='sample')\n"
                "write_report(DEFAULT_REPORT, report)\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=("scripts/runtime_gate.py",),
                path_commands=(),
            )
            self.assertFalse(report["command_lookup_violations"])

    def test_glue_script_safety_report_detects_aliased_tempfile_usage(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "import tempfile as tf\n"
                "with tf.TemporaryDirectory() as temp_dir:\n"
                "    pass\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=(),
            )
            self.assertIn("scripts/runtime_gate.py:TemporaryDirectory", report["tempdir_violations"])

    def test_glue_script_safety_report_detects_missing_report_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "def main():\n"
                "    return 0\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=("scripts/runtime_gate.py",),
            )
            self.assertIn(
                "scripts/runtime_gate.py:finalize_deterministic_report",
                report["report_helper_violations"],
            )
            self.assertIn(
                "scripts/runtime_gate.py:write_report",
                report["report_helper_violations"],
            )

    def test_glue_script_safety_report_reports_missing_scripts_clearly(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/missing_gate.py",),
                report_scripts=(),
            )
            self.assertEqual(report["missing_script_violations"], ["scripts/missing_gate.py"])

    def test_glue_script_safety_report_detects_unauthorized_safe_reader(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from pathlib import Path\n"
                "text = Path('case.safe').read_text(encoding='utf-8')\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=(),
            )
            self.assertTrue(report["unauthorized_safe_source_readers"])

    def test_glue_script_safety_report_detects_safe_reader_via_bound_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            scripts_dir = repo_root / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "runtime_gate.py").write_text(
                "from pathlib import Path\n"
                "fixture = Path('case.safe')\n"
                "text = fixture.read_text(encoding='utf-8')\n",
                encoding="utf-8",
            )
            report = glue_script_safety_report(
                repo_root=repo_root,
                audited_scripts=("scripts/runtime_gate.py",),
                report_scripts=(),
            )
            self.assertIn("scripts/runtime_gate.py:read_text", report["unauthorized_safe_source_readers"])

    def test_performance_scale_sanity_report_detects_missing_markers(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_scale_limits.md").write_text(
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text(
                "PR06.9.12\n",
                encoding="utf-8",
            )
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text(
                "PR06.9.12\n",
                encoding="utf-8",
            )

            report = performance_scale_sanity_report(repo_root=repo_root)
            self.assertIn(
                "docs/frontend_scale_limits.md:cliff-detection gate, not a benchmark commitment",
                report["doc_policy_violations"],
            )
            self.assertIn(
                "compiler_impl/README.md:docs/frontend_scale_limits.md",
                report["doc_policy_violations"],
            )
            self.assertIn(
                "release/frontend_runtime_decision.md:docs/frontend_scale_limits.md",
                report["doc_policy_violations"],
            )

    def test_check_performance_scale_sanity_accepts_valid_docs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_scale_limits.md").write_text(
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n"
                "cliff-detection gate, not a benchmark commitment\n"
                "raw timings are intentionally kept out of committed evidence\n"
                "Fixed-point Rule 5 work, general discriminants, channels/tasks/concurrency, and other unsupported surfaces are out of scope\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text(
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n"
                "docs/frontend_scale_limits.md\n"
                "cliff-detection gate, not a benchmark commitment\n",
                encoding="utf-8",
            )
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text(
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n"
                "docs/frontend_scale_limits.md\n"
                "PR08 starts from this cleaned PR07 baseline and must extend the live path rather than revive deleted legacy packages.\n",
                encoding="utf-8",
            )

            check_performance_scale_sanity(repo_root=repo_root)

    def test_documentation_architecture_clarity_report_detects_missing_baseline_doc(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            (repo_root / "README.md").write_text(
                "[Baseline](docs/frontend_architecture_baseline.md)\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text(
                "[Baseline](../docs/frontend_architecture_baseline.md)\n",
                encoding="utf-8",
            )
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text(
                "[Baseline](../docs/frontend_architecture_baseline.md)\n",
                encoding="utf-8",
            )
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_scale_limits.md").write_text(
                "[Baseline](frontend_architecture_baseline.md)\n",
                encoding="utf-8",
            )

            report = documentation_architecture_clarity_report(
                repo_root=repo_root,
                doc_requirements={
                    "README.md": [],
                    "compiler_impl/README.md": [],
                    "release/frontend_runtime_decision.md": [],
                    "docs/frontend_architecture_baseline.md": [],
                    "docs/frontend_scale_limits.md": [],
                },
                required_links={},
                stale_markers={},
            )
            self.assertIn("docs/frontend_architecture_baseline.md", report["missing_doc_files"])

    def test_documentation_architecture_clarity_report_detects_missing_markers_and_links(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_architecture_baseline.md").write_text(
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n",
                encoding="utf-8",
            )
            (docs_dir / "frontend_scale_limits.md").write_text(
                "frontend_architecture_baseline.md\n",
                encoding="utf-8",
            )
            (repo_root / "README.md").write_text(
                "[Baseline](docs/frontend_architecture_baseline.md)\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text(
                "No link here\n",
                encoding="utf-8",
            )
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text(
                "[Broken](../docs/missing.md)\n",
                encoding="utf-8",
            )

            report = documentation_architecture_clarity_report(
                repo_root=repo_root,
                doc_requirements={
                    "README.md": ["PR07 is the milestone that establishes this expanded baseline before PR08."],
                    "compiler_impl/README.md": ["PR08 must extend the live `Check_*` + `Mir_*` pipeline."],
                    "release/frontend_runtime_decision.md": ["Python is glue/orchestration only."],
                    "docs/frontend_architecture_baseline.md": ["PR08 must extend the live path rather than revive deleted legacy packages."],
                    "docs/frontend_scale_limits.md": [
                        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern"
                    ],
                },
                required_links={
                    "README.md": ["docs/frontend_architecture_baseline.md"],
                    "compiler_impl/README.md": ["../docs/frontend_architecture_baseline.md"],
                    "release/frontend_runtime_decision.md": ["../docs/frontend_architecture_baseline.md"],
                },
                stale_markers={},
            )
            self.assertIn(
                "README.md:PR07 is the milestone that establishes this expanded baseline before PR08.",
                report["doc_policy_violations"],
            )
            self.assertIn(
                "compiler_impl/README.md:../docs/frontend_architecture_baseline.md",
                report["missing_required_links"],
            )
            self.assertIn(
                "release/frontend_runtime_decision.md:../docs/missing.md",
                report["unresolved_local_links"],
            )

    def test_documentation_architecture_clarity_report_detects_stale_wording(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_architecture_baseline.md").write_text("ok\n", encoding="utf-8")
            (docs_dir / "frontend_scale_limits.md").write_text("ok\n", encoding="utf-8")
            (repo_root / "README.md").write_text(
                "PR00–PR06.9.1 sequential frontend landed\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text("ok\n", encoding="utf-8")
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text("ok\n", encoding="utf-8")

            report = documentation_architecture_clarity_report(
                repo_root=repo_root,
                doc_requirements={
                    "README.md": [],
                    "compiler_impl/README.md": [],
                    "release/frontend_runtime_decision.md": [],
                    "docs/frontend_architecture_baseline.md": [],
                    "docs/frontend_scale_limits.md": [],
                },
                required_links={},
                stale_markers={"README.md": ["PR00–PR06.9.1 sequential frontend landed"]},
            )
            self.assertEqual(
                report["stale_boundary_violations"],
                ["README.md:PR00–PR06.9.1 sequential frontend landed"],
            )

    def test_documentation_architecture_clarity_required_links_accept_anchors(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_architecture_baseline.md").write_text(
                "PR08 must extend the live path rather than revive deleted legacy packages.\n",
                encoding="utf-8",
            )
            (docs_dir / "frontend_scale_limits.md").write_text(
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n",
                encoding="utf-8",
            )
            (repo_root / "README.md").write_text(
                "[Baseline](docs/frontend_architecture_baseline.md#current-boundary)\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text(
                "[Baseline](../docs/frontend_architecture_baseline.md#current-boundary)\n",
                encoding="utf-8",
            )
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text(
                "[Baseline](../docs/frontend_architecture_baseline.md#current-boundary)\n",
                encoding="utf-8",
            )

            report = documentation_architecture_clarity_report(
                repo_root=repo_root,
                doc_requirements={
                    "README.md": [],
                    "compiler_impl/README.md": [],
                    "release/frontend_runtime_decision.md": [],
                    "docs/frontend_architecture_baseline.md": [],
                    "docs/frontend_scale_limits.md": [],
                },
                required_links={
                    "README.md": ["docs/frontend_architecture_baseline.md"],
                    "compiler_impl/README.md": ["../docs/frontend_architecture_baseline.md"],
                    "release/frontend_runtime_decision.md": ["../docs/frontend_architecture_baseline.md"],
                },
                stale_markers={},
            )
            self.assertEqual(report["missing_required_links"], [])

    def test_documentation_architecture_clarity_rejects_absolute_local_filesystem_links(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_architecture_baseline.md").write_text("ok\n", encoding="utf-8")
            (docs_dir / "frontend_scale_limits.md").write_text("ok\n", encoding="utf-8")
            absolute_target = repo_root / "docs" / "frontend_architecture_baseline.md"
            (repo_root / "README.md").write_text(
                f"[Baseline]({absolute_target})\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text("ok\n", encoding="utf-8")
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text("ok\n", encoding="utf-8")

            report = documentation_architecture_clarity_report(
                repo_root=repo_root,
                doc_requirements={
                    "README.md": [],
                    "compiler_impl/README.md": [],
                    "release/frontend_runtime_decision.md": [],
                    "docs/frontend_architecture_baseline.md": [],
                    "docs/frontend_scale_limits.md": [],
                },
                required_links={},
                stale_markers={},
            )
            self.assertEqual(
                report["unresolved_local_links"],
                [f"README.md:{absolute_target}"],
            )

    def test_check_documentation_architecture_clarity_accepts_valid_docs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            docs_dir = repo_root / "docs"
            docs_dir.mkdir()
            (docs_dir / "frontend_architecture_baseline.md").write_text(
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n"
                "Python is glue/orchestration only.\n"
                "No user-facing `safec` command depends on Python at runtime.\n"
                "`Check_*`\n"
                "`Mir_*`\n"
                "`Lexer`\n"
                "`Source`\n"
                "`Types`\n"
                "`Diagnostics`\n"
                "`Json`\n"
                "The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.\n"
                "PR08 must extend the live path rather than revive deleted legacy packages.\n"
                "`safec lex`\n`ast`\n`safec validate-mir`\n`safec analyze-mir`\n`safec check`\n`safec emit`\n",
                encoding="utf-8",
            )
            (docs_dir / "frontend_scale_limits.md").write_text(
                "[Baseline](frontend_architecture_baseline.md)\n"
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n",
                encoding="utf-8",
            )
            (repo_root / "README.md").write_text(
                "[Baseline](docs/frontend_architecture_baseline.md)\n"
                "[Scale](docs/frontend_scale_limits.md)\n"
                "[Compiler](compiler_impl/README.md)\n"
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n"
                "Ada-native `safec lex` / `ast` / `validate-mir` / `analyze-mir` / `check` / `emit`\n"
                "Python remains glue/orchestration only around the compiler.\n"
                "PR07 is the milestone that establishes this expanded baseline before PR08.\n",
                encoding="utf-8",
            )
            compiler_dir = repo_root / "compiler_impl"
            compiler_dir.mkdir()
            (compiler_dir / "README.md").write_text(
                "[Baseline](../docs/frontend_architecture_baseline.md)\n"
                "[Scale](../docs/frontend_scale_limits.md)\n"
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n"
                "All current user-facing `safec` commands are Ada-native for that supported surface.\n"
                "Python remains glue/orchestration only around the compiler.\n"
                "The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.\n"
                "PR08 must extend the live `Check_*` + `Mir_*` pipeline.\n",
                encoding="utf-8",
            )
            release_dir = repo_root / "release"
            release_dir.mkdir()
            (release_dir / "frontend_runtime_decision.md").write_text(
                "[Baseline](../docs/frontend_architecture_baseline.md)\n"
                "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern\n"
                "Ada-native runtime commands:\n"
                "Python is glue/orchestration only.\n"
                "The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.\n"
                "PR06.9.1 through PR06.9.13 established the hardened pre-PR07 baseline, and PR07 extends that same live path.\n"
                "PR08 starts from this cleaned PR07 baseline and must extend the live path rather than revive deleted legacy packages.\n",
                encoding="utf-8",
            )

            check_documentation_architecture_clarity(
                repo_root=repo_root,
                doc_requirements={
                    "README.md": [
                        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
                        "PR07 is the milestone that establishes this expanded baseline before PR08.",
                    ],
                    "compiler_impl/README.md": [
                        "PR08 must extend the live `Check_*` + `Mir_*` pipeline.",
                    ],
                    "release/frontend_runtime_decision.md": [
                        "PR06.9.1 through PR06.9.13 established the hardened pre-PR07 baseline, and PR07 extends that same live path.",
                    ],
                    "docs/frontend_architecture_baseline.md": [
                        "PR08 must extend the live path rather than revive deleted legacy packages.",
                    ],
                    "docs/frontend_scale_limits.md": [
                        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
                    ],
                },
                required_links={
                    "README.md": [
                        "docs/frontend_architecture_baseline.md",
                        "docs/frontend_scale_limits.md",
                        "compiler_impl/README.md",
                    ],
                    "compiler_impl/README.md": [
                        "../docs/frontend_architecture_baseline.md",
                        "../docs/frontend_scale_limits.md",
                    ],
                    "release/frontend_runtime_decision.md": [
                        "../docs/frontend_architecture_baseline.md",
                    ],
                    "docs/frontend_scale_limits.md": [
                        "frontend_architecture_baseline.md",
                    ],
                },
                stale_markers={
                    "README.md": ["PR00–PR06.9.1 sequential frontend landed"],
                },
            )

    def test_run_preflight_phase_checks_environment_without_evidence_files(self) -> None:
        tracker = {"tasks": []}
        with mock.patch("validate_execution_state.check_tracker_schema"), mock.patch(
            "validate_execution_state.check_status_rules"
        ), mock.patch("validate_execution_state.check_dependencies"), mock.patch(
            "validate_execution_state.check_frozen_sha",
            return_value="a" * 40,
        ), mock.patch("validate_execution_state.check_documented_sha"), mock.patch(
            "validate_execution_state.check_test_distribution"
        ), mock.patch(
            "validate_execution_state.check_environment_preconditions",
            return_value={"authority": "local"},
        ), mock.patch(
            "validate_execution_state.check_generated_output_cleanliness"
        ):
            report = run_preflight_phase(tracker=tracker, authority="local", env={})
        self.assertEqual(report["phase"], "preflight")
        self.assertEqual(report["policy_sha256"], EVIDENCE_POLICY_SHA256)
        self.assertEqual(report["preconditions"]["authority"], "local")

    def test_run_preflight_phase_rejects_dirty_generated_outputs(self) -> None:
        tracker = {"tasks": []}
        with mock.patch("validate_execution_state.check_tracker_schema"), mock.patch(
            "validate_execution_state.check_status_rules"
        ), mock.patch("validate_execution_state.check_dependencies"), mock.patch(
            "validate_execution_state.check_frozen_sha",
            return_value="a" * 40,
        ), mock.patch("validate_execution_state.check_documented_sha"), mock.patch(
            "validate_execution_state.check_test_distribution"
        ), mock.patch(
            "validate_execution_state.run",
            return_value={
                "command": ["git", "status"],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": " M execution/reports/pr10-emitted-baseline-report.json\n M execution/dashboard.md\n",
                "stderr": "",
            },
        ):
            with self.assertRaises(ValueError) as exc:
                run_preflight_phase(tracker=tracker, authority="local", env={})
        self.assertIn("ratchet-owned generated outputs must be clean before preflight", str(exc.exception))
        self.assertIn(" M execution/dashboard.md", str(exc.exception))
        self.assertIn(" M execution/reports/pr10-emitted-baseline-report.json", str(exc.exception))
        self.assertIn("accept ratchet artifact", str(exc.exception))
        self.assertIn("restore ratchet baseline", str(exc.exception))

    def test_run_preflight_phase_accepts_matching_generated_output_baseline(self) -> None:
        tracker = {"tasks": []}
        with tempfile.TemporaryDirectory() as temp_dir:
            baseline_file = Path(temp_dir) / "generated-output-baseline.txt"
            baseline_file.write_text(
                " M execution/dashboard.md\n M execution/reports/pr0699-build-reproducibility-report.json\n",
                encoding="utf-8",
            )
            with mock.patch("validate_execution_state.check_tracker_schema"), mock.patch(
                "validate_execution_state.check_status_rules"
            ), mock.patch("validate_execution_state.check_dependencies"), mock.patch(
                "validate_execution_state.check_frozen_sha",
                return_value="a" * 40,
            ), mock.patch("validate_execution_state.check_documented_sha"), mock.patch(
                "validate_execution_state.check_test_distribution"
            ), mock.patch(
                "validate_execution_state.check_environment_preconditions",
                return_value={"authority": "local"},
            ), mock.patch(
                "validate_execution_state.run",
                return_value={
                    "command": ["git", "status"],
                    "cwd": "$REPO_ROOT",
                    "returncode": 0,
                    "stdout": " M execution/reports/pr0699-build-reproducibility-report.json\n M execution/dashboard.md\n",
                    "stderr": "",
                },
            ):
                report = run_preflight_phase(
                    tracker=tracker,
                    authority="local",
                    env={},
                    generated_output_baseline_file=baseline_file,
                )
        self.assertEqual(report["phase"], "preflight")
        self.assertEqual(report["preconditions"]["authority"], "local")

    def test_run_preflight_phase_rejects_missing_generated_output_baseline_file(self) -> None:
        tracker = {"tasks": []}
        with tempfile.TemporaryDirectory() as temp_dir, mock.patch(
            "validate_execution_state.check_tracker_schema"
        ), mock.patch(
            "validate_execution_state.check_status_rules"
        ), mock.patch(
            "validate_execution_state.check_dependencies"
        ), mock.patch(
            "validate_execution_state.check_frozen_sha",
            return_value="a" * 40,
        ), mock.patch(
            "validate_execution_state.check_documented_sha"
        ), mock.patch(
            "validate_execution_state.check_test_distribution"
        ):
            baseline_file = Path(temp_dir) / "missing-generated-output-baseline.txt"
            with self.assertRaises(ValueError) as exc:
                run_preflight_phase(
                    tracker=tracker,
                    authority="local",
                    env={},
                    generated_output_baseline_file=baseline_file,
                )
        self.assertIn("--generated-output-baseline-file does not exist", str(exc.exception))

    def test_run_preflight_phase_rejects_mismatched_generated_output_baseline(self) -> None:
        tracker = {"tasks": []}
        with tempfile.TemporaryDirectory() as temp_dir:
            baseline_file = Path(temp_dir) / "generated-output-baseline.txt"
            baseline_file.write_text(
                " M execution/reports/pr0699-build-reproducibility-report.json\n",
                encoding="utf-8",
            )
            with mock.patch("validate_execution_state.check_tracker_schema"), mock.patch(
                "validate_execution_state.check_status_rules"
            ), mock.patch("validate_execution_state.check_dependencies"), mock.patch(
                "validate_execution_state.check_frozen_sha",
                return_value="a" * 40,
            ), mock.patch("validate_execution_state.check_documented_sha"), mock.patch(
                "validate_execution_state.check_test_distribution"
            ), mock.patch(
                "validate_execution_state.run",
                return_value={
                    "command": ["git", "status"],
                    "cwd": "$REPO_ROOT",
                    "returncode": 0,
                    "stdout": " M execution/reports/pr0699-build-reproducibility-report.json\n M execution/dashboard.md\n",
                    "stderr": "",
                },
            ):
                with self.assertRaises(ValueError) as exc:
                    run_preflight_phase(
                        tracker=tracker,
                        authority="local",
                        env={},
                        generated_output_baseline_file=baseline_file,
                    )
        self.assertIn("ratchet-owned generated outputs changed relative to the preflight baseline", str(exc.exception))
        self.assertIn(" M execution/dashboard.md", str(exc.exception))

    def test_main_rejects_generated_output_baseline_file_for_final_phase(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir, mock.patch.object(
            sys,
            "argv",
            [
                "validate_execution_state.py",
                "--phase",
                "final",
                "--generated-output-baseline-file",
                str(Path(temp_dir) / "generated-output-baseline.txt"),
            ],
        ), mock.patch(
            "validate_execution_state.ensure_deterministic_env",
            return_value={},
        ), mock.patch(
            "validate_execution_state.load_tracker",
            return_value={"tasks": []},
        ), mock.patch(
            "sys.stderr",
            new_callable=io.StringIO,
        ):
            with self.assertRaises(SystemExit) as exc:
                validate_execution_state.main()
        self.assertEqual(exc.exception.code, 2)

    def test_resolve_tool_command_prefers_pinned_alire_toolchain_binary(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            home = Path(temp_dir)
            pinned = home / ".local" / "share" / "alire" / "toolchains" / "gnat_native_15.2.1_deadbeef" / "bin" / "gnat"
            pinned.parent.mkdir(parents=True, exist_ok=True)
            pinned.write_text("", encoding="utf-8")
            with mock.patch("validate_execution_state.Path.home", return_value=home), mock.patch(
                "validate_execution_state.find_command",
                return_value="gnat",
            ):
                self.assertEqual(resolve_tool_command(authority="ci", name="gnat"), str(pinned))

    def test_run_final_phase_resolves_generated_root_and_embeds_policy_metadata(self) -> None:
        tracker = {"tasks": []}
        with tempfile.TemporaryDirectory() as temp_dir:
            generated_root = Path(temp_dir)
            with mock.patch(
                "validate_execution_state.check_frozen_sha",
                return_value="a" * 40,
            ), mock.patch("validate_execution_state.check_documented_sha"), mock.patch(
                "validate_execution_state.check_dashboard_freshness"
            ) as check_dashboard_freshness, mock.patch(
                "validate_execution_state.check_evidence_reproducibility"
            ) as check_evidence_reproducibility, mock.patch(
                "validate_execution_state.check_report_sync"
            ) as check_report_sync, mock.patch(
                "validate_execution_state.check_pr101_report_sync"
            ) as check_pr101_report_sync, mock.patch(
                "validate_execution_state.check_runtime_boundary"
            ), mock.patch(
                "validate_execution_state.check_environment_assumptions"
            ), mock.patch(
                "validate_execution_state.check_legacy_frontend_cleanup"
            ), mock.patch(
                "validate_execution_state.check_glue_script_safety"
            ), mock.patch(
                "validate_execution_state.check_performance_scale_sanity"
            ), mock.patch(
                "validate_execution_state.check_documentation_architecture_clarity"
            ), mock.patch(
                "validate_execution_state.check_policy_anchoring",
                return_value=[],
            ):
                report = run_final_phase(
                    tracker=tracker,
                    authority="ci",
                    env={},
                    generated_root=generated_root,
                )
        check_dashboard_freshness.assert_called_once_with(tracker, generated_root=generated_root)
        check_evidence_reproducibility.assert_called_once_with(
            tracker,
            generated_root=generated_root,
            ignored_evidence=("execution/reports/execution-state-validation-report.json",),
        )
        check_report_sync.assert_called_once_with(generated_root=generated_root)
        check_pr101_report_sync.assert_called_once_with(generated_root=generated_root)
        self.assertEqual(report["phase"], "final")
        self.assertNotIn("authority", report)
        self.assertIsNone(report["generated_root"])
        self.assertEqual(report["dashboard_path"], "execution/dashboard.md")
        self.assertEqual(report["policy_sha256"], EVIDENCE_POLICY_SHA256)
        self.assertIn("documentation_architecture", report["policy_sections_used"])

    def test_check_policy_anchoring_detects_mismatched_hash(self) -> None:
        from validate_execution_state import check_policy_anchoring

        with tempfile.TemporaryDirectory() as temp_dir:
            generated_root = Path(temp_dir)
            report_paths = [
                generated_root / "execution" / "reports" / "pr06910-portability-environment-report.json",
                generated_root / "execution" / "reports" / "pr06911-glue-script-safety-report.json",
                generated_root / "execution" / "reports" / "pr06913-documentation-architecture-clarity-report.json",
            ]
            for path in report_paths:
                self._write_finalized_report(
                    path,
                    {
                        "status": "ok",
                        "policy_sha256": EVIDENCE_POLICY_SHA256,
                        "policy_sections_used": ["environment"],
                    },
                )
            self._write_finalized_report(
                report_paths[1],
                {
                    "status": "ok",
                    "policy_sha256": "0" * 64,
                    "policy_sections_used": ["glue_safety"],
                },
            )

            violations = check_policy_anchoring(generated_root=generated_root)

        self.assertEqual(
            violations,
            ["execution/reports/pr06911-glue-script-safety-report.json:policy_sha256"],
        )


if __name__ == "__main__":
    unittest.main()
