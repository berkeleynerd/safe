#!/usr/bin/env python3
"""Run the PR06.9.5 diagnostic stability hardening gate."""

from __future__ import annotations

import argparse
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
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr0695-diagnostic-stability-report.json"
LEGACY_SOURCE = REPO_ROOT / "compiler_impl" / "tests" / "legacy_two_char_tokens.safe"

GOLDEN_CASES = [
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_overflow.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule3_zero_div.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_zero_div.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule4_null_deref.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_null_deref.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_double_move.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_double_move.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_borrow_conflict.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_borrow_conflict.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_lifetime.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_lifetime_violation.txt",
    ),
]

EXPECTED_LEGACY_DIAGNOSTICS = [
    {
        "reason": "source_frontend_error",
        "message": 'legacy token ":=" is not allowed',
        "path": "compiler_impl/tests/legacy_two_char_tokens.safe",
        "span": {"start_line": 2, "start_col": 19, "end_line": 2, "end_col": 20},
        "highlight_span": None,
        "notes": [],
        "suggestions": ["Use current Safe syntax (`=` for assignment)."],
    },
    {
        "reason": "source_frontend_error",
        "message": 'legacy token "=>" is not allowed',
        "path": "compiler_impl/tests/legacy_two_char_tokens.safe",
        "span": {"start_line": 3, "start_col": 20, "end_line": 3, "end_col": 21},
        "highlight_span": None,
        "notes": [],
        "suggestions": [
            "Use current Safe syntax (`=` for named associations/aggregates and `then` for select arms)."
        ],
    },
    {
        "reason": "source_frontend_error",
        "message": 'legacy token "/=" is not allowed',
        "path": "compiler_impl/tests/legacy_two_char_tokens.safe",
        "span": {"start_line": 4, "start_col": 19, "end_line": 4, "end_col": 20},
        "highlight_span": None,
        "notes": [],
        "suggestions": ["Use current Safe syntax (`!=` for inequality)."],
    },
]

ANALYZER_EXPECTED = {
    "tests/negative/neg_rule3_zero_div.safe": {
        "reason": "division_by_zero",
        "message": "divisor not provably nonzero",
        "path": "tests/negative/neg_rule3_zero_div.safe",
        "span": {"start_line": 14, "start_col": 16, "end_line": 14, "end_col": 16},
        "highlight_span": {"start_line": 14, "start_col": 18, "end_line": 14, "end_col": 18},
        "notes": [
            "right operand 'B' has type Value (range -100 .. 100),\nwhich includes zero.",
            "no preceding conditional or subtype constraint establishes\nB /= 0 on all paths reaching this division.",
            "rule: D27 Rule 3 (Division by Provably Nonzero Divisor)",
            "per spec/02-restrictions.md section 2.8.3 paragraph 133:\n\"The right operand of the operators /, mod, and rem shall be\nprovably nonzero at compile time.\"",
            "per spec/02-restrictions.md section 2.8.3 paragraph 134:\n\"If none of the conditions in paragraph 133 holds, the program\nis nonconforming and a conforming implementation shall reject\nthe expression with a diagnostic.\"",
        ],
        "suggestions": [
            "add a guard before the division:\nif B /= 0 then\n   return A / B;\nelse\n   return 0;  -- or handle the zero case\nend if;",
            "or use a positive subtype that excludes zero:\ntype Positive_Value is range 1 .. 100;",
        ],
    },
    "tests/negative/neg_rule4_null_deref.safe": {
        "reason": "null_dereference",
        "message": "dereference of possibly null access value",
        "path": "tests/negative/neg_rule4_null_deref.safe",
        "span": {"start_line": 14, "start_col": 14, "end_line": 14, "end_col": 18},
        "highlight_span": {"start_line": 14, "start_col": 14, "end_line": 14, "end_col": 18},
        "notes": [
            "P is of type Value_Ptr (access Value), which does not exclude null.",
            "no null check precedes this dereference on all paths reaching\nthis program point.",
            "rule: D27 Rule 4 (Not-Null Dereference)",
            "per spec/02-restrictions.md section 2.8.4 paragraph 136:\n\"Dereference of an access value shall require the access subtype\nto be not null. A conforming implementation shall reject any\ndereference where the access subtype at the point of dereference\ndoes not exclude null.\"",
        ],
        "suggestions": [
            "use a \"not null access\" subtype, or add an explicit null check:\nif P /= null then\n   return P.all;\nend if;"
        ],
    },
    "tests/negative/neg_own_borrow_conflict.safe": {
        "reason": "borrow_conflict",
        "message": "lender 'Owner' is frozen by an active mutable borrow",
        "path": "tests/negative/neg_own_borrow_conflict.safe",
        "span": {"start_line": 25, "start_col": 11, "end_line": 25, "end_col": 15},
        "highlight_span": {"start_line": 25, "start_col": 11, "end_line": 25, "end_col": 15},
        "notes": [
            "reads, writes, and moves of the lender are forbidden while the borrow is active.",
            "rule: Safe §2.3.3 (mutable borrow freezes lender)",
        ],
        "suggestions": [],
    },
}

