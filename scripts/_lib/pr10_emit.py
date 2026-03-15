"""Shared helpers for PR10 emitted-output GNATprove gates."""

from __future__ import annotations

import re
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from .harness_common import require, run
from .pr09_emit import (
    COMPILER_ROOT,
    REPO_ROOT,
    alr_command,
    compile_emitted_ada,
    ensure_emit_success,
    repo_arg,
    require_safec,
    run_emit,
    write_emitted_ada_project,
)


SELECTED_EMITTED_CORPUS: list[dict[str, Any]] = [
    {
        "fixture": "tests/positive/rule1_averaging.safe",
        "coverage": "rule1",
        "kind": "sequential",
        "feature": "Rule 1 wide arithmetic subset",
        "matrix_note": "Loop-carried wide arithmetic with an explicit narrowing return, plus validated narrowing before cross-subprogram parameter passing.",
        "source_fragments": [
            "function Average (Data : Readings) return Reading is",
            "for I in Sensor_Count loop",
            "Sum = Sum + Data (I);",
            "return Sum / 10;",
        ],
    },
    {
        "fixture": "tests/positive/rule2_binary_search_function.safe",
        "coverage": "rule2",
        "kind": "sequential",
        "feature": "Rule 2 function-return index-safety subset",
        "matrix_note": "Bounded-array binary search as a record-returning function with midpoint indexing and multiple early returns.",
        "source_fragments": [
            "function Search (Arr : Sorted_Array;",
            "type Search_Result is record",
            "Key : Element) return Search_Result is",
            "while Lo <= Hi loop",
            "Mid = Lo + (Hi - Lo) / 2;",
            "return ((Found = True, Found_At = Mid) as Search_Result);",
            "return ((Found = False, Found_At = Index.First) as Search_Result);",
        ],
    },
    {
        "fixture": "tests/positive/rule3_divide.safe",
        "coverage": "rule3",
        "kind": "sequential",
        "feature": "Rule 3 division-safety subset",
        "matrix_note": "Typed nonzero divisor plus guarded variable-divisor division.",
        "source_fragments": [
            "type Positive_Divisor is range 1 .. 1000;",
            "return Dividend / Result_Value (Divisor);",
            "if B != 0 then",
            "return A / B;",
        ],
    },
    {
        "fixture": "tests/positive/rule1_parameter.safe",
        "coverage": "rule1",
        "kind": "sequential",
        "feature": "Rule 1 wide arithmetic subset",
        "matrix_note": "Loop-carried wide arithmetic with an explicit narrowing return, plus validated narrowing before cross-subprogram parameter passing.",
        "source_fragments": [
            "procedure Apply_Percentage (P : Percentage; Base : Wide_Int;",
            "Result = Wide_Int ((Wide_Int (Base) * Wide_Int (P)) / 100);",
            "Pct = Percentage (Raw);",
            "Apply_Percentage (Pct, 5000, Output);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_move.safe",
        "coverage": "ownership",
        "kind": "sequential",
        "feature": "Sequential ownership move subset",
        "matrix_note": "Single-owner move with post-move nulling and target-only dereference.",
        "source_fragments": [
            "Source : Payload_Ptr = new ((Value = 42) as Payload);",
            "Target : Payload_Ptr = null;",
            "Target = Source;",
            "Target.all.Value = 100;",
        ],
    },
    {
        "fixture": "tests/positive/rule4_linked_list_sum.safe",
        "coverage": "rule4",
        "kind": "sequential",
        "feature": "Rule 4 observer-traversal subset",
        "matrix_note": "Null-guarded linked-list prefix accumulation with dereference plus bounded count and total arithmetic.",
        "source_fragments": [
            "function Summarize_Prefix (Head : Node_Ptr) return Total_Value is",
            "Count = Count + 1;",
            "Total = Total + Total_Value (Head.all.Value);",
            "Second : access constant Node = Head.all.Next.Access;",
            "Total = Total + Total_Value (Second.all.Value);",
        ],
    },
    {
        "fixture": "tests/positive/rule5_vector_normalize.safe",
        "coverage": "rule5",
        "kind": "sequential",
        "feature": "Rule 5 computed-divisor vector subset",
        "matrix_note": "Three-field floating-point record computation with a branch-computed positive divisor derived from all components and a returned normalized component.",
        "source_fragments": [
            "type Vector3 is record",
            "type Component is digits 6 range 0.0 .. 100.0;",
            "type Positive_Count is range 1 .. 4;",
            "function Normalize_X (Input : Vector3) return Float is",
            "if Input.X > 0.0 then",
            "if Input.Y > 0.0 then",
            "if Input.Z > 0.0 then",
            "return Float (Input.X) / Float (Divisor);",
        ],
    },
    {
        "fixture": "tests/positive/channel_pingpong.safe",
        "coverage": "concurrency",
        "kind": "concurrency",
        "feature": "Concurrency ping-pong subset",
        "matrix_note": "Two priority-bearing tasks exchanging bounded channel messages in both directions.",
        "source_fragments": [
            "task Ping_Task with Priority = 10 is",
            "task Pong_Task with Priority = 10 is",
            "send Ping_Ch, 7;",
            "receive Pong_Ch, Reply;",
        ],
    },
    {
        "fixture": "tests/positive/channel_pipeline_compute.safe",
        "coverage": "concurrency",
        "kind": "concurrency",
        "feature": "Concurrency pipeline compute subset",
        "matrix_note": "Three-task channel pipeline with arithmetic in the filter and consumer task bodies.",
        "source_fragments": [
            "task Producer with Priority = 10 is",
            "Seed : Sample = 8;",
            "task Filter with Priority = 10 is",
            "task Consumer with Priority = 10 is",
            "Output = Input / 2 + 1;",
            "Adjusted = Running_Total (Running_Total (Data) + 1);",
        ],
    },
    {
        "fixture": "tests/concurrency/select_with_delay.safe",
        "coverage": "concurrency",
        "kind": "concurrency",
        "feature": "Select-with-delay emitted polling subset",
        "matrix_note": "One receive arm plus one delay arm proved through the emitted polling-based lowering, not source-level blocking fairness or timing semantics.",
        "source_fragments": [
            "select",
            "when Item : Message from Msg_Ch then",
            "delay 0.05 then",
        ],
    },
]

EXPECTED_COVERAGE = {
    "rule1",
    "rule2",
    "rule3",
    "rule4",
    "rule5",
    "ownership",
    "concurrency",
}

FLOW_SWITCHES = [
    "--mode=flow",
    "--report=all",
    "--warnings=error",
]

PROVE_SWITCHES = [
    "--mode=prove",
    "--level=2",
    "--prover=cvc5,z3,altergo",
    "--steps=0",
    "--timeout=120",
    "--report=all",
    "--warnings=error",
    "--checks-as-errors=on",
]


def selected_emitted_corpus() -> list[dict[str, Any]]:
    return [dict(item) for item in SELECTED_EMITTED_CORPUS]


def corpus_paths() -> list[Path]:
    return [REPO_ROOT / item["fixture"] for item in SELECTED_EMITTED_CORPUS]


def normalize_source_text(text: str) -> str:
    return " ".join(text.split())


def normalized_source_fragments(item: dict[str, Any]) -> Sequence[str]:
    return tuple(normalize_source_text(fragment) for fragment in item["source_fragments"])


def emit_selected_fixture(
    *,
    source: Path,
    root: Path,
    env: dict[str, str],
) -> dict[str, Path]:
    safec = require_safec()
    out_dir = root / "out"
    iface_dir = root / "iface"
    ada_dir = root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)
    run_emit(
        safec=safec,
        source=source,
        out_dir=out_dir,
        iface_dir=iface_dir,
        ada_dir=ada_dir,
        env=env,
        temp_root=root,
    )
    ensure_emit_success(source=source, root=root)
    return {
        "out_dir": out_dir,
        "iface_dir": iface_dir,
        "ada_dir": ada_dir,
    }


