from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from validate_execution_state import (
    check_dependencies,
    check_environment_assumptions,
    check_evidence_reproducibility,
    check_glue_script_safety,
    check_status_rules,
    check_test_distribution,
    count_test_files,
    environment_assumptions_report,
    evidence_reproducibility_report,
    glue_script_safety_report,
    legacy_frontend_cleanup_report,
    runtime_boundary_report,
)


class ValidateExecutionStateTests(unittest.TestCase):
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
                "Ubuntu/Linux CI and local macOS\nWindows is explicitly unsupported\n",
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
                doc_requirements={"docs/policy.md": ["Ubuntu/Linux CI and local macOS", "Windows is explicitly unsupported"]},
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
                        "Ubuntu/Linux CI and local macOS",
                        "Windows is explicitly unsupported",
                        "PATH-based command discovery",
                        "deterministic TemporaryDirectory prefixes",
                        "shell-free",
                    ]
                },
                runtime_source_globs=(),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )
            self.assertIn(
                "docs/policy.md:Ubuntu/Linux CI and local macOS",
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
                "Ubuntu/Linux CI and local macOS\n"
                "Windows is explicitly unsupported\n"
                "PATH-based command discovery\n"
                "deterministic TemporaryDirectory prefixes\n"
                "shell-free\n",
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
                        "Ubuntu/Linux CI and local macOS",
                        "Windows is explicitly unsupported",
                        "PATH-based command discovery",
                        "deterministic TemporaryDirectory prefixes",
                        "shell-free",
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
                "Ubuntu/Linux CI and local macOS\n"
                "Windows is explicitly unsupported\n"
                "PATH-based command discovery\n"
                "deterministic TemporaryDirectory prefixes\n"
                "shell-free\n"
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
                        "Ubuntu/Linux CI and local macOS",
                        "Windows is explicitly unsupported",
                        "PATH-based command discovery",
                        "deterministic TemporaryDirectory prefixes",
                        "shell-free",
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
                        "Ubuntu/Linux CI and local macOS",
                        "Windows is explicitly unsupported",
                        "PATH-based command discovery",
                        "deterministic TemporaryDirectory prefixes",
                        "shell-free",
                    ]
                },
                runtime_source_globs=("compiler_impl/src/*.adb",),
                module_requirements={"scripts/runtime_gate.py": ["MASKED_PYTHON_INTERPRETERS"]},
                tempdir_scripts=("scripts/runtime_gate.py",),
                path_lookup_scripts=("scripts/runtime_gate.py",),
            )

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


if __name__ == "__main__":
    unittest.main()
