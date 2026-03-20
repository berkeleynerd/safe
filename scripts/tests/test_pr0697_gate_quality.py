from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr0697_gate_quality


class Pr0697GateQualityTests(unittest.TestCase):
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

    def test_normalize_unittest_output_preserves_non_success_detail(self) -> None:
        observed = "FAILED (errors=1)\nRan 157 tests in 3.225s\n"
        self.assertEqual(
            run_pr0697_gate_quality.normalize_unittest_output(observed),
            "FAILED (errors=1)\nRan 157 tests in <elapsed>\n",
        )


if __name__ == "__main__":
    unittest.main()
