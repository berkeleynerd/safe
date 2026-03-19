#!/usr/bin/env python3
"""Run the PR06.9.6 unsupported-feature boundary hardening gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from _lib.harness_common import (
    display_path,
    finalize_deterministic_report,
    find_command,
    normalize_text,
    read_diag_json,
    require,
    require_repo_command,
    run,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr0696-unsupported-feature-boundary-report.json"
)
LEGACY_SOURCE = REPO_ROOT / "compiler_impl" / "tests" / "legacy_two_char_tokens.safe"
LEGACY_SOURCE_ARG = str(LEGACY_SOURCE.relative_to(REPO_ROOT))

EXPECTED_LEGACY_DIAGNOSTICS = [
    {
        "reason": "source_frontend_error",
        "message": 'legacy token ":=" is not allowed',
        "path": "compiler_impl/tests/legacy_two_char_tokens.safe",
        "span": {"start_line": 2, "start_col": 19, "end_line": 2, "end_col": 20},
        "highlight_span": None,
    },
    {
        "reason": "source_frontend_error",
        "message": 'legacy token "=>" is not allowed',
        "path": "compiler_impl/tests/legacy_two_char_tokens.safe",
        "span": {"start_line": 3, "start_col": 20, "end_line": 3, "end_col": 21},
        "highlight_span": None,
    },
    {
        "reason": "source_frontend_error",
        "message": 'legacy token "/=" is not allowed',
        "path": "compiler_impl/tests/legacy_two_char_tokens.safe",
        "span": {"start_line": 4, "start_col": 19, "end_line": 4, "end_col": 20},
        "highlight_span": None,
    },
]

CONTROL_INLINE_CASES = [
    {
        "name": "package_end_mismatch.safe",
        "text": "package Package_End_Mismatch is\nend Different_Name;\n",
        "expected_reason": "source_frontend_error",
        "expected_message": "package end name must match declared package name",
        "expected_header": "package_end_mismatch.safe:2:1: error: package end name must match declared package name",
    },
    {
        "name": "oversized_integer_literal.safe",
        "text": (
            "package Oversized_Integer_Literal is\n"
            "   Value : Integer = 999999999999999999999999999999999999999;\n"
            "end Oversized_Integer_Literal;\n"
        ),
        "expected_reason": "source_frontend_error",
        "expected_message": "integer literal is out of range",
        "expected_header": "oversized_integer_literal.safe:2:22: error: integer literal is out of range",
    },
]

UNSUPPORTED_CASES = [
    {
        "name": "fixed_point.safe",
        "text": (
            "package Fixed_Point is\n"
            "   type Money is delta 0.01 range -100.00 to 100.00;\n"
            "end Fixed_Point;\n"
        ),
        "expected_reason": "unsupported_source_construct",
    },
    {
        "name": "delay_until",
        "source": REPO_ROOT / "tests" / "negative" / "neg_delay_until.safe",
        "expected_reason": "unsupported_source_construct",
    },
    {
        "name": "statement_label_assignment",
        "source": REPO_ROOT / "tests" / "negative" / "neg_statement_label_assignment.safe",
        "expected_reason": "unsupported_source_construct",
    },
    {
        "name": "named_number_unsupported",
        "source": REPO_ROOT / "tests" / "negative" / "neg_named_number_unsupported.safe",
        "expected_reason": "unsupported_source_construct",
    },
    {
        "name": "generic_case.safe",
        "text": "generic\npackage Generic_Case is\nend Generic_Case;\n",
        "expected_reason": "unsupported_source_construct",
    },
    {
        "name": "exception_case.safe",
        "text": "package Exception_Case is\n   E : exception;\nend Exception_Case;\n",
        "expected_reason": "unsupported_source_construct",
    },
    {
        "name": "string_equality",
        "source": REPO_ROOT / "tests" / "negative" / "neg_string_equality.safe",
        "expected_reason": "unsupported_source_construct",
    },
    {
        "name": "protected_case.safe",
        "text": (
            "package Protected_Case is\n"
            "   protected Lock is\n"
            "   end Lock;\n"
            "end Protected_Case;\n"
        ),
        "expected_reason": "unsupported_source_construct",
    },
]


def first_stderr_line(result: Dict[str, Any], label: str) -> str:
    lines = result["stderr"].splitlines()
    require(lines, f"{label}: expected stderr output")
    return lines[0]


def ensure_no_internal_failure(result: Dict[str, Any], label: str) -> None:
    combined = f"{result['stdout']}\n{result['stderr']}".lower()
    require("internal error" not in combined, f"{label}: unexpected internal error wording")
    require("internal failure" not in combined, f"{label}: unexpected internal failure wording")


def observed_artifacts(directory: Path) -> List[str]:
    if not directory.exists():
        return []
    return sorted(str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file())


def ensure_no_emit_artifacts(out_dir: Path, iface_dir: Path, label: str) -> Dict[str, List[str]]:
    out_files = observed_artifacts(out_dir)
    iface_files = observed_artifacts(iface_dir)
    require(not out_files, f"{label}: emit unexpectedly wrote output artifacts {out_files}")
    require(not iface_files, f"{label}: emit unexpectedly wrote interface artifacts {iface_files}")
    return {"out_files": out_files, "iface_files": iface_files}


def validate_legacy_control_case(safec: Path, temp_root: Path) -> Dict[str, Any]:
    diag_json = run(
        [str(safec), "check", "--diag-json", LEGACY_SOURCE_ARG],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(diag_json["stdout"], str(LEGACY_SOURCE))
    require(len(payload["diagnostics"]) == 3, "legacy token fixture: expected three diagnostics")
    for expected, actual in zip(EXPECTED_LEGACY_DIAGNOSTICS, payload["diagnostics"]):
        require(actual["reason"] == expected["reason"], "legacy token fixture: reason drifted")
        require(actual["message"] == expected["message"], "legacy token fixture: message drifted")
        require(
            actual["path"] == LEGACY_SOURCE_ARG,
            "legacy token fixture: diagnostics path must preserve the CLI source path",
        )
        require(actual["span"] == expected["span"], "legacy token fixture: span drifted")
        require(
            actual["highlight_span"] == expected["highlight_span"],
            "legacy token fixture: highlight_span drifted",
        )

    human = run(
        [str(safec), "check", LEGACY_SOURCE_ARG],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )
    ensure_no_internal_failure(human, "legacy token fixture")
    lines = human["stderr"].splitlines()
    require(lines, "legacy token fixture: expected stderr lines")
    require(
        lines[0] == 'legacy_two_char_tokens.safe:2:19: error: legacy token ":=" is not allowed',
        "legacy token fixture: human stderr must keep the basename-only first diagnostic header",
    )
    require(
        not any(line.startswith("legacy_two_char_tokens.safe:3:") for line in lines),
        "legacy token fixture: human stderr must render only the first diagnostic",
    )
    require(
        not any(line.startswith("legacy_two_char_tokens.safe:4:") for line in lines),
        "legacy token fixture: human stderr must render only the first diagnostic",
    )

    return {
        "name": "legacy_two_char_tokens",
        "source": "compiler_impl/tests/legacy_two_char_tokens.safe",
        "diag_json": diag_json,
        "diagnostics": payload["diagnostics"],
        "human": human,
    }


def validate_inline_control_case(
    safec: Path,
    temp_root: Path,
    case: Dict[str, str],
) -> Dict[str, Any]:
    source = temp_root / case["name"]
    source.write_text(case["text"], encoding="utf-8")

    diag_json = run(
        [str(safec), "check", "--diag-json", str(source)],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(diag_json["stdout"], case["name"])
    require(payload["diagnostics"], f"{case['name']}: expected at least one diagnostic")
    first = payload["diagnostics"][0]
    require(first["reason"] == case["expected_reason"], f"{case['name']}: wrong reason")
    require(first["message"] == case["expected_message"], f"{case['name']}: wrong message")
    require(
        first["path"] == normalize_text(str(source), temp_root=temp_root),
        f"{case['name']}: diagnostics path must preserve the CLI path",
    )
    require(first["highlight_span"] is None, f"{case['name']}: highlight_span must be null")

    human = run(
        [str(safec), "check", str(source)],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )
    ensure_no_internal_failure(human, case["name"])
    require(
        first_stderr_line(human, case["name"]) == case["expected_header"],
        f"{case['name']}: human stderr header drifted",
    )

    return {
        "name": case["name"],
        "source": "$TMPDIR/" + case["name"],
        "diag_json": diag_json,
        "diagnostics": payload["diagnostics"],
        "human": human,
    }


def materialize_case_source(temp_root: Path, case: Dict[str, Any]) -> Tuple[Path, str]:
    source = case.get("source")
    if source is not None:
        path = Path(source)
        return path, str(path.relative_to(REPO_ROOT))
    name = case["name"]
    path = temp_root / name
    path.write_text(case["text"], encoding="utf-8")
    return path, str(path)


def validate_unsupported_case(
    safec: Path,
    temp_root: Path,
    case: Dict[str, Any],
) -> Dict[str, Any]:
    source, cli_source = materialize_case_source(temp_root, case)
    source_label = normalize_text(cli_source, temp_root=temp_root)

    diag_json = run(
        [str(safec), "check", "--diag-json", cli_source],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(diag_json["stdout"], case["name"])
    require(payload["diagnostics"], f"{case['name']}: expected at least one diagnostic")
    first = payload["diagnostics"][0]
    require(first["reason"] == case["expected_reason"], f"{case['name']}: wrong reason")
    require(
        first["path"] == source_label,
        f"{case['name']}: diagnostics path must preserve the CLI path",
    )

    check_human = run(
        [str(safec), "check", cli_source],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )
    ast_human = run(
        [str(safec), "ast", cli_source],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )

    out_dir = temp_root / (source.stem + "-out")
    iface_dir = temp_root / (source.stem + "-iface")
    emit_human = run(
        [
            str(safec),
            "emit",
            cli_source,
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
        temp_root=temp_root,
        expected_returncode=1,
    )

    for label, result in (
        (case["name"] + " check", check_human),
        (case["name"] + " ast", ast_human),
        (case["name"] + " emit", emit_human),
    ):
        ensure_no_internal_failure(result, label)

    check_header = first_stderr_line(check_human, case["name"] + " check")
    require(
        check_header.startswith(source.name + ":"),
        f"{case['name']}: check stderr must use a basename-only header",
    )
    require(
        first_stderr_line(ast_human, case["name"] + " ast") == check_header,
        f"{case['name']}: ast must fail with the same first message as check",
    )
    require(
        first_stderr_line(emit_human, case["name"] + " emit") == check_header,
        f"{case['name']}: emit must fail with the same first message as check",
    )

    artifacts = ensure_no_emit_artifacts(out_dir, iface_dir, case["name"])

    return {
        "name": case["name"],
        "source": source_label,
        "check_diag_json": diag_json,
        "diagnostics": payload["diagnostics"],
        "check": check_human,
        "ast": ast_human,
        "emit": emit_human,
        "emit_artifacts": artifacts,
    }


def generate_report(
    *,
    safec: Path,
    temp_root: Path,
) -> Dict[str, Any]:
    control_cases = {
        "legacy_tokens": validate_legacy_control_case(safec, temp_root),
        "frontend_inline": [
            validate_inline_control_case(safec, temp_root, case) for case in CONTROL_INLINE_CASES
        ],
    }
    unsupported_cases = [
        validate_unsupported_case(safec, temp_root, case) for case in UNSUPPORTED_CASES
    ]

    return {
        "task": "PR06.9.6",
        "status": "ok",
        "control_cases": control_cases,
        "unsupported_cases": unsupported_cases,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    find_command("python3")
    find_command("alr", Path.home() / "bin" / "alr")

    def build_report() -> Dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="pr0696-unsupported-") as temp_dir:
            temp_root = Path(temp_dir)
            return generate_report(
                safec=safec,
                temp_root=temp_root,
            )

    report = finalize_deterministic_report(
        build_report,
        label="PR06.9.6 unsupported-feature boundary",
    )
    write_report(args.report, report)

    print(f"wrote {display_path(args.report, repo_root=REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
