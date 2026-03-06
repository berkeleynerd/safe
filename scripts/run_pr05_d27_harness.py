#!/usr/bin/env python3
"""Run the PR05 D27 golden and corpus harness."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr05-d27-report.json"
DIAGNOSTICS_EXIT = 1

GOLDEN_CASES = [
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_overflow.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule2_oob.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_index_oob.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule3_zero_div.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_zero_div.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule4_null_deref.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_null_deref.txt",
    ),
]

POSITIVE_CASES = [
    "tests/positive/rule1_accumulate.safe",
    "tests/positive/rule1_averaging.safe",
    "tests/positive/rule1_conversion.safe",
    "tests/positive/rule1_parameter.safe",
    "tests/positive/rule1_return.safe",
    "tests/positive/rule2_binary_search.safe",
    "tests/positive/rule2_iteration.safe",
    "tests/positive/rule2_lookup.safe",
    "tests/positive/rule2_matrix.safe",
    "tests/positive/rule2_slice.safe",
    "tests/positive/rule3_average.safe",
    "tests/positive/rule3_divide.safe",
    "tests/positive/rule3_modulo.safe",
    "tests/positive/rule3_percent.safe",
    "tests/positive/rule3_remainder.safe",
    "tests/positive/rule4_conditional.safe",
    "tests/positive/rule4_deref.safe",
    "tests/positive/rule4_factory.safe",
    "tests/positive/rule4_linked_list.safe",
    "tests/positive/rule4_optional.safe",
]

NEGATIVE_CASES = [
    "tests/negative/neg_rule1_index_fail.safe",
    "tests/negative/neg_rule1_narrow_fail.safe",
    "tests/negative/neg_rule1_overflow.safe",
    "tests/negative/neg_rule1_param_fail.safe",
    "tests/negative/neg_rule1_return_fail.safe",
    "tests/negative/neg_rule2_dynamic.safe",
    "tests/negative/neg_rule2_empty.safe",
    "tests/negative/neg_rule2_negative.safe",
    "tests/negative/neg_rule2_off_by_one.safe",
    "tests/negative/neg_rule2_oob.safe",
    "tests/negative/neg_rule3_expression.safe",
    "tests/negative/neg_rule3_variable.safe",
    "tests/negative/neg_rule3_zero_div.safe",
    "tests/negative/neg_rule3_zero_mod.safe",
    "tests/negative/neg_rule3_zero_rem.safe",
    "tests/negative/neg_rule4_freed.safe",
    "tests/negative/neg_rule4_maybe_null.safe",
    "tests/negative/neg_rule4_moved.safe",
    "tests/negative/neg_rule4_null_deref.safe",
    "tests/negative/neg_rule4_uninitialized.safe",
]

DETERMINISM_SAMPLES = [
    REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
    REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
]

CANONICAL_REASON = {
    "neg_rule1_overflow.safe": "intermediate_overflow",
    "neg_rule2_oob.safe": "index_out_of_bounds",
    "neg_rule3_zero_div.safe": "division_by_zero",
    "neg_rule4_null_deref.safe": "null_dereference",
}


def normalize_text(text: str, *, temp_root: Path | None = None) -> str:
    result = text
    if temp_root is not None:
        result = result.replace(str(temp_root), "$TMPDIR")
    return result.replace(str(REPO_ROOT), "$REPO_ROOT")


def normalize_argv(argv: list[str], *, temp_root: Path | None = None) -> list[str]:
    normalized: list[str] = []
    for item in argv:
        candidate = Path(item)
        if candidate.is_absolute():
            if temp_root is not None and temp_root in candidate.parents:
                normalized.append("$TMPDIR/" + str(candidate.relative_to(temp_root)))
            elif REPO_ROOT in candidate.parents:
                normalized.append(str(candidate.relative_to(REPO_ROOT)))
            else:
                normalized.append(candidate.name)
        else:
            normalized.append(item)
    return normalized


def find_command(name: str, fallback: Path | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def run(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    temp_root: Path | None = None,
    expected_returncode: int = 0,
) -> dict[str, Any]:
    completed = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    result = {
        "command": normalize_argv(argv, temp_root=temp_root),
        "cwd": normalize_text(str(cwd), temp_root=temp_root),
        "returncode": completed.returncode,
        "stdout": normalize_text(completed.stdout, temp_root=temp_root),
        "stderr": normalize_text(completed.stderr, temp_root=temp_root),
    }
    if completed.returncode != expected_returncode:
        raise RuntimeError(json.dumps(result, indent=2))
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"Expected diagnostic output:\n-+\n(.*)\n-+\n", text, flags=re.DOTALL)
    if not match:
        raise RuntimeError(f"could not extract expected block from {path}")
    return match.group(1).rstrip() + "\n"


def read_expected_reason(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^-- Expected:\s+REJECT\s+([a-z_]+)\s*$", text, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"missing expected reason header in {path}")
    return match.group(1)


def extract_reason(stderr: str, basename: str) -> str:
    if basename in CANONICAL_REASON:
        return CANONICAL_REASON[basename]
    match = re.search(r"error\[SC\d+\]:\s+([a-z_]+):", stderr)
    if not match:
        raise RuntimeError(f"could not extract semantic reason from stderr for {basename}")
    return match.group(1)


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        f"out/{stem}.ast.json": root / "out" / f"{stem}.ast.json",
        f"out/{stem}.typed.json": root / "out" / f"{stem}.typed.json",
        f"out/{stem}.mir.json": root / "out" / f"{stem}.mir.json",
        f"iface/{stem}.safei.json": root / "iface" / f"{stem}.safei.json",
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def tool_versions(python: str, alr: str) -> dict[str, str]:
    versions: dict[str, str] = {}
    versions["python3"] = subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stdout.strip() or subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stderr.strip()
    versions["alr"] = subprocess.run([alr, "--version"], text=True, capture_output=True, check=False).stdout.strip()
    gprbuild = shutil.which("gprbuild")
    if gprbuild:
        versions["gprbuild"] = subprocess.run([gprbuild, "--version"], text=True, capture_output=True, check=False).stdout.splitlines()[0]
    return versions


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
        expected = normalize_text(extract_expected_block(golden_path), temp_root=temp_root)
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
            [str(safec), "check", str(source_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        positives.append({"source": relative, "result": result})

    for relative in NEGATIVE_CASES:
        source_path = REPO_ROOT / relative
        result = run(
            [str(safec), "check", str(source_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=DIAGNOSTICS_EXIT,
        )
        expected_reason = read_expected_reason(source_path)
        actual_reason = extract_reason(result["stderr"], source_path.name)
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
            sample_hashes[relative] = sha256(left)
        report[str(sample.relative_to(REPO_ROOT))] = sample_hashes
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

    args.report.parent.mkdir(parents=True, exist_ok=True)

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    safec = COMPILER_ROOT / "bin" / "safec"
    require(safec.exists(), f"expected built compiler at {safec}")

    env = os.environ.copy()

    with tempfile.TemporaryDirectory(prefix="pr05-d27-") as temp_root_str:
        temp_root = Path(temp_root_str)
        report: dict[str, Any] = {
            "tool_versions": tool_versions(python, alr),
            "mode": args.mode,
        }
        if args.mode in {"all", "golden"}:
            report["golden_mode"] = run_golden_mode(safec, env, temp_root)
        if args.mode in {"all", "corpus"}:
            report["corpus_mode"] = run_corpus_mode(safec, env, temp_root)
        report["determinism"] = run_determinism_checks(safec, env, temp_root)

    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"pr05 harness: OK ({args.report})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr05 harness: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
