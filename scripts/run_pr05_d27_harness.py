#!/usr/bin/env python3
"""Run the PR05 D27 golden and corpus harness."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.gate_expectations import D27_GOLDEN_CASES, PR05_NEGATIVE_CASES, PR05_POSITIVE_CASES, REPRESENTATIVE_EMIT_SAMPLES
from _lib.harness_common import (
    display_path,
    extract_expected_block,
    finalize_deterministic_report,
    find_command,
    read_diag_json,
    read_expected_reason,
    require,
    require_repo_command,
    run,
    stable_emitted_artifact_sha256,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr05-d27-report.json"
DIAGNOSTICS_EXIT = 1

GOLDEN_CASES = [(REPO_ROOT / source, REPO_ROOT / golden) for source, golden in D27_GOLDEN_CASES]
POSITIVE_CASES = PR05_POSITIVE_CASES
NEGATIVE_CASES = PR05_NEGATIVE_CASES

DETERMINISM_SAMPLES = [
    REPO_ROOT / path for path in REPRESENTATIVE_EMIT_SAMPLES
]

MIR_VALIDATION_SAMPLES = [
    REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
    REPO_ROOT / "tests" / "positive" / "rule3_divide.safe",
    REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
    REPO_ROOT / "tests" / "positive" / "rule4_linked_list.safe",
]

def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        f"out/{stem}.ast.json": root / "out" / f"{stem}.ast.json",
        f"out/{stem}.typed.json": root / "out" / f"{stem}.typed.json",
        f"out/{stem}.mir.json": root / "out" / f"{stem}.mir.json",
        f"iface/{stem}.safei.json": root / "iface" / f"{stem}.safei.json",
    }


def run_golden_mode(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for source_path, golden_path in GOLDEN_CASES:
        result = run(
            [str(safec), "check", str(source_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=DIAGNOSTICS_EXIT,
        )
        expected = extract_expected_block(golden_path).replace(str(temp_root), "$TMPDIR")
        require(
            result["stderr"] == expected,
            f"golden mismatch for {source_path.name}",
        )
        results.append(
            {
                "source": str(source_path.relative_to(REPO_ROOT)),
                "golden": str(golden_path.relative_to(REPO_ROOT)),
                "result": result,
            }
        )
    return results


def run_corpus_mode(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, list[dict[str, Any]]]:
    positives: list[dict[str, Any]] = []
    negatives: list[dict[str, Any]] = []

    for relative in POSITIVE_CASES:
        source_path = REPO_ROOT / relative
        result = run(
            [str(safec), "check", "--diag-json", str(source_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        payload = read_diag_json(result["stdout"], relative)
        require(payload["diagnostics"] == [], f"{relative}: expected no diagnostics")
        positives.append({"source": relative, "result": result, "diagnostics": payload})

    for relative in NEGATIVE_CASES:
        source_path = REPO_ROOT / relative
        result = run(
            [str(safec), "check", "--diag-json", str(source_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=DIAGNOSTICS_EXIT,
        )
        payload = read_diag_json(result["stdout"], relative)
        require(payload["diagnostics"], f"{relative}: expected at least one diagnostic")
        expected_reason = read_expected_reason(source_path)
        actual_reason = payload["diagnostics"][0]["reason"]
        require(
            actual_reason == expected_reason,
            f"reason mismatch for {relative}: expected {expected_reason}, got {actual_reason}",
        )
        negatives.append(
            {
                "source": relative,
                "expected_reason": expected_reason,
                "actual_reason": actual_reason,
                "result": result,
                "diagnostics": payload,
            }
        )

    return {"positives": positives, "negatives": negatives}


def run_determinism_checks(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, dict[str, str]]:
    report: dict[str, dict[str, str]] = {}
    for sample in DETERMINISM_SAMPLES:
        emit_a_root = temp_root / f"{sample.stem}-a"
        emit_b_root = temp_root / f"{sample.stem}-b"
        for root in (emit_a_root, emit_b_root):
            run(
                [
                    str(safec),
                    "emit",
                    str(sample),
                    "--out-dir",
                    str(root / "out"),
                    "--interface-dir",
                    str(root / "iface"),
                ],
                cwd=REPO_ROOT,
                env=env,
                temp_root=temp_root,
            )
        sample_hashes: dict[str, str] = {}
        for relative, left in emitted_paths(emit_a_root, sample).items():
            right = emit_b_root / relative
            left_bytes = left.read_bytes()
            right_bytes = right.read_bytes()
            require(left_bytes == right_bytes, f"non-deterministic emit output for {sample.name}::{relative}")
            sample_hashes[relative] = stable_emitted_artifact_sha256(left, temp_root=temp_root)
        report[str(sample.relative_to(REPO_ROOT))] = sample_hashes
    return report


def run_mir_validation(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for sample in MIR_VALIDATION_SAMPLES:
        root = temp_root / f"{sample.stem}-mir"
        emit_result = run(
            [
                str(safec),
                "emit",
                str(sample),
                "--out-dir",
                str(root / "out"),
                "--interface-dir",
                str(root / "iface"),
            ],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        mir_path = root / "out" / f"{sample.stem.lower()}.mir.json"
        validate_result = run(
            [str(safec), "validate-mir", str(mir_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        results.append(
            {
                "source": str(sample.relative_to(REPO_ROOT)),
                "emit": emit_result,
                "validate": validate_result,
            }
        )
    return results


def generate_report(*, mode: str, safec: Path, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr05-d27-") as temp_root_str:
        temp_root = Path(temp_root_str)
        report: dict[str, Any] = {
            "mode": mode,
        }
        if mode in {"all", "golden"}:
            report["golden_mode"] = run_golden_mode(safec, env, temp_root)
        if mode in {"all", "corpus"}:
            report["corpus_mode"] = run_corpus_mode(safec, env, temp_root)
        report["determinism"] = run_determinism_checks(safec, env, temp_root)
        report["mir_validation"] = run_mir_validation(safec, env, temp_root)
        return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=["all", "golden", "corpus"],
        default="all",
        help="Run the golden diff set, the full corpus gate, or both.",
    )
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    find_command("python3")
    find_command("alr", Path.home() / "bin" / "alr")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    require(safec.exists(), f"expected built compiler at {safec}")

    env = os.environ.copy()
    report = finalize_deterministic_report(
        lambda: generate_report(mode=args.mode, safec=safec, env=env),
        label="PR05",
    )

    write_report(args.report, report)
    print(f"pr05 harness: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr05 harness: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
