#!/usr/bin/env python3
"""Validate emitted AST JSON against the compiler AST contract."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SCHEMA = REPO_ROOT / "compiler" / "ast_schema.json"
STRICT_NODE_FIELDS = {
}
PACKAGE_ITEM_TARGETS = {
    "BasicDeclaration": {
        "TypeDeclaration",
        "IncompleteTypeDeclaration",
        "SubtypeDeclaration",
        "ObjectDeclaration",
        "NumberDeclaration",
        "SubunitStub",
        "ObjectRenamingDeclaration",
        "PackageRenamingDeclaration",
        "SubprogramRenamingDeclaration",
        "SubprogramDeclaration",
        "SubprogramBody",
    },
    "TaskDeclaration": {"TaskDeclaration"},
    "ChannelDeclaration": {"ChannelDeclaration"},
    "UseTypeClause": {"UseTypeClause"},
    "RepresentationItem": {"RepresentationItem"},
    "Pragma": {"Pragma"},
}
ABSTRACT_TARGETS = {
    "BasicDeclaration": {
        "TypeDeclaration",
        "IncompleteTypeDeclaration",
        "SubtypeDeclaration",
        "ObjectDeclaration",
        "NumberDeclaration",
        "SubprogramDeclaration",
        "SubprogramBody",
    },
    "TypeDefinition": {
        "SignedIntegerTypeDefinition",
        "UnconstrainedArrayDefinition",
        "ConstrainedArrayDefinition",
        "RecordTypeDefinition",
        "AccessToObjectDefinition",
    },
    "Name": {
        "DirectName",
        "SelectedComponent",
        "IndexedComponent",
        "FunctionCall",
        "TypeConversion",
    },
    "Literal": {
        "NumericLiteral",
        "EnumerationLiteral",
        "StringLiteral",
        "CharacterLiteral",
    },
    "Aggregate": {
        "RecordAggregate",
    },
    "SubprogramSpecification": {
        "ProcedureSpecification",
        "FunctionSpecification",
    },
    "SimpleStatement": {
        "NullStatement",
        "AssignmentStatement",
        "SimpleReturnStatement",
    },
    "CompoundStatement": {
        "IfStatement",
        "LoopStatement",
        "BlockStatement",
    },
}


def fail(message: str) -> None:
    raise ValueError(message)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def node_contracts(schema: dict[str, Any]) -> dict[str, dict[str, Any]]:
    nodes = schema.get("nodes")
    if not isinstance(nodes, list):
        fail("schema nodes entry must be a list")
    contracts: dict[str, dict[str, Any]] = {}
    for node in nodes:
        node_type = node.get("node_type")
        if not isinstance(node_type, str) or not node_type:
            fail("schema contains a node without a valid node_type")
        contracts[node_type] = node
    return contracts


def split_targets(type_spec: str) -> list[str]:
    match = re.search(r"<(.+)>", type_spec)
    if not match:
        return []
    return [part.strip() for part in match.group(1).split("|")]


def expand_targets(type_spec: str, contracts: dict[str, dict[str, Any]]) -> set[str]:
    expanded: set[str] = set()
    for target in split_targets(type_spec):
        if target in contracts:
            expanded.add(target)
        expanded.update(ABSTRACT_TARGETS.get(target, set()))
    return expanded


def validate_span(value: Any, path: str) -> None:
    if not isinstance(value, dict):
        fail(f"{path} must be an object")
    required = ("start_line", "start_col", "end_line", "end_col")
    for field in required:
        if field not in value:
            fail(f"{path}.{field} is required")
        if not isinstance(value[field], int) or value[field] < 1:
            fail(f"{path}.{field} must be a positive integer")


def validate_node(
    node: Any,
    path: str,
    contracts: dict[str, dict[str, Any]],
) -> None:
    if not isinstance(node, dict):
        fail(f"{path} must be an object")
    node_type = node.get("node_type")
    if not isinstance(node_type, str):
        fail(f"{path}.node_type is required")
    contract = contracts.get(node_type)
    if contract is None:
        fail(f"{path}.node_type {node_type!r} is not defined in compiler/ast_schema.json")

    fields = contract.get("fields", [])
    for field in fields:
        name = field["name"]
        optional = field.get("optional", False)
        if name not in node:
            if optional:
                continue
            fail(f"{path}.{name} is required for node_type {node_type}")
        value = node[name]
        type_spec = field.get("type", "")
        if name == "span":
            validate_span(value, f"{path}.{name}")
            continue
        if type_spec.startswith("NonEmptyList<"):
            if not isinstance(value, list) or not value:
                fail(f"{path}.{name} must be a non-empty list")
        elif type_spec.startswith("List<"):
            if not isinstance(value, list):
                fail(f"{path}.{name} must be a list")
        elif type_spec.startswith("NodeRef<"):
            if value is None:
                fail(f"{path}.{name} must not be null")

        target_types = expand_targets(type_spec, contracts)
        if node_type == "PackageItem" and name == "item":
            kind = node.get("kind")
            allowed_targets = PACKAGE_ITEM_TARGETS.get(kind)
            if not allowed_targets:
                fail(f"{path}.kind must resolve to a known PackageItem target set")
            if not isinstance(value, dict):
                fail(f"{path}.{name} must be a node object")
            validate_node(value, f"{path}.{name}", contracts)
            if value["node_type"] not in allowed_targets:
                fail(
                    f"{path}.{name}.node_type {value['node_type']!r} "
                    f"does not match package-item kind {kind!r}"
                )
            continue
        if not target_types:
            continue

        if isinstance(value, dict):
            validate_node(value, f"{path}.{name}", contracts)
            if value["node_type"] not in target_types:
                fail(
                    f"{path}.{name}.node_type {value['node_type']!r} "
                    f"does not match expected {sorted(target_types)}"
                )
        elif isinstance(value, list):
            for index, element in enumerate(value):
                if not isinstance(element, dict):
                    fail(f"{path}.{name}[{index}] must be a node object")
                validate_node(element, f"{path}.{name}[{index}]", contracts)
                if element["node_type"] not in target_types:
                    fail(
                        f"{path}.{name}[{index}].node_type {element['node_type']!r} "
                        f"does not match expected {sorted(target_types)}"
                    )

    if node_type == "PackageItem":
        allowed = {
            "BasicDeclaration",
            "TaskDeclaration",
            "ChannelDeclaration",
            "UseTypeClause",
            "RepresentationItem",
            "Pragma",
        }
        kind = node.get("kind")
        if kind not in allowed:
            fail(f"{path}.kind must be one of {sorted(allowed)}, saw {kind!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ast_json", nargs="+", type=Path, help="AST JSON files to validate")
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    args = parser.parse_args()

    schema = load_json(args.schema)
    contracts = node_contracts(schema)

    for ast_path in args.ast_json:
        instance = load_json(ast_path)
        validate_node(instance, ast_path.name, contracts)
        print(f"{ast_path}: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"ast validation: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
