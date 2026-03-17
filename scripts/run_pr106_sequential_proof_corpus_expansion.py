#!/usr/bin/env python3
"""Run the PR10.6 sequential proof-corpus expansion milestone gate."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.gate_expectations import (
    PR106_EXCLUDED_POSITIVE_CONCURRENCY_CASES,
    PR106_SEQUENTIAL_PROOF_CASES,
)
from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    require,
    write_report,
)
from _lib.pr09_emit import (
    REPO_ROOT,
    compile_emitted_ada,
    emitted_ada_files,
    emitted_body_file,
    emitted_spec_file,
    repo_arg,
    require_safec,
)
from _lib.pr10_emit import emit_fixture, gnatprove_emitted_ada
from _lib.pr106_sequential import (
    corpus_paths,
    excluded_positive_concurrency_paths,
    normalized_source_fragments,
    sequential_proof_corpus,
)


DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr106-sequential-proof-corpus-expansion-report.json"
)


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "command": result["command"],
        "cwd": result["cwd"],
        "returncode": result["returncode"],
    }


def normalize_source_text(text: str) -> str:
    return " ".join(text.split())


def assert_normalized_source_fragments(path: Path, fragments: list[str]) -> list[str]:
    normalized = normalize_source_text(path.read_text(encoding="utf-8"))
    for fragment in fragments:
        require(fragment in normalized, f"{display_path(path, repo_root=REPO_ROOT)} missing source fragment: {fragment}")
    return fragments


def assert_text_fragments(*, text: str, fragments: list[str], label: str) -> list[str]:
    for fragment in fragments:
        require(fragment in text, f"{label} missing required fragment: {fragment}")
    return fragments


def assert_regexes(*, text: str, patterns: list[str], label: str) -> list[str]:
    for pattern in patterns:
        require(re.search(pattern, text, flags=re.MULTILINE) is not None, f"{label} missing required pattern: {pattern}")
    return patterns


def assert_order(*, text: str, fragments: list[str], label: str) -> list[str]:
    cursor = -1
    for fragment in fragments:
        index = text.find(fragment, cursor + 1)
        require(index >= 0, f"{label} missing ordered fragment: {fragment}")
        require(index > cursor, f"{label} fragment out of order: {fragment}")
        cursor = index
    return fragments


def assert_absent_files(*, observed: list[str], forbidden: list[str], label: str) -> list[str]:
    observed_set = set(observed)
    for filename in forbidden:
        require(filename not in observed_set, f"{label} unexpectedly emitted {filename}")
    return forbidden


def verify_corpus_contract(corpus: list[dict[str, Any]]) -> dict[str, Any]:
    expected = [item["fixture"] for item in corpus]
    require(
        list(PR106_SEQUENTIAL_PROOF_CASES) == expected,
        "PR10.6 sequential proof corpus must remain the exact 27-fixture set",
    )
    require(
        corpus_paths() == expected,
        "PR10.6 sequential helper corpus paths must match the canonical 27-fixture list",
    )
    excluded = excluded_positive_concurrency_paths()
    require(
        list(PR106_EXCLUDED_POSITIVE_CONCURRENCY_CASES) == excluded,
        "PR10.6 excluded positive concurrency list must remain canonical",
    )
    require(
        set(expected).isdisjoint(excluded),
        "PR10.6 sequential proof corpus must exclude the positive-path concurrency fixtures",
    )
    require(
        "tests/positive/channel_pipeline.safe" in excluded,
        "PR10.6 must keep channel_pipeline.safe outside the sequential proof corpus",
    )
    return {
        "fixtures": expected,
        "excluded_positive_concurrency": excluded,
    }


def structural_assertions_for_fixture(
    item: dict[str, Any],
    *,
    ada_dir: Path,
    body_path: Path,
    spec_path: Path,
) -> dict[str, Any]:
    body_text = body_path.read_text(encoding="utf-8")
    spec_text = spec_path.read_text(encoding="utf-8")
    source_path = REPO_ROOT / item["fixture"]
    observed_files = emitted_ada_files(ada_dir)
    return {
        "coverage_note": item["coverage_note"],
        "source_fragments": list(assert_normalized_source_fragments(source_path, list(normalized_source_fragments(item)))),
        "spec_fragments": list(assert_text_fragments(text=spec_text, fragments=list(item.get("spec_fragments", [])), label=spec_path.name)),
        "body_fragments": list(assert_text_fragments(text=body_text, fragments=list(item.get("body_fragments", [])), label=body_path.name)),
        "spec_regexes": list(assert_regexes(text=spec_text, patterns=list(item.get("spec_regexes", [])), label=spec_path.name)),
        "body_regexes": list(assert_regexes(text=body_text, patterns=list(item.get("body_regexes", [])), label=body_path.name)),
        "body_order": list(assert_order(text=body_text, fragments=list(item.get("body_order", [])), label=body_path.name)),
        "absent_ada_files": list(assert_absent_files(observed=observed_files, forbidden=list(item.get("absent_ada_files", [])), label=display_path(ada_dir, repo_root=REPO_ROOT))),
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
            ada_dir=outputs["ada_dir"],
            body_path=body_path,
            spec_path=spec_path,
        ),
    }


def generate_report(*, env: dict[str, str]) -> dict[str, Any]:
    require_safec()
    corpus = sequential_proof_corpus()
    with tempfile.TemporaryDirectory(prefix="pr106-sequential-") as temp_root_str:
        temp_root = Path(temp_root_str)
        fixtures = [run_fixture(item, env=env, temp_root=temp_root) for item in corpus]
    return {
        "task": "PR10.6",
        "status": "ok",
        "corpus_contract": verify_corpus_contract(corpus),
        "fixtures": fixtures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env),
        label="PR10.6 sequential proof-corpus expansion",
    )
    write_report(args.report, report)
    print(f"pr10.6 sequential proof-corpus expansion: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr10.6 sequential proof-corpus expansion: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