def gnatprove_command(
    *,
    gpr_path: Path,
    ada_dir: Path,
    mode: str,
) -> list[str]:
    switches = FLOW_SWITCHES if mode == "flow" else PROVE_SWITCHES
    argv = [
        alr_command(),
        "exec",
        "--",
        "gnatprove",
        "-P",
        str(gpr_path),
        *switches,
    ]
    if (ada_dir / "gnat.adc").exists():
        # gnatprove does not honor the project Compiler switches for -gnatec.
        argv.extend(["-cargs", f"-gnatec={ada_dir / 'gnat.adc'}"])
    return argv


def parse_summary_cell(cell: str) -> dict[str, Any]:
    stripped = cell.strip()
    if stripped == ".":
        return {"count": 0, "detail": ""}
    match = re.match(r"^(?P<count>\d+)(?: \((?P<detail>.*)\))?$", stripped)
    require(match is not None, f"unexpected GNATprove summary cell: {cell!r}")
    return {
        "count": int(match.group("count")),
        "detail": match.group("detail") or "",
    }


def parse_gnatprove_summary(text: str) -> dict[str, Any]:
    lines = text.splitlines()
    header_index = None
    for index, line in enumerate(lines):
        if line.strip().startswith("SPARK Analysis results"):
            header_index = index
            break
    require(header_index is not None, "missing GNATprove summary table")

    rows: dict[str, dict[str, dict[str, Any]]] = {}
    for line in lines[header_index + 2 :]:
        stripped = line.strip()
        if not stripped:
            continue
        if set(stripped) == {"-"}:
            continue
        parts = re.split(r"\s{2,}", stripped)
        if len(parts) != 6:
            continue
        label, total, flow, provers, justified, unproved = parts
        rows[label] = {
            "total": parse_summary_cell(total),
            "flow": parse_summary_cell(flow),
            "provers": parse_summary_cell(provers),
            "justified": parse_summary_cell(justified),
            "unproved": parse_summary_cell(unproved),
        }

    require("Total" in rows, "GNATprove summary missing Total row")
    return {
        "rows": rows,
        "total": rows["Total"],
    }


