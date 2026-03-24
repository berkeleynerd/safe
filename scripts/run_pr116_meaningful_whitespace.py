#!/usr/bin/env python3
"""Run the PR11.6 meaningful whitespace gate."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    managed_scratch_root,
    normalize_source_text,
    normalized_source_fragments,
    read_diag_json,
    require,
    write_report,
)
from _lib.pr09_emit import (
    REPO_ROOT,
    compile_emitted_ada,
    emit_paths,
    emitted_body_file,
    emitted_spec_file,
    repo_arg,
    run,
    run_emit,
)
from _lib.pr111_language_eval import safec_path
from _lib.pr116_surface import (
    corpus_paths,
    migration_examples,
    negative_cases,
    negative_paths,
    positive_cases,
    rosetta_paths,
    rosetta_readability_cases,
)
from migrate_pr116_whitespace import rewrite_safe_source


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr116-meaningful-whitespace-report.json"


def assert_source_surface(
    path: Path,
    *,
    required_fragments: tuple[str, ...],
    forbidden_fragments: tuple[str, ...] = (),
) -> dict[str, list[str]]:
    normalized = normalize_source_text(path.read_text(encoding="utf-8"))
    required = [normalize_source_text(fragment) for fragment in required_fragments]
    forbidden = [normalize_source_text(fragment) for fragment in forbidden_fragments]
    for fragment in required:
        require(fragment in normalized, f"{path.name}: source is missing {fragment!r}")
    for fragment in forbidden:
        require(fragment not in normalized, f"{path.name}: source still contains legacy fragment {fragment!r}")
    return {
        "required_fragments": required,
        "forbidden_fragments": forbidden,
    }


def run_positive_case(
    *,
    safec: Path,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
    expected_source_fragments: tuple[str, ...],
    forbidden_source_fragments: tuple[str, ...] = (),
    expected_typed_snippets: tuple[str, ...] = (),
    expected_mir_snippets: tuple[str, ...] = (),
    expected_safei_snippets: tuple[str, ...] = (),
    expected_ada_snippets: tuple[str, ...] = (),
) -> dict[str, Any]:
    root = temp_root / source.stem
    out_dir = root / "out"
    iface_dir = root / "iface"
    ada_dir = root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    source_surface = assert_source_surface(
        source,
        required_fragments=expected_source_fragments,
        forbidden_fragments=forbidden_source_fragments,
    )

    check = run([str(safec), "check", repo_arg(source)], cwd=REPO_ROOT, env=env, temp_root=temp_root)
    emit = run_emit(
        safec=safec,
        source=source,
        out_dir=out_dir,
        iface_dir=iface_dir,
        ada_dir=ada_dir,
        env=env,
        temp_root=temp_root,
    )
    paths = emit_paths(root, source)
    for path in paths.values():
        require(path.exists(), f"{source.name}: missing emitted artifact {display_path(path, repo_root=REPO_ROOT)}")

    validate_mir = run(
        [str(safec), "validate-mir", str(paths["mir"])],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    compile_result = compile_emitted_ada(ada_dir=ada_dir, env=env, temp_root=temp_root)

    typed_text = paths["typed"].read_text(encoding="utf-8")
    mir_text = paths["mir"].read_text(encoding="utf-8")
    safei_text = paths["safei"].read_text(encoding="utf-8")
    ada_text = emitted_spec_file(ada_dir).read_text(encoding="utf-8") + "\n" + emitted_body_file(
        ada_dir
    ).read_text(encoding="utf-8")

    for snippet in expected_typed_snippets:
        require(snippet in typed_text, f"{source.name}: typed output is missing {snippet!r}")
    for snippet in expected_mir_snippets:
        require(snippet in mir_text, f"{source.name}: MIR output is missing {snippet!r}")
    for snippet in expected_safei_snippets:
        require(snippet in safei_text, f"{source.name}: safei output is missing {snippet!r}")
    for snippet in expected_ada_snippets:
        require(snippet in ada_text, f"{source.name}: emitted Ada is missing {snippet!r}")

    return {
        "source": repo_arg(source),
        "source_surface": source_surface,
        "check": {
            "command": check["command"],
            "cwd": check["cwd"],
            "returncode": check["returncode"],
        },
        "emit": {
            "command": emit["command"],
            "cwd": emit["cwd"],
            "returncode": emit["returncode"],
        },
        "validate_mir": {
            "command": validate_mir["command"],
            "cwd": validate_mir["cwd"],
            "returncode": validate_mir["returncode"],
        },
        "compile": {
            "command": compile_result["command"],
            "cwd": compile_result["cwd"],
            "returncode": compile_result["returncode"],
        },
        "typed_snippets": list(expected_typed_snippets),
        "mir_snippets": list(expected_mir_snippets),
        "safei_snippets": list(expected_safei_snippets),
        "ada_snippets": list(expected_ada_snippets),
    }


def run_negative_case(
    *,
    safec: Path,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
    expected_reason: str,
    expected_message: str,
) -> dict[str, Any]:
    result = run(
        [str(safec), "check", "--diag-json", repo_arg(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(result["stdout"], repo_arg(source))
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{source.name}: expected at least one diagnostic")
    first = diagnostics[0]
    require(first["reason"] == expected_reason, f"{source.name}: expected reason {expected_reason!r}")
    require(expected_message in first["message"], f"{source.name}: expected message containing {expected_message!r}")

    return {
        "source": repo_arg(source),
        "check": {
            "command": result["command"],
            "cwd": result["cwd"],
            "returncode": result["returncode"],
        },
        "first_diagnostic": {
            "reason": first["reason"],
            "message": first["message"],
            "path": first["path"],
        },
    }


def run_migration_example(example: dict[str, Any]) -> dict[str, Any]:
    migrated = normalize_source_text(rewrite_safe_source(example["legacy_source"]))
    required = [normalize_source_text(fragment) for fragment in example["migrated_fragments"]]
    forbidden = [normalize_source_text(fragment) for fragment in example["forbidden_fragments"]]
    for fragment in required:
        require(fragment in migrated, f"{example['name']}: migrated source is missing {fragment!r}")
    for fragment in forbidden:
        require(fragment not in migrated, f"{example['name']}: migrated source still contains {fragment!r}")
    return {
        "name": example["name"],
        "required_fragments": required,
        "forbidden_fragments": forbidden,
    }


def generate_report(*, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, Any]:
    safec = safec_path()
    positives: list[dict[str, Any]] = []
    negatives: list[dict[str, Any]] = []
    rosetta_samples: list[dict[str, Any]] = []

    with managed_scratch_root(scratch_root=scratch_root, prefix="pr116-whitespace-") as temp_root:
        for case in positive_cases():
            positives.append(
                run_positive_case(
                    safec=safec,
                    source=case["source"],
                    env=env,
                    temp_root=temp_root,
                    expected_source_fragments=tuple(normalized_source_fragments(case)),
                    forbidden_source_fragments=tuple(
                        normalized_source_fragments(case, key="forbidden_source_fragments")
                    ),
                    expected_typed_snippets=tuple(case.get("typed_snippets", ())),
                    expected_mir_snippets=tuple(case.get("mir_snippets", ())),
                    expected_safei_snippets=tuple(case.get("safei_snippets", ())),
                    expected_ada_snippets=tuple(case.get("ada_snippets", ())),
                )
            )
        for case in negative_cases():
            negatives.append(
                run_negative_case(
                    safec=safec,
                    source=case["source"],
                    env=env,
                    temp_root=temp_root,
                    expected_reason=case["reason"],
                    expected_message=case["message"],
                )
            )
        for case in rosetta_readability_cases():
            rosetta_samples.append(
                run_positive_case(
                    safec=safec,
                    source=case["source"],
                    env=env,
                    temp_root=temp_root,
                    expected_source_fragments=tuple(normalized_source_fragments(case)),
                )
            )

    return {
        "task": "PR11.6",
        "status": "ok",
        "syntax_policy": {
            "meaningful_whitespace_shipped": True,
            "pragma_strict_deferred_post_1_0": True,
            "lexer_token_stream_changed": True,
            "indentation_style": "spaces_only",
            "indentation_step": 3,
            "declare_blocks_remain_explicit": True,
        },
        "positive_fixtures": positives,
        "negative_boundaries": negatives,
        "rosetta_readability_samples": rosetta_samples,
        "migration_examples": [run_migration_example(example) for example in migration_examples()],
        "corpus_contract": {
            "positive_fixtures": corpus_paths(),
            "negative_fixtures": negative_paths(),
            "rosetta_samples": rosetta_paths(),
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report",
        type=Path,
        default=DEFAULT_REPORT,
        help=f"path to write the deterministic report (default: {display_path(DEFAULT_REPORT, repo_root=REPO_ROOT)})",
    )
    parser.add_argument("--scratch-root", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env, scratch_root=args.scratch_root),
        label="PR11.6 meaningful whitespace",
    )
    write_report(args.report, report)
    print(
        "PR11.6 meaningful whitespace report written to"
        f" {display_path(args.report, repo_root=REPO_ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
