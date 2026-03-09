#!/usr/bin/env python3
"""Run the PR06.9.1 semantic correctness hardening gate."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    find_command,
    normalize_text,
    read_diag_json,
    require,
    run,
    tool_versions,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr0691-semantic-correctness-report.json"

POSITIVE_GROUPS = {
    "range_call_return": [
        REPO_ROOT / "tests" / "positive" / "rule1_parameter.safe",
        REPO_ROOT / "tests" / "positive" / "rule1_return.safe",
    ],
    "interprocedural_ownership": [
        REPO_ROOT / "tests" / "positive" / "ownership_return.safe",
        REPO_ROOT / "tests" / "positive" / "ownership_inout.safe",
        REPO_ROOT / "tests" / "positive" / "ownership_observe_access.safe",
    ],
    "analyzer_representative": [
        REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
        REPO_ROOT / "tests" / "positive" / "rule3_divide.safe",
        REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
    ],
}

NEGATIVE_GROUPS = {
    "range_call_return": [
        REPO_ROOT / "tests" / "negative" / "neg_rule1_param_fail.safe",
        REPO_ROOT / "tests" / "negative" / "neg_rule1_return_fail.safe",
        REPO_ROOT / "tests" / "negative" / "neg_rule1_narrow_fail.safe",
    ],
    "interprocedural_ownership": [
        REPO_ROOT / "tests" / "negative" / "neg_own_return_move.safe",
        REPO_ROOT / "tests" / "negative" / "neg_own_inout_move.safe",
        REPO_ROOT / "tests" / "negative" / "neg_own_observe_requires_access.safe",
        REPO_ROOT / "tests" / "negative" / "neg_own_lifetime.safe",
    ],
    "analyzer_representative": [
        REPO_ROOT / "tests" / "negative" / "neg_rule2_dynamic.safe",
        REPO_ROOT / "tests" / "negative" / "neg_rule3_expression.safe",
        REPO_ROOT / "tests" / "negative" / "neg_rule4_moved.safe",
    ],
}

ANALYZER_FIXTURE_CASES = [
    {
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr05_division_by_zero.json",
        "expected_reason": "division_by_zero",
        "paired_source": REPO_ROOT / "tests" / "negative" / "neg_rule3_expression.safe",
    },
    {
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr06_double_move.json",
        "expected_reason": "double_move",
        "paired_source": REPO_ROOT / "tests" / "negative" / "neg_own_inout_move.safe",
    },
]

PACKAGE_GLOBAL_RECORD_SOURCE = """package Package_Global_Record is
   type Config is record
      Rate : Natural;
      Limit : Natural;
   end record;

   Current : Config = (Rate = 1, Limit = 2);

   function Read return Natural is
   begin
      return Current.Rate;
   end Read;
end Package_Global_Record;
"""

PACKAGE_GLOBAL_ARRAY_SOURCE = """package Package_Global_Array is
   type Index is range 1 .. 4;
   type Element is range 0 .. 20;
   type Table is array (Index) of Element;
   Data : Table;

   function Read return Element is
   begin
      Data (Index.First) = 5;
      return Data (Index.First);
   end Read;
end Package_Global_Array;
"""

PACKAGE_GLOBAL_OBSERVE_SOURCE = """package Package_Global_Observe is
   type Config is record
      Rate : Natural;
   end record;

   type Config_Ptr is access Config;

   Owner : Config_Ptr = new ((Rate = 100) as Config);

   function Read_Config (Ref : access constant Config) return Integer is
   begin
      return Ref.all.Rate;
   end Read_Config;

   function Read return Integer is
   begin
      return Read_Config (Owner.Access);
   end Read;
