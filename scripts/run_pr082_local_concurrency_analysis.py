#!/usr/bin/env python3
"""Run the PR08.2 local concurrency analysis gate."""

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
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr082-local-concurrency-analysis-report.json"
)
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"

POSITIVE_CASES = [
    REPO_ROOT / "tests" / "positive" / "channel_pingpong.safe",
    REPO_ROOT / "tests" / "positive" / "channel_pipeline.safe",
    REPO_ROOT / "tests" / "concurrency" / "multi_task_channel.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_delay_local_scope.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_priority.safe",
    REPO_ROOT / "tests" / "concurrency" / "task_priority_delay.safe",
    REPO_ROOT / "tests" / "concurrency" / "try_ops.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
    REPO_ROOT / "tests" / "concurrency" / "exclusive_variable.safe",
    REPO_ROOT / "tests" / "concurrency" / "task_global_owner.safe",
    REPO_ROOT / "tests" / "concurrency" / "channel_ceiling_priority.safe",
]

NEGATIVE_CASES = [
    REPO_ROOT / "tests" / "negative" / "neg_task_shared_variable.safe",
    REPO_ROOT / "tests" / "negative" / "neg_task_shared_subprogram_global.safe",
    REPO_ROOT / "tests" / "concurrency" / "channel_access_type.safe",
    REPO_ROOT / "tests" / "negative" / "neg_channel_access_component.safe",
    REPO_ROOT / "tests" / "concurrency" / "try_send_ownership.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_ownership_binding.safe",
    REPO_ROOT / "tests" / "negative" / "neg_receive_target_not_null.safe",
    REPO_ROOT / "tests" / "negative" / "neg_try_receive_target_not_null.safe",
    REPO_ROOT / "tests" / "negative" / "neg_send_use_after_move.safe",
    REPO_ROOT / "tests" / "negative" / "neg_try_send_use_after_move.safe",
    REPO_ROOT / "tests" / "negative" / "neg_try_send_reassign_without_check.safe",
    REPO_ROOT / "tests" / "negative" / "neg_try_send_success_overwrite.safe",
    REPO_ROOT / "tests" / "negative" / "neg_try_send_compound_else_use.safe",
]

SEQUENTIAL_PARITY_CASES = [
    {
        "name": "move_target_not_null_regression",
        "source": REPO_ROOT / "tests" / "negative" / "neg_own_target_not_null.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr0695_move_target_not_null_parity.json",
    },
    {
        "name": "use_after_move_regression",
        "source": REPO_ROOT / "tests" / "negative" / "neg_own_use_after_move.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr0695_use_after_move_parity.json",
    },
    {
        "name": "division_by_zero_regression",
        "source": REPO_ROOT / "tests" / "negative" / "neg_rule3_expression.safe",
        "fixture": REPO_ROOT / "compiler_impl" / "tests" / "mir_analysis" / "pr0695_division_by_zero_parity.json",
    },
]

SEQUENTIAL_POSITIVE_TEMP_CASES = [
    {
        "name": "not_null_owner_decl_init",
        "text": (
            "package Not_Null_Owner_Decl_Init is\n"
            "\n"
            "   type Payload is record\n"
            "      Value : Integer;\n"
            "   end record;\n"
            "\n"
            "   type Payload_Ptr is not null access Payload;\n"
            "\n"
            "   function Run is\n"
            "      Owner : Payload_Ptr = new ((Value = 1) as Payload);\n"
            "   begin\n"
            "      Owner.all.Value = Owner.all.Value + 1;\n"
            "   end Run;\n"
            "\n"
            "end Not_Null_Owner_Decl_Init;\n"
        ),
    },
]


