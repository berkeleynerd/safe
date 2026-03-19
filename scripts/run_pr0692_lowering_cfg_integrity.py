#!/usr/bin/env python3
"""Run the PR06.9.2 lowering and CFG integrity gate."""

from __future__ import annotations

import argparse
import json
import os
import sys
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
    require,
    require_repo_command,
    run,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr0692-lowering-cfg-integrity-report.json"
)

PACKAGE_GLOBAL_OWNER_SOURCE = """package Package_Global_Owner is
   type Value is range 0 to 10;
   type Value_Ptr is access all Value;
   Owner : Value_Ptr = new (1 as Value);

   function Read returns Value is
   begin
      return Owner.all;
   end Read;
end Package_Global_Owner;
"""

PACKAGE_GLOBAL_OBSERVE_SOURCE = """package Package_Global_Observe is
   type Config is record
      Rate : Natural;
   end record;

   type Config_Ptr is access Config;

   Owner : Config_Ptr = new ((Rate = 100) as Config);

   function Read_Config (Ref : access constant Config) returns Integer is
   begin
      return Ref.all.Rate;
   end Read_Config;

   function Read returns Integer is
   begin
      return Read_Config (Owner.Access);
   end Read;
end Package_Global_Observe;
"""

PACKAGE_GLOBAL_RECORD_SOURCE = """package Package_Global_Record is
   type Config is record
      Rate : Natural;
      Limit : Natural;
   end record;

   Current : Config = (Rate = 1, Limit = 2);

   function Read returns Natural is
   begin
      return Current.Rate;
   end Read;
end Package_Global_Record;
"""

PACKAGE_GLOBAL_ARRAY_SOURCE = """package Package_Global_Array is
   type Index is range 1 to 4;
   type Element is range 0 to 20;
   type Table is array (Index) of Element;
   Data : Table;

   function Read returns Element is
   begin
      Data (Index.First) = 5;
      return Data (Index.First);
   end Read;
end Package_Global_Array;
"""

NESTED_DECLARE_SCOPE_SOURCE = """package Nested_Declare_Scope is
   function Read returns Integer is
      Total : Integer = 1;
   begin
      declare
         Inner : Integer = Total;
         Copy : Integer;
      begin
         Copy = Inner;
         Total = Copy;
      end;
      return Total;
   end Read;
end Nested_Declare_Scope;
"""

FOR_LOOP_SCOPE_SOURCE = """package For_Loop_Scope is
   function Read returns Integer is
      Total : Integer = 0;
   begin
      for I in 1 to 3 loop
         Total = Total + I;
      end loop;
      return Total;
   end Read;
end For_Loop_Scope;
"""

IF_RETURN_CFG_SOURCE = """package If_Return_Cfg is
   function Pick (Flag : Boolean) returns Integer is
      Value : Integer = 2;
   begin
      if Flag then
         return Value;
      end if;
      Value = Value + 1;
      return Value;
   end Pick;
end If_Return_Cfg;
"""

WHILE_AND_THEN_CFG_SOURCE = """package While_And_Then_Cfg is
   function Read returns Integer is
      Count : Integer = 0;
      Flag : Boolean = True;
   begin
      if Flag and then Count < 3 then
         Count = Count + 1;
      end if;
      return Count;
   end Read;
end While_And_Then_Cfg;
"""

WHILE_INTEGER_BOUND_CFG_SOURCE = """package While_Integer_Bound_Cfg is
   function Read returns Integer is
      Count : Integer = 0;
      Limit : Integer = 3;
   begin
      while Count < Limit loop
         Count = Count + 1;
      end loop;
      return Count;
   end Read;
end While_Integer_Bound_Cfg;
"""

INLINE_CASES = {
    "package_global_owner": PACKAGE_GLOBAL_OWNER_SOURCE,
    "package_global_observe": PACKAGE_GLOBAL_OBSERVE_SOURCE,
    "package_global_record": PACKAGE_GLOBAL_RECORD_SOURCE,
    "package_global_array": PACKAGE_GLOBAL_ARRAY_SOURCE,
    "nested_declare_scope": NESTED_DECLARE_SCOPE_SOURCE,
    "for_loop_scope": FOR_LOOP_SCOPE_SOURCE,
    "if_return_cfg": IF_RETURN_CFG_SOURCE,
    "while_and_then_cfg": WHILE_AND_THEN_CFG_SOURCE,
    "while_integer_bound_cfg": WHILE_INTEGER_BOUND_CFG_SOURCE,
}

