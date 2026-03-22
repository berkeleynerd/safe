#!/usr/bin/env python3
"""Canonical gate pipeline runner."""

from __future__ import annotations

import argparse
import difflib
import json
import os
import shutil
import tempfile
import time
from pathlib import Path
from typing import Any

from _lib.gate_manifest import (
    BUILD_INITIAL,
    BUILD_POST_REPRO,
    BUILD_STATEFUL,
    NODES,
    VALIDATE_EXECUTION_STATE_FINAL,
    VALIDATE_EXECUTION_STATE_PREFLIGHT,
    DeterminismClass,
    Node,
    NodeKind,
    resolve_branch,
)
from _lib.harness_common import (
    COMPILER_ROOT,
    REPO_ROOT,
    compiler_build_argv,
    display_path,
    ensure_deterministic_env,
    ensure_sdkroot,
    find_command,
    load_evidence_policy,
    require,
    resolve_generated_path,
    run,
)
from _lib.proof_report import (
    validate_pr101_child_semantic_floor,
    validate_pr101_semantic_floor,
    validate_semantic_floor,
)
from render_execution_status import load_tracker, render_dashboard


BUILD_LABELS = {
    BUILD_INITIAL: "build_initial",
    BUILD_STATEFUL: "build_stateful",
    BUILD_POST_REPRO: "build_post_repro",
}
EVIDENCE_POLICY = load_evidence_policy()
REPORTS_ROOT_REL = Path(EVIDENCE_POLICY["generated_outputs"]["reports_root"])
DASHBOARD_REL = Path(EVIDENCE_POLICY["generated_outputs"]["dashboard"])
PROOF_SEMANTIC_FLOOR_NODE_IDS = frozenset(
    {
        "pr10_emitted_flow",
        "pr10_emitted_prove",
        "pr102_rule5_boundary_closure",
        "pr103_sequential_proof_expansion",
        "pr104_gnatprove_evidence",
        "pr106_sequential_proof_corpus",
        "pr113a_proof_checkpoint",
        "emitted_hardening_regressions",
    }
)
PR101_CHILD_NODE_IDS = frozenset(
    {
        "pr101a_companion_proof_verification",
        "pr101b_template_proof_verification",
    }
)
NODES_BY_ID = {node.id: node for node in NODES}
NODE_INDEX_BY_ID = {node.id: index for index, node in enumerate(NODES)}
_RATCHET_NODE_TIMINGS: dict[str, float] | None = None


def format_elapsed(seconds: float) -> str:
    return f"{seconds:.1f}s"


def print_gate_pipeline(message: str) -> None:
    print(f"[gate-pipeline] {message}", flush=True)


def reset_ratchet_node_timings() -> None:
    global _RATCHET_NODE_TIMINGS
    _RATCHET_NODE_TIMINGS = {}


def clear_ratchet_node_timings() -> None:
    global _RATCHET_NODE_TIMINGS
    _RATCHET_NODE_TIMINGS = None


def record_ratchet_node_timing(node_id: str, elapsed: float) -> None:
    if _RATCHET_NODE_TIMINGS is None:
        return
    previous = _RATCHET_NODE_TIMINGS.get(node_id)
    if previous is None or elapsed > previous:
        _RATCHET_NODE_TIMINGS[node_id] = elapsed


