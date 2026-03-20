#!/usr/bin/env python3
"""Run the PR10.2 Rule 5 boundary-closure milestone gate."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

from _lib.gate_expectations import (
    ALL_DIAGNOSTIC_GOLDEN_CASES,
    PR07_RULE5_POSITIVE_CASES,
    PR102_DIAGNOSTIC_GOLDEN_CASES,
    PR102_LOOP_NEGATIVE_CASES,
    PR102_RULE5_NEGATIVE_CASES,
    PR102_RULE5_POSITIVE_CASES,
)
from _lib.harness_common import (
    compact_result,
    display_path,
    ensure_sdkroot,
    extract_expected_block,
    finalize_deterministic_report,
    managed_scratch_root,
    normalize_text,
    read_diag_json,
    read_expected_reason,
    require,
    require_repo_command,
    run,
    write_report,
)
from _lib.proof_report import (
    build_three_way_report,
    split_command_result,
    split_proof_fixtures,
)
from _lib.pr09_emit import COMPILER_ROOT, REPO_ROOT, compile_emitted_ada, repo_arg
from _lib.pr10_emit import emit_fixture, gnatprove_emitted_ada


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr102-rule5-boundary-closure-report.json"
EXPECTED_RULE5_POSITIVES = [
    "tests/positive/rule5_filter.safe",
    "tests/positive/rule5_interpolate.safe",
    "tests/positive/rule5_normalize.safe",
    "tests/positive/rule5_statistics.safe",
    "tests/positive/rule5_temperature.safe",
    "tests/positive/rule5_vector_normalize.safe",
]
EXPECTED_RULE5_NEGATIVES = [
    "tests/negative/neg_rule5_div_zero.safe",
    "tests/negative/neg_rule5_infinity.safe",
    "tests/negative/neg_rule5_nan.safe",
    "tests/negative/neg_rule5_overflow.safe",
    "tests/negative/neg_rule5_uninitialized.safe",
]
EXPECTED_LOOP_NEGATIVE = "tests/negative/neg_while_variant_not_derivable.safe"
EXPECTED_NEGATIVE_GOLDENS = [
    ("tests/negative/neg_rule5_div_zero.safe", "tests/diagnostics_golden/diag_rule5_div_zero.txt"),
    ("tests/negative/neg_rule5_infinity.safe", "tests/diagnostics_golden/diag_rule5_infinity.txt"),
    ("tests/negative/neg_rule5_nan.safe", "tests/diagnostics_golden/diag_rule5_nan.txt"),
    ("tests/negative/neg_rule5_overflow.safe", "tests/diagnostics_golden/diag_rule5_overflow.txt"),
    ("tests/negative/neg_rule5_uninitialized.safe", "tests/diagnostics_golden/diag_rule5_uninitialized.txt"),
    (
        "tests/negative/neg_while_variant_not_derivable.safe",
        "tests/diagnostics_golden/diag_loop_variant_not_derivable.txt",
    ),
]
EXPECTED_PR102_GOLDENS = [
    ("tests/negative/neg_rule5_div_zero.safe", "tests/diagnostics_golden/diag_rule5_div_zero.txt"),
    ("tests/negative/neg_rule5_infinity.safe", "tests/diagnostics_golden/diag_rule5_infinity.txt"),
    ("tests/negative/neg_rule5_overflow.safe", "tests/diagnostics_golden/diag_rule5_overflow.txt"),
    ("tests/negative/neg_rule5_uninitialized.safe", "tests/diagnostics_golden/diag_rule5_uninitialized.txt"),
    (
        "tests/negative/neg_while_variant_not_derivable.safe",
        "tests/diagnostics_golden/diag_loop_variant_not_derivable.txt",
    ),
]
PARITY_FIXTURE = REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr102_fp_unsupported_expression_parity.json"
EXPECTED_PARITY_DIAGNOSTIC = {
    "reason": "fp_unsupported_expression_at_narrowing",
    "message": "unsupported floating expression aggregate at narrowing",
    "path": "compiler_impl/tests/mir_analysis/pr102_fp_unsupported_expression_parity.safe",
    "span": {"start_line": 1, "start_col": 1, "end_line": 1, "end_col": 1},
    "highlight_span": None,
    "notes": [],
    "suggestions": [],
}

def first_diag(payload: dict[str, Any], label: str) -> dict[str, Any]:
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{label}: expected at least one diagnostic")
    return diagnostics[0]


def diag_signature(diag: dict[str, Any]) -> dict[str, Any]:
    return {
        "reason": diag["reason"],
        "message": diag["message"],
        "path": diag["path"],
        "span": diag["span"],
        "highlight_span": diag.get("highlight_span"),
        "notes": diag.get("notes", []),
        "suggestions": diag.get("suggestions", []),
    }


def verify_corpus_contract() -> dict[str, Any]:
    require(
        list(PR07_RULE5_POSITIVE_CASES) == EXPECTED_RULE5_POSITIVES[:-1],
        "PR07 Rule 5 positive corpus must remain the first five PR10.2 positives",
    )
    require(
        list(PR102_RULE5_POSITIVE_CASES) == EXPECTED_RULE5_POSITIVES,
        "PR10.2 positive Rule 5 corpus must remain the exact six-fixture set",
    )
    require(
        list(PR102_RULE5_NEGATIVE_CASES) == EXPECTED_RULE5_NEGATIVES,
        "PR10.2 Rule 5 negatives must remain the exact five-fixture set",
    )
    require(
        list(PR102_LOOP_NEGATIVE_CASES) == [EXPECTED_LOOP_NEGATIVE],
        "PR10.2 loop-boundary corpus must remain the exact single-fixture set",
    )
    require(
        list(PR102_DIAGNOSTIC_GOLDEN_CASES) == EXPECTED_PR102_GOLDENS,
        "PR10.2 diagnostic goldens must remain the exact committed set",
    )
    golden_map = set(ALL_DIAGNOSTIC_GOLDEN_CASES)
    for pair in EXPECTED_NEGATIVE_GOLDENS:
        require(pair in golden_map, f"{pair[1]} must be wired into the canonical diagnostics golden map")
    return {
        "rule5_positives": EXPECTED_RULE5_POSITIVES,
        "rule5_negatives": EXPECTED_RULE5_NEGATIVES,
        "loop_negatives": [EXPECTED_LOOP_NEGATIVE],
        "goldens": [golden for _source, golden in EXPECTED_NEGATIVE_GOLDENS],
    }


def run_positive_fixture(source: Path, *, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    fixture_root = temp_root / source.stem
    outputs = emit_fixture(source=source, root=fixture_root, env=env)
    compile_result = compile_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=fixture_root,
    )
    flow_result = gnatprove_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=fixture_root,
        mode="flow",
    )
    prove_result = gnatprove_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=fixture_root,
        mode="prove",
    )
    require(
        flow_result["summary"]["total"]["justified"]["count"] == 0,
        f"{repo_arg(source)}: flow justified checks must be zero",
    )
    require(
        flow_result["summary"]["total"]["unproved"]["count"] == 0,
        f"{repo_arg(source)}: flow unproved checks must be zero",
    )
    require(
        prove_result["summary"]["total"]["justified"]["count"] == 0,
        f"{repo_arg(source)}: justified checks must be zero",
    )
    require(
        prove_result["summary"]["total"]["unproved"]["count"] == 0,
        f"{repo_arg(source)}: unproved checks must be zero",
    )
    return {
        "fixture": repo_arg(source),
        "compile": compile_result,
        "flow": flow_result,
        "prove": prove_result,
    }


def run_negative_fixture(
    source_rel: str,
    golden_rel: str,
    *,
    safec: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    source_path = REPO_ROOT / source_rel
    golden_path = REPO_ROOT / golden_rel

    diag_json = run(
        [str(safec), "check", "--diag-json", source_rel],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(diag_json["stdout"], source_rel)
    require(len(payload["diagnostics"]) == 1, f"{source_rel}: expected exactly one diagnostic")
    diag = first_diag(payload, source_rel)
    expected_reason = read_expected_reason(source_path)
    require(diag["reason"] == expected_reason, f"{source_rel}: reason drifted")

    human = run(
        [str(safec), "check", source_rel],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    expected_human = normalize_text(extract_expected_block(golden_path), temp_root=temp_root)
    require(human["stderr"] == expected_human, f"{source_rel}: golden mismatch")

    return {
        "fixture": source_rel,
        "golden": golden_rel,
        "expected_reason": expected_reason,
        "diagnostic": diag_signature(diag),
        "check_diag_json": compact_result(diag_json),
        "check_human": compact_result(human),
    }


def run_parity_fixture(*, safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    fixture_rel = display_path(PARITY_FIXTURE, repo_root=REPO_ROOT)
    analyze = run(
        [str(safec), "analyze-mir", "--diag-json", fixture_rel],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(analyze["stdout"], fixture_rel)
    require(len(payload["diagnostics"]) == 1, f"{fixture_rel}: expected exactly one diagnostic")
    diag = first_diag(payload, fixture_rel)
    signature = diag_signature(diag)
    require(signature == EXPECTED_PARITY_DIAGNOSTIC, f"{fixture_rel}: parity diagnostic drifted")
    require(
        diag["reason"] != "fp_overflow_at_narrowing",
        f"{fixture_rel}: unsupported float shape must not be mislabeled as overflow",
    )
    return {
        "fixture": fixture_rel,
        "analyze_mir": compact_result(analyze),
        "diagnostic": signature,
    }


def split_negative_fixture(fixture: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    diag_canonical, diag_machine = split_command_result(fixture["check_diag_json"])
    human_canonical, human_machine = split_command_result(fixture["check_human"])
    canonical = {
        "fixture": fixture["fixture"],
        "golden": fixture["golden"],
        "expected_reason": fixture["expected_reason"],
        "diagnostic": fixture["diagnostic"],
        "check_diag_json": diag_canonical,
        "check_human": human_canonical,
    }
    machine = {
        "fixture": fixture["fixture"],
        "check_diag_json": diag_machine,
        "check_human": human_machine,
    }
    return canonical, machine


def split_parity_fixture(fixture: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    analyze_canonical, analyze_machine = split_command_result(fixture["analyze_mir"])
    canonical = {
        "fixture": fixture["fixture"],
        "diagnostic": fixture["diagnostic"],
        "analyze_mir": analyze_canonical,
    }
    machine = {
        "fixture": fixture["fixture"],
        "analyze_mir": analyze_machine,
    }
    return canonical, machine


def generate_report(*, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, Any]:
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr102-rule5-") as temp_root:
        positive_fixtures = [
            run_positive_fixture(REPO_ROOT / source_rel, env=env, temp_root=temp_root)
            for source_rel in EXPECTED_RULE5_POSITIVES
        ]
        negative_fixtures = [
            run_negative_fixture(source_rel, golden_rel, safec=safec, env=env, temp_root=temp_root)
            for source_rel, golden_rel in EXPECTED_NEGATIVE_GOLDENS
        ]
        parity_fixture = run_parity_fixture(safec=safec, env=env, temp_root=temp_root)

    semantic_floor, canonical_positive, machine_positive = split_proof_fixtures(positive_fixtures)
    canonical_negative: list[dict[str, Any]] = []
    machine_negative: list[dict[str, Any]] = []
    for fixture in negative_fixtures:
        canonical, machine = split_negative_fixture(fixture)
        canonical_negative.append(canonical)
        machine_negative.append(machine)
    canonical_parity, machine_parity = split_parity_fixture(parity_fixture)
    return build_three_way_report(
        identity={
            "task": "PR10.2",
        },
        semantic_floor=semantic_floor,
        canonical_proof_detail={
            "contract": verify_corpus_contract(),
            "positive_rule5_corpus": canonical_positive,
            "negative_diagnostics": canonical_negative,
            "mir_parity": canonical_parity,
            "notes": [
                "PR10.2 closes the live accepted Rule 5 surface by merging the PR07 Rule 5 positives with the frozen PR10 Rule 5 emitted representative.",
                "Rule 5 remains a narrowing-point proof boundary: IEEE 754 intermediate NaN and infinity are allowed, but narrowing points must be provably safe.",
                "While-loop conditions outside the current derivable Loop_Variant surface are rejected during safec check rather than deferred to emitted GNATprove failure.",
            ],
        },
        machine_sensitive={
            "positive_rule5_corpus": machine_positive,
            "negative_diagnostics": machine_negative,
            "mir_parity": machine_parity,
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env, scratch_root=args.scratch_root),
        label="PR10.2 Rule 5 boundary closure",
    )
    write_report(args.report, report)
    print(f"pr10.2 rule5 boundary closure: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr10.2 rule5 boundary closure: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
