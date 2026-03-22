from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPTS_DIR.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr0697_gate_quality


class Pr0697GateQualityTests(unittest.TestCase):
    def test_expected_test_modules_cover_all_repo_test_modules(self) -> None:
        discovered = tuple(
            sorted(f"scripts.tests.{path.stem}" for path in (REPO_ROOT / "scripts" / "tests").glob("test_*.py"))
        )
        self.assertEqual(run_pr0697_gate_quality.EXPECTED_TEST_MODULES, discovered)

    def test_normalize_unittest_output_freezes_successful_suite_summary(self) -> None:
        observed = (
            "." * 157
            + "\n----------------------------------------------------------------------\n"
            + "Ran 157 tests in 3.225s\n\nOK\n"
        )
        self.assertEqual(
            run_pr0697_gate_quality.normalize_unittest_output(observed),
            run_pr0697_gate_quality.canonical_unittest_success_output(count=157),
        )

    def test_normalize_unittest_output_accepts_singular_test_summary(self) -> None:
        observed = ".\n----------------------------------------------------------------------\nRan 1 test in 0.002s\n\nOK\n"
        self.assertEqual(
            run_pr0697_gate_quality.normalize_unittest_output(observed),
            run_pr0697_gate_quality.canonical_unittest_success_output(count=1),
        )

    def test_normalize_unittest_output_preserves_non_success_detail(self) -> None:
        observed = "FAILED (errors=1)\nRan 157 tests in 3.225s\n"
        self.assertEqual(
            run_pr0697_gate_quality.normalize_unittest_output(observed),
            "FAILED (errors=1)\nRan 157 tests in <elapsed>\n",
        )

    def test_run_unittest_suite_uses_explicit_manifest_and_records_metadata(self) -> None:
        command_result = {
            "command": ["python3", "-m", "unittest", *run_pr0697_gate_quality.EXPECTED_TEST_MODULES],
            "cwd": "$REPO_ROOT",
            "returncode": 0,
            "stdout": "",
            "stderr": (
                "." * 22
                + "\n----------------------------------------------------------------------\n"
                + "Ran 22 tests in 0.123s\n\nOK\n"
            ),
        }
        with mock.patch.object(run_pr0697_gate_quality, "run", return_value=command_result) as run_mock:
            result = run_pr0697_gate_quality.run_unittest_suite("python3")

        run_mock.assert_called_once_with(
            ["python3", "-m", "unittest", *run_pr0697_gate_quality.EXPECTED_TEST_MODULES],
            cwd=run_pr0697_gate_quality.REPO_ROOT,
        )
        self.assertEqual(result["modules"], list(run_pr0697_gate_quality.EXPECTED_TEST_MODULES))
        self.assertEqual(result["observed_count"], 22)
        self.assertEqual(
            result["stderr"],
            run_pr0697_gate_quality.canonical_unittest_success_output(count=22),
        )

    def test_extract_observed_test_count_reads_normalized_output(self) -> None:
        observed_count = run_pr0697_gate_quality.extract_observed_test_count(
            stdout="",
            stderr="Ran 242 tests in <elapsed>\n",
        )
        self.assertEqual(observed_count, 242)

    def test_extract_observed_test_count_reads_singular_test_output(self) -> None:
        observed_count = run_pr0697_gate_quality.extract_observed_test_count(
            stdout="Ran 1 test in <elapsed>\n",
            stderr="",
        )
        self.assertEqual(observed_count, 1)


if __name__ == "__main__":
    unittest.main()