def repo_arg(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


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


def span(start_line: int, start_col: int, end_line: int, end_col: int) -> dict[str, int]:
    return {
        "start_line": start_line,
        "start_col": start_col,
        "end_line": end_line,
        "end_col": end_col,
    }


def ident(name: str, type_name: str, item_span: dict[str, int]) -> dict[str, Any]:
    return {
        "tag": "ident",
        "name": name,
        "type": type_name,
        "span": item_span,
    }


def null_expr(type_name: str, item_span: dict[str, int]) -> dict[str, Any]:
    return {"tag": "null", "type": type_name, "span": item_span}


def int_expr(value: int, type_name: str, item_span: dict[str, int]) -> dict[str, Any]:
    return {
        "tag": "int",
        "text": str(value),
        "value": value,
        "type": type_name,
        "span": item_span,
    }


def allocator_expr(
    *,
    aggregate_type: str,
    access_type: str,
    field_name: str,
    field_value: int,
    item_span: dict[str, int],
) -> dict[str, Any]:
    return {
        "tag": "allocator",
        "type": f"access {aggregate_type}",
        "span": item_span,
        "value": {
            "tag": "annotated",
            "type": f"access {aggregate_type}",
            "span": item_span,
            "subtype": {
                "tag": "ident",
                "name": aggregate_type,
                "span": item_span,
            },
            "expr": {
                "tag": "aggregate",
                "type": aggregate_type,
                "span": item_span,
                "fields": [
                    {
                        "field": field_name,
                        "span": item_span,
                        "expr": int_expr(field_value, "Integer", item_span),
                    }
                ],
            },
        },
    }


def select_expr(
    prefix: dict[str, Any],
    selector: str,
    type_name: str,
    item_span: dict[str, int],
) -> dict[str, Any]:
    return {
        "tag": "select",
        "prefix": prefix,
        "selector": selector,
        "type": type_name,
        "span": item_span,
    }


def binary_expr(
    op: str,
    left: dict[str, Any],
    right: dict[str, Any],
    type_name: str,
    item_span: dict[str, int],
) -> dict[str, Any]:
    return {
        "tag": "binary",
        "op": op,
        "left": left,
        "right": right,
        "type": type_name,
        "span": item_span,
    }


def base_payload_types() -> list[dict[str, Any]]:
    return [
        {
            "name": "Payload",
            "kind": "record",
            "fields": {"Value": "Integer"},
        },
        {
            "name": "Payload_Ptr",
            "kind": "access",
            "target": "Payload",
            "not_null": False,
            "anonymous": False,
            "is_constant": False,
            "is_all": False,
            "access_role": "Owner",
        },
    ]


def payload_ptr_type() -> dict[str, Any]:
    return {
        "name": "Payload_Ptr",
        "kind": "access",
        "target": "Payload",
        "not_null": False,
        "anonymous": False,
        "is_constant": False,
        "is_all": False,
        "access_role": "Owner",
    }


def counter_type() -> dict[str, Any]:
    return {
        "name": "counter",
        "kind": "integer",
        "low": 0,
        "high": 100,
    }


def data_channel() -> dict[str, Any]:
    return {
        "name": "Data_Ch",
        "element_type": payload_ptr_type(),
        "capacity": 1,
        "span": span(13, 4, 13, 39),
    }


def root_scope(local_ids: list[str], entry_block: str, exit_blocks: list[str]) -> dict[str, Any]:
    return {
        "id": "scope0",
        "parent_scope_id": None,
        "kind": "subprogram",
        "local_ids": local_ids,
        "entry_block": entry_block,
        "exit_blocks": exit_blocks,
    }


def task_scope(local_ids: list[str], entry_block: str, exit_blocks: list[str]) -> dict[str, Any]:
    return {
        "id": "scope0",
        "parent_scope_id": None,
        "kind": "task",
        "local_ids": local_ids,
        "entry_block": entry_block,
        "exit_blocks": exit_blocks,
    }


def return_terminator(item_span: dict[str, int]) -> dict[str, Any]:
    return {
        "kind": "return",
        "span": item_span,
        "ownership_effect": "None",
        "value": None,
    }


def jump_terminator(target: str, item_span: dict[str, int]) -> dict[str, Any]:
    return {"kind": "jump", "target": target, "span": item_span}


def build_task_variable_ownership_fixture(source_path: str) -> dict[str, Any]:
    counter = counter_type()
    global_span = span(9, 4, 9, 24)
    assign_a_span = span(14, 10, 14, 29)
    assign_b_span = span(21, 10, 21, 29)
    shared_ident_a = ident("shared", "counter", span(14, 10, 14, 15))
    shared_ident_b = ident("shared", "counter", span(21, 10, 21, 15))
    return {
        "format": "mir-v2",
        "source_path": source_path,
        "package_name": "neg_Task_Shared_Variable",
        "types": [counter],
        "channels": [],
        "graphs": [
            {
                "name": "A",
                "kind": "task",
                "entry_bb": "bb0",
                "return_type": None,
                "priority": 31,
                "has_explicit_priority": False,
                "locals": [
                    {
                        "id": "v0",
                        "kind": "global",
                        "mode": "in",
                        "name": "shared",
                        "ownership_role": "",
                        "scope_id": "scope0",
                        "span": global_span,
                        "type": counter,
                    }
                ],
                "scopes": [task_scope(["v0"], "bb0", [])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": span(11, 4, 16, 9),
                        "ops": [
                            {
                                "kind": "assign",
                                "span": assign_a_span,
                                "ownership_effect": "None",
                                "target": shared_ident_a,
                                "type": "counter",
                                "value": binary_expr(
                                    "+",
                                    ident("shared", "counter", span(14, 19, 14, 24)),
                                    int_expr(1, "Integer", span(14, 28, 14, 28)),
                                    "Integer",
                                    span(14, 19, 14, 28),
                                ),
                                "declaration_init": False,
                            }
                        ],
                        "terminator": jump_terminator("bb0", span(13, 7, 15, 14)),
                    }
                ],
            },
            {
                "name": "B",
                "kind": "task",
                "entry_bb": "bb0",
                "return_type": None,
                "priority": 31,
                "has_explicit_priority": False,
                "locals": [
                    {
                        "id": "v1",
                        "kind": "global",
                        "mode": "in",
                        "name": "shared",
                        "ownership_role": "",
                        "scope_id": "scope0",
                        "span": global_span,
                        "type": counter,
                    }
                ],
                "scopes": [task_scope(["v1"], "bb0", [])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": span(18, 4, 23, 9),
                        "ops": [
                            {
                                "kind": "assign",
                                "span": assign_b_span,
                                "ownership_effect": "None",
                                "target": shared_ident_b,
                                "type": "counter",
                                "value": binary_expr(
                                    "+",
                                    ident("shared", "counter", span(21, 19, 21, 24)),
                                    int_expr(1, "Integer", span(21, 28, 21, 28)),
                                    "Integer",
                                    span(21, 19, 21, 28),
                                ),
                                "declaration_init": False,
                            }
                        ],
                        "terminator": jump_terminator("bb0", span(20, 7, 22, 14)),
                    }
                ],
            },
        ],
    }