def print_ratchet_timing_summary(*, total_elapsed: float, success: bool) -> None:
    if success:
        print_gate_pipeline(f"ratchet complete ({format_elapsed(total_elapsed)})")
    if _RATCHET_NODE_TIMINGS:
        print_gate_pipeline("slowest nodes:")
        slowest = sorted(_RATCHET_NODE_TIMINGS.items(), key=lambda item: (-item[1], item[0]))[:5]
        for index, (node_id, elapsed) in enumerate(slowest, start=1):
            print_gate_pipeline(f"  {index}. {node_id:<30} {format_elapsed(elapsed)}")
    print_gate_pipeline(f"total wall time: {format_elapsed(total_elapsed)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan = subparsers.add_parser("plan")
    plan.add_argument("--branch", help="branch name to resolve; defaults to current branch")

    verify = subparsers.add_parser(
        "verify",
        help="verify committed evidence against the canonical gate pipeline",
    )
    verify.add_argument("--authority", choices=("local", "ci"), default="local")

    ratchet = subparsers.add_parser(
        "ratchet",
        help="advance ratchet-owned generated outputs from a clean generated-output baseline",
    )
    ratchet.add_argument("--authority", choices=("local", "ci"), default="local")

    return parser.parse_args()


def current_branch(*, git: str, env: dict[str, str]) -> str:
    result = run(
        [git, "symbolic-ref", "--quiet", "--short", "HEAD"],
        cwd=REPO_ROOT,
        env=env,
    )
    branch = result["stdout"].strip()
    if not branch:
        raise RuntimeError("unable to determine current branch for gate pipeline")
    return branch


def tracked_diff_snapshot(
    *,
    git: str,
    env: dict[str, str],
    paths: tuple[Path, ...] = (),
) -> str:
    argv = [git, "status", "--porcelain", "--untracked-files=no"]
    if paths:
        argv.extend(["--", *[str(path) for path in paths]])
    stdout = run(
        argv,
        cwd=REPO_ROOT,
        env=env,
    )["stdout"]
    lines = stdout.splitlines()
    lines.sort()
    if not lines:
        return ""
    return "\n".join(lines) + "\n"


def diff_context(*, expected: str, actual: str, label: str) -> str:
    diff = list(
        difflib.unified_diff(
            expected.splitlines(),
            actual.splitlines(),
            fromfile=f"{label}:expected",
            tofile=f"{label}:actual",
            lineterm="",
            n=3,
        )
    )
    if not diff:
        return ""
    return "\n".join(diff[:60])


def print_phase(phase: str, *, detail: str | None = None) -> None:
    message = f"phase: {phase}"
    if detail:
        message += f" ({detail})"
    print_gate_pipeline(message)


def print_plan(branch: str) -> int:
    nodes = resolve_branch(branch)
    print(f"[gate-pipeline] branch: {branch}")
    if not nodes:
        print("[gate-pipeline] no informational branch plan is defined")
        return 0
    for index, node in enumerate(nodes, start=1):
        if node.kind is NodeKind.BUILD:
            detail = f"build {BUILD_LABELS.get(node.id, node.id)}"
        elif node.report_path is not None:
            detail = f"{display_path(node.script, repo_root=REPO_ROOT)} -> {display_path(node.report_path, repo_root=REPO_ROOT)}"
        else:
            detail = display_path(node.script, repo_root=REPO_ROOT)
        print(f"[gate-pipeline] {index}. {node.id} [{node.kind.value}] {detail}")
    return 0


def generated_output_path(root: Path, relative: Path) -> Path:
    return root / relative


def generated_report_output_path(root: Path, report_path: Path) -> Path:
    try:
        relative = report_path.relative_to(REPO_ROOT)
    except ValueError:
        relative = Path(report_path.name)
    return generated_output_path(root, relative)


def ratchet_owned_paths() -> tuple[Path, ...]:
    return (
        REPORTS_ROOT_REL,
        DASHBOARD_REL,
    )


def checkpoint_path(checkpoint_root: Path, *, node_id: str) -> Path:
    return checkpoint_root / f"{node_id}.json"


def dependency_report_hashes(*, node: Node, pipeline_context: dict[str, Any]) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for dependency in node.depends_on:
        entry = pipeline_context.get(dependency)
        if not isinstance(entry, dict):
            continue
        report = entry.get("report")
        if not isinstance(report, dict):
            continue
        report_sha256 = report.get("report_sha256")
        if isinstance(report_sha256, str):
            hashes[dependency] = report_sha256
    return hashes


def make_pipeline_context_entry(
    *,
    node: Node,
    result: dict[str, Any],
    payload: dict[str, Any] | None,
) -> dict[str, Any]:
    if node.report_path is None:
        return {"result": result}
    require(payload is not None, f"{node.id}: missing report payload for pipeline context")
    return {
        "script": display_path(node.script, repo_root=REPO_ROOT),
        "result": result,
        "report": {
            "deterministic": payload["deterministic"],
            "report_sha256": payload["report_sha256"],
            "repeat_sha256": payload["repeat_sha256"],
        },
    }


def write_checkpoint(
    checkpoint_root: Path,
    *,
    node: Node,
    node_index: int,
    authority: str,
    pipeline_context_entry: dict[str, Any],
    dependency_hashes: dict[str, str],
) -> None:
    checkpoint_root.mkdir(parents=True, exist_ok=True)
    report = pipeline_context_entry.get("report")
    report_sha256 = report.get("report_sha256") if isinstance(report, dict) else None
    payload = {
        "node_id": node.id,
        "node_index": node_index,
        "kind": node.kind.value,
        "authority": authority,
        "repo_clean_profile": node.repo_clean_profile,
        "scratch_profile": node.scratch_profile,
        "depends_on": list(node.depends_on),
        "status": "ok",
        "report_sha256": report_sha256,
        "dependency_report_hashes": dependency_hashes,
        "pipeline_context_entry": pipeline_context_entry,
    }
    checkpoint_path(checkpoint_root, node_id=node.id).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def load_seed_pipeline_context(*, checkpoint_root: Path, start_index: int) -> dict[str, Any]:
    if start_index <= 1:
        return {}
    seeded: dict[str, Any] = {}
    for node in NODES[1:start_index]:
        if node.kind is NodeKind.BUILD:
            continue
        path = checkpoint_path(checkpoint_root, node_id=node.id)
        require(path.exists(), f"{node.id}: missing checkpoint {display_path(path, repo_root=REPO_ROOT)}")
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"{node.id}: corrupt checkpoint {display_path(path, repo_root=REPO_ROOT)}: {exc.msg}"
            ) from exc
        require(payload.get("status") == "ok", f"{node.id}: invalid checkpoint status")
        require(payload.get("node_id") == node.id, f"{node.id}: checkpoint node id mismatch")
        entry = payload.get("pipeline_context_entry")
        require(isinstance(entry, dict), f"{node.id}: checkpoint missing pipeline_context_entry")
        seeded[node.id] = entry
    return seeded


