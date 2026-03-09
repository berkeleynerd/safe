from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from _lib import harness_common as hc


class HarnessCommonTests(unittest.TestCase):
    def test_normalize_text_rewrites_repo_and_temp_roots(self) -> None:
        temp_root = Path("/tmp/example-root")
        original = f"{hc.REPO_ROOT}/alpha {temp_root}/beta"
        self.assertEqual(hc.normalize_text(original, temp_root=temp_root), "$REPO_ROOT/alpha $TMPDIR/beta")

    def test_normalize_argv_rewrites_absolute_paths(self) -> None:
        temp_root = Path("/tmp/example-root")
        argv = [
            str(hc.REPO_ROOT / "scripts" / "run_frontend_smoke.py"),
            str(temp_root / "out" / "result.json"),
            "--flag",
        ]
        self.assertEqual(
            hc.normalize_argv(argv, temp_root=temp_root),
            ["scripts/run_frontend_smoke.py", "$TMPDIR/out/result.json", "--flag"],
        )

    def test_find_command_uses_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            fallback = Path(temp_dir) / "fake-tool"
            fallback.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            fallback.chmod(0o755)
            self.assertEqual(hc.find_command("clearly-missing-tool", fallback), str(fallback))

    def test_run_enforces_return_code_and_captures_stdout_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            stdout_path = temp_root / "stdout.txt"
            result = hc.run(
                [
                    sys.executable,
                    "-c",
                    "print('hello'); import sys; print('warn', file=sys.stderr)",
                ],
                cwd=hc.REPO_ROOT,
                stdout_path=stdout_path,
                temp_root=temp_root,
            )
            self.assertEqual(result["stdout"], "hello\n")
            self.assertEqual(result["stderr"], "warn\n")
            self.assertEqual(stdout_path.read_text(encoding="utf-8"), "hello\n")

            with self.assertRaises(RuntimeError):
                hc.run(
                    [sys.executable, "-c", "import sys; sys.exit(2)"],
                    cwd=hc.REPO_ROOT,
                    temp_root=temp_root,
                )

    def test_read_diag_json_checks_format(self) -> None:
        payload = hc.read_diag_json(
            json.dumps({"format": "diagnostics-v0", "diagnostics": []}),
            "ok-case",
        )
        self.assertEqual(payload["format"], "diagnostics-v0")
        with self.assertRaises(RuntimeError):
            hc.read_diag_json(json.dumps({"format": "wrong", "diagnostics": []}), "bad-case")

    def test_serialize_and_write_report_are_stable(self) -> None:
        report = {"b": 2, "a": 1}
        serialized = hc.serialize_report(report)
        self.assertEqual(serialized, '{\n  "a": 1,\n  "b": 2\n}\n')
        self.assertEqual(hc.sha256_text(serialized), hc.sha256_text(serialized))
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "reports" / "sample.json"
            hc.write_report(path, report)
            self.assertEqual(path.read_text(encoding="utf-8"), serialized)

    def test_display_path_prefers_repo_relative(self) -> None:
        inside = hc.REPO_ROOT / "scripts" / "run_frontend_smoke.py"
        outside = Path("/tmp/report.json")
        self.assertEqual(hc.display_path(inside), "scripts/run_frontend_smoke.py")
        self.assertEqual(hc.display_path(outside), "/tmp/report.json")


if __name__ == "__main__":
    unittest.main()
