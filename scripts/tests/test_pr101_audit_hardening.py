from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr08_frontend_baseline
import run_pr09_ada_emission_baseline
import run_pr10_emitted_baseline
import run_pr101_comprehensive_audit


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
