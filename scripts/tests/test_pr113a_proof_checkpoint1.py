from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr113a_proof_checkpoint1


class Pr113aProofCheckpoint1Tests(unittest.TestCase):
    def test_corpus_lists_match_expected_checkpoint_surface(self) -> None:
        corpus = run_pr113a_proof_checkpoint1.sequential_proof_corpus()
        fixtures = [item["fixture"] for item in corpus]
        self.assertEqual(
            fixtures,
            [
                "tests/positive/pr112_character_case.safe",
                "tests/positive/pr112_discrete_case.safe",
                "tests/positive/pr112_string_param.safe",
                "tests/positive/pr112_case_scrutinee_once.safe",
                "tests/positive/pr113_discriminant_constraints.safe",
                "tests/positive/pr113_tuple_destructure.safe",
                "tests/positive/pr113_structured_result.safe",
                "tests/positive/pr113_variant_guard.safe",
                "tests/positive/constant_discriminant_default.safe",
                "tests/positive/result_equality_check.safe",
                "tests/positive/result_guarded_access.safe",
            ],
        )
        self.assertEqual(
            run_pr113a_proof_checkpoint1.excluded_positive_concurrency_paths(),
            ["tests/positive/pr113_tuple_channel.safe"],
        )
        by_fixture = {item["fixture"]: item for item in corpus}
        self.assertIn(
            "function Grade_Message(Grade : Character) return String with Global => null,",
            by_fixture["tests/positive/pr112_character_case.safe"]["spec_fragments"],
        )
        self.assertIn(
            "Depends => (Grade_Message'Result => Grade);",
            by_fixture["tests/positive/pr112_character_case.safe"]["spec_fragments"],
        )
        self.assertIn(
            "function Take(Item : Safe_constraint_Packet_Active_true_Kind_A_Count_2) return Safe_constraint_Packet_Active_true_Kind_A_Count_2 with Global => null,",
            by_fixture["tests/positive/pr113_discriminant_constraints.safe"]["spec_fragments"],
        )
        self.assertIn(
            "Depends => (Take'Result => Item);",
            by_fixture["tests/positive/pr113_discriminant_constraints.safe"]["spec_fragments"],
        )

    def test_generate_report_includes_task_status_and_corpus_contract(self) -> None:
        fixture_names = [
            item["fixture"]
            for item in run_pr113a_proof_checkpoint1.sequential_proof_corpus()
        ]
        with mock.patch.object(
            run_pr113a_proof_checkpoint1,
            "require_safec",
            return_value=Path("/tmp/safec"),
        ), mock.patch.object(
            run_pr113a_proof_checkpoint1,
            "run_fixture",
            side_effect=[{"fixture": name} for name in fixture_names],
        ):
            report = run_pr113a_proof_checkpoint1.generate_report(env={})

        self.assertEqual(report["task"], "PR11.3a")
        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["semantic_floor"]["fixture_count"], len(fixture_names))
        self.assertEqual(
            report["canonical_proof_detail"]["corpus_contract"]["fixtures"],
            fixture_names,
        )
        self.assertEqual(
            report["canonical_proof_detail"]["corpus_contract"]["excluded_positive_concurrency"],
            ["tests/positive/pr113_tuple_channel.safe"],
        )
        self.assertEqual(
            len(report["canonical_proof_detail"]["fixtures"]),
            len(fixture_names),
        )


if __name__ == "__main__":
    unittest.main()
