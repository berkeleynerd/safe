#!/usr/bin/env python3
"""Run the PR11.2 parser-completeness phase 1 gate."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    managed_scratch_root,
    read_diag_json,
    require,
    write_report,
)
from _lib.pr09_emit import (
    REPO_ROOT,
    compile_emitted_ada,
    emit_paths,
    emitted_body_file,
    repo_arg,
    run,
    run_emit,
)
from _lib.pr111_language_eval import safec_path


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr112-parser-completeness-phase1-report.json"

POSITIVE_CASES = (
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_character_case.safe",
        "mir_tags": ("char", "string"),
        "ada_snippets": ("case grade is", "when 'A' =>", 'return "excellent";'),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_discrete_case.safe",
        "mir_tags": ("string",),
        "ada_snippets": ("case flag is", "case opcode is", "when (-1) =>", 'return "unknown";'),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_string_param.safe",
        "mir_tags": ("string",),
        "ada_snippets": (
            "function echo(name : string) return string is",
            'return echo ("hello");',
            "return name;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_case_scrutinee_once.safe",
        "mir_tags": ("string",),
        "ada_snippets": ("case read_opcode is", 'return "two";'),
        "call_counts": {"read_opcode": 1},
    },
)

NEGATIVE_CASES = (
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_mutable_object.safe",
        "reason": "unsupported_source_construct",
        "message": "mutable objects of type String are outside the current PR11.2 text subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_out_param.safe",
        "reason": "unsupported_source_construct",
        "message": "string parameters currently support mode `in` only",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_field.safe",
        "reason": "unsupported_source_construct",
        "message": "record fields of type String are outside the current PR11.2 text subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_channel.safe",
        "reason": "unsupported_source_construct",
        "message": "channel element types of String are outside the current PR11.2 text subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_equality.safe",
        "reason": "unsupported_source_construct",
        "message": "string comparison and concatenation are outside the current PR11.2 text subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_initializer_type.safe",
        "reason": "source_frontend_error",
        "message": "object initializer type does not match declared type",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_index.safe",
        "reason": "unsupported_source_construct",
        "message": "string indexing is outside the current PR11.2 text subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_attribute.safe",
        "reason": "unsupported_source_construct",
        "message": "string attributes are outside the current PR11.2 text subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_array_component.safe",
        "reason": "unsupported_source_construct",
        "message": "array component types of String are outside the current PR11.2 text subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_case_on_string.safe",
        "reason": "unsupported_source_construct",
        "message": "PR11.2 case expressions are limited to Boolean, integer, and Character",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_case_range_choice.safe",
        "reason": "unsupported_source_construct",
        "message": "range case choices are outside the current PR11.2 parser-completeness subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_case_string_choice.safe",
        "reason": "unsupported_source_construct",
        "message": "case arms currently support exactly one Boolean, integer, or Character literal choice per arm",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_case_multi_choice.safe",
        "reason": "unsupported_source_construct",
        "message": "multi-choice case arms are outside the current PR11.2 parser-completeness subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_case_missing_others.safe",
        "reason": "source_frontend_error",
        "message": "case statements currently require a final `when others` arm",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_return_type.safe",
        "reason": "type_check_failure",
        "message": "return expression type does not match function result type",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_character_return_type.safe",
        "reason": "type_check_failure",
        "message": "return expression type does not match function result type",
    },
)

ROSETTA_TEXT_SAMPLES = (
    REPO_ROOT / "samples" / "rosetta" / "text" / "grade_message.safe",
    REPO_ROOT / "samples" / "rosetta" / "text" / "opcode_dispatch.safe",
)


def collect_expr_tags(payload: Any) -> set[str]:
    tags: set[str] = set()

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            tag = value.get("tag")
            if isinstance(tag, str):
                tags.add(tag)
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(payload)
    return tags


def collect_call_counts(payload: Any) -> dict[str, int]:
    counts: dict[str, int] = {}

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            if value.get("tag") == "call":
                callee = value.get("callee")
                if isinstance(callee, dict):
                    name = callee.get("name")
                    if isinstance(name, str) and name:
                        counts[name] = counts.get(name, 0) + 1
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(payload)
    return counts


def run_positive_case(
    *,
    safec: Path,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
    expected_tags: tuple[str, ...],
    expected_ada_snippets: tuple[str, ...],
    expected_call_counts: dict[str, int] | None = None,
) -> dict[str, Any]:
    root = temp_root / source.stem
    out_dir = root / "out"
    iface_dir = root / "iface"
    ada_dir = root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    check = run(
        [str(safec), "check", repo_arg(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
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
    compile_result = compile_emitted_ada(
        ada_dir=ada_dir,
        env=env,
        temp_root=temp_root,
    )

    mir_payload = json.loads(paths["mir"].read_text(encoding="utf-8"))
    observed_tags = collect_expr_tags(mir_payload)
    observed_call_counts = collect_call_counts(mir_payload)
    for tag in expected_tags:
        require(tag in observed_tags, f"{source.name}: MIR output is missing tag {tag!r}")
    if expected_call_counts:
        for name, count in expected_call_counts.items():
            require(
                observed_call_counts.get(name, 0) == count,
                f"{source.name}: expected {count} MIR call(s) to {name}, found {observed_call_counts.get(name, 0)}",
            )

    ada_text = emitted_body_file(ada_dir).read_text(encoding="utf-8")
    for snippet in expected_ada_snippets:
        require(snippet in ada_text, f"{source.name}: emitted Ada is missing {snippet!r}")

    return {
        "source": repo_arg(source),
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
        "compile": compile_result,
        "observed_mir_tags": sorted(observed_tags),
        "observed_call_counts": observed_call_counts,
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
    diag_json = run(
        [str(safec), "check", "--diag-json", repo_arg(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(diag_json["stdout"], repo_arg(source))
    require(payload["diagnostics"], f"{source.name}: expected at least one diagnostic")
    first = payload["diagnostics"][0]
    require(first["reason"] == expected_reason, f"{source.name}: diagnostic reason drifted")
    require(first["message"] == expected_message, f"{source.name}: diagnostic message drifted")
    require(first["path"] == repo_arg(source), f"{source.name}: diagnostic path drifted")

    return {
        "source": repo_arg(source),
        "reason": first["reason"],
        "message": first["message"],
        "span": first["span"],
    }


def generate_report(*, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, Any]:
    safec = safec_path()
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr112-phase1-") as temp_root:
        return {
            "task": "PR11.2",
            "status": "ok",
            "positive_fixtures": [
                run_positive_case(
                    safec=safec,
                    source=case["source"],
                    env=env,
                    temp_root=temp_root,
                    expected_tags=case["mir_tags"],
                    expected_ada_snippets=case["ada_snippets"],
                    expected_call_counts=case.get("call_counts"),
                )
                for case in POSITIVE_CASES
            ],
            "negative_boundaries": [
                run_negative_case(
                    safec=safec,
                    source=case["source"],
                    env=env,
                    temp_root=temp_root,
                    expected_reason=case["reason"],
                    expected_message=case["message"],
                )
                for case in NEGATIVE_CASES
            ],
            "rosetta_text_samples": [
                run_positive_case(
                    safec=safec,
                    source=source,
                    env=env,
                    temp_root=temp_root,
                    expected_tags=("string",),
                    expected_ada_snippets=("case ",),
                )
                for source in ROSETTA_TEXT_SAMPLES
            ],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    report = finalize_deterministic_report(
        lambda: generate_report(env=ensure_sdkroot(os.environ.copy()), scratch_root=args.scratch_root),
        label="PR11.2 parser completeness phase 1",
    )
    write_report(args.report, report)
    print(f"pr112 parser completeness phase 1: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError, json.JSONDecodeError) as exc:
        print(f"pr112 parser completeness phase 1: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
