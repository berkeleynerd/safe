"""Shared helpers for CI-authoritative proof report partitioning."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .harness_common import require


SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
GNATPROVE_VALUE_SWITCHES = (
    "-P",
    "--project",
    "--mode",
    "--level",
    "--prover",
    "--steps",
    "--timeout",
    "--report",
    "--warnings",
    "--checks-as-errors",
)
PR101_BASELINE_GATE_IDS = (
    "pr08_frontend_baseline",
    "pr09_ada_emission_baseline",
    "pr10_emitted_baseline",
    "emitted_hardening_regressions",
)
PR101_CHILD_REPORT_IDS = (
    "pr101a_companion_proof_verification",
    "pr101b_template_proof_verification",
)
PR101_ANCHOR_GROUPS = ("companion_verify", "templates_verify")
PR101_ANCHOR_KEYS = (
    "assumptions_extracted_sha256",
    "prove_golden_sha256",
    "gnatprove_summary_sha256",
)


def _command_name(command: list[str]) -> str:
    if not command:
        return ""
    return Path(command[0]).name


def _normalize_profile_arg(arg: str) -> str:
    if arg.startswith("-gnatec="):
        return "-gnatec=<ada_dir>/gnat.adc"
    if arg.startswith("$TMPDIR/") and arg.endswith(".json"):
        return "$REPORT"
    candidate = Path(arg)
    if candidate.suffix == ".gpr":
        return candidate.name
    if candidate.suffix in {".adb", ".ads", ".py"}:
        return candidate.name
    return arg


def command_profile(command: list[str]) -> dict[str, Any]:
    require(command, "command profile requires a non-empty command")
    program = _command_name(command)
    if program.startswith("python"):
        script = command[1] if len(command) > 1 else ""
        return {
            "program": program,
            "script": script,
            "args": [_normalize_profile_arg(arg) for arg in command[2:]],
        }
    if len(command) >= 4 and command[1] == "exec" and command[2] == "--":
        tool = Path(command[3]).name
        tool_args = command[4:]
        profile: dict[str, Any] = {
            "program": program,
            "tool": tool,
        }
        if tool == "gnatprove":
            profile["project"] = _value_after(tool_args, "-P", "--project")
            profile["mode"] = _switch_value(tool_args, "--mode")
            profile["level"] = _switch_value(tool_args, "--level")
            profile["provers"] = _csv_switch(tool_args, "--prover")
            profile["steps"] = _switch_value(tool_args, "--steps")
            profile["timeout"] = _switch_value(tool_args, "--timeout")
            profile["report"] = _switch_value(tool_args, "--report")
            profile["warnings"] = _switch_value(tool_args, "--warnings")
            profile["checks_as_errors"] = _switch_value(tool_args, "--checks-as-errors")
            profile["explicit_gnatec"] = any(arg.startswith("-gnatec=") for arg in tool_args)
            extras = _gnatprove_extra_args(tool_args)
            if extras:
                profile["extra_args"] = extras
            return profile
        if tool == "gprbuild":
            profile["project"] = _value_after(tool_args, "-P", "--project")
            profile["compile_only"] = "-c" in tool_args
            profile["explicit_gnatec"] = any(arg.startswith("-gnatec=") for arg in tool_args)
            normalized = [_normalize_profile_arg(arg) for arg in tool_args]
            if normalized:
                profile["args"] = normalized
            return profile
        profile["args"] = [_normalize_profile_arg(arg) for arg in tool_args]
        return profile
    return {
        "program": program,
        "args": [_normalize_profile_arg(arg) for arg in command[1:]],
    }


def _value_after(argv: list[str], *switches: str) -> str | None:
    for index, arg in enumerate(argv):
        for switch in switches:
            if arg == switch and index + 1 < len(argv):
                return _normalize_profile_arg(argv[index + 1])
            if arg.startswith(switch + "="):
                return _normalize_profile_arg(arg.split("=", 1)[1])
    return None


def _switch_value(argv: list[str], prefix: str) -> str | None:
    return _value_after(argv, prefix)


def _csv_switch(argv: list[str], prefix: str) -> list[str]:
    value = _switch_value(argv, prefix)
    if not value:
        return []
    return value.split(",")


def _known_gnatprove_arg(arg: str) -> bool:
    return (
        arg in {*GNATPROVE_VALUE_SWITCHES, "-cargs"}
        or any(arg.startswith(switch + "=") for switch in GNATPROVE_VALUE_SWITCHES)
        or arg.startswith("-gnatec=")
    )


def _gnatprove_extra_args(argv: list[str]) -> list[str]:
    extras: list[str] = []
    skip_next = False
    for arg in argv:
        if skip_next:
            skip_next = False
            continue
        if arg in GNATPROVE_VALUE_SWITCHES:
            skip_next = True
            continue
        if _known_gnatprove_arg(arg):
            continue
        extras.append(_normalize_profile_arg(arg))
    return extras


def count_only_summary(summary: dict[str, Any]) -> dict[str, Any]:
    return {
        "rows": {
            label: {key: value["count"] for key, value in row.items()}
            for label, row in summary["rows"].items()
        },
        "total": {key: value["count"] for key, value in summary["total"].items()},
    }


def summary_detail_map(summary: dict[str, Any]) -> dict[str, Any]:
    rows = {
        label: {key: value["detail"] for key, value in row.items() if value["detail"]}
        for label, row in summary["rows"].items()
    }
    rows = {label: row for label, row in rows.items() if row}
    total = {key: value["detail"] for key, value in summary["total"].items() if value["detail"]}
    details: dict[str, Any] = {}
    if rows:
        details["rows"] = rows
    if total:
        details["total"] = total
    return details


def split_command_result(result: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    canonical = {
        "returncode": result["returncode"],
        "command_profile": command_profile(result["command"]),
    }
    machine = {
        "command": result["command"],
        "cwd": result["cwd"],
    }
    if result.get("stdout"):
        machine["stdout"] = result["stdout"]
    if result.get("stderr"):
        machine["stderr"] = result["stderr"]
    return canonical, machine


def split_gnatprove_result(result: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    canonical, machine = split_command_result(result)
    canonical["summary"] = count_only_summary(result["summary"])
    details = summary_detail_map(result["summary"])
    if details:
        machine["summary"] = details
    return canonical, machine


def split_proof_fixture(
    fixture_payload: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    semantic: dict[str, Any] = {"fixture": fixture_payload["fixture"]}
    if "family" in fixture_payload:
        semantic["family"] = fixture_payload["family"]

    canonical: dict[str, Any] = {"fixture": fixture_payload["fixture"]}
    machine: dict[str, Any] = {"fixture": fixture_payload["fixture"]}
    if "family" in fixture_payload:
        canonical["family"] = fixture_payload["family"]
        machine["family"] = fixture_payload["family"]

    if "compile" in fixture_payload:
        semantic["compile_returncode"] = fixture_payload["compile"]["returncode"]
        canonical["compile"], machine["compile"] = split_command_result(fixture_payload["compile"])
    if "flow" in fixture_payload:
        flow_total = fixture_payload["flow"]["summary"]["total"]
        semantic["flow_returncode"] = fixture_payload["flow"]["returncode"]
        semantic["flow_justified"] = flow_total["justified"]["count"]
        semantic["flow_unproved"] = flow_total["unproved"]["count"]
        semantic["flow_total_checks"] = flow_total["total"]["count"]
        canonical["flow"], machine["flow"] = split_gnatprove_result(fixture_payload["flow"])
    if "prove" in fixture_payload:
        prove_total = fixture_payload["prove"]["summary"]["total"]
        semantic["prove_returncode"] = fixture_payload["prove"]["returncode"]
        semantic["prove_justified"] = prove_total["justified"]["count"]
        semantic["prove_unproved"] = prove_total["unproved"]["count"]
        semantic["prove_total_checks"] = prove_total["total"]["count"]
        canonical["prove"], machine["prove"] = split_gnatprove_result(fixture_payload["prove"])

    for key, value in fixture_payload.items():
        if key in {"fixture", "family", "compile", "flow", "prove"}:
            continue
        canonical[key] = value

    return semantic, canonical, machine


def split_proof_fixtures(
    fixtures: list[dict[str, Any]],
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    semantic_fixtures: list[dict[str, Any]] = []
    canonical_fixtures: list[dict[str, Any]] = []
    machine_fixtures: list[dict[str, Any]] = []
    for fixture in fixtures:
        semantic, canonical, machine = split_proof_fixture(fixture)
        semantic_fixtures.append(semantic)
        canonical_fixtures.append(canonical)
        machine_fixtures.append(machine)
    return {
        "fixture_count": len(semantic_fixtures),
        "fixtures": semantic_fixtures,
    }, canonical_fixtures, machine_fixtures


def build_three_way_report(
    *,
    identity: dict[str, Any],
    semantic_floor: dict[str, Any],
    canonical_proof_detail: dict[str, Any],
    machine_sensitive: dict[str, Any],
) -> dict[str, Any]:
    report = dict(identity)
    report["semantic_floor"] = semantic_floor
    report["canonical_proof_detail"] = canonical_proof_detail
    report["machine_sensitive"] = machine_sensitive
    return report


def validate_three_way_sections(payload: dict[str, Any]) -> None:
    require(isinstance(payload.get("semantic_floor"), dict), "missing semantic_floor")
    require(isinstance(payload.get("canonical_proof_detail"), dict), "missing canonical_proof_detail")
    require(isinstance(payload.get("machine_sensitive"), dict), "missing machine_sensitive")


def validate_semantic_floor(payload: dict[str, Any]) -> None:
    validate_three_way_sections(payload)
    floor = payload["semantic_floor"]
    fixtures = floor.get("fixtures")
    require(isinstance(fixtures, list), "semantic_floor.fixtures must be a list")
    require(floor.get("fixture_count") == len(fixtures), "semantic_floor.fixture_count mismatch")
    for fixture in fixtures:
        require(isinstance(fixture.get("fixture"), str), "semantic_floor fixture missing fixture path")
        for key in ("compile_returncode", "flow_returncode", "prove_returncode"):
            if key in fixture:
                require(fixture[key] == 0, f"{fixture['fixture']}: {key} must be zero")
        for key in ("flow_justified", "flow_unproved", "prove_justified", "prove_unproved"):
            if key in fixture:
                require(fixture[key] == 0, f"{fixture['fixture']}: {key} must be zero")
        for key in ("flow_total_checks", "prove_total_checks"):
            if key in fixture:
                require(
                    isinstance(fixture[key], int) and fixture[key] >= 0,
                    f"{fixture['fixture']}: {key} must be a non-negative int",
                )


def validate_pr101_semantic_floor(payload: dict[str, Any], *, pipeline_context: dict[str, Any]) -> None:
    validate_three_way_sections(payload)
    floor = payload["semantic_floor"]
    baseline_gate_hashes = floor.get("baseline_gate_hashes")
    require(isinstance(baseline_gate_hashes, dict), "PR101 semantic_floor.baseline_gate_hashes missing")
    for node_id in PR101_BASELINE_GATE_IDS:
        require(node_id in baseline_gate_hashes, f"PR101 semantic_floor missing {node_id}")
        expected = _pipeline_report_sha256(pipeline_context, node_id=node_id)
        require(
            baseline_gate_hashes[node_id] == expected,
            f"PR101 semantic_floor {node_id} hash mismatch",
        )
    child_report_hashes = floor.get("child_report_hashes")
    require(isinstance(child_report_hashes, dict), "PR101 semantic_floor.child_report_hashes missing")
    for node_id in PR101_CHILD_REPORT_IDS:
        require(node_id in child_report_hashes, f"PR101 semantic_floor missing {node_id}")
        expected = _pipeline_report_sha256(pipeline_context, node_id=node_id)
        require(
            child_report_hashes[node_id] == expected,
            f"PR101 semantic_floor {node_id} hash mismatch",
        )


def validate_pr101_child_semantic_floor(payload: dict[str, Any]) -> None:
    validate_three_way_sections(payload)
    floor = payload["semantic_floor"]
    for key in (
        "build_returncode",
        "flow_returncode",
        "prove_returncode",
        "extract_assumptions_returncode",
        "diff_assumptions_returncode",
    ):
        require(floor.get(key) == 0, f"{key} must be zero")
    for key in PR101_ANCHOR_KEYS:
        require(
            isinstance(floor.get(key), str) and SHA256_PATTERN.fullmatch(floor[key]) is not None,
            f"{key} must be a sha256",
        )


def _pipeline_report_sha256(pipeline_context: dict[str, Any], *, node_id: str) -> str:
    require(node_id in pipeline_context, f"PR101 pipeline_context missing {node_id}")
    entry = pipeline_context[node_id]
    require(isinstance(entry, dict), f"PR101 pipeline_context {node_id} entry must be a dict")
    report = entry.get("report")
    require(isinstance(report, dict), f"PR101 pipeline_context {node_id} missing report payload")
    report_sha256 = report.get("report_sha256")
    require(
        isinstance(report_sha256, str) and SHA256_PATTERN.fullmatch(report_sha256) is not None,
        f"PR101 pipeline_context {node_id} missing report_sha256",
    )
    return report_sha256
