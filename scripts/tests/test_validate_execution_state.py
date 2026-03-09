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
    check_status_rules,
    check_test_distribution,
    count_test_files,
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


if __name__ == "__main__":
    unittest.main()
