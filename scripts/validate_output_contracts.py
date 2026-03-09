#!/usr/bin/env python3
"""Validate emitted typed/MIR/interface outputs against current contract expectations."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise ValueError(message)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def require_mapping(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{path} must be an object")
    return value


def require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        fail(f"{path} must be a list")
    return value


def require_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{path} must be a non-empty string")
    return value


def validate_span(value: Any, path: str) -> None:
    span = require_mapping(value, path)
    for field in ("start_line", "start_col", "end_line", "end_col"):
        number = span.get(field)
        if not isinstance(number, int) or number < 1:
            fail(f"{path}.{field} must be a positive integer")


def validate_decl_list(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        require_string(entry.get("kind"), f"{path}[{index}].kind")
        require_string(entry.get("signature"), f"{path}[{index}].signature")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        result.append(entry)
    return result


def validate_ast_payload(ast_payload: Any, *, path: str) -> dict[str, Any]:
    ast_obj = require_mapping(ast_payload, path)
    if "format" in ast_obj:
        fail(f"{path} must remain untagged")
    if ast_obj.get("node_type") != "CompilationUnit":
        fail(f"{path}.node_type must be CompilationUnit")
    validate_span(ast_obj.get("span"), f"{path}.span")
    return ast_obj


def validate_typed_payload(payload: Any, *, path: str, ast_payload: dict[str, Any]) -> dict[str, Any]:
    typed = require_mapping(payload, path)
    if typed.get("format") != "typed-v2":
        fail(f"{path}.format must be typed-v2")
    for field in (
        "package_name",
        "package_end_name",
        "types",
        "executables",
        "public_declarations",
        "ast",
    ):
        if field not in typed:
            fail(f"{path}.{field} is required")

    require_string(typed.get("package_name"), f"{path}.package_name")
    require_string(typed.get("package_end_name"), f"{path}.package_end_name")
    require_list(typed.get("types"), f"{path}.types")
    validate_decl_list(typed.get("executables"), f"{path}.executables")
    validate_decl_list(typed.get("public_declarations"), f"{path}.public_declarations")
    typed_ast = validate_ast_payload(typed.get("ast"), path=f"{path}.ast")
    if typed_ast != ast_payload:
        fail(f"{path}.ast must exactly match the emitted AST payload")
    return typed


def validate_mir_payload(payload: Any, *, path: str, expected_source_path: str) -> dict[str, Any]:
    mir = require_mapping(payload, path)
    if mir.get("format") != "mir-v2":
        fail(f"{path}.format must be mir-v2")
    for field in ("source_path", "package_name", "types", "graphs"):
        if field not in mir:
            fail(f"{path}.{field} is required")

    source_path = require_string(mir.get("source_path"), f"{path}.source_path")
    if source_path != expected_source_path:
        fail(
            f"{path}.source_path must preserve the exact emit CLI path: "
            f"expected {expected_source_path!r}, saw {source_path!r}"
        )
    require_string(mir.get("package_name"), f"{path}.package_name")
    require_list(mir.get("types"), f"{path}.types")
    require_list(mir.get("graphs"), f"{path}.graphs")
    return mir


def validate_safei_payload(payload: Any, *, path: str) -> dict[str, Any]:
    safei = require_mapping(payload, path)
    if safei.get("format") != "safei-v0":
        fail(f"{path}.format must be safei-v0")
    for field in ("package_name", "executables", "public_declarations"):
        if field not in safei:
            fail(f"{path}.{field} is required")

    require_string(safei.get("package_name"), f"{path}.package_name")
    validate_decl_list(safei.get("executables"), f"{path}.executables")
    validate_decl_list(safei.get("public_declarations"), f"{path}.public_declarations")
    return safei


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ast", required=True, type=Path)
    parser.add_argument("--typed", required=True, type=Path)
    parser.add_argument("--mir", required=True, type=Path)
    parser.add_argument("--safei", required=True, type=Path)
    parser.add_argument("--source-path", required=True)
    args = parser.parse_args()

    ast_payload = validate_ast_payload(load_json(args.ast), path=args.ast.name)
    typed_payload = validate_typed_payload(load_json(args.typed), path=args.typed.name, ast_payload=ast_payload)
    mir_payload = validate_mir_payload(
        load_json(args.mir), path=args.mir.name, expected_source_path=args.source_path
    )
    safei_payload = validate_safei_payload(load_json(args.safei), path=args.safei.name)

    if typed_payload["package_name"] != mir_payload["package_name"]:
        fail(
            f"package_name mismatch: typed={typed_payload['package_name']!r}, "
            f"mir={mir_payload['package_name']!r}"
        )
    if typed_payload["package_name"] != safei_payload["package_name"]:
        fail(
            f"package_name mismatch: typed={typed_payload['package_name']!r}, "
            f"safei={safei_payload['package_name']!r}"
        )

    print(
        f"output contracts: OK ({args.ast.name}, {args.typed.name}, {args.mir.name}, {args.safei.name})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"output contract validation: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