def build_task_shared_subprogram_global_fixture(source_path: str) -> dict[str, Any]:
    counter = counter_type()
    global_span = span(10, 4, 10, 23)
    helper_span = span(12, 4, 15, 14)
    wrapper_span = span(17, 4, 20, 15)
    task_a_span = span(22, 4, 28, 9)
    task_b_span = span(30, 4, 36, 9)
    helper_call_span = span(19, 7, 19, 12)
    wrapper_call_span = span(33, 10, 33, 16)
    return {
        "format": "mir-v2",
        "source_path": source_path,
        "package_name": "neg_task_shared_subprogram_global",
        "types": [counter],
        "channels": [],
        "graphs": [
            {
                "name": "helper",
                "kind": "procedure",
                "entry_bb": "bb0",
                "span": helper_span,
                "return_type": None,
                "locals": [
                    {
                        "id": "v0",
                        "kind": "global",
                        "mode": "in",
                        "name": "shared",
                        "ownership_role": "",
                        "scope_id": "scope0",
                        "span": global_span,
                        "type": counter,
                    }
                ],
                "scopes": [root_scope(["v0"], "bb0", ["bb0"])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": helper_span,
                        "ops": [
                            {
                                "kind": "assign",
                                "span": global_span,
                                "ownership_effect": "None",
                                "target": ident("shared", "counter", global_span),
                                "type": "counter",
                                "value": int_expr(0, "Integer", span(10, 23, 10, 23)),
                                "declaration_init": True,
                            },
                            {
                                "kind": "assign",
                                "span": span(14, 7, 14, 26),
                                "ownership_effect": "None",
                                "target": ident("shared", "counter", span(14, 7, 14, 12)),
                                "type": "counter",
                                "value": binary_expr(
                                    "+",
                                    ident("shared", "counter", span(14, 16, 14, 21)),
                                    int_expr(1, "Integer", span(14, 25, 14, 25)),
                                    "Integer",
                                    span(14, 16, 14, 25),
                                ),
                                "declaration_init": False,
                            },
                        ],
                        "terminator": return_terminator(helper_span),
                    }
                ],
            },
            {
                "name": "wrapper",
                "kind": "procedure",
                "entry_bb": "bb0",
                "span": wrapper_span,
                "return_type": None,
                "locals": [],
                "scopes": [root_scope([], "bb0", ["bb0"])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": wrapper_span,
                        "ops": [
                            {
                                "kind": "call",
                                "span": helper_call_span,
                                "ownership_effect": "None",
                                "target": None,
                                "type": "Integer",
                                "value": {
                                    "tag": "call",
                                    "span": helper_call_span,
                                    "type": "Integer",
                                    "callee": ident("helper", "Integer", span(19, 7, 19, 12)),
                                    "args": [],
                                    "call_span": helper_call_span,
                                },
                            }
                        ],
                        "terminator": return_terminator(wrapper_span),
                    }
                ],
            },
            {
                "name": "a",
                "kind": "task",
                "entry_bb": "bb0",
                "span": task_a_span,
                "return_type": None,
                "priority": 31,
                "has_explicit_priority": False,
                "locals": [],
                "scopes": [task_scope([], "bb0", ["bb0"])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": task_a_span,
                        "ops": [
                            {
                                "kind": "call",
                                "span": span(25, 10, 25, 15),
                                "ownership_effect": "None",
                                "target": None,
                                "type": "Integer",
                                "value": {
                                    "tag": "call",
                                    "span": span(25, 10, 25, 15),
                                    "type": "Integer",
                                    "callee": ident("helper", "Integer", span(25, 10, 25, 15)),
                                    "args": [],
                                    "call_span": span(25, 10, 25, 15),
                                },
                            }
                        ],
                        "terminator": return_terminator(task_a_span),
                    }
                ],
            },
            {
                "name": "b",
                "kind": "task",
                "entry_bb": "bb0",
                "span": task_b_span,
                "return_type": None,
                "priority": 31,
                "has_explicit_priority": False,
                "locals": [],
                "scopes": [task_scope([], "bb0", ["bb0"])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": task_b_span,
                        "ops": [
                            {
                                "kind": "call",
                                "span": wrapper_call_span,
                                "ownership_effect": "None",
                                "target": None,
                                "type": "Integer",
                                "value": {
                                    "tag": "call",
                                    "span": wrapper_call_span,
                                    "type": "Integer",
                                    "callee": ident("wrapper", "Integer", span(33, 10, 33, 16)),
                                    "args": [],
                                    "call_span": wrapper_call_span,
                                },
                            }
                        ],
                        "terminator": return_terminator(task_b_span),
                    }
                ],
            },
        ],
    }


def build_receive_target_not_null_fixture(source_path: str, *, try_receive: bool) -> dict[str, Any]:
    run_span = span(15, 4, 20 if try_receive else 19, 17)
    target_decl_span = span(16, 7, 16, 49)
    receive_span = span(19, 7, 19, 43) if try_receive else span(18, 7, 18, 30)
    payload_types = base_payload_types()
    locals_list = [
        {
            "id": "v0",
            "kind": "local",
            "mode": "in",
            "name": "Target",
            "ownership_role": "Owner",
            "scope_id": "scope0",
            "span": target_decl_span,
            "type": payload_ptr_type(),
        }
    ]
    local_ids = ["v0"]
    ops: list[dict[str, Any]] = [
        {
            "kind": "scope_enter",
            "span": run_span,
            "scope_id": "scope0",
            "locals": ["Target"] + (["Success"] if try_receive else []),
        },
        {
            "kind": "assign",
            "span": target_decl_span,
            "ownership_effect": "Move",
            "target": ident("Target", "Payload_Ptr", span(16, 7, 16, 12)),
            "type": "Payload_Ptr",
            "value": allocator_expr(
                aggregate_type="Payload",
                access_type="Payload_Ptr",
                field_name="Value",
                field_value=2,
                item_span=span(16, 28, 16, 49),
            ),
            "declaration_init": True,
        },
    ]
    if try_receive:
        locals_list.append(
            {
                "id": "v1",
                "kind": "local",
                "mode": "in",
                "name": "Success",
                "ownership_role": "",
                "scope_id": "scope0",
                "span": span(17, 7, 17, 31),
                "type": {
                    "name": "Boolean",
                    "kind": "integer",
                    "low": 0,
                    "high": 1,
                },
            }
        )
        local_ids.append("v1")
        ops.append(
            {
                "kind": "assign",
                "span": span(17, 7, 17, 31),
                "ownership_effect": "None",
                "target": ident("Success", "Boolean", span(17, 7, 17, 13)),
                "type": "Boolean",
                "value": {
                    "tag": "bool",
                    "type": "Boolean",
                    "value": False,
                    "span": span(17, 26, 17, 30),
                },
                "declaration_init": True,
            }
        )
        ops.append(
            {
                "kind": "channel_try_receive",
                "span": receive_span,
                "ownership_effect": "None",
                "channel": ident("Data_Ch", "Payload_Ptr", span(19, 19, 19, 25)),
                "target": ident("Target", "Payload_Ptr", span(19, 28, 19, 33)),
                "success_target": ident("Success", "Boolean", span(19, 36, 19, 42)),
                "type": "Payload_Ptr",
            }
        )
    else:
        ops.append(
            {
                "kind": "channel_receive",
                "span": receive_span,
                "ownership_effect": "None",
                "channel": ident("Data_Ch", "Payload_Ptr", span(18, 15, 18, 21)),
                "target": ident("Target", "Payload_Ptr", span(18, 24, 18, 29)),
                "type": "Payload_Ptr",
            }
        )

    return {
        "format": "mir-v2",
        "source_path": source_path,
        "package_name": "Neg_Try_Receive_Target_Not_Null" if try_receive else "Neg_Receive_Target_Not_Null",
        "types": payload_types,
        "channels": [data_channel()],
        "graphs": [
            {
                "name": "Run",
                "kind": "procedure",
                "entry_bb": "bb0",
                "return_type": None,
                "locals": locals_list,
                "scopes": [root_scope(local_ids, "bb0", ["bb0"])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": run_span,
                        "ops": ops,
                        "terminator": return_terminator(run_span),
                    }
                ],
            }
        ],
    }


