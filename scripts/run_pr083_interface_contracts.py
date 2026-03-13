#!/usr/bin/env python3
"""Run the PR08.3 interface contracts and cross-package resolution gate."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    read_diag_json,
    read_expected_reason,
    require,
    require_repo_command,
    run,
    sha256_file,
    sha256_text,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr083-interface-contracts-report.json"
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"

PROVIDER_TYPES = REPO_ROOT / "tests" / "interfaces" / "provider_types.safe"
CLIENT_TYPES = REPO_ROOT / "tests" / "interfaces" / "client_types.safe"
PROVIDER_CHANNEL = REPO_ROOT / "tests" / "interfaces" / "provider_channel.safe"
CLIENT_CHANNEL = REPO_ROOT / "tests" / "interfaces" / "client_channel.safe"
PROVIDER_OBJECT = REPO_ROOT / "tests" / "interfaces" / "provider_object.safe"
CLIENT_OBJECT = REPO_ROOT / "tests" / "interfaces" / "client_object.safe"
PROVIDER_RECORD_OBJECT = REPO_ROOT / "tests" / "interfaces" / "provider_record_object.safe"

NEG_UNKNOWN_IMPORTED_MEMBER = REPO_ROOT / "tests" / "negative" / "neg_unknown_imported_member.safe"
NEG_IMPORTED_OBJECT_ASSIGNMENT = REPO_ROOT / "tests" / "negative" / "neg_imported_object_assignment.safe"
NEG_IMPORTED_OBJECT_SUBCOMPONENT_ASSIGNMENT = (
    REPO_ROOT / "tests" / "negative" / "neg_imported_object_subcomponent_assignment.safe"
)
NEG_CHANNEL_PACKAGE_NOT_WITHD = REPO_ROOT / "tests" / "negative" / "neg_channel_package_not_withd.safe"
NEG_QUALIFIED_CHANNEL_REFERENCE = REPO_ROOT / "tests" / "negative" / "neg_qualified_channel_reference.safe"


def repo_arg(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    compact = dict(result)
    stdout = compact.get("stdout", "")
    if len(stdout) > 400:
        compact["stdout_sha256"] = sha256_text(stdout)
        compact["stdout"] = f"<{len(stdout)} chars>"
    return compact


def first_stderr_line(result: dict[str, Any], label: str) -> str:
    lines = result["stderr"].splitlines()
    require(lines, f"{label}: expected stderr output")
    return lines[0]


def read_first_reason(result: dict[str, Any], source: Path) -> str:
    payload = read_diag_json(result["stdout"], repo_arg(source))
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{source}: expected at least one diagnostic")
    return diagnostics[0]["reason"]


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
        repo_arg(source),
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
    argv = [str(safec), command, repo_arg(source)]
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
            repo_arg(source),
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
        analyze_result: dict[str, Any] = compact_result(analyze_mir)
        validate_result: dict[str, Any] = compact_result(validate_mir)
    else:
        validate_result = {"skipped": True, "reason": "no_local_graphs"}
        analyze_result = {"skipped": True, "reason": "no_local_graphs"}

    require(typed_payload["format"] == "typed-v2", f"{paths['typed']}: expected typed-v2")
    require(mir_payload["format"] == "mir-v2", f"{paths['mir']}: expected mir-v2")
    require(safei_payload["format"] == "safei-v1", f"{paths['safei']}: expected safei-v1")

    return {
        "files": {key: str(path.relative_to(emit_root)) for key, path in paths.items()},
        "hashes": {key: sha256_file(path) for key, path in paths.items()},
        "validators": {
            "ast": compact_result(ast_validate),
            "output_contracts": compact_result(output_validate),
            "validate_mir": validate_result,
            "analyze_mir": analyze_result,
        },
        "typed_summary": {
            "package_name": typed_payload["package_name"],
            "type_names": [entry["name"] for entry in typed_payload["types"]],
            "public_declaration_names": [entry["name"] for entry in typed_payload["public_declarations"]],
        },
        "mir_summary": {
            "package_name": mir_payload["package_name"],
            "source_path": mir_payload["source_path"],
            "type_names": [entry["name"] for entry in mir_payload["types"]],
            "graph_names": [entry["name"] for entry in mir_payload["graphs"]],
        },
        "safei_summary": {
            "package_name": safei_payload["package_name"],
            "dependencies": safei_payload["dependencies"],
            "type_names": [entry["name"] for entry in safei_payload["types"]],
            "subtype_names": [entry["name"] for entry in safei_payload["subtypes"]],
            "channel_names": [entry["name"] for entry in safei_payload["channels"]],
            "object_names": [entry["name"] for entry in safei_payload["objects"]],
            "subprogram_names": [entry["name"] for entry in safei_payload["subprograms"]],
            "effect_summary_names": [entry["name"] for entry in safei_payload["effect_summaries"]],
            "channel_summary_names": [
                entry["name"] for entry in safei_payload["channel_access_summaries"]
            ],
        },
        "typed_payload": typed_payload,
        "mir_payload": mir_payload,
        "safei_payload": safei_payload,
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
    search_dirs: list[Path],
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
                    search_dirs=search_dirs,
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


def run_positive_case(
    *,
    name: str,
    provider: Path,
    client: Path,
    safec: Path,
    python: str,
    env: dict[str, str],
    temp_root: Path,
    assert_roundtrip_determinism: bool = False,
) -> dict[str, Any]:
    provider_iface_dir, provider_result = emit_provider(
        safec=safec,
        python=python,
        source=provider,
        env=env,
        temp_root=temp_root,
        label=f"{name}-provider",
    )

    ast_result = run_ast_or_check(
        safec=safec,
        command="ast",
        source=client,
        env=env,
        temp_root=temp_root,
        search_dirs=[provider_iface_dir],
    )
    check_result = run_ast_or_check(
        safec=safec,
        command="check",
        source=client,
        env=env,
        temp_root=temp_root,
        search_dirs=[provider_iface_dir],
    )
    client_root = temp_root / f"{name}-client"
    emit_result = run_emit(
        safec=safec,
        source=client,
        out_dir=client_root / "out",
        iface_dir=client_root / "iface",
        env=env,
        temp_root=temp_root,
        search_dirs=[provider_iface_dir],
    )
    validated = validate_emit_outputs(
        safec=safec,
        python=python,
        source=client,
        emit_root=client_root,
        env=env,
        temp_root=temp_root,
    )
    provider_safei = provider_result.pop("safei_payload")
    provider_typed = provider_result.pop("typed_payload")
    provider_mir = provider_result.pop("mir_payload")
    client_safei = validated.pop("safei_payload")
    client_typed = validated.pop("typed_payload")
    client_mir = validated.pop("mir_payload")

    result: dict[str, Any] = {
        "provider": provider_result,
        "client": {
            "ast": compact_result(ast_result),
            "check": compact_result(check_result),
            "emit": compact_result(emit_result),
            **validated,
        },
    }

    if provider == PROVIDER_TYPES:
        require(
            {entry["name"] for entry in provider_safei["types"]} == {"Count", "Handle"},
            "provider_types: expected Count and Handle in safei-v1 types",
        )
        require(
            provider_safei["subprograms"][0]["params"][0]["type"]["name"] == "Count",
            "provider_types: expected structured parameter type in safei-v1",
        )
        require(
            len(provider_safei["effect_summaries"]) == 1
            and len(provider_safei["channel_access_summaries"]) == 1,
            "provider_types: expected Bronze-derived public summaries in safei-v1",
        )
        require(
            any(entry["name"] == "Provider_Types.Handle" for entry in client_typed["types"]),
            "client_types: expected imported incomplete type in typed-v2 output",
        )
        require(
            any(entry["name"] == "Provider_Types.Handle" for entry in client_mir["types"]),
            "client_types: expected imported incomplete type in MIR output",
        )
        result["provider_contract"] = {
            "type_names": [entry["name"] for entry in provider_safei["types"]],
            "subprogram_names": [entry["name"] for entry in provider_safei["subprograms"]],
            "effect_summary_names": [entry["name"] for entry in provider_safei["effect_summaries"]],
            "channel_summary_names": [
                entry["name"] for entry in provider_safei["channel_access_summaries"]
            ],
            "client_imported_type_names": [
                entry["name"]
                for entry in client_typed["types"]
                if entry["name"].startswith("Provider_Types.")
            ],
        }
    elif provider == PROVIDER_CHANNEL:
        require(
            client_safei["format"] == "safei-v1",
            "client_channel: expected safei-v1 interface emission",
        )
    elif provider == PROVIDER_OBJECT:
        require(
            client_typed["types"][0]["name"] == "Provider_Object.Count",
            "client_object: imported typed-v2 types must be qualified",
        )

    if assert_roundtrip_determinism:
        result["repeat_emit"] = assert_repeat_emit_stable(
            safec=safec,
            python=python,
            source=client,
            search_dirs=[provider_iface_dir],
            env=env,
            temp_root=temp_root,
        )

    _ = provider_typed, provider_mir, client_mir

    return result


def make_wrong_format_dir(*, base_interface: Path, temp_root: Path) -> Path:
    target = temp_root / "wrong-format"
    target.mkdir(parents=True, exist_ok=True)
    payload = load_json(base_interface)
    payload["format"] = "safei-v0"
    write_json(target / base_interface.name, payload)
    return target


def make_duplicate_dir(*, base_interface: Path, temp_root: Path) -> Path:
    target = temp_root / "duplicate-dir"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(base_interface, target / base_interface.name)
    shutil.copy2(base_interface, target / f"duplicate-{base_interface.name}")
    return target


def make_search_order_dirs(*, base_interface: Path, temp_root: Path) -> tuple[Path, Path]:
    first = temp_root / "search-order-first"
    second = temp_root / "search-order-second"
    first.mkdir(parents=True, exist_ok=True)
    second.mkdir(parents=True, exist_ok=True)
    shutil.copy2(base_interface, first / base_interface.name)

    altered = load_json(base_interface)
    altered["channels"] = []
    altered["public_declarations"] = [entry for entry in altered["public_declarations"] if entry["name"] != "Data_Ch"]
    write_json(second / base_interface.name, altered)
    return first, second


def make_malformed_dir(*, temp_root: Path) -> Path:
    target = temp_root / "malformed-dir"
    target.mkdir(parents=True, exist_ok=True)
    (target / "broken.safei.json").write_text("{ this is not valid json\n", encoding="utf-8")
    return target


def make_missing_channel_type_dir(*, base_interface: Path, temp_root: Path) -> Path:
    target = temp_root / "missing-channel-type"
    target.mkdir(parents=True, exist_ok=True)
    payload = load_json(base_interface)
    payload["channels"][0]["element_type"] = None
    write_json(target / base_interface.name, payload)
    return target


def make_missing_object_type_dir(*, base_interface: Path, temp_root: Path) -> Path:
    target = temp_root / "missing-object-type"
    target.mkdir(parents=True, exist_ok=True)
    payload = load_json(base_interface)
    payload["objects"][0]["type"] = None
    write_json(target / base_interface.name, payload)
    return target


def make_missing_subprogram_type_dir(*, base_interface: Path, temp_root: Path) -> Path:
    target = temp_root / "missing-subprogram-type"
    target.mkdir(parents=True, exist_ok=True)
    payload = load_json(base_interface)
    payload["subprograms"][0]["params"][0]["type"] = None
    if payload["subprograms"][0].get("has_return_type"):
        payload["subprograms"][0]["return_type"] = None
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
            repo_arg(source),
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
    require(
        read_first_reason(check_diag, source) == reason,
        f"{name}: check --diag-json reason drifted",
    )
    require(
        observed_files(emit_root / "out") == [],
        f"{name}: emit unexpectedly wrote output artifacts",
    )
    require(
        observed_files(emit_root / "iface") == [],
        f"{name}: emit unexpectedly wrote interface artifacts",
    )

    return {
        "expected_reason": reason,
        "ast": compact_result(ast_result),
        "check": compact_result(check_result),
        "check_diag": compact_result(check_diag),
        "emit": compact_result(emit_result),
        "first_header": ast_header,
    }


def assert_resolve_failure(
    *,
    name: str,
    source: Path,
    safec: Path,
    env: dict[str, str],
    temp_root: Path,
    search_dirs: list[Path] | None = None,
    expected_reason: str = "source_frontend_error",
) -> dict[str, Any]:
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
            repo_arg(source),
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

    check_header = first_stderr_line(check_result, f"{name}: check")
    emit_header = first_stderr_line(emit_result, f"{name}: emit")
    require(check_header == emit_header, f"{name}: first diagnostic header drifted")
    require(
        read_first_reason(check_diag, source) == expected_reason,
        f"{name}: check --diag-json reason drifted",
    )
    require(
        observed_files(emit_root / "out") == [],
        f"{name}: emit unexpectedly wrote output artifacts",
    )
    require(
        observed_files(emit_root / "iface") == [],
        f"{name}: emit unexpectedly wrote interface artifacts",
    )

    return {
        "expected_reason": expected_reason,
        "check": compact_result(check_result),
        "check_diag": compact_result(check_diag),
        "emit": compact_result(emit_result),
        "first_header": check_header,
    }


def assert_emit_interface_dir_not_implicit(
    *,
    safec: Path,
    source: Path,
    provider_iface_dir: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    emit_root = temp_root / "interface-dir-not-search"
    before_iface_files = observed_files(provider_iface_dir)
    emit_result = run_emit(
        safec=safec,
        source=source,
        out_dir=emit_root / "out",
        iface_dir=provider_iface_dir,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    after_iface_files = observed_files(provider_iface_dir)
    require(
        observed_files(emit_root / "out") == [],
        "--interface-dir implicit search regression: unexpected output artifacts",
    )
    require(
        before_iface_files == after_iface_files,
        "--interface-dir implicit search regression: interface output directory drifted on failure",
    )
    return {
        "emit": compact_result(emit_result),
        "iface_files_before": before_iface_files,
        "iface_files_after": after_iface_files,
    }


def assert_search_order(
    *,
    safec: Path,
    source: Path,
    first_dir: Path,
    second_dir: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    success = run_ast_or_check(
        safec=safec,
        command="check",
        source=source,
        env=env,
        temp_root=temp_root,
        search_dirs=[first_dir, second_dir],
    )
    failure = run_ast_or_check(
        safec=safec,
        command="check",
        source=source,
        env=env,
        temp_root=temp_root,
        search_dirs=[second_dir, first_dir],
        expected_returncode=1,
    )
    failure_diag = run(
        [
            str(safec),
            "check",
            "--diag-json",
            repo_arg(source),
            "--interface-search-dir",
            str(second_dir),
            "--interface-search-dir",
            str(first_dir),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    require(
        read_first_reason(failure_diag, source) == "source_frontend_error",
        "search-order regression: reversed dirs must fail with source_frontend_error",
    )
    return {
        "success": compact_result(success),
        "failure": compact_result(failure),
        "failure_diag": compact_result(failure_diag),
    }


def generate_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr083-interface-contracts-") as temp_root_str:
        temp_root = Path(temp_root_str)

        positive_types = run_positive_case(
            name="types",
            provider=PROVIDER_TYPES,
            client=CLIENT_TYPES,
            safec=safec,
            python=python,
            env=env,
            temp_root=temp_root,
            assert_roundtrip_determinism=True,
        )
        positive_channel = run_positive_case(
            name="channel",
            provider=PROVIDER_CHANNEL,
            client=CLIENT_CHANNEL,
            safec=safec,
            python=python,
            env=env,
            temp_root=temp_root,
        )
        positive_object = run_positive_case(
            name="object",
            provider=PROVIDER_OBJECT,
            client=CLIENT_OBJECT,
            safec=safec,
            python=python,
            env=env,
            temp_root=temp_root,
        )

        provider_types_iface = temp_root / "types-provider" / "iface" / "provider_types.safei.json"
        provider_channel_iface = temp_root / "channel-provider" / "iface" / "provider_channel.safei.json"
        provider_object_iface = temp_root / "object-provider" / "iface" / "provider_object.safei.json"
        provider_record_object_iface, provider_record_object = emit_provider(
            safec=safec,
            python=python,
            source=PROVIDER_RECORD_OBJECT,
            env=env,
            temp_root=temp_root,
            label="record-object-provider",
        )

        wrong_format_dir = make_wrong_format_dir(base_interface=provider_types_iface, temp_root=temp_root)
        duplicate_dir = make_duplicate_dir(base_interface=provider_types_iface, temp_root=temp_root)
        search_order_first, search_order_second = make_search_order_dirs(
            base_interface=provider_channel_iface,
            temp_root=temp_root,
        )
        malformed_dir = make_malformed_dir(temp_root=temp_root)
        missing_channel_type_dir = make_missing_channel_type_dir(
            base_interface=provider_channel_iface,
            temp_root=temp_root,
        )
        missing_object_type_dir = make_missing_object_type_dir(
            base_interface=provider_object_iface,
            temp_root=temp_root,
        )
        missing_subprogram_type_dir = make_missing_subprogram_type_dir(
            base_interface=provider_types_iface,
            temp_root=temp_root,
        )

        failures = {
            "missing_interface": assert_failure_parity(
                name="missing-interface",
                source=CLIENT_TYPES,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[],
                expected_reason="source_frontend_error",
            ),
            "duplicate_same_dir": assert_failure_parity(
                name="duplicate-same-dir",
                source=CLIENT_TYPES,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[duplicate_dir],
                expected_reason="source_frontend_error",
            ),
            "wrong_format_interface": assert_failure_parity(
                name="wrong-format-interface",
                source=CLIENT_TYPES,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[wrong_format_dir],
                expected_reason="source_frontend_error",
            ),
            "malformed_interface": assert_failure_parity(
                name="malformed-interface",
                source=CLIENT_TYPES,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[malformed_dir],
                expected_reason="source_frontend_error",
            ),
            "missing_channel_type": assert_resolve_failure(
                name="missing-channel-type",
                source=CLIENT_CHANNEL,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[missing_channel_type_dir],
                expected_reason="source_frontend_error",
            ),
            "missing_object_type": assert_resolve_failure(
                name="missing-object-type",
                source=CLIENT_OBJECT,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[missing_object_type_dir],
                expected_reason="source_frontend_error",
            ),
            "missing_subprogram_type": assert_resolve_failure(
                name="missing-subprogram-type",
                source=CLIENT_TYPES,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[missing_subprogram_type_dir],
                expected_reason="source_frontend_error",
            ),
            "unknown_imported_member": assert_failure_parity(
                name="unknown-imported-member",
                source=NEG_UNKNOWN_IMPORTED_MEMBER,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[provider_channel_iface.parent],
            ),
            "imported_object_assignment": assert_failure_parity(
                name="imported-object-assignment",
                source=NEG_IMPORTED_OBJECT_ASSIGNMENT,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[provider_object_iface.parent],
            ),
            "imported_object_subcomponent_assignment": assert_failure_parity(
                name="imported-object-subcomponent-assignment",
                source=NEG_IMPORTED_OBJECT_SUBCOMPONENT_ASSIGNMENT,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[provider_record_object_iface],
            ),
            "qualified_channel_missing_with": assert_failure_parity(
                name="qualified-channel-missing-with",
                source=NEG_CHANNEL_PACKAGE_NOT_WITHD,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[],
            ),
            "qualified_channel_missing_interface": assert_failure_parity(
                name="qualified-channel-missing-interface",
                source=NEG_QUALIFIED_CHANNEL_REFERENCE,
                safec=safec,
                env=env,
                temp_root=temp_root,
                search_dirs=[],
            ),
        }

        interface_dir_not_search = assert_emit_interface_dir_not_implicit(
            safec=safec,
            source=CLIENT_TYPES,
            provider_iface_dir=provider_types_iface.parent,
            env=env,
            temp_root=temp_root,
        )
        search_order = assert_search_order(
            safec=safec,
            source=CLIENT_CHANNEL,
            first_dir=search_order_first,
            second_dir=search_order_second,
            env=env,
            temp_root=temp_root,
        )

        return {
            "task": "PR08.3",
            "status": "ok",
            "positive_roundtrips": {
                "types": positive_types,
                "channel": positive_channel,
                "object": positive_object,
            },
            "supporting_interfaces": {
                "record_object_provider": provider_record_object,
            },
            "negative_lookup_cases": failures,
            "search_order": search_order,
            "interface_dir_not_implicit_search": interface_dir_not_search,
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
        label="PR08.3 interface contracts",
    )
    write_report(args.report, report)
    print(f"pr083 interface contracts: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