end Package_Global_Observe;
"""
def read_expected_reason(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^-- Expected:\s+REJECT\s+([a-z_]+)\s*$", text, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"missing expected reason header in {path}")
    return match.group(1)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        f"out/{stem}.ast.json": root / "out" / f"{stem}.ast.json",
        f"out/{stem}.typed.json": root / "out" / f"{stem}.typed.json",
        f"out/{stem}.mir.json": root / "out" / f"{stem}.mir.json",
        f"iface/{stem}.safei.json": root / "iface" / f"{stem}.safei.json",
    }


def graph_by_name(mir_payload: dict[str, Any], name: str) -> dict[str, Any]:
    for graph in mir_payload["graphs"]:
        if graph["name"] == name:
            return graph
    raise RuntimeError(f"missing graph {name!r}")


def local_by_name(graph: dict[str, Any], name: str) -> dict[str, Any]:
    for item in graph["locals"]:
        if item["name"] == name:
            return item
    raise RuntimeError(f"missing local {name!r} in graph {graph['name']!r}")


def first_return_value(graph: dict[str, Any]) -> dict[str, Any]:
    for block in graph["blocks"]:
        if block["terminator"]["kind"] == "return" and block["terminator"]["value"] is not None:
            return block["terminator"]["value"]
    raise RuntimeError(f"missing return value in graph {graph['name']!r}")


def run_positive_case(safec: Path, source: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    check_run = run(
        [str(safec), "check", "--diag-json", str(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    check_payload = read_diag_json(check_run["stdout"], str(source))
    require(check_payload["diagnostics"] == [], f"{source}: expected no check diagnostics")

    emit_root = temp_root / f"{source.stem}-emit"
    emit_run = run(
        [
            str(safec),
            "emit",
            str(source),
            "--out-dir",
            str(emit_root / "out"),
            "--interface-dir",
            str(emit_root / "iface"),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )

    outputs = emitted_paths(emit_root, source)
    for path in outputs.values():
        require(path.exists(), f"{source}: missing emitted artifact {path}")

    typed_output = outputs[f"out/{source.stem.lower()}.typed.json"]
    mir_output = outputs[f"out/{source.stem.lower()}.mir.json"]
    safei_output = outputs[f"iface/{source.stem.lower()}.safei.json"]

    mir_validate = run(
        [str(safec), "validate-mir", str(mir_output)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_run = run(
        [str(safec), "analyze-mir", "--diag-json", str(mir_output)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_payload = read_diag_json(analyze_run["stdout"], str(mir_output))
    require(analyze_payload["diagnostics"] == [], f"{source}: emitted MIR must stay diagnostic-free")

    typed_payload = load_json(typed_output)
    mir_payload = load_json(mir_output)
    safei_payload = load_json(safei_output)
    require(typed_payload.get("format") == "typed-v2", f"{typed_output}: expected typed-v2")
    require(mir_payload.get("format") == "mir-v2", f"{mir_output}: expected mir-v2")
    require(safei_payload.get("format") == "safei-v0", f"{safei_output}: expected safei-v0")
    require(mir_payload["source_path"] == str(source), f"{mir_output}: source_path must preserve CLI path")

    return {
        "source": str(source.relative_to(REPO_ROOT)),
        "check": {
            **check_run,
            "diagnostics": check_payload,
        },
        "emit": emit_run,
        "validate_mir": mir_validate,
        "analyze_mir": {
            **analyze_run,
            "diagnostics": analyze_payload,
        },
        "formats": {
            "typed": typed_payload["format"],
            "mir": mir_payload["format"],
            "safei": safei_payload["format"],
        },
    }


def run_negative_source_case(safec: Path, source: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    expected_reason = read_expected_reason(source)
    check_run = run(
        [str(safec), "check", "--diag-json", str(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    check_payload = read_diag_json(check_run["stdout"], str(source))
    require(check_payload["diagnostics"], f"{source}: expected at least one diagnostic")
    actual_reason = check_payload["diagnostics"][0]["reason"]
    require(
        actual_reason == expected_reason,
        f"{source}: expected primary reason {expected_reason}, got {actual_reason}",
    )
    return {
        "source": str(source.relative_to(REPO_ROOT)),
        "expected_reason": expected_reason,
        "actual_reason": actual_reason,
        "check": {
            **check_run,
            "diagnostics": check_payload,
        },
    }


def run_analyzer_fixture_case(
    safec: Path,
    fixture: Path,
    expected_reason: str,
    paired_source: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    analyze_run = run(
        [str(safec), "analyze-mir", "--diag-json", str(fixture)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    analyze_payload = read_diag_json(analyze_run["stdout"], str(fixture))
    require(analyze_payload["diagnostics"], f"{fixture}: expected at least one diagnostic")
    actual_reason = analyze_payload["diagnostics"][0]["reason"]
    require(
        actual_reason == expected_reason,
        f"{fixture}: expected primary reason {expected_reason}, got {actual_reason}",
    )

    source_case = run_negative_source_case(safec, paired_source, env, temp_root)
    require(
        source_case["actual_reason"] == actual_reason,
        f"{fixture}: analyzer/source reason mismatch {source_case['actual_reason']} vs {actual_reason}",
    )

    return {
        "fixture": str(fixture.relative_to(REPO_ROOT)),
        "expected_reason": expected_reason,
        "actual_reason": actual_reason,
        "analyze_mir": {
            **analyze_run,
            "diagnostics": analyze_payload,
        },
        "paired_source": source_case,
    }


def emit_inline_source_case(
    *,
    name: str,
    text: str,
    safec: Path,
    env: dict[str, str],
    temp_root: Path,
) -> tuple[
    dict[str, Any],
    dict[str, Any],
    dict[str, Any],
    dict[str, Any],
    dict[str, Any],
    dict[str, Any],
    dict[str, Any],
]:
    source = temp_root / f"{name}.safe"
    source.write_text(text, encoding="utf-8")

    check_run = run(
        [str(safec), "check", "--diag-json", str(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    check_payload = read_diag_json(check_run["stdout"], str(source))
    require(check_payload["diagnostics"] == [], f"{source}: expected no check diagnostics")

    emit_root = temp_root / f"{name}-emit"
    emit_run = run(
        [
            str(safec),
            "emit",
            str(source),
            "--out-dir",
            str(emit_root / "out"),
            "--interface-dir",
            str(emit_root / "iface"),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    outputs = emitted_paths(emit_root, source)
    mir_output = outputs[f"out/{name}.mir.json"]
    require(mir_output.exists(), f"{source}: missing emitted MIR")

    mir_validate = run(
        [str(safec), "validate-mir", str(mir_output)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_run = run(
        [str(safec), "analyze-mir", "--diag-json", str(mir_output)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_payload = read_diag_json(analyze_run["stdout"], str(mir_output))
    require(analyze_payload["diagnostics"] == [], f"{source}: expected zero analyze-mir diagnostics")
    mir_payload = load_json(mir_output)
    require(mir_payload["source_path"] == str(source), f"{mir_output}: source_path must preserve CLI path")

    return check_run, check_payload, emit_run, mir_validate, analyze_run, analyze_payload, mir_payload


def run_package_global_cases(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    cases = [
        ("package_global_observe", PACKAGE_GLOBAL_OBSERVE_SOURCE),
        ("package_global_record", PACKAGE_GLOBAL_RECORD_SOURCE),
        ("package_global_array", PACKAGE_GLOBAL_ARRAY_SOURCE),
    ]
    results: dict[str, Any] = {}

    for name, text in cases:
        check_run, check_payload, emit_run, mir_validate, analyze_run, analyze_payload, mir_payload = (
            emit_inline_source_case(name=name, text=text, safec=safec, env=env, temp_root=temp_root)
        )
        result: dict[str, Any] = {
            "source": f"$TMPDIR/{name}.safe",
            "check": {
                **check_run,
                "diagnostics": check_payload,
            },
            "emit": emit_run,
            "validate_mir": mir_validate,
            "analyze_mir": {
                **analyze_run,
                "diagnostics": analyze_payload,
            },
        }

        if name == "package_global_observe":
            read_graph = graph_by_name(mir_payload, "Read")
            helper_graph = graph_by_name(mir_payload, "Read_Config")
            owner_local = local_by_name(read_graph, "Owner")
            ref_local = local_by_name(helper_graph, "Ref")
            return_value = first_return_value(read_graph)
            require(owner_local["kind"] == "global", "package_global_observe: Owner must lower as global")
            require(
                owner_local["type"]["name"] == "Config_Ptr",
                f"package_global_observe: expected Owner type Config_Ptr, saw {owner_local['type']['name']!r}",
            )
            require(
                ref_local["ownership_role"] == "Observe",
                f"package_global_observe: expected Ref ownership_role Observe, saw {ref_local['ownership_role']!r}",
            )
            require(return_value["tag"] == "call", "package_global_observe: expected return call expression")
            require(
                return_value["args"][0]["tag"] == "select" and return_value["args"][0]["selector"] == "Access",
                "package_global_observe: expected Owner.Access call argument",
            )
            require(
                return_value["args"][0]["prefix"]["type"] == "Config_Ptr",
                f"package_global_observe: expected Owner.Access prefix type Config_Ptr, saw {return_value['args'][0]['prefix'].get('type')!r}",
            )
            result["semantic_proof"] = {
                "owner_local": owner_local,
                "ref_local": ref_local,
                "return_value": return_value,
            }

        if name == "package_global_record":
            graph = graph_by_name(mir_payload, "Read")
            current_local = local_by_name(graph, "Current")
            return_value = first_return_value(graph)
            init_ops = [
                op
                for op in graph["blocks"][0]["ops"]
                if op["kind"] == "assign" and op["target"]["name"] == "Current"
            ]
            require(current_local["kind"] == "global", "package_global_record: Current must lower as global")
            require(
                current_local["type"]["name"] == "Config",
                f"package_global_record: expected Current type Config, saw {current_local['type']['name']!r}",
            )
            require(
                init_ops and init_ops[0]["declaration_init"],
                "package_global_record: Current init must stay declaration_init",
            )
            require(return_value["tag"] == "select", "package_global_record: expected select return")
            require(
                return_value["prefix"]["type"] == "Config",
                f"package_global_record: expected select prefix type Config, saw {return_value['prefix'].get('type')!r}",
            )
            result["semantic_proof"] = {
                "current_local": current_local,
                "return_value": return_value,
            }

        if name == "package_global_array":
            graph = graph_by_name(mir_payload, "Read")
            data_local = local_by_name(graph, "Data")
            return_value = first_return_value(graph)
            require(data_local["kind"] == "global", "package_global_array: Data must lower as global")
            require(
                data_local["type"]["name"] == "Table",
                f"package_global_array: expected Data type Table, saw {data_local['type']['name']!r}",
            )
            require(
                return_value["tag"] == "resolved_index",
                f"package_global_array: expected resolved_index return, saw {return_value['tag']!r}",
            )
            require(
                return_value["prefix"]["type"] == "Table",
                f"package_global_array: expected indexed prefix type Table, saw {return_value['prefix'].get('type')!r}",
            )
            result["semantic_proof"] = {
                "data_local": data_local,
                "return_value": return_value,
            }

        results[name] = result

    return results


def run_positive_groups(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, list[dict[str, Any]]]:
    results: dict[str, list[dict[str, Any]]] = {}
    for group, cases in POSITIVE_GROUPS.items():
        results[group] = [run_positive_case(safec, source, env, temp_root) for source in cases]
    return results


def run_negative_groups(safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, list[dict[str, Any]]]:
    results: dict[str, list[dict[str, Any]]] = {}
    for group, cases in NEGATIVE_GROUPS.items():
        results[group] = [run_negative_source_case(safec, source, env, temp_root) for source in cases]
    return results


def run_analyzer_fixture_groups(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    return [
        run_analyzer_fixture_case(
            safec,
            case["fixture"],
            case["expected_reason"],
            case["paired_source"],
            env,
            temp_root,
        )
        for case in ANALYZER_FIXTURE_CASES
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    env = ensure_sdkroot(os.environ.copy())

    safec = COMPILER_ROOT / "bin" / "safec"
    require(safec.exists(), f"expected built compiler at {safec}")

    with tempfile.TemporaryDirectory(prefix="safec-pr0691-") as temp_root_str:
        temp_root = Path(temp_root_str)
        report = {
            "tool_versions": tool_versions(python=python, alr=alr),
            "scope": {
                "positive_groups": {
                    group: [str(path.relative_to(REPO_ROOT)) for path in paths]
                    for group, paths in POSITIVE_GROUPS.items()
                },
                "negative_groups": {
                    group: [str(path.relative_to(REPO_ROOT)) for path in paths]
                    for group, paths in NEGATIVE_GROUPS.items()
                },
                "analyzer_fixture_pairs": [
                    {
                        "fixture": str(case["fixture"].relative_to(REPO_ROOT)),
                        "paired_source": str(case["paired_source"].relative_to(REPO_ROOT)),
                        "expected_reason": case["expected_reason"],
                    }
                    for case in ANALYZER_FIXTURE_CASES
                ],
                "package_global_cases": [
                    "$TMPDIR/package_global_observe.safe",
                    "$TMPDIR/package_global_record.safe",
                    "$TMPDIR/package_global_array.safe",
                ],
                "negative_emit_note": "Negative source seam cases are check-only in this gate because safec emit must refuse to write artifacts when diagnostics exist.",
            },
            "source_positive_parity": run_positive_groups(safec, env, temp_root),
            "source_negative_reasons": run_negative_groups(safec, env, temp_root),
            "analyzer_negative_parity": run_analyzer_fixture_groups(safec, env, temp_root),
            "package_global_positive_parity": run_package_global_cases(safec, env, temp_root),
        }

    write_report(args.report, report)
    print(f"pr0691 semantic correctness: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr0691 semantic correctness: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
