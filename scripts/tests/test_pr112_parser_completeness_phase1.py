from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr112_parser_completeness_phase1


class Pr112ParserCompletenessPhase1Tests(unittest.TestCase):
    def test_fixture_lists_cover_follow_up_cases(self) -> None:
        positive_sources = {
            case["source"].name for case in run_pr112_parser_completeness_phase1.POSITIVE_CASES
        }
        negative_sources = {
            case["source"].name for case in run_pr112_parser_completeness_phase1.NEGATIVE_CASES
        }

        self.assertIn("pr112_string_param.safe", positive_sources)
        self.assertIn("neg_string_initializer_type.safe", negative_sources)
        self.assertIn("neg_string_index.safe", negative_sources)
        self.assertIn("neg_string_attribute.safe", negative_sources)
        self.assertIn("neg_string_array_component.safe", negative_sources)
        self.assertIn("neg_case_string_choice.safe", negative_sources)
        self.assertIn("neg_string_return_type.safe", negative_sources)
        self.assertIn("neg_character_return_type.safe", negative_sources)

    def test_generate_report_includes_task_and_status_envelope(self) -> None:
        positive_side_effect = [
            {"source": case["source"].name}
            for case in run_pr112_parser_completeness_phase1.POSITIVE_CASES
        ] + [
            {"source": source.name}
            for source in run_pr112_parser_completeness_phase1.ROSETTA_TEXT_SAMPLES
        ]
        negative_side_effect = [
            {"source": case["source"].name}
            for case in run_pr112_parser_completeness_phase1.NEGATIVE_CASES
        ]

        with mock.patch.object(
            run_pr112_parser_completeness_phase1,
            "safec_path",
            return_value=Path("/tmp/safec"),
        ), mock.patch.object(
            run_pr112_parser_completeness_phase1,
            "run_positive_case",
            side_effect=positive_side_effect,
        ), mock.patch.object(
            run_pr112_parser_completeness_phase1,
            "run_negative_case",
            side_effect=negative_side_effect,
        ):
            report = run_pr112_parser_completeness_phase1.generate_report(env={})

        self.assertEqual(report["task"], "PR11.2")
        self.assertEqual(report["status"], "ok")
        self.assertEqual(
            len(report["positive_fixtures"]),
            len(run_pr112_parser_completeness_phase1.POSITIVE_CASES),
        )
        self.assertEqual(
            len(report["negative_boundaries"]),
            len(run_pr112_parser_completeness_phase1.NEGATIVE_CASES),
        )


if __name__ == "__main__":
    unittest.main()
