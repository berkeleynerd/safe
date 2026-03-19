from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr114_signature_control_flow_syntax


class Pr114SignatureControlFlowSyntaxTests(unittest.TestCase):
    def test_fixture_lists_cover_expected_cutover_surface(self) -> None:
        positive_sources = {
            case["source"].name for case in run_pr114_signature_control_flow_syntax.positive_cases()
        }
        negative_sources = {
            case["source"].name for case in run_pr114_signature_control_flow_syntax.negative_cases()
        }

        self.assertEqual(
            positive_sources,
            {
                "emitter_surface_proc.safe",
                "pr112_string_param.safe",
                "rule4_conditional.safe",
                "rule2_slice.safe",
                "pr113_discriminant_constraints.safe",
            },
        )
        self.assertEqual(
            negative_sources,
            {
                "neg_pr114_legacy_procedure.safe",
                "neg_pr114_legacy_signature_return.safe",
                "neg_pr114_legacy_elsif.safe",
                "neg_pr114_legacy_range_dots.safe",
            },
        )

    def test_generate_report_includes_task_status_and_cutover_policy(self) -> None:
        with mock.patch.object(
            run_pr114_signature_control_flow_syntax,
            "safec_path",
            return_value=Path("/tmp/safec"),
        ), mock.patch.object(
            run_pr114_signature_control_flow_syntax,
            "run_positive_case",
            side_effect=[
                {"source": case["source"].name}
                for case in run_pr114_signature_control_flow_syntax.positive_cases()
            ],
        ), mock.patch.object(
            run_pr114_signature_control_flow_syntax,
            "run_negative_case",
            side_effect=[
                {"source": case["source"].name}
                for case in run_pr114_signature_control_flow_syntax.negative_cases()
            ],
        ):
            report = run_pr114_signature_control_flow_syntax.generate_report(env={})

        self.assertEqual(report["task"], "PR11.4")
        self.assertEqual(report["status"], "ok")
        self.assertFalse(report["cutover_policy"]["coexistence"])
        self.assertTrue(report["cutover_policy"]["full_quartet_scope"])
        self.assertEqual(
            len(report["positive_fixtures"]),
            len(run_pr114_signature_control_flow_syntax.positive_cases()),
        )
        self.assertEqual(
            len(report["negative_boundaries"]),
            len(run_pr114_signature_control_flow_syntax.negative_cases()),
        )

    def test_no_result_callable_case_checks_ast_shape(self) -> None:
        emitter_surface_proc = next(
            case
            for case in run_pr114_signature_control_flow_syntax.positive_cases()
            if case["source"].name == "emitter_surface_proc.safe"
        )
        self.assertEqual(
            tuple(emitter_surface_proc["ast_snippets"]),
            ('"node_type":"ProcedureSpecification"',),
        )
        self.assertEqual(
            tuple(emitter_surface_proc["ast_absent_snippets"]),
            ('"node_type":"FunctionSpecification"',),
        )


if __name__ == "__main__":
    unittest.main()
