#!/usr/bin/env python3
"""Archive retired reports and manage the PR11.6.1 compaction receipt."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any

from _lib.attestation_compression import (
    ARCHIVE_ROOT,
    ARCHIVE_SCHEMA_VERSION,
    LIVE_SUBSUMER,
    RECEIPT_PATH,
    RECEIPT_SCHEMA_VERSION,
    RETIRED_NODE_IDS,
    RETIRED_NODE_SPECS,
    active_report_entries,
    merkle_root,
    inclusion_proof,
    validate_retired_node_ids,
    verify_inclusion_proof,
)
from _lib.harness_common import REPO_ROOT, display_path, ensure_deterministic_env, find_command, require, run, write_report


def git_process_env(base_env: dict[str, str]) -> dict[str, str]:
    return ensure_deterministic_env(
        {
            key: value
            for key, value in base_env.items()
            if not key.startswith("GIT_")
        }
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    apply_parser = subparsers.add_parser("apply", help="archive retired reports and write provenance")
    apply_parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    apply_parser.add_argument("--pre-compaction-commit")

    finalize = subparsers.add_parser(
        "finalize-receipt",
        help="write the final PR11.6.1 compaction receipt after the compaction commit exists",
    )
    finalize.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    finalize.add_argument("--pre-compaction-commit")
    finalize.add_argument("--post-compaction-commit")
    finalize.add_argument("--receipt", type=Path)

    verify = subparsers.add_parser("verify-receipt", help="verify archive proofs and the compaction receipt")
    verify.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    verify.add_argument("--pre-compaction-root", type=Path)
    verify.add_argument("--receipt", type=Path)

    return parser.parse_args()


def current_head_commit(*, git: str, env: dict[str, str], repo_root: Path) -> str:
    return run([git, "rev-parse", "HEAD"], cwd=repo_root, env=env)["stdout"].strip()


def check_clean_worktree(*, git: str, env: dict[str, str], repo_root: Path) -> None:
    stdout = run(
        [git, "status", "--porcelain", "--untracked-files=no"],
        cwd=repo_root,
        env=env,
    )["stdout"].strip()
    require(not stdout, "compress_attestation_chain apply requires a clean tracked worktree")


def retired_entries(*, repo_root: Path) -> list[tuple[str, bytes]]:
    entries: list[tuple[str, bytes]] = []
    for spec in RETIRED_NODE_SPECS:
        report_path = spec.original_report_path_at(repo_root)
        require(report_path.exists(), f"missing retired report {display_path(report_path, repo_root=repo_root)}")
        entries.append((spec.original_report_rel, report_path.read_bytes()))
    return entries


def apply_archive(*, git: str, env: dict[str, str], repo_root: Path, pre_compaction_commit: str | None) -> int:
    check_clean_worktree(git=git, env=env, repo_root=repo_root)
    validate_retired_node_ids(RETIRED_NODE_IDS)
    pre_commit = pre_compaction_commit or current_head_commit(git=git, env=env, repo_root=repo_root)
    entries = retired_entries(repo_root=repo_root)
    pre_root = merkle_root(entries)

    for spec in RETIRED_NODE_SPECS:
        archive_dir = spec.archive_dir_at(repo_root)
        original_report_path = spec.original_report_path_at(repo_root)
        archive_report_path = spec.archive_report_path_at(repo_root)
        archive_provenance_path = spec.archive_provenance_path_at(repo_root)
        archive_dir.mkdir(parents=True, exist_ok=True)
        shutil.move(str(original_report_path), str(archive_report_path))
        report_payload = json.loads(archive_report_path.read_text(encoding="utf-8"))
        provenance = {
            "schema_version": ARCHIVE_SCHEMA_VERSION,
            "node_id": spec.node_id,
            "original_report_path": spec.original_report_rel,
            "archived_report_path": spec.archive_report_rel,
            "report_sha256": report_payload["report_sha256"],
            "live_subsumer": LIVE_SUBSUMER,
            "transitive_chain": list(spec.transitive_chain),
            "pre_merkle_root": pre_root,
            "inclusion_proof": inclusion_proof(entries, path=spec.original_report_rel),
            "pre_compaction_commit": pre_commit,
        }
        write_report(archive_provenance_path, provenance)

    print(f"attestation compression applied: {display_path(repo_root / 'execution' / 'archive', repo_root=repo_root)}")
    return 0


def load_provenance(*, repo_root: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for spec in RETIRED_NODE_SPECS:
        path = spec.archive_provenance_path_at(repo_root)
        require(path.exists(), f"missing archive provenance {display_path(path, repo_root=repo_root)}")
        payload = json.loads(path.read_text(encoding="utf-8"))
        require(isinstance(payload, dict), f"{display_path(path, repo_root=repo_root)} must be a JSON object")
        records.append(payload)
    return records


def finalize_receipt(
    *,
    git: str,
    env: dict[str, str],
    repo_root: Path,
    receipt_path: Path,
    pre_compaction_commit: str | None,
    post_compaction_commit: str | None,
) -> int:
    provenance = load_provenance(repo_root=repo_root)
    validate_retired_node_ids([record["node_id"] for record in provenance])
    pre_commit = pre_compaction_commit or provenance[0]["pre_compaction_commit"]
    post_commit = post_compaction_commit or current_head_commit(git=git, env=env, repo_root=repo_root)
    pre_root = provenance[0]["pre_merkle_root"]
    post_root = merkle_root(active_report_entries(repo_root=repo_root))
    retired_nodes: list[dict[str, Any]] = []
    for record in provenance:
        retired_nodes.append(
            {
                "node_id": record["node_id"],
                "original_report_path": record["original_report_path"],
                "archived_report_path": record["archived_report_path"],
                "report_sha256": record["report_sha256"],
                "live_subsumer": record["live_subsumer"],
                "transitive_chain": record["transitive_chain"],
                "pre_merkle_root": record["pre_merkle_root"],
                "inclusion_proof": record["inclusion_proof"],
                "pre_compaction_commit": record["pre_compaction_commit"],
            }
        )
    receipt = {
        "schema_version": RECEIPT_SCHEMA_VERSION,
        "task_id": "PR11.6.1",
        "retired_node_ids": list(RETIRED_NODE_IDS),
        "pre_merkle_root": pre_root,
        "post_merkle_root": post_root,
        "pre_compaction_commit": pre_commit,
        "post_compaction_commit": post_commit,
        "archive_root": "execution/archive",
        "retired_nodes": retired_nodes,
    }
    write_report(receipt_path, receipt)
    print(f"compaction receipt written: {display_path(receipt_path, repo_root=repo_root)}")
    return 0


def verify_receipt(*, receipt_path: Path, repo_root: Path, pre_compaction_root: Path | None = None) -> int:
    require(receipt_path.exists(), f"missing receipt {display_path(receipt_path, repo_root=repo_root)}")
    payload = json.loads(receipt_path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), "receipt root must be a JSON object")
    require(payload["task_id"] == "PR11.6.1", "receipt task_id must be PR11.6.1")
    require(payload["retired_node_ids"] == list(RETIRED_NODE_IDS), "receipt retired_node_ids drifted")
    require(payload["archive_root"] == "execution/archive", "receipt archive_root drifted")
    pre_root = payload["pre_merkle_root"]
    post_root = payload["post_merkle_root"]
    pre_commit = payload["pre_compaction_commit"]
    post_commit = payload["post_compaction_commit"]
    retired_nodes = payload.get("retired_nodes")
    require(isinstance(retired_nodes, list), "receipt retired_nodes must be a list")
    require(len(retired_nodes) == len(RETIRED_NODE_SPECS), "receipt retired_nodes length drifted")
    retired_nodes_by_id: dict[str, dict[str, Any]] = {}
    for entry in retired_nodes:
        require(isinstance(entry, dict), "receipt retired_nodes entries must be JSON objects")
        node_id = entry.get("node_id")
        require(isinstance(node_id, str), "receipt retired_nodes entries must include node_id")
        require(node_id not in retired_nodes_by_id, f"{node_id}: duplicate retired node in receipt")
        retired_nodes_by_id[node_id] = entry
    require(list(retired_nodes_by_id) == list(RETIRED_NODE_IDS), "receipt retired_nodes order drifted")
    if pre_compaction_root is not None:
        require(
            merkle_root(retired_entries(repo_root=pre_compaction_root)) == pre_root,
            "receipt pre_merkle_root does not match the supplied pre-compaction checkout",
        )
    for spec in RETIRED_NODE_SPECS:
        retired_node = retired_nodes_by_id[spec.node_id]
        archived_report_bytes = spec.archive_report_path_at(repo_root).read_bytes()
        archived_report_payload = json.loads(archived_report_bytes.decode("utf-8"))
        require(isinstance(archived_report_payload, dict), f"{spec.node_id}: archived report root must be a JSON object")
        report_bytes = archived_report_bytes
        if pre_compaction_root is not None:
            report_bytes = spec.original_report_path_at(pre_compaction_root).read_bytes()
        require(retired_node.get("original_report_path") == spec.original_report_rel, f"{spec.node_id}: original_report_path drifted")
        require(retired_node.get("archived_report_path") == spec.archive_report_rel, f"{spec.node_id}: archived_report_path drifted")
        require(retired_node.get("live_subsumer") == LIVE_SUBSUMER, f"{spec.node_id}: live_subsumer drifted")
        require(
            retired_node.get("transitive_chain") == list(spec.transitive_chain),
            f"{spec.node_id}: transitive_chain drifted",
        )
        require(retired_node.get("pre_merkle_root") == pre_root, f"{spec.node_id}: pre_merkle_root drifted")
        require(
            retired_node.get("pre_compaction_commit") == pre_commit,
            f"{spec.node_id}: pre_compaction_commit drifted",
        )
        require(
            retired_node.get("report_sha256") == archived_report_payload.get("report_sha256"),
            f"{spec.node_id}: report_sha256 drifted",
        )
        proof = retired_node.get("inclusion_proof")
        require(isinstance(proof, list), f"{spec.node_id}: inclusion_proof must be a list")
        require(
            verify_inclusion_proof(
                path=spec.original_report_rel,
                file_bytes=report_bytes,
                proof=proof,
                root_hex=pre_root,
            ),
            f"{spec.node_id}: inclusion proof failed",
        )
    git = find_command("git")
    env = git_process_env(os.environ.copy())
    if current_head_commit(git=git, env=env, repo_root=repo_root) == post_commit:
        require(
            merkle_root(active_report_entries(repo_root=repo_root)) == post_root,
            "receipt post_merkle_root does not match the active report set at post_compaction_commit",
        )
    print(f"compaction receipt verified: {display_path(receipt_path, repo_root=repo_root)}")
    return 0


def main() -> int:
    args = parse_args()
    env = git_process_env(os.environ.copy())
    git = find_command("git")
    if args.command == "apply":
        return apply_archive(
            git=git,
            env=env,
            repo_root=args.repo_root,
            pre_compaction_commit=args.pre_compaction_commit,
        )
    if args.command == "finalize-receipt":
        receipt_path = args.receipt or (args.repo_root / RECEIPT_PATH.relative_to(REPO_ROOT))
        return finalize_receipt(
            git=git,
            env=env,
            repo_root=args.repo_root,
            receipt_path=receipt_path,
            pre_compaction_commit=args.pre_compaction_commit,
            post_compaction_commit=args.post_compaction_commit,
        )
    if args.command == "verify-receipt":
        receipt_path = args.receipt or (args.repo_root / RECEIPT_PATH.relative_to(REPO_ROOT))
        return verify_receipt(
            receipt_path=receipt_path,
            repo_root=args.repo_root,
            pre_compaction_root=args.pre_compaction_root,
        )
    raise RuntimeError(f"unknown command {args.command}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, FileNotFoundError) as exc:
        print(f"compress_attestation_chain: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
