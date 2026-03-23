#!/usr/bin/env python3
"""Run the PR08.1 local concurrency frontend gate."""

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
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr081-local-concurrency-frontend-report.json"
)
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"
DEFAULT_TASK_PRIORITY = 31

POSITIVE_EMIT_CASES = [
    REPO_ROOT / "tests" / "positive" / "channel_pingpong.safe",
    REPO_ROOT / "tests" / "positive" / "channel_pipeline.safe",
    REPO_ROOT / "tests" / "concurrency" / "multi_task_channel.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_delay_local_scope.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_priority.safe",
    REPO_ROOT / "tests" / "concurrency" / "task_priority_delay.safe",
    REPO_ROOT / "tests" / "concurrency" / "try_ops.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
]

NEGATIVE_CASES = [
    REPO_ROOT / "tests" / "negative" / "neg_public_task.safe",
    REPO_ROOT / "tests" / "negative" / "neg_task_end_mismatch.safe",
    REPO_ROOT / "tests" / "negative" / "neg_task_priority_range.safe",
    REPO_ROOT / "tests" / "negative" / "neg_chan_zero_cap.safe",
    REPO_ROOT / "tests" / "negative" / "neg_channel_indefinite.safe",
    REPO_ROOT / "tests" / "concurrency" / "channel_access_type.safe",
    REPO_ROOT / "tests" / "negative" / "neg_channel_access_component.safe",
    REPO_ROOT / "tests" / "negative" / "neg_select_no_channel_arm.safe",
    REPO_ROOT / "tests" / "negative" / "neg_select_multiple_delay.safe",
    REPO_ROOT / "tests" / "negative" / "neg_try_send_success_not_boolean.safe",
    REPO_ROOT / "tests" / "negative" / "neg_try_receive_success_not_boolean.safe",
    REPO_ROOT / "tests" / "negative" / "neg_task_return.safe",
    REPO_ROOT / "tests" / "negative" / "neg_task_outer_exit.safe",
    REPO_ROOT / "tests" / "negative" / "neg_delay_until.safe",
    REPO_ROOT / "tests" / "negative" / "neg_statement_label_assignment.safe",
    REPO_ROOT / "tests" / "negative" / "neg_qualified_channel_reference.safe",
]

DETERMINISTIC_EMIT_CASES = [
    REPO_ROOT / "tests" / "positive" / "channel_pingpong.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
]

VALID_MIR_FIXTURES = [
    COMPILER_ROOT / "tests" / "mir_validation" / "valid_mir_v2_concurrency.json",
]

INVALID_MIR_FIXTURES = [
    {
        "path": COMPILER_ROOT / "tests" / "mir_validation" / "invalid_select_multiple_delay_arms.json",
        "expected_error": "select terminator may have at most one delay arm",
    },
]

