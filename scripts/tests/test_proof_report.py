from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_emitted_hardening_regressions
import run_pr102_rule5_boundary_closure
import run_pr104_gnatprove_evidence_parser_hardening
import run_pr10_emitted_prove
from _lib.proof_report import (
    command_profile,
    count_only_summary,
    split_proof_fixtures,
    summary_detail_map,
    validate_pr101_child_semantic_floor,
    validate_pr101_semantic_floor,
    validate_semantic_floor,
)


def sample_summary(
    *,
    total: int = 3,
    justified: int = 0,
    unproved: int = 0,
    detail_prefix: str = "detail",
) -> dict[str, object]:
    return {
        "rows": {
            "safe_sample.adb:7:1": {
                "proved": {"count": total, "detail": ""},
                "justified": {"count": justified, "detail": ""},
                "unproved": {"count": unproved, "detail": f"{detail_prefix}-row"},
                "total": {"count": total + justified + unproved, "detail": ""},
            }
        },
        "total": {
            "proved": {"count": total, "detail": ""},
            "justified": {"count": justified, "detail": ""},
            "unproved": {"count": unproved, "detail": f"{detail_prefix}-total"},
            "total": {"count": total + justified + unproved, "detail": ""},
        },
    }


def sample_result(command: list[str], *, stdout: str = "", stderr: str = "", returncode: int = 0) -> dict[str, object]:
    return {
        "command": command,
        "cwd": "$REPO_ROOT",
        "returncode": returncode,
        "stdout": stdout,
        "stderr": stderr,
    }


def sample_fixture(*, fixture: str = "tests/positive/sample.safe", family: str | None = None) -> dict[str, object]:
    payload: dict[str, object] = {
        "fixture": fixture,
        "compile": sample_result(
            ["alr", "exec", "--", "gprbuild", "-P", "build.gpr", "-c", "-gnatec=/tmp/out/gnat.adc"]
        ),
        "prove": {
            **sample_result(
                [
                    "alr",
                    "exec",
                    "--",
                    "gnatprove",
                    "-P",
                    "build.gpr",
                    "--mode=prove",
                    "--level=2",
                    "--prover=cvc5,z3,altergo",
                    "--steps=0",
                    "--timeout=120",
                    "--report=all",
                    "--warnings=error",
                    "--checks-as-errors=on",
                    "-gnatec=/tmp/out/gnat.adc",
                ],
                stdout="ok\n",
            ),
            "summary": sample_summary(),
        },
    }
    if family is not None:
        payload["family"] = family
    return payload


