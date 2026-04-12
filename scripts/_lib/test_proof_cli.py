"""Proof inventory, proof-eval, and ``safe prove`` checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import subprocess
import shutil
import sys
import tempfile
from pathlib import Path

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



def run_internal_proof_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    passed += record_result(failures, "proof-inventory-coverage", run_proof_inventory_coverage_case())
    passed += record_result(failures, "proof-eval-message-priority", run_proof_eval_message_priority_case())
    passed += record_result(failures, "proof-eval-clean-nonzero", run_proof_eval_clean_nonzero_case())
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
    for label, verbose in (
        ("safe prove current directory", False),
        ("safe prove failure stage", False),
        ("safe prove verbose failure", True),
    ):
        if label == "safe prove current directory":
            result = run_safe_prove_directory_case()
        else:
            result = run_safe_prove_failure_case(verbose=verbose)
        passed += record_result(failures, label, result)

    passed += record_result(failures, "safe prove empty directory", run_safe_prove_no_sources_case())
    return passed, 0, failures
