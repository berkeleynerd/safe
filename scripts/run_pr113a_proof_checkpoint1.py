#!/usr/bin/env python3
"""Run the PR11.3a proof-checkpoint 1 gate."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

from _lib.gate_expectations import (
    PR113A_EXCLUDED_POSITIVE_CONCURRENCY_CASES,
    PR113A_SEQUENTIAL_PROOF_CASES,
)
from _lib.harness_common import (
    assert_order,
    assert_regexes,
    assert_text_fragments,
    compact_result,
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    managed_scratch_root,
    require,
    write_report,
)
from _lib.proof_report import build_three_way_report, split_proof_fixtures
from _lib.pr09_emit import (
    REPO_ROOT,
    compile_emitted_ada,
    emitted_body_file,
    emitted_spec_file,
    repo_arg,
    require_safec,
)
from _lib.pr10_emit import emit_fixture, gnatprove_emitted_ada
from _lib.pr113a_sequential import (
    corpus_paths,
    excluded_positive_concurrency_paths,
    normalize_source_text,
    normalized_source_fragments,
    sequential_proof_corpus,
)


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr113a-proof-checkpoint1-report.json"

def assert_normalized_source_fragments(path: Path, fragments: list[str]) -> list[str]:
    normalized = normalize_source_text(path.read_text(encoding="utf-8"))
    for fragment in fragments:
        require(fragment in normalized, f"{display_path(path, repo_root=REPO_ROOT)} missing source fragment: {fragment}")
    return fragments


def verify_corpus_contract(corpus: list[dict[str, Any]]) -> dict[str, Any]:
    expected = [item["fixture"] for item in corpus]
    require(
        list(PR113A_SEQUENTIAL_PROOF_CASES) == expected,
        "PR11.3a sequential proof corpus must remain the exact 11-fixture checkpoint set",
    )
    require(
        corpus_paths() == expected,
        "PR11.3a sequential helper corpus paths must match the canonical 11-fixture list",
    )
    excluded = excluded_positive_concurrency_paths()
    require(
        list(PR113A_EXCLUDED_POSITIVE_CONCURRENCY_CASES) == excluded,
        "PR11.3a excluded positive concurrency list must remain canonical",
    )
    require(
        set(expected).isdisjoint(excluded),
        "PR11.3a sequential proof corpus must exclude the positive-path tuple-channel fixture",
    )
    require(
        excluded == ["tests/positive/pr113_tuple_channel.safe"],
        "PR11.3a must keep pr113_tuple_channel.safe outside the sequential proof corpus",
    )
    return {
        "fixtures": expected,
        "excluded_positive_concurrency": excluded,
    }


def structural_assertions_for_fixture(
    item: dict[str, Any],
    *,
    body_path: Path,
    spec_path: Path,
) -> dict[str, Any]:
    body_text = body_path.read_text(encoding="utf-8")
    spec_text = spec_path.read_text(encoding="utf-8")
    source_path = REPO_ROOT / item["fixture"]
    return {
        "coverage_note": item["coverage_note"],
        "source_fragments": list(assert_normalized_source_fragments(source_path, list(normalized_source_fragments(item)))),
        "spec_fragments": list(assert_text_fragments(text=spec_text, fragments=list(item.get("spec_fragments", [])), label=spec_path.name)),
        "body_fragments": list(assert_text_fragments(text=body_text, fragments=list(item.get("body_fragments", [])), label=body_path.name)),
        "spec_regexes": list(assert_regexes(text=spec_text, patterns=list(item.get("spec_regexes", [])), label=spec_path.name)),
        "body_regexes": list(assert_regexes(text=body_text, patterns=list(item.get("body_regexes", [])), label=body_path.name)),
        "body_order": list(assert_order(text=body_text, fragments=list(item.get("body_order", [])), label=body_path.name)),
    }


def run_fixture(item: dict[str, Any], *, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    source = REPO_ROOT / item["fixture"]
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
    body_path = emitted_body_file(outputs["ada_dir"])
    spec_path = emitted_spec_file(outputs["ada_dir"])
    return {
        "fixture": item["fixture"],
        "family": item["family"],
        "compile": compact_result(compile_result),
        "flow": {
            "command": flow_result["command"],
            "cwd": flow_result["cwd"],
            "returncode": flow_result["returncode"],
            "summary": flow_result["summary"],
        },
        "prove": {
            "command": prove_result["command"],
            "cwd": prove_result["cwd"],
            "returncode": prove_result["returncode"],
            "summary": prove_result["summary"],
        },
        "structural_assertions": structural_assertions_for_fixture(
            item,
            body_path=body_path,
            spec_path=spec_path,
        ),
    }


def generate_report(*, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, Any]:
    require_safec()
    corpus = sequential_proof_corpus()
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr113a-proof-") as temp_root:
        fixtures = [run_fixture(item, env=env, temp_root=temp_root) for item in corpus]
    semantic_floor, canonical_fixtures, machine_fixtures = split_proof_fixtures(fixtures)
    return build_three_way_report(
        identity={
            "task": "PR11.3a",
            "status": "ok",
        },
        semantic_floor=semantic_floor,
        canonical_proof_detail={
            "corpus_contract": verify_corpus_contract(corpus),
            "fixtures": canonical_fixtures,
        },
        machine_sensitive={
            "fixtures": machine_fixtures,
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
        label="PR11.3a proof checkpoint 1",
    )
    write_report(args.report, report)
    print(f"pr11.3a proof checkpoint 1: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr11.3a proof checkpoint 1: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
