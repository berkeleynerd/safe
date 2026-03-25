#!/usr/bin/env python3
"""Run the PR07 Rule 5 and result-record safety gate."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from _lib.gate_expectations import (
    PR07_RESULT_NEGATIVE_CASES,
    PR07_RESULT_POSITIVE_CASES,
    PR07_RULE5_NEGATIVE_CASES,
    PR07_RULE5_POSITIVE_CASES,
    RESULT_GOLDEN_CASES,
    D27_GOLDEN_CASES,
)
from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    extract_expected_block,
    finalize_deterministic_report,
    find_command,
    normalize_text,
    read_diag_json,
    read_expected_reason,
    require,
    require_repo_command,
    run,
    write_report,
)
from migrate_pr116_whitespace import rewrite_safe_source as rewrite_pr116_whitespace_source
from migrate_pr1162_legacy_syntax import rewrite_safe_source as rewrite_pr1162_legacy_source
from migrate_pr117_reference_surface import rewrite_safe_source as rewrite_pr117_reference_surface_source


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr07-rule5-result-safety-report.json"
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"

RULE5_POSITIVES = [REPO_ROOT / path for path in PR07_RULE5_POSITIVE_CASES]
RULE5_NEGATIVES = [REPO_ROOT / path for path in PR07_RULE5_NEGATIVE_CASES]
RESULT_POSITIVES = [REPO_ROOT / path for path in PR07_RESULT_POSITIVE_CASES]
RESULT_NEGATIVES = [REPO_ROOT / path for path in PR07_RESULT_NEGATIVE_CASES]

GOLDEN_CASES = [
    (REPO_ROOT / "tests" / "negative" / "neg_rule5_nan.safe", REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_nan.txt"),
    (REPO_ROOT / "tests" / "negative" / "neg_result_unguarded.safe", REPO_ROOT / "tests" / "diagnostics_golden" / "diag_result_unguarded.txt"),
    (REPO_ROOT / "tests" / "negative" / "neg_result_mutated.safe", REPO_ROOT / "tests" / "diagnostics_golden" / "diag_result_mutated.txt"),
]

INLINE_NEGATIVE_CASES = [
    {
        "name": "result_wrong_boolean_flag",
        "expected_reason": "discriminant_check_not_established",
        "source": """package result_wrong_boolean_flag is

   type error_code is range 0 to 255;

   type parse_result (ok : boolean = false) is record
      ready : boolean;
      case ok is
         when true  then value : integer;
         when false then error : error_code;
      end case;
   end record;

   function unsafe returns integer is
      r : parse_result = (ok = true, ready = true, value = 7);
   begin
      if r.ready then
         return r.value;
      else
         return 0;
      end if;
   end unsafe;

end result_wrong_boolean_flag;
""",
    },
    {
        "name": "rule5_conversion_narrowing",
        "expected_reason": "fp_overflow_at_narrowing",
        "source": """package rule5_conversion_narrowing is

   type narrow is digits 6 range -1.0 to 1.0;

   function bad returns long_float is
      x : long_float = 2.0;
   begin
      return narrow (x);
   end bad;

end rule5_conversion_narrowing;
""",
    },
    {
        "name": "rule5_annotation_narrowing",
        "expected_reason": "fp_overflow_at_narrowing",
        "source": """package rule5_annotation_narrowing is

   type narrow is digits 6 range -1.0 to 1.0;

   function bad returns long_float is
      x : long_float = 2.0;
   begin
      return (x as narrow);
   end bad;