def build_send_use_after_move_fixture(source_path: str, *, try_send: bool) -> dict[str, Any]:
    run_span = span(15, 4, 21 if try_send else 20, 17)
    decl_span = span(16, 7, 16, 49)
    payload_types = base_payload_types()
    locals_list = [
        {
            "id": "v0",
            "kind": "local",
            "mode": "in",
            "name": "Source",
            "ownership_role": "Owner",
            "scope_id": "scope0",
            "span": decl_span,
            "type": payload_ptr_type(),
        }
    ]
    local_ids = ["v0"]
    ops: list[dict[str, Any]] = [
        {
            "kind": "scope_enter",
            "span": run_span,
            "scope_id": "scope0",
            "locals": ["Source"] + (["Success"] if try_send else []),
        },
        {
            "kind": "assign",
            "span": decl_span,
            "ownership_effect": "Move",
            "target": ident("Source", "Payload_Ptr", span(16, 7, 16, 12)),
            "type": "Payload_Ptr",
            "value": allocator_expr(
                aggregate_type="Payload",
                access_type="Payload_Ptr",
                field_name="Value",
                field_value=1,
                item_span=span(16, 28, 16, 49),
            ),
            "declaration_init": True,
        },
    ]
    if try_send:
        locals_list.append(
            {
                "id": "v1",
                "kind": "local",
                "mode": "in",
                "name": "Success",
                "ownership_role": "",
                "scope_id": "scope0",
                "span": span(17, 7, 17, 31),
                "type": {
                    "name": "Boolean",
                    "kind": "integer",
                    "low": 0,
                    "high": 1,
                },
            }
        )
        local_ids.append("v1")
        ops.append(
            {
                "kind": "assign",
                "span": span(17, 7, 17, 31),
                "ownership_effect": "None",
                "target": ident("Success", "Boolean", span(17, 7, 17, 13)),
                "type": "Boolean",
                "value": {
                    "tag": "bool",
                    "type": "Boolean",
                    "value": False,
                    "span": span(17, 27, 17, 31),
                },
                "declaration_init": True,
            }
        )
        ops.append(
            {
                "kind": "channel_try_send",
                "span": span(19, 7, 19, 39),
                "ownership_effect": "None",
                "channel": ident("Data_Ch", "Payload_Ptr", span(19, 16, 19, 22)),
                "value": ident("Source", "Payload_Ptr", span(19, 25, 19, 30)),
                "success_target": ident("Success", "Boolean", span(19, 33, 19, 39)),
                "type": "Payload_Ptr",
            }
        )
    else:
        ops.append(
            {
                "kind": "channel_send",
                "span": span(18, 7, 18, 27),
                "ownership_effect": "None",
                "channel": ident("Data_Ch", "Payload_Ptr", span(18, 12, 18, 18)),
                "value": ident("Source", "Payload_Ptr", span(18, 21, 18, 26)),
                "type": "Payload_Ptr",
            }
        )

    source_prefix_span = span(20 if try_send else 19, 7, 20 if try_send else 19, 12)
    ops.append(
        {
            "kind": "assign",
            "span": span(20 if try_send else 19, 7, 20 if try_send else 19, 26),
            "ownership_effect": "None",
            "target": select_expr(
                select_expr(
                    ident("Source", "Payload_Ptr", source_prefix_span),
                    "all",
                    "Payload",
                    source_prefix_span,
                ),
                "Value",
                "Integer",
                span(20 if try_send else 19, 7, 20 if try_send else 19, 22),
            ),
            "type": "Integer",
            "value": int_expr(2, "Integer", span(20 if try_send else 19, 26, 20 if try_send else 19, 26)),
            "declaration_init": False,
        }
    )

    return {
        "format": "mir-v2",
        "source_path": source_path,
        "package_name": "Neg_Try_Send_Use_After_Move" if try_send else "Neg_Send_Use_After_Move",
        "types": payload_types,
        "channels": [data_channel()],
        "graphs": [
            {
                "name": "Run",
                "kind": "procedure",
                "entry_bb": "bb0",
                "return_type": None,
                "locals": locals_list,
                "scopes": [root_scope(local_ids, "bb0", ["bb0"])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": run_span,
                        "ops": ops,
                        "terminator": return_terminator(run_span),
                    }
                ],
            }
        ],
    }