PARITY_CASES = [
    {
        "name": "division_by_zero_parity",
        "source": REPO_ROOT / "tests" / "negative" / "neg_rule3_expression.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr0695_division_by_zero_parity.json",
    },
    {
        "name": "double_move_parity",
        "source": REPO_ROOT / "tests" / "negative" / "neg_own_inout_move.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr0695_double_move_parity.json",
    },
    {
        "name": "first_diagnostic_order",
        "source": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr0695_first_diagnostic_order.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr0695_first_diagnostic_order.json",
        "expected_first_span": {"start_line": 8, "start_col": 29, "end_line": 8, "end_col": 29},
        "candidate_spans": [
            {"start_line": 8, "start_col": 29, "end_line": 8, "end_col": 29},
            {"start_line": 10, "start_col": 29, "end_line": 10, "end_col": 29},
        ],
    },
]


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


def require_repo_command(path: Path, name: str) -> Path:
    if path.exists():
        return path
    raise FileNotFoundError(f"required repo-local command not found: {name} ({path})")


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


def ensure_sdkroot(env: dict[str, str]) -> dict[str, str]:
    if sys.platform != "darwin" or env.get("SDKROOT"):
        return env
    candidate = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
    if candidate.exists():
        updated = env.copy()
        updated["SDKROOT"] = str(candidate)
        return updated
    return env


def tool_versions(python: str, alr: str) -> dict[str, str]:
    versions: dict[str, str] = {}
    versions["python3"] = (
        subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stdout.strip()
        or subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stderr.strip()
    )
    versions["alr"] = subprocess.run([alr, "--version"], text=True, capture_output=True, check=False).stdout.strip()
    gprbuild = shutil.which("gprbuild")
    if gprbuild:
        versions["gprbuild"] = subprocess.run(
            [gprbuild, "--version"], text=True, capture_output=True, check=False
        ).stdout.splitlines()[0]
    return versions


def read_diag_json(stdout: str, source: str) -> dict[str, Any]:
    payload = json.loads(stdout)
    require(payload.get("format") == "diagnostics-v0", f"{source}: unexpected diagnostics format")
    require(isinstance(payload.get("diagnostics"), list), f"{source}: diagnostics must be a list")
    return payload


def first_diag(payload: dict[str, Any], source: str) -> dict[str, Any]:
    require(payload["diagnostics"], f"{source}: expected at least one diagnostic")
    return payload["diagnostics"][0]


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


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"Expected diagnostic output:\n-+\n(.*)\n-+\n", text, flags=re.DOTALL)
    require(match is not None, f"could not extract expected block from {path}")
    return match.group(1).rstrip() + "\n"


