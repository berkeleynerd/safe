#!/usr/bin/env python3
"""Run the PR08.4 imported-summary consumption and transitive integration gate."""

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
    require,
    require_repo_command,
    run,
    stable_emitted_artifact_sha256,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr084-transitive-concurrency-integration-report.json"
)
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"

PROVIDER_TRANSITIVE_CHANNEL = REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe"
CLIENT_CHANNEL_PROVIDER = (
    REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_provider_ceiling.safe"
)
CLIENT_CHANNEL_CLIENT = (
    REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_client_ceiling.safe"
)
PROVIDER_TRANSITIVE_GLOBAL = REPO_ROOT / "tests" / "interfaces" / "provider_transitive_global.safe"
CLIENT_GLOBAL_OK = REPO_ROOT / "tests" / "interfaces" / "client_transitive_global_ok.safe"
PROVIDER_IMPORT_OWNERSHIP = (
    REPO_ROOT / "tests" / "interfaces" / "provider_imported_call_ownership.safe"
)
CLIENT_IMPORT_BORROW_OBSERVE = (
    REPO_ROOT / "tests" / "interfaces" / "client_imported_borrow_observe.safe"
)
EXISTING_PROVIDER_CHANNEL = REPO_ROOT / "tests" / "interfaces" / "provider_channel.safe"
EXISTING_CLIENT_CHANNEL = REPO_ROOT / "tests" / "interfaces" / "client_channel.safe"

NEG_IMPORTED_SHARED_GLOBAL = REPO_ROOT / "tests" / "negative" / "neg_imported_shared_global.safe"
NEG_IMPORTED_INOUT_DOUBLE_MOVE = REPO_ROOT / "tests" / "negative" / "neg_imported_inout_double_move.safe"


def repo_arg(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
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
    stderr = compact.get("stderr", "")
    if len(stdout) > 400:
        compact["stdout"] = f"<{len(stdout)} chars>"
    if len(stderr) > 400:
        compact["stderr"] = f"<{len(stderr)} chars>"
    return compact


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


def run_check(
    *,
    safec: Path,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
    search_dirs: list[Path],
    expected_returncode: int = 0,
) -> dict[str, Any]:
    argv = [str(safec), "check", "--diag-json", repo_arg(source)]
    for directory in search_dirs:
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
    iface_dir: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    paths = emitted_paths(emit_root, source.stem.lower())
    paths["safei"] = iface_dir / f"{source.stem.lower()}.safei.json"
    for label, path in paths.items():
        require(path.exists(), f"{source}: missing emitted {label} artifact {path}")
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
    mir_payload = load_json(paths["mir"])
    mir_payload["source_path"] = normalize_text(mir_payload["source_path"], temp_root=temp_root)
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
        "files": {
            key: (
                str(path.relative_to(emit_root))
                if path.is_relative_to(emit_root)
                else str(path.relative_to(temp_root))
            )
            for key, path in paths.items()
        },
        "hashes": {
            key: stable_emitted_artifact_sha256(path, temp_root=temp_root)
            for key, path in paths.items()
        },
        "validators": {
            "output_contracts": compact_result(output_validate),
            "validate_mir": validate_result,
            "analyze_mir": analyze_result,
        },
        "mir_payload": mir_payload,
        "safei_payload": load_json(paths["safei"]),
    }


def flatten_name(expr: dict[str, Any] | None) -> str:
    if not isinstance(expr, dict):
        return ""
    tag = expr.get("tag")
    if tag == "ident":
        return expr.get("name", "")
    if tag == "select":
        prefix = flatten_name(expr.get("prefix"))
        selector = expr.get("selector", "")
        return f"{prefix}.{selector}" if prefix else selector
    if tag == "conversion":
        return flatten_name(expr.get("expr"))
    return ""