def changed_report_nodes(*, generated_root: Path) -> list[str]:
    changed: list[str] = []
    for node in NODES:
        if node.report_path is None:
            continue
        generated_path = generated_report_output_path(generated_root, node.report_path)
        require(generated_path.exists(), f"{node.id}: missing generated report {generated_path}")
        expected_path = node.report_path
        if not expected_path.exists():
            changed.append(node.id)
            continue
        if generated_path.read_text(encoding="utf-8") != expected_path.read_text(encoding="utf-8"):
            changed.append(node.id)
    return changed


def dashboard_changed(*, generated_root: Path) -> bool:
    staged_dashboard = generated_output_path(generated_root, DASHBOARD_REL)
    committed_dashboard = REPO_ROOT / DASHBOARD_REL
    require(staged_dashboard.exists(), f"missing staged dashboard {staged_dashboard}")
    require(committed_dashboard.exists(), f"missing committed dashboard {committed_dashboard}")
    return staged_dashboard.read_text(encoding="utf-8") != committed_dashboard.read_text(encoding="utf-8")


def final_rerun_start_index(*, changed_nodes: list[str], dashboard_changed_flag: bool) -> int:
    del dashboard_changed_flag
    if not changed_nodes:
        return NODE_INDEX_BY_ID[VALIDATE_EXECUTION_STATE_FINAL]
    frontier_node = NODES_BY_ID[changed_nodes[0]]
    for dependency in frontier_node.depends_on:
        dependency_node = NODES_BY_ID[dependency]
        if dependency_node.kind is NodeKind.BUILD:
            return NODE_INDEX_BY_ID[dependency]
    return NODE_INDEX_BY_ID[frontier_node.id]


def execution_indices(*, start_index: int, rerun_preflight: bool) -> list[int]:
    if rerun_preflight and start_index > 0:
        return [NODE_INDEX_BY_ID[VALIDATE_EXECUTION_STATE_PREFLIGHT], *range(start_index, len(NODES))]
    return list(range(start_index, len(NODES)))