def build_try_send_reassign_fixture(source_path: str) -> dict[str, Any]:
    run_span = span(17, 4, 23, 17)
    return {
        "format": "mir-v2",
        "source_path": source_path,
        "package_name": "Neg_Try_Send_Reassign_Without_Check",
        "types": base_payload_types(),
        "channels": [data_channel()],
        "graphs": [
            {
                "name": "Run",
                "kind": "procedure",
                "entry_bb": "bb0",
                "return_type": None,
                "locals": [
                    {
                        "id": "v0",
                        "kind": "local",
                        "mode": "in",
                        "name": "Source",
                        "ownership_role": "Owner",
                        "scope_id": "scope0",
                        "span": span(18, 7, 18, 49),
                        "type": payload_ptr_type(),
                    },
                    {
                        "id": "v1",
                        "kind": "local",
                        "mode": "in",
                        "name": "Success",
                        "ownership_role": "",
                        "scope_id": "scope0",
                        "span": span(19, 7, 19, 31),
                        "type": {
                            "name": "Boolean",
                            "kind": "integer",
                            "low": 0,
                            "high": 1,
                        },
                    },
                ],
                "scopes": [root_scope(["v0", "v1"], "bb0", ["bb0"])],
                "blocks": [
                    {
                        "id": "bb0",
                        "active_scope_id": "scope0",
                        "role": "entry",
                        "span": run_span,
                        "ops": [
                            {
                                "kind": "scope_enter",
                                "span": run_span,
                                "scope_id": "scope0",
                                "locals": ["Source", "Success"],
                            },
                            {
                                "kind": "assign",
                                "span": span(18, 7, 18, 49),
                                "ownership_effect": "Move",
                                "target": ident("Source", "Payload_Ptr", span(18, 7, 18, 12)),
                                "type": "Payload_Ptr",
                                "value": allocator_expr(
                                    aggregate_type="Payload",
                                    access_type="Payload_Ptr",
                                    field_name="Value",
                                    field_value=1,
                                    item_span=span(18, 28, 18, 49),
                                ),
                                "declaration_init": True,
                            },
                            {
                                "kind": "assign",
                                "span": span(19, 7, 19, 31),
                                "ownership_effect": "None",
                                "target": ident("Success", "Boolean", span(19, 7, 19, 13)),
                                "type": "Boolean",
                                "value": {
                                    "tag": "bool",
                                    "type": "Boolean",
                                    "value": False,
                                    "span": span(19, 27, 19, 31),
                                },
                                "declaration_init": True,
                            },
                            {
                                "kind": "channel_try_send",
                                "span": span(21, 7, 21, 39),
                                "ownership_effect": "None",
                                "channel": ident("Data_Ch", "Payload_Ptr", span(21, 16, 21, 22)),
                                "value": ident("Source", "Payload_Ptr", span(21, 25, 21, 30)),
                                "success_target": ident("Success", "Boolean", span(21, 33, 21, 39)),
                                "type": "Payload_Ptr",
                            },
                            {
                                "kind": "assign",
                                "span": span(22, 7, 22, 44),
                                "ownership_effect": "Move",
                                "target": ident("Source", "Payload_Ptr", span(22, 7, 22, 12)),
                                "type": "Payload_Ptr",
                                "value": allocator_expr(
                                    aggregate_type="Payload",
                                    access_type="Payload_Ptr",
                                    field_name="Value",
                                    field_value=2,
                                    item_span=span(22, 17, 22, 44),
                                ),
                                "declaration_init": False,
                            },
                        ],
                        "terminator": return_terminator(run_span),
                    }
                ],
            }
        ],
    }


def flatten_name(expr: dict[str, Any] | None) -> str:
    if not expr:
        return ""
    tag = expr.get("tag")
    if tag == "ident":
        return expr.get("name", "")
    if tag == "select":
        prefix = flatten_name(expr.get("prefix"))
        selector = expr.get("selector", "")
        if not prefix:
            return selector
        return f"{prefix}.{selector}"
    if tag == "conversion":
        return flatten_name(expr.get("inner") or expr.get("expr") or expr.get("value"))
    return ""


def root_name(expr: dict[str, Any] | None) -> str:
    if not expr:
        return ""
    tag = expr.get("tag")
    if tag == "ident":
        return expr.get("name", "")
    if tag == "select":
        return root_name(expr.get("prefix"))
    if tag == "conversion":
        return root_name(expr.get("inner") or expr.get("expr") or expr.get("value"))
    return ""


def note_read(name: str, locals_map: dict[str, dict[str, Any]], reads: set[str], inputs: set[str]) -> None:
    if not name or name not in locals_map:
        return
    local = locals_map[name]
    if local["kind"] == "global":
        reads.add(name)
        inputs.add(f"global:{name}")
    elif local["kind"] == "param":
        inputs.add(f"param:{name}")


def note_write(name: str, locals_map: dict[str, dict[str, Any]], writes: set[str], outputs: set[str]) -> None:
    if not name or name not in locals_map:
        return
    local = locals_map[name]
    if local["kind"] == "global":
        writes.add(name)
        outputs.add(f"global:{name}")
    elif local["kind"] == "param" and local.get("mode") in ("out", "in out"):
        outputs.add(f"param:{name}")


def walk_expr(
    expr: dict[str, Any] | None,
    *,
    locals_map: dict[str, dict[str, Any]],
    graph_names: set[str],
    reads: set[str],
    calls: set[str],
    inputs: set[str],
) -> None:
    if not expr:
        return
    tag = expr.get("tag")
    if tag == "ident":
        note_read(expr.get("name", ""), locals_map, reads, inputs)
    elif tag == "select":
        if expr.get("selector") == "Access":
            note_read(root_name(expr.get("prefix")), locals_map, reads, inputs)
        else:
            walk_expr(
                expr.get("prefix"),
                locals_map=locals_map,
                graph_names=graph_names,
                reads=reads,
                calls=calls,
                inputs=inputs,
            )
    elif tag == "resolved_index":
        walk_expr(
            expr.get("prefix"),
            locals_map=locals_map,
            graph_names=graph_names,
            reads=reads,
            calls=calls,
            inputs=inputs,
        )
        for item in expr.get("args", []):
            walk_expr(item, locals_map=locals_map, graph_names=graph_names, reads=reads, calls=calls, inputs=inputs)
    elif tag in ("conversion", "unary", "annotated"):
        walk_expr(
            expr.get("inner") or expr.get("expr") or expr.get("value"),
            locals_map=locals_map,
            graph_names=graph_names,
            reads=reads,
            calls=calls,
            inputs=inputs,
        )
    elif tag == "binary":
        walk_expr(expr.get("left"), locals_map=locals_map, graph_names=graph_names, reads=reads, calls=calls, inputs=inputs)
        walk_expr(expr.get("right"), locals_map=locals_map, graph_names=graph_names, reads=reads, calls=calls, inputs=inputs)
    elif tag == "allocator":
        walk_expr(
            expr.get("value"),
            locals_map=locals_map,
            graph_names=graph_names,
            reads=reads,
            calls=calls,
            inputs=inputs,
        )
    elif tag == "aggregate":
        for field in expr.get("fields", []):
            walk_expr(field.get("expr"), locals_map=locals_map, graph_names=graph_names, reads=reads, calls=calls, inputs=inputs)
    elif tag == "call":
        callee = flatten_name(expr.get("callee"))
        if callee and callee in graph_names:
            calls.add(callee)
        for arg in expr.get("args", []):
            walk_expr(arg, locals_map=locals_map, graph_names=graph_names, reads=reads, calls=calls, inputs=inputs)


def sorted_list(items: set[str]) -> list[str]:
    return sorted(items, key=lambda value: value.lower())


def dependency_vector(outputs: set[str], inputs: set[str]) -> list[dict[str, Any]]:
    return [{"output_name": name, "inputs": sorted_list(inputs)} for name in sorted_list(outputs)]