def walk_expr(expr: dict[str, Any] | None, callable_names: set[str], reads: set[str], calls: set[str]) -> None:
    if not isinstance(expr, dict):
        return
    tag = expr.get("tag")
    if tag == "ident":
        return
    if tag == "select":
        return
    if tag == "resolved_index":
        walk_expr(expr.get("prefix"), callable_names, reads, calls)
        for item in expr.get("indices", []):
            walk_expr(item, callable_names, reads, calls)
        return
    if tag in {"conversion", "annotated", "unary"}:
        walk_expr(expr.get("expr"), callable_names, reads, calls)
        return
    if tag == "binary":
        walk_expr(expr.get("left"), callable_names, reads, calls)
        walk_expr(expr.get("right"), callable_names, reads, calls)
        return
    if tag == "aggregate":
        for field in expr.get("fields", []):
            walk_expr(field.get("expr"), callable_names, reads, calls)
        return
    if tag == "allocator":
        walk_expr(expr.get("value"), callable_names, reads, calls)
        return
    if tag == "call":
        callee = flatten_name(expr.get("callee"))
        if callee in callable_names:
            calls.add(callee)
        for arg in expr.get("args", []):
            walk_expr(arg, callable_names, reads, calls)


def derive_bronze(mir_payload: dict[str, Any]) -> dict[str, Any]:
    callable_names = {graph["name"] for graph in mir_payload.get("graphs", [])}
    callable_names.update(external["name"] for external in mir_payload.get("externals", []))
    summaries: dict[str, dict[str, Any]] = {}

    for external in mir_payload.get("externals", []):
        summary = {
            "name": external["name"],
            "is_task": False,
            "priority": 0,
            "reads": set(external["effect_summary"]["reads"]),
            "writes": set(external["effect_summary"]["writes"]),
            "channels": set(external["channel_access_summary"]["channels"]),
            "calls": set(),
            "inputs": set(external["effect_summary"]["inputs"]),
            "outputs": set(external["effect_summary"]["outputs"]),
        }
        summaries[summary["name"]] = summary

    for graph in mir_payload.get("graphs", []):
        reads: set[str] = set()
        writes: set[str] = set()
        channels: set[str] = set()
        calls: set[str] = set()
        inputs: set[str] = set()
        outputs: set[str] = set()

        for block in graph.get("blocks", []):
            for op in block.get("ops", []):
                kind = op.get("kind")
                if kind == "call":
                    walk_expr(op.get("value"), callable_names, reads, calls)
                elif kind in {"channel_send", "channel_try_send"}:
                    walk_expr(op.get("value"), callable_names, reads, calls)
                    channels.add(flatten_name(op.get("channel")))
                elif kind in {"channel_receive", "channel_try_receive"}:
                    channels.add(flatten_name(op.get("channel")))
                elif kind == "delay":
                    walk_expr(op.get("value"), callable_names, reads, calls)
            terminator = block.get("terminator", {})
            if terminator.get("kind") == "select":
                for arm in terminator.get("arms", []):
                    if arm.get("kind") == "channel":
                        channels.add(arm["channel_name"])
                    elif arm.get("kind") == "delay":
                        walk_expr(arm.get("duration_expr"), callable_names, reads, calls)

        summary = {
            "name": graph["name"],
            "is_task": graph.get("kind") == "task",
            "priority": graph.get("priority", 0),
            "reads": reads,
            "writes": writes,
            "channels": channels,
            "calls": calls,
            "inputs": inputs,
            "outputs": outputs,
        }
        summaries[summary["name"]] = summary

    changed = True
    while changed:
        changed = False
        for name, summary in list(summaries.items()):
            reads = set(summary["reads"])
            writes = set(summary["writes"])
            channels = set(summary["channels"])
            calls = set(summary["calls"])
            inputs = set(summary["inputs"])
            outputs = set(summary["outputs"])
            for callee in list(summary["calls"]):
                callee_summary = summaries.get(callee)
                if not callee_summary:
                    continue
                reads |= callee_summary["reads"]
                writes |= callee_summary["writes"]
                channels |= callee_summary["channels"]
                calls |= callee_summary["calls"]
                inputs |= callee_summary["inputs"]
                outputs |= callee_summary["outputs"]
            if (
                reads != summary["reads"]
                or writes != summary["writes"]
                or channels != summary["channels"]
                or calls != summary["calls"]
                or inputs != summary["inputs"]
                or outputs != summary["outputs"]
            ):
                summary["reads"] = reads
                summary["writes"] = writes
                summary["channels"] = channels
                summary["calls"] = calls
                summary["inputs"] = inputs
                summary["outputs"] = outputs
                changed = True

    ownership: dict[str, list[str]] = {}
    channel_tasks: dict[str, list[str]] = {}
    task_calls: dict[str, list[str]] = {}
    for summary in summaries.values():
        if not summary["is_task"]:
            continue
        task_name = summary["name"]
        for global_name in sorted(summary["reads"] | summary["writes"]):
            ownership.setdefault(global_name, []).append(task_name)
        for channel_name in sorted(summary["channels"]):
            channel_tasks.setdefault(channel_name, []).append(task_name)
        for callee in sorted(summary["calls"]):
            task_calls.setdefault(callee, []).append(task_name)

    base_ceilings = {
        channel["name"]: channel.get("required_ceiling", 0)
        for channel in mir_payload.get("channels", [])
    }
    ceilings: dict[str, int] = {}
    for channel_name, tasks in channel_tasks.items():
        local_priority = max(summaries[task]["priority"] for task in tasks)
        ceilings[channel_name] = max(base_ceilings.get(channel_name, 0), local_priority)
    for channel_name, priority in base_ceilings.items():
        ceilings.setdefault(channel_name, priority)

    return {
        "summaries": {
            name: {
                "reads": sorted(summary["reads"]),
                "writes": sorted(summary["writes"]),
                "channels": sorted(summary["channels"]),
                "calls": sorted(summary["calls"]),
            }
            for name, summary in sorted(summaries.items())
        },
        "ownership": {name: sorted(tasks) for name, tasks in sorted(ownership.items())},
        "task_calls": {name: sorted(tasks) for name, tasks in sorted(task_calls.items())},
        "ceilings": dict(sorted(ceilings.items())),
    }


