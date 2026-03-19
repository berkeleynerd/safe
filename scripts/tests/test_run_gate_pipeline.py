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
