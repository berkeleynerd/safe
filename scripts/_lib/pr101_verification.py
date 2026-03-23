"""Shared helpers for PR101 companion/template verification reports."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

from .harness_common import compact_result, find_command, require, run, sha256_file
from .pr09_emit import REPO_ROOT, alr_command
from .proof_report import PR101_ANCHOR_KEYS, build_three_way_report, split_command_result


def normalized_assumptions_hash(path: Path) -> str:
    from .harness_common import sha256_text

    text = path.read_text(encoding="utf-8")
    normalized = re.sub(r"^# Generated: .*\n", "", text, flags=re.MULTILINE)
    return sha256_text(normalized)


def normalized_gnatprove_summary_hash(path: Path) -> str:
    from .harness_common import display_path, sha256_text

    text = path.read_text(encoding="utf-8")
    match = re.search(r"^Summary of SPARK.*?^Total.*$", text, flags=re.MULTILINE | re.DOTALL)
    require(match is not None, f"{display_path(path, repo_root=REPO_ROOT)}: missing GNATprove summary block")
    normalized = re.sub(r"\([^)]*\)", "(normalized)", match.group(0))
    return sha256_text(normalized)


def snapshot_text(path: Path) -> str | None:
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8")


def restore_text(path: Path, contents: str | None) -> None:
    if contents is None:
        if path.exists():
            path.unlink()
        return
    path.write_text(contents, encoding="utf-8")


def _run_verification(
    *,
    env: dict[str, str],
    root: Path,
    project: str,
    extract_prove_out: str | None = None,
    diff_prove_golden: str | None = None,
    diff_prove_out: str | None = None,
) -> dict[str, Any]:
    bash = find_command("bash")
    alr = alr_command()
    gnatprove = find_command("gnatprove", Path.home() / ".alire" / "bin" / "gnatprove")
    tool_env = env.copy()
    if gnatprove != "gnatprove":
        alire_bin = str(Path(gnatprove).parent)
        current_path = tool_env.get("PATH", "")
        tool_env["PATH"] = alire_bin if not current_path else alire_bin + os.pathsep + current_path
    assumptions_path = REPO_ROOT / "companion" / "assumptions_extracted.txt"
    original_assumptions = snapshot_text(assumptions_path)
    build = run([alr, "build"], cwd=root, env=tool_env)
    flow = run(
        [alr, "exec", "--", "gnatprove", "-P", project, "--mode=flow", "--report=all", "--warnings=error"],
        cwd=root,
        env=tool_env,
    )
    prove = run(
        [
            alr,
            "exec",
            "--",
            "gnatprove",
            "-P",
            project,
            "--mode=prove",
            "--level=2",
            "--prover=cvc5,z3,altergo",
            "--steps=0",
            "--timeout=120",
            "--report=all",
            "--warnings=error",
            "--checks-as-errors=on",
        ],
        cwd=root,
        env=tool_env,
    )
    extract_env = tool_env.copy()
    if extract_prove_out is not None:
        extract_env["PROVE_OUT"] = extract_prove_out
    diff_env = tool_env.copy()
    if diff_prove_golden is not None:
        diff_env["PROVE_GOLDEN"] = diff_prove_golden
    if diff_prove_out is not None:
        diff_env["PROVE_OUT"] = diff_prove_out
    try:
        extract = run([bash, "scripts/extract_assumptions.sh"], cwd=REPO_ROOT, env=extract_env)
        extracted_hash = normalized_assumptions_hash(assumptions_path)
        diff = run([bash, "scripts/diff_assumptions.sh"], cwd=REPO_ROOT, env=diff_env)
    finally:
        restore_text(assumptions_path, original_assumptions)
    return {
        "build": compact_result(build),
        "flow": compact_result(flow),
        "prove": compact_result(prove),
        "extract_assumptions": compact_result(extract),
        "diff_assumptions": compact_result(diff),
        "assumptions_extracted_sha256": extracted_hash,
    }


def run_companion_verify(*, env: dict[str, str]) -> dict[str, Any]:
    root = REPO_ROOT / "companion" / "gen"
    result = _run_verification(env=env, root=root, project="companion.gpr")
    result["prove_golden_sha256"] = sha256_file(root / "prove_golden.txt")
    result["gnatprove_summary_sha256"] = normalized_gnatprove_summary_hash(root / "obj" / "gnatprove" / "gnatprove.out")
    return result


def run_templates_verify(*, env: dict[str, str]) -> dict[str, Any]:
    root = REPO_ROOT / "companion" / "templates"
    result = _run_verification(
        env=env,
        root=root,
        project="templates.gpr",
        extract_prove_out="companion/templates/obj/gnatprove",
        diff_prove_golden="companion/templates/prove_golden.txt",
        diff_prove_out="companion/templates/obj/gnatprove/gnatprove.out",
    )
    result["prove_golden_sha256"] = sha256_file(root / "prove_golden.txt")
    result["gnatprove_summary_sha256"] = normalized_gnatprove_summary_hash(root / "obj" / "gnatprove" / "gnatprove.out")
    return result


def split_verification_group(group: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    canonical: dict[str, Any] = {}
    machine: dict[str, Any] = {}
    for key in ("build", "flow", "prove", "extract_assumptions", "diff_assumptions"):
        canonical[key], machine[key] = split_command_result(group[key])
    for key in PR101_ANCHOR_KEYS:
        canonical[key] = group[key]
    return canonical, machine


def verification_semantic_floor(group: dict[str, Any]) -> dict[str, Any]:
    return {
        "build_returncode": group["build"]["returncode"],
        "flow_returncode": group["flow"]["returncode"],
        "prove_returncode": group["prove"]["returncode"],
        "extract_assumptions_returncode": group["extract_assumptions"]["returncode"],
        "diff_assumptions_returncode": group["diff_assumptions"]["returncode"],
        **{key: group[key] for key in PR101_ANCHOR_KEYS},
    }


def build_verification_report(*, task: str, verification: str, group: dict[str, Any]) -> dict[str, Any]:
    canonical, machine = split_verification_group(group)
    return build_three_way_report(
        identity={
            "task": task,
            "verification": verification,
        },
        semantic_floor=verification_semantic_floor(group),
        canonical_proof_detail=canonical,
        machine_sensitive=machine,
    )


def verification_report_reference(
    *,
    node_id: str,
    script: str,
    report_sha256: str,
    deterministic: bool,
) -> dict[str, Any]:
    return {
        "node_id": node_id,
        "script": script,
        "report_sha256": report_sha256,
        "deterministic": deterministic,
    }
