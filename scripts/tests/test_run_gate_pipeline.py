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
from _lib.gate_manifest import DeterminismClass, Node, NodeKind, VALIDATE_EXECUTION_STATE_FINAL


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

    @staticmethod
    def _local_host_sensitive_payload(
        *,
        safec_binary_sha256: str,
        gate_quality_hash: str,
        report_sha256: str,
    ) -> dict[str, object]:
        return {
            "task": "PR06.9.9",
            "status": "ok",
            "build_reproducibility": {
                "binary_deterministic": True,
            },
            "delegated_reports": {
                "frontend_smoke": {"report_sha256": "f" * 64, "repeat_sha256": "f" * 64},
                "gate_quality": {"report_sha256": "g" * 64, "repeat_sha256": "g" * 64},
                "legacy_package_cleanup": {"report_sha256": "l" * 64, "repeat_sha256": "l" * 64},
            },
            "child_gate_input_hashes": {"gate_quality": gate_quality_hash},
            "safec_binary_sha256": safec_binary_sha256,
            "deterministic": True,
            "report_sha256": report_sha256,
            "repeat_sha256": report_sha256,
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

    def test_verify_uses_branch_scoped_nodes_when_branch_is_provided(self) -> None:
        branch_nodes = (
            Node(id="validate_execution_state_preflight", kind=NodeKind.GATE, script=Path("/tmp/preflight.py")),
        )
        with mock.patch.object(run_gate_pipeline, "resolve_branch", return_value=list(branch_nodes)), mock.patch.object(
            run_gate_pipeline,
            "tracked_diff_snapshot",
            return_value="",
        ), mock.patch.object(run_gate_pipeline, "execute_pipeline", return_value={}) as execute_pipeline:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(
                    run_gate_pipeline.verify_pipeline(
                        authority="local",
                        python="python3",
                        git="git",
                        alr="alr",
                        env={},
                        branch="codex/pr114-signature-control-flow-syntax",
                    ),
                    0,
                )
        self.assertEqual(execute_pipeline.call_args.kwargs["nodes"], branch_nodes)

    def test_verify_local_reuses_ci_authoritative_report_without_running_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            payload = self._proof_payload()
            self._write_report(expected_path, payload)
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

    def test_verify_local_reuse_rejects_unhandled_ci_authoritative_node(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            self._write_report(expected_path, self._report_payload("authoritative"))
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
                    with self.assertRaises(RuntimeError) as exc:
                        run_gate_pipeline.verify_pipeline(
                            authority="local",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                        )
        self.assertIn("unhandled local CI-authoritative validation", str(exc.exception))

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

    def test_report_compare_text_normalizes_local_host_sensitive_fields(self) -> None:
        node = Node(
            id="pr0699_build_reproducibility",
            kind=NodeKind.GATE,
            report_path=Path("/tmp/pr0699.json"),
            determinism_class=DeterminismClass.LOCAL_HOST_SENSITIVE,
        )
        payload = self._local_host_sensitive_payload(
            safec_binary_sha256="a" * 64,
            gate_quality_hash="b" * 64,
            report_sha256="c" * 64,
        )

        normalized = run_gate_pipeline.report_compare_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            node=node,
            authority="local",
        )

        normalized_payload = json.loads(normalized)
        self.assertNotIn("safec_binary_sha256", normalized_payload)
        self.assertNotIn("child_gate_input_hashes", normalized_payload)
        self.assertNotIn("report_sha256", normalized_payload)
        self.assertNotIn("repeat_sha256", normalized_payload)

    def test_verify_local_accepts_local_host_sensitive_report_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            expected_path = Path(temp_dir) / "expected.json"
            self._write_report(
                expected_path,
                self._local_host_sensitive_payload(
                    safec_binary_sha256="1" * 64,
                    gate_quality_hash="2" * 64,
                    report_sha256="3" * 64,
                ),
            )
            node = Node(
                id="pr0699_build_reproducibility",
                kind=NodeKind.GATE,
                script=Path("/tmp/run_pr0699_build_reproducibility.py"),
                report_path=expected_path,
                determinism_class=DeterminismClass.LOCAL_HOST_SENSITIVE,
            )

            def fake_run_node(
                _node: Node,
                *,
                write_generated_root: Path | None,
                **_kwargs: object,
            ) -> tuple[dict[str, object], dict[str, object], Path]:
                assert write_generated_root is not None
                actual_path = write_generated_root / "expected.json"
                actual_payload = self._local_host_sensitive_payload(
                    safec_binary_sha256="4" * 64,
                    gate_quality_hash="5" * 64,
                    report_sha256="6" * 64,
                )
                self._write_report(actual_path, actual_payload)
                return (
                    {"command": ["python3"], "cwd": "$REPO_ROOT", "returncode": 0, "stdout": "", "stderr": ""},
                    actual_payload,
                    actual_path,
                )

            with mock.patch.object(run_gate_pipeline, "NODES", (node,)), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=["", ""],
            ), mock.patch.object(run_gate_pipeline, "run_node", side_effect=fake_run_node):
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

    def test_run_node_passes_generated_output_baseline_file_to_preflight(self) -> None:
        node = Node(
            id="validate_execution_state_preflight",
            kind=NodeKind.VALIDATION,
            script=Path("/tmp/validate_execution_state.py"),
            supports_authority=True,
            argv=("--phase", "preflight"),
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
            baseline_file = Path(temp_dir) / "generated-output-baseline.txt"
            run_gate_pipeline.run_node(
                node,
                python="python3",
                authority="local",
                env={},
                read_generated_root=None,
                write_generated_root=Path(temp_dir),
                pipeline_context={},
                preflight_generated_output_baseline_file=baseline_file,
            )
        self.assertEqual(
            run_mock.call_args.args[0],
            [
                "python3",
                "/tmp/validate_execution_state.py",
                "--phase",
                "preflight",
                "--authority",
                "local",
                "--generated-output-baseline-file",
                str(baseline_file),
            ],
        )

    def test_execute_pipeline_writes_checkpoints_for_non_build_nodes_only(self) -> None:
        build_node = Node(id="build", kind=NodeKind.BUILD, repo_clean_profile="frontend_build")
        gate_node = Node(
            id="sample_gate",
            kind=NodeKind.GATE,
            script=Path("/tmp/run_sample_gate.py"),
            report_path=Path("/tmp/sample_gate.json"),
        )

        def fake_run_node(
            node: Node,
            *,
            write_generated_root: Path | None,
            **_kwargs: object,
        ) -> tuple[dict[str, object], dict[str, object], Path]:
            assert node is gate_node
            assert write_generated_root is not None
            actual_path = write_generated_root / "sample_gate.json"
            payload = self._report_payload("ok")
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

        with tempfile.TemporaryDirectory() as temp_dir, mock.patch.object(
            run_gate_pipeline,
            "NODES",
            (build_node, gate_node),
        ), mock.patch.object(
            run_gate_pipeline,
            "run",
            return_value={
                "command": ["alr", "build"],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": "",
                "stderr": "",
            },
        ), mock.patch.object(
            run_gate_pipeline,
            "tracked_diff_snapshot",
            return_value="",
        ), mock.patch.object(
            run_gate_pipeline,
            "clean_repo_profile",
        ), mock.patch.object(
            run_gate_pipeline,
            "run_node",
            side_effect=fake_run_node,
        ):
            root = Path(temp_dir)
            checkpoint_root = root / "checkpoints"
            with redirect_stdout(io.StringIO()):
                run_gate_pipeline.execute_pipeline(
                    authority="local",
                    python="python3",
                    env={},
                    alr="alr",
                    git="git",
                    read_generated_root=None,
                    write_generated_root=root,
                    compare_root=None,
                    compare_to_committed=False,
                    initial_snapshot="",
                    checkpoint_root=checkpoint_root,
                )
            self.assertFalse((checkpoint_root / "build.json").exists())
            checkpoint = json.loads((checkpoint_root / "sample_gate.json").read_text(encoding="utf-8"))
            self.assertEqual(checkpoint["node_id"], "sample_gate")
            self.assertEqual(checkpoint["kind"], "gate")
            self.assertEqual(checkpoint["authority"], "local")
            self.assertEqual(checkpoint["status"], "ok")
            self.assertEqual(checkpoint["report_sha256"], "1" * 64)
            self.assertEqual(checkpoint["dependency_report_hashes"], {})
            self.assertEqual(checkpoint["pipeline_context_entry"]["report"]["report_sha256"], "1" * 64)

    def test_final_rerun_start_index_rewinds_pr0699_to_self_without_post_repro_build(self) -> None:
        self.assertEqual(
            run_gate_pipeline.final_rerun_start_index(
                changed_nodes=["pr0699_build_reproducibility"],
                dashboard_changed_flag=False,
            ),
            run_gate_pipeline.NODE_INDEX_BY_ID["pr0699_build_reproducibility"],
        )

    def test_final_rerun_start_index_starts_at_pr0697_when_pr0697_changed(self) -> None:
        self.assertEqual(
            run_gate_pipeline.final_rerun_start_index(
                changed_nodes=["pr0697_gate_quality"],
                dashboard_changed_flag=False,
            ),
            run_gate_pipeline.NODE_INDEX_BY_ID["pr0697_gate_quality"],
        )

    def test_final_rerun_start_index_uses_final_validation_for_dashboard_only(self) -> None:
        self.assertEqual(
            run_gate_pipeline.final_rerun_start_index(
                changed_nodes=[],
                dashboard_changed_flag=True,
            ),
            run_gate_pipeline.NODE_INDEX_BY_ID[VALIDATE_EXECUTION_STATE_FINAL],
        )

    def test_changed_report_nodes_treats_missing_committed_report_as_changed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stage_root = root / "stage"
            stage_root.mkdir()
            committed_path = root / "missing-committed.json"
            generated_path = stage_root / committed_path.name
            self._write_report(generated_path, self._report_payload("generated"))
            node = Node(id="sample_gate", kind=NodeKind.GATE, report_path=committed_path)
            with mock.patch.object(run_gate_pipeline, "NODES", (node,)):
                changed = run_gate_pipeline.changed_report_nodes(generated_root=stage_root, authority="local")
        self.assertEqual(changed, ["sample_gate"])

    def test_changed_report_nodes_rejects_missing_generated_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stage_root = root / "stage"
            stage_root.mkdir()
            committed_path = root / "committed.json"
            self._write_report(committed_path, self._report_payload("committed"))
            node = Node(id="sample_gate", kind=NodeKind.GATE, report_path=committed_path)
            with mock.patch.object(run_gate_pipeline, "NODES", (node,)):
                with self.assertRaises(RuntimeError) as exc:
                    run_gate_pipeline.changed_report_nodes(generated_root=stage_root, authority="local")
        self.assertIn("sample_gate: missing generated report", str(exc.exception))

    def test_changed_report_nodes_ignores_local_host_sensitive_only_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stage_root = root / "stage"
            stage_root.mkdir()
            committed_path = root / "pr0699.json"
            stage_path = stage_root / committed_path.name
            self._write_report(
                committed_path,
                self._local_host_sensitive_payload(
                    safec_binary_sha256="1" * 64,
                    gate_quality_hash="2" * 64,
                    report_sha256="3" * 64,
                ),
            )
            self._write_report(
                stage_path,
                self._local_host_sensitive_payload(
                    safec_binary_sha256="4" * 64,
                    gate_quality_hash="5" * 64,
                    report_sha256="6" * 64,
                ),
            )
            node = Node(
                id="pr0699_build_reproducibility",
                kind=NodeKind.GATE,
                report_path=committed_path,
                determinism_class=DeterminismClass.LOCAL_HOST_SENSITIVE,
            )
            with mock.patch.object(run_gate_pipeline, "NODES", (node,)):
                changed = run_gate_pipeline.changed_report_nodes(
                    generated_root=stage_root,
                    authority="local",
                )
        self.assertEqual(changed, [])

    def test_execution_indices_rerun_preflight_before_suffix(self) -> None:
        indices = run_gate_pipeline.execution_indices(
            start_index=run_gate_pipeline.NODE_INDEX_BY_ID["pr0697_gate_quality"],
            rerun_preflight=True,
        )
        self.assertEqual(indices[0], run_gate_pipeline.NODE_INDEX_BY_ID["validate_execution_state_preflight"])
        self.assertEqual(indices[1], run_gate_pipeline.NODE_INDEX_BY_ID["pr0697_gate_quality"])

    def test_load_seed_pipeline_context_reads_non_build_prefix_checkpoints(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            checkpoint_root = Path(temp_dir)
            nodes = (
                Node(id="validate_execution_state_preflight", kind=NodeKind.VALIDATION),
                Node(id="build", kind=NodeKind.BUILD),
                Node(id="gate_a", kind=NodeKind.GATE),
                Node(id="gate_b", kind=NodeKind.GATE),
            )
            for node_id in ("gate_a",):
                checkpoint = {
                    "node_id": node_id,
                    "status": "ok",
                    "pipeline_context_entry": {"result": {"returncode": 0}},
                }
                (checkpoint_root / f"{node_id}.json").write_text(
                    json.dumps(checkpoint, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                )
            with mock.patch.object(run_gate_pipeline, "NODES", nodes):
                seeded = run_gate_pipeline.load_seed_pipeline_context(
                    checkpoint_root=checkpoint_root,
                    start_index=3,
                )
        self.assertIn("gate_a", seeded)
        self.assertNotIn("build", seeded)

    def test_load_seed_pipeline_context_rejects_corrupt_checkpoint_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            checkpoint_root = Path(temp_dir)
            nodes = (
                Node(id="validate_execution_state_preflight", kind=NodeKind.VALIDATION),
                Node(id="gate_a", kind=NodeKind.GATE),
            )
            (checkpoint_root / "gate_a.json").write_text("{not json\n", encoding="utf-8")
            with mock.patch.object(run_gate_pipeline, "NODES", nodes):
                with self.assertRaises(RuntimeError) as exc:
                    run_gate_pipeline.load_seed_pipeline_context(
                        checkpoint_root=checkpoint_root,
                        start_index=2,
                    )
        self.assertIn("gate_a: corrupt checkpoint", str(exc.exception))

    def test_node_scratch_root_creates_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            write_generated_root = Path(temp_dir)
            node = Node(
                id="scratch_gate",
                kind=NodeKind.GATE,
                supports_scratch_root=True,
            )
            scratch_root = run_gate_pipeline.node_scratch_root(
                node=node,
                write_generated_root=write_generated_root,
            )
            self.assertIsNotNone(scratch_root)
            assert scratch_root is not None
            self.assertTrue(scratch_root.exists())
            self.assertTrue(scratch_root.is_dir())

    def test_final_rerun_pipeline_passes_promoted_baseline_and_seeded_context(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stage_root = root / "stage"
            stage_verify_root = root / "verify"
            final_verify_root = root / "final"
            stage_root.mkdir()
            stage_verify_root.mkdir()
            final_verify_root.mkdir()
            self._write_report(
                stage_root / "execution" / "reports" / "pr0699-build-reproducibility-report.json",
                self._report_payload("refreshed"),
            )
            with mock.patch.object(
                run_gate_pipeline,
                "changed_report_nodes",
                return_value=["pr0699_build_reproducibility"],
            ), mock.patch.object(
                run_gate_pipeline,
                "dashboard_changed",
                return_value=False,
            ), mock.patch.object(
                run_gate_pipeline,
                "promote_stage",
            ), mock.patch.object(
                run_gate_pipeline,
                "tracked_diff_snapshot",
                side_effect=[
                    " M execution/reports/pr0699-build-reproducibility-report.json\n",
                    " M execution/reports/pr0699-build-reproducibility-report.json\n",
                ],
            ), mock.patch.object(
                run_gate_pipeline,
                "load_seed_pipeline_context",
                return_value={"pr0697_gate_quality": {"result": {"returncode": 0}}},
            ) as load_seed_pipeline_context, mock.patch.object(
                run_gate_pipeline,
                "execute_pipeline",
                return_value={},
            ) as execute_pipeline:
                stdout = io.StringIO()
                with redirect_stdout(stdout):
                    self.assertEqual(
                        run_gate_pipeline.final_rerun_pipeline(
                            authority="local",
                            python="python3",
                            git="git",
                            alr="alr",
                            env={},
                            stage_root=stage_root,
                            stage_verify_root=stage_verify_root,
                            final_verify_root=final_verify_root,
                        ),
                        0,
                    )
                text = stdout.getvalue()
                self.assertIn(
                    "[gate-pipeline] phase: promote staged outputs (changed reports: pr0699_build_reproducibility)",
                    text,
                )
                self.assertIn(
                    "[gate-pipeline] phase: final rerun (start node: pr0699_build_reproducibility)",
                    text,
                )
                load_seed_pipeline_context.assert_called_once_with(
                    checkpoint_root=stage_verify_root / "checkpoints",
                    start_index=run_gate_pipeline.NODE_INDEX_BY_ID["pr0699_build_reproducibility"],
                )
                baseline_file = execute_pipeline.call_args.kwargs["preflight_generated_output_baseline_file"]
                self.assertEqual(
                    baseline_file.read_text(encoding="utf-8"),
                    " M execution/reports/pr0699-build-reproducibility-report.json\n",
                )
                self.assertEqual(
                    execute_pipeline.call_args.kwargs["start_index"],
                    run_gate_pipeline.NODE_INDEX_BY_ID["pr0699_build_reproducibility"],
                )
                self.assertEqual(
                    execute_pipeline.call_args.kwargs["seed_pipeline_context"],
                    {"pr0697_gate_quality": {"result": {"returncode": 0}}},
                )
                self.assertIsNone(execute_pipeline.call_args.kwargs["read_generated_root"])
                self.assertIsNone(execute_pipeline.call_args.kwargs["compare_root"])
                self.assertTrue(execute_pipeline.call_args.kwargs["compare_to_committed"])

    def test_promote_stage_rolls_back_reports_without_merging_partial_stage_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repo_root = root / "repo"
            stage_root = root / "stage"
            committed_reports = repo_root / "execution" / "reports"
            committed_dashboard = repo_root / "execution" / "dashboard.md"
            stage_dashboard = stage_root / "execution" / "dashboard.md"

            committed_reports.mkdir(parents=True)
            committed_dashboard.parent.mkdir(parents=True, exist_ok=True)
            stage_dashboard.parent.mkdir(parents=True, exist_ok=True)

            (committed_reports / "kept.json").write_text("old report\n", encoding="utf-8")
            committed_dashboard.write_text("old dashboard\n", encoding="utf-8")
            staged_report = stage_root / "execution" / "reports" / "new.json"
            staged_report.parent.mkdir(parents=True, exist_ok=True)
            staged_report.write_text("new report\n", encoding="utf-8")
            stage_dashboard.write_text("new dashboard\n", encoding="utf-8")

            node = Node(
                id="sample_gate",
                kind=NodeKind.GATE,
                report_path=repo_root / "execution" / "reports" / "new.json",
            )
            original_copy2 = run_gate_pipeline.shutil.copy2

            def flaky_copy2(src: str | Path, dst: str | Path, *args: object, **kwargs: object) -> str:
                src_path = Path(src)
                if src_path == staged_report:
                    raise RuntimeError("simulated copy failure")
                return original_copy2(src_path, dst, *args, **kwargs)

            with mock.patch.object(run_gate_pipeline, "REPO_ROOT", repo_root), mock.patch.object(
                run_gate_pipeline,
                "NODES_BY_ID",
                {"sample_gate": node},
            ), mock.patch.object(
                run_gate_pipeline.shutil,
                "copy2",
                side_effect=flaky_copy2,
            ):
                with self.assertRaises(RuntimeError) as exc:
                    run_gate_pipeline.promote_stage(
                        stage_root,
                        changed_nodes=["sample_gate"],
                        dashboard_changed_flag=True,
                    )

            self.assertEqual(str(exc.exception), "simulated copy failure")
            self.assertEqual((committed_reports / "kept.json").read_text(encoding="utf-8"), "old report\n")
            self.assertFalse((committed_reports / "new.json").exists())
            self.assertEqual(committed_dashboard.read_text(encoding="utf-8"), "old dashboard\n")

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
            side_effect=[" M docs/vision.md\n", ""],
        ), mock.patch.object(run_gate_pipeline, "execute_pipeline", return_value={}) as execute_pipeline, mock.patch.object(
            run_gate_pipeline,
            "final_rerun_pipeline",
            return_value=0,
        ) as final_rerun_pipeline:
            stdout = io.StringIO()
            with redirect_stdout(stdout):
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
        text = stdout.getvalue()
        self.assertIn("[gate-pipeline] phase: stage generation", text)
        self.assertIn("[gate-pipeline] phase: stage verify", text)
        self.assertEqual(execute_pipeline.call_count, 2)
        final_rerun_pipeline.assert_called_once()

    def test_ratchet_requires_clean_generated_output_baseline(self) -> None:
        with mock.patch.object(
            run_gate_pipeline,
            "tracked_diff_snapshot",
            side_effect=["", " M execution/reports/example.json\n"],
        ), mock.patch.object(
            run_gate_pipeline,
            "execute_pipeline",
            side_effect=AssertionError("should not run"),
        ):
            with self.assertRaises(RuntimeError) as exc:
                run_gate_pipeline.ratchet_pipeline(
                    authority="local",
                    python="python3",
                    git="git",
                    alr="alr",
                    env={},
                )
        self.assertIn("ratchet requires a clean generated-output working tree", str(exc.exception))
        self.assertIn("accept ratchet artifact", str(exc.exception))
        self.assertIn("restore ratchet baseline", str(exc.exception))

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
            "final_rerun_pipeline",
        ) as final_rerun_pipeline:
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
        final_rerun_pipeline.assert_not_called()

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
