#!/usr/bin/env python3
"""Canonical gate pipeline runner."""

from __future__ import annotations

import argparse
import difflib
import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

from _lib.gate_manifest import (
    BUILD_INITIAL,
    BUILD_POST_REPRO,
    BUILD_STATEFUL,
    NODES,
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
from render_execution_status import load_tracker, render_dashboard


BUILD_LABELS = {
    BUILD_INITIAL: "build_initial",
    BUILD_STATEFUL: "build_stateful",
    BUILD_POST_REPRO: "build_post_repro",
}
EVIDENCE_POLICY = load_evidence_policy()
REPORTS_ROOT_REL = Path(EVIDENCE_POLICY["generated_outputs"]["reports_root"])
DASHBOARD_REL = Path(EVIDENCE_POLICY["generated_outputs"]["dashboard"])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan = subparsers.add_parser("plan")
    plan.add_argument("--branch", help="branch name to resolve; defaults to current branch")

    verify = subparsers.add_parser("verify")
    verify.add_argument("--authority", choices=("local", "ci"), default="local")

    ratchet = subparsers.add_parser("ratchet")
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
    return run(
        argv,
        cwd=REPO_ROOT,
        env=env,
    )["stdout"]


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


def prepare_generated_root(root: Path) -> None:
    generated_output_path(root, REPORTS_ROOT_REL).mkdir(parents=True, exist_ok=True)
    dashboard_path = generated_output_path(root, DASHBOARD_REL)
    dashboard_path.parent.mkdir(parents=True, exist_ok=True)
    dashboard_path.write_text(render_dashboard(load_tracker()), encoding="utf-8")


def clean_profile(profile: str | None) -> None:
    if profile is None:
        return
    if profile == "frontend_build":
        shutil.rmtree(COMPILER_ROOT / "obj", ignore_errors=True)
        shutil.rmtree(COMPILER_ROOT / "alire" / "tmp", ignore_errors=True)
        safec = COMPILER_ROOT / "bin" / "safec"
        if safec.exists():
            safec.unlink()
        return
    if profile == "post_repro_build":
        clean_profile("frontend_build")
        shutil.rmtree(REPO_ROOT / "companion" / "gen" / "obj", ignore_errors=True)
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
) -> tuple[dict[str, Any], dict[str, Any] | None, Path | None]:
    argv = [python, str(node.script), *node.argv]
    temp_root = write_generated_root

    if node.script is not None and node.script.name == "validate_execution_state.py":
        argv.extend(["--authority", authority])

    if node.supports_pipeline_input:
        require(write_generated_root is not None, f"{node.id}: write root required for pipeline input")
        pipeline_input_path = write_generated_root / "pipeline-input.json"
        write_pipeline_input(pipeline_input_path, pipeline_context)
        argv.extend(["--pipeline-input", str(pipeline_input_path)])

    if node.supports_generated_root and read_generated_root is not None:
        argv.extend(["--generated-root", str(read_generated_root)])

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
) -> dict[str, Any]:
    pipeline_context: dict[str, Any] = {}
    if write_generated_root is not None:
        prepare_generated_root(write_generated_root)

    for node in NODES:
        print(f"[gate-pipeline] running: {node.id}")
        if node.kind is NodeKind.BUILD:
            clean_profile(node.clean_profile)
            run(compiler_build_argv(alr), cwd=COMPILER_ROOT, env=env)
            continue

        if authority == "local" and node.determinism_class is DeterminismClass.CI_AUTHORITATIVE:
            result, payload, generated_report_path = reuse_ci_authoritative_report(
                node,
                python=python,
                authority=authority,
                compare_root=compare_root,
                write_generated_root=write_generated_root,
            )
        else:
            result, payload, generated_report_path = run_node(
                node,
                python=python,
                authority=authority,
                env=env,
                read_generated_root=read_generated_root,
                write_generated_root=write_generated_root,
                pipeline_context=pipeline_context,
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
            pipeline_context[node.id] = {
                "script": display_path(node.script, repo_root=REPO_ROOT),
                "result": result,
                "report": {
                    "deterministic": payload["deterministic"],
                    "report_sha256": payload["report_sha256"],
                    "repeat_sha256": payload["repeat_sha256"],
                },
            }
        else:
            pipeline_context[node.id] = {"result": result}

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
    print(f"[gate-pipeline] verified ({authority})")
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
            shutil.copytree(backup_root / REPORTS_ROOT_REL, reports_path, dirs_exist_ok=True)
        if (backup_root / DASHBOARD_REL).exists():
            dashboard_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(backup_root / DASHBOARD_REL, dashboard_path)
        raise
    finally:
        shutil.rmtree(backup_root, ignore_errors=True)


def ratchet_pipeline(*, authority: str, python: str, git: str, alr: str, env: dict[str, str]) -> int:
    initial_snapshot = tracked_diff_snapshot(git=git, env=env)
    generated_snapshot = tracked_diff_snapshot(git=git, env=env, paths=ratchet_owned_paths())
    require(generated_snapshot == "", "ratchet requires a clean generated-output working tree")

    with tempfile.TemporaryDirectory(prefix="gate-pipeline-stage-") as stage_root_str:
        stage_root = Path(stage_root_str)
        prepare_generated_root(stage_root)
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
        )

        with tempfile.TemporaryDirectory(prefix="gate-pipeline-stage-verify-") as verify_root_str:
            verify_root = Path(verify_root_str)
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
            )

        promote_stage(stage_root)

    return verify_pipeline(
        authority=authority,
        python=python,
        git=git,
        alr=alr,
        env=env,
        initial_snapshot=tracked_diff_snapshot(git=git, env=env),
    )


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
