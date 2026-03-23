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

import run_pr0699_build_reproducibility


class Pr0699BuildReproducibilityTests(unittest.TestCase):
    def test_load_prior_report_prefers_generated_root_report_when_present(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            generated_root = temp_root / "stage"
            generated_report = (
                generated_root / "execution" / "reports" / "pr0699-build-reproducibility-report.json"
            )
            generated_report.parent.mkdir(parents=True, exist_ok=True)
            generated_report.write_text(
                json.dumps({"task": "generated", "safec_binary_sha256": "generated-hash"}),
                encoding="utf-8",
            )

            committed_report = temp_root / "committed-pr0699.json"
            committed_report.write_text(
                json.dumps({"task": "committed", "safec_binary_sha256": "committed-hash"}),
                encoding="utf-8",
            )

            with mock.patch.object(
                run_pr0699_build_reproducibility,
                "DEFAULT_REPORT",
                committed_report,
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "resolve_generated_path",
                return_value=generated_report,
            ):
                report = run_pr0699_build_reproducibility.load_prior_report(
                    generated_root=generated_root
                )

        self.assertEqual(report["task"], "generated")

    def test_infer_generated_root_returns_none_for_repo_report(self) -> None:
        self.assertIsNone(
            run_pr0699_build_reproducibility.infer_generated_root(
                report_path=run_pr0699_build_reproducibility.DEFAULT_REPORT
            )
        )

    def test_infer_generated_root_derives_stage_root_for_temp_report(self) -> None:
        stage_root = Path("/tmp/gate-pipeline-stage-xyz")
        report_path = stage_root / "execution" / "reports" / "pr0699-build-reproducibility-report.json"
        self.assertEqual(
            run_pr0699_build_reproducibility.infer_generated_root(report_path=report_path),
            stage_root,
        )

    def test_canonicalize_generated_gate_result_strips_report_transport(self) -> None:
        report_path = run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT
        result = {
            "command": [
                "python3",
                "scripts/run_frontend_smoke.py",
                "--report",
                "$TMPDIR/execution/reports/pr00-pr04-frontend-smoke.json",
            ],
            "cwd": "$REPO_ROOT",
            "returncode": 0,
            "stdout": "frontend smoke: OK ($TMPDIR/execution/reports/pr00-pr04-frontend-smoke.json)\n",
            "stderr": "",
        }
        canonical = run_pr0699_build_reproducibility.canonicalize_generated_gate_result(
            result=result,
            report_path=report_path,
        )
        self.assertEqual(
            canonical["command"],
            ["python3", "scripts/run_frontend_smoke.py"],
        )
        self.assertEqual(
            canonical["stdout"],
            "frontend smoke: OK (execution/reports/pr00-pr04-frontend-smoke.json)\n",
        )

    def test_resolve_build_reproducibility_skips_rebuild_when_build_input_hash_matches(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            build_reproducibility = {
                "binary_deterministic": True,
                "build_input_hash": "same-hash",
            }
            build_cache: dict[str, object] = {}

            with mock.patch.object(
                run_pr0699_build_reproducibility,
                "compute_build_input_hash",
                return_value="same-hash",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "stable_binary_sha256",
                return_value="observed-hash",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "run_build_reproducibility",
            ) as rebuild_mock, mock.patch.object(
                run_pr0699_build_reproducibility.time,
                "monotonic",
                side_effect=[10.0, 10.2],
            ):
                reused, binary_hash = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                    alr="alr",
                    safec=safec,
                    prior_report={
                        "build_reproducibility": build_reproducibility,
                    },
                    build_cache=build_cache,
                    env={},
                )

        rebuild_mock.assert_not_called()
        self.assertEqual(reused, build_reproducibility)
        self.assertEqual(binary_hash, "observed-hash")
        self.assertEqual(build_cache["build_reproducibility"], build_reproducibility)
        self.assertEqual(build_cache["observed_binary_sha256"], "observed-hash")

    def test_resolve_build_reproducibility_emits_skip_log_in_verbose_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            build_reproducibility = {
                "binary_deterministic": True,
                "build_input_hash": "same-hash",
            }
            stdout = io.StringIO()

            with mock.patch.object(
                run_pr0699_build_reproducibility,
                "compute_build_input_hash",
                return_value="same-hash",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "stable_binary_sha256",
                return_value="observed-hash",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "run_build_reproducibility",
            ) as rebuild_mock, mock.patch.object(
                run_pr0699_build_reproducibility.time,
                "monotonic",
                side_effect=[10.0, 10.2],
            ), redirect_stdout(stdout):
                reused, binary_hash = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                    alr="alr",
                    safec=safec,
                    prior_report={
                        "build_reproducibility": build_reproducibility,
                    },
                    build_cache={},
                    env={},
                    verbose=True,
                )

        rebuild_mock.assert_not_called()
        self.assertEqual(reused, build_reproducibility)
        self.assertEqual(binary_hash, "observed-hash")
        self.assertEqual(
            stdout.getvalue(),
            "[pr0699] build inputs unchanged, skipping reproducibility rebuild (0.2s hash check)\n",
        )

    def test_resolve_build_reproducibility_reuses_in_process_cache_when_hash_matches(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            cached_build = {
                "binary_deterministic": True,
                "build_input_hash": "same-hash",
            }

            with mock.patch.object(
                run_pr0699_build_reproducibility,
                "compute_build_input_hash",
                return_value="same-hash",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "run_build_reproducibility",
            ) as rebuild_mock:
                resolved = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                    alr="alr",
                    safec=safec,
                    prior_report=None,
                    build_cache={
                        "build_reproducibility": cached_build,
                        "observed_binary_sha256": "cached-hash",
                    },
                    env={},
                )

        rebuild_mock.assert_not_called()
        self.assertEqual(resolved, (cached_build, "cached-hash"))

    def test_resolve_build_reproducibility_caches_proven_build_for_second_call(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            build_cache: dict[str, object] = {}
            rebuilt = (
                {
                    "binary_deterministic": True,
                    "build_input_hash": "build-input-hash",
                },
                "rebuilt-hash",
            )
            with mock.patch.object(
                run_pr0699_build_reproducibility,
                "compute_build_input_hash",
                return_value="build-input-hash",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "run_build_reproducibility",
                return_value=rebuilt,
            ) as rebuild_mock:
                first = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                    alr="alr",
                    safec=Path("/missing/safec"),
                    prior_report=None,
                    build_cache=build_cache,
                    env={},
                )
                safec.write_bytes(b"binary")
                second = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                    alr="alr",
                    safec=safec,
                    prior_report=None,
                    build_cache=build_cache,
                    env={},
                )

        self.assertEqual(rebuild_mock.call_count, 1)
        self.assertEqual(first, rebuilt)
        self.assertEqual(second, rebuilt)

    def test_resolve_build_reproducibility_falls_back_when_build_input_hash_mismatches(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            rebuilt = (
                {
                    "binary_deterministic": True,
                    "build_input_hash": "new-hash",
                },
                "rebuilt-binary-hash",
            )

            with mock.patch.object(
                run_pr0699_build_reproducibility,
                "compute_build_input_hash",
                return_value="new-hash",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "run_build_reproducibility",
                return_value=rebuilt,
            ) as rebuild_mock:
                resolved = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                    alr="alr",
                    safec=safec,
                    prior_report={
                        "build_reproducibility": {
                            "binary_deterministic": True,
                            "build_input_hash": "old-hash",
                        },
                    },
                    build_cache={},
                    env={},
                )

        rebuild_mock.assert_called_once_with(
            alr="alr",
            safec=safec,
            build_input_hash="new-hash",
            env={},
        )
        self.assertEqual(resolved, rebuilt)

    def test_resolve_build_reproducibility_falls_back_without_prior_build_input_hash(self) -> None:
        rebuilt = (
            {
                "binary_deterministic": True,
                "build_input_hash": "rebuilt-hash",
            },
            "rebuilt-binary-hash",
        )
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_build_input_hash",
            return_value="rebuilt-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_build_reproducibility",
            return_value=rebuilt,
        ) as rebuild_mock:
            resolved = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                alr="alr",
                safec=Path("/missing/safec"),
                prior_report={"build_reproducibility": {"binary_deterministic": True}},
                build_cache={},
                env={},
            )

        rebuild_mock.assert_called_once_with(
            alr="alr",
            safec=Path("/missing/safec"),
            build_input_hash="rebuilt-hash",
            env={},
        )
        self.assertEqual(resolved, rebuilt)

    def test_resolve_build_reproducibility_falls_back_when_prior_report_missing(self) -> None:
        rebuilt = (
            {
                "binary_deterministic": True,
                "build_input_hash": "rebuilt-hash",
            },
            "rebuilt-binary-hash",
        )
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_build_input_hash",
            return_value="rebuilt-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_build_reproducibility",
            return_value=rebuilt,
        ) as rebuild_mock:
            resolved = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                alr="alr",
                safec=Path("/missing/safec"),
                prior_report=None,
                build_cache={},
                env={},
            )

        rebuild_mock.assert_called_once_with(
            alr="alr",
            safec=Path("/missing/safec"),
            build_input_hash="rebuilt-hash",
            env={},
        )
        self.assertEqual(resolved, rebuilt)

    def test_resolve_build_reproducibility_falls_back_when_binary_missing(self) -> None:
        rebuilt = (
            {
                "binary_deterministic": True,
                "build_input_hash": "rebuilt-hash",
            },
            "rebuilt-binary-hash",
        )
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_build_input_hash",
            return_value="rebuilt-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_build_reproducibility",
            return_value=rebuilt,
        ) as rebuild_mock, mock.patch.object(
            run_pr0699_build_reproducibility,
            "stable_binary_sha256",
        ) as hash_mock:
            resolved = run_pr0699_build_reproducibility.resolve_build_reproducibility(
                alr="alr",
                safec=Path("/missing/safec"),
                prior_report={
                    "build_reproducibility": {
                        "binary_deterministic": True,
                        "build_input_hash": "rebuilt-hash",
                    },
                },
                build_cache={},
                env={},
            )

        hash_mock.assert_not_called()
        rebuild_mock.assert_called_once_with(
            alr="alr",
            safec=Path("/missing/safec"),
            build_input_hash="rebuilt-hash",
            env={},
        )
        self.assertEqual(resolved, rebuilt)

    def test_resolve_gate_quality_result_skips_when_input_hash_matches(self) -> None:
        prior_gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "gate",
            "repeat_sha256": "gate",
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
        ) as gate_mock, mock.patch.object(
            run_pr0699_build_reproducibility.time,
            "monotonic",
            side_effect=[20.0, 20.1],
        ):
            result = run_pr0699_build_reproducibility.resolve_gate_quality_result(
                python="python3",
                generated_root=None,
                env={},
                prior_report={
                    "child_gate_input_hashes": {
                        run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "same-hash"
                    },
                    "delegated_reports": {
                        run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: prior_gate_quality
                    },
                },
                gate_quality_input_hash="same-hash",
            )

        gate_mock.assert_not_called()
        self.assertEqual(result, prior_gate_quality)

    def test_resolve_gate_quality_result_emits_skip_log_in_verbose_mode(self) -> None:
        prior_gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "gate",
            "repeat_sha256": "gate",
        }
        stdout = io.StringIO()
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
        ) as gate_mock, mock.patch.object(
            run_pr0699_build_reproducibility.time,
            "monotonic",
            side_effect=[20.0, 20.1],
        ), redirect_stdout(stdout):
            result = run_pr0699_build_reproducibility.resolve_gate_quality_result(
                python="python3",
                generated_root=None,
                env={},
                prior_report={
                    "child_gate_input_hashes": {
                        run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "same-hash"
                    },
                    "delegated_reports": {
                        run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: prior_gate_quality
                    },
                },
                gate_quality_input_hash="same-hash",
                verbose=True,
            )

        gate_mock.assert_not_called()
        self.assertEqual(result, prior_gate_quality)
        self.assertEqual(
            stdout.getvalue(),
            "[pr0699] gate_quality inputs unchanged, reusing cached result (0.1s hash check)\n",
        )

    def test_canonical_safec_binary_sha256_preserves_prior_local_value(self) -> None:
        self.assertEqual(
            run_pr0699_build_reproducibility.canonical_safec_binary_sha256(
                authority="local",
                prior_report={"safec_binary_sha256": "prior-hash"},
                observed_binary_sha256="observed-hash",
            ),
            "prior-hash",
        )

    def test_canonical_child_gate_input_hashes_preserve_prior_local_value(self) -> None:
        self.assertEqual(
            run_pr0699_build_reproducibility.canonical_child_gate_input_hashes(
                authority="local",
                prior_report={
                    "child_gate_input_hashes": {
                        run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "prior-hash"
                    }
                },
                gate_quality_input_hash="observed-hash",
            ),
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "prior-hash"},
        )

    def test_compute_gate_quality_input_hash_is_independent_of_binary_hash(self) -> None:
        gate_quality_script = Path("/tmp/run_pr0697_gate_quality.py")
        output_validator = Path("/tmp/validate_output_contracts.py")
        fixture_file = Path("/tmp/fixture.safe")
        digests = {
            gate_quality_script: "script-hash",
            output_validator: "validator-hash",
            fixture_file: "fixture-hash",
        }

        def fake_sha256_file(path: Path) -> str:
            return digests[path]

        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "GATE_QUALITY_SCRIPT",
            gate_quality_script,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "sha256_file",
            side_effect=fake_sha256_file,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "module_file_path",
            side_effect=lambda module_name: Path(f"/tmp/{module_name}.py"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "gate_quality_fixture_files",
            return_value=[fixture_file],
        ), mock.patch.dict(
            "sys.modules",
            {
                "run_pr0697_gate_quality": mock.Mock(
                    EXPECTED_TEST_MODULES=("scripts.tests.test_alpha", "scripts.tests.test_beta"),
                    OUTPUT_CONTRACT_FIXTURES=Path("/tmp/fixtures"),
                    OUTPUT_VALIDATOR=output_validator,
                )
            },
        ):
            digests[Path("/tmp/scripts.tests.test_alpha.py")] = "alpha-hash"
            digests[Path("/tmp/scripts.tests.test_beta.py")] = "beta-hash"
            self.assertEqual(
                run_pr0699_build_reproducibility.compute_gate_quality_input_hash(),
                run_pr0699_build_reproducibility.sha256_text(
                    "".join(
                        [
                            "script-hash",
                            run_pr0699_build_reproducibility.sha256_text(
                                "scripts.tests.test_alpha\nscripts.tests.test_beta"
                            ),
                            "alpha-hash",
                            "beta-hash",
                            "validator-hash",
                            "fixture-hash",
                        ]
                    )
                ),
            )

    def test_generate_report_runs_child_gates_after_binary_skip(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "gate",
            "repeat_sha256": "gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value=None,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "same-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value="gate-input-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, gate_quality, legacy_cleanup],
        ) as gate_mock, mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )

        self.assertEqual(gate_mock.call_count, 3)
        self.assertEqual(report["safec_binary_sha256"], "same-hash")
        self.assertEqual(
            report["child_gate_input_hashes"],
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "gate-input-hash"},
        )
        self.assertEqual(report["build_reproducibility"], {"binary_deterministic": True})

    def test_generate_report_local_preserves_prior_host_sensitive_fields(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "gate",
            "repeat_sha256": "gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value={
                "safec_binary_sha256": "prior-binary-hash",
                "child_gate_input_hashes": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "prior-gate-hash"
                },
            },
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "observed-binary-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value="observed-gate-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, gate_quality, legacy_cleanup],
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                authority="local",
                env={},
            )

        self.assertEqual(report["safec_binary_sha256"], "prior-binary-hash")
        self.assertEqual(
            report["child_gate_input_hashes"],
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "prior-gate-hash"},
        )

    def test_generate_report_reuses_pipeline_frontend_smoke_result(self) -> None:
        gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "gate",
            "repeat_sha256": "gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        pipeline_input = {
            "frontend_smoke": {
                "result": {
                    "command": [
                        "python3",
                        "scripts/run_frontend_smoke.py",
                        "--report",
                        "$TMPDIR/execution/reports/pr00-pr04-frontend-smoke.json",
                    ],
                    "cwd": "$REPO_ROOT",
                    "returncode": 0,
                    "stdout": "frontend smoke: OK ($TMPDIR/execution/reports/pr00-pr04-frontend-smoke.json)\n",
                    "stderr": "",
                },
                "report": {
                    "deterministic": True,
                    "report_sha256": "frontend",
                    "repeat_sha256": "frontend",
                },
            }
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value=None,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "same-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value="gate-input-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_gate_quality_result",
            return_value=gate_quality,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            return_value=legacy_cleanup,
        ) as gate_mock:
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
                pipeline_input=pipeline_input,
            )

        gate_mock.assert_called_once_with(
            python="python3",
            script=run_pr0699_build_reproducibility.LEGACY_CLEANUP_SCRIPT,
            report_path=run_pr0699_build_reproducibility.LEGACY_CLEANUP_REPORT,
            generated_root=None,
            env={},
        )
        self.assertEqual(
            report["delegated_reports"]["frontend_smoke"],
            {
                "run": {
                    "command": ["python3", "scripts/run_frontend_smoke.py"],
                    "cwd": "$REPO_ROOT",
                    "returncode": 0,
                    "stdout": "frontend smoke: OK (execution/reports/pr00-pr04-frontend-smoke.json)\n",
                    "stderr": "",
                },
                "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
                "report_sha256": "frontend",
                "repeat_sha256": "frontend",
                "binary_deterministic": True,
            },
        )

    def test_gate_quality_skipped_when_input_hash_matches(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        prior_gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "cached-gate",
            "repeat_sha256": "cached-gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value={
                "child_gate_input_hashes": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "same-hash"
                },
                "delegated_reports": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: prior_gate_quality
                },
            },
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "binary-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value="same-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, legacy_cleanup],
        ) as gate_mock, mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )

        self.assertEqual(gate_mock.call_count, 2)
        self.assertEqual(
            report["delegated_reports"][run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME],
            prior_gate_quality,
        )
        self.assertEqual(
            report["child_gate_input_hashes"],
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "same-hash"},
        )

    def test_gate_quality_reruns_when_gate_quality_script_hash_changes(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "new-gate",
            "repeat_sha256": "new-gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value={
                "child_gate_input_hashes": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "old-hash"
                },
                "delegated_reports": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: {"report_sha256": "cached"}
                },
            },
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "binary-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value="new-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, gate_quality, legacy_cleanup],
        ) as gate_mock, mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )

        self.assertEqual(gate_mock.call_count, 3)
        self.assertEqual(
            report["delegated_reports"][run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME],
            gate_quality,
        )
        self.assertEqual(
            report["child_gate_input_hashes"],
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "new-hash"},
        )

    def test_gate_quality_reruns_when_binary_hash_changes(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "new-gate",
            "repeat_sha256": "new-gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value={
                "child_gate_input_hashes": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "old-hash"
                },
                "delegated_reports": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: {"report_sha256": "cached"}
                },
            },
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "new-binary-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value="binary-derived-hash",
        ) as hash_mock, mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, gate_quality, legacy_cleanup],
        ) as gate_mock, mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )

        hash_mock.assert_called_once_with()
        self.assertEqual(gate_mock.call_count, 3)
        self.assertEqual(
            report["child_gate_input_hashes"],
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "binary-derived-hash"},
        )

    def test_gate_quality_reruns_when_prior_report_missing_child_input_hashes(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "gate",
            "repeat_sha256": "gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value={"delegated_reports": {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: {}}},
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "binary-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value="current-hash",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, gate_quality, legacy_cleanup],
        ) as gate_mock, mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )

        self.assertEqual(gate_mock.call_count, 3)
        self.assertEqual(
            report["delegated_reports"][run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME],
            gate_quality,
        )

    def test_child_gate_input_hashes_recorded_on_full_run(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        gate_quality = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0697-gate-quality-report.json",
            "report_sha256": "gate",
            "repeat_sha256": "gate",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        full_hash = "a" * 64
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value=None,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "binary-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value=full_hash,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, gate_quality, legacy_cleanup],
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )

        self.assertEqual(
            report["child_gate_input_hashes"],
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: full_hash},
        )
        self.assertEqual(len(report["child_gate_input_hashes"][run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME]), 64)

    def test_child_gate_input_hashes_recorded_on_cached_run(self) -> None:
        frontend_smoke = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr00-pr04-frontend-smoke.json",
            "report_sha256": "frontend",
            "repeat_sha256": "frontend",
        }
        legacy_cleanup = {
            "run": {"returncode": 0},
            "report_path": "execution/reports/pr0698-legacy-package-cleanup-report.json",
            "report_sha256": "legacy",
            "repeat_sha256": "legacy",
        }
        cached_hash = "b" * 64
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_prior_report",
            return_value={
                "child_gate_input_hashes": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: cached_hash
                },
                "delegated_reports": {
                    run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: {"report_sha256": "cached"}
                },
            },
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_build_reproducibility",
            return_value=({"binary_deterministic": True}, "binary-hash"),
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "compute_gate_quality_input_hash",
            return_value=cached_hash,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "require_repo_command",
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
            side_effect=[frontend_smoke, legacy_cleanup],
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            report = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )

        self.assertEqual(
            report["child_gate_input_hashes"],
            {run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: cached_hash},
        )

    def test_resolve_gate_quality_result_quiet_by_default(self) -> None:
        stdout = io.StringIO()
        with mock.patch.object(
            run_pr0699_build_reproducibility,
            "run_gate_script",
        ), mock.patch.object(
            run_pr0699_build_reproducibility.time,
            "monotonic",
            side_effect=[30.0, 30.1],
        ), redirect_stdout(stdout):
            run_pr0699_build_reproducibility.resolve_gate_quality_result(
                python="python3",
                generated_root=None,
                env={},
                prior_report={
                    "child_gate_input_hashes": {
                        run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: "cached-hash"
                    },
                    "delegated_reports": {
                        run_pr0699_build_reproducibility.GATE_QUALITY_CHILD_NAME: {"report_sha256": "cached"}
                    },
                },
                gate_quality_input_hash="cached-hash",
            )

        self.assertEqual(stdout.getvalue(), "")

    def test_pipeline_frontend_smoke_emits_reuse_log_in_verbose_mode(self) -> None:
        pipeline_input = {
            "frontend_smoke": {
                "result": {
                    "command": [
                        "python3",
                        "scripts/run_frontend_smoke.py",
                        "--report",
                        "$TMPDIR/execution/reports/pr00-pr04-frontend-smoke.json",
                    ],
                    "cwd": "$REPO_ROOT",
                    "returncode": 0,
                    "stdout": "frontend smoke: OK ($TMPDIR/execution/reports/pr00-pr04-frontend-smoke.json)\n",
                    "stderr": "",
                },
                "report": {
                    "deterministic": True,
                    "report_sha256": "frontend",
                    "repeat_sha256": "frontend",
                },
            }
        }
        stdout = io.StringIO()

        with redirect_stdout(stdout):
            result = run_pr0699_build_reproducibility.resolve_frontend_smoke_result(
                python="python3",
                generated_root=None,
                env={},
                pipeline_input=pipeline_input,
                verbose=True,
            )

        self.assertTrue(result["binary_deterministic"])
        self.assertEqual(stdout.getvalue(), "[pr0699] reusing pipeline frontend_smoke result\n")

    def test_main_passes_authority_to_execution_state_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "pr0699-report.json"
            run_calls: list[list[str]] = []

            def fake_run(argv: list[str], **_kwargs: object) -> dict[str, object]:
                run_calls.append(list(argv))
                return {
                    "command": list(argv),
                    "cwd": "$REPO_ROOT",
                    "returncode": 0,
                    "stdout": "",
                    "stderr": "",
                }

            with mock.patch.object(
                sys,
                "argv",
                [
                    "run_pr0699_build_reproducibility.py",
                    "--report",
                    str(report_path),
                    "--authority",
                    "ci",
                ],
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "find_command",
                side_effect=lambda name, *alts: name,
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "ensure_sdkroot",
                side_effect=lambda env: env,
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "finalize_deterministic_report",
                return_value={},
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "write_report",
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "current_dirty_report_paths",
                side_effect=[[], []],
            ), mock.patch.object(
                run_pr0699_build_reproducibility,
                "run",
                side_effect=fake_run,
            ):
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(run_pr0699_build_reproducibility.main(), 0)

        self.assertIn(
            [
                "python3",
                str(run_pr0699_build_reproducibility.VALIDATE_EXECUTION_STATE),
                "--authority",
                "ci",
            ],
            run_calls,
        )


if __name__ == "__main__":
    unittest.main()
