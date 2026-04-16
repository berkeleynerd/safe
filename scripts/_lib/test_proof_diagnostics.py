"""Proof diagnostic rewriting checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path
from types import SimpleNamespace

from _lib.proof_diagnostic_catalog import DEFAULT_CATALOG
from _lib.proof_diagnostics import (
    GnatproveDiag,
    LineMapEntry,
    classify_message,
    load_all_line_maps,
    lookup_line_map_entry,
    parse_gnatprove_diagnostic,
    rewrite_diagnostic,
    rewrite_gnatprove_output,
    write_line_map_sidecar,
)
from _lib.test_harness import RunCounts, record_result
from safe_cli import (
    clear_diagnostics_sidecar,
    diagnostics_sidecar_path,
    write_diagnostics_sidecar,
)


def run_parse_gnatprove_diagnostic_case() -> tuple[bool, str]:
    parsed = parse_gnatprove_diagnostic(
        "demo.adb:5:11: high: overflow check might fail, cannot prove upper bound"
    )
    if parsed is None:
        return False, "expected GNATprove diagnostic to parse"
    if parsed.ada_file != "demo.adb" or parsed.ada_line != 5 or parsed.ada_col != 11:
        return False, f"unexpected location {parsed!r}"
    if parsed.severity != "high" or "overflow check" not in parsed.message:
        return False, f"unexpected severity/message {parsed!r}"
    parsed = parse_gnatprove_diagnostic(
        "/tmp/out/demo.ads:12:3: warning: condition is always False"
    )
    if parsed is None or parsed.ada_file != "/tmp/out/demo.ads" or parsed.severity != "warning":
        return False, f"failed to parse warning with absolute path {parsed!r}"
    if parse_gnatprove_diagnostic("gnatprove: unproved check messages considered as errors") is not None:
        return False, "expected non-diagnostic GNATprove line to be ignored"
    return True, ""


def run_catalog_coverage_case() -> tuple[bool, str]:
    samples = [
        ("range check might fail", "value may exceed type range at conversion"),
        ("overflow check might fail", "arithmetic may overflow"),
        ("assertion might fail", "generated proof assertion could not be verified"),
        ("loop should mention Total in a loop invariant", "prover cannot establish loop body safety"),
        ("call to a volatile function in interfering context", "shared reads in compound conditions"),
        ("cannot write X during elaboration", "imported state cannot be modified at unit scope"),
        ("object Foo may be uninitialized", "variable may be uninitialized on this path"),
        ("precondition might fail", "precondition of called function may not hold"),
    ]
    for raw, expected_prefix in samples:
        message, fix = classify_message(raw, DEFAULT_CATALOG)
        if not message.startswith(expected_prefix):
            return False, f"{raw!r} classified as {message!r}"
        if not fix:
            return False, f"{raw!r} produced empty fix guidance"
    fallback, fix = classify_message("some new GNATprove wording")
    if fallback != "GNATprove could not verify generated proof obligation":
        return False, f"unexpected fallback {fallback!r}"
    if "--verbose" not in fix:
        return False, f"unexpected fallback guidance {fix!r}"
    return True, ""


def run_line_map_loading_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-line-map-test-") as temp_root_str:
        temp_root = Path(temp_root_str)
        (temp_root / "demo_line_map.json").write_text(
            json.dumps(
                {
                    "format": "safe-line-map-v0",
                    "unit": "demo",
                    "entries": [
                        {
                            "ada_file": "demo.adb",
                            "ada_line": 10,
                            "safe_file": "demo.safe",
                            "safe_line": 4,
                            "safe_col": 7,
                        },
                        {
                            "ada_file": "demo.adb",
                            "ada_line": 20,
                            "safe_file": "demo.safe",
                            "safe_line": 8,
                            "safe_col": 3,
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        (temp_root / "ignored_line_map.json").write_text("not json", encoding="utf-8")
        line_maps = load_all_line_maps(temp_root)
    entry = lookup_line_map_entry(line_maps, "/tmp/build/demo.adb", 12)
    if entry != LineMapEntry("demo.adb", 10, "demo.safe", 4, 7):
        return False, f"nearest preceding lookup returned {entry!r}"
    entry = lookup_line_map_entry(line_maps, "demo.adb", 20)
    if entry != LineMapEntry("demo.adb", 20, "demo.safe", 8, 3):
        return False, f"exact lookup returned {entry!r}"
    if lookup_line_map_entry(line_maps, "demo.adb", 5) is not None:
        return False, "expected lookup before first mapping to be unmapped"
    return True, ""


def run_line_map_sidecar_refresh_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-line-map-refresh-") as temp_root_str:
        temp_root = Path(temp_root_str)
        (temp_root / "demo.ads").write_text(
            "with Provider;\npackage demo is\n   -- safe:demo.safe:3:4\nend demo;\n",
            encoding="utf-8",
        )
        (temp_root / "demo.adb").write_text(
            "with Provider;\npackage body demo is\n   -- safe:demo.safe:6:7\nbegin\n   null;\nend demo;\n",
            encoding="utf-8",
        )
        write_line_map_sidecar(temp_root, "demo")
        line_maps = load_all_line_maps(temp_root)
    spec_entry = lookup_line_map_entry(line_maps, "demo.ads", 3)
    if spec_entry != LineMapEntry("demo.ads", 3, "demo.safe", 3, 4):
        return False, f"unexpected spec refreshed line-map entry {spec_entry!r}"
    body_entry = lookup_line_map_entry(line_maps, "demo.adb", 3)
    if body_entry != LineMapEntry("demo.adb", 3, "demo.safe", 6, 7):
        return False, f"unexpected body refreshed line-map entry {body_entry!r}"
    return True, ""


def run_rewrite_diagnostic_case() -> tuple[bool, str]:
    line_maps = {
        "demo.adb": [
            LineMapEntry(
                ada_file="demo.adb",
                ada_line=9,
                safe_file="tests/build/demo.safe",
                safe_line=3,
                safe_col=5,
            )
        ]
    }
    rewritten = rewrite_diagnostic(
        GnatproveDiag(
            ada_file="/tmp/out/demo.adb",
            ada_line=11,
            ada_col=14,
            severity="high",
            message="overflow check might fail",
        ),
        line_maps,
        stage="prove",
    )
    if rewritten.file != "tests/build/demo.safe" or rewritten.line != 3 or rewritten.column != 5:
        return False, f"unexpected Safe location {rewritten!r}"
    if rewritten.ada_file != "demo.adb" or rewritten.ada_line != 11 or rewritten.stage != "prove":
        return False, f"unexpected Ada/stage metadata {rewritten!r}"
    if rewritten.message != "arithmetic may overflow":
        return False, f"unexpected classified message {rewritten.message!r}"
    unmapped = rewrite_diagnostic(
        GnatproveDiag(
            ada_file="/tmp/out/other.adb",
            ada_line=2,
            ada_col=4,
            severity="medium",
            message="precondition might fail",
        ),
        line_maps,
        stage="flow",
    )
    if unmapped.file != "other.adb" or unmapped.ada_file != "other.adb":
        return False, f"expected unmapped diagnostic to use Ada basename {unmapped!r}"
    if unmapped.line != 2 or unmapped.column != 4:
        return False, f"expected unmapped diagnostic to retain Ada line/column {unmapped!r}"
    return True, ""


def run_rewrite_output_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-rewrite-output-") as temp_root_str:
        temp_root = Path(temp_root_str)
        (temp_root / "demo_line_map.json").write_text(
            json.dumps(
                {
                    "format": "safe-line-map-v0",
                    "unit": "demo",
                    "entries": [
                        {
                            "ada_file": "demo.adb",
                            "ada_line": 4,
                            "safe_file": "demo.safe",
                            "safe_line": 2,
                            "safe_col": 1,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        human, diagnostics = rewrite_gnatprove_output(
            "\n".join(
                [
                    "demo.adb:5:11: high: overflow check might fail",
                    "demo.adb:6:1: info: assertion proved",
                    "gnatprove: unproved check messages considered as errors",
                ]
            ),
            temp_root,
            stage="prove",
        )
    if "demo.safe:2:1: high: arithmetic may overflow" not in human:
        return False, f"missing rewritten diagnostic in {human!r}"
    if "assertion proved" in human:
        return False, f"info diagnostic should not be rendered {human!r}"
    if len(diagnostics) != 1:
        return False, f"expected one JSON diagnostic {diagnostics!r}"
    if diagnostics[0]["file"] != "demo.safe" or diagnostics[0]["stage"] != "prove":
        return False, f"unexpected JSON diagnostic {diagnostics!r}"
    return True, ""


def run_rewrite_output_fallback_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-rewrite-output-fallback-") as temp_root_str:
        human, diagnostics = rewrite_gnatprove_output(
            "\n".join(
                [
                    "/tmp/out/demo.adb:5:11: info: assertion proved",
                    "/tmp/out/demo.adb: malformed unrecognized proof output",
                ]
            ),
            Path(temp_root_str),
            stage="prove",
        )
    if "no Safe-mappable diagnostics found" not in human:
        return False, f"missing neutral fallback in {human!r}"
    if "/tmp/out/demo.adb" in human:
        return False, f"fallback leaked raw Ada path {human!r}"
    if diagnostics:
        return False, f"fallback should not emit JSON diagnostics {diagnostics!r}"
    return True, ""


def run_cli_diagnostics_sidecar_case() -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-diagnostics-sidecar-") as temp_root_str:
        source = Path(temp_root_str) / "demo.safe"
        source.write_text("package demo\n", encoding="utf-8")
        result = SimpleNamespace(
            source=source,
            diagnostics_json=[
                {
                    "file": "demo.safe",
                    "line": 1,
                    "column": 1,
                    "message": "arithmetic may overflow",
                }
            ],
        )
        write_diagnostics_sidecar(result)
        path = diagnostics_sidecar_path(source)
        if not path.exists():
            return False, "diagnostics sidecar was not written"
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, list) or payload[0]["message"] != "arithmetic may overflow":
            return False, f"unexpected diagnostics payload {payload!r}"
        write_diagnostics_sidecar(SimpleNamespace(source=source, diagnostics_json=[]))
        if path.exists():
            return False, "empty diagnostics did not clear sidecar"
        write_diagnostics_sidecar(result)
        clear_diagnostics_sidecar(source)
        if path.exists():
            return False, "explicit clear did not remove sidecar"
    return True, ""


def run_proof_diagnostic_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    cases = [
        ("proof-diagnostic-parse", run_parse_gnatprove_diagnostic_case),
        ("proof-diagnostic-catalog", run_catalog_coverage_case),
        ("proof-diagnostic-line-map", run_line_map_loading_case),
        ("proof-diagnostic-line-map-refresh", run_line_map_sidecar_refresh_case),
        ("proof-diagnostic-rewrite", run_rewrite_diagnostic_case),
        ("proof-diagnostic-output", run_rewrite_output_case),
        ("proof-diagnostic-output-fallback", run_rewrite_output_fallback_case),
        ("proof-diagnostic-cli-sidecar", run_cli_diagnostics_sidecar_case),
    ]
    for label, case in cases:
        passed += record_result(failures, label, case())
    return passed, 0, failures