ANALYSIS_REGRESSION_CASES = [
    {
        "name": "send_division_by_zero.safe",
        "text": (
            "package Send_Division_By_Zero is\n"
            "\n"
            "   type Message is range 0 to 100;\n"
            "\n"
            "   channel Data_Ch : Message capacity 1;\n"
            "\n"
            "   task Producer is\n"
            "   begin\n"
            "      loop\n"
            "         send Data_Ch, 10 / 0;\n"
            "      end loop;\n"
            "   end Producer;\n"
            "\n"
            "end Send_Division_By_Zero;\n"
        ),
        "expected_reason": "division_by_zero",
        "expected_message": "divisor not provably nonzero",
    },
    {
        "name": "select_arm_division_by_zero.safe",
        "text": (
            "package Select_Arm_Division_By_Zero is\n"
            "\n"
            "   type Message is range 0 to 100;\n"
            "\n"
            "   channel Data_Ch : Message capacity 1;\n"
            "\n"
            "   task Worker is\n"
            "      Value : Message;\n"
            "   begin\n"
            "      loop\n"
            "         select\n"
            "            when Item : Message from Data_Ch then\n"
            "               Value = 10 / 0;\n"
            "         or\n"
            "            delay 1.0 then\n"
            "               Value = 0;\n"
            "         end select;\n"
            "      end loop;\n"
            "   end Worker;\n"
            "\n"
            "end Select_Arm_Division_By_Zero;\n"
        ),
        "expected_reason": "division_by_zero",
        "expected_message": "divisor not provably nonzero",
    },
    {
        "name": "select_delay_division_by_zero.safe",
        "text": (
            "package Select_Delay_Division_By_Zero is\n"
            "\n"
            "   type Message is range 0 to 100;\n"
            "\n"
            "   channel Data_Ch : Message capacity 1;\n"
            "\n"
            "   task Worker is\n"
            "   begin\n"
            "      loop\n"
            "         select\n"
            "            when Item : Message from Data_Ch then\n"
            "               null;\n"
            "         or\n"
            "            delay 1.0 / 0.0 then\n"
            "               null;\n"
            "         end select;\n"
            "      end loop;\n"
            "   end Worker;\n"
            "\n"
            "end Select_Delay_Division_By_Zero;\n"
        ),
        "expected_reason": "fp_division_by_zero",
        "expected_message": "floating divisor is not provably nonzero",
    },
]

DELAY_ARM_SCOPE_CASE = REPO_ROOT / "tests" / "concurrency" / "select_delay_local_scope.safe"


def repo_arg(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def first_diag(payload: dict[str, Any], label: str) -> dict[str, Any]:
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{label}: expected at least one diagnostic")
    return diagnostics[0]


def first_stderr_line(result: dict[str, Any], label: str) -> str:
    lines = result["stderr"].splitlines()
    require(lines, f"{label}: expected stderr output")
    return lines[0]


def ensure_no_internal_failure(result: dict[str, Any], label: str) -> None:
    combined = f"{result['stdout']}\n{result['stderr']}".lower()
    require("internal error" not in combined, f"{label}: unexpected internal error wording")
    require("internal failure" not in combined, f"{label}: unexpected internal failure wording")


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        "ast": root / "out" / f"{stem}.ast.json",
        "typed": root / "out" / f"{stem}.typed.json",
        "mir": root / "out" / f"{stem}.mir.json",
        "safei": root / "iface" / f"{stem}.safei.json",
    }


def observed_artifacts(directory: Path) -> list[str]:
    if not directory.exists():
        return []
    return sorted(str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file())


def ensure_no_emit_artifacts(out_dir: Path, iface_dir: Path, label: str) -> dict[str, list[str]]:
    out_files = observed_artifacts(out_dir)
    iface_files = observed_artifacts(iface_dir)
    require(not out_files, f"{label}: emit unexpectedly wrote output artifacts {out_files}")
    require(not iface_files, f"{label}: emit unexpectedly wrote interface artifacts {iface_files}")
    return {"out_files": out_files, "iface_files": iface_files}


def graph_by_name(mir_payload: dict[str, Any], name: str) -> dict[str, Any]:
    for graph in mir_payload["graphs"]:
        if graph["name"] == name:
            return graph
    raise RuntimeError(f"missing graph {name!r}")


def task_graphs(mir_payload: dict[str, Any]) -> list[dict[str, Any]]:
    return [graph for graph in mir_payload["graphs"] if graph["kind"] == "task"]


def all_op_kinds(mir_payload: dict[str, Any]) -> list[str]:
    result: list[str] = []
    for graph in mir_payload["graphs"]:
        for block in graph["blocks"]:
            for op in block["ops"]:
                result.append(op["kind"])
    return result


