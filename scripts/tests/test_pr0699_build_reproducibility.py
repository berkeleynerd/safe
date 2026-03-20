from __future__ import annotations

import io
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
