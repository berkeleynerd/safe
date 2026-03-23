#!/usr/bin/env python3
"""Run the PR08.3a public constants and imported constant values gate."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    normalize_text,
    read_diag_json,
    read_expected_reason,
    require,
    require_repo_command,
    run,
    stable_emitted_artifact_sha256,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr083a-public-constants-report.json"
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"

LOCAL_RANGE = REPO_ROOT / "tests" / "positive" / "constant_range_bound.safe"
LOCAL_CAPACITY = REPO_ROOT / "tests" / "positive" / "constant_channel_capacity.safe"
LOCAL_PRIORITY = REPO_ROOT / "tests" / "positive" / "constant_task_priority.safe"
LOCAL_BOOL = REPO_ROOT / "tests" / "positive" / "constant_discriminant_default.safe"
LOCAL_ACCESS_DEREF = REPO_ROOT / "tests" / "positive" / "constant_access_deref_write.safe"
LOCAL_SHADOW = REPO_ROOT / "tests" / "positive" / "constant_shadow_mutable.safe"

PROVIDER_INT = REPO_ROOT / "tests" / "interfaces" / "provider_constant_int.safe"
CLIENT_RANGE = REPO_ROOT / "tests" / "interfaces" / "client_constant_range.safe"
CLIENT_CAPACITY = REPO_ROOT / "tests" / "interfaces" / "client_constant_capacity.safe"
PROVIDER_BOOL = REPO_ROOT / "tests" / "interfaces" / "provider_constant_bool.safe"
CLIENT_BOOL = REPO_ROOT / "tests" / "interfaces" / "client_constant_bool.safe"
PROVIDER_UNSUPPORTED = REPO_ROOT / "tests" / "interfaces" / "provider_constant_unsupported.safe"
CLIENT_MISSING_VALUE = REPO_ROOT / "tests" / "interfaces" / "client_constant_missing_value.safe"

NEG_NAMED_NUMBER = REPO_ROOT / "tests" / "negative" / "neg_named_number_unsupported.safe"
NEG_WRITE_ASSIGN = REPO_ROOT / "tests" / "negative" / "neg_write_to_constant_assign.safe"
NEG_WRITE_FIELD = REPO_ROOT / "tests" / "negative" / "neg_write_to_constant_field.safe"
NEG_WRITE_INDEX = REPO_ROOT / "tests" / "negative" / "neg_write_to_constant_index.safe"


def repo_arg(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def cli_arg(path: Path) -> str:
    try:
        return repo_arg(path)
    except ValueError:
        return str(path)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    compact = dict(result)
    stdout = compact.get("stdout", "")
    if len(stdout) > 400:
        compact["stdout"] = f"<{len(stdout)} chars>"
    return compact


def stable_failure_result(result: dict[str, Any]) -> dict[str, Any]:
    stable = compact_result(result)
    if "stderr" in stable:
        stable["stderr"] = "<validated via header parity>"
    return stable


def first_stderr_line(result: dict[str, Any], label: str) -> str:
    lines = result["stderr"].splitlines()
    require(lines, f"{label}: expected stderr output")
    return lines[0]


def read_first_reason(result: dict[str, Any], source: Path) -> str:
    payload = read_diag_json(result["stdout"], cli_arg(source))
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{source}: expected at least one diagnostic")
    return diagnostics[0]["reason"]


def first_diag(payload: dict[str, Any], label: str) -> dict[str, Any]:
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{label}: expected at least one diagnostic")
    return diagnostics[0]


def normalized_diag(diag: dict[str, Any]) -> dict[str, Any]:
    return {
        "reason": diag["reason"],
        "message": diag["message"],
        "path": diag["path"],
    }


def observed_files(directory: Path) -> list[str]:
    if not directory.exists():
        return []
    return sorted(str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file())


def emitted_paths(root: Path, stem: str) -> dict[str, Path]:
    return {
        "ast": root / "out" / f"{stem}.ast.json",
        "typed": root / "out" / f"{stem}.typed.json",
        "mir": root / "out" / f"{stem}.mir.json",
        "safei": root / "iface" / f"{stem}.safei.json",
    }


def run_emit(
    *,
    safec: Path,
    source: Path,
    out_dir: Path,
    iface_dir: Path,
    env: dict[str, str],
    temp_root: Path,
    search_dirs: list[Path] | None = None,
    expected_returncode: int = 0,
) -> dict[str, Any]:
    argv = [
        str(safec),
        "emit",
        cli_arg(source),
        "--out-dir",
        str(out_dir),
        "--interface-dir",
        str(iface_dir),
    ]
    for directory in search_dirs or []:
        argv.extend(["--interface-search-dir", str(directory)])
    return run(
        argv,
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=expected_returncode,
    )


def run_ast_or_check(
    *,
    safec: Path,
    command: str,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
    search_dirs: list[Path] | None = None,
    expected_returncode: int = 0,
) -> dict[str, Any]:
    argv = [str(safec), command, cli_arg(source)]
    for directory in search_dirs or []:
        argv.extend(["--interface-search-dir", str(directory)])
    return run(
        argv,
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=expected_returncode,
    )


def validate_emit_outputs(
    *,
    safec: Path,
    python: str,
    source: Path,
    emit_root: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    paths = emitted_paths(emit_root, source.stem.lower())
    for label, path in paths.items():
        require(path.exists(), f"{source}: missing emitted {label} artifact {path}")

    ast_validate = run(
        [python, str(AST_VALIDATOR), str(paths["ast"])],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    typed_payload = load_json(paths["typed"])
    mir_payload = load_json(paths["mir"])
    safei_payload = load_json(paths["safei"])
    mir_payload["source_path"] = normalize_text(mir_payload["source_path"], temp_root=temp_root)
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
            cli_arg(source),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    if mir_payload["graphs"]:
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
        analyze_payload = read_diag_json(analyze_mir["stdout"], str(paths["mir"]))
        require(analyze_payload["diagnostics"] == [], f"{source}: emitted MIR must be diagnostic-free")
        validate_result: dict[str, Any] = compact_result(validate_mir)
        analyze_result: dict[str, Any] = compact_result(analyze_mir)
    else:
        validate_result = {"skipped": True, "reason": "no_local_graphs"}
        analyze_result = {"skipped": True, "reason": "no_local_graphs"}

    return {
        "files": {key: str(path.relative_to(emit_root)) for key, path in paths.items()},
        "hashes": {
            key: stable_emitted_artifact_sha256(path, temp_root=temp_root)
            for key, path in paths.items()
        },
        "validators": {
            "ast": compact_result(ast_validate),
            "output_contracts": compact_result(output_validate),
            "validate_mir": validate_result,
            "analyze_mir": analyze_result,
        },
        "ast_payload": load_json(paths["ast"]),
        "typed_payload": typed_payload,
        "mir_payload": mir_payload,
        "safei_payload": safei_payload,
    }


def collect_constant_object_nodes(payload: Any) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            if node.get("node_type") == "ObjectDeclaration" and node.get("is_constant") is True:
                found.append(node)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(payload)
    return found


def count_constant_locals(payload: dict[str, Any]) -> int:
    total = 0
    for graph in payload.get("graphs", []):
        for local in graph.get("locals", []):
            if local.get("is_constant") is True:
                total += 1
    return total


def require_public_constant(
    *,
    safei_payload: dict[str, Any],
    name: str,
    kind: str | None,
    value: Any | None,
    label: str,
) -> dict[str, Any]:
    objects = {
        entry["name"]: entry
        for entry in safei_payload["objects"]
    }
    require(name in objects, f"{label}: missing public object `{name}` in safei-v1")
    entry = objects[name]
    require(entry.get("is_constant") is True, f"{label}: `{name}` must be exported as constant")
    if kind is None:
        require("static_value_kind" not in entry, f"{label}: `{name}` must omit static value kind")
        require("static_value" not in entry, f"{label}: `{name}` must omit static value")
    else:
        require(entry.get("static_value_kind") == kind, f"{label}: `{name}` static_value_kind drifted")
        require(entry.get("static_value") == value, f"{label}: `{name}` static_value drifted")
    return entry


def run_local_positive_case(
    *,
    name: str,
    source: Path,
    safec: Path,
    python: str,
    env: dict[str, str],
    temp_root: Path,
    expect_mir_constants: bool,
) -> dict[str, Any]:
    ast_result = run_ast_or_check(
        safec=safec,
        command="ast",
        source=source,
        env=env,
        temp_root=temp_root,
    )
    ast_payload = json.loads(ast_result["stdout"])
    constant_nodes = collect_constant_object_nodes(ast_payload)
    require(constant_nodes, f"{name}: expected AST output to contain at least one constant object declaration")

    check_result = run_ast_or_check(
        safec=safec,
        command="check",
        source=source,
        env=env,
        temp_root=temp_root,
    )
    emit_root = temp_root / name
    emit_result = run_emit(
        safec=safec,
        source=source,
        out_dir=emit_root / "out",
        iface_dir=emit_root / "iface",
        env=env,
        temp_root=temp_root,
    )
    validated = validate_emit_outputs(
        safec=safec,
        python=python,
        source=source,
        emit_root=emit_root,
        env=env,
        temp_root=temp_root,
    )
    mirrored_constants = count_constant_locals(validated["mir_payload"])
    if expect_mir_constants:
        require(mirrored_constants > 0, f"{name}: expected mir-v2 locals to preserve constant metadata")

    ast_emit_constants = collect_constant_object_nodes(validated["ast_payload"])
    require(ast_emit_constants, f"{name}: emitted AST artifact must contain constant object declarations")

    return {
        "source": repo_arg(source),
        "ast": compact_result(ast_result),
        "check": compact_result(check_result),
        "emit": compact_result(emit_result),
        "validators": validated["validators"],
        "hashes": validated["hashes"],
        "ast_constant_nodes": len(constant_nodes),
        "mir_constant_locals": mirrored_constants,
    }


def emit_provider(
    *,
    safec: Path,
    python: str,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
    label: str,
) -> tuple[Path, dict[str, Any]]:
    emit_root = temp_root / label
    emit_result = run_emit(
        safec=safec,
        source=source,
        out_dir=emit_root / "out",
        iface_dir=emit_root / "iface",
        env=env,
        temp_root=temp_root,
    )
    validated = validate_emit_outputs(
        safec=safec,
        python=python,
        source=source,
        emit_root=emit_root,
        env=env,
        temp_root=temp_root,
    )
    return emit_root / "iface", {"emit": compact_result(emit_result), **validated}


def assert_repeat_emit_stable(
    *,
    safec: Path,
    python: str,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    first_root = temp_root / "repeat-a"
    second_root = temp_root / "repeat-b"
    runs = []
    for root in (first_root, second_root):
        runs.append(
            compact_result(
                run_emit(
                    safec=safec,
                    source=source,
                    out_dir=root / "out",
                    iface_dir=root / "iface",
                    env=env,
                    temp_root=temp_root,
                )
            )
        )
    first = validate_emit_outputs(
        safec=safec,
        python=python,
        source=source,
        emit_root=first_root,
        env=env,
        temp_root=temp_root,
    )
    second = validate_emit_outputs(
        safec=safec,
        python=python,
        source=source,
        emit_root=second_root,
        env=env,
        temp_root=temp_root,
    )
    require(first["hashes"] == second["hashes"], f"{source}: repeated emit outputs drifted")
    return {
        "runs": runs,
        "hashes": first["hashes"],
    }


def run_import_client_case(
    *,
    name: str,
    source: Path,
    iface_dirs: list[Path],
    safec: Path,
    python: str,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    ast_result = run_ast_or_check(
        safec=safec,
        command="ast",
        source=source,
        env=env,
        temp_root=temp_root,
        search_dirs=iface_dirs,
    )
    check_result = run_ast_or_check(
        safec=safec,
        command="check",
        source=source,
        env=env,
        temp_root=temp_root,
        search_dirs=iface_dirs,
    )
    emit_root = temp_root / name
    emit_result = run_emit(
        safec=safec,
        source=source,
        out_dir=emit_root / "out",
        iface_dir=emit_root / "iface",
        env=env,
        temp_root=temp_root,
        search_dirs=iface_dirs,
    )
    validated = validate_emit_outputs(
        safec=safec,
        python=python,
        source=source,
        emit_root=emit_root,
        env=env,
        temp_root=temp_root,
    )
    return {
        "source": repo_arg(source),
        "ast": compact_result(ast_result),
        "check": compact_result(check_result),
        "emit": compact_result(emit_result),
        "validators": validated["validators"],
        "hashes": validated["hashes"],
        "safei_summary": {
            "package_name": validated["safei_payload"]["package_name"],
            "object_names": [entry["name"] for entry in validated["safei_payload"]["objects"]],
            "type_names": [entry["name"] for entry in validated["typed_payload"]["types"]],
        },
    }


def make_missing_static_value_dir(*, base_interface: Path, temp_root: Path) -> Path:
    target = temp_root / "missing-static-value"
    target.mkdir(parents=True, exist_ok=True)
    payload = load_json(base_interface)
    for entry in payload["objects"]:
        if entry["name"] == "Max_Count":
            entry["is_constant"] = True
            entry["static_value_kind"] = "integer"
            entry.pop("static_value", None)
    write_json(target / base_interface.name, payload)
    return target


def make_kind_mismatch_dir(*, base_interface: Path, temp_root: Path) -> Path:
    target = temp_root / "kind-mismatch"
    target.mkdir(parents=True, exist_ok=True)
    payload = load_json(base_interface)
    for entry in payload["objects"]:
        if entry["name"] == "Max_Count":
            entry["is_constant"] = True
            entry["static_value_kind"] = "boolean"
            entry["static_value"] = 4
    write_json(target / base_interface.name, payload)
    return target


def assert_failure_parity(
    *,
    name: str,
    source: Path,
    safec: Path,
    env: dict[str, str],
    temp_root: Path,
    search_dirs: list[Path] | None = None,
    expected_reason: str | None = None,
    expected_header_substring: str | None = None,
) -> dict[str, Any]:
    reason = expected_reason or read_expected_reason(source)

    ast_result = run_ast_or_check(
        safec=safec,
        command="ast",
        source=source,
        env=env,
        temp_root=temp_root,
        search_dirs=search_dirs,
        expected_returncode=1,
    )
    check_result = run_ast_or_check(
        safec=safec,
        command="check",
        source=source,
        env=env,
        temp_root=temp_root,
        search_dirs=search_dirs,
        expected_returncode=1,
    )
    check_diag = run(
        [
            str(safec),
            "check",
            "--diag-json",
            cli_arg(source),
            *[
                part
                for directory in (search_dirs or [])
                for part in ("--interface-search-dir", str(directory))
            ],
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    emit_root = temp_root / f"{name}-emit-failure"
    emit_result = run_emit(
        safec=safec,
        source=source,
        out_dir=emit_root / "out",
        iface_dir=emit_root / "iface",
        env=env,
        temp_root=temp_root,
        search_dirs=search_dirs,
        expected_returncode=1,
    )

    ast_header = first_stderr_line(ast_result, f"{name}: ast")
    check_header = first_stderr_line(check_result, f"{name}: check")
    emit_header = first_stderr_line(emit_result, f"{name}: emit")
    require(ast_header == check_header == emit_header, f"{name}: first diagnostic header drifted")
    if expected_header_substring is not None:
        require(
            expected_header_substring in ast_header,
            f"{name}: expected first header to contain {expected_header_substring!r}, saw {ast_header!r}",
        )
    diag_payload = read_diag_json(check_diag["stdout"], cli_arg(source))
    first = first_diag(diag_payload, name)
    require(first["reason"] == reason, f"{name}: check --diag-json reason drifted")
    require(observed_files(emit_root / "out") == [], f"{name}: emit unexpectedly wrote output artifacts")
    require(observed_files(emit_root / "iface") == [], f"{name}: emit unexpectedly wrote interface artifacts")

    ast_record = stable_failure_result(ast_result)
    check_record = stable_failure_result(check_result)
    emit_record = stable_failure_result(emit_result)

    return {
        "expected_reason": reason,
        "ast": ast_record,
        "check": check_record,
        "check_diag": {
            "command": check_diag["command"],
            "cwd": check_diag["cwd"],
            "returncode": check_diag["returncode"],
            "first_diagnostic": {
                "reason": first["reason"],
                "path": first["path"],
            },
        },
        "emit": emit_record,
        "header_parity": True,
        "header_contains": expected_header_substring,
        "first_header_kind": "validated_during_gate",
    }


def temp_source_text_for_parity(source: Path) -> str:
    if source == NEG_WRITE_INDEX:
        return (
            "package Neg_Write_To_Constant_Index is\n\n"
            "   type Index is range 1 to 3;\n"
            "   type Buffer is array (Index) of Integer;\n\n"
            "   function Run is\n"
            "      Data : Buffer;\n"
            "   begin\n"
            "      Data (1) = 1;\n"
            "      Data (2) = 2;\n"
            "      Data (3) = 3;\n"
            "      Data (1) = 0;\n"
            "   end Run;\n\n"
            "end Neg_Write_To_Constant_Index;\n"
        )
    original = source.read_text(encoding="utf-8")
    rewritten = original.replace(": constant ", ": ", 1)
    require(rewritten != original, f"{source}: expected constant declaration to rewrite for parity fixture")
    return rewritten


def patch_mir_constant_local(
    *,
    payload: dict[str, Any],
    local_name: str,
    source_path: str,
) -> dict[str, Any]:
    patched = json.loads(json.dumps(payload))
    patched["source_path"] = source_path
    found = False
    for graph in patched.get("graphs", []):
        for local in graph.get("locals", []):
            if local.get("name") == local_name:
                local["is_constant"] = True
                found = True
    require(found, f"synthetic mir fixture: local `{local_name}` not found")
    return patched


def run_write_to_constant_parity_case(
    *,
    name: str,
    negative_source: Path,
    local_name: str,
    safec: Path,
    python: str,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    check_result = run(
        [str(safec), "check", "--diag-json", repo_arg(negative_source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    check_payload = read_diag_json(check_result["stdout"], repo_arg(negative_source))
    check_diag = first_diag(check_payload, repo_arg(negative_source))

    temp_source = temp_root / f"{name}.safe"
    temp_source.write_text(temp_source_text_for_parity(negative_source), encoding="utf-8")
    emit_root = temp_root / f"{name}-emit"
    emit_result = run_emit(
        safec=safec,
        source=temp_source,
        out_dir=emit_root / "out",
        iface_dir=emit_root / "iface",
        env=env,
        temp_root=temp_root,
    )
    validated = validate_emit_outputs(
        safec=safec,
        python=python,
        source=temp_source,
        emit_root=emit_root,
        env=env,
        temp_root=temp_root,
    )
    patched_payload = patch_mir_constant_local(
        payload=validated["mir_payload"],
        local_name=local_name,
        source_path=repo_arg(negative_source),
    )
    fixture_path = temp_root / "mir" / f"{name}.json"
    write_json(fixture_path, patched_payload)
    validate_result = run(
        [str(safec), "validate-mir", str(fixture_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_result = run(
        [str(safec), "analyze-mir", "--diag-json", str(fixture_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    analyze_payload = read_diag_json(analyze_result["stdout"], str(fixture_path))
    analyze_diag = first_diag(analyze_payload, str(fixture_path))
    require(
        normalized_diag(check_diag) == normalized_diag(analyze_diag),
        f"{name}: check/analyze parity drifted",
    )
    return {
        "name": name,
        "source": repo_arg(negative_source),
        "emit": compact_result(emit_result),
        "validate_mir": compact_result(validate_result),
        "check_first": normalized_diag(check_diag),
        "analyze_first": normalized_diag(analyze_diag),
        "fixture": str(fixture_path.relative_to(temp_root)),
    }


def generate_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr083a-public-constants-") as temp_root_str:
        temp_root = Path(temp_root_str)

        local_cases = {
            "range_bound": run_local_positive_case(
                name="local-range-bound",
                source=LOCAL_RANGE,
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
                expect_mir_constants=False,
            ),
            "channel_capacity": run_local_positive_case(
                name="local-channel-capacity",
                source=LOCAL_CAPACITY,
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
                expect_mir_constants=False,
            ),
            "task_priority": run_local_positive_case(
                name="local-task-priority",
                source=LOCAL_PRIORITY,
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
                expect_mir_constants=True,
            ),
            "bool_discriminant_default": run_local_positive_case(
                name="local-bool-discriminant",
                source=LOCAL_BOOL,
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
                expect_mir_constants=False,
            ),
            "constant_access_deref_write": run_local_positive_case(
                name="local-constant-access-deref",
                source=LOCAL_ACCESS_DEREF,
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
                expect_mir_constants=True,
            ),
            "constant_shadow_mutable": run_local_positive_case(
                name="local-constant-shadow",
                source=LOCAL_SHADOW,
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
                expect_mir_constants=True,
            ),
        }

        provider_int_iface_dir, provider_int = emit_provider(
            safec=safec,
            python=python,
            source=PROVIDER_INT,
            env=env,
            temp_root=temp_root,
            label="provider-int",
        )
        provider_bool_iface_dir, provider_bool = emit_provider(
            safec=safec,
            python=python,
            source=PROVIDER_BOOL,
            env=env,
            temp_root=temp_root,
            label="provider-bool",
        )
        provider_unsupported_iface_dir, provider_unsupported = emit_provider(
            safec=safec,
            python=python,
            source=PROVIDER_UNSUPPORTED,
            env=env,
            temp_root=temp_root,
            label="provider-unsupported",
        )

        provider_int_safei = provider_int["safei_payload"]
        provider_bool_safei = provider_bool["safei_payload"]
        provider_unsupported_safei = provider_unsupported["safei_payload"]

        int_object = require_public_constant(
            safei_payload=provider_int_safei,
            name="Max_Count",
            kind="integer",
            value=4,
            label="provider_constant_int",
        )
        bool_object = require_public_constant(
            safei_payload=provider_bool_safei,
            name="Default_Active",
            kind="boolean",
            value=True,
            label="provider_constant_bool",
        )
        unsupported_object = require_public_constant(
            safei_payload=provider_unsupported_safei,
            name="Limit",
            kind=None,
            value=None,
            label="provider_constant_unsupported",
        )

        provider_repeat = assert_repeat_emit_stable(
            safec=safec,
            python=python,
            source=PROVIDER_INT,
            env=env,
            temp_root=temp_root,
        )

        imported_cases = {
            "range_bound": run_import_client_case(
                name="client-constant-range",
                source=CLIENT_RANGE,
                iface_dirs=[provider_int_iface_dir],
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            ),
            "channel_capacity": run_import_client_case(
                name="client-constant-capacity",
                source=CLIENT_CAPACITY,
                iface_dirs=[provider_int_iface_dir],
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            ),
            "bool_discriminant_default": run_import_client_case(
                name="client-constant-bool",
                source=CLIENT_BOOL,
                iface_dirs=[provider_bool_iface_dir],
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            ),
        }

        missing_value_dir = make_missing_static_value_dir(
            base_interface=provider_int_iface_dir / PROVIDER_INT.with_suffix(".safei.json").name,
            temp_root=temp_root,
        )
        kind_mismatch_dir = make_kind_mismatch_dir(
            base_interface=provider_int_iface_dir / PROVIDER_INT.with_suffix(".safei.json").name,
            temp_root=temp_root,
        )

        failures = {
            "named_number_unsupported": assert_failure_parity(
                name="named-number-unsupported",
                source=NEG_NAMED_NUMBER,
                safec=safec,
                env=env,
                temp_root=temp_root,
            ),
            "imported_missing_static_value": assert_failure_parity(
                name="imported-missing-static-value",
                source=CLIENT_MISSING_VALUE,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[provider_unsupported_iface_dir],
                expected_reason="source_frontend_error",
            ),
            "malformed_constant_payload_missing_value": assert_failure_parity(
                name="malformed-constant-payload-missing-value",
                source=CLIENT_RANGE,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[missing_value_dir],
                expected_reason="source_frontend_error",
                expected_header_substring="objects[].static_value is required",
            ),
            "malformed_constant_payload_kind_mismatch": assert_failure_parity(
                name="malformed-constant-payload-kind-mismatch",
                source=CLIENT_RANGE,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[kind_mismatch_dir],
                expected_reason="source_frontend_error",
            ),
            "write_to_constant_assign": assert_failure_parity(
                name="write-to-constant-assign",
                source=NEG_WRITE_ASSIGN,
                safec=safec,
                env=env,
                temp_root=temp_root,
            ),
            "write_to_constant_field": assert_failure_parity(
                name="write-to-constant-field",
                source=NEG_WRITE_FIELD,
                safec=safec,
                env=env,
                temp_root=temp_root,
            ),
            "write_to_constant_index": assert_failure_parity(
                name="write-to-constant-index",
                source=NEG_WRITE_INDEX,
                safec=safec,
                env=env,
                temp_root=temp_root,
            ),
        }

        write_parity = [
            run_write_to_constant_parity_case(
                name="write-to-constant-assign",
                negative_source=NEG_WRITE_ASSIGN,
                local_name="Limit",
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            ),
            run_write_to_constant_parity_case(
                name="write-to-constant-field",
                negative_source=NEG_WRITE_FIELD,
                local_name="Value",
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            ),
            run_write_to_constant_parity_case(
                name="write-to-constant-index",
                negative_source=NEG_WRITE_INDEX,
                local_name="Data",
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            ),
        ]

        provider_int.pop("ast_payload")
        provider_int.pop("typed_payload")
        provider_int.pop("mir_payload")
        provider_int.pop("safei_payload")
        provider_bool.pop("ast_payload")
        provider_bool.pop("typed_payload")
        provider_bool.pop("mir_payload")
        provider_bool.pop("safei_payload")
        provider_unsupported.pop("ast_payload")
        provider_unsupported.pop("typed_payload")
        provider_unsupported.pop("mir_payload")
        provider_unsupported.pop("safei_payload")

        return {
            "task": "PR08.3a",
            "status": "ok",
            "local_positive_cases": local_cases,
            "provider_interfaces": {
                "integer": {
                    **provider_int,
                    "constant_object": int_object,
                },
                "boolean": {
                    **provider_bool,
                    "constant_object": bool_object,
                },
                "unsupported_static_subset": {
                    **provider_unsupported,
                    "constant_object": unsupported_object,
                },
            },
            "repeat_emit": {
                "provider_constant_int": provider_repeat,
            },
            "imported_constant_cases": imported_cases,
            "source_failures": failures,
            "synthetic_mir_parity": write_parity,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    python = find_command("python3")
    env = ensure_sdkroot(os.environ.copy())

    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, python=python, env=env),
        label="PR08.3a public constants",
    )
    write_report(args.report, report)
    print(f"pr083a public constants: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
