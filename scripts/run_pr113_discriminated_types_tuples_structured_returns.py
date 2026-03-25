#!/usr/bin/env python3
"""Run the PR11.3 discriminated-types, tuples, and structured-returns gate."""

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
    repo_arg,
    run,
    run_emit,
)
from _lib.pr111_language_eval import safec_path


DEFAULT_REPORT = (
    REPO_ROOT
    / "execution"
    / "reports"
    / "pr113-discriminated-types-tuples-structured-returns-report.json"
)

POSITIVE_CASES = (
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_discriminant_constraints.safe",
        "mir_tags": (),
        "mir_snippets": (
            '"discriminants":[',
            '"discriminant_constraints":[',
            '"name":"kind"',
            '"name":"count"',
        ),
        "typed_snippets": ('"discriminants":[', '"name":"active"', '"name":"kind"', '"name":"count"'),
        "safei_snippets": ("__constraint_packet_active_true_kind_A_count_2",),
        "ada_snippets": (
            "type packet (active : boolean := True; kind : character := 'A'; count : integer := 0) is record",
            "subtype Safe_constraint_packet_active_true_kind_A_count_1 is packet (True, 'A', 1);",
            "subtype Safe_constraint_packet_active_true_kind_A_count_2 is packet (active => True, kind => 'A', count => 2);",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_variant_guard.safe",
        "mir_tags": (),
        "mir_snippets": (
            '"variant_discriminant_name":"kind"',
            '"variant_fields":[',
            '"is_others":true',
            '"choice":{"kind":"character"',
        ),
        "typed_snippets": (
            '"variant_discriminant_name":"kind"',
            '"variant_fields":[',
            '"is_others":true',
        ),
        "safei_snippets": ("function read_alpha", "returns integer"),
        "ada_snippets": (
            "case kind is",
            "when 'A' =>",
            "when others =>",
            "case p.kind is",
            "return p.alpha;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_tuple_destructure.safe",
        "mir_tags": ("tuple",),
        "mir_snippets": ('"tuple_element_types":["boolean","integer"]',),
        "typed_snippets": (
            '"node_type":"DestructureDeclaration"',
            '"node_type":"TupleTypeSpec"',
        ),
        "safei_snippets": ("__tuple_boolean_integer",),
        "ada_snippets": (
            "type Safe_tuple_boolean_integer is record",
            "Safe_Destructure_1 : Safe_tuple_boolean_integer := lookup (True);",
            "return direct.F2;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_tuple_channel.safe",
        "mir_tags": ("tuple",),
        "mir_snippets": ('"tuple_element_types":["boolean","integer"]',),
        "typed_snippets": (
            '"tuple_element_types":["boolean","integer"]',
            '"name":"pair_ch"',
        ),
        "safei_snippets": ('"signature":"task producer"', '"signature":"task consumer"'),
        "ada_snippets": (
            "type Safe_tuple_boolean_integer is record",
            "entry Send (Value : in Safe_tuple_boolean_integer);",
            "type pair_ch_Buffer is array (pair_ch_Index) of Safe_tuple_boolean_integer;",
            "pair_ch.Send ((F1 => True, F2 => 41));",
            "payload.F1",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_structured_result.safe",
        "mir_tags": ("tuple", "string"),
        "mir_snippets": ('"tuple_element_types":["result","integer"]',),
        "typed_snippets": (
            '"identifier":"result"',
            '"node_type":"TupleTypeSpec"',
        ),
        "safei_snippets": ("__tuple_result_integer",),
        "ada_snippets": (
            "type result is record",
            "Message : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.Null_Unbounded_String;",
            "type Safe_tuple_result_integer is record",
            "function reject(msg : string) return result with Global => null,",
            "return (Ok => False, Message => Ada.Strings.Unbounded.To_Unbounded_String (msg));",
            "F1 => (Ok => True, Message => Ada.Strings.Unbounded.Null_Unbounded_String)",
        ),
    },
)

NEGATIVE_CASES = (
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_mixed_constraints.safe",
        "reason": "source_frontend_error",
        "message": "do not mix positional and named discriminant constraints",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_duplicate_named_constraint.safe",
        "reason": "source_frontend_error",
        "message": "duplicate named discriminant constraint 'kind'",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_unknown_discriminant_name.safe",
        "reason": "source_frontend_error",
        "message": "unknown discriminant name 'mode'",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_incomplete_constraints.safe",
        "reason": "source_frontend_error",
        "message": "discriminant constraints must cover every discriminant in PR11.3",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_constraint_type_mismatch.safe",
        "reason": "source_frontend_error",
        "message": "discriminant constraint value does not match discriminant type",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_constraint_out_of_range.safe",
        "reason": "source_frontend_error",
        "message": "discriminant constraint value does not match discriminant type",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_float_discriminant.safe",
        "reason": "unsupported_source_construct",
        "message": "PR11.3 discriminants currently support only boolean, character, and integer-family types",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_string_discriminant.safe",
        "reason": "unsupported_source_construct",
        "message": "PR11.3 discriminants currently support only boolean, character, and integer-family types",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_tuple_field_oob.safe",
        "reason": "source_frontend_error",
        "message": "tuple field selector is out of bounds for the tuple type",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_nested_tuple.safe",
        "reason": "unsupported_source_construct",
        "message": "tuple elements are limited to the current value-type subset in PR11.3",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_access_tuple_element.safe",
        "reason": "unsupported_source_construct",
        "message": "tuple elements are limited to the current value-type subset in PR11.3",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_variant_multi_choice.safe",
        "reason": "unsupported_source_construct",
        "message": "multi-choice variant alternatives are outside the current PR11.3 subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr113_variant_range_choice.safe",
        "reason": "unsupported_source_construct",
        "message": "range variant alternatives are outside the current PR11.3 subset",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_field.safe",
        "reason": "unsupported_source_construct",
        "message": "record fields of type String are outside the current PR11.2 text subset",
    },
)

ROSETTA_SAMPLES = (
    REPO_ROOT / "samples" / "rosetta" / "data_structures" / "parse_result.safe",
    REPO_ROOT / "samples" / "rosetta" / "text" / "lookup_pair.safe",
    REPO_ROOT / "samples" / "rosetta" / "text" / "lookup_result.safe",
)


def emitted_spec_file(ada_dir: Path) -> Path:
    candidates = sorted(path for path in ada_dir.glob("*.ads") if path.name != "safe_runtime.ads")
    require(candidates, f"{display_path(ada_dir)}: expected emitted .ads file")
    return candidates[0]


def emitted_body_file(ada_dir: Path) -> Path:
    candidates = sorted(path for path in ada_dir.glob("*.adb") if path.name != "safe_runtime.adb")
    require(candidates, f"{display_path(ada_dir)}: expected emitted .adb file")
    return candidates[0]


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


def run_positive_case(
    *,
    safec: Path,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
    expected_tags: tuple[str, ...],
    expected_mir_snippets: tuple[str, ...],
    expected_typed_snippets: tuple[str, ...],
    expected_safei_snippets: tuple[str, ...],
    expected_ada_snippets: tuple[str, ...],
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
    analyze_mir = run(
        [str(safec), "analyze-mir", "--diag-json", str(paths["mir"])],
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
    for tag in expected_tags:
        require(tag in observed_tags, f"{source.name}: MIR output is missing tag {tag!r}")
    mir_text = paths["mir"].read_text(encoding="utf-8")
    for snippet in expected_mir_snippets:
        require(snippet in mir_text, f"{source.name}: MIR output is missing {snippet!r}")
    analyze_payload = read_diag_json(analyze_mir["stdout"], display_path(paths["mir"], repo_root=REPO_ROOT))
    require(not analyze_payload["diagnostics"], f"{source.name}: expected clean analyze-mir diagnostics")

    typed_text = paths["typed"].read_text(encoding="utf-8")
    for snippet in expected_typed_snippets:
        require(snippet in typed_text, f"{source.name}: typed output is missing {snippet!r}")

    safei_text = paths["safei"].read_text(encoding="utf-8")
    for snippet in expected_safei_snippets:
        require(snippet in safei_text, f"{source.name}: safei output is missing {snippet!r}")

    ada_text = emitted_spec_file(ada_dir).read_text(encoding="utf-8") + "\n" + emitted_body_file(
        ada_dir
    ).read_text(encoding="utf-8")
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
        "analyze_mir": {
            "command": analyze_mir["command"],
            "cwd": analyze_mir["cwd"],
            "returncode": analyze_mir["returncode"],
        },
        "compile": compile_result,
        "observed_mir_tags": sorted(observed_tags),
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
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr113-gate-") as temp_root:
        return {
            "task": "PR11.3",
            "status": "ok",
            "positive_fixtures": [
                run_positive_case(
                    safec=safec,
                    source=case["source"],
                    env=env,
                    temp_root=temp_root,
                expected_tags=case["mir_tags"],
                expected_mir_snippets=case.get("mir_snippets", ()),
                expected_typed_snippets=case["typed_snippets"],
                expected_safei_snippets=case["safei_snippets"],
                expected_ada_snippets=case["ada_snippets"],
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
            "rosetta_samples": [
                run_positive_case(
                    safec=safec,
                    source=source,
                    env=env,
                    temp_root=temp_root,
                    expected_tags=("tuple",),
                    expected_mir_snippets=(),
                    expected_typed_snippets=(),
                    expected_safei_snippets=(),
                    expected_ada_snippets=(
                        "type Safe_tuple_",
                        "return ",
                    ),
                )
                for source in ROSETTA_SAMPLES
            ],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    report = finalize_deterministic_report(
        lambda: generate_report(env=ensure_sdkroot(os.environ.copy()), scratch_root=args.scratch_root),
        label="PR11.3 discriminated types, tuples, and structured returns",
    )
    write_report(args.report, report)
    print(
        "pr113 discriminated types, tuples, and structured returns: OK "
        f"({display_path(args.report, repo_root=REPO_ROOT)})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError, json.JSONDecodeError) as exc:
        print(f"pr113 discriminated types, tuples, and structured returns: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
