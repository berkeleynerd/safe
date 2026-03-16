from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr08_frontend_baseline
import run_pr09_ada_emission_baseline
import run_pr10_emitted_baseline
import run_pr101_comprehensive_audit


class Pr101AuditHardeningTests(unittest.TestCase):
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
                run_pr101_comprehensive_audit.normalized_gnatprove_summary_hash(first_path),
                run_pr101_comprehensive_audit.normalized_gnatprove_summary_hash(second_path),
            )

    def test_normalized_gnatprove_summary_hash_requires_summary_block(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "missing.out"
            output_path.write_text("no summary here\n", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                run_pr101_comprehensive_audit.normalized_gnatprove_summary_hash(output_path)


if __name__ == "__main__":
    unittest.main()
