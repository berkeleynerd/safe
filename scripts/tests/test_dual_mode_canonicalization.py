from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr08_frontend_baseline
import run_pr0699_build_reproducibility
import run_pr06910_portability_environment
import run_pr06911_glue_script_safety
import run_pr06913_documentation_architecture_clarity
import run_pr101_comprehensive_audit
from _lib import harness_common as hc
from _lib.gate_manifest import NODES


CANONICALIZED_DUAL_MODE_NODES = {
    "pr0699_build_reproducibility",
    "pr06910_portability_environment",
    "pr06911_glue_script_safety",
    "pr06913_documentation_architecture_clarity",
    "pr101_comprehensive_audit",
}
AUDIT_ONLY_DUAL_MODE_NODES = {
    "validate_execution_state_final",
}


class DualModeCanonicalizationTests(unittest.TestCase):
    def test_strip_transport_only_switches_removes_all_transport_args(self) -> None:
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
                    "--timeout=120",
                ]
            ),
            [
                "python3",
                "scripts/sample.py",
                "--mode=prove",
                "--timeout=120",
            ],
        )

    def test_strip_transport_only_switches_handles_repeated_transport_args(self) -> None:
        self.assertEqual(
            hc.strip_transport_only_switches(
                [
                    "python3",
                    "scripts/sample.py",
                    "--report",
                    "/tmp/first.json",
                    "--report=/tmp/second.json",
                    "--authority",
                    "local",
                    "--authority",
                    "ci",
                ]
            ),
            ["python3", "scripts/sample.py"],
        )

    def test_dual_mode_surface_is_explicitly_audited(self) -> None:
        dual_mode_nodes = {
            node.id
            for node in NODES
            if node.supports_pipeline_input or node.supports_generated_root
        }
        self.assertEqual(
            dual_mode_nodes,
            CANONICALIZED_DUAL_MODE_NODES | AUDIT_ONLY_DUAL_MODE_NODES,
        )

    def test_pr08_standalone_and_pipeline_subgates_share_canonical_bytes(self) -> None:
        def fake_run(argv: list[str], *, cwd: Path, **_kwargs: object) -> dict[str, object]:
            script = Path(str(argv[1])).name
            report_path = hc.display_path(run_pr08_frontend_baseline.SUBGATE_REPORTS[script])
            return {
                "command": ["python3", f"scripts/{script}"],
                "cwd": "$REPO_ROOT",
                "returncode": 0,
                "stdout": f"{script}: ok ({report_path})\n",
                "stderr": "",
            }

        with mock.patch.object(run_pr08_frontend_baseline, "run", side_effect=fake_run):
            standalone = run_pr08_frontend_baseline.run_subgates(python="python3")
        pipeline = run_pr08_frontend_baseline.pipeline_subgates(
            pipeline_input={
                node_id: {
                    "result": {
                        "command": [
                            "python3",
                            f"scripts/{script_name}",
                            "--pipeline-input",
                            "$TMPDIR/pipeline.json",
                            "--generated-root",
                            "$TMPDIR/stage",
                            "--report",
                            f"$TMPDIR/{node_id}.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                        "stdout": f"{script_name}: ok ($TMPDIR/{node_id}.json)\n",
                        "stderr": "",
                    }
                }
                for script_name, node_id in run_pr08_frontend_baseline.SUBGATE_PIPELINE_IDS.items()
            }
        )
        self.assertEqual(standalone, pipeline)

    def test_pr06910_standalone_and_pipeline_reports_share_canonical_bytes(self) -> None:
        with mock.patch.object(
            run_pr06910_portability_environment,
            "environment_assumptions_report",
            return_value={
                "missing_doc_files": [],
                "doc_policy_violations": [],
                "runtime_source_violations": [],
                "portability_module_violations": [],
                "tempdir_convention_violations": [],
                "path_lookup_violations": [],
                "shell_assumption_violations": [],
            },
        ), mock.patch.object(
            run_pr06910_portability_environment,
            "require_repo_command",
        ), mock.patch.object(
            run_pr06910_portability_environment,
            "rerun_report_gate_and_compare",
            side_effect=[
                hc.reference_committed_report(
                    script=run_pr06910_portability_environment.RUNTIME_BOUNDARY_SCRIPT,
                    committed_report_path=run_pr06910_portability_environment.RUNTIME_BOUNDARY_REPORT,
                    result={
                        "command": [
                            "python3",
                            "scripts/run_pr0693_runtime_boundary.py",
                            "--report",
                            "$TMPDIR/pr0693-runtime-boundary-report.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                    },
                ),
                hc.reference_committed_report(
                    script=run_pr06910_portability_environment.NO_PYTHON_SCRIPT,
                    committed_report_path=run_pr06910_portability_environment.NO_PYTHON_REPORT,
                    result={
                        "command": [
                            "python3",
                            "scripts/run_pr068_ada_ast_emit_no_python.py",
                            "--report",
                            "$TMPDIR/pr068-ada-ast-emit-no-python-report.json",
                        ],
                        "cwd": "$REPO_ROOT",
                        "returncode": 0,
                    },
                ),
            ],
        ):
            standalone = run_pr06910_portability_environment.generate_report(
                python="python3",
                env={},
                pipeline_input={},
                generated_root=None,
            )
            pipeline = run_pr06910_portability_environment.generate_report(
                python="python3",
                env={},
                pipeline_input={
                    "pr0693_runtime_boundary": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr0693_runtime_boundary.py",
                                "--generated-root",
                                "/tmp/stage",
                                "--authority",
                                "ci",
                                "--report",
                                "$TMPDIR/pr0693-runtime-boundary-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr068_ada_ast_emit_no_python": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr068_ada_ast_emit_no_python.py",
                                "--pipeline-input",
                                "$TMPDIR/pipeline.json",
                                "--report",
                                "$TMPDIR/pr068-ada-ast-emit-no-python-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                },
                generated_root=None,
            )
        self.assertEqual(hc.serialize_report(standalone), hc.serialize_report(pipeline))

    def test_pr0699_standalone_and_pipeline_reports_share_canonical_bytes(self) -> None:
        build_reproducibility = {"binary_deterministic": True}
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
        standalone_frontend = {
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
            return_value=(build_reproducibility, "binary-hash"),
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
            side_effect=[standalone_frontend, legacy_cleanup, legacy_cleanup],
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "resolve_generated_path",
            return_value=run_pr0699_build_reproducibility.FRONTEND_SMOKE_REPORT,
        ), mock.patch.object(
            run_pr0699_build_reproducibility,
            "load_json",
            return_value={"build": {"binary_deterministic": True}},
        ):
            standalone = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
            )
            pipeline = run_pr0699_build_reproducibility.generate_report(
                python="python3",
                alr="alr",
                safec=Path("/tmp/safec"),
                generated_root=None,
                env={},
                pipeline_input=pipeline_input,
            )
        self.assertEqual(hc.serialize_report(standalone), hc.serialize_report(pipeline))

    def test_pr06911_standalone_and_pipeline_reports_share_canonical_bytes(self) -> None:
        base_glue_report = {
            "subprocess_import_violations": [],
            "subprocess_call_violations": [],
            "shell_assumption_violations": [],
            "tempdir_violations": [],
            "report_helper_violations": [],
            "command_lookup_violations": [],
            "unauthorized_safe_source_readers": [],
        }
        with mock.patch.object(
            run_pr06911_glue_script_safety,
            "glue_script_safety_report",
            return_value=base_glue_report,
        ), mock.patch.object(
            run_pr06911_glue_script_safety,
            "check_glue_script_safety",
        ), mock.patch.object(
            run_pr06911_glue_script_safety,
            "require_repo_command",
        ):
            standalone = run_pr06911_glue_script_safety.generate_report(
                python="python3",
                env={},
                pipeline_input={},
                generated_root=None,
            )
            pipeline = run_pr06911_glue_script_safety.generate_report(
                python="python3",
                env={},
                pipeline_input={
                    "pr0693_runtime_boundary": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr0693_runtime_boundary.py",
                                "--generated-root",
                                "/tmp/stage",
                                "--report",
                                "$TMPDIR/pr0693-runtime-boundary-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr0697_gate_quality": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr0697_gate_quality.py",
                                "--report",
                                "$TMPDIR/pr0697-gate-quality-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr06910_portability_environment": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr06910_portability_environment.py",
                                "--pipeline-input",
                                "$TMPDIR/pipeline.json",
                                "--authority",
                                "ci",
                                "--report",
                                "$TMPDIR/pr06910-portability-environment-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "frontend_smoke": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_frontend_smoke.py",
                                "--report",
                                "$TMPDIR/pr00-pr04-frontend-smoke.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr0699_build_reproducibility": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr0699_build_reproducibility.py",
                                "--authority",
                                "local",
                                "--report",
                                "$TMPDIR/pr0699-build-reproducibility-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                },
                generated_root=None,
            )
        self.assertEqual(hc.serialize_report(standalone), hc.serialize_report(pipeline))

    def test_pr06913_standalone_and_pipeline_reports_share_canonical_bytes(self) -> None:
        with mock.patch.object(
            run_pr06913_documentation_architecture_clarity,
            "documentation_architecture_clarity_report",
            return_value={},
        ), mock.patch.object(
            run_pr06913_documentation_architecture_clarity,
            "check_documentation_architecture_clarity",
        ):
            standalone = run_pr06913_documentation_architecture_clarity.generate_report(
                python="python3",
                pipeline_input={},
                generated_root=None,
            )
            pipeline = run_pr06913_documentation_architecture_clarity.generate_report(
                python="python3",
                pipeline_input={
                    "pr0693_runtime_boundary": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr0693_runtime_boundary.py",
                                "--report",
                                "$TMPDIR/pr0693-runtime-boundary-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr0698_legacy_package_cleanup": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr0698_legacy_package_cleanup.py",
                                "--report",
                                "$TMPDIR/pr0698-legacy-package-cleanup-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr06910_portability_environment": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr06910_portability_environment.py",
                                "--pipeline-input",
                                "$TMPDIR/pipeline.json",
                                "--generated-root",
                                "/tmp/stage",
                                "--report",
                                "$TMPDIR/pr06910-portability-environment-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr0697_gate_quality": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr0697_gate_quality.py",
                                "--report",
                                "$TMPDIR/pr0697-gate-quality-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr06911_glue_script_safety": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr06911_glue_script_safety.py",
                                "--authority",
                                "ci",
                                "--report",
                                "$TMPDIR/pr06911-glue-script-safety-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                    "pr06912_performance_scale_sanity": {
                        "result": {
                            "command": [
                                "python3",
                                "scripts/run_pr06912_performance_scale_sanity.py",
                                "--report",
                                "$TMPDIR/pr06912-performance-scale-sanity-report.json",
                            ],
                            "cwd": "$REPO_ROOT",
                            "returncode": 0,
                        }
                    },
                },
                generated_root=None,
            )
        self.assertEqual(hc.serialize_report(standalone), hc.serialize_report(pipeline))

    def test_pr101_local_reused_and_pipeline_gate_results_share_canonical_bytes(self) -> None:
        pipeline_result = run_pr101_comprehensive_audit.compact_result(
            run_pr101_comprehensive_audit.canonicalize_baseline_gate_result(
                script=Path("scripts/run_pr08_frontend_baseline.py"),
                result={
                    "command": [
                        "python3",
                        "scripts/run_pr08_frontend_baseline.py",
                        "--pipeline-input",
                        "$TMPDIR/pipeline.json",
                        "--generated-root",
                        "$TMPDIR/stage",
                        "--authority",
                        "local",
                        "--report",
                        "$TMPDIR/run_pr08_frontend_baseline.json",
                    ],
                    "cwd": "$REPO_ROOT",
                    "returncode": 0,
                },
            )
        )
        self.assertEqual(
            pipeline_result,
            run_pr101_comprehensive_audit.local_reused_gate_result(
                python="python3",
                script=Path("scripts/run_pr08_frontend_baseline.py"),
            ),
        )


if __name__ == "__main__":
    unittest.main()
