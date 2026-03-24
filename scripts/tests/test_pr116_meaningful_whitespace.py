from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr116_meaningful_whitespace


class Pr116MeaningfulWhitespaceTests(unittest.TestCase):
    def test_fixture_lists_cover_expected_surface(self) -> None:
        positive_sources = {
            case["source"].name for case in run_pr116_meaningful_whitespace.positive_cases()
        }
        negative_sources = {
            case["source"].name for case in run_pr116_meaningful_whitespace.negative_cases()
        }
        rosetta_sources = {
            case["source"].name for case in run_pr116_meaningful_whitespace.rosetta_readability_cases()
        }
        migration_names = {
            case["name"] for case in run_pr116_meaningful_whitespace.migration_examples()
        }

        self.assertEqual(
            positive_sources,
            {
                "pr116_bare_return.safe",
                "pr115_compound_terminators.safe",
                "rule2_binary_search.safe",
                "pr112_character_case.safe",
                "pr113_variant_guard.safe",
                "select_with_delay.safe",
            },
        )
        self.assertEqual(
            negative_sources,
            {
                "neg_pr116_tab_indent.safe",
                "neg_pr116_bad_indent_step.safe",
                "neg_pr116_legacy_end_if.safe",
                "neg_pr116_legacy_begin.safe",
                "neg_pr116_declare_missing_begin.safe",
                "neg_pr116_mixed_named_end.safe",
            },
        )
        self.assertEqual(
            rosetta_sources,
            {
                "collatz_bounded.safe",
                "bounded_stack.safe",
                "producer_consumer.safe",
            },
        )
        self.assertEqual(
            migration_names,
            {
                "control_flow_cutover",
                "case_and_select_cutover",
            },
        )

    def test_generate_report_includes_cutover_policy(self) -> None:
        positive_side_effect = [
            {"source": case["source"].name}
            for case in run_pr116_meaningful_whitespace.positive_cases()
        ] + [
            {"source": case["source"].name}
            for case in run_pr116_meaningful_whitespace.rosetta_readability_cases()
        ]
        negative_side_effect = [
            {"source": case["source"].name}
            for case in run_pr116_meaningful_whitespace.negative_cases()
        ]
        migration_side_effect = [
            {"name": case["name"]}
            for case in run_pr116_meaningful_whitespace.migration_examples()
        ]

        with mock.patch.object(
            run_pr116_meaningful_whitespace,
            "safec_path",
            return_value=Path("/tmp/safec"),
        ), mock.patch.object(
            run_pr116_meaningful_whitespace,
            "run_positive_case",
            side_effect=positive_side_effect,
        ), mock.patch.object(
            run_pr116_meaningful_whitespace,
            "run_negative_case",
            side_effect=negative_side_effect,
        ), mock.patch.object(
            run_pr116_meaningful_whitespace,
            "run_migration_example",
            side_effect=migration_side_effect,
        ):
            report = run_pr116_meaningful_whitespace.generate_report(env={})

        self.assertEqual(report["task"], "PR11.6")
        self.assertEqual(report["status"], "ok")
        self.assertTrue(report["syntax_policy"]["meaningful_whitespace_shipped"])
        self.assertTrue(report["syntax_policy"]["pragma_strict_deferred_post_1_0"])
        self.assertTrue(report["syntax_policy"]["lexer_token_stream_changed"])
        self.assertEqual(report["syntax_policy"]["indentation_style"], "spaces_only")
        self.assertEqual(report["syntax_policy"]["indentation_step"], 3)
        self.assertTrue(report["syntax_policy"]["declare_blocks_remain_explicit"])
        self.assertEqual(
            len(report["positive_fixtures"]),
            len(run_pr116_meaningful_whitespace.positive_cases()),
        )
        self.assertEqual(
            len(report["negative_boundaries"]),
            len(run_pr116_meaningful_whitespace.negative_cases()),
        )
        self.assertEqual(
            len(report["rosetta_readability_samples"]),
            len(run_pr116_meaningful_whitespace.rosetta_readability_cases()),
        )
        self.assertEqual(
            len(report["migration_examples"]),
            len(run_pr116_meaningful_whitespace.migration_examples()),
        )


if __name__ == "__main__":
    unittest.main()