def prepare_generated_root(root: Path) -> None:
    generated_output_path(root, REPORTS_ROOT_REL).mkdir(parents=True, exist_ok=True)
    dashboard_path = generated_output_path(root, DASHBOARD_REL)
    dashboard_path.parent.mkdir(parents=True, exist_ok=True)
    dashboard_path.write_text(render_dashboard(load_tracker()), encoding="utf-8")


def clean_repo_profile(profile: str | None) -> None:
    if profile is None:
        return
    if profile == "frontend_build":
        shutil.rmtree(COMPILER_ROOT / "obj", ignore_errors=True)
        shutil.rmtree(COMPILER_ROOT / "alire" / "tmp", ignore_errors=True)
        safec = COMPILER_ROOT / "bin" / "safec"
        if safec.exists():
            safec.unlink()
        return
    if profile == "companion_gen_proof":
        shutil.rmtree(REPO_ROOT / "companion" / "gen" / "obj", ignore_errors=True)
        return
    if profile == "companion_template_proof":
        shutil.rmtree(REPO_ROOT / "companion" / "templates" / "obj", ignore_errors=True)
        return
    raise RuntimeError(f"unknown clean profile: {profile}")


def report_compare_text(
    report_text: str,
    *,
    node: Node,
    authority: str,
) -> str:
    if authority == "local" and node.determinism_class is DeterminismClass.CI_AUTHORITATIVE:
        payload = json.loads(report_text)
        normalized = {key: value for key, value in payload.items() if key != "machine_sensitive"}
        return json.dumps(normalized, indent=2, sort_keys=True) + "\n"
    return report_text


def expected_report_path(node: Node, *, compare_root: Path | None) -> Path:
    require(node.report_path is not None, f"{node.id}: report path required")
    if compare_root is None:
        return node.report_path
    return generated_report_output_path(compare_root, node.report_path)


def reused_authoritative_command(*, python: str, node: Node) -> list[str]:
    require(node.script is not None, f"{node.id}: script required for reused authoritative command")
    command = [
        python,
        display_path(node.script, repo_root=REPO_ROOT),
        *node.argv,
        "--report",
        f"$TMPDIR/{node.script.stem}.json",
    ]
    return command


def reused_authoritative_stdout(*, node: Node) -> str:
    require(node.script is not None, f"{node.id}: script required for reused authoritative stdout")
    label = node.script.stem
    if label.startswith("run_"):
        label = label[4:]
    label = label.replace("_", " ")
    return f"{label}: OK ($TMPDIR/{node.script.stem}.json)\n"


def reuse_ci_authoritative_report(
    node: Node,
    *,
    python: str,
    authority: str,
    compare_root: Path | None,
    write_generated_root: Path | None,
) -> tuple[dict[str, Any], dict[str, Any], Path]:
    require(authority == "local", f"{node.id}: CI-authoritative reuse is local-only")
    require(
        node.determinism_class is DeterminismClass.CI_AUTHORITATIVE,
        f"{node.id}: expected CI-authoritative node",
    )
    require(node.report_path is not None, f"{node.id}: report path required for CI-authoritative reuse")
    require(write_generated_root is not None, f"{node.id}: write root required for CI-authoritative reuse")

    source_report_path = expected_report_path(node, compare_root=compare_root)
    require(source_report_path.exists(), f"{node.id}: missing source report {source_report_path}")
    generated_report_path = generated_report_output_path(write_generated_root, node.report_path)
    generated_report_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_report_path, generated_report_path)

    payload = json.loads(generated_report_path.read_text(encoding="utf-8"))
    require(payload.get("deterministic") is True, f"{node.id}: reused authoritative report must be deterministic")
    require(
        payload.get("report_sha256") == payload.get("repeat_sha256"),
        f"{node.id}: reused authoritative report hashes must match",
    )
    result = {
        "command": reused_authoritative_command(python=python, node=node),
        "cwd": "$REPO_ROOT",
        "returncode": 0,
        "stdout": reused_authoritative_stdout(node=node),
        "stderr": "",
    }
    return result, payload, generated_report_path


