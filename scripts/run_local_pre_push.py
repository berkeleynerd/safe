#!/usr/bin/env python3
"""Run full local pre-push checks via the canonical gate pipeline."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from _lib.harness_common import ensure_deterministic_env, ensure_sdkroot, find_command, run
from run_gate_pipeline import EVIDENCE_POLICY, current_branch, verify_pipeline


REPO_ROOT = Path(__file__).resolve().parent.parent

# PR10.1 still audits these literal script paths in this file as part of the
# frozen local-workflow surface, even though execution now delegates to the
# canonical pipeline runner.
LEGACY_GATE_SNIPPETS = (
    "scripts/run_pr09_ada_emission_baseline.py",
    "scripts/run_pr104_gnatprove_evidence_parser_hardening.py",
    "scripts/run_pr101_comprehensive_audit.py",
    "scripts/run_pr103_sequential_proof_expansion.py",
    "scripts/run_pr106_sequential_proof_corpus_expansion.py",
    "scripts/run_pr111_language_evaluation_harness.py",
    "scripts/run_pr112_parser_completeness_phase1.py",
    "scripts/run_pr113_discriminated_types_tuples_structured_returns.py",
    "scripts/run_pr113a_proof_checkpoint1.py",
    "scripts/run_pr114_signature_control_flow_syntax.py",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--branch", help="override current branch detection")
    parser.add_argument("--dry-run", action="store_true", help="print the plan without executing it")
    parser.add_argument(
        "--skip-diff",
        action="store_true",
        help="skip the final git diff cleanliness check",
    )
    args, _extras = parser.parse_known_args()
    return args


def main() -> int:
    args = parse_args()
    env = ensure_deterministic_env(
        ensure_sdkroot(os.environ.copy()),
        required=EVIDENCE_POLICY["environment"]["required_env"],
    )
    git = find_command("git")
    python = find_command("python3")
    alr = find_command("alr", fallback=Path.home() / "bin" / "alr")
    branch = args.branch or current_branch(git=git, env=env)

    if args.dry_run:
        print(f"[pre-push] branch: {branch}")
        print("[pre-push] plan: full canonical gate pipeline verify (authority=local)")
        return 0

    print(f"[pre-push] branch: {branch}")
    verify_pipeline(authority="local", python=python, git=git, alr=alr, env=env)
    if not args.skip_diff:
        run([git, "diff", "--exit-code"], cwd=REPO_ROOT, env=env)
    print("[pre-push] local gate chain passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
