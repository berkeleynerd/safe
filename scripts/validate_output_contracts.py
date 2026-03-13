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


def require_boolean(value: Any, path: str) -> bool:
    if type(value) is not bool:
        fail(f"{path} must be a boolean")
    return value


def require_positive_int(value: Any, path: str) -> int:
    if type(value) is not int or value <= 0:
        fail(f"{path} must be a positive integer")
    return value


def validate_type_descriptor(value: Any, path: str) -> dict[str, Any]:
    descriptor = require_mapping(value, path)
    require_string(descriptor.get("name"), f"{path}.name")
    require_string(descriptor.get("kind"), f"{path}.kind")
    return descriptor


def validate_span(value: Any, path: str) -> None:
    span = require_mapping(value, path)
    for field in ("start_line", "start_col", "end_line", "end_col"):
        number = span.get(field)
        if type(number) is not int or number < 1:
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


def validate_string_list(items: Any, path: str) -> list[str]:
    result: list[str] = []
    for index, item in enumerate(require_list(items, path)):
        result.append(require_string(item, f"{path}[{index}]"))
    return result


def validate_type_descriptor_list(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        result.append(validate_type_descriptor(item, f"{path}[{index}]"))
    return result


def validate_optional_typed_channels(value: Any, path: str) -> list[dict[str, Any]]:
    if value is None:
        return []
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(value, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        require_boolean(entry.get("is_public"), f"{path}[{index}].is_public")
        validate_type_descriptor(entry.get("element_type"), f"{path}[{index}].element_type")
        require_positive_int(entry.get("capacity"), f"{path}[{index}].capacity")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        result.append(entry)
    return result


def validate_typed_channels(value: Any, path: str) -> list[dict[str, Any]]:
    return validate_optional_typed_channels(require_list(value, path), path)


def validate_optional_typed_tasks(value: Any, path: str) -> list[dict[str, Any]]:
    if value is None:
        return []
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(value, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        if type(entry.get("priority")) is not int:
            fail(f"{path}[{index}].priority must be an integer")
        require_boolean(entry.get("has_explicit_priority"), f"{path}[{index}].has_explicit_priority")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        result.append(entry)
    return result


def validate_optional_mir_channels(value: Any, path: str) -> list[dict[str, Any]]:
    if value is None:
        return []
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(value, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        validate_type_descriptor(entry.get("element_type"), f"{path}[{index}].element_type")
        require_positive_int(entry.get("capacity"), f"{path}[{index}].capacity")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        result.append(entry)
    return result


def validate_mir_expr(value: Any, path: str) -> dict[str, Any]:
    expr = require_mapping(value, path)
    require_string(expr.get("tag"), f"{path}.tag")
    if "span" in expr:
        validate_span(expr.get("span"), f"{path}.span")
    return expr


def validate_select_arms(value: Any, path: str) -> list[dict[str, Any]]:
    arms = require_list(value, path)
    if not arms:
        fail(f"{path} must be a non-empty list")
    result: list[dict[str, Any]] = []
    delay_arms = 0
    for index, item in enumerate(arms):
        entry = require_mapping(item, f"{path}[{index}]")
        kind = require_string(entry.get("kind"), f"{path}[{index}].kind")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        if kind == "channel":
            require_string(entry.get("channel_name"), f"{path}[{index}].channel_name")
            require_string(entry.get("variable_name"), f"{path}[{index}].variable_name")
            require_string(entry.get("scope_id"), f"{path}[{index}].scope_id")
            require_string(entry.get("local_id"), f"{path}[{index}].local_id")
            require_string(entry.get("target"), f"{path}[{index}].target")
            validate_type_descriptor(entry.get("type"), f"{path}[{index}].type")
        elif kind == "delay":
            delay_arms += 1
            validate_mir_expr(entry.get("duration_expr"), f"{path}[{index}].duration_expr")
            require_string(entry.get("target"), f"{path}[{index}].target")
        else:
            fail(f"{path}[{index}].kind must be channel or delay")
        result.append(entry)
    if delay_arms > 1:
        fail(f"{path} may contain at most one delay arm")
    return result


def validate_mir_blocks(value: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(value, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("id"), f"{path}[{index}].id")
        require_string(entry.get("role"), f"{path}[{index}].role")
        require_string(entry.get("active_scope_id"), f"{path}[{index}].active_scope_id")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        ops = require_list(entry.get("ops"), f"{path}[{index}].ops")
        for op_index, op_item in enumerate(ops):
            op = require_mapping(op_item, f"{path}[{index}].ops[{op_index}]")
            kind = require_string(op.get("kind"), f"{path}[{index}].ops[{op_index}].kind")
            if kind in {
                "channel_send",
                "channel_receive",
                "channel_try_send",
                "channel_try_receive",
                "delay",
            }:
                require_string(op.get("ownership_effect"), f"{path}[{index}].ops[{op_index}].ownership_effect")
                require_string(op.get("type"), f"{path}[{index}].ops[{op_index}].type")
                if kind != "delay":
                    validate_mir_expr(op.get("channel"), f"{path}[{index}].ops[{op_index}].channel")
                if kind in {"channel_send", "channel_try_send", "delay"}:
                    validate_mir_expr(op.get("value"), f"{path}[{index}].ops[{op_index}].value")
                if kind in {"channel_receive", "channel_try_receive"}:
                    validate_mir_expr(op.get("target"), f"{path}[{index}].ops[{op_index}].target")
                if kind in {"channel_try_send", "channel_try_receive"}:
                    validate_mir_expr(
                        op.get("success_target"),
                        f"{path}[{index}].ops[{op_index}].success_target",
                    )
        terminator = require_mapping(entry.get("terminator"), f"{path}[{index}].terminator")
        kind = require_string(terminator.get("kind"), f"{path}[{index}].terminator.kind")
        if kind == "select":
            validate_select_arms(terminator.get("arms"), f"{path}[{index}].terminator.arms")
        result.append(entry)
    return result


def validate_mir_graphs(value: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(value, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        kind = require_string(entry.get("kind"), f"{path}[{index}].kind")
        require_string(entry.get("entry_bb"), f"{path}[{index}].entry_bb")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        if kind == "task":
            if type(entry.get("priority")) is not int:
                fail(f"{path}[{index}].priority must be an integer for task graphs")
            require_boolean(entry.get("has_explicit_priority"), f"{path}[{index}].has_explicit_priority")
            if entry.get("return_type") is not None:
                fail(f"{path}[{index}].return_type must be null for task graphs")
        validate_mir_blocks(entry.get("blocks"), f"{path}[{index}].blocks")
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
    if typed["package_end_name"] != typed["package_name"]:
        fail(
            f"{path}.package_end_name must match package_name: "
            f"{typed['package_end_name']!r} != {typed['package_name']!r}"
        )
    require_list(typed.get("types"), f"{path}.types")
    validate_optional_typed_channels(typed.get("channels"), f"{path}.channels")
    validate_optional_typed_tasks(typed.get("tasks"), f"{path}.tasks")
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
    validate_optional_mir_channels(mir.get("channels"), f"{path}.channels")
    validate_mir_graphs(mir.get("graphs"), f"{path}.graphs")
    return mir


def validate_safei_object_list(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        validate_type_descriptor(entry.get("type"), f"{path}[{index}].type")
        is_constant = entry.get("is_constant", False)
        if "is_constant" in entry:
            is_constant = require_boolean(entry.get("is_constant"), f"{path}[{index}].is_constant")
        static_kind = entry.get("static_value_kind")
        has_static_value = "static_value" in entry
        if static_kind is None:
            if has_static_value:
                fail(f"{path}[{index}].static_value_kind is required when static_value is present")
        else:
            if not is_constant:
                fail(f"{path}[{index}].static_value_kind requires is_constant to be true")
            if type(static_kind) is not str or static_kind not in {"integer", "boolean"}:
                fail(f"{path}[{index}].static_value_kind must be `integer` or `boolean`")
            if not has_static_value:
                fail(f"{path}[{index}].static_value is required when static_value_kind is present")
            value = entry.get("static_value")
            if static_kind == "integer":
                if type(value) is not int:
                    fail(f"{path}[{index}].static_value must be an integer")
            elif type(value) is not bool:
                fail(f"{path}[{index}].static_value must be a boolean")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        result.append(entry)
    return result


def validate_safei_params(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        require_string(entry.get("mode"), f"{path}[{index}].mode")
        validate_type_descriptor(entry.get("type"), f"{path}[{index}].type")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        result.append(entry)
    return result


def validate_safei_subprograms(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        require_string(entry.get("kind"), f"{path}[{index}].kind")
        require_string(entry.get("signature"), f"{path}[{index}].signature")
        validate_safei_params(entry.get("params"), f"{path}[{index}].params")
        has_return_type = require_boolean(entry.get("has_return_type"), f"{path}[{index}].has_return_type")
        require_boolean(entry.get("return_is_access_def"), f"{path}[{index}].return_is_access_def")
        if has_return_type:
            if "return_type" not in entry:
                fail(f"{path}[{index}].return_type is required when has_return_type is true")
            validate_type_descriptor(entry.get("return_type"), f"{path}[{index}].return_type")
        elif entry.get("return_type") is not None:
            fail(f"{path}[{index}].return_type must be null when has_return_type is false")
        validate_span(entry.get("span"), f"{path}[{index}].span")
        result.append(entry)
    return result


def validate_safei_depends(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("output_name"), f"{path}[{index}].output_name")
        validate_string_list(entry.get("inputs"), f"{path}[{index}].inputs")
        result.append(entry)
    return result


def validate_safei_effect_summaries(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        require_string(entry.get("signature"), f"{path}[{index}].signature")
        validate_string_list(entry.get("reads"), f"{path}[{index}].reads")
        validate_string_list(entry.get("writes"), f"{path}[{index}].writes")
        validate_string_list(entry.get("inputs"), f"{path}[{index}].inputs")
        validate_string_list(entry.get("outputs"), f"{path}[{index}].outputs")
        validate_safei_depends(entry.get("depends"), f"{path}[{index}].depends")
        result.append(entry)
    return result


def validate_safei_channel_access_summaries(items: Any, path: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(require_list(items, path)):
        entry = require_mapping(item, f"{path}[{index}]")
        require_string(entry.get("name"), f"{path}[{index}].name")
        require_string(entry.get("signature"), f"{path}[{index}].signature")
        validate_string_list(entry.get("channels"), f"{path}[{index}].channels")
        result.append(entry)
    return result


def validate_safei_payload(payload: Any, *, path: str) -> dict[str, Any]:
    safei = require_mapping(payload, path)
    if safei.get("format") != "safei-v1":
        fail(f"{path}.format must be safei-v1")
    for field in (
        "package_name",
        "dependencies",
        "executables",
        "public_declarations",
        "types",
        "subtypes",
        "channels",
        "objects",
        "subprograms",
        "effect_summaries",
        "channel_access_summaries",
    ):
        if field not in safei:
            fail(f"{path}.{field} is required")

    require_string(safei.get("package_name"), f"{path}.package_name")
    validate_string_list(safei.get("dependencies"), f"{path}.dependencies")
    executables = validate_decl_list(safei.get("executables"), f"{path}.executables")
    public_declarations = validate_decl_list(safei.get("public_declarations"), f"{path}.public_declarations")
    validate_type_descriptor_list(safei.get("types"), f"{path}.types")
    validate_type_descriptor_list(safei.get("subtypes"), f"{path}.subtypes")
    validate_typed_channels(safei.get("channels"), f"{path}.channels")
    validate_safei_object_list(safei.get("objects"), f"{path}.objects")
    subprograms = validate_safei_subprograms(safei.get("subprograms"), f"{path}.subprograms")
    effect_summaries = validate_safei_effect_summaries(
        safei.get("effect_summaries"), f"{path}.effect_summaries"
    )
    channel_summaries = validate_safei_channel_access_summaries(
        safei.get("channel_access_summaries"), f"{path}.channel_access_summaries"
    )

    executable_names = {entry["name"] for entry in executables}
    subprogram_names = {entry["name"] for entry in subprograms}
    for summary in effect_summaries:
        if summary["name"] not in subprogram_names and summary["name"] not in executable_names:
            fail(f"{path}.effect_summaries contains unknown subprogram {summary['name']!r}")
    for summary in channel_summaries:
        if summary["name"] not in subprogram_names and summary["name"] not in executable_names:
            fail(f"{path}.channel_access_summaries contains unknown subprogram {summary['name']!r}")

    for entry in public_declarations:
        if "signature" not in entry:
            fail(f"{path}.public_declarations entries must include signatures")
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
