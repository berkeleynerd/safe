from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
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

    def test_normalize_argv_rewrites_equals_style_absolute_paths(self) -> None:
        temp_root = Path("/tmp/example-root")
        argv = [
            f"-gnatec={temp_root / 'ada' / 'gnat.adc'}",
            f"--report={hc.REPO_ROOT / 'execution' / 'reports' / 'sample.json'}",
            "--mode=prove",
        ]
        self.assertEqual(
            hc.normalize_argv(argv, temp_root=temp_root),
            [
                "-gnatec=$TMPDIR/ada/gnat.adc",
                "--report=execution/reports/sample.json",
                "--mode=prove",
            ],
        )

    def test_find_command_uses_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            fallback = Path(temp_dir) / "fake-tool"
            fallback.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            fallback.chmod(0o755)
            self.assertEqual(hc.find_command("clearly-missing-tool", fallback), str(fallback))

    def test_find_command_returns_name_for_path_discovered_tool(self) -> None:
        self.assertEqual(hc.find_command("sh"), "sh")

    def test_compiler_build_argv_uses_default_parallel_gprbuild(self) -> None:
        self.assertEqual(
            hc.compiler_build_argv("alr"),
            ["alr", "build", "--", "-j0", "-p"],
        )

    def test_ensure_deterministic_env_overrides_conflicting_values(self) -> None:
        env = {
            "PYTHONHASHSEED": "123",
            "LC_ALL": "en_US.UTF-8",
            "TZ": "America/New_York",
            "KEEP": "yes",
        }
        updated = hc.ensure_deterministic_env(env)
        self.assertEqual(updated["PYTHONHASHSEED"], "0")
        self.assertEqual(updated["LC_ALL"], "C.UTF-8")
        self.assertEqual(updated["TZ"], "UTC")
        self.assertEqual(updated["KEEP"], "yes")

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

    def test_run_capture_returns_stdout_stderr_and_returncode_without_raising(self) -> None:
        completed = hc.run_capture(
            [
                sys.executable,
                "-c",
                "import sys; print('hello'); print('warn', file=sys.stderr); sys.exit(3)",
            ],
            cwd=hc.REPO_ROOT,
        )
        self.assertEqual(completed.returncode, 3)
        self.assertEqual(completed.stdout, "hello\n")
        self.assertEqual(completed.stderr, "warn\n")

    def test_run_passthrough_returns_process_exit_code(self) -> None:
        exit_code = hc.run_passthrough(
            [sys.executable, "-c", "import sys; sys.exit(5)"],
            cwd=hc.REPO_ROOT,
        )
        self.assertEqual(exit_code, 5)

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

    def test_finalize_deterministic_report_adds_hashes(self) -> None:
        report = hc.finalize_deterministic_report(
            lambda: {"task": "PR06.9.X", "status": "ok"},
            label="test",
        )
        self.assertTrue(report["deterministic"])
        self.assertEqual(report["report_sha256"], report["repeat_sha256"])
        self.assertNotIn("tool_versions", report)

    def test_finalize_deterministic_report_rejects_drift(self) -> None:
        counter = {"value": 0}

        def generator() -> dict[str, int]:
            counter["value"] += 1
            return {"value": counter["value"]}

        with self.assertRaises(RuntimeError):
            hc.finalize_deterministic_report(generator, label="drift")

    def test_strip_transport_only_switches_removes_transport_args(self) -> None:
        self.assertEqual(
            hc.strip_transport_only_switches(
                [
                    "python3",
                    "scripts/sample.py",
                    "--authority",
                    "ci",
                    "--pipeline-input",
                    "/tmp/pipeline.json",
                    "--generated-root=/tmp/stage",
                    "--scratch-root",
                    "/tmp/scratch",
                    "--generated-output-baseline-file",
                    "/tmp/baseline.txt",
                    "--report",
                    "/tmp/report.json",
                    "--mode=prove",
                ]
            ),
            ["python3", "scripts/sample.py", "--mode=prove"],
        )

    def test_canonicalize_serialized_child_result_preserves_stable_fields(self) -> None:
        canonical = hc.canonicalize_serialized_child_result(
            {
                "command": [
                    "python3",
                    "scripts/sample.py",
                    "--report",
                    "/tmp/report.json",
                    "--authority",
                    "local",
                ],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": "wrote /tmp/report.json\n",
            },
            committed_report_path=Path("execution/reports/sample-report.json"),
        )
        self.assertEqual(canonical["command"], ["python3", "scripts/sample.py"])
        self.assertEqual(canonical["cwd"], "$REPO_ROOT")
        self.assertEqual(canonical["returncode"], 0)
        self.assertEqual(
            canonical["stdout"],
            "wrote execution/reports/sample-report.json\n",
        )

    def test_stable_emitted_artifact_sha256_normalizes_repo_paths_in_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            artifact = temp_root / "sample.mir.json"
            artifact.write_text(
                (
                    "{"
                    f"\"source_path\":\"{hc.REPO_ROOT / 'tests/positive/rule4_conditional.safe'}\""
                    "}"
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                hc.stable_emitted_artifact_sha256(artifact, temp_root=temp_root),
                hc.sha256_text('{"source_path":"$REPO_ROOT/tests/positive/rule4_conditional.safe"}'),
            )

    def test_managed_scratch_root_clears_supplied_root_between_uses(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            scratch_root = Path(temp_dir) / "scratch"
            scratch_root.mkdir()
            (scratch_root / "stale.txt").write_text("stale\n", encoding="utf-8")
            with hc.managed_scratch_root(scratch_root=scratch_root, prefix="unused-") as managed:
                self.assertEqual(managed, scratch_root)
                self.assertFalse((managed / "stale.txt").exists())
                (managed / "fresh.txt").write_text("fresh\n", encoding="utf-8")
            with hc.managed_scratch_root(scratch_root=scratch_root, prefix="unused-") as managed:
                self.assertFalse((managed / "fresh.txt").exists())

    def test_managed_scratch_root_rejects_repository_root(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "scratch root must not be the repository root"):
            with hc.managed_scratch_root(scratch_root=hc.REPO_ROOT, prefix="unused-"):
                self.fail("managed_scratch_root unexpectedly yielded the repository root")

    def test_managed_scratch_root_rejects_non_temp_root(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "scratch root must live under"):
            with hc.managed_scratch_root(scratch_root=Path("/home/non-temp-scratch"), prefix="unused-"):
                self.fail("managed_scratch_root unexpectedly yielded a non-temp scratch root")

    def test_rerun_report_gate_and_compare_returns_stable_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            script = temp_root / "sample_gate.py"
            report_path = temp_root / "sample-report.json"
            compare_root = temp_root / "rerun"
            compare_root.mkdir()
            script.write_text(
                textwrap.dedent(
                    """
                    from pathlib import Path
                    import argparse
                    import sys

                    SCRIPTS_DIR = Path(__SCRIPTS_DIR__)
                    if str(SCRIPTS_DIR) not in sys.path:
                        sys.path.insert(0, str(SCRIPTS_DIR))

                    from _lib.harness_common import finalize_deterministic_report, write_report

                    parser = argparse.ArgumentParser()
                    parser.add_argument("--report", type=Path, required=True)
                    args = parser.parse_args()
                    report = finalize_deterministic_report(
                        lambda: {"task": "sample", "status": "ok"},
                        label="sample",
                    )
                    write_report(args.report, report)
                    """
                ).replace("__SCRIPTS_DIR__", repr(str(hc.REPO_ROOT / "scripts"))).strip()
                + "\n",
                encoding="utf-8",
            )
            subprocess.run(
                [sys.executable, str(script), "--report", str(report_path)],
                check=True,
                cwd=hc.REPO_ROOT,
            )
            metadata = hc.rerun_report_gate_and_compare(
                python=sys.executable,
                script=script,
                committed_report_path=report_path,
                cwd=hc.REPO_ROOT,
                temp_root=compare_root,
            )
            self.assertEqual(metadata["script"], str(script))
            self.assertEqual(metadata["committed_report_path"], str(report_path))
            self.assertTrue(metadata["matches_committed_report"])
            self.assertEqual(metadata["rerun"]["returncode"], 0)
            self.assertEqual(metadata["rerun"]["command"], ["python3", "sample_gate.py"])

    def test_reference_committed_report_returns_stable_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            report_path = temp_root / "sample-report.json"
            report = hc.finalize_deterministic_report(
                lambda: {"task": "sample", "status": "ok"},
                label="sample report",
            )
            hc.write_report(report_path, report)

            metadata = hc.reference_committed_report(
                script=temp_root / "sample_gate.py",
                committed_report_path=report_path,
            )

            self.assertEqual(metadata["script"], str(temp_root / "sample_gate.py"))
            self.assertEqual(metadata["committed_report_path"], str(report_path))
            self.assertTrue(metadata["matches_committed_report"])

    def test_reference_committed_report_can_attach_synthetic_rerun(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            report_path = temp_root / "sample-report.json"
            report = hc.finalize_deterministic_report(
                lambda: {"task": "sample", "status": "ok"},
                label="sample report",
            )
            hc.write_report(report_path, report)

            metadata = hc.reference_committed_report(
                script=temp_root / "sample_gate.py",
                committed_report_path=report_path,
                python="python3",
            )

            self.assertEqual(
                metadata["rerun"]["command"],
                ["python3", str(temp_root / "sample_gate.py")],
            )
            self.assertEqual(metadata["rerun"]["cwd"], "$REPO_ROOT")
            self.assertEqual(metadata["rerun"]["returncode"], 0)

    def test_ensure_sdkroot_is_a_noop_for_existing_value(self) -> None:
        env = {"SDKROOT": "/tmp/sdk"}
        self.assertEqual(hc.ensure_sdkroot(env, platform_name="darwin"), env)

    def test_ensure_sdkroot_is_a_noop_without_sdkroot(self) -> None:
        env = {"PATH": "/usr/bin"}
        self.assertEqual(hc.ensure_sdkroot(env, platform_name="darwin"), env)


if __name__ == "__main__":
    unittest.main()