def require_reason(stdout: str, path_label: str, expected_reason: str) -> dict[str, Any]:
    payload = read_diag_json(stdout, path_label)
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{path_label}: expected at least one diagnostic")
    require(
        diagnostics[0]["reason"] == expected_reason,
        f"{path_label}: expected {expected_reason}, saw {diagnostics[0]['reason']}",
    )
    return diagnostics[0]


def generate_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr084_gate_") as temp_dir:
        temp_root = Path(temp_dir)
        iface_dir = temp_root / "iface"
        provider_out = temp_root / "providers"
        client_out = temp_root / "clients"
        iface_dir.mkdir()
        provider_out.mkdir()
        client_out.mkdir()

        providers = [
            PROVIDER_TRANSITIVE_CHANNEL,
            PROVIDER_TRANSITIVE_GLOBAL,
            PROVIDER_IMPORT_OWNERSHIP,
            EXISTING_PROVIDER_CHANNEL,
        ]
        provider_results: dict[str, Any] = {}
        for provider in providers:
            emit_root = provider_out / provider.stem.lower()
            emit_root.mkdir()
            emit_result = run_emit(
                safec=safec,
                source=provider,
                out_dir=emit_root / "out",
                iface_dir=iface_dir,
                env=env,
                temp_root=temp_root,
            )
            provider_results[provider.name] = {
                "emit": compact_result(emit_result),
                "outputs": validate_emit_outputs(
                    safec=safec,
                    python=python,
                    source=provider,
                    emit_root=emit_root,
                    iface_dir=iface_dir,
                    env=env,
                    temp_root=temp_root,
                ),
            }

        positives = [
            EXISTING_CLIENT_CHANNEL,
            CLIENT_CHANNEL_PROVIDER,
            CLIENT_CHANNEL_CLIENT,
            CLIENT_GLOBAL_OK,
            CLIENT_IMPORT_BORROW_OBSERVE,
        ]
        positive_results: dict[str, Any] = {}
        for source in positives:
            check_result = run_check(
                safec=safec,
                source=source,
                env=env,
                temp_root=temp_root,
                search_dirs=[iface_dir],
            )
            payload = read_diag_json(check_result["stdout"], repo_arg(source))
            require(payload["diagnostics"] == [], f"{source}: expected clean check diagnostics")
            emit_root = client_out / source.stem.lower()
            emit_root.mkdir()
            emit_result = run_emit(
                safec=safec,
                source=source,
                out_dir=emit_root / "out",
                iface_dir=iface_dir,
                env=env,
                temp_root=temp_root,
                search_dirs=[iface_dir],
            )
            outputs = validate_emit_outputs(
                safec=safec,
                python=python,
                source=source,
                emit_root=emit_root,
                iface_dir=iface_dir,
                env=env,
                temp_root=temp_root,
            )
            positive_results[source.name] = {
                "check": compact_result(check_result),
                "emit": compact_result(emit_result),
                "outputs": outputs,
                "bronze": derive_bronze(outputs["mir_payload"]),
            }

        require(
            positive_results[EXISTING_CLIENT_CHANNEL.name]["bronze"]["summaries"]["Sender"]["channels"]
            == ["Provider_Channel.Data_Ch"],
            "direct imported channel ops must preserve the full qualified channel name",
        )
        require(
            positive_results[CLIENT_CHANNEL_PROVIDER.name]["bronze"]["ceilings"][
                "Provider_Transitive_Channel.Data_Ch"
            ]
            == 12,
            "provider required ceiling must dominate local task priorities when higher",
        )
        require(
            positive_results[CLIENT_CHANNEL_CLIENT.name]["bronze"]["ceilings"][
                "Provider_Transitive_Channel.Data_Ch"
            ]
            == 20,
            "client task priorities must dominate provider required ceiling when higher",
        )
        require(
            positive_results[CLIENT_GLOBAL_OK.name]["bronze"]["ownership"][
                "Provider_Transitive_Global.Shared"
            ]
            == ["Worker"],
            "single-task imported global ownership should stay clean and deterministic",
        )

        negative_results: dict[str, Any] = {}
        shared_global_check = run_check(
            safec=safec,
            source=NEG_IMPORTED_SHARED_GLOBAL,
            env=env,
            temp_root=temp_root,
            search_dirs=[iface_dir],
            expected_returncode=1,
        )
        shared_global_diag = require_reason(
            shared_global_check["stdout"], repo_arg(NEG_IMPORTED_SHARED_GLOBAL), "task_variable_ownership"
        )
        negative_results[NEG_IMPORTED_SHARED_GLOBAL.name] = {
            "check": compact_result(shared_global_check),
            "diagnostic": {
                "reason": shared_global_diag["reason"],
                "message": shared_global_diag["message"],
            },
        }

        imported_move_check = run_check(
            safec=safec,
            source=NEG_IMPORTED_INOUT_DOUBLE_MOVE,
            env=env,
            temp_root=temp_root,
            search_dirs=[iface_dir],
            expected_returncode=1,
        )
        imported_move_diag = require_reason(
            imported_move_check["stdout"], repo_arg(NEG_IMPORTED_INOUT_DOUBLE_MOVE), "double_move"
        )
        negative_results[NEG_IMPORTED_INOUT_DOUBLE_MOVE.name] = {
            "check": compact_result(imported_move_check),
            "diagnostic": {
                "reason": imported_move_diag["reason"],
                "message": imported_move_diag["message"],
            },
        }

        synthetic_results: dict[str, Any] = {}

        # Imported global ownership parity from emitted client MIR by cloning the task graph.
        global_base_mir = positive_results[CLIENT_GLOBAL_OK.name]["outputs"]["mir_payload"]
        synthetic_global = json.loads(json.dumps(global_base_mir))
        cloned = json.loads(json.dumps(synthetic_global["graphs"][0]))
        cloned["name"] = "Worker_2"
        synthetic_global["graphs"].append(cloned)
        synthetic_global_path = temp_root / "synthetic_imported_shared_global.mir.json"
        write_json(synthetic_global_path, synthetic_global)
        synthetic_global_analyze = run(
            [str(safec), "analyze-mir", "--diag-json", str(synthetic_global_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        synthetic_global_diag = require_reason(
            synthetic_global_analyze["stdout"],
            str(synthetic_global_path),
            "task_variable_ownership",
        )
        synthetic_results["imported_shared_global_parity"] = {
            "analyze_mir": compact_result(synthetic_global_analyze),
            "diagnostic": {
                "reason": synthetic_global_diag["reason"],
                "message": synthetic_global_diag["message"],
            },
        }

        # Imported in-out ownership parity from emitted MIR by duplicating the imported call.
        tmp_positive_dir = temp_root / "tmp_imported_inout"
        tmp_positive_dir.mkdir()
        tmp_client = tmp_positive_dir / "client.safe"
        tmp_client.write_text(
            "\n".join(
                [
                    "with Provider_Imported_Call_Ownership;",
                    "",
                    "package Tmp_Imported_Inout is",
                    "",
                    "   function Run is",
                    "      Owner : Provider_Imported_Call_Ownership.Payload_Ptr =",
                    "        new ((Value = 5) as Provider_Imported_Call_Ownership.Payload);",
                    "   begin",
                    "      Provider_Imported_Call_Ownership.Consume (Owner);",
                    "   end Run;",
                    "",
                    "end Tmp_Imported_Inout;",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        tmp_emit_root = client_out / "tmp_imported_inout"
        tmp_emit_root.mkdir()
        run_emit(
            safec=safec,
            source=tmp_client,
            out_dir=tmp_emit_root / "out",
            iface_dir=iface_dir,
            env=env,
            temp_root=temp_root,
            search_dirs=[iface_dir],
        )
        tmp_mir = load_json(tmp_emit_root / "out" / "client.mir.json")
        call_ops: list[dict[str, Any]] | None = None
        call_index: int | None = None
        if not tmp_mir["graphs"][0]["blocks"]:
            require(False, "tmp imported inout MIR must contain at least one block")
        for block in tmp_mir["graphs"][0]["blocks"]:
            for index, op in enumerate(block["ops"]):
                if op.get("kind") == "call":
                    call_ops = block["ops"]
                    call_index = index
                    break
            if call_ops:
                break
        require(call_ops is not None and call_index is not None, "tmp imported inout MIR must contain a call op")
        call_ops.append(json.loads(json.dumps(call_ops[call_index])))
        synthetic_move_path = temp_root / "synthetic_imported_double_move.mir.json"
        write_json(synthetic_move_path, tmp_mir)
        synthetic_move_analyze = run(
            [str(safec), "analyze-mir", "--diag-json", str(synthetic_move_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        synthetic_move_diag = require_reason(
            synthetic_move_analyze["stdout"],
            str(synthetic_move_path),
            imported_move_diag["reason"],
        )
        synthetic_results["imported_inout_parity"] = {
            "analyze_mir": compact_result(synthetic_move_analyze),
            "diagnostic": {
                "reason": synthetic_move_diag["reason"],
                "message": synthetic_move_diag["message"],
            },
        }

        # Determinism on one imported-summary provider/client pair.
        determinism_root = temp_root / "determinism"
        determinism_root.mkdir()
        first = determinism_root / "first"
        second = determinism_root / "second"
        first.mkdir()
        second.mkdir()
        first_iface = first / "iface"
        second_iface = second / "iface"
        first_iface.mkdir()
        second_iface.mkdir()
        first_emit = run_emit(
            safec=safec,
            source=CLIENT_CHANNEL_PROVIDER,
            out_dir=first / "out",
            iface_dir=first_iface,
            env=env,
            temp_root=temp_root,
            search_dirs=[iface_dir],
        )
        second_emit = run_emit(
            safec=safec,
            source=CLIENT_CHANNEL_PROVIDER,
            out_dir=second / "out",
            iface_dir=second_iface,
            env=env,
            temp_root=temp_root,
            search_dirs=[iface_dir],
        )
        determinism = {
            "emit_runs": {
                "first": compact_result(first_emit),
                "second": compact_result(second_emit),
            },
            "mir_equal": stable_emitted_artifact_sha256(
                first / "out" / "client_transitive_channel_provider_ceiling.mir.json",
                temp_root=temp_root,
            )
            == stable_emitted_artifact_sha256(
                second / "out" / "client_transitive_channel_provider_ceiling.mir.json",
                temp_root=temp_root,
            ),
            "safei_equal": stable_emitted_artifact_sha256(
                first_iface / "client_transitive_channel_provider_ceiling.safei.json",
                temp_root=temp_root,
            )
            == stable_emitted_artifact_sha256(
                second_iface / "client_transitive_channel_provider_ceiling.safei.json",
                temp_root=temp_root,
            ),
        }
        require(determinism["mir_equal"], "PR08.4 MIR determinism drifted")
        require(determinism["safei_equal"], "PR08.4 safei determinism drifted")

        return {
            "milestone": "PR08.4",
            "providers": provider_results,
            "positives": positive_results,
            "negatives": negative_results,
            "synthetic_parity": synthetic_results,
            "determinism": determinism,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    python = find_command("python3")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")

    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, python=python, env=env),
        label="PR08.4 transitive concurrency integration",
    )
    write_report(args.report, report)
    print(f"[pr084] wrote report to {display_path(args.report)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