class ProofReportHelperTests(unittest.TestCase):
    def test_count_only_summary_drops_detail_strings(self) -> None:
        summary = sample_summary(detail_prefix="focus")
        self.assertEqual(
            count_only_summary(summary),
            {
                "rows": {
                    "safe_sample.adb:7:1": {
                        "proved": 3,
                        "justified": 0,
                        "unproved": 0,
                        "total": 3,
                    }
                },
                "total": {
                    "proved": 3,
                    "justified": 0,
                    "unproved": 0,
                    "total": 3,
                },
            },
        )

    def test_summary_detail_map_keeps_only_non_empty_details(self) -> None:
        self.assertEqual(
            summary_detail_map(sample_summary(detail_prefix="focus")),
            {
                "rows": {
                    "safe_sample.adb:7:1": {
                        "unproved": "focus-row",
                    }
                },
                "total": {
                    "unproved": "focus-total",
                },
            },
        )

    def test_command_profile_normalizes_gnatprove_invocation(self) -> None:
        profile = command_profile(
            [
                "alr",
                "exec",
                "--",
                "gnatprove",
                "-P",
                "/tmp/work/companion.gpr",
                "--mode=prove",
                "--level=2",
                "--prover=cvc5,z3,altergo",
                "--steps=0",
                "--timeout=120",
                "--report=all",
                "--warnings=error",
                "--checks-as-errors=on",
                "-gnatec=/tmp/out/gnat.adc",
                "/tmp/out/safe_sample.adb",
            ]
        )
        self.assertEqual(profile["program"], "alr")
        self.assertEqual(profile["tool"], "gnatprove")
        self.assertEqual(profile["project"], "companion.gpr")
        self.assertEqual(profile["mode"], "prove")
        self.assertEqual(profile["provers"], ["cvc5", "z3", "altergo"])
        self.assertEqual(profile["timeout"], "120")
        self.assertTrue(profile["explicit_gnatec"])
        self.assertEqual(profile["extra_args"], ["safe_sample.adb"])

    def test_split_proof_fixtures_builds_semantic_floor_and_machine_sensitive(self) -> None:
        semantic_floor, canonical, machine = split_proof_fixtures(
            [
                {
                    **sample_fixture(family="proof"),
                    "structural_assertions": {"safe_sample.adb": ["return Value;"]},
                }
            ]
        )
        self.assertEqual(semantic_floor["fixture_count"], 1)
        self.assertEqual(
            semantic_floor["fixtures"][0],
            {
                "fixture": "tests/positive/sample.safe",
                "family": "proof",
                "compile_returncode": 0,
                "prove_returncode": 0,
                "prove_justified": 0,
                "prove_unproved": 0,
                "prove_total_checks": 3,
            },
        )
        self.assertEqual(canonical[0]["prove"]["summary"]["total"]["total"], 3)
        self.assertEqual(machine[0]["prove"]["summary"]["total"]["unproved"], "detail-total")
        self.assertIn("structural_assertions", canonical[0])

    def test_validate_semantic_floor_rejects_nonzero_unproved(self) -> None:
        payload = {
            "semantic_floor": {
                "fixture_count": 1,
                "fixtures": [
                    {
                        "fixture": "tests/positive/sample.safe",
                        "compile_returncode": 0,
                        "prove_returncode": 0,
                        "prove_justified": 0,
                        "prove_unproved": 1,
                        "prove_total_checks": 3,
                    }
                ],
            },
            "canonical_proof_detail": {},
            "machine_sensitive": {},
        }
        with self.assertRaises(RuntimeError) as exc:
            validate_semantic_floor(payload)
        self.assertIn("prove_unproved must be zero", str(exc.exception))

    def test_validate_pr101_semantic_floor_checks_hashes(self) -> None:
        payload = {
            "semantic_floor": {
                "baseline_gate_hashes": {
                    "pr08_frontend_baseline": "1" * 64,
                    "pr09_ada_emission_baseline": "2" * 64,
                    "pr10_emitted_baseline": "3" * 64,
                    "emitted_hardening_regressions": "4" * 64,
                },
                "child_report_hashes": {
                    "pr101a_companion_proof_verification": "5" * 64,
                    "pr101b_template_proof_verification": "6" * 64,
                },
            },
            "canonical_proof_detail": {},
            "machine_sensitive": {},
        }
        pipeline_context = {
            "pr08_frontend_baseline": {"report": {"report_sha256": "1" * 64}},
            "pr09_ada_emission_baseline": {"report": {"report_sha256": "2" * 64}},
            "pr10_emitted_baseline": {"report": {"report_sha256": "3" * 64}},
            "emitted_hardening_regressions": {"report": {"report_sha256": "4" * 64}},
            "pr101a_companion_proof_verification": {"report": {"report_sha256": "5" * 64}},
            "pr101b_template_proof_verification": {"report": {"report_sha256": "6" * 64}},
        }
        validate_pr101_semantic_floor(payload, pipeline_context=pipeline_context)

    def test_validate_pr101_child_semantic_floor_checks_anchor_hashes(self) -> None:
        payload = {
            "semantic_floor": {
                "build_returncode": 0,
                "flow_returncode": 0,
                "prove_returncode": 0,
                "extract_assumptions_returncode": 0,
                "diff_assumptions_returncode": 0,
                "assumptions_extracted_sha256": "1" * 64,
                "prove_golden_sha256": "2" * 64,
                "gnatprove_summary_sha256": "3" * 64,
            },
            "canonical_proof_detail": {},
            "machine_sensitive": {},
        }
        validate_pr101_child_semantic_floor(payload)