def run_golden_cases(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for source_path, golden_path in GOLDEN_CASES:
        result = run(
            [str(safec), "check", str(source_path.relative_to(REPO_ROOT))],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        expected = normalize_text(extract_expected_block(golden_path), temp_root=temp_root)
        require(result["stderr"] == expected, f"golden mismatch for {source_path.name}")
        results.append(
            {
                "source": str(source_path.relative_to(REPO_ROOT)),
                "golden": str(golden_path.relative_to(REPO_ROOT)),
                "check": result,
            }
        )
    return results


def run_source_frontend_cases(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    legacy_json = run(
        [str(safec), "check", "--diag-json", str(LEGACY_SOURCE.relative_to(REPO_ROOT))],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    legacy_payload = read_diag_json(legacy_json["stdout"], str(LEGACY_SOURCE))
    require(
        [diag_signature(item) for item in legacy_payload["diagnostics"]] == EXPECTED_LEGACY_DIAGNOSTICS,
        "legacy token diagnostics drifted",
    )
    legacy_human = run(
        [str(safec), "check", str(LEGACY_SOURCE.relative_to(REPO_ROOT))],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    legacy_lines = legacy_human["stderr"].splitlines()
    require(legacy_lines, "legacy token stderr must not be empty")
    require(
        legacy_lines[0] == 'legacy_two_char_tokens.safe:2:19: error: legacy token ":=" is not allowed',
        "legacy token stderr must use the basename-only header for the first diagnostic",
    )
    require(
        'legacy token ":=" is not allowed' in legacy_human["stderr"],
        "legacy token stderr must render the first diagnostic",
    )
    require(
        'legacy token "=>" is not allowed' not in legacy_human["stderr"]
        and 'legacy token "/=" is not allowed' not in legacy_human["stderr"],
        "legacy token stderr must render only the first diagnostic",
    )

    inline_cases = [
        {
            "name": "package_end_mismatch.safe",
            "text": "package Package_End_Mismatch is\nend Different_Name;\n",
            "expected": {
                "reason": "source_frontend_error",
                "message": "package end name must match declared package name",
                "span": {"start_line": 2, "start_col": 1, "end_line": 2, "end_col": 18},
                "highlight_span": None,
                "notes": ["declared `Package_End_Mismatch`, found `Different_Name`"],
                "suggestions": [],
            },
        },
        {
            "name": "oversized_integer_literal.safe",
            "text": (
                "package Oversized_Integer_Literal is\n"
                "   Value : Integer = 999999999999999999999999999999999999999;\n"
                "end Oversized_Integer_Literal;\n"
            ),
            "expected": {
                "reason": "source_frontend_error",
                "message": "integer literal is out of range",
                "span": {"start_line": 2, "start_col": 22, "end_line": 2, "end_col": 60},
                "highlight_span": None,
                "notes": ["literal `999999999999999999999999999999999999999` cannot be represented"],
                "suggestions": [],
            },
        },
    ]

    inline_results: list[dict[str, Any]] = []
    for case in inline_cases:
        source = temp_root / case["name"]
        source.write_text(case["text"], encoding="utf-8")
        diag_json = run(
            [str(safec), "check", "--diag-json", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        payload = read_diag_json(diag_json["stdout"], str(source))
        diag = first_diag(payload, str(source))
        expected = dict(case["expected"])
        expected["path"] = normalize_text(str(source), temp_root=temp_root)
        require(diag_signature(diag) == expected, f"{case['name']}: source diagnostic drifted")

        human = run(
            [str(safec), "check", str(source)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        require(source.name in human["stderr"], f"{case['name']}: stderr must use basename header")
        require(case["expected"]["message"] in human["stderr"], f"{case['name']}: missing human error")

        inline_results.append(
            {
                "source": f"$TMPDIR/{case['name']}",
                "diag_json": diag_json,
                "diagnostics": payload,
                "human": human,
            }
        )

    return {
        "legacy_tokens": {
            "diag_json": legacy_json,
            "diagnostics": legacy_payload,
            "human": legacy_human,
        },
        "inline": inline_results,
    }


def run_analyzer_source_cases(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for relative, expected in ANALYZER_EXPECTED.items():
        result = run(
            [str(safec), "check", "--diag-json", relative],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        payload = read_diag_json(result["stdout"], relative)
        diag = first_diag(payload, relative)
        require(diag_signature(diag) == expected, f"{relative}: analyzer-backed diagnostic drifted")
        require(diag["highlight_span"] is not None, f"{relative}: expected non-null highlight_span")
        require(len(payload["diagnostics"]) == 1, f"{relative}: expected exactly one diagnostic")
        results[relative] = {"check": result, "diagnostics": payload}
    return results


def run_parity_cases(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for case in PARITY_CASES:
        source_rel = str(case["source"].relative_to(REPO_ROOT))
        fixture_rel = str(case["fixture"].relative_to(REPO_ROOT))
        check_result = run(
            [str(safec), "check", "--diag-json", source_rel],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        check_payload = read_diag_json(check_result["stdout"], source_rel)
        check_diag = first_diag(check_payload, source_rel)

        analyze_result = run(
            [str(safec), "analyze-mir", "--diag-json", fixture_rel],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        analyze_payload = read_diag_json(analyze_result["stdout"], fixture_rel)
        analyze_diag = first_diag(analyze_payload, fixture_rel)

        require(
            diag_signature(check_diag) == diag_signature(analyze_diag),
            f"{case['name']}: check/analyze-mir first diagnostic drifted",
        )

        if "expected_first_span" in case:
            require(
                analyze_diag["span"] == case["expected_first_span"],
                f"{case['name']}: unexpected first-diagnostic ordering",
            )
            require(
                check_diag["span"] == case["expected_first_span"],
                f"{case['name']}: source first diagnostic ordering drifted",
            )

        results[case["name"]] = {
            "source": source_rel,
            "fixture": fixture_rel,
            "check": check_result,
            "check_diagnostics": check_payload,
            "analyze_mir": analyze_result,
            "analyze_diagnostics": analyze_payload,
        }
        if "candidate_spans" in case:
            results[case["name"]]["candidate_spans"] = case["candidate_spans"]
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    args.report.parent.mkdir(parents=True, exist_ok=True)

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    env = ensure_sdkroot(os.environ.copy())

    with tempfile.TemporaryDirectory(prefix="pr0695-diagnostics-") as temp_root_str:
        temp_root = Path(temp_root_str)
        report = {
            "task": "PR06.9.5",
            "status": "ok",
            "tool_versions": tool_versions(python, alr),
            "inputs": {
                "golden_cases": [str(path.relative_to(REPO_ROOT)) for path, _ in GOLDEN_CASES],
                "source_frontend_cases": [
                    str(LEGACY_SOURCE.relative_to(REPO_ROOT)),
                    "package_end_mismatch.safe",
                    "oversized_integer_literal.safe",
                ],
                "analyzer_cases": sorted(ANALYZER_EXPECTED),
                "parity_cases": [
                    {
                        "source": str(case["source"].relative_to(REPO_ROOT)),
                        "fixture": str(case["fixture"].relative_to(REPO_ROOT)),
                    }
                    for case in PARITY_CASES
                ],
            },
            "cases": {
                "golden": run_golden_cases(safec, env, temp_root),
                "source_frontend": run_source_frontend_cases(safec, env, temp_root),
                "analyzer_source": run_analyzer_source_cases(safec, env, temp_root),
                "parity": run_parity_cases(safec, env, temp_root),
            },
        }
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
