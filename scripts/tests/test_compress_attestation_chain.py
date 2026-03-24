from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from _lib.attestation_compression import RECEIPT_PATH, RETIRED_NODE_SPECS
from _lib.harness_common import ensure_deterministic_env
import compress_attestation_chain


def write_sample_report(path: Path, *, report_sha256: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "deterministic": True,
                "report_sha256": report_sha256,
                "repeat_sha256": report_sha256,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


class CompressAttestationChainTests(unittest.TestCase):
    def git(self, repo_root: Path, *args: str) -> str:
        completed = subprocess.run(
            ["git", *args],
            cwd=repo_root,
            check=True,
            text=True,
            capture_output=True,
        )
        return completed.stdout.strip()

    def init_repo(self, repo_root: Path) -> str:
        self.git(repo_root, "init")
        self.git(repo_root, "config", "user.name", "Codex")
        self.git(repo_root, "config", "user.email", "codex@example.com")
        for index, spec in enumerate(RETIRED_NODE_SPECS, start=1):
            write_sample_report(
                repo_root / spec.original_report_rel,
                report_sha256=f"{index:064x}"[-64:],
            )
        write_sample_report(
            repo_root / "execution" / "reports" / "pr101-comprehensive-audit-report.json",
            report_sha256="a" * 64,
        )
        self.git(repo_root, "add", "-A")
        self.git(repo_root, "commit", "-m", "pre-compaction baseline")
        return self.git(repo_root, "rev-parse", "HEAD")

    def test_apply_archive_moves_reports_and_writes_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            pre_commit = self.init_repo(repo_root)
            env = ensure_deterministic_env(os.environ.copy())

            result = compress_attestation_chain.apply_archive(
                git="git",
                env=env,
                repo_root=repo_root,
                pre_compaction_commit=pre_commit,
            )

            self.assertEqual(result, 0)
            sample = RETIRED_NODE_SPECS[0]
            self.assertFalse((repo_root / sample.original_report_rel).exists())
            archived_report = repo_root / sample.archive_report_rel
            archived_provenance = repo_root / sample.archive_provenance_rel
            self.assertTrue(archived_report.exists())
            self.assertTrue(archived_provenance.exists())
            provenance = json.loads(archived_provenance.read_text(encoding="utf-8"))
            self.assertEqual(provenance["node_id"], sample.node_id)
            self.assertEqual(provenance["original_report_path"], sample.original_report_rel)
            self.assertEqual(provenance["archived_report_path"], sample.archive_report_rel)
            self.assertEqual(provenance["pre_compaction_commit"], pre_commit)
            self.assertEqual(len(provenance["inclusion_proof"]), 5)

    def test_finalize_and_verify_receipt_supports_alternate_repo_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            pre_commit = self.init_repo(repo_root)
            env = ensure_deterministic_env(os.environ.copy())

            compress_attestation_chain.apply_archive(
                git="git",
                env=env,
                repo_root=repo_root,
                pre_compaction_commit=pre_commit,
            )
            self.git(repo_root, "add", "-A")
            self.git(repo_root, "commit", "-m", "compress attestation chain")
            post_commit = self.git(repo_root, "rev-parse", "HEAD")

            receipt_path = repo_root / RECEIPT_PATH.relative_to(compress_attestation_chain.REPO_ROOT)
            result = compress_attestation_chain.finalize_receipt(
                git="git",
                env=env,
                repo_root=repo_root,
                receipt_path=receipt_path,
                pre_compaction_commit=pre_commit,
                post_compaction_commit=post_commit,
            )

            self.assertEqual(result, 0)
            payload = json.loads(receipt_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["pre_compaction_commit"], pre_commit)
            self.assertEqual(payload["post_compaction_commit"], post_commit)
            self.assertEqual(len(payload["retired_nodes"]), len(RETIRED_NODE_SPECS))

            verify_result = compress_attestation_chain.verify_receipt(
                receipt_path=receipt_path,
                repo_root=repo_root,
            )
            self.assertEqual(verify_result, 0)

    def test_verify_receipt_rejects_tampered_post_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            pre_commit = self.init_repo(repo_root)
            env = ensure_deterministic_env(os.environ.copy())

            compress_attestation_chain.apply_archive(
                git="git",
                env=env,
                repo_root=repo_root,
                pre_compaction_commit=pre_commit,
            )
            self.git(repo_root, "add", "-A")
            self.git(repo_root, "commit", "-m", "compress attestation chain")
            post_commit = self.git(repo_root, "rev-parse", "HEAD")

            receipt_path = repo_root / RECEIPT_PATH.relative_to(compress_attestation_chain.REPO_ROOT)
            compress_attestation_chain.finalize_receipt(
                git="git",
                env=env,
                repo_root=repo_root,
                receipt_path=receipt_path,
                pre_compaction_commit=pre_commit,
                post_compaction_commit=post_commit,
            )
            payload = json.loads(receipt_path.read_text(encoding="utf-8"))
            payload["post_merkle_root"] = "0" * 64
            receipt_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

            with self.assertRaises(RuntimeError):
                compress_attestation_chain.verify_receipt(
                    receipt_path=receipt_path,
                    repo_root=repo_root,
                )