def derive_bronze(mir_payload: dict[str, Any]) -> dict[str, Any]:
    graph_names = {graph["name"] for graph in mir_payload["graphs"]}
    init_set: set[str] = set()
    global_spans: dict[str, dict[str, int]] = {}
    summaries: dict[str, dict[str, Any]] = {}

    for graph in mir_payload["graphs"]:
        locals_map = {local["name"]: local for local in graph["locals"]}
        for local in graph["locals"]:
            if local["kind"] == "global" and local["name"] not in global_spans:
                global_spans[local["name"]] = local["span"]

        direct_reads: set[str] = set()
        direct_writes: set[str] = set()
        direct_channels: set[str] = set()
        direct_calls: set[str] = set()
        direct_inputs: set[str] = set()
        direct_outputs: set[str] = set()

        for block in graph["blocks"]:
            for op in block["ops"]:
                kind = op["kind"]
                if kind == "assign":
                    walk_expr(
                        op.get("value"),
                        locals_map=locals_map,
                        graph_names=graph_names,
                        reads=direct_reads,
                        calls=direct_calls,
                        inputs=direct_inputs,
                    )
                    target_root = root_name(op.get("target"))
                    if (
                        target_root
                        and target_root in locals_map
                        and op.get("declaration_init", False)
                        and locals_map[target_root]["kind"] == "global"
                    ):
                        init_set.add(target_root)
                    else:
                        note_write(target_root, locals_map, direct_writes, direct_outputs)
                elif kind == "call":
                    walk_expr(
                        op.get("value"),
                        locals_map=locals_map,
                        graph_names=graph_names,
                        reads=direct_reads,
                        calls=direct_calls,
                        inputs=direct_inputs,
                    )
                elif kind in ("channel_send", "channel_try_send"):
                    walk_expr(
                        op.get("value"),
                        locals_map=locals_map,
                        graph_names=graph_names,
                        reads=direct_reads,
                        calls=direct_calls,
                        inputs=direct_inputs,
                    )
                    channel_root = root_name(op.get("channel"))
                    if channel_root:
                        direct_channels.add(channel_root)
                    if kind == "channel_try_send":
                        note_write(root_name(op.get("success_target")), locals_map, direct_writes, direct_outputs)
                elif kind in ("channel_receive", "channel_try_receive"):
                    channel_root = root_name(op.get("channel"))
                    if channel_root:
                        direct_channels.add(channel_root)
                    note_write(root_name(op.get("target")), locals_map, direct_writes, direct_outputs)
                    if kind == "channel_try_receive":
                        note_write(root_name(op.get("success_target")), locals_map, direct_writes, direct_outputs)
                elif kind == "delay":
                    walk_expr(
                        op.get("value"),
                        locals_map=locals_map,
                        graph_names=graph_names,
                        reads=direct_reads,
                        calls=direct_calls,
                        inputs=direct_inputs,
                    )

            terminator = block["terminator"]
            if terminator["kind"] == "branch":
                walk_expr(
                    terminator.get("condition"),
                    locals_map=locals_map,
                    graph_names=graph_names,
                    reads=direct_reads,
                    calls=direct_calls,
                    inputs=direct_inputs,
                )
            elif terminator["kind"] == "return" and terminator.get("value") is not None:
                walk_expr(
                    terminator.get("value"),
                    locals_map=locals_map,
                    graph_names=graph_names,
                    reads=direct_reads,
                    calls=direct_calls,
                    inputs=direct_inputs,
                )
                direct_outputs.add("return")
            elif terminator["kind"] == "select":
                for arm in terminator.get("arms", []):
                    if arm["kind"] == "channel":
                        direct_channels.add(arm["channel_name"])
                    elif arm["kind"] == "delay":
                        walk_expr(
                            arm.get("duration_expr"),
                            locals_map=locals_map,
                            graph_names=graph_names,
                            reads=direct_reads,
                            calls=direct_calls,
                            inputs=direct_inputs,
                        )

        summaries[graph["name"]] = {
            "name": graph["name"],
            "kind": graph["kind"],
            "is_task": graph["kind"] == "task",
            "priority": graph.get("priority", 0) if graph["kind"] == "task" else 0,
            "span": graph.get("span"),
            "reads": set(direct_reads),
            "writes": set(direct_writes),
            "channels": set(direct_channels),
            "calls": set(direct_calls),
            "inputs": set(direct_inputs),
            "outputs": set(direct_outputs),
        }

    changed = True
    while changed:
        changed = False
        for name, summary in list(summaries.items()):
            updated = {
                key: set(value) if isinstance(value, set) else value
                for key, value in summary.items()
            }
            for callee in sorted(summary["calls"]):
                if callee in summaries:
                    callee_summary = summaries[callee]
                    updated["reads"] |= callee_summary["reads"]
                    updated["writes"] |= callee_summary["writes"]
                    updated["channels"] |= callee_summary["channels"]
                    updated["inputs"] |= callee_summary["inputs"]
                    updated["outputs"] |= callee_summary["outputs"]
                    updated["calls"] |= callee_summary["calls"]
            if any(updated[key] != summary[key] for key in ("reads", "writes", "channels", "inputs", "outputs", "calls")):
                summaries[name] = updated
                changed = True

    task_access: dict[str, set[str]] = {}
    task_calls: dict[str, set[str]] = {}
    channel_tasks: dict[str, set[str]] = {}
    graphs_report: list[dict[str, Any]] = []

    for name in sorted(summaries, key=str.lower):
        summary = summaries[name]
        graphs_report.append(
            {
                "name": name,
                "kind": summary["kind"],
                "is_task": summary["is_task"],
                "priority": summary["priority"],
                "reads": sorted_list(summary["reads"]),
                "writes": sorted_list(summary["writes"]),
                "channels": sorted_list(summary["channels"]),
                "calls": sorted_list(summary["calls"]),
                "inputs": sorted_list(summary["inputs"]),
                "outputs": sorted_list(summary["outputs"]),
                "depends": dependency_vector(summary["outputs"], summary["inputs"]),
            }
        )
        if summary["is_task"]:
            for global_name in sorted(summary["reads"] | summary["writes"], key=str.lower):
                task_access.setdefault(global_name, set()).add(name)
            for callee in sorted(summary["calls"], key=str.lower):
                task_calls.setdefault(callee, set()).add(name)
            for channel in sorted(summary["channels"], key=str.lower):
                channel_tasks.setdefault(channel, set()).add(name)

    ownership = [
        {"global_name": global_name, "task_name": sorted_list(tasks)[0]}
        for global_name, tasks in sorted(task_access.items(), key=lambda item: item[0].lower())
        if len(tasks) == 1
    ]
    shared_globals = [
        {"global_name": global_name, "tasks": sorted_list(tasks)}
        for global_name, tasks in sorted(task_access.items(), key=lambda item: item[0].lower())
        if len(tasks) > 1
    ]
    shared_callees = [
        {
            "callee": callee,
            "tasks": sorted_list(tasks),
            "globals": sorted_list(summaries[callee]["reads"] | summaries[callee]["writes"]),
        }
        for callee, tasks in sorted(task_calls.items(), key=lambda item: item[0].lower())
        if len(tasks) > 1 and (summaries[callee]["reads"] or summaries[callee]["writes"])
    ]
    ceilings = []
    for channel_name, tasks in sorted(channel_tasks.items(), key=lambda item: item[0].lower()):
        task_names = sorted_list(tasks)
        priority = max(summaries[task]["priority"] for task in task_names)
        ceilings.append(
            {
                "channel_name": channel_name,
                "priority": priority,
                "task_names": task_names,
            }
        )

    return {
        "graphs": graphs_report,
        "initializes": sorted_list(init_set),
        "ownership": ownership,
        "shared_globals": shared_globals,
        "shared_callees": shared_callees,
        "ceilings": ceilings,
        "global_spans": global_spans,
    }


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        "ast": root / "out" / f"{stem}.ast.json",
        "typed": root / "out" / f"{stem}.typed.json",
        "mir": root / "out" / f"{stem}.mir.json",
        "safei": root / "iface" / f"{stem}.safei.json",
    }


