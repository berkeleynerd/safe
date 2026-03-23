from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from _lib import pr101_verification


class Pr101VerificationTests(unittest.TestCase):
    def test_run_verification_prepends_alire_bin_when_gnatprove_is_fallback_only(self) -> None:
        calls: list[tuple[list[str], dict[str, str]]] = []

        def fake_run(argv: list[str], **kwargs: object) -> dict[str, object]:
            calls.append((argv, dict(kwargs.get("env", {}))))
            return {
                "command": argv,
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": "",
                "stderr": "",
            }

        with mock.patch.object(pr101_verification, "find_command", side_effect=["bash", "/tmp/gnatprove"]), mock.patch.object(
            pr101_verification, "run", side_effect=fake_run
        ), mock.patch.object(
            pr101_verification, "snapshot_text", return_value=None
        ), mock.patch.object(
            pr101_verification, "restore_text"
        ), mock.patch.object(
            pr101_verification, "normalized_assumptions_hash", return_value="1" * 64
        ):
            result = pr101_verification._run_verification(
                env={"PATH": "/usr/bin"},
                root=Path("/tmp/work"),
                project="companion.gpr",
            )

        self.assertEqual(calls[1][0][:4], [pr101_verification.alr_command(), "exec", "--", "gnatprove"])
        self.assertEqual(calls[2][0][:4], [pr101_verification.alr_command(), "exec", "--", "gnatprove"])
        self.assertEqual(calls[0][1]["PATH"], "/tmp:/usr/bin")
        self.assertEqual(calls[1][1]["PATH"], "/tmp:/usr/bin")
        self.assertEqual(result["flow"]["returncode"], 0)
        self.assertEqual(result["prove"]["returncode"], 0)


if __name__ == "__main__":
    unittest.main()