def select_terminators(mir_payload: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for graph in mir_payload["graphs"]:
        for block in graph["blocks"]:
            terminator = block["terminator"]
            if terminator["kind"] == "select":
                result.append(terminator)
    return result


def op_kinds_for_block(block: dict[str, Any]) -> set[str]:
    return {op["kind"] for op in block["ops"]}


def inspect_emitted_payloads(
    *,
    sample: Path,
    typed_payload: dict[str, Any],
    mir_payload: dict[str, Any],
    safei_payload: dict[str, Any],
) -> dict[str, Any]:
    typed_channels = typed_payload.get("channels", [])
    typed_tasks = typed_payload.get("tasks", [])
    mir_channels = mir_payload.get("channels", [])
    mir_task_graphs = task_graphs(mir_payload)

    require(
        len(typed_channels) == len(mir_channels),
        f"{sample.name}: typed/mir channel count drifted",
    )
    require(
        len(typed_tasks) == len(mir_task_graphs),
        f"{sample.name}: typed tasks and task graphs drifted",
    )
    require(
        len(safei_payload["executables"]) == len(typed_tasks),
        f"{sample.name}: safei executable count drifted from typed tasks",
    )

    for graph in mir_task_graphs:
        require(isinstance(graph.get("priority"), int), f"{sample.name}: task graph missing priority")
        require(graph.get("return_type") is None, f"{sample.name}: task graph must not carry return_type")
        if graph.get("has_explicit_priority") is False:
            require(
                graph["priority"] == DEFAULT_TASK_PRIORITY,
                f"{sample.name}: default task priority drifted",
            )
        for block in graph["blocks"]:
            require(
                block["terminator"]["kind"] != "return",
                f"{sample.name}: task graph must not contain a return terminator",
            )

    checks: dict[str, Any] = {
        "typed_channels": len(typed_channels),
        "typed_tasks": len(typed_tasks),
        "task_graphs": [graph["name"] for graph in mir_task_graphs],
        "op_kinds": sorted(set(all_op_kinds(mir_payload))),
        "select_terminators": len(select_terminators(mir_payload)),
    }

    if sample.name == "task_priority_delay.safe":
        worker = graph_by_name(mir_payload, "Worker")
        require(worker["priority"] == 5, "task_priority_delay.safe: explicit priority drifted")
        require(worker["has_explicit_priority"] is True, "task_priority_delay.safe: expected explicit priority")
        require("delay" in all_op_kinds(mir_payload), "task_priority_delay.safe: missing delay op")
        checks["worker"] = {
            "priority": worker["priority"],
            "has_explicit_priority": worker["has_explicit_priority"],
        }
    elif sample.name == "try_ops.safe":
        op_kinds = set(all_op_kinds(mir_payload))
        require("channel_try_send" in op_kinds, "try_ops.safe: missing channel_try_send op")
        require("channel_try_receive" in op_kinds, "try_ops.safe: missing channel_try_receive op")
    elif sample.name == "select_priority.safe":
        terminators = select_terminators(mir_payload)
        require(terminators, "select_priority.safe: missing select terminator")
        require(
            all(sum(1 for arm in term["arms"] if arm["kind"] == "delay") == 0 for term in terminators),
            "select_priority.safe: unexpected delay arm",
        )
    elif sample.name == "select_with_delay.safe":
        terminators = select_terminators(mir_payload)
        require(terminators, "select_with_delay.safe: missing select terminator")
        require(
            any(sum(1 for arm in term["arms"] if arm["kind"] == "delay") == 1 for term in terminators),
            "select_with_delay.safe: missing delay arm",
        )
    elif sample.name == "select_delay_local_scope.safe":
        worker = graph_by_name(mir_payload, "Worker")
        delay_blocks = [block for block in worker["blocks"] if block["role"] == "select_delay_arm"]
        require(delay_blocks, "select_delay_local_scope.safe: missing select_delay_arm block")
        require(
            any("scope_enter" in op_kinds_for_block(block) for block in delay_blocks),
            "select_delay_local_scope.safe: missing delay-arm scope_enter",
        )
        require(
            any("scope_exit" in op_kinds_for_block(block) for block in delay_blocks),
            "select_delay_local_scope.safe: missing delay-arm scope_exit",
        )

    return checks


def validate_positive_emit_case(
    *,
    safec: Path,
    python: str,
    sample: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    root = temp_root / sample.stem.lower()
    (root / "out").mkdir(parents=True, exist_ok=True)
    (root / "iface").mkdir(parents=True, exist_ok=True)

    ast_result = run([str(safec), "ast", repo_arg(sample)], cwd=REPO_ROOT, env=env, temp_root=temp_root)
    ast_stdout_path = root / f"{sample.stem.lower()}.ast.stdout.json"
    ast_stdout_path.write_text(ast_result["stdout"], encoding="utf-8")
    ast_stdout_validate = run(
        [python, str(AST_VALIDATOR), str(ast_stdout_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )

    emit_result = run(
        [
            str(safec),
            "emit",
            repo_arg(sample),
            "--out-dir",
            str(root / "out"),
            "--interface-dir",
            str(root / "iface"),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    paths = emitted_paths(root, sample)

    ast_validate = run([python, str(AST_VALIDATOR), str(paths["ast"])], cwd=REPO_ROOT, env=env, temp_root=temp_root)
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
            repo_arg(sample),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    mir_validate = run(
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
    require(
        analyze_payload["diagnostics"] == [],
        f"{sample.name}: expected emitted MIR to be diagnostic-free",
    )

    ast_payload = load_json(paths["ast"])
    ast_stdout_payload = load_json(ast_stdout_path)
    require(ast_payload == ast_stdout_payload, f"{sample.name}: ast stdout drifted from emitted AST")

    typed_payload = load_json(paths["typed"])
    mir_payload = load_json(paths["mir"])
    safei_payload = load_json(paths["safei"])

    checks = inspect_emitted_payloads(
        sample=sample,
        typed_payload=typed_payload,
        mir_payload=mir_payload,
        safei_payload=safei_payload,
    )

    return {
        "sample": repo_arg(sample),
        "ast": ast_result,
        "ast_stdout_validate": ast_stdout_validate,
        "emit": emit_result,
        "ast_validate": ast_validate,
        "output_validate": output_validate,
        "mir_validate": mir_validate,
        "analyze_mir": analyze_result,
        "checks": checks,
    }


def validate_negative_case(
    *,
    safec: Path,
    sample: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    source_rel = repo_arg(sample)
    expected_reason = read_expected_reason(sample)

    diag_json = run(
        [str(safec), "check", "--diag-json", source_rel],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(diag_json["stdout"], source_rel)
    diag = first_diag(payload, sample.name)
    require(diag["reason"] == expected_reason, f"{sample.name}: wrong reason")
    require(diag["path"] == source_rel, f"{sample.name}: diagnostics path drifted")

    check_human = run(
        [str(safec), "check", source_rel],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    ast_human = run(
        [str(safec), "ast", source_rel],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )

    out_dir = temp_root / (sample.stem + "-out")
    iface_dir = temp_root / (sample.stem + "-iface")
    emit_human = run(
        [
            str(safec),
            "emit",
            source_rel,
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )

    for label, result in (
        (sample.name + " check", check_human),
        (sample.name + " ast", ast_human),
        (sample.name + " emit", emit_human),
    ):
        ensure_no_internal_failure(result, label)

    check_header = first_stderr_line(check_human, sample.name + " check")
    require(check_header.startswith(sample.name + ":"), f"{sample.name}: check header drifted")
    require(
        first_stderr_line(ast_human, sample.name + " ast") == check_header,
        f"{sample.name}: ast first stderr line drifted",
    )
    require(
        first_stderr_line(emit_human, sample.name + " emit") == check_header,
        f"{sample.name}: emit first stderr line drifted",
    )

    artifacts = ensure_no_emit_artifacts(out_dir, iface_dir, sample.name)

    return {
        "sample": source_rel,
        "expected_reason": expected_reason,
        "first_diagnostic": {
            "reason": diag["reason"],
            "message": diag["message"],
            "path": diag["path"],
            "span": diag["span"],
            "highlight_span": diag.get("highlight_span"),
        },
        "check_diag_json": diag_json,
        "check": check_human,
        "ast": ast_human,
        "emit": emit_human,
        "emit_artifacts": artifacts,
    }


def validate_analysis_regression_case(
    *,
    safec: Path,
    sample: dict[str, str],
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    source = temp_root / sample["name"]
    source.write_text(sample["text"], encoding="utf-8")

    ast_result = run([str(safec), "ast", str(source)], cwd=REPO_ROOT, env=env, temp_root=temp_root)
    check_diag_json = run(
        [str(safec), "check", "--diag-json", str(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(check_diag_json["stdout"], sample["name"])
    diag = first_diag(payload, sample["name"])
    require(diag["reason"] == sample["expected_reason"], f"{sample['name']}: wrong reason")
    require(diag["message"] == sample["expected_message"], f"{sample['name']}: wrong message")
    require(
        diag["path"] == normalize_text(str(source), temp_root=temp_root),
        f"{sample['name']}: diagnostics path drifted",
    )

    check_human = run(
        [str(safec), "check", str(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )

    out_dir = temp_root / (source.stem + "-out")
    iface_dir = temp_root / (source.stem + "-iface")
    emit_human = run(
        [
            str(safec),
            "emit",
            str(source),
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )

    for label, result in (
        (sample["name"] + " ast", ast_result),
        (sample["name"] + " check", check_human),
        (sample["name"] + " emit", emit_human),
    ):
        ensure_no_internal_failure(result, label)

    check_header = first_stderr_line(check_human, sample["name"] + " check")
    require(
        first_stderr_line(emit_human, sample["name"] + " emit") == check_header,
        f"{sample['name']}: emit first stderr line drifted",
    )

    artifacts = ensure_no_emit_artifacts(out_dir, iface_dir, sample["name"])

    return {
        "sample": "$TMPDIR/" + sample["name"],
        "expected_reason": sample["expected_reason"],
        "first_diagnostic": {
            "reason": diag["reason"],
            "message": diag["message"],
            "path": diag["path"],
            "span": diag["span"],
            "highlight_span": diag.get("highlight_span"),
        },
        "ast": ast_result,
        "check_diag_json": check_diag_json,
        "check": check_human,
        "emit": emit_human,
        "emit_artifacts": artifacts,
    }


def validate_delay_arm_scope_case(
    *,
    safec: Path,
    python: str,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    source = DELAY_ARM_SCOPE_CASE
    root = temp_root / source.stem.lower()
    (root / "out").mkdir(parents=True, exist_ok=True)
    (root / "iface").mkdir(parents=True, exist_ok=True)

    ast_result = run([str(safec), "ast", repo_arg(source)], cwd=REPO_ROOT, env=env, temp_root=temp_root)
    ast_stdout_path = root / f"{source.stem.lower()}.ast.stdout.json"
    ast_stdout_path.write_text(ast_result["stdout"], encoding="utf-8")
    ast_stdout_validate = run(
        [python, str(AST_VALIDATOR), str(ast_stdout_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )

    emit_result = run(
        [
            str(safec),
            "emit",
            repo_arg(source),
            "--out-dir",
            str(root / "out"),
            "--interface-dir",
            str(root / "iface"),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    paths = emitted_paths(root, source)

    ast_validate = run([python, str(AST_VALIDATOR), str(paths["ast"])], cwd=REPO_ROOT, env=env, temp_root=temp_root)
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
    mir_validate = run(
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
    require(
        analyze_payload["diagnostics"] == [],
        f"{source.name}: expected emitted MIR to be diagnostic-free",
    )

    mir_payload = load_json(paths["mir"])
    worker = graph_by_name(mir_payload, "Worker")
    delay_blocks = [block for block in worker["blocks"] if block["role"] == "select_delay_arm"]
    require(delay_blocks, f"{source.name}: missing select_delay_arm block")
    require(
        any("scope_enter" in op_kinds_for_block(block) for block in delay_blocks),
        f"{source.name}: missing delay-arm scope_enter",
    )
    require(
        any("scope_exit" in op_kinds_for_block(block) for block in delay_blocks),
        f"{source.name}: missing delay-arm scope_exit",
    )

    return {
        "sample": repo_arg(source),
        "ast": ast_result,
        "ast_stdout_validate": ast_stdout_validate,
        "emit": emit_result,
        "ast_validate": ast_validate,
        "output_validate": output_validate,
        "mir_validate": mir_validate,
        "analyze_mir": analyze_result,
        "checks": {
            "delay_arm_roles": [block["role"] for block in delay_blocks],
            "delay_arm_scope_ids": sorted({block["active_scope_id"] for block in delay_blocks}),
            "delay_arm_op_kinds": sorted(
                {kind for block in delay_blocks for kind in op_kinds_for_block(block)}
            ),
        },
    }


def run_deterministic_emit(
    *,
    safec: Path,
    sample: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    hashes: list[dict[str, str]] = []
    for run_index in (1, 2):
        root = temp_root / f"{sample.stem.lower()}-{run_index}"
        (root / "out").mkdir(parents=True, exist_ok=True)
        (root / "iface").mkdir(parents=True, exist_ok=True)
        run(
            [
                str(safec),
                "emit",
                repo_arg(sample),
                "--out-dir",
                str(root / "out"),
                "--interface-dir",
                str(root / "iface"),
            ],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        paths = emitted_paths(root, sample)
        hashes.append(
            {
                name: stable_emitted_artifact_sha256(path, temp_root=temp_root)
                for name, path in paths.items()
            }
        )

    require(hashes[0] == hashes[1], f"{sample.name}: repeated emit drifted")
    return {"sample": repo_arg(sample), "hashes": hashes[0]}


def validate_mir_fixtures(*, safec: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    valid_results: list[dict[str, Any]] = []
    invalid_results: list[dict[str, Any]] = []

    for fixture in VALID_MIR_FIXTURES:
        valid_results.append(
            {
                "fixture": repo_arg(fixture),
                "result": run([str(safec), "validate-mir", str(fixture)], cwd=REPO_ROOT, env=env, temp_root=temp_root),
            }
        )

    for case in INVALID_MIR_FIXTURES:
        result = run(
            [str(safec), "validate-mir", str(case["path"])],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        require(
            case["expected_error"] in result["stderr"],
            f"{case['path'].name}: expected stderr to contain {case['expected_error']!r}",
        )
        invalid_results.append(
            {
                "fixture": repo_arg(case["path"]),
                "expected_error": case["expected_error"],
                "result": result,
            }
        )

    return {"valid": valid_results, "invalid": invalid_results}


def build_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr081-local-concurrency-") as temp_root_str:
        temp_root = Path(temp_root_str)
        return {
            "task": "PR08.1",
            "status": "ok",
            "positive_emit_cases": [
                validate_positive_emit_case(
                    safec=safec,
                    python=python,
                    sample=sample,
                    env=env,
                    temp_root=temp_root,
                )
                for sample in POSITIVE_EMIT_CASES
            ],
            "negative_legality_cases": [
                validate_negative_case(safec=safec, sample=sample, env=env, temp_root=temp_root)
                for sample in NEGATIVE_CASES
            ],
            "analysis_regression_cases": [
                validate_analysis_regression_case(
                    safec=safec,
                    sample=sample,
                    env=env,
                    temp_root=temp_root,
                )
                for sample in ANALYSIS_REGRESSION_CASES
            ],
            "delay_arm_scope_case": validate_delay_arm_scope_case(
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            ),
            "deterministic_emit": [
                run_deterministic_emit(safec=safec, sample=sample, env=env, temp_root=temp_root)
                for sample in DETERMINISTIC_EMIT_CASES
            ],
            "mir_validation_fixtures": validate_mir_fixtures(safec=safec, env=env, temp_root=temp_root),
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
        label="PR08.1 local concurrency frontend",
    )
    write_report(args.report, report)

    print(f"pr08.1 local concurrency frontend: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
