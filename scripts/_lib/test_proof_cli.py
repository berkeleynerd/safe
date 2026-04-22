"""Proof inventory, proof-eval, and ``safe prove`` checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import subprocess
import shutil
import sys
import tempfile
from pathlib import Path

from _lib import proof_eval
from _lib.proof_eval import (
    allow_clean_nonzero_gnatprove_exit,
    first_message as proof_eval_first_message,
)
from _lib.proof_inventory import EMITTED_PROOF_COVERED_PATHS, iter_proof_coverage_paths
from _lib.test_harness import (
    REPO_ROOT,
    SAFE_CLI,
    RunCounts,
    clear_project_artifacts,
    first_message,
    record_result,
    repo_rel,
    run_command,
)

PROVE_SINGLE_SUCCESS_SOURCE = REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe"
PROVE_IMPORTED_SUCCESS_SOURCE = REPO_ROOT / "tests" / "interfaces" / "client_types.safe"
PROVE_FAILURE_SOURCE = REPO_ROOT / "tests" / "negative" / "neg_rule2_oob.safe"
PROVE_DIRECTORY_FIXTURES = [
    REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe",
    REPO_ROOT / "tests" / "positive" / "constant_range_bound.safe",
]

def run_safe_prove_single_case(source: Path) -> tuple[bool, str]:
    clear_project_artifacts(source)
    completed = run_command(
        [sys.executable, str(SAFE_CLI), "prove", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        return False, f"safe prove failed: {first_message(completed)}"
    line = f"PASS {repo_rel(source)} ("
    if line not in completed.stdout:
        return False, f"missing PASS line {line!r}"
    if "flow total=" not in completed.stdout or "prove total=" not in completed.stdout:
        return False, f"missing proof summary in stdout {completed.stdout!r}"
    if "safe prove: PASS" not in completed.stdout:
        return False, f"missing final PASS verdict in stdout {completed.stdout!r}"
    if completed.stderr:
        return False, f"unexpected stderr {completed.stderr!r}"
    return True, ""


def run_safe_prove_directory_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-prove-dir-") as temp_root_str:
        temp_root = Path(temp_root_str)
        for source in PROVE_DIRECTORY_FIXTURES:
            shutil.copy2(source, temp_root / source.name)
        completed = run_command(
            [sys.executable, str(SAFE_CLI), "prove"],
            cwd=temp_root,
        )
        if completed.returncode != 0:
            return False, f"safe prove directory failed: {first_message(completed)}"
        lines = [line for line in completed.stdout.splitlines() if line.startswith("PASS ")]
        expected = [
            f"PASS {source.name} ("
            for source in sorted(PROVE_DIRECTORY_FIXTURES, key=lambda path: path.name)
        ]
        if len(lines) != len(expected):
            return False, f"unexpected PASS lines {lines!r}"
        for line, prefix in zip(lines, expected):
            if not line.startswith(prefix):
                return False, f"unexpected PASS order {lines!r}"
        if "2 passed, 0 failed" not in completed.stdout:
            return False, f"missing directory summary in stdout {completed.stdout!r}"
        if "safe prove: PASS" not in completed.stdout:
            return False, f"missing final PASS verdict in stdout {completed.stdout!r}"
        if completed.stderr:
            return False, f"unexpected stderr {completed.stderr!r}"
    return True, ""


def run_safe_prove_failure_case(*, verbose: bool) -> tuple[bool, str]:
    argv = [sys.executable, str(SAFE_CLI), "prove"]
    if verbose:
        argv.append("--verbose")
    argv.append(repo_rel(PROVE_FAILURE_SOURCE))
    completed = run_command(argv, cwd=REPO_ROOT)
    if completed.returncode == 0:
        return False, "safe prove unexpectedly succeeded"
    expected_stage = f"FAIL {repo_rel(PROVE_FAILURE_SOURCE)} [check]"
    if expected_stage not in completed.stdout:
        return False, f"missing stage line {expected_stage!r}"
    if "safe prove: FAIL" not in completed.stdout:
        return False, f"missing final FAIL verdict in stdout {completed.stdout!r}"
    if verbose:
        if "--- check output ---" not in completed.stderr:
            return False, f"missing verbose failure header in stderr {completed.stderr!r}"
        if PROVE_FAILURE_SOURCE.name not in completed.stderr:
            return False, f"missing failing source name in verbose stderr {completed.stderr!r}"
    elif completed.stderr:
        return False, f"unexpected stderr {completed.stderr!r}"
    return True, ""


def run_safe_prove_no_sources_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-prove-empty-") as temp_root_str:
        completed = run_command(
            [sys.executable, str(SAFE_CLI), "prove"],
            cwd=Path(temp_root_str),
        )
        if completed.returncode == 0:
            return False, "safe prove unexpectedly succeeded without sources"
        if "safe prove: no .safe files found in the current directory" not in completed.stderr:
            return False, f"missing empty-directory error in stderr {completed.stderr!r}"
        if completed.stdout:
            return False, f"unexpected stdout {completed.stdout!r}"
    return True, ""

def run_proof_inventory_coverage_case() -> tuple[bool, str]:
    covered = set(EMITTED_PROOF_COVERED_PATHS)
    uncovered = [
        entry
        for entry in iter_proof_coverage_paths(REPO_ROOT)
        if entry not in covered
    ]
    if uncovered:
        return (
            False,
            "fixtures under proof coverage roots missing from proof inventory: "
            + ", ".join(uncovered),
        )
    return True, ""


def run_proof_eval_message_priority_case() -> tuple[bool, str]:
    completed = subprocess.CompletedProcess(
        args=["dummy"],
        returncode=1,
        stdout="tool: error: real failure\n",
        stderr="wrapper warning: noisy wrapper prefix\n",
    )
    detail = proof_eval_first_message(completed)
    if detail != "tool: error: real failure":
        return False, f"unexpected prioritized detail {detail!r}"
    return True, ""


def run_proof_eval_clean_nonzero_case() -> tuple[bool, str]:
    completed = subprocess.CompletedProcess(
        args=["dummy"],
        returncode=1,
        stdout="",
        stderr="unit.ads:1:1: info: assertion proved\n",
    )
    total_row = {
        "total": {"count": 1, "detail": ""},
        "flow": {"count": 0, "detail": ""},
        "provers": {"count": 1, "detail": ""},
        "justified": {"count": 0, "detail": ""},
        "unproved": {"count": 0, "detail": ""},
    }
    if not allow_clean_nonzero_gnatprove_exit(completed, total_row):
        return False, "expected info-only nonzero GNATprove exit to be accepted"
    return True, ""


def run_proof_eval_check_mode_success_case() -> tuple[bool, str]:
    toolchain = proof_eval.ProofToolchain(
        safec=SAFE_CLI,
        alr="alr",
        gnatprove="gnatprove",
        env={},
    )
    calls: list[list[str]] = []
    original_run_command = proof_eval.run_command
    original_parse_summary = proof_eval.parse_gnatprove_summary
    try:
        def fake_run_command(
            argv: list[str],
            *,
            cwd: Path,
            env: dict[str, str] | None = None,
            timeout: int | None = None,
        ) -> subprocess.CompletedProcess[str]:
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, "", "")

        def unexpected_parse_summary(_summary_path: Path) -> object:
            raise AssertionError("check mode should not parse GNATprove summaries")

        proof_eval.run_command = fake_run_command
        proof_eval.parse_gnatprove_summary = unexpected_parse_summary
        passed, detail = proof_eval.run_gnatprove_project(
            project_dir=REPO_ROOT,
            project_file="demo.gpr",
            toolchain=toolchain,
            proof_mode="check",
        )
    except AssertionError as exc:
        return False, str(exc)
    finally:
        proof_eval.run_command = original_run_command
        proof_eval.parse_gnatprove_summary = original_parse_summary

    if not passed or detail:
        return False, f"expected check mode success, got passed={passed} detail={detail!r}"
    expected_argv = ["alr", "exec", "--", "gnatprove", "-P", "demo.gpr", *proof_eval.CHECK_SWITCHES]
    if calls != [expected_argv]:
        return False, f"unexpected check-mode invocation {calls!r}"
    return True, ""


def run_proof_eval_check_mode_failure_case() -> tuple[bool, str]:
    toolchain = proof_eval.ProofToolchain(
        safec=SAFE_CLI,
        alr="alr",
        gnatprove="gnatprove",
        env={},
    )
    original_run_command = proof_eval.run_command
    original_parse_summary = proof_eval.parse_gnatprove_summary
    try:
        def fake_run_command(
            argv: list[str],
            *,
            cwd: Path,
            env: dict[str, str] | None = None,
            timeout: int | None = None,
        ) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(argv, 1, "", "gnatprove: legality failed\n")

        def unexpected_parse_summary(_summary_path: Path) -> object:
            raise AssertionError("check mode should not parse GNATprove summaries")

        proof_eval.run_command = fake_run_command
        proof_eval.parse_gnatprove_summary = unexpected_parse_summary
        passed, detail = proof_eval.run_gnatprove_project(
            project_dir=REPO_ROOT,
            project_file="demo.gpr",
            toolchain=toolchain,
            proof_mode="check",
        )
    except AssertionError as exc:
        return False, str(exc)
    finally:
        proof_eval.run_command = original_run_command
        proof_eval.parse_gnatprove_summary = original_parse_summary

    if passed:
        return False, "check mode unexpectedly succeeded"
    if detail != "check failed: gnatprove: legality failed":
        return False, f"unexpected check-mode failure detail {detail!r}"
    return True, ""


def run_proof_eval_invalid_mode_case() -> tuple[bool, str]:
    toolchain = proof_eval.ProofToolchain(
        safec=SAFE_CLI,
        alr="alr",
        gnatprove="gnatprove",
        env={},
    )
    try:
        proof_eval.run_gnatprove_project(
            project_dir=REPO_ROOT,
            project_file="demo.gpr",
            toolchain=toolchain,
            proof_mode="bogus",
        )
    except ValueError as exc:
        if str(exc) != "unsupported proof mode: bogus":
            return False, f"unexpected invalid-mode error {exc!r}"
        return True, ""
    return False, "invalid proof mode unexpectedly succeeded"


def run_proof_eval_check_mode_custom_switches_case() -> tuple[bool, str]:
    toolchain = proof_eval.ProofToolchain(
        safec=SAFE_CLI,
        alr="alr",
        gnatprove="gnatprove",
        env={},
    )
    try:
        proof_eval.run_gnatprove_project(
            project_dir=REPO_ROOT,
            project_file="demo.gpr",
            toolchain=toolchain,
            proof_mode="check",
            prove_switches=["--dummy"],
        )
    except ValueError as exc:
        if str(exc) != "prove_switches is not supported in check mode":
            return False, f"unexpected check-mode switches error {exc!r}"
        return True, ""
    return False, "check mode unexpectedly accepted custom prove switches"


def run_source_proof_check_mode_custom_switches_case() -> tuple[bool, str]:
    toolchain = proof_eval.ProofToolchain(
        safec=SAFE_CLI,
        alr="alr",
        gnatprove="gnatprove",
        env={},
    )
    with tempfile.TemporaryDirectory(prefix="safe-proof-root-") as proof_root_str:
        try:
            proof_eval.run_source_proof(
                toolchain=toolchain,
                source=PROVE_SINGLE_SUCCESS_SOURCE,
                proof_root=Path(proof_root_str),
                run_check=False,
                proof_mode="check",
                prove_switches=["--dummy"],
            )
        except ValueError as exc:
            if str(exc) != "prove_switches is not supported in check mode":
                return False, f"unexpected source-proof switches error {exc!r}"
            return True, ""
    return False, "run_source_proof unexpectedly accepted custom prove switches"


def run_source_proof_check_mode_success_case() -> tuple[bool, str]:
    return run_source_proof_check_mode_execution_case(returncode=0)


def run_source_proof_check_mode_failure_case() -> tuple[bool, str]:
    return run_source_proof_check_mode_execution_case(returncode=1)


def run_source_proof_check_mode_execution_case(*, returncode: int) -> tuple[bool, str]:
    toolchain = proof_eval.ProofToolchain(
        safec=SAFE_CLI,
        alr="alr",
        gnatprove="gnatprove",
        env={},
    )
    calls: list[list[str]] = []
    original_prepare_proof_root = proof_eval.prepare_proof_root
    original_ensure_interface_dependencies = proof_eval.ensure_interface_dependencies
    original_emit_source_for_proof = proof_eval.emit_source_for_proof
    original_mirror_with_clauses = proof_eval.mirror_with_clauses_into_emitted_unit
    original_load_all_line_maps = proof_eval.load_all_line_maps
    original_compile_emitted_ada = proof_eval.compile_emitted_ada
    original_write_emitted_project = proof_eval.write_emitted_project
    original_run_command = proof_eval.run_command
    original_record_stage_output = proof_eval.record_gnatprove_stage_output
    original_parse_summary = proof_eval.parse_gnatprove_summary
    try:
        with tempfile.TemporaryDirectory(prefix="safe-proof-root-") as proof_root_str:
            proof_root = Path(proof_root_str)
            ada_dir = proof_root / "ada"
            ada_dir.mkdir(parents=True, exist_ok=True)
            gpr_path = ada_dir / "proof.gpr"
            gpr_path.write_text("project Proof is end Proof;\n", encoding="utf-8")

            def fake_prepare_proof_root(_root: Path) -> dict[str, Path]:
                return {"ada": ada_dir, "iface": proof_root / "iface"}

            def fake_ensure_interface_dependencies(**_kwargs: object) -> str | None:
                return None

            def fake_emit_source_for_proof(**_kwargs: object) -> subprocess.CompletedProcess[str]:
                return subprocess.CompletedProcess(["safec"], 0, "", "")

            def fake_mirror_with_clauses(_source: Path, _ada_dir: Path) -> None:
                return None

            def fake_load_all_line_maps(_ada_dir: Path) -> dict[str, dict[int, object]]:
                return {}

            def fake_compile_emitted_ada(
                _ada_dir: Path,
                *,
                toolchain: proof_eval.ProofToolchain,
            ) -> subprocess.CompletedProcess[str]:
                return subprocess.CompletedProcess([toolchain.alr], 0, "", "")

            def fake_write_emitted_project(_ada_dir: Path) -> Path:
                return gpr_path

            def fake_run_command(
                argv: list[str],
                *,
                cwd: Path,
                env: dict[str, str] | None = None,
                timeout: int | None = None,
            ) -> subprocess.CompletedProcess[str]:
                calls.append(argv)
                stderr = "" if returncode == 0 else "gnatprove: legality failed\n"
                return subprocess.CompletedProcess(argv, returncode, "", stderr)

            def fake_record_stage_output(
                result: proof_eval.ProofRunResult,
                stage_name: str,
                completed: subprocess.CompletedProcess[str],
                *,
                ada_dir: Path,
                line_maps: dict[str, dict[int, object]],
            ) -> None:
                result.stage_output[stage_name] = proof_eval.format_completed_output(completed)

            def unexpected_parse_summary(_summary_path: Path) -> object:
                raise AssertionError("check mode should not parse GNATprove summaries")

            proof_eval.prepare_proof_root = fake_prepare_proof_root
            proof_eval.ensure_interface_dependencies = fake_ensure_interface_dependencies
            proof_eval.emit_source_for_proof = fake_emit_source_for_proof
            proof_eval.mirror_with_clauses_into_emitted_unit = fake_mirror_with_clauses
            proof_eval.load_all_line_maps = fake_load_all_line_maps
            proof_eval.compile_emitted_ada = fake_compile_emitted_ada
            proof_eval.write_emitted_project = fake_write_emitted_project
            proof_eval.run_command = fake_run_command
            proof_eval.record_gnatprove_stage_output = fake_record_stage_output
            proof_eval.parse_gnatprove_summary = unexpected_parse_summary

            result = proof_eval.run_source_proof(
                toolchain=toolchain,
                source=PROVE_SINGLE_SUCCESS_SOURCE,
                proof_root=proof_root,
                run_check=False,
                proof_mode="check",
            )
    except AssertionError as exc:
        return False, str(exc)
    finally:
        proof_eval.prepare_proof_root = original_prepare_proof_root
        proof_eval.ensure_interface_dependencies = original_ensure_interface_dependencies
        proof_eval.emit_source_for_proof = original_emit_source_for_proof
        proof_eval.mirror_with_clauses_into_emitted_unit = original_mirror_with_clauses
        proof_eval.load_all_line_maps = original_load_all_line_maps
        proof_eval.compile_emitted_ada = original_compile_emitted_ada
        proof_eval.write_emitted_project = original_write_emitted_project
        proof_eval.run_command = original_run_command
        proof_eval.record_gnatprove_stage_output = original_record_stage_output
        proof_eval.parse_gnatprove_summary = original_parse_summary

    expected_argv = [
        "alr",
        "exec",
        "--",
        "gnatprove",
        "-P",
        str(gpr_path),
        *proof_eval.CHECK_SWITCHES,
    ]
    if calls != [expected_argv]:
        return False, f"unexpected source-proof check invocation {calls!r}"

    if returncode == 0:
        if not result.passed:
            return False, f"expected source-proof check success, got passed={result.passed}"
        if result.detail:
            return False, f"expected empty detail on source-proof success, got {result.detail!r}"
        if result.stage != "prove-check":
            return False, f"unexpected success stage {result.stage!r}"
        return True, ""

    if result.passed:
        return False, "source-proof check unexpectedly succeeded"
    if result.detail != "check failed: gnatprove: legality failed":
        return False, f"unexpected source-proof failure detail {result.detail!r}"
    if result.stage != "prove-check":
        return False, f"unexpected failure stage {result.stage!r}"
    return True, ""



def run_internal_proof_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    passed += record_result(failures, "proof-inventory-coverage", run_proof_inventory_coverage_case())
    passed += record_result(failures, "proof-eval-message-priority", run_proof_eval_message_priority_case())
    passed += record_result(failures, "proof-eval-clean-nonzero", run_proof_eval_clean_nonzero_case())
    passed += record_result(failures, "proof-eval-check-mode-success", run_proof_eval_check_mode_success_case())
    passed += record_result(failures, "proof-eval-check-mode-failure", run_proof_eval_check_mode_failure_case())
    passed += record_result(failures, "proof-eval-invalid-mode", run_proof_eval_invalid_mode_case())
    passed += record_result(
        failures,
        "proof-eval-check-mode-custom-switches",
        run_proof_eval_check_mode_custom_switches_case(),
    )
    passed += record_result(
        failures,
        "source-proof-check-mode-custom-switches",
        run_source_proof_check_mode_custom_switches_case(),
    )
    passed += record_result(
        failures,
        "source-proof-check-mode-success",
        run_source_proof_check_mode_success_case(),
    )
    passed += record_result(
        failures,
        "source-proof-check-mode-failure",
        run_source_proof_check_mode_failure_case(),
    )
    return passed, 0, failures


def run_safe_prove_success_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    for source in (PROVE_SINGLE_SUCCESS_SOURCE, PROVE_IMPORTED_SUCCESS_SOURCE):
        passed += record_result(
            failures,
            f"safe prove {repo_rel(source)}",
            run_safe_prove_single_case(source),
        )
    return passed, 0, failures


def run_safe_prove_failure_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []

    result = run_safe_prove_directory_case()
    passed += record_result(failures, "safe prove current directory", result)

    for label, verbose in (
        ("safe prove failure stage", False),
        ("safe prove verbose failure", True),
    ):
        result = run_safe_prove_failure_case(verbose=verbose)
        passed += record_result(failures, label, result)

    passed += record_result(failures, "safe prove empty directory", run_safe_prove_no_sources_case())
    return passed, 0, failures