class ProofReportGateShapeTests(unittest.TestCase):
    def test_pr10_emitted_prove_generate_report_uses_three_way_shape(self) -> None:
        with mock.patch.object(run_pr10_emitted_prove, "corpus_paths", return_value=[Path("tests/positive/sample.safe")]), mock.patch.object(
            run_pr10_emitted_prove,
            "compile_and_prove_fixture",
            return_value=sample_fixture(),
        ):
            report = run_pr10_emitted_prove.generate_report(env={})
        self.assertEqual(report["semantic_floor"]["fixture_count"], 1)
        self.assertIn("fixtures", report["canonical_proof_detail"])
        self.assertIn("fixtures", report["machine_sensitive"])
        self.assertEqual(report["semantic_floor"]["fixtures"][0]["prove_total_checks"], 3)

    def test_pr102_generate_report_keeps_negative_diagnostics_out_of_semantic_floor(self) -> None:
        with mock.patch.object(run_pr102_rule5_boundary_closure, "require_repo_command", return_value=Path("/tmp/safec")), mock.patch.object(
            run_pr102_rule5_boundary_closure,
            "run_positive_fixture",
            return_value={
                **sample_fixture(),
                "flow": {
                    **sample_result(
                        [
                            "alr",
                            "exec",
                            "--",
                            "gnatprove",
                            "-P",
                            "build.gpr",
                            "--mode=flow",
                            "--report=all",
                        ]
                    ),
                    "summary": sample_summary(),
                },
            },
        ), mock.patch.object(
            run_pr102_rule5_boundary_closure,
            "run_negative_fixture",
            return_value={
                "fixture": "tests/negative/sample.safe",
                "golden": "tests/diagnostics_golden/sample.txt",
                "expected_reason": "source_frontend_error",
                "diagnostic": {"reason": "source_frontend_error"},
                "check_diag_json": sample_result(["/tmp/safec", "check", "--diag-json", "tests/negative/sample.safe"], returncode=1),
                "check_human": sample_result(["/tmp/safec", "check", "tests/negative/sample.safe"], returncode=1),
            },
        ), mock.patch.object(
            run_pr102_rule5_boundary_closure,
            "run_parity_fixture",
            return_value={
                "fixture": "compiler_impl/tests/mir_analysis/sample.safe",
                "diagnostic": {"reason": "fp_unsupported_expression_at_narrowing"},
                "analyze_mir": sample_result(["/tmp/safec", "analyze-mir", "--diag-json", "sample"], returncode=1),
            },
        ), mock.patch.object(
            run_pr102_rule5_boundary_closure,
            "verify_corpus_contract",
            return_value={"rule5_positives": ["tests/positive/sample.safe"]},
        ):
            report = run_pr102_rule5_boundary_closure.generate_report(env={})
        self.assertEqual(report["semantic_floor"]["fixture_count"], len(run_pr102_rule5_boundary_closure.EXPECTED_RULE5_POSITIVES))
        self.assertIn("negative_diagnostics", report["canonical_proof_detail"])
        self.assertIn("mir_parity", report["canonical_proof_detail"])
        self.assertNotIn("negative_diagnostics", report["semantic_floor"])

    def test_pr104_generate_report_keeps_parser_regressions_in_canonical_detail(self) -> None:
        flow_fixture = {
            "fixture": "tests/concurrency/select_with_delay_multiarm.safe",
            "compile": sample_result(["alr", "exec", "--", "gprbuild", "-P", "build.gpr"]),
            "flow": {
                **sample_result(["alr", "exec", "--", "gnatprove", "-P", "build.gpr", "--mode=flow"]),
                "summary": sample_summary(),
            },
            "prove": {
                **sample_result(["alr", "exec", "--", "gnatprove", "-P", "build.gpr", "--mode=prove"]),
                "summary": sample_summary(),
            },
            "prove_profile": {
                "shared_switches": ["--mode=prove"],
                "actual_command": [
                    "alr",
                    "exec",
                    "--",
                    "gnatprove",
                    "-P",
                    "build.gpr",
                    "--mode=prove",
                ],
            },
        }
        with mock.patch.object(
            run_pr104_gnatprove_evidence_parser_hardening,
            "verify_parser_tests",
            return_value=sample_result(["python3", "-m", "unittest", "scripts.tests.test_pr101_audit_hardening"], stdout="ok\n"),
        ), mock.patch.object(
            run_pr104_gnatprove_evidence_parser_hardening,
            "verify_concurrency_evidence",
            return_value=flow_fixture,
        ), mock.patch.object(
            run_pr104_gnatprove_evidence_parser_hardening,
            "verify_proof_profile_doc",
            return_value={"path": "docs/gnatprove_profile.md"},
        ), mock.patch.object(
            run_pr104_gnatprove_evidence_parser_hardening,
            "verify_decascaded_reports",
            return_value={"committed_report_contracts": {}},
        ):
            report = run_pr104_gnatprove_evidence_parser_hardening.generate_report(python="python3", env={})
        self.assertEqual(report["semantic_floor"]["fixture_count"], 1)
        self.assertIn("parser_regressions", report["canonical_proof_detail"])
        self.assertIn("gnatprove_profile_doc", report["canonical_proof_detail"])
        self.assertIn("de_cascaded_reports", report["canonical_proof_detail"])
        self.assertIn("parser_regressions", report["machine_sensitive"])

    def test_emitted_hardening_semantic_floor_excludes_rejected_access_channel_fixtures(self) -> None:
        with mock.patch.object(run_emitted_hardening_regressions, "require_safec", return_value=Path("/tmp/safec")), mock.patch.object(
            run_emitted_hardening_regressions,
            "ownership_early_return_regression",
            return_value={
                "fixture": "tests/positive/ownership_early_return.safe",
                "compile": sample_result(["alr", "exec", "--", "gprbuild", "-P", "build.gpr"]),
                "structural_assertions": {"safe_sample.adb": ["return Value;"]},
            },
        ), mock.patch.object(
            run_emitted_hardening_regressions,
            "supplemental_proof_fixture",
            return_value={
                **sample_fixture(fixture="tests/concurrency/select_with_delay_multiarm.safe"),
                "flow": {
                    **sample_result(["alr", "exec", "--", "gnatprove", "-P", "build.gpr", "--mode=flow"]),
                    "summary": sample_summary(),
                },
                "structural_assertions": {"safe_sample.adb": ["Try_Receive ("]},
            },
        ), mock.patch.object(
            run_emitted_hardening_regressions,
            "rejected_channel_fixture",
            return_value={
                "fixture": "tests/concurrency/channel_access_type.safe",
                "check": sample_result(["/tmp/safec", "check", "--diag-json", "tests/concurrency/channel_access_type.safe"], returncode=1),
                "emit": sample_result(["/tmp/safec", "emit", "tests/concurrency/channel_access_type.safe"], returncode=1),
                "first_diagnostic": {"reason": "source_frontend_error"},
            },
        ):
            report = run_emitted_hardening_regressions.generate_report(env={})
        self.assertEqual(report["semantic_floor"]["fixture_count"], len(run_emitted_hardening_regressions.PROOF_FIXTURES))
        self.assertEqual(
            [fixture["fixture"] for fixture in report["semantic_floor"]["fixtures"]],
            ["tests/concurrency/select_with_delay_multiarm.safe"],
        )
        self.assertIn("rejected_access_channel_fixtures", report["canonical_proof_detail"])
        self.assertNotIn("rejected_access_channel_fixtures", report["semantic_floor"])


if __name__ == "__main__":
    unittest.main()
