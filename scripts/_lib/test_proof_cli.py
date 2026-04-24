"""Proof inventory, proof-eval, and ``safe prove`` checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import argparse
import contextlib
import io
import subprocess
import shutil
import sys
import tempfile
from pathlib import Path

import run_proofs as run_proofs_script
import safe_cli as safe_cli_script

from _lib import proof_eval
from _lib import project_cache
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
    safe_prove_summary_path,
)

PROVE_SINGLE_SUCCESS_SOURCE = REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe"
PROVE_IMPORTED_SUCCESS_SOURCE = REPO_ROOT / "tests" / "interfaces" / "client_types.safe"
PROVE_FAILURE_SOURCE = REPO_ROOT / "tests" / "negative" / "neg_rule2_oob.safe"
PROVE_DIRECTORY_FIXTURES = [
    REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe",
    REPO_ROOT / "tests" / "positive" / "constant_range_bound.safe",
]
TEST_GNATPROVE_VERSION = "GNATprove 25.0\ncvc5 1.0"
RUN_PROOFS_GROUP_ATTRS = (
    "PR11_8A_CHECKPOINT_FIXTURES",
    "PR11_8B_CHECKPOINT_FIXTURES",
    "PR11_8E_CHECKPOINT_FIXTURES",
    "PR11_8F_CHECKPOINT_FIXTURES",
    "PR11_8G1_CHECKPOINT_FIXTURES",
    "PR11_8G2_CHECKPOINT_FIXTURES",
    "PR11_8I_CHECKPOINT_FIXTURES",
    "PR11_8I1_CHECKPOINT_FIXTURES",
    "PR11_8K_CHECKPOINT_FIXTURES",
    "PR11_10A_CHECKPOINT_FIXTURES",
    "PR11_10B_CHECKPOINT_FIXTURES",
    "PR11_10C_CHECKPOINT_FIXTURES",
    "PR11_11A_CHECKPOINT_FIXTURES",
    "PR11_11B_CHECKPOINT_FIXTURES",
    "PR11_11C_CHECKPOINT_FIXTURES",
    "PR11_12A_CHECKPOINT_FIXTURES",
    "PR11_12B_CHECKPOINT_FIXTURES",
    "PR11_12C_CHECKPOINT_FIXTURES",
    "PR11_12D_CHECKPOINT_FIXTURES",
    "PR11_12E_CHECKPOINT_FIXTURES",
    "PR11_12F_CHECKPOINT_FIXTURES",
    "PR11_13A_CHECKPOINT_FIXTURES",
    "PR11_13B_CHECKPOINT_FIXTURES",
    "PR11_13C_CHECKPOINT_FIXTURES",
    "PR11_16_CHECKPOINT_FIXTURES",
    "PR11_23_PROOF_EXPANSION_FIXTURES",
    "EMITTED_PROOF_REGRESSION_FIXTURES",
)


def test_toolchain() -> proof_eval.ProofToolchain:
    return proof_eval.ProofToolchain(
        safec=SAFE_CLI,
        alr="alr",
        gnatprove="gnatprove",
        gnatprove_version=TEST_GNATPROVE_VERSION,
        env={},
    )


def run_run_proofs_subset(
    argv: list[str],
    *,
    fixtures: list[str],
    use_real_toolchain: bool,
    fake_source_proof: object | None = None,
    fake_cached_source_proof: object | None = None,
) -> tuple[int, str, str]:
    original_argv = sys.argv[:]
    stdout = io.StringIO()
    stderr = io.StringIO()
    originals = {
        "COMPANION_PROJECTS": run_proofs_script.COMPANION_PROJECTS,
        "validate_manifests": run_proofs_script.validate_manifests,
        "prepare_proof_toolchain": run_proofs_script.prepare_proof_toolchain,
        "run_source_proof": run_proofs_script.run_source_proof,
        "run_cached_source_proof": run_proofs_script.run_cached_source_proof,
        "EMITTED_PROOF_FIXTURES": run_proofs_script.EMITTED_PROOF_FIXTURES,
    }
    originals.update({name: getattr(run_proofs_script, name) for name in RUN_PROOFS_GROUP_ATTRS})

    try:
        run_proofs_script.COMPANION_PROJECTS = []
        run_proofs_script.validate_manifests = lambda: None
        run_proofs_script.prepare_proof_toolchain = (
            (lambda env: proof_eval.prepare_proof_toolchain(env=env, build_frontend=False))
            if use_real_toolchain
            else (lambda env: test_toolchain())
        )
        if fake_source_proof is not None:
            run_proofs_script.run_source_proof = fake_source_proof
        if fake_cached_source_proof is not None:
            run_proofs_script.run_cached_source_proof = fake_cached_source_proof
        run_proofs_script.EMITTED_PROOF_FIXTURES = tuple(fixtures)
        for name in RUN_PROOFS_GROUP_ATTRS:
            setattr(run_proofs_script, name, [])
        run_proofs_script.PR11_8A_CHECKPOINT_FIXTURES = list(fixtures)

        sys.argv = ["run_proofs.py", *argv]
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            return run_proofs_script.main(), stdout.getvalue(), stderr.getvalue()
    finally:
        sys.argv = original_argv
        for name, value in originals.items():
            setattr(run_proofs_script, name, value)


def successful_summary_row() -> dict[str, dict[str, int | str]]:
    return {
        "total": {"count": 1, "detail": ""},
        "flow": {"count": 0, "detail": ""},
        "provers": {"count": 1, "detail": ""},
        "justified": {"count": 0, "detail": ""},
        "unproved": {"count": 0, "detail": ""},
    }


def fake_cached_proof_runner(**kwargs: object) -> proof_eval.ProofRunResult:
    source = kwargs["source"]
    toolchain = kwargs["toolchain"]
    prove_switches = kwargs.get("prove_switches")
    target_bits = int(kwargs.get("target_bits", 64))
    summary_path = safe_prove_summary_path(source, target_bits=target_bits)
    fingerprint = repr(
        {
            "source": project_cache.source_key(source),
            "target_bits": target_bits,
            "prove_switches": prove_switches,
            "gnatprove_version": toolchain.gnatprove_version,
        }
    )
    cache_entry = project_cache.cached_proof_result(
        source=source,
        fingerprint=fingerprint,
        target_bits=target_bits,
    )
    row = successful_summary_row()
    result = proof_eval.ProofRunResult(
        source=source,
        proof_root=summary_path.parents[2],
        passed=True,
        stage="prove",
        flow_summary=row,
        prove_summary=row,
        used_cache=cache_entry is not None,
    )
    if result.used_cache:
        return result

    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text("mock gnatprove summary\n", encoding="utf-8")
    project_cache.record_cached_proof_result(
        source=source,
        fingerprint=fingerprint,
        flow_summary=row,
        prove_summary=row,
        target_bits=target_bits,
    )
    return result


def run_safe_prove_subset(
    source: Path,
    *,
    fake_cached_source_proof: object,
    level: int = 1,
    target_bits: int = 64,
) -> tuple[int, str, str]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    originals = {
        "prepare_proof_toolchain": safe_cli_script.prepare_proof_toolchain,
        "run_cached_source_proof": safe_cli_script.run_cached_source_proof,
    }
    args = argparse.Namespace(
        source=repo_rel(source),
        verbose=False,
        level=level,
        target_bits=target_bits,
    )
    try:
        safe_cli_script.prepare_proof_toolchain = lambda env, build_frontend=False: test_toolchain()
        safe_cli_script.run_cached_source_proof = fake_cached_source_proof
        with contextlib.chdir(REPO_ROOT):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                return safe_cli_script.safe_prove(args), stdout.getvalue(), stderr.getvalue()
    finally:
        for name, value in originals.items():
            setattr(safe_cli_script, name, value)

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
    toolchain = test_toolchain()
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
    toolchain = test_toolchain()
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
    toolchain = test_toolchain()
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
    toolchain = test_toolchain()
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
    toolchain = test_toolchain()
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
    toolchain = test_toolchain()
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


def run_prepare_proof_toolchain_version_normalization_case() -> tuple[bool, str]:
    original_find_command = proof_eval.find_command
    original_require_safec = proof_eval.require_safec
    original_run_command = proof_eval.run_command
    try:
        def fake_find_command(name: str, fallback: Path | None = None) -> str:
            del fallback
            return name

        def fake_require_safec() -> Path:
            return SAFE_CLI

        def fake_run_command(
            argv: list[str],
            *,
            cwd: Path,
            env: dict[str, str] | None = None,
            timeout: int | None = None,
        ) -> subprocess.CompletedProcess[str]:
            del env, timeout
            if cwd != proof_eval.COMPILER_ROOT:
                raise AssertionError(f"unexpected cwd {cwd!r}")
            if argv != ["alr", "exec", "--", "gnatprove", "--version"]:
                raise AssertionError(f"unexpected command {argv!r}")
            return subprocess.CompletedProcess(
                argv,
                0,
                "\r\n GNATprove 25.0 \r\n  cvc5 1.0 \r\n",
                "\n",
            )

        proof_eval.find_command = fake_find_command
        proof_eval.require_safec = fake_require_safec
        proof_eval.run_command = fake_run_command
        toolchain = proof_eval.prepare_proof_toolchain(env={}, build_frontend=False)
    except AssertionError as exc:
        return False, str(exc)
    finally:
        proof_eval.find_command = original_find_command
        proof_eval.require_safec = original_require_safec
        proof_eval.run_command = original_run_command

    if toolchain.gnatprove_version != TEST_GNATPROVE_VERSION:
        return False, f"unexpected normalized version text {toolchain.gnatprove_version!r}"
    return True, ""


def run_prepare_proof_toolchain_version_probe_failure_case() -> tuple[bool, str]:
    original_find_command = proof_eval.find_command
    original_require_safec = proof_eval.require_safec
    original_run_command = proof_eval.run_command
    try:
        def fake_find_command(name: str, fallback: Path | None = None) -> str:
            del fallback
            return name

        def fake_require_safec() -> Path:
            return SAFE_CLI

        def fake_run_command(
            argv: list[str],
            *,
            cwd: Path,
            env: dict[str, str] | None = None,
            timeout: int | None = None,
        ) -> subprocess.CompletedProcess[str]:
            del env, timeout
            if cwd != proof_eval.COMPILER_ROOT:
                raise AssertionError(f"unexpected cwd {cwd!r}")
            if argv != ["alr", "exec", "--", "gnatprove", "--version"]:
                raise AssertionError(f"unexpected command {argv!r}")
            return subprocess.CompletedProcess(argv, 1, "", "probe failed\n")

        proof_eval.find_command = fake_find_command
        proof_eval.require_safec = fake_require_safec
        proof_eval.run_command = fake_run_command
        proof_eval.prepare_proof_toolchain(env={}, build_frontend=False)
    except RuntimeError as exc:
        if str(exc) != "failed to capture gnatprove --version: probe failed":
            return False, f"unexpected version-probe error {exc!r}"
        return True, ""
    except AssertionError as exc:
        return False, str(exc)
    finally:
        proof_eval.find_command = original_find_command
        proof_eval.require_safec = original_require_safec
        proof_eval.run_command = original_run_command

    return False, "prepare_proof_toolchain unexpectedly accepted failed version probe"


def run_proof_fingerprint_gnatprove_version_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-proof-fingerprint-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "demo.safe"
        source.write_text("value : integer = 1\n", encoding="utf-8")
        fingerprint_a = project_cache.proof_fingerprint(
            source=source,
            sources=[source],
            safec_hash="safec-hash",
            gnatprove_id="gnatprove",
            gnatprove_version="GNATprove 25.0",
            flow_switches=proof_eval.FLOW_SWITCHES,
            prove_switches=proof_eval.prove_switches_for_level(1),
        )
        fingerprint_b = project_cache.proof_fingerprint(
            source=source,
            sources=[source],
            safec_hash="safec-hash",
            gnatprove_id="gnatprove",
            gnatprove_version="GNATprove 25.1",
            flow_switches=proof_eval.FLOW_SWITCHES,
            prove_switches=proof_eval.prove_switches_for_level(1),
        )
    if fingerprint_a == fingerprint_b:
        return False, "proof fingerprint ignored gnatprove_version"
    return True, ""


def run_cached_proof_hit_skips_emit_case() -> tuple[bool, str]:
    source = PROVE_SINGLE_SUCCESS_SOURCE
    toolchain = test_toolchain()
    sources = project_cache.resolve_project_sources(source)
    fingerprint = project_cache.proof_fingerprint(
        source=source,
        sources=sources,
        safec_hash=proof_eval.sha256_file(toolchain.safec),
        gnatprove_id=proof_eval.tool_identity(toolchain.gnatprove),
        gnatprove_version=toolchain.gnatprove_version,
        flow_switches=proof_eval.FLOW_SWITCHES,
        prove_switches=proof_eval.prove_switches_for_level(1),
    )
    row = successful_summary_row()
    project_cache.drop_cached_proof_result(source=source, target_bits=64)
    project_cache.record_cached_proof_result(
        source=source,
        fingerprint=fingerprint,
        flow_summary=row,
        prove_summary=row,
        target_bits=64,
    )

    original_ensure_project_emitted = proof_eval.ensure_project_emitted
    try:
        def unexpected_emit(**_kwargs: object) -> object:
            raise AssertionError("cache hit should not emit the project")

        proof_eval.ensure_project_emitted = unexpected_emit
        result = proof_eval.run_cached_source_proof(
            toolchain=toolchain,
            source=source,
            run_check=True,
            prove_switches=proof_eval.prove_switches_for_level(1),
        )
    except AssertionError as exc:
        return False, str(exc)
    finally:
        proof_eval.ensure_project_emitted = original_ensure_project_emitted
        project_cache.drop_cached_proof_result(source=source, target_bits=64)

    if not result.passed or not result.used_cache:
        return False, f"expected cached proof hit, got passed={result.passed} used_cache={result.used_cache}"
    if result.flow_summary != row or result.prove_summary != row:
        return False, "cached proof summaries were not replayed"
    return True, ""


def run_run_proofs_no_cache_case() -> tuple[bool, str]:
    fixture = repo_rel(PROVE_SINGLE_SUCCESS_SOURCE)
    source_calls = 0
    cached_calls = 0

    def fake_source_proof(**kwargs: object) -> proof_eval.ProofRunResult:
        nonlocal source_calls
        source_calls += 1
        source = kwargs["source"]
        proof_root = kwargs["proof_root"]
        return proof_eval.ProofRunResult(
            source=source,
            proof_root=proof_root,
            passed=True,
            stage="prove",
        )

    def fake_cached_source_proof(**kwargs: object) -> proof_eval.ProofRunResult:
        nonlocal cached_calls
        cached_calls += 1
        raise AssertionError(f"unexpected cached proof call {kwargs!r}")

    try:
        returncode, stdout, stderr = run_run_proofs_subset(
            ["--no-cache"],
            fixtures=[fixture],
            use_real_toolchain=False,
            fake_source_proof=fake_source_proof,
            fake_cached_source_proof=fake_cached_source_proof,
        )
    except AssertionError as exc:
        return False, str(exc)

    if returncode != 0:
        return False, f"run_proofs --no-cache failed: {stderr or stdout}"
    if source_calls != 1 or cached_calls != 0:
        return False, f"unexpected prove call counts source={source_calls} cached={cached_calls}"
    if "cache reuse enabled" in stdout:
        return False, f"unexpected cache banner in stdout {stdout!r}"
    if "PR11.8a checkpoint: 1 proved, 0 cached, 0 failed" not in stdout:
        return False, f"unexpected prove summary {stdout!r}"
    if stderr:
        return False, f"unexpected stderr {stderr!r}"
    return True, ""


def run_run_proofs_check_mode_ignores_cache_case() -> tuple[bool, str]:
    fixture = repo_rel(PROVE_SINGLE_SUCCESS_SOURCE)
    source_calls = 0

    def fake_source_proof(**kwargs: object) -> proof_eval.ProofRunResult:
        nonlocal source_calls
        source_calls += 1
        source = kwargs["source"]
        proof_root = kwargs["proof_root"]
        return proof_eval.ProofRunResult(
            source=source,
            proof_root=proof_root,
            passed=True,
            stage="prove-check",
        )

    def fake_cached_source_proof(**kwargs: object) -> proof_eval.ProofRunResult:
        raise AssertionError(f"check mode should not use cached proof path: {kwargs!r}")

    try:
        cached_run = run_run_proofs_subset(
            ["--mode=check", "--cache"],
            fixtures=[fixture],
            use_real_toolchain=False,
            fake_source_proof=fake_source_proof,
            fake_cached_source_proof=fake_cached_source_proof,
        )
        uncached_run = run_run_proofs_subset(
            ["--mode=check", "--no-cache"],
            fixtures=[fixture],
            use_real_toolchain=False,
            fake_source_proof=fake_source_proof,
            fake_cached_source_proof=fake_cached_source_proof,
        )
    except AssertionError as exc:
        return False, str(exc)

    if cached_run != uncached_run:
        return False, f"check-mode cache flag changed output {cached_run!r} != {uncached_run!r}"
    returncode, stdout, stderr = cached_run
    if returncode != 0:
        return False, f"check-mode run_proofs failed: {stderr or stdout}"
    if source_calls != 2:
        return False, f"expected two uncached check-mode calls, saw {source_calls}"
    if "cache reuse enabled" in stdout:
        return False, f"unexpected cache banner in check-mode stdout {stdout!r}"
    if "PR11.8a checkpoint: 1 checked, 0 failed" not in stdout:
        return False, f"unexpected check-mode summary {stdout!r}"
    if stderr:
        return False, f"unexpected stderr {stderr!r}"
    return True, ""


def run_run_proofs_default_cache_case() -> tuple[bool, str]:
    source = PROVE_SINGLE_SUCCESS_SOURCE
    fixture = repo_rel(source)
    clear_project_artifacts(source)
    project_cache.drop_cached_proof_result(source=source, target_bits=64)
    summary_path = safe_prove_summary_path(source, target_bits=64)

    first_returncode, first_stdout, first_stderr = run_run_proofs_subset(
        ["--level", "1"],
        fixtures=[fixture],
        use_real_toolchain=False,
        fake_cached_source_proof=fake_cached_proof_runner,
    )
    if first_returncode != 0:
        return False, f"initial run_proofs failed: {first_stderr or first_stdout}"
    if "[run_proofs] cache reuse enabled (--no-cache to disable)" not in first_stdout:
        return False, f"missing cache banner in stdout {first_stdout!r}"
    if "PR11.8a checkpoint: 1 proved, 0 cached, 0 failed" not in first_stdout:
        return False, f"unexpected first prove summary {first_stdout!r}"
    if first_stderr:
        return False, f"unexpected stderr {first_stderr!r}"
    if not summary_path.exists():
        return False, f"missing proof summary {summary_path}"
    summary_mtime = summary_path.stat().st_mtime_ns

    second_returncode, second_stdout, second_stderr = run_run_proofs_subset(
        ["--level", "1"],
        fixtures=[fixture],
        use_real_toolchain=False,
        fake_cached_source_proof=fake_cached_proof_runner,
    )
    if second_returncode != 0:
        return False, f"cached run_proofs failed: {second_stderr or second_stdout}"
    if summary_path.stat().st_mtime_ns != summary_mtime:
        return False, "cached run_proofs reran GNATprove"
    if "PR11.8a checkpoint: 0 proved, 1 cached, 0 failed" not in second_stdout:
        return False, f"unexpected cached prove summary {second_stdout!r}"
    if second_stderr:
        return False, f"unexpected stderr {second_stderr!r}"
    return True, ""


def run_run_proofs_explicit_cache_case() -> tuple[bool, str]:
    source = PROVE_SINGLE_SUCCESS_SOURCE
    fixture = repo_rel(source)
    clear_project_artifacts(source)
    project_cache.drop_cached_proof_result(source=source, target_bits=64)
    summary_path = safe_prove_summary_path(source, target_bits=64)

    first_returncode, first_stdout, first_stderr = run_run_proofs_subset(
        ["--cache", "--level", "1"],
        fixtures=[fixture],
        use_real_toolchain=False,
        fake_cached_source_proof=fake_cached_proof_runner,
    )
    if first_returncode != 0:
        return False, f"explicit-cache run_proofs failed: {first_stderr or first_stdout}"
    if "[run_proofs] cache reuse enabled (--no-cache to disable)" not in first_stdout:
        return False, f"missing cache banner in stdout {first_stdout!r}"
    if "PR11.8a checkpoint: 1 proved, 0 cached, 0 failed" not in first_stdout:
        return False, f"unexpected first explicit-cache summary {first_stdout!r}"
    if first_stderr:
        return False, f"unexpected stderr {first_stderr!r}"
    if not summary_path.exists():
        return False, f"missing proof summary {summary_path}"
    summary_mtime = summary_path.stat().st_mtime_ns

    second_returncode, second_stdout, second_stderr = run_run_proofs_subset(
        ["--cache", "--level", "1"],
        fixtures=[fixture],
        use_real_toolchain=False,
        fake_cached_source_proof=fake_cached_proof_runner,
    )
    if second_returncode != 0:
        return False, f"cached explicit-cache run_proofs failed: {second_stderr or second_stdout}"
    if summary_path.stat().st_mtime_ns != summary_mtime:
        return False, "explicit-cache run_proofs reran GNATprove"
    if "PR11.8a checkpoint: 0 proved, 1 cached, 0 failed" not in second_stdout:
        return False, f"unexpected cached explicit-cache summary {second_stdout!r}"
    if second_stderr:
        return False, f"unexpected stderr {second_stderr!r}"
    return True, ""


def run_cross_tool_cache_consistency_case() -> tuple[bool, str]:
    source = PROVE_SINGLE_SUCCESS_SOURCE
    fixture = repo_rel(source)
    summary_path = safe_prove_summary_path(source, target_bits=64)
    cache_call_signatures: list[tuple[Path, tuple[str, ...] | None, int]] = []

    def recording_cached_proof_runner(**kwargs: object) -> proof_eval.ProofRunResult:
        prove_switches = kwargs.get("prove_switches")
        if prove_switches is None:
            normalized_switches = None
        elif isinstance(prove_switches, (str, bytes)):
            raise AssertionError(
                f"unexpected prove_switches value for cache signature: {prove_switches!r}"
            )
        else:
            try:
                normalized_switches = tuple(prove_switches)
            except TypeError as exc:
                raise AssertionError(
                    f"unexpected prove_switches value for cache signature: {prove_switches!r}"
                ) from exc
        cache_call_signatures.append(
            (
                Path(kwargs["source"]),
                normalized_switches,
                int(kwargs.get("target_bits", 64)),
            )
        )
        return fake_cached_proof_runner(**kwargs)

    def require_matching_cache_signatures(
        *,
        label: str,
    ) -> tuple[bool, str]:
        if len(cache_call_signatures) != 2:
            return False, f"{label} recorded {len(cache_call_signatures)} cache calls"
        left, right = cache_call_signatures
        if left != right:
            return False, f"{label} passed mismatched cache signatures {left!r} != {right!r}"
        return True, ""

    clear_project_artifacts(source)
    project_cache.drop_cached_proof_result(source=source, target_bits=64)
    safe_prove_returncode, safe_prove_stdout, safe_prove_stderr = run_safe_prove_subset(
        source,
        fake_cached_source_proof=recording_cached_proof_runner,
    )
    if safe_prove_returncode != 0:
        return False, f"initial safe prove failed: {safe_prove_stderr or safe_prove_stdout}"
    if not summary_path.exists():
        return False, f"safe prove did not create summary {summary_path}"
    summary_mtime = summary_path.stat().st_mtime_ns

    run_proofs_returncode, run_proofs_stdout, run_proofs_stderr = run_run_proofs_subset(
        ["--level", "1"],
        fixtures=[fixture],
        use_real_toolchain=False,
        fake_cached_source_proof=recording_cached_proof_runner,
    )
    if run_proofs_returncode != 0:
        return False, f"run_proofs after safe prove failed: {run_proofs_stderr or run_proofs_stdout}"
    if summary_path.stat().st_mtime_ns != summary_mtime:
        return False, "run_proofs did not reuse safe prove cache"
    if "PR11.8a checkpoint: 0 proved, 1 cached, 0 failed" not in run_proofs_stdout:
        return False, f"run_proofs did not report cache hit after safe prove {run_proofs_stdout!r}"
    if run_proofs_stderr:
        return False, f"unexpected stderr {run_proofs_stderr!r}"
    ok, detail = require_matching_cache_signatures(label="safe prove -> run_proofs")
    if not ok:
        return False, detail

    cache_call_signatures.clear()
    clear_project_artifacts(source)
    project_cache.drop_cached_proof_result(source=source, target_bits=64)
    run_proofs_returncode, run_proofs_stdout, run_proofs_stderr = run_run_proofs_subset(
        ["--level", "1"],
        fixtures=[fixture],
        use_real_toolchain=False,
        fake_cached_source_proof=recording_cached_proof_runner,
    )
    if run_proofs_returncode != 0:
        return False, f"initial run_proofs failed: {run_proofs_stderr or run_proofs_stdout}"
    if not summary_path.exists():
        return False, f"run_proofs did not create summary {summary_path}"
    summary_mtime = summary_path.stat().st_mtime_ns

    safe_prove_cached_returncode, safe_prove_cached_stdout, safe_prove_cached_stderr = run_safe_prove_subset(
        source,
        fake_cached_source_proof=recording_cached_proof_runner,
    )
    if safe_prove_cached_returncode != 0:
        return False, f"safe prove after run_proofs failed: {safe_prove_cached_stderr or safe_prove_cached_stdout}"
    if summary_path.stat().st_mtime_ns != summary_mtime:
        return False, "safe prove did not reuse run_proofs cache"
    ok, detail = require_matching_cache_signatures(label="run_proofs -> safe prove")
    if not ok:
        return False, detail
    return True, ""



def run_internal_proof_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    passed += record_result(failures, "proof-inventory-coverage", run_proof_inventory_coverage_case())
    passed += record_result(failures, "proof-eval-message-priority", run_proof_eval_message_priority_case())
    passed += record_result(failures, "proof-eval-clean-nonzero", run_proof_eval_clean_nonzero_case())
    passed += record_result(
        failures,
        "prepare-proof-toolchain-version-normalization",
        run_prepare_proof_toolchain_version_normalization_case(),
    )
    passed += record_result(
        failures,
        "prepare-proof-toolchain-version-probe-failure",
        run_prepare_proof_toolchain_version_probe_failure_case(),
    )
    passed += record_result(
        failures,
        "proof-fingerprint-gnatprove-version",
        run_proof_fingerprint_gnatprove_version_case(),
    )
    passed += record_result(
        failures,
        "cached-proof-hit-skips-emit",
        run_cached_proof_hit_skips_emit_case(),
    )
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
    passed += record_result(failures, "run_proofs no-cache", run_run_proofs_no_cache_case())
    passed += record_result(
        failures,
        "run_proofs check-mode ignores cache",
        run_run_proofs_check_mode_ignores_cache_case(),
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
    passed += record_result(failures, "run_proofs default cache", run_run_proofs_default_cache_case())
    passed += record_result(failures, "run_proofs explicit cache", run_run_proofs_explicit_cache_case())
    passed += record_result(
        failures,
        "cross-tool proof cache consistency",
        run_cross_tool_cache_consistency_case(),
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
