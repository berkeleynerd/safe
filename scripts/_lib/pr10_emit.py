"""Shared helpers for PR10 emitted-output GNATprove gates."""

from __future__ import annotations

import re
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


SELECTED_EMITTED_CORPUS: list[dict[str, str]] = [
    {
        "fixture": "tests/positive/rule1_averaging.safe",
        "coverage": "rule1",
        "kind": "sequential",
    },
    {
        "fixture": "tests/positive/rule2_binary_search.safe",
        "coverage": "rule2",
        "kind": "sequential",
    },
    {
        "fixture": "tests/positive/rule3_average.safe",
        "coverage": "rule3",
        "kind": "sequential",
    },
    {
        "fixture": "tests/positive/rule1_parameter.safe",
        "coverage": "rule1",
        "kind": "sequential",
    },
    {
        "fixture": "tests/positive/ownership_move.safe",
        "coverage": "ownership",
        "kind": "sequential",
    },
    {
        "fixture": "tests/positive/rule4_linked_list.safe",
        "coverage": "rule4",
        "kind": "sequential",
    },
    {
        "fixture": "tests/positive/rule5_normalize.safe",
        "coverage": "rule5",
        "kind": "sequential",
    },
    {
        "fixture": "tests/positive/channel_pingpong.safe",
        "coverage": "concurrency",
        "kind": "concurrency",
    },
    {
        "fixture": "tests/positive/channel_pipeline.safe",
        "coverage": "concurrency",
        "kind": "concurrency",
    },
    {
        "fixture": "tests/concurrency/select_with_delay.safe",
        "coverage": "concurrency",
        "kind": "concurrency",
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


def selected_emitted_corpus() -> list[dict[str, str]]:
    return [dict(item) for item in SELECTED_EMITTED_CORPUS]


def corpus_paths() -> list[Path]:
    return [REPO_ROOT / item["fixture"] for item in SELECTED_EMITTED_CORPUS]


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
