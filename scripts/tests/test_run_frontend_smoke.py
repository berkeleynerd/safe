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

import run_frontend_smoke


class RunFrontendSmokeTests(unittest.TestCase):
    def test_load_prior_report_prefers_requested_report_when_present(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            requested = temp_root / "requested.json"
            default = temp_root / "default.json"
            requested.write_text(json.dumps({"task": "requested"}), encoding="utf-8")
            default.write_text(json.dumps({"task": "default"}), encoding="utf-8")

            with mock.patch.object(run_frontend_smoke, "DEFAULT_REPORT", default):
                report = run_frontend_smoke.load_prior_report(report_path=requested)

        self.assertEqual(report, {"task": "requested"})

    def test_load_prior_report_falls_back_to_default_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            requested = temp_root / "missing.json"
            default = temp_root / "default.json"
            default.write_text(json.dumps({"task": "default"}), encoding="utf-8")

            with mock.patch.object(run_frontend_smoke, "DEFAULT_REPORT", default):
                report = run_frontend_smoke.load_prior_report(report_path=requested)

        self.assertEqual(report, {"task": "default"})

    def test_load_prior_report_returns_none_when_no_candidate_exists(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            requested = temp_root / "missing.json"
            default = temp_root / "default.json"

            with mock.patch.object(run_frontend_smoke, "DEFAULT_REPORT", default):
                report = run_frontend_smoke.load_prior_report(report_path=requested)

        self.assertIsNone(report)

    def test_resolve_build_reuses_prior_report_when_hash_matches(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            prior_build = {
                "command": ["alr", "build"],
                "cwd": "$REPO_ROOT/compiler_impl",
                "returncodes": [0, 0],
                "binary_path": "compiler_impl/bin/safec",
                "binary_deterministic": True,
                "build_input_hash": "same-hash",
            }
            build_cache: dict[str, object] = {}

            with mock.patch.object(
                run_frontend_smoke,
                "compute_build_input_hash",
                return_value="same-hash",
            ), mock.patch.object(
                run_frontend_smoke,
                "stable_binary_sha256",
                side_effect=["current-hash", "current-hash"],
            ), mock.patch.object(
                run_frontend_smoke,
                "clean_frontend_build_outputs",
            ), mock.patch.object(
                run_frontend_smoke,
                "build_frontend",
                return_value={"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
            ) as build_mock, mock.patch.object(
                run_frontend_smoke,
                "require_repo_command",
            ):
                resolved = run_frontend_smoke.resolve_build(
                    alr="alr",
                    safec=safec,
                    prior_report={"build": prior_build},
                    build_cache=build_cache,
                    env={},
                )

        build_mock.assert_called_once()
        self.assertEqual(resolved, prior_build)
        self.assertEqual(build_cache["build"], prior_build)
        self.assertEqual(build_cache["binary_sha256"], "current-hash")

    def test_resolve_build_reuses_in_process_cache_when_hash_matches(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            cached_build = {
                "command": ["alr", "build"],
                "cwd": "$REPO_ROOT/compiler_impl",
                "returncodes": [0, 0],
                "binary_path": "compiler_impl/bin/safec",
                "binary_deterministic": True,
                "build_input_hash": "same-hash",
            }

            with mock.patch.object(
                run_frontend_smoke,
                "compute_build_input_hash",
                return_value="same-hash",
            ), mock.patch.object(
                run_frontend_smoke,
                "stable_binary_sha256",
                return_value="cached-hash",
            ), mock.patch.object(
                run_frontend_smoke,
                "build_frontend",
            ) as build_mock:
                resolved = run_frontend_smoke.resolve_build(
                    alr="alr",
                    safec=safec,
                    prior_report=None,
                    build_cache={"build": cached_build, "binary_sha256": "cached-hash"},
                    env={},
                )

        build_mock.assert_not_called()
        self.assertEqual(resolved, cached_build)

    def test_resolve_build_falls_back_when_prior_report_missing_binary_sha256(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            build_cache: dict[str, object] = {}

            with mock.patch.object(
                run_frontend_smoke,
                "compute_build_input_hash",
                return_value="build-input-hash",
            ), mock.patch.object(
                run_frontend_smoke,
                "clean_frontend_build_outputs",
            ), mock.patch.object(
                run_frontend_smoke,
                "build_frontend",
                side_effect=[
                    {"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
                    {"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
                ],
            ) as build_mock, mock.patch.object(
                run_frontend_smoke,
                "require_repo_command",
            ), mock.patch.object(
                run_frontend_smoke,
                "stable_binary_sha256",
                side_effect=["proved-hash", "proved-hash"],
            ):
                resolved = run_frontend_smoke.resolve_build(
                    alr="alr",
                    safec=safec,
                    prior_report={"build": {"binary_deterministic": True}},
                    build_cache=build_cache,
                    env={},
                )

        self.assertEqual(build_mock.call_count, 2)
        self.assertEqual(resolved["build_input_hash"], "build-input-hash")
        self.assertEqual(resolved["returncodes"], [0, 0])
        self.assertEqual(build_cache["build"], resolved)
        self.assertEqual(build_cache["binary_sha256"], "proved-hash")

    def test_resolve_build_caches_proven_build_for_second_call(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            build_cache: dict[str, object] = {}

            with mock.patch.object(
                run_frontend_smoke,
                "compute_build_input_hash",
                return_value="build-input-hash",
            ), mock.patch.object(
                run_frontend_smoke,
                "clean_frontend_build_outputs",
            ), mock.patch.object(
                run_frontend_smoke,
                "build_frontend",
                side_effect=[
                    {"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
                    {"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
                ],
            ) as build_mock, mock.patch.object(
                run_frontend_smoke,
                "require_repo_command",
            ), mock.patch.object(
                run_frontend_smoke,
                "stable_binary_sha256",
                side_effect=["proved-hash", "proved-hash", "proved-hash"],
            ):
                first = run_frontend_smoke.resolve_build(
                    alr="alr",
                    safec=safec,
                    prior_report=None,
                    build_cache=build_cache,
                    env={},
                )
                safec.write_bytes(b"binary")
                second = run_frontend_smoke.resolve_build(
                    alr="alr",
                    safec=safec,
                    prior_report=None,
                    build_cache=build_cache,
                    env={},
                )

        self.assertEqual(build_mock.call_count, 2)
        self.assertEqual(first["build_input_hash"], "build-input-hash")
        self.assertEqual(second, first)

    def test_resolve_build_rebuilds_when_prior_report_validation_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            prior_build = {
                "command": ["alr", "build"],
                "cwd": "$REPO_ROOT/compiler_impl",
                "returncodes": [0, 0],
                "binary_path": "compiler_impl/bin/safec",
                "binary_deterministic": True,
                "build_input_hash": "same-hash",
            }
            build_cache: dict[str, object] = {}

            with mock.patch.object(
                run_frontend_smoke,
                "compute_build_input_hash",
                return_value="same-hash",
            ), mock.patch.object(
                run_frontend_smoke,
                "clean_frontend_build_outputs",
            ), mock.patch.object(
                run_frontend_smoke,
                "build_frontend",
                side_effect=[
                    {"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
                    {"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
                ],
            ) as build_mock, mock.patch.object(
                run_frontend_smoke,
                "require_repo_command",
            ), mock.patch.object(
                run_frontend_smoke,
                "stable_binary_sha256",
                side_effect=["current-hash", "rebuilt-hash", "rebuilt-hash"],
            ):
                resolved = run_frontend_smoke.resolve_build(
                    alr="alr",
                    safec=safec,
                    prior_report={"build": prior_build},
                    build_cache=build_cache,
                    env={},
                )

        self.assertEqual(build_mock.call_count, 2)
        self.assertEqual(resolved["build_input_hash"], "same-hash")
        self.assertEqual(build_cache["build"], resolved)
        self.assertEqual(build_cache["binary_sha256"], "rebuilt-hash")

    def test_resolve_build_emits_skip_log_in_verbose_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            safec = Path(temp_dir) / "safec"
            safec.write_bytes(b"binary")
            prior_build = {
                "command": ["alr", "build"],
                "cwd": "$REPO_ROOT/compiler_impl",
                "returncodes": [0, 0],
                "binary_path": "compiler_impl/bin/safec",
                "binary_deterministic": True,
                "build_input_hash": "same-hash",
            }
            stdout = io.StringIO()

            with mock.patch.object(
                run_frontend_smoke,
                "compute_build_input_hash",
                return_value="same-hash",
            ), mock.patch.object(
                run_frontend_smoke,
                "stable_binary_sha256",
                side_effect=["current-hash", "current-hash"],
            ), mock.patch.object(
                run_frontend_smoke,
                "clean_frontend_build_outputs",
            ), mock.patch.object(
                run_frontend_smoke,
                "build_frontend",
                return_value={"command": ["alr", "build"], "cwd": "$REPO_ROOT/compiler_impl", "returncode": 0},
            ), mock.patch.object(
                run_frontend_smoke,
                "require_repo_command",
            ), mock.patch.object(
                run_frontend_smoke.time,
                "monotonic",
                side_effect=[10.0, 10.2, 10.8, 11.0],
            ), redirect_stdout(stdout):
                run_frontend_smoke.resolve_build(
                    alr="alr",
                    safec=safec,
                    prior_report={"build": prior_build},
                    build_cache={},
                    env={},
                    verbose=True,
                )

        self.assertEqual(
            stdout.getvalue(),
            "[frontend_smoke] build inputs unchanged, validated cached build (0.6s rebuild, 1.0s total)\n",
        )


if __name__ == "__main__":
    unittest.main()
