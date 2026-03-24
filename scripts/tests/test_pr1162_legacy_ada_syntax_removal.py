from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr1162_legacy_ada_syntax_removal


class Pr1162LegacyAdaSyntaxRemovalTests(unittest.TestCase):
    def test_fixture_lists_cover_expected_surface(self) -> None:
        positive_sources = {
            case["source"].name for case in run_pr1162_legacy_ada_syntax_removal.positive_cases()
        }
        negative_sources = {
            case["source"].name for case in run_pr1162_legacy_ada_syntax_removal.negative_cases()
        }
        migration_names = {
            case["name"] for case in run_pr1162_legacy_ada_syntax_removal.migration_examples()
        }

        self.assertEqual(
            positive_sources,
            {
                "constant_shadow_mutable.safe",
                "ownership_inout.safe",
                "constant_task_priority.safe",
                "ownership_early_return.safe",
                "rule4_linked_list.safe",
                "provider_transitive_channel.safe",
                "pr1162_empty_subprogram_body_followed_by_sibling.safe",
                "pr1162_empty_select_delay_arm.safe",
            },
        )
        self.assertEqual(
            negative_sources,
            {
                "neg_pr1162_removed_declare.safe",
                "neg_pr1162_removed_declare_expression.safe",
                "neg_pr1162_removed_null_statement.safe",
                "neg_pr1162_removed_named_exit.safe",
                "neg_pr1162_removed_goto.safe",
                "neg_pr1162_removed_aliased.safe",
                "neg_pr1162_removed_representation_clause.safe",
            },
        )
        self.assertEqual(
            migration_names,
            {
                "declare_tail_hoist",
                "null_statement_removal",
            },
        )

    def test_generate_report_includes_removal_policy(self) -> None:
        positive_side_effect = [
            {"source": case["source"].name}
            for case in run_pr1162_legacy_ada_syntax_removal.positive_cases()
        ]
        negative_side_effect = [
            {"source": case["source"].name}
            for case in run_pr1162_legacy_ada_syntax_removal.negative_cases()
        ]
        migration_side_effect = [
            {"name": case["name"]}
            for case in run_pr1162_legacy_ada_syntax_removal.migration_examples()
        ]

        with mock.patch.object(
            run_pr1162_legacy_ada_syntax_removal,
            "safec_path",
            return_value=Path("/tmp/safec"),
        ), mock.patch.object(
            run_pr1162_legacy_ada_syntax_removal,
            "run_positive_case",
            side_effect=positive_side_effect,
        ), mock.patch.object(
            run_pr1162_legacy_ada_syntax_removal,
            "run_negative_case",
            side_effect=negative_side_effect,
        ), mock.patch.object(
            run_pr1162_legacy_ada_syntax_removal,
            "run_migration_example",
            side_effect=migration_side_effect,
        ):
            report = run_pr1162_legacy_ada_syntax_removal.generate_report(env={})

        self.assertEqual(report["task"], "PR11.6.2")
        self.assertEqual(report["status"], "ok")
        self.assertIn("declare block", report["syntax_policy"]["removed_source_constructs"])
        self.assertIn("aliased", report["syntax_policy"]["removed_source_spellings"])
        self.assertTrue(report["syntax_policy"]["empty_suites_replace_null_statements"])
        self.assertTrue(report["syntax_policy"]["removed_words_remain_reserved"])
        self.assertEqual(
            len(report["positive_fixtures"]),
            len(run_pr1162_legacy_ada_syntax_removal.positive_cases()),
        )
        self.assertEqual(
            len(report["negative_boundaries"]),
            len(run_pr1162_legacy_ada_syntax_removal.negative_cases()),
        )
        self.assertEqual(
            len(report["migration_examples"]),
            len(run_pr1162_legacy_ada_syntax_removal.migration_examples()),
        )


if __name__ == "__main__":
    unittest.main()