def gnatprove_emitted_ada(
    *,
    ada_dir: Path,
    env: dict[str, str],
    temp_root: Path,
    mode: str,
) -> dict[str, Any]:
    require(mode in {"flow", "prove"}, f"unsupported GNATprove mode: {mode}")
    gpr_path = write_emitted_ada_project(ada_dir)
    result = run(
        gnatprove_command(gpr_path=gpr_path, ada_dir=ada_dir, mode=mode),
        cwd=COMPILER_ROOT,
        env=env,
        temp_root=temp_root,
    )
    summary_path = ada_dir / "obj" / "gnatprove" / "gnatprove.out"
    require(summary_path.exists(), f"missing GNATprove summary: {summary_path}")
    summary = parse_gnatprove_summary(summary_path.read_text(encoding="utf-8"))
    return {
        "command": result["command"],
        "cwd": result["cwd"],
        "returncode": result["returncode"],
        "summary": summary,
    }


def compile_and_prove_fixture(
    *,
    source: Path,
    root: Path,
    env: dict[str, str],
    mode: str,
) -> dict[str, Any]:
    outputs = emit_selected_fixture(source=source, root=root, env=env)
    compile_result = compile_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=root,
    )
    proof_result = gnatprove_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=root,
        mode=mode,
    )
    if mode == "prove":
        require(
            proof_result["summary"]["total"]["justified"]["count"] == 0,
            f"{repo_arg(source)}: prove summary contains justified checks",
        )
        require(
            proof_result["summary"]["total"]["unproved"]["count"] == 0,
            f"{repo_arg(source)}: prove summary contains unproved checks",
        )
    return {
        "fixture": repo_arg(source),
        "compile": compile_result,
        mode: proof_result,
    }
