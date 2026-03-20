from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_gate_pipeline
from _lib.gate_manifest import DeterminismClass, Node, NodeKind


class RunGatePipelineTests(unittest.TestCase):
    @staticmethod
    def _report_payload(status: str) -> dict[str, object]:
        return {
            "status": status,
            "deterministic": True,
            "report_sha256": "1" * 64,
            "repeat_sha256": "1" * 64,
        }

    @staticmethod
    def _proof_payload(
        *,
        fixture_name: str = "tests/positive/sample.safe",
        compile_returncode: int = 0,
        prove_returncode: int = 0,
        prove_justified: int = 0,
        prove_unproved: int = 0,
    ) -> dict[str, object]:
        return {
            "semantic_floor": {
                "fixture_count": 1,
                "fixtures": [
                    {
                        "fixture": fixture_name,
                        "compile_returncode": compile_returncode,
                        "prove_returncode": prove_returncode,
                        "prove_justified": prove_justified,
                        "prove_unproved": prove_unproved,
                        "prove_total_checks": 3,
                    }
                ],
            },
            "canonical_proof_detail": {"fixtures": []},
            "machine_sensitive": {"fixtures": []},
            "deterministic": True,
            "report_sha256": "1" * 64,
            "repeat_sha256": "1" * 64,
        }

    @staticmethod
    def _pr101_payload(*, baseline_gate_hashes: dict[str, str]) -> dict[str, object]:
        return {
            "task": "PR10.1",
            "semantic_floor": {
                "baseline_gate_hashes": baseline_gate_hashes,
                "child_report_hashes": {
                    "pr101a_companion_proof_verification": "5" * 64,
                    "pr101b_template_proof_verification": "6" * 64,
                },
            },
            "canonical_proof_detail": {},
            "machine_sensitive": {},
            "deterministic": True,
            "report_sha256": "b" * 64,
            "repeat_sha256": "b" * 64,
        }

    @staticmethod
    def _pr101_child_payload(*, report_sha: str = "5" * 64) -> dict[str, object]:
        return {
            "task": "PR10.1",
            "verification": "companion",
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
            "deterministic": True,
            "report_sha256": report_sha,
            "repeat_sha256": report_sha,
        }

    @classmethod
    def _write_report(cls, path: Path, payload: dict[str, object]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def test_plan_prints_node_order(self) -> None:
        nodes = (
            Node(id="build_initial", kind=NodeKind.BUILD),
            Node(
                id="sample_gate",
                kind=NodeKind.GATE,
                script=Path("/tmp/sample.py"),
                report_path=Path("/tmp/sample.json"),
            ),
        )
        with mock.patch.object(run_gate_pipeline, "resolve_branch", return_value=list(nodes)):
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                self.assertEqual(run_gate_pipeline.print_plan("codex/pr114-signature-control-flow-syntax"), 0)
        text = stdout.getvalue()
        self.assertIn("[gate-pipeline] branch: codex/pr114-signature-control-flow-syntax", text)
        self.assertIn("[gate-pipeline] 1. build_initial [build] build build_initial", text)
        self.assertIn("[gate-pipeline] 2. sample_gate [gate]", text)

    def test_tracked_diff_snapshot_sorts_status_lines(self) -> None:
        with mock.patch.object(
            run_gate_pipeline,
            "run",
            return_value={
                "command": ["git", "status", "--porcelain", "--untracked-files=no"],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": " M scripts/z.py\n D docs/a.md\n M scripts/a.py\n",
                "stderr": "",
            },
        ):
            self.assertEqual(
                run_gate_pipeline.tracked_diff_snapshot(git="git", env={}),
                " D docs/a.md\n M scripts/a.py\n M scripts/z.py\n",
            )

    def test_verify_fails_on_mismatched_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            self._write_report(expected_path, self._report_payload("expected"))
            node = Node(
                id="sample_gate",
                kind=NodeKind.GATE,
                script=Path("/tmp/sample.py"),
                report_path=expected_path,
                determinism_class=DeterminismClass.BYTE_EXACT,
            )

            def fake_run_node(
                _node: Node,
                *,
                write_generated_root: Path | None,
                **_kwargs: object,
            ) -> tuple[dict[str, object], dict[str, object], Path]:
                assert write_generated_root is not None
                actual_path = write_generated_root / "expected.json"
                payload = self._report_payload("actual")
                self._write_report(actual_path, payload)
                return (
                    {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "", "stderr": ""},
                    payload,
                    actual_path,
                )

            with mock.patch.object(run_gate_pipeline, "NODES", (node,)), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=["", ""],
            ), mock.patch.object(run_gate_pipeline, "run_node", side_effect=fake_run_node):
                with redirect_stdout(io.StringIO()):
                    with self.assertRaises(RuntimeError) as exc:
                        run_gate_pipeline.verify_pipeline(
                            authority="local",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                        )
            self.assertIn("sample_gate: generated report drifted", str(exc.exception))

    def test_verify_rejects_tracked_file_mutation(self) -> None:
        with mock.patch.object(run_gate_pipeline, "NODES", ()), mock.patch.object(
            run_gate_pipeline,
            "tracked_diff_snapshot",
            side_effect=["", " M scripts/run_gate_pipeline.py\n"],
        ):
            with redirect_stdout(io.StringIO()):
                with self.assertRaises(RuntimeError) as exc:
                    run_gate_pipeline.verify_pipeline(
                        authority="local",
                        python="python3",
                        git="git",
                        alr="alr",
                        env={},
                    )
        self.assertIn("gate pipeline changed tracked files during execution", str(exc.exception))

    def test_verify_local_reuses_ci_authoritative_report_without_running_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            payload = self._report_payload("authoritative")
            self._write_report(expected_path, payload)
            node = Node(
                id="sample_gate",
                kind=NodeKind.GATE,
                script=Path("/tmp/run_sample_gate.py"),
                report_path=expected_path,
                determinism_class=DeterminismClass.CI_AUTHORITATIVE,
            )
            with mock.patch.object(run_gate_pipeline, "NODES", (node,)), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=["", ""],
            ), mock.patch.object(run_gate_pipeline, "run_node", side_effect=AssertionError("should not run")):
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(
                        run_gate_pipeline.verify_pipeline(
                            authority="local",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                        ),
                        0,
                    )

    def test_verify_ci_runs_ci_authoritative_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            payload = self._report_payload("authoritative")
            self._write_report(expected_path, payload)
            node = Node(
                id="sample_gate",
                kind=NodeKind.GATE,
                script=Path("/tmp/run_sample_gate.py"),
                report_path=expected_path,
                determinism_class=DeterminismClass.CI_AUTHORITATIVE,
            )

            def fake_run_node(
                _node: Node,
                *,
                write_generated_root: Path | None,
                **_kwargs: object,
            ) -> tuple[dict[str, object], dict[str, object], Path]:
                assert write_generated_root is not None
                actual_path = write_generated_root / "expected.json"
                self._write_report(actual_path, payload)
                return (
                    {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "", "stderr": ""},
                    payload,
                    actual_path,
                )

            with mock.patch.object(run_gate_pipeline, "NODES", (node,)), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=["", ""],
            ), mock.patch.object(run_gate_pipeline, "run_node", side_effect=fake_run_node) as run_node:
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(
                        run_gate_pipeline.verify_pipeline(
                            authority="ci",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                        ),
                        0,
                    )
            run_node.assert_called_once()

    def test_run_node_passes_authority_to_supporting_nodes(self) -> None:
        node = Node(
            id="sample_gate",
            kind=NodeKind.GATE,
            script=Path("/tmp/run_sample_gate.py"),
            supports_authority=True,
        )
        with mock.patch.object(
            run_gate_pipeline,
            "run",
            return_value={
                "command": [],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": "",
                "stderr": "",
            },
        ) as run_mock:
            result, payload, generated_path = run_gate_pipeline.run_node(
                node,
                python="python3",
                authority="ci",
                env={},
                read_generated_root=None,
                write_generated_root=None,
                pipeline_context={},
            )
        self.assertEqual(result["returncode"], 0)
        self.assertIsNone(payload)
        self.assertIsNone(generated_path)
        self.assertEqual(
            run_mock.call_args.args[0],
            ["python3", "/tmp/run_sample_gate.py", "--authority", "ci"],
        )

    def test_run_node_passes_scratch_root_to_supporting_nodes(self) -> None:
        node = Node(
            id="sample_gate",
            kind=NodeKind.GATE,
            script=Path("/tmp/run_sample_gate.py"),
            supports_scratch_root=True,
        )
        with tempfile.TemporaryDirectory() as temp_dir, mock.patch.object(
            run_gate_pipeline,
            "run",
            return_value={
                "command": [],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": "",
                "stderr": "",
            },
        ) as run_mock:
            result, payload, generated_path = run_gate_pipeline.run_node(
                node,
                python="python3",
                authority="local",
                env={},
                read_generated_root=None,
                write_generated_root=Path(temp_dir),
                pipeline_context={},
            )
        self.assertEqual(result["returncode"], 0)
        self.assertIsNone(payload)
        self.assertIsNone(generated_path)
        self.assertEqual(
            run_mock.call_args.args[0],
            [
                "python3",
                "/tmp/run_sample_gate.py",
                "--scratch-root",
                str(Path(temp_dir) / "scratch" / "sample_gate"),
            ],
        )

    def test_verify_local_reuse_rejects_ci_proof_report_missing_three_way_sections(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            self._write_report(expected_path, self._report_payload("authoritative"))
            node = Node(
                id="pr10_emitted_flow",
                kind=NodeKind.GATE,
                script=Path("/tmp/run_pr10_emitted_flow.py"),
                report_path=expected_path,
                determinism_class=DeterminismClass.CI_AUTHORITATIVE,
            )
            with mock.patch.object(run_gate_pipeline, "NODES", (node,)), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=["", ""],
            ):
                with redirect_stdout(io.StringIO()):
                    with self.assertRaises(RuntimeError) as exc:
                        run_gate_pipeline.verify_pipeline(
                            authority="local",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                        )
        self.assertIn("missing semantic_floor", str(exc.exception))

    def test_verify_local_reuse_rejects_nonzero_semantic_floor_counts(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            self._write_report(expected_path, self._proof_payload(prove_unproved=1))
            node = Node(
                id="pr10_emitted_prove",
                kind=NodeKind.GATE,
                script=Path("/tmp/run_pr10_emitted_prove.py"),
                report_path=expected_path,
                determinism_class=DeterminismClass.CI_AUTHORITATIVE,
            )
            with mock.patch.object(run_gate_pipeline, "NODES", (node,)), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=["", ""],
            ):
                with redirect_stdout(io.StringIO()):
                    with self.assertRaises(RuntimeError) as exc:
                        run_gate_pipeline.verify_pipeline(
                            authority="local",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                        )
        self.assertIn("prove_unproved must be zero", str(exc.exception))

    def test_verify_local_reuse_rejects_pr101_hash_mismatch_against_pipeline_context(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            report_paths = {
                node_id: temp_root / f"{node_id}.json"
                for node_id in (
                    "pr08_frontend_baseline",
                    "pr09_ada_emission_baseline",
                    "pr10_emitted_baseline",
                    "emitted_hardening_regressions",
                    "pr101a_companion_proof_verification",
                    "pr101b_template_proof_verification",
                    "pr101_comprehensive_audit",
                )
            }
            self._write_report(report_paths["pr08_frontend_baseline"], self._report_payload("pr08"))
            self._write_report(report_paths["pr09_ada_emission_baseline"], self._report_payload("pr09"))
            self._write_report(report_paths["pr10_emitted_baseline"], self._report_payload("pr10"))
            self._write_report(report_paths["emitted_hardening_regressions"], self._report_payload("hard"))
            self._write_report(
                report_paths["pr101a_companion_proof_verification"],
                self._pr101_child_payload(report_sha="5" * 64),
            )
            self._write_report(
                report_paths["pr101b_template_proof_verification"],
                self._pr101_child_payload(report_sha="6" * 64),
            )
            self._write_report(
                report_paths["pr101_comprehensive_audit"],
                self._pr101_payload(
                    baseline_gate_hashes={
                        "pr08_frontend_baseline": "1" * 64,
                        "pr09_ada_emission_baseline": "1" * 64,
                        "pr10_emitted_baseline": "f" * 64,
                        "emitted_hardening_regressions": "1" * 64,
                    }
                ),
            )

            nodes = (
                Node(
                    id="pr08_frontend_baseline",
                    kind=NodeKind.GATE,
                    script=Path("/tmp/run_pr08_frontend_baseline.py"),
                    report_path=report_paths["pr08_frontend_baseline"],
                ),
                Node(
                    id="pr09_ada_emission_baseline",
                    kind=NodeKind.GATE,
                    script=Path("/tmp/run_pr09_ada_emission_baseline.py"),
                    report_path=report_paths["pr09_ada_emission_baseline"],
                ),
                Node(
                    id="pr10_emitted_baseline",
                    kind=NodeKind.GATE,
                    script=Path("/tmp/run_pr10_emitted_baseline.py"),
                    report_path=report_paths["pr10_emitted_baseline"],
                ),
                Node(
                    id="emitted_hardening_regressions",
                    kind=NodeKind.GATE,
                    script=Path("/tmp/run_emitted_hardening_regressions.py"),
                    report_path=report_paths["emitted_hardening_regressions"],
                ),
                Node(
                    id="pr101a_companion_proof_verification",
                    kind=NodeKind.GATE,
                    script=Path("/tmp/run_pr101a_companion_proof_verification.py"),
                    report_path=report_paths["pr101a_companion_proof_verification"],
                    determinism_class=DeterminismClass.CI_AUTHORITATIVE,
                ),
                Node(
                    id="pr101b_template_proof_verification",
                    kind=NodeKind.GATE,
                    script=Path("/tmp/run_pr101b_template_proof_verification.py"),
                    report_path=report_paths["pr101b_template_proof_verification"],
                    determinism_class=DeterminismClass.CI_AUTHORITATIVE,
                ),
                Node(
                    id="pr101_comprehensive_audit",
                    kind=NodeKind.GATE,
                    script=Path("/tmp/run_pr101_comprehensive_audit.py"),
                    report_path=report_paths["pr101_comprehensive_audit"],
                    determinism_class=DeterminismClass.CI_AUTHORITATIVE,
                ),
            )

            def fake_run_node(
                node: Node,
                *,
                write_generated_root: Path | None,
                **_kwargs: object,
            ) -> tuple[dict[str, object], dict[str, object], Path]:
                assert write_generated_root is not None
                actual_path = write_generated_root / node.report_path.name
                payload = json.loads(node.report_path.read_text(encoding="utf-8"))
                self._write_report(actual_path, payload)
                return (
                    {
                        "command": ["python3", str(node.script)],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                        "stdout": "",
                        "stderr": "",
                    },
                    payload,
                    actual_path,
                )

            with mock.patch.object(run_gate_pipeline, "NODES", nodes), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=["", ""],
            ), mock.patch.object(run_gate_pipeline, "run_node", side_effect=fake_run_node):
                with redirect_stdout(io.StringIO()):
                    with self.assertRaises(RuntimeError) as exc:
                        run_gate_pipeline.verify_pipeline(
                            authority="local",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                        )
        self.assertIn("PR101 semantic_floor pr10_emitted_baseline hash mismatch", str(exc.exception))

    def test_ratchet_allows_unrelated_tracked_edits(self) -> None:
        with mock.patch.object(
            run_gate_pipeline,
            "tracked_diff_snapshot",
            side_effect=[" M docs/vision.md\n", "", ""],
        ), mock.patch.object(run_gate_pipeline, "execute_pipeline", return_value={}) as execute_pipeline, mock.patch.object(
            run_gate_pipeline,
            "promote_stage",
        ) as promote_stage, mock.patch.object(run_gate_pipeline, "verify_pipeline", return_value=0) as verify_pipeline:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(
                    run_gate_pipeline.ratchet_pipeline(
                        authority="local",
                        python="python3",
                        git="git",
                        alr="alr",
                        env={},
                    ),
                    0,
                )
        self.assertEqual(execute_pipeline.call_count, 2)
        promote_stage.assert_called_once()
        verify_pipeline.assert_called_once()
        self.assertEqual(
            verify_pipeline.call_args.kwargs["initial_snapshot"],
            "",
        )

    def test_ratchet_aborts_before_promotion_when_stage_verify_fails(self) -> None:
        with mock.patch.object(
            run_gate_pipeline,
            "tracked_diff_snapshot",
            side_effect=["", ""],
        ), mock.patch.object(
            run_gate_pipeline,
            "execute_pipeline",
            side_effect=[{}, RuntimeError("stage verify failed")],
        ) as execute_pipeline, mock.patch.object(
            run_gate_pipeline,
            "promote_stage",
        ) as promote_stage, mock.patch.object(run_gate_pipeline, "verify_pipeline") as verify_pipeline:
            with redirect_stdout(io.StringIO()):
                with self.assertRaises(RuntimeError) as exc:
                    run_gate_pipeline.ratchet_pipeline(
                        authority="local",
                        python="python3",
                        git="git",
                        alr="alr",
                        env={},
                    )
        self.assertEqual(str(exc.exception), "stage verify failed")
        self.assertEqual(execute_pipeline.call_count, 2)
        promote_stage.assert_not_called()
        verify_pipeline.assert_not_called()

    def test_verify_uses_explicit_initial_snapshot(self) -> None:
        with mock.patch.object(run_gate_pipeline, "NODES", ()), mock.patch.object(
            run_gate_pipeline,
            "tracked_diff_snapshot",
            return_value=" M execution/reports/example.json\n",
        ) as tracked_diff_snapshot:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(
                    run_gate_pipeline.verify_pipeline(
                        authority="local",
                        python="python3",
                        git="git",
                        alr="alr",
                        env={},
                        initial_snapshot=" M execution/reports/example.json\n",
                    ),
                    0,
                )
        tracked_diff_snapshot.assert_called_once_with(git="git", env={})


if __name__ == "__main__":
    unittest.main()