CORPUS_CASES = [
    REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
    REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
    REPO_ROOT / "tests" / "positive" / "ownership_inout.safe",
]


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


def block_map(graph: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {block["id"]: block for block in graph["blocks"]}


def scope_map(graph: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {scope["id"]: scope for scope in graph["scopes"]}


def local_id_map(graph: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {local["id"]: local for local in graph["locals"]}


def local_name_map(graph: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {local["name"]: local for local in graph["locals"]}


def graph_by_name(mir_payload: dict[str, Any], name: str) -> dict[str, Any]:
    for graph in mir_payload["graphs"]:
        if graph["name"] == name:
            return graph
    raise RuntimeError(f"missing graph {name!r}")


def local_by_name(graph: dict[str, Any], name: str) -> dict[str, Any]:
    for local in graph["locals"]:
        if local["name"] == name:
            return local
    raise RuntimeError(f"missing local {name!r} in graph {graph['name']!r}")


def block_by_role(graph: dict[str, Any], role: str) -> dict[str, Any]:
    for block in graph["blocks"]:
        if block["role"] == role:
            return block
    raise RuntimeError(f"missing block role {role!r} in graph {graph['name']!r}")


def first_return_value(graph: dict[str, Any]) -> dict[str, Any]:
    for block in graph["blocks"]:
        terminator = block["terminator"]
        if terminator["kind"] == "return" and terminator["value"] is not None:
            return terminator["value"]
    raise RuntimeError(f"missing return value in graph {graph['name']!r}")


def assign_ops_for_name(graph: dict[str, Any], target_name: str) -> list[dict[str, Any]]:
    ops: list[dict[str, Any]] = []
    for block in graph["blocks"]:
        for op in block["ops"]:
            if (
                op["kind"] == "assign"
                and op["target"]["tag"] == "ident"
                and op["target"]["name"] == target_name
            ):
                ops.append(op)
    return ops


def reachable_block_ids(graph: dict[str, Any]) -> list[str]:
    blocks = block_map(graph)
    pending = [graph["entry_bb"]]
    seen: set[str] = set()
    while pending:
        current = pending.pop(0)
        if current in seen or current not in blocks:
            continue
        seen.add(current)
        terminator = blocks[current]["terminator"]
        kind = terminator["kind"]
        if kind == "jump":
            pending.append(terminator["target"])
        elif kind == "branch":
            pending.append(terminator["true_target"])
            pending.append(terminator["false_target"])
    return sorted(seen)


def assert_graph_integrity(graph: dict[str, Any], *, source: str) -> dict[str, Any]:
    blocks = block_map(graph)
    scopes = scope_map(graph)
    locals_by_id = local_id_map(graph)
    locals_by_name = local_name_map(graph)
    reachable = set(reachable_block_ids(graph))

    require(graph["entry_bb"] in blocks, f"{source}: graph {graph['name']} entry_bb must exist")
    require(
        len(blocks) == len(graph["blocks"]),
        f"{source}: graph {graph['name']} contains duplicate block ids",
    )
    require(
        len(locals_by_id) == len(graph["locals"]),
        f"{source}: graph {graph['name']} contains duplicate local ids",
    )
    require(
        len(locals_by_name) == len(graph["locals"]),
        f"{source}: graph {graph['name']} contains duplicate local names",
    )
    require(
        len(scopes) == len(graph["scopes"]),
        f"{source}: graph {graph['name']} contains duplicate scope ids",
    )

    patched_dead_blocks: list[str] = []
    for block in graph["blocks"]:
        block_id = block["id"]
        require(
            block["active_scope_id"] in scopes,
            f"{source}: graph {graph['name']} block {block_id} has invalid active_scope_id",
        )
        terminator = block["terminator"]
        kind = terminator["kind"]
        require(kind != "<unknown>", f"{source}: graph {graph['name']} block {block_id} has unknown terminator")
        if kind == "jump":
            target = terminator["target"]
            require(target in blocks, f"{source}: graph {graph['name']} block {block_id} jumps to missing {target}")
            if target == block_id:
                patched_dead_blocks.append(block_id)
                require(
                    block_id not in reachable,
                    f"{source}: graph {graph['name']} has reachable self-jump patch {block_id}",
                )
        elif kind == "branch":
            require(
                terminator["true_target"] in blocks,
                f"{source}: graph {graph['name']} block {block_id} has invalid true_target",
            )
            require(
                terminator["false_target"] in blocks,
                f"{source}: graph {graph['name']} block {block_id} has invalid false_target",
            )

        for op in block["ops"]:
            if op["kind"] in {"scope_enter", "scope_exit"}:
                scope_id = op["scope_id"]
                require(
                    scope_id in scopes,
                    f"{source}: graph {graph['name']} op {op['kind']} references unknown scope {scope_id}",
                )
                for local_name in op.get("locals", []):
                    require(
                        local_name in locals_by_name,
                        f"{source}: graph {graph['name']} op {op['kind']} references unknown local {local_name}",
                    )
                    require(
                        locals_by_name[local_name]["scope_id"] == scope_id,
                        f"{source}: graph {graph['name']} local {local_name} does not belong to scope {scope_id}",
                    )

    for scope in graph["scopes"]:
        scope_id = scope["id"]
        require(
            scope["entry_block"] in blocks,
            f"{source}: graph {graph['name']} scope {scope_id} missing real entry_block",
        )
        require(
            bool(scope["exit_blocks"]),
            f"{source}: graph {graph['name']} scope {scope_id} must record at least one exit_block",
        )
        for block_id in scope["exit_blocks"]:
            require(
                block_id in blocks,
                f"{source}: graph {graph['name']} scope {scope_id} exit_block {block_id} missing from graph",
            )
        for local_id in scope["local_ids"]:
            require(
                local_id in locals_by_id,
                f"{source}: graph {graph['name']} scope {scope_id} references unknown local id {local_id}",
            )
            require(
                locals_by_id[local_id]["scope_id"] == scope_id,
                f"{source}: graph {graph['name']} local id {local_id} does not belong to scope {scope_id}",
            )

    for local in graph["locals"]:
        scope_id = local["scope_id"]
        require(scope_id in scopes, f"{source}: graph {graph['name']} local {local['name']} has invalid scope_id")
        require(
            local["id"] in scopes[scope_id]["local_ids"],
            f"{source}: graph {graph['name']} local {local['name']} missing from scope {scope_id} local_ids",
        )

    return {
        "graph": graph["name"],
        "reachable_blocks": sorted(reachable),
        "patched_dead_blocks": patched_dead_blocks,
        "scopes": {
            scope["id"]: {
                "kind": scope["kind"],
                "parent_scope_id": scope["parent_scope_id"],
                "entry_block": scope["entry_block"],
                "exit_blocks": scope["exit_blocks"],
                "local_ids": scope["local_ids"],
            }
            for scope in graph["scopes"]
        },
    }


def assert_case_specific(case_name: str, mir_payload: dict[str, Any]) -> dict[str, Any]:
    graph_name = "Pick" if case_name == "if_return_cfg" else "Read"
    graph = graph_by_name(mir_payload, graph_name)
    summary: dict[str, Any] = {}

    if case_name == "package_global_owner":
        owner_local = local_by_name(graph, "Owner")
        return_value = first_return_value(graph)
        owner_assigns = assign_ops_for_name(graph, "Owner")
        require(owner_local["kind"] == "global", "package_global_owner: Owner must lower as global")
        require(
            owner_local["type"]["name"] == "Value_Ptr",
            f"package_global_owner: expected Owner type Value_Ptr, saw {owner_local['type']['name']!r}",
        )
        require(owner_assigns and owner_assigns[0]["declaration_init"], "package_global_owner: Owner init must be declaration_init")
        require(return_value["tag"] == "select", "package_global_owner: expected select return")
        require(
            return_value["prefix"].get("type") == "Value_Ptr",
            f"package_global_owner: expected select prefix type Value_Ptr, saw {return_value['prefix'].get('type')!r}",
        )
        summary["owner_local_id"] = owner_local["id"]

    elif case_name == "package_global_observe":
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
        require(return_value["tag"] == "call", "package_global_observe: expected call return")
        require(
            return_value["args"][0]["prefix"].get("type") == "Config_Ptr",
            "package_global_observe: expected Owner.Access prefix type Config_Ptr",
        )
        summary["observe_param_id"] = ref_local["id"]

    elif case_name == "package_global_record":
        current_local = local_by_name(graph, "Current")
        current_assigns = assign_ops_for_name(graph, "Current")
        return_value = first_return_value(graph)
        require(current_local["kind"] == "global", "package_global_record: Current must lower as global")
        require(
            current_local["type"]["name"] == "Config",
            f"package_global_record: expected Current type Config, saw {current_local['type']['name']!r}",
        )
        require(
            current_assigns and current_assigns[0]["declaration_init"],
            "package_global_record: Current init must be declaration_init",
        )
        require(return_value["tag"] == "select", "package_global_record: expected select return")
        require(
            return_value["prefix"].get("type") == "Config",
            "package_global_record: expected select prefix type Config",
        )
        summary["current_local_id"] = current_local["id"]

    elif case_name == "package_global_array":
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
            return_value["prefix"].get("type") == "Table",
            "package_global_array: expected index prefix type Table",
        )
        summary["data_local_id"] = data_local["id"]

    elif case_name == "nested_declare_scope":
        scope1 = graph_by_name(mir_payload, "Read")["scopes"][1]
        inner_assigns = assign_ops_for_name(graph, "Inner")
        copy_assigns = assign_ops_for_name(graph, "Copy")
        total_assigns = assign_ops_for_name(graph, "Total")
        exit_block = block_map(graph)[scope1["exit_blocks"][0]]
        require(scope1["kind"] == "block", "nested_declare_scope: inner scope must be block")
        require(scope1["parent_scope_id"] == "scope0", "nested_declare_scope: inner scope must parent scope0")
        require(inner_assigns and inner_assigns[0]["declaration_init"], "nested_declare_scope: Inner init must be declaration_init")
        require(copy_assigns and not copy_assigns[0]["declaration_init"], "nested_declare_scope: Copy assignment must not be declaration_init")
        require(len(total_assigns) >= 2 and not total_assigns[-1]["declaration_init"], "nested_declare_scope: reassigned Total must not be declaration_init")
        require(
            any(op["kind"] == "scope_exit" and op["scope_id"] == "scope1" for op in exit_block["ops"]),
            "nested_declare_scope: exit block must contain scope_exit for scope1",
        )
        summary["inner_scope_exit_block"] = scope1["exit_blocks"][0]

    elif case_name == "for_loop_scope":
        scope1 = graph["scopes"][1]
        loop_local = local_by_name(graph, "I")
        init_block = block_by_role(graph, "for_init")
        latch_block = block_by_role(graph, "for_latch")
        exit_block = block_by_role(graph, "for_exit")
        init_assigns = assign_ops_for_name(graph, "I")
        require(scope1["kind"] == "loop", "for_loop_scope: scope1 must be loop")
        require(scope1["parent_scope_id"] == "scope0", "for_loop_scope: loop scope must parent scope0")
        require(loop_local["scope_id"] == "scope1", "for_loop_scope: I must belong to scope1")
        require(
            any(op["kind"] == "assign" and op["target"]["name"] == "I" and op["declaration_init"] for op in init_block["ops"]),
            "for_loop_scope: loop init assignment must be declaration_init",
        )
        require(
            any(op["kind"] == "assign" and op["target"]["name"] == "I" and not op["declaration_init"] for op in latch_block["ops"]),
            "for_loop_scope: loop latch assignment must not be declaration_init",
        )
        require(
            any(op["kind"] == "scope_exit" and op["scope_id"] == "scope1" for op in exit_block["ops"]),
            "for_loop_scope: for_exit must contain scope_exit for scope1",
        )
        summary["loop_scope_exit_block"] = scope1["exit_blocks"][0]
        summary["loop_assign_count"] = len(init_assigns)

    elif case_name == "if_return_cfg":
        scope0 = graph["scopes"][0]
        return_blocks = sorted(
            block["id"] for block in graph["blocks"] if block["terminator"]["kind"] == "return"
        )
        require(
            sorted(scope0["exit_blocks"]) == return_blocks,
            f"if_return_cfg: expected scope0 exit_blocks {return_blocks}, saw {scope0['exit_blocks']}",
        )
        summary["return_blocks"] = return_blocks

    elif case_name == "while_and_then_cfg":
        header = block_by_role(graph, "entry")
        rhs = block_by_role(graph, "and_then_rhs")
        then_block = block_by_role(graph, "if_then")
        else_block = block_by_role(graph, "if_else")
        require(header["terminator"]["kind"] == "branch", "while_and_then_cfg: entry must branch")
        require(
            header["terminator"]["true_target"] == rhs["id"],
            "while_and_then_cfg: header true_target must go to and_then_rhs",
        )
        require(
            header["terminator"]["false_target"] == else_block["id"],
            "while_and_then_cfg: header false_target must go to if_else",
        )
        require(rhs["terminator"]["kind"] == "branch", "while_and_then_cfg: and_then_rhs must branch")
        require(
            rhs["terminator"]["true_target"] == then_block["id"],
            "while_and_then_cfg: and_then_rhs true_target must go to if_then",
        )
        require(
            rhs["terminator"]["false_target"] == else_block["id"],
            "while_and_then_cfg: and_then_rhs false_target must go to if_else",
        )
        summary["while_header"] = header["id"]
        summary["and_then_rhs"] = rhs["id"]

    elif case_name == "while_integer_bound_cfg":
        header = block_by_role(graph, "while_header")
        body = block_by_role(graph, "while_body")
        exit_block = block_by_role(graph, "while_exit")
        require(
            header["terminator"]["kind"] == "branch",
            "while_integer_bound_cfg: header must branch",
        )
        require(
            header["terminator"]["true_target"] == body["id"],
            "while_integer_bound_cfg: header true_target must go to while_body",
        )
        require(
            header["terminator"]["false_target"] == exit_block["id"],
            "while_integer_bound_cfg: header false_target must go to while_exit",
        )
        summary["while_header"] = header["id"]
        summary["while_body"] = body["id"]

    return summary


def run_positive_case(
    safec: Path,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
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

    mir_output = outputs[f"out/{source.stem.lower()}.mir.json"]
    validate_run = run(
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
    require(analyze_payload["diagnostics"] == [], f"{source}: emitted MIR must be diagnostic-free")

    mir_payload = load_json(mir_output)
    require(mir_payload.get("format") == "mir-v2", f"{mir_output}: expected mir-v2")
    require(mir_payload["source_path"] == str(source), f"{mir_output}: source_path must preserve CLI path")

    integrity = [assert_graph_integrity(graph, source=str(source)) for graph in mir_payload["graphs"]]
    return {
        "source": normalize_text(str(source), temp_root=temp_root),
        "check": {**check_run, "diagnostics": check_payload},
        "emit": emit_run,
        "validate_mir": validate_run,
        "analyze_mir": {**analyze_run, "diagnostics": analyze_payload},
        "integrity": integrity,
        "mir": mir_payload,
    }


def run_inline_cases(
    safec: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for name, source_text in INLINE_CASES.items():
        source_path = temp_root / f"{name}.safe"
        source_path.write_text(source_text, encoding="utf-8")
        case = run_positive_case(safec, source_path, env, temp_root)
        case["case_specific"] = assert_case_specific(name, case["mir"])
        del case["mir"]
        results[name] = case
    return results


def run_corpus_cases(
    safec: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for source in CORPUS_CASES:
        case = run_positive_case(safec, source, env, temp_root)
        del case["mir"]
        results[str(source.relative_to(REPO_ROOT))] = case
    return results


def generate_report(*, safec: Path, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr0692-lowering-") as temp_dir:
        temp_root = Path(temp_dir)
        return {
            "task": "PR06.9.2",
            "inputs": {
                "inline_cases": [f"$TMPDIR/{name}.safe" for name in INLINE_CASES],
                "corpus_cases": [str(path.relative_to(REPO_ROOT)) for path in CORPUS_CASES],
            },
            "results": {
                "inline_cases": run_inline_cases(safec, env, temp_root),
                "corpus_cases": run_corpus_cases(safec, env, temp_root),
            },
            "status": "ok",
        }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run the PR06.9.2 lowering and CFG integrity gate."
    )
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    find_command("python3")
    find_command("alr", Path.home() / "bin" / "alr")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")

    env = ensure_sdkroot(os.environ.copy())

    try:
        report = finalize_deterministic_report(
            lambda: generate_report(safec=safec, env=env),
            label="PR06.9.2 lowering/CFG integrity",
        )
        write_report(args.report, report)
    except Exception as exc:
        print(f"PR06.9.2 lowering/CFG integrity gate failed: {exc}", file=sys.stderr)
        return 1

    print(
        f"PR06.9.2 lowering/CFG integrity gate report written to {display_path(args.report, repo_root=REPO_ROOT)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