def validate_local_reused_authoritative_report(
    *,
    node: Node,
    payload: dict[str, Any],
    pipeline_context: dict[str, Any],
) -> None:
    if node.id in PROOF_SEMANTIC_FLOOR_NODE_IDS:
        validate_semantic_floor(payload)
        return
    if node.id in PR101_CHILD_NODE_IDS:
        validate_pr101_child_semantic_floor(payload)
        return
    if node.id == "pr101_comprehensive_audit":
        validate_pr101_semantic_floor(payload, pipeline_context=pipeline_context)
        return
    raise RuntimeError(f"{node.id}: unhandled local CI-authoritative validation")


def node_scratch_root(*, node: Node, write_generated_root: Path | None) -> Path | None:
    if not node.supports_scratch_root:
        return None
    require(write_generated_root is not None, f"{node.id}: write root required for scratch root")
    scratch_root = write_generated_root / "scratch" / node.id
    shutil.rmtree(scratch_root, ignore_errors=True)
    scratch_root.parent.mkdir(parents=True, exist_ok=True)
    scratch_root.mkdir(parents=True, exist_ok=True)
    return scratch_root


def write_pipeline_input(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_node(
    node: Node,
    *,
    python: str,
    authority: str,
    env: dict[str, str],
    read_generated_root: Path | None,
    write_generated_root: Path | None,
    pipeline_context: dict[str, Any],
    preflight_generated_output_baseline_file: Path | None = None,
) -> tuple[dict[str, Any], dict[str, Any] | None, Path | None]:
    argv = [python, str(node.script), *node.argv]
    temp_root = write_generated_root

    if node.supports_authority:
        argv.extend(["--authority", authority])

    if (
        node.id == VALIDATE_EXECUTION_STATE_PREFLIGHT
        and preflight_generated_output_baseline_file is not None
    ):
        argv.extend(
            [
                "--generated-output-baseline-file",
                str(preflight_generated_output_baseline_file),
            ]
        )

    if node.supports_pipeline_input:
        require(write_generated_root is not None, f"{node.id}: write root required for pipeline input")
        pipeline_input_path = write_generated_root / "pipeline-input.json"
        write_pipeline_input(pipeline_input_path, pipeline_context)
        argv.extend(["--pipeline-input", str(pipeline_input_path)])

    if node.supports_generated_root and read_generated_root is not None:
        argv.extend(["--generated-root", str(read_generated_root)])

    scratch_root = node_scratch_root(node=node, write_generated_root=write_generated_root)
    if scratch_root is not None:
        argv.extend(["--scratch-root", str(scratch_root)])

    report_path: Path | None = None
    if node.report_path is not None:
        require(write_generated_root is not None, f"{node.id}: write root required for report")
        report_path = generated_report_output_path(write_generated_root, node.report_path)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        argv.extend(["--report", str(report_path)])

    result = run(argv, cwd=REPO_ROOT, env=env, temp_root=temp_root)
    if report_path is None:
        return result, None, None

    require(report_path.exists(), f"{node.id}: missing generated report {report_path}")
    payload = json.loads(report_path.read_text(encoding="utf-8"))
    require(payload.get("deterministic") is True, f"{node.id}: temp report must be deterministic")
    require(
        payload.get("report_sha256") == payload.get("repeat_sha256"),
        f"{node.id}: temp report hashes must match",
    )
    return result, payload, report_path


def execute_pipeline(
    *,
    authority: str,
    python: str,
    env: dict[str, str],
    alr: str,
    git: str,
    read_generated_root: Path | None,
    write_generated_root: Path | None,
    compare_root: Path | None,
    compare_to_committed: bool,
    initial_snapshot: str,
    start_index: int = 0,
    seed_pipeline_context: dict[str, Any] | None = None,
    checkpoint_root: Path | None = None,
    preflight_generated_output_baseline_file: Path | None = None,
) -> dict[str, Any]:
    pipeline_context: dict[str, Any] = dict(seed_pipeline_context or {})
    if write_generated_root is not None:
        prepare_generated_root(write_generated_root)

    for node_index in execution_indices(
        start_index=start_index,
        rerun_preflight=preflight_generated_output_baseline_file is not None,
    ):
        node = NODES[node_index]
        node_started = time.monotonic()
        print_gate_pipeline(f"running: {node.id}")
        if node.kind is NodeKind.BUILD:
            if node.repo_clean_profile is not None:
                clean_started = time.monotonic()
                clean_repo_profile(node.repo_clean_profile)
                print_gate_pipeline(
                    f"clean profile: {node.repo_clean_profile} ({format_elapsed(time.monotonic() - clean_started)})"
                )
            build_started = time.monotonic()
            run(compiler_build_argv(alr), cwd=COMPILER_ROOT, env=env)
            print_gate_pipeline(f"build: {node.id} ({format_elapsed(time.monotonic() - build_started)})")
            node_elapsed = time.monotonic() - node_started
            print_gate_pipeline(f"completed: {node.id} ({format_elapsed(node_elapsed)})")
            record_ratchet_node_timing(node.id, node_elapsed)
            continue

        if authority == "local" and node.determinism_class is DeterminismClass.CI_AUTHORITATIVE:
            result, payload, generated_report_path = reuse_ci_authoritative_report(
                node,
                python=python,
                authority=authority,
                compare_root=compare_root,
                write_generated_root=write_generated_root,
            )
            require(payload is not None, f"{node.id}: missing reused report payload")
            validate_local_reused_authoritative_report(
                node=node,
                payload=payload,
                pipeline_context=pipeline_context,
            )
        else:
            clean_repo_profile(node.repo_clean_profile)
            result, payload, generated_report_path = run_node(
                node,
                python=python,
                authority=authority,
                env=env,
                read_generated_root=read_generated_root,
                write_generated_root=write_generated_root,
                pipeline_context=pipeline_context,
                preflight_generated_output_baseline_file=preflight_generated_output_baseline_file,
            )
        if node.report_path is not None:
            require(payload is not None and generated_report_path is not None, f"{node.id}: missing report payload")
            if compare_to_committed or compare_root is not None:
                expected_path = (
                    node.report_path
                    if compare_to_committed
                    else expected_report_path(node, compare_root=compare_root)
                )
                require(expected_path.exists(), f"{node.id}: missing expected report {expected_path}")
                actual_report_text = generated_report_path.read_text(encoding="utf-8")
                expected_report_text = expected_path.read_text(encoding="utf-8")
                actual_text = report_compare_text(actual_report_text, node=node, authority=authority)
                expected_text = report_compare_text(expected_report_text, node=node, authority=authority)
                require(
                    actual_text == expected_text,
                    f"{node.id}: generated report drifted from {display_path(expected_path, repo_root=REPO_ROOT)}\n"
                    f"{diff_context(expected=expected_text, actual=actual_text, label=node.id)}",
                )
        pipeline_context_entry = make_pipeline_context_entry(node=node, result=result, payload=payload)
        pipeline_context[node.id] = pipeline_context_entry
        if checkpoint_root is not None:
            write_checkpoint(
                checkpoint_root,
                node=node,
                node_index=node_index,
                authority=authority,
                pipeline_context_entry=pipeline_context_entry,
                dependency_hashes=dependency_report_hashes(node=node, pipeline_context=pipeline_context),
            )
        node_elapsed = time.monotonic() - node_started
        print_gate_pipeline(f"completed: {node.id} ({format_elapsed(node_elapsed)})")
        record_ratchet_node_timing(node.id, node_elapsed)

    final_snapshot = tracked_diff_snapshot(git=git, env=env)
    require(final_snapshot == initial_snapshot, "gate pipeline changed tracked files during execution")
    return pipeline_context


def verify_pipeline(
    *,
    authority: str,
    python: str,
    git: str,
    alr: str,
    env: dict[str, str],
    initial_snapshot: str | None = None,
) -> int:
    verify_started = time.monotonic()
    if initial_snapshot is None:
        initial_snapshot = tracked_diff_snapshot(git=git, env=env)
    with tempfile.TemporaryDirectory(prefix="gate-pipeline-verify-") as temp_root_str:
        temp_root = Path(temp_root_str)
        execute_pipeline(
            authority=authority,
            python=python,
            env=env,
            alr=alr,
            git=git,
            read_generated_root=None,
            write_generated_root=temp_root,
            compare_root=None,
            compare_to_committed=True,
            initial_snapshot=initial_snapshot,
        )
    print_gate_pipeline(f"verify complete ({format_elapsed(time.monotonic() - verify_started)})")
    print_gate_pipeline(f"verified ({authority})")
    return 0


def promote_stage(stage_root: Path) -> None:
    reports_path = REPO_ROOT / REPORTS_ROOT_REL
    dashboard_path = REPO_ROOT / DASHBOARD_REL
    stage_reports = generated_output_path(stage_root, REPORTS_ROOT_REL)
    stage_dashboard = generated_output_path(stage_root, DASHBOARD_REL)

    backup_root = Path(tempfile.mkdtemp(prefix="gate-pipeline-backup-"))
    try:
        backup_reports = backup_root / REPORTS_ROOT_REL
        backup_dashboard = backup_root / DASHBOARD_REL
        backup_reports.parent.mkdir(parents=True, exist_ok=True)
        backup_dashboard.parent.mkdir(parents=True, exist_ok=True)
        if reports_path.exists():
            shutil.copytree(reports_path, backup_reports, dirs_exist_ok=True)
        if dashboard_path.exists():
            shutil.copy2(dashboard_path, backup_dashboard)

        shutil.rmtree(reports_path, ignore_errors=True)
        reports_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(stage_reports, reports_path, dirs_exist_ok=True)
        dashboard_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(stage_dashboard, dashboard_path)
    except Exception:
        shutil.rmtree(reports_path, ignore_errors=True)
        if (backup_root / REPORTS_ROOT_REL).exists():
            shutil.copytree(backup_root / REPORTS_ROOT_REL, reports_path)
        if (backup_root / DASHBOARD_REL).exists():
            dashboard_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(backup_root / DASHBOARD_REL, dashboard_path)
        raise
    finally:
        shutil.rmtree(backup_root, ignore_errors=True)


def write_generated_output_baseline_file(path: Path, *, snapshot: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(snapshot, encoding="utf-8")


def final_rerun_pipeline(
    *,
    authority: str,
    python: str,
    git: str,
    alr: str,
    env: dict[str, str],
    stage_root: Path,
    stage_verify_root: Path,
    final_verify_root: Path,
) -> int:
    changed_nodes = changed_report_nodes(generated_root=stage_root)
    promoted_dashboard_changed = dashboard_changed(generated_root=stage_root)
    start_index = final_rerun_start_index(
        changed_nodes=changed_nodes,
        dashboard_changed_flag=promoted_dashboard_changed,
    )

    print_gate_pipeline(
        f"frontier computation: starting at {NODES[start_index].id} (index {start_index})"
    )

    print_phase(
        "promote staged outputs",
        detail=(
            "changed reports: "
            + ", ".join(changed_nodes)
            if changed_nodes
            else (
                "dashboard only"
                if promoted_dashboard_changed
                else "no staged output changes"
            )
        ),
    )
    promotion_started = time.monotonic()
    promote_stage(stage_root)
    print_gate_pipeline(f"promotion complete ({format_elapsed(time.monotonic() - promotion_started)})")

    promoted_snapshot = tracked_diff_snapshot(git=git, env=env)
    promoted_generated_snapshot = tracked_diff_snapshot(git=git, env=env, paths=ratchet_owned_paths())
    baseline_path = final_verify_root / "generated-output-baseline.txt"
    write_generated_output_baseline_file(baseline_path, snapshot=promoted_generated_snapshot)

    checkpoint_started = time.monotonic()
    seed_pipeline_context = load_seed_pipeline_context(
        checkpoint_root=stage_verify_root / "checkpoints",
        start_index=start_index,
    )
    print_gate_pipeline(
        "checkpoint seeding: loaded "
        f"{len(seed_pipeline_context)} prefix entries ({format_elapsed(time.monotonic() - checkpoint_started)})"
    )
    print_phase(
        "final rerun",
        detail=f"start node: {NODES[start_index].id}",
    )
    rerun_indices = execution_indices(start_index=start_index, rerun_preflight=True)
    rerun_started = time.monotonic()
    execute_pipeline(
        authority=authority,
        python=python,
        env=env,
        alr=alr,
        git=git,
        read_generated_root=None,
        write_generated_root=final_verify_root,
        compare_root=None,
        compare_to_committed=True,
        initial_snapshot=promoted_snapshot,
        start_index=start_index,
        seed_pipeline_context=seed_pipeline_context,
        checkpoint_root=final_verify_root / "checkpoints",
        preflight_generated_output_baseline_file=baseline_path,
    )
    rerun_elapsed = time.monotonic() - rerun_started
    print_gate_pipeline(f"final rerun complete ({format_elapsed(rerun_elapsed)})")
    print_gate_pipeline(
        f"final rerun: {len(rerun_indices)} nodes executed, "
        f"{len(NODES) - len(set(rerun_indices))} nodes skipped ({format_elapsed(rerun_elapsed)})"
    )
    print_gate_pipeline(f"verified ({authority})")
    return 0


def ratchet_pipeline(*, authority: str, python: str, git: str, alr: str, env: dict[str, str]) -> int:
    ratchet_started = time.monotonic()
    success = False
    reset_ratchet_node_timings()
    try:
        initial_snapshot = tracked_diff_snapshot(git=git, env=env)
        generated_snapshot = tracked_diff_snapshot(git=git, env=env, paths=ratchet_owned_paths())
        require(
            generated_snapshot == "",
            "ratchet requires a clean generated-output working tree; either accept ratchet artifact "
            "and commit the current ratchet-owned diffs, or restore ratchet baseline before retrying",
        )

        with tempfile.TemporaryDirectory(prefix="gate-pipeline-stage-") as stage_root_str:
            stage_root = Path(stage_root_str)
            with tempfile.TemporaryDirectory(prefix="gate-pipeline-stage-verify-") as verify_root_str, tempfile.TemporaryDirectory(
                prefix="gate-pipeline-final-verify-"
            ) as final_verify_root_str:
                verify_root = Path(verify_root_str)
                final_verify_root = Path(final_verify_root_str)
                print_phase("stage generation")
                stage_generation_started = time.monotonic()
                execute_pipeline(
                    authority=authority,
                    python=python,
                    env=env,
                    alr=alr,
                    git=git,
                    read_generated_root=stage_root,
                    write_generated_root=stage_root,
                    compare_root=None,
                    compare_to_committed=False,
                    initial_snapshot=initial_snapshot,
                    checkpoint_root=stage_root / "checkpoints",
                )
                print_gate_pipeline(
                    f"stage generation complete ({format_elapsed(time.monotonic() - stage_generation_started)})"
                )
                print_phase("stage verify")
                stage_verify_started = time.monotonic()
                execute_pipeline(
                    authority=authority,
                    python=python,
                    env=env,
                    alr=alr,
                    git=git,
                    read_generated_root=stage_root,
                    write_generated_root=verify_root,
                    compare_root=stage_root,
                    compare_to_committed=False,
                    initial_snapshot=initial_snapshot,
                    checkpoint_root=verify_root / "checkpoints",
                )
                print_gate_pipeline(
                    f"stage verification complete ({format_elapsed(time.monotonic() - stage_verify_started)})"
                )
                result = final_rerun_pipeline(
                    authority=authority,
                    python=python,
                    git=git,
                    alr=alr,
                    env=env,
                    stage_root=stage_root,
                    stage_verify_root=verify_root,
                    final_verify_root=final_verify_root,
                )
                success = True
                return result
    finally:
        print_ratchet_timing_summary(
            total_elapsed=time.monotonic() - ratchet_started,
            success=success,
        )
        clear_ratchet_node_timings()


def main() -> int:
    args = parse_args()
    env = ensure_deterministic_env(
        ensure_sdkroot(os.environ.copy()),
        required=EVIDENCE_POLICY["environment"]["required_env"],
    )
    python = find_command("python3")
    git = find_command("git")
    alr = find_command("alr", fallback=Path.home() / "bin" / "alr")

    if args.command == "plan":
        branch = args.branch or current_branch(git=git, env=env)
        return print_plan(branch)
    if args.command == "verify":
        return verify_pipeline(authority=args.authority, python=python, git=git, alr=alr, env=env)
    if args.command == "ratchet":
        return ratchet_pipeline(authority=args.authority, python=python, git=git, alr=alr, env=env)
    raise RuntimeError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
