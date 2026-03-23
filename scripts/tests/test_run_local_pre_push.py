from __future__ import annotations

import argparse
import io
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_local_pre_push


class RunLocalPrePushTests(unittest.TestCase):
    def test_dry_run_reports_full_verify_plan(self) -> None:
        args = argparse.Namespace(branch="codex/pr114-signature-control-flow-syntax", dry_run=True, skip_diff=False)
        stdout = io.StringIO()
        with mock.patch.object(run_local_pre_push, "parse_args", return_value=args), mock.patch.object(
            run_local_pre_push,
            "verify_pipeline",
        ) as verify_pipeline:
            with redirect_stdout(stdout):
                self.assertEqual(run_local_pre_push.main(), 0)
        self.assertIn("[pre-push] branch: codex/pr114-signature-control-flow-syntax", stdout.getvalue())
        self.assertIn("[pre-push] plan: full canonical gate pipeline verify (authority=local)", stdout.getvalue())
        verify_pipeline.assert_not_called()

    def test_main_verifies_and_checks_diff(self) -> None:
        args = argparse.Namespace(branch="codex/pr114-signature-control-flow-syntax", dry_run=False, skip_diff=False)
        with mock.patch.object(run_local_pre_push, "parse_args", return_value=args), mock.patch.object(
            run_local_pre_push,
            "ensure_sdkroot",
            side_effect=lambda env: env,
        ), mock.patch.object(
            run_local_pre_push,
            "ensure_deterministic_env",
            return_value={},
        ), mock.patch.object(
            run_local_pre_push,
            "find_command",
            side_effect=["git", "python3", "alr"],
        ), mock.patch.object(run_local_pre_push,
            "verify_pipeline",
            return_value=0,
        ) as verify_pipeline, mock.patch.object(
            run_local_pre_push,
            "run",
            return_value={
                "command": ["git", "diff", "--exit-code"],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": "",
                "stderr": "",
            },
        ) as run_command:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(run_local_pre_push.main(), 0)

        verify_pipeline.assert_called_once_with(
            authority="local",
            python="python3",
            git="git",
            alr="alr",
            env={},
        )
        run_command.assert_called_once()
        self.assertEqual(run_command.call_args.args[0], ["git", "diff", "--exit-code"])

    def test_main_skips_clean_tree_check_when_requested(self) -> None:
        args = argparse.Namespace(branch="codex/pr114-signature-control-flow-syntax", dry_run=False, skip_diff=True)
        with mock.patch.object(run_local_pre_push, "parse_args", return_value=args), mock.patch.object(
            run_local_pre_push,
            "ensure_sdkroot",
            side_effect=lambda env: env,
        ), mock.patch.object(
            run_local_pre_push,
            "ensure_deterministic_env",
            return_value={},
        ), mock.patch.object(
            run_local_pre_push,
            "find_command",
            side_effect=["git", "python3", "alr"],
        ), mock.patch.object(run_local_pre_push,
            "verify_pipeline",
            return_value=0,
        ) as verify_pipeline, mock.patch.object(
            run_local_pre_push,
            "run",
        ) as run_command:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(run_local_pre_push.main(), 0)

        verify_pipeline.assert_called_once_with(
            authority="local",
            python="python3",
            git="git",
            alr="alr",
            env={},
        )
        run_command.assert_not_called()

    def test_main_detects_current_branch_when_not_overridden(self) -> None:
        args = argparse.Namespace(branch=None, dry_run=False, skip_diff=True)
        with mock.patch.object(run_local_pre_push, "parse_args", return_value=args), mock.patch.object(
            run_local_pre_push,
            "ensure_sdkroot",
            side_effect=lambda env: env,
        ), mock.patch.object(
            run_local_pre_push,
            "ensure_deterministic_env",
            return_value={},
        ), mock.patch.object(
            run_local_pre_push,
            "find_command",
            side_effect=["git", "python3", "alr"],
        ), mock.patch.object(
            run_local_pre_push,
            "current_branch",
            return_value="codex/pr114-signature-control-flow-syntax",
        ) as current_branch, mock.patch.object(run_local_pre_push,
            "verify_pipeline",
            return_value=0,
        ) as verify_pipeline:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(run_local_pre_push.main(), 0)
        current_branch.assert_called_once()
        verify_pipeline.assert_called_once_with(
            authority="local",
            python="python3",
            git="git",
            alr="alr",
            env={},
        )

    def test_main_verifies_full_pipeline_even_without_branch_plan(self) -> None:
        args = argparse.Namespace(branch="codex/misc-cleanup", dry_run=False, skip_diff=False)
        stdout = io.StringIO()
        with mock.patch.object(run_local_pre_push, "parse_args", return_value=args), mock.patch.object(
            run_local_pre_push,
            "ensure_sdkroot",
            side_effect=lambda env: env,
        ), mock.patch.object(
            run_local_pre_push,
            "ensure_deterministic_env",
            return_value={},
        ), mock.patch.object(
            run_local_pre_push,
            "find_command",
            side_effect=["git", "python3", "alr"],
        ), mock.patch.object(run_local_pre_push,
            "verify_pipeline",
            return_value=0,
        ) as verify_pipeline, mock.patch.object(
            run_local_pre_push,
            "run",
            return_value={
                "command": ["git", "diff", "--exit-code"],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": "",
                "stderr": "",
            },
        ) as run_command:
            with redirect_stdout(stdout):
                self.assertEqual(run_local_pre_push.main(), 0)
        self.assertIn("[pre-push] branch: codex/misc-cleanup", stdout.getvalue())
        verify_pipeline.assert_called_once_with(
            authority="local",
            python="python3",
            git="git",
            alr="alr",
            env={},
        )
        run_command.assert_called_once()


if __name__ == "__main__":
    unittest.main()
