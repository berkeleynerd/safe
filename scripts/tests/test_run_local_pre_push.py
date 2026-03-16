from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from run_local_pre_push import build_steps, gate_scripts_for_branch


class RunLocalPrePushTests(unittest.TestCase):
    def test_gate_scripts_for_branch_maps_known_pr083a_branch(self) -> None:
        self.assertEqual(
            gate_scripts_for_branch("codex/pr083a-public-constants"),
            (
                "scripts/run_pr083_interface_contracts.py",
                "scripts/run_pr083a_public_constants.py",
            ),
        )

    def test_gate_scripts_for_branch_maps_known_pr084_branch(self) -> None:
        self.assertEqual(
            gate_scripts_for_branch("codex/pr084-imported-summary-integration"),
            (
                "scripts/run_pr084_transitive_concurrency_integration.py",
                "scripts/run_pr08_frontend_baseline.py",
            ),
        )

    def test_gate_scripts_for_branch_rejects_unknown_pr08_branch(self) -> None:
        with self.assertRaises(RuntimeError):
            gate_scripts_for_branch("codex/pr083b-named-numbers")

    def test_build_steps_includes_rebuild_and_diff(self) -> None:
        steps = build_steps(
            branch="codex/pr083a-public-constants",
            python="python3",
            alr="alr",
            git="git",
            include_diff=True,
        )
        labels = [step.label for step in steps]
        self.assertEqual(labels[0], "Build compiler")
        self.assertIn("Run run_pr083_interface_contracts.py", labels)
        self.assertIn("Run run_pr083a_public_constants.py", labels)
        self.assertIn("Run run_pr0699_build_reproducibility.py", labels)
        self.assertIn("Rebuild compiler after reproducibility gate", labels)
        self.assertEqual(labels[-1], "Require clean tracked tree after local gates")

    def test_build_steps_include_pr084_and_pr08_baseline_gates(self) -> None:
        steps = build_steps(
            branch="codex/pr084-imported-summary-integration",
            python="python3",
            alr="alr",
            git="git",
            include_diff=False,
        )
        labels = [step.label for step in steps]
        self.assertIn("Run run_pr084_transitive_concurrency_integration.py", labels)
        self.assertIn("Run run_pr08_frontend_baseline.py", labels)

    def test_gate_scripts_for_branch_maps_known_pr09_branch(self) -> None:
        self.assertEqual(
            gate_scripts_for_branch("codex/pr09-ada-emission"),
            ("scripts/run_pr09_ada_emission_baseline.py",),
        )

    def test_build_steps_include_pr09_baseline_gate(self) -> None:
        steps = build_steps(
            branch="codex/pr09-ada-emission",
            python="python3",
            alr="alr",
            git="git",
            include_diff=False,
        )
        labels = [step.label for step in steps]
        self.assertIn("Run run_pr09_ada_emission_baseline.py", labels)

    def test_gate_scripts_for_branch_maps_known_pr103_branch(self) -> None:
        self.assertEqual(
            gate_scripts_for_branch("codex/pr103-ownership-proof-expansion"),
            (
                "scripts/run_pr103_sequential_proof_expansion.py",
                "scripts/run_pr10_emitted_baseline.py",
                "scripts/run_pr101_comprehensive_audit.py",
            ),
        )

    def test_gate_scripts_for_branch_maps_known_pr104_branch(self) -> None:
        self.assertEqual(
            gate_scripts_for_branch("codex/pr104-gnatprove-evidence-hardening"),
            (
                "scripts/run_pr104_gnatprove_evidence_parser_hardening.py",
                "scripts/run_pr101_comprehensive_audit.py",
            ),
        )

    def test_build_steps_skips_unmapped_non_pr08_branch(self) -> None:
        self.assertEqual(
            build_steps(
                branch="codex/misc-cleanup",
                python="python3",
                alr="alr",
                git="git",
                include_diff=True,
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