def validate_positive_case(
    *,
    safec: Path,
    python: str,
    sample: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    check_result = run(
        [str(safec), "check", "--diag-json", repo_arg(sample)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    check_payload = read_diag_json(check_result["stdout"], repo_arg(sample))
    require(not check_payload["diagnostics"], f"{sample.name}: expected clean check diagnostics")

    case_dir = temp_root / sample.stem
    out_dir = case_dir / "out"
    iface_dir = case_dir / "iface"
    emit_result = run(
        [str(safec), "emit", repo_arg(sample), "--out-dir", str(out_dir), "--interface-dir", str(iface_dir)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    paths = emitted_paths(case_dir, sample)
    for path in paths.values():
        require(path.exists(), f"{sample.name}: missing emitted artifact {path.name}")

    ast_validate = run(
        [python, str(AST_VALIDATOR), str(paths["ast"])],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    contract_validate = run(
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
    validate_mir = run(
        [str(safec), "validate-mir", str(paths["mir"])],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_result = run(
        [str(safec), "analyze-mir", "--diag-json", str(paths["mir"])],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    analyze_payload = read_diag_json(analyze_result["stdout"], str(paths["mir"]))
    require(not analyze_payload["diagnostics"], f"{sample.name}: expected clean analyze-mir diagnostics")

    return {
        "source": repo_arg(sample),
        "check": check_result,
        "emit": emit_result,
        "validate_ast": ast_validate,
        "validate_contracts": contract_validate,
        "validate_mir": validate_mir,
        "analyze_mir": analyze_result,
    }


def validate_negative_source_case(
    *,
    safec: Path,
    sample: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    expected_reason = read_expected_reason(sample)
    check_result = run(
        [str(safec), "check", "--diag-json", repo_arg(sample)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(check_result["stdout"], repo_arg(sample))
    diag = first_diag(payload, repo_arg(sample))
    require(diag["reason"] == expected_reason, f"{sample.name}: expected {expected_reason}, saw {diag['reason']}")
    return {
        "source": repo_arg(sample),
        "expected_reason": expected_reason,
        "first_diagnostic": normalized_diag(diag),
        "check": check_result,
    }


def write_temp_mir(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_temp_source(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        rewrite_pr117_reference_surface_source(
            rewrite_pr1162_legacy_source(rewrite_pr116_whitespace_source(text)),
            mode="combined",
        ),
        encoding="utf-8",
    )


def run_concurrency_parity_case(
    *,
    safec: Path,
    source: Path,
    fixture_payload: dict[str, Any],
    env: dict[str, str],
    temp_root: Path,
    label: str,
) -> dict[str, Any]:
    check_result = run(
        [str(safec), "check", "--diag-json", repo_arg(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    check_payload = read_diag_json(check_result["stdout"], repo_arg(source))
    check_diag = first_diag(check_payload, repo_arg(source))

    fixture_path = temp_root / "mir" / f"{label}.json"
    write_temp_mir(fixture_path, fixture_payload)
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
        f"{label}: check/analyze parity drifted",
    )
    return {
        "name": label,
        "source": repo_arg(source),
        "fixture": str(fixture_path.relative_to(temp_root)),
        "validate_mir": validate_result,
        "check_first": normalized_diag(check_diag),
        "analyze_first": normalized_diag(analyze_diag),
    }


def run_existing_parity_case(
    *,
    safec: Path,
    source: Path,
    fixture: Path,
    env: dict[str, str],
    temp_root: Path,
    label: str,
) -> dict[str, Any]:
    check_result = run(
        [str(safec), "check", "--diag-json", repo_arg(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    check_payload = read_diag_json(check_result["stdout"], repo_arg(source))
    check_diag = first_diag(check_payload, repo_arg(source))
    analyze_result = run(
        [str(safec), "analyze-mir", "--diag-json", str(fixture)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    analyze_payload = read_diag_json(analyze_result["stdout"], str(fixture))
    analyze_diag = first_diag(analyze_payload, str(fixture))
    require(
        normalized_diag(check_diag) == normalized_diag(analyze_diag),
        f"{label}: sequential parity drifted",
    )
    return {
        "name": label,
        "source": repo_arg(source),
        "fixture": repo_arg(fixture),
        "check_first": normalized_diag(check_diag),
        "analyze_first": normalized_diag(analyze_diag),
    }


def run_temp_positive_check_case(
    *,
    safec: Path,
    env: dict[str, str],
    temp_root: Path,
    name: str,
    text: str,
) -> dict[str, Any]:
    source_path = temp_root / "sources" / f"{name}.safe"
    write_temp_source(source_path, text)
    check_result = run(
        [str(safec), "check", "--diag-json", str(source_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    check_payload = read_diag_json(check_result["stdout"], str(source_path))
    require(not check_payload["diagnostics"], f"{name}: expected clean check diagnostics")
    return {
        "name": name,
        "source": str(source_path.relative_to(temp_root)),
        "check": check_result,
    }


def build_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr082-local-concurrency-") as temp_root_str:
        temp_root = Path(temp_root_str)

        positive_results = [
            validate_positive_case(
                safec=safec,
                python=python,
                sample=sample,
                env=env,
                temp_root=temp_root,
            )
            for sample in POSITIVE_CASES
        ]

        negative_results = [
            validate_negative_source_case(
                safec=safec,
                sample=sample,
                env=env,
                temp_root=temp_root,
            )
            for sample in NEGATIVE_CASES
        ]

        evidence: dict[str, Any] = {}
        for sample in (
            REPO_ROOT / "tests" / "concurrency" / "task_global_owner.safe",
            REPO_ROOT / "tests" / "concurrency" / "channel_ceiling_priority.safe",
        ):
            case_dir = temp_root / f"evidence-{sample.stem}"
            out_dir = case_dir / "out"
            iface_dir = case_dir / "iface"
            run(
                [str(safec), "emit", repo_arg(sample), "--out-dir", str(out_dir), "--interface-dir", str(iface_dir)],
                cwd=REPO_ROOT,
                env=env,
                temp_root=temp_root,
            )
            mir_payload = load_json(out_dir / f"{sample.stem.lower()}.mir.json")
            bronze = derive_bronze(mir_payload)
            evidence[repo_arg(sample)] = bronze

        task_global_evidence = evidence["tests/concurrency/task_global_owner.safe"]
        require(
            task_global_evidence["ownership"] == [{"global_name": "shared", "task_name": "worker"}],
            "task_global_owner.safe: ownership map drifted",
        )
        worker_graph = next(item for item in task_global_evidence["graphs"] if item["name"] == "worker")
        require(worker_graph["reads"] == ["shared"], "task_global_owner.safe: worker reads drifted")
        require(worker_graph["writes"] == ["shared"], "task_global_owner.safe: worker writes drifted")
        require(worker_graph["depends"] == [{"output_name": "global:shared", "inputs": ["global:shared"]}], "task_global_owner.safe: worker depends drifted")
        require(task_global_evidence["initializes"] == ["shared"], "task_global_owner.safe: initializes drifted")

        ceiling_evidence = evidence["tests/concurrency/channel_ceiling_priority.safe"]
        require(
            ceiling_evidence["ceilings"] == [{"channel_name": "data_ch", "priority": 20, "task_names": ["fast", "slow"]}],
            "channel_ceiling_priority.safe: ceiling summary drifted",
        )
        fast_graph = next(item for item in ceiling_evidence["graphs"] if item["name"] == "fast")
        slow_graph = next(item for item in ceiling_evidence["graphs"] if item["name"] == "slow")
        push_graph = next(item for item in ceiling_evidence["graphs"] if item["name"] == "push")
        require(fast_graph["channels"] == ["data_ch"], "channel_ceiling_priority.safe: fast channel access drifted")
        require(slow_graph["channels"] == ["data_ch"], "channel_ceiling_priority.safe: slow channel access drifted")
        require(push_graph["channels"] == ["data_ch"], "channel_ceiling_priority.safe: push channel access drifted")

        shared_callee_fixture = build_task_shared_subprogram_global_fixture(
            "tests/negative/neg_task_shared_subprogram_global.safe"
        )
        shared_callee_bronze = derive_bronze(shared_callee_fixture)
        require(
            shared_callee_bronze["shared_globals"] == [{"global_name": "shared", "tasks": ["a", "b"]}],
            "neg_task_shared_subprogram_global.safe: shared-global Bronze summary drifted",
        )
        require(
            shared_callee_bronze["shared_callees"]
            == [{"callee": "helper", "tasks": ["a", "b"], "globals": ["shared"]}],
            "neg_task_shared_subprogram_global.safe: shared-callee Bronze summary drifted",
        )
        evidence["synthetic/neg_task_shared_subprogram_global"] = shared_callee_bronze

        concurrency_parity = [
            run_concurrency_parity_case(
                safec=safec,
                source=REPO_ROOT / "tests" / "negative" / "neg_task_shared_variable.safe",
                fixture_payload=build_task_variable_ownership_fixture("tests/negative/neg_task_shared_variable.safe"),
                env=env,
                temp_root=temp_root,
                label="task_variable_ownership_parity",
            ),
            run_concurrency_parity_case(
                safec=safec,
                source=REPO_ROOT / "tests" / "negative" / "neg_task_shared_subprogram_global.safe",
                fixture_payload=shared_callee_fixture,
                env=env,
                temp_root=temp_root,
                label="task_shared_subprogram_global_parity",
            ),
        ]

        sequential_regression = [
            run_existing_parity_case(
                safec=safec,
                source=case["source"],
                fixture=case["fixture"],
                env=env,
                temp_root=temp_root,
                label=case["name"],
            )
            for case in SEQUENTIAL_PARITY_CASES
        ]

        sequential_positive_regressions = [
            run_temp_positive_check_case(
                safec=safec,
                env=env,
                temp_root=temp_root,
                name=case["name"],
                text=case["text"],
            )
            for case in SEQUENTIAL_POSITIVE_TEMP_CASES
        ]

        return {
            "task": "PR08.2",
            "status": "ok",
            "positive_cases": positive_results,
            "negative_cases": negative_results,
            "concurrency_parity_cases": concurrency_parity,
            "sequential_regression_cases": sequential_regression,
            "sequential_positive_regression_cases": sequential_positive_regressions,
            "bronze_evidence": evidence,
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
        label="PR08.2 local concurrency analysis",
    )
    write_report(args.report, report)

    print(f"pr08.2 local concurrency analysis: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