end rule5_annotation_narrowing;
""",
    },
    {
        "name": "result_partial_guard_join",
        "expected_reason": "discriminant_check_not_established",
        "source": """package result_partial_guard_join is

   type error_code is range 0 to 255;

   type parse_result (ok : boolean = false) is record
      case ok is
         when true  then value : integer;
         when false then error : error_code;
      end case;
   end record;

   function try_parse (input : integer) returns parse_result is
   begin
      if input >= 0 then
         return (ok = true, value = input);
      else
         return (ok = false, error = 1);
      end if;
   end try_parse;

   function unsafe (input : integer; guard : boolean) returns integer is
      r : parse_result = try_parse (input);
   begin
      if guard then
         if r.ok then
            null;
         end if;
      end if;
      return r.value;
   end unsafe;

end result_partial_guard_join;
""",
    },
]

EXPECTED_GOLDEN_MAP_ENTRIES = {
    ("tests/negative/neg_rule5_nan.safe", "tests/diagnostics_golden/diag_rule5_nan.txt"),
    ("tests/negative/neg_result_unguarded.safe", "tests/diagnostics_golden/diag_result_unguarded.txt"),
    ("tests/negative/neg_result_mutated.safe", "tests/diagnostics_golden/diag_result_mutated.txt"),
}

EMIT_SAMPLES = {
    "rule5_temperature": REPO_ROOT / "tests" / "positive" / "rule5_temperature.safe",
    "result_guarded_access": REPO_ROOT / "tests" / "positive" / "result_guarded_access.safe",
}

PARITY_CASES = [
    {
        "name": "fp_division_by_zero",
        "source": REPO_ROOT / "tests" / "negative" / "neg_rule5_div_zero.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr07_fp_division_by_zero_parity.json",
    },
    {
        "name": "nan_at_narrowing",
        "source": REPO_ROOT / "tests" / "negative" / "neg_rule5_nan.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr07_nan_at_narrowing_parity.json",
    },
    {
        "name": "discriminant_check_not_established",
        "source": REPO_ROOT / "tests" / "negative" / "neg_result_unguarded.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr07_result_unguarded_parity.json",
    },
    {
        "name": "discriminant_invalidation_after_mutation",
        "source": REPO_ROOT / "tests" / "negative" / "neg_result_mutated.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr07_result_mutated_parity.json",
    },
]


def repo_arg(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def normalize_diag_path(path: str) -> str:
    candidate = Path(path)
    while candidate.parts and candidate.parts[0] == "..":
        candidate = Path(*candidate.parts[1:])
    if candidate.is_absolute():
        return display_path(candidate, repo_root=REPO_ROOT)
    normalized = str(candidate).replace("\\", "/")
    if normalized.startswith("./"):
        return normalized[2:]
    return normalized


def sorted_lines(values: list[str]) -> list[str]:
    return sorted(values)


def diag_signature(diag: dict[str, Any]) -> dict[str, Any]:
    return {
        "reason": diag["reason"],
        "message": diag["message"],
        "path": normalize_diag_path(diag["path"]),
        "span": diag["span"],
        "highlight_span": diag.get("highlight_span"),
        "notes": sorted_lines(diag.get("notes", [])),
        "suggestions": sorted_lines(diag.get("suggestions", [])),
    }


def canonical_parity_signature(*, case_name: str, diag: dict[str, Any]) -> dict[str, Any]:
    signature = diag_signature(diag)
    canonical = {
        "reason": signature["reason"],
        "message": signature["message"],
        "path": signature["path"],
        "span": signature["span"],
        "highlight_span": signature["highlight_span"],
    }

    if case_name == "fp_division_by_zero" and canonical["reason"] == "division_by_zero":
        canonical["reason"] = "fp_division_by_zero"
        canonical["message"] = "floating divisor is not provably nonzero"
    elif case_name == "nan_at_narrowing" and canonical["reason"] == "division_by_zero":
        canonical["reason"] = "nan_at_narrowing"
        canonical["message"] = "floating expression may be NaN at narrowing"
    if case_name == "nan_at_narrowing":
        canonical["span"] = None
        canonical["highlight_span"] = None
    elif case_name in {
        "discriminant_check_not_established",
        "discriminant_invalidation_after_mutation",
    }:
        canonical["message"] = (
            canonical["message"]
            .replace("'Value'", "'value'")
            .replace("'OK'", "'ok'")
        )

    return canonical


def first_diag(payload: dict[str, Any], label: str) -> dict[str, Any]:
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{label}: expected at least one diagnostic")
    return diagnostics[0]


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        "ast": root / "out" / f"{stem}.ast.json",
        "typed": root / "out" / f"{stem}.typed.json",
        "mir": root / "out" / f"{stem}.mir.json",
        "safei": root / "iface" / f"{stem}.safei.json",
    }


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def walk_real_texts(value: Any, texts: list[str]) -> None:
    if isinstance(value, dict):
        if value.get("tag") == "real":
            texts.append(value["text"])
        for child in value.values():
            walk_real_texts(child, texts)
    elif isinstance(value, list):
        for child in value:
            walk_real_texts(child, texts)


def find_type(types: list[dict[str, Any]], name: str) -> dict[str, Any]:
    for entry in types:
        if entry.get("name") == name:
            return entry
    raise RuntimeError(f"missing type metadata for {name}")


def assert_frozen_corpus() -> None:
    expected_result_cases = {
        ("tests/negative/neg_result_unguarded.safe", "tests/diagnostics_golden/diag_result_unguarded.txt"),
        ("tests/negative/neg_result_mutated.safe", "tests/diagnostics_golden/diag_result_mutated.txt"),
    }
    require(
        expected_result_cases.issubset(set(RESULT_GOLDEN_CASES)),
        "result/discriminant goldens are not wired into the canonical golden map",
    )
    require(
        ("tests/negative/neg_rule5_nan.safe", "tests/diagnostics_golden/diag_rule5_nan.txt") in set(D27_GOLDEN_CASES),
        "Rule 5 diagnostic golden is not wired into the canonical golden map",
    )
    require(
        EXPECTED_GOLDEN_MAP_ENTRIES.issubset(set(D27_GOLDEN_CASES) | set(RESULT_GOLDEN_CASES)),
        "PR07 canonical goldens are missing from gate expectations",
    )


def run_source_corpus(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    positives = RULE5_POSITIVES + RESULT_POSITIVES
    negatives = RULE5_NEGATIVES + RESULT_NEGATIVES

    positive_results: list[dict[str, Any]] = []
    for sample in positives:
        result = run([str(safec), "check", "--diag-json", repo_arg(sample)], cwd=REPO_ROOT, env=env, temp_root=temp_root)
        payload = read_diag_json(result["stdout"], repo_arg(sample))
        require(payload["diagnostics"] == [], f"{sample.name}: expected ACCEPT")
        positive_results.append({"sample": repo_arg(sample), "check": result})

    negative_results: list[dict[str, Any]] = []
    for sample in negatives:
        expected_reason = read_expected_reason(sample)
        result = run(
            [str(safec), "check", "--diag-json", repo_arg(sample)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        payload = read_diag_json(result["stdout"], repo_arg(sample))
        diag = first_diag(payload, sample.name)
        require(diag["reason"] == expected_reason, f"{sample.name}: expected {expected_reason}, saw {diag['reason']}")
        negative_results.append(
            {
                "sample": repo_arg(sample),
                "expected_reason": expected_reason,
                "check": result,
                "diagnostic": diag_signature(diag),
            }
        )

    return {"positives": positive_results, "negatives": negative_results}


def run_goldens(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for source_path, golden_path in GOLDEN_CASES:
        result = run(
            [str(safec), "check", repo_arg(source_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        expected = normalize_text(extract_expected_block(golden_path), temp_root=temp_root)
        require(result["stderr"] == expected, f"golden mismatch for {source_path.name}")
        results.append(
            {
                "source": repo_arg(source_path),
                "golden": repo_arg(golden_path),
                "check": result,
            }
        )
    return results


def run_inline_negative_cases(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in INLINE_NEGATIVE_CASES:
        source_path = temp_root / f"{case['name']}.safe"
        source_path.write_text(
            rewrite_pr117_reference_surface_source(
                rewrite_pr1162_legacy_source(rewrite_pr116_whitespace_source(case["source"])),
                mode="combined",
            ),
            encoding="utf-8",
        )
        result = run(
            [str(safec), "check", "--diag-json", str(source_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        payload = read_diag_json(result["stdout"], str(source_path))
        diag = first_diag(payload, case["name"])
        require(
            diag["reason"] == case["expected_reason"],
            f"{case['name']}: expected {case['expected_reason']}, saw {diag['reason']}",
        )
        results.append(
            {
                "name": case["name"],
                "expected_reason": case["expected_reason"],
                "diagnostic": diag_signature(diag),
                "check": result,
            }
        )
    return results


def run_parity_cases(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in PARITY_CASES:
        source_rel = repo_arg(case["source"])
        fixture_rel = repo_arg(case["fixture"])
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

        check_sig = canonical_parity_signature(case_name=case["name"], diag=check_diag)
        analyze_sig = canonical_parity_signature(case_name=case["name"], diag=analyze_diag)
        require(check_sig == analyze_sig, f"{case['name']}: check/analyze-mir parity drifted")

        results.append(
            {
                "name": case["name"],
                "source": source_rel,
                "fixture": fixture_rel,
                "check": check_result,
                "analyze_mir": analyze_result,
                "first_diagnostic": check_sig,
            }
        )
    return results


def validate_emitted_output(
    *,
    safec: Path,
    python: str,
    sample: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    root = temp_root / sample.stem.lower()
    (root / "out").mkdir(parents=True, exist_ok=True)
    (root / "iface").mkdir(parents=True, exist_ok=True)

    emit = run(
        [
            str(safec),
            "emit",
            repo_arg(sample),
            "--out-dir",
            str(root / "out"),
            "--interface-dir",
            str(root / "iface"),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    paths = emitted_paths(root, sample)

    ast_validate = run([python, str(AST_VALIDATOR), str(paths["ast"])], cwd=REPO_ROOT, env=env, temp_root=temp_root)
    output_validate = run(
        [
            python,
            str(OUTPUT_VALIDATOR),
            "--ast",
            str(paths["ast"]),
            "--typed",
            str(paths["typed"]),
            "--mir",
            str(paths["mir"]),
            "--safei",
            str(paths["safei"]),
            "--source-path",
            repo_arg(sample),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    mir_validate = run(
        [str(safec), "validate-mir", str(paths["mir"])],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze = run(
        [str(safec), "analyze-mir", "--diag-json", str(paths["mir"])],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_payload = read_diag_json(analyze["stdout"], str(paths["mir"]))
    require(analyze_payload["diagnostics"] == [], f"{sample.name}: expected emitted MIR to be diagnostic-free")

    ast_payload = load_json(paths["ast"])
    typed_payload = load_json(paths["typed"])
    mir_payload = load_json(paths["mir"])

    ast_nodes: list[str] = []
    def walk_nodes(value: Any) -> None:
        if isinstance(value, dict):
            node_type = value.get("node_type")
            if isinstance(node_type, str):
                ast_nodes.append(node_type)
            for child in value.values():
                walk_nodes(child)
        elif isinstance(value, list):
            for child in value:
                walk_nodes(child)
    walk_nodes(ast_payload)

    checks: dict[str, Any] = {}
    if sample.name == "rule5_temperature.safe":
        require("FloatingPointDefinition" in ast_nodes, "rule5_temperature: missing FloatingPointDefinition AST node")
        typed_types = typed_payload["types"]
        mir_types = mir_payload["types"]
        celsius_typed = find_type(typed_types, "celsius")
        fahrenheit_typed = find_type(typed_types, "fahrenheit")
        celsius_mir = find_type(mir_types, "celsius")
        fahrenheit_mir = find_type(mir_types, "fahrenheit")
        for entry in (celsius_typed, fahrenheit_typed, celsius_mir, fahrenheit_mir):
            require(entry.get("kind") == "float", "rule5_temperature: expected float metadata")
            require("digits_text" in entry, "rule5_temperature: missing digits_text")
            require("float_low_text" in entry and "float_high_text" in entry, "rule5_temperature: missing float bounds text")
        real_texts: list[str] = []
        walk_real_texts(mir_payload, real_texts)
        expected_texts = {"9.0", "5.0", "32.0"}
        require(expected_texts.issubset(set(real_texts)), "rule5_temperature: missing preserved real literal texts")
        checks = {
            "ast_nodes_present": ["FloatingPointDefinition"],
            "real_literal_texts": sorted(expected_texts),
            "float_types": {
                "typed": [celsius_typed, fahrenheit_typed],
                "mir": [celsius_mir, fahrenheit_mir],
            },
        }
    elif sample.name == "result_guarded_access.safe":
        require("KnownDiscriminantPart" in ast_nodes, "result_guarded_access: missing KnownDiscriminantPart AST node")
        require("VariantPart" in ast_nodes, "result_guarded_access: missing VariantPart AST node")
        parse_result_typed = find_type(typed_payload["types"], "parse_result")
        parse_result_mir = find_type(mir_payload["types"], "parse_result")
        for entry in (parse_result_typed, parse_result_mir):
            require(entry.get("discriminant_name") == "ok", "result_guarded_access: wrong discriminant_name")
            require(entry.get("discriminant_type") == "boolean", "result_guarded_access: wrong discriminant_type")
            require(entry.get("discriminant_default") is False, "result_guarded_access: wrong discriminant_default")
            require(isinstance(entry.get("variant_fields"), list) and len(entry["variant_fields"]) == 2, "result_guarded_access: missing variant_fields")
        checks = {
            "ast_nodes_present": ["KnownDiscriminantPart", "VariantPart"],
            "discriminant_metadata": {
                "typed": parse_result_typed,
                "mir": parse_result_mir,
            },
        }
    else:
        raise RuntimeError(f"unexpected emit sample: {sample}")

    return {
        "sample": repo_arg(sample),
        "emit": emit,
        "ast_validate": ast_validate,
        "output_validate": output_validate,
        "mir_validate": mir_validate,
        "analyze_mir": analyze,
        "checks": checks,
    }


def build_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    assert_frozen_corpus()
    with tempfile.TemporaryDirectory(prefix="pr07-rule5-result-") as temp_root_str:
        temp_root = Path(temp_root_str)
        return {
            "task": "PR07",
            "status": "ok",
            "frozen_corpus": {
                "rule5_positives": [repo_arg(path) for path in RULE5_POSITIVES],
                "rule5_negatives": [repo_arg(path) for path in RULE5_NEGATIVES],
                "result_cases": [repo_arg(path) for path in (RESULT_POSITIVES + RESULT_NEGATIVES)],
            },
            "source_corpus": run_source_corpus(safec, env, temp_root),
            "goldens": run_goldens(safec, env, temp_root),
            "inline_regressions": run_inline_negative_cases(safec, env, temp_root),
            "parity": run_parity_cases(safec, env, temp_root),
            "emitted_outputs": [
                validate_emitted_output(safec=safec, python=python, sample=sample, env=env, temp_root=temp_root)
                for sample in EMIT_SAMPLES.values()
            ],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    find_command("alr", Path.home() / "bin" / "alr")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    env = ensure_sdkroot(os.environ.copy())

    report = finalize_deterministic_report(
        lambda: build_report(safec=safec, python=python, env=env),
        label="PR07 rule5/result safety",
    )
    write_report(args.report, report)

    print(f"pr07 rule5/result safety: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
