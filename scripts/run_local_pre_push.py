#!/usr/bin/env python3
"""Run branch-aware local pre-push checks for milestone branches."""

from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from _lib.harness_common import ensure_sdkroot, find_command, run


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"


@dataclass(frozen=True)
class Step:
    label: str
    argv: tuple[str, ...]
    cwd: Path


FOLLOWUP_SCRIPTS = (
    "scripts/run_pr09_ada_emission_baseline.py",
    "scripts/run_pr0694_output_contract_stability.py",
    "scripts/run_pr0697_gate_quality.py",
    "scripts/run_pr0699_build_reproducibility.py",
    "scripts/run_pr06910_portability_environment.py",
    "scripts/run_pr06911_glue_script_safety.py",
    "scripts/run_pr06913_documentation_architecture_clarity.py",
    "scripts/validate_execution_state.py",
)

PRIMARY_GATE_SCRIPTS = {
    "codex/pr081": ("scripts/run_pr081_local_concurrency_frontend.py",),
    "codex/pr082": ("scripts/run_pr082_local_concurrency_analysis.py",),
    "codex/pr083": ("scripts/run_pr083_interface_contracts.py",),
    "codex/pr083a": (
        "scripts/run_pr083_interface_contracts.py",
        "scripts/run_pr083a_public_constants.py",
    ),
    "codex/pr084": (
        "scripts/run_pr084_transitive_concurrency_integration.py",
        "scripts/run_pr08_frontend_baseline.py",
    ),
    "codex/pr09": ("scripts/run_pr09_ada_emission_baseline.py",),
    "codex/pr10": (
        "scripts/run_pr10_emitted_baseline.py",
        "scripts/run_emitted_hardening_regressions.py",
        "scripts/run_pr101_comprehensive_audit.py",
    ),
    "codex/pr101": ("scripts/run_pr101_comprehensive_audit.py",),
    "codex/pr102": (
        "scripts/run_pr102_rule5_boundary_closure.py",
        "scripts/run_pr10_contract_baseline.py",
        "scripts/run_pr101_comprehensive_audit.py",
    ),
    "codex/pr103": (
        "scripts/run_pr103_sequential_proof_expansion.py",
        "scripts/run_pr10_emitted_baseline.py",
        "scripts/run_pr101_comprehensive_audit.py",
    ),
    "codex/pr104": (
        "scripts/run_pr104_gnatprove_evidence_parser_hardening.py",
        "scripts/run_pr101_comprehensive_audit.py",
    ),
    "codex/pr105": (
        "scripts/run_pr105_ada_emitter_maintenance_hardening.py",
        "scripts/run_pr101_comprehensive_audit.py",
    ),
    "codex/pr106": (
        "scripts/run_pr106_sequential_proof_corpus_expansion.py",
        "scripts/run_pr101_comprehensive_audit.py",
    ),
}

PR11_FAMILY_GATE_SCRIPTS = (
    "scripts/run_frontend_smoke.py",
    "scripts/run_pr101_comprehensive_audit.py",
)


def current_branch(*, git: str, env: dict[str, str]) -> str:
    result = run(
        [git, "symbolic-ref", "--quiet", "--short", "HEAD"],
        cwd=REPO_ROOT,
        env=env,
    )
    branch = result["stdout"].strip()
    if not branch:
        raise RuntimeError("unable to determine current branch for local pre-push checks")
    return branch


def gate_scripts_for_branch(branch: str) -> tuple[str, ...]:
    for prefix, scripts in PRIMARY_GATE_SCRIPTS.items():
        if branch == prefix or branch.startswith(prefix + "-"):
            return scripts
    if branch.startswith("codex/pr11"):
        return PR11_FAMILY_GATE_SCRIPTS
    if branch.startswith("codex/pr08") or branch.startswith("codex/pr09") or branch.startswith("codex/pr10"):
        raise RuntimeError(
            f"{branch}: no local pre-push plan is defined yet; update scripts/run_local_pre_push.py"
        )
    return ()


def build_steps(
    *,
    branch: str,
    python: str,
    alr: str,
    git: str,
    include_diff: bool,
) -> list[Step]:
    gate_scripts = gate_scripts_for_branch(branch)
    if not gate_scripts:
        return []

    steps: list[Step] = [Step("Build compiler", (alr, "build"), COMPILER_ROOT)]
    for script in gate_scripts:
        steps.append(Step(f"Run {Path(script).name}", (python, script), REPO_ROOT))

    for script in FOLLOWUP_SCRIPTS[:3]:
        steps.append(Step(f"Run {Path(script).name}", (python, script), REPO_ROOT))

    steps.append(Step("Rebuild compiler after reproducibility gate", (alr, "build"), COMPILER_ROOT))

    for script in FOLLOWUP_SCRIPTS[3:]:
        steps.append(Step(f"Run {Path(script).name}", (python, script), REPO_ROOT))

    if include_diff:
        steps.append(
            Step(
                "Require clean tracked tree after local gates",
                (git, "diff", "--exit-code"),
                REPO_ROOT,
            )
        )
    return steps


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


def print_plan(branch: str, steps: Sequence[Step]) -> None:
    print(f"[pre-push] branch: {branch}")
    if not steps:
        print("[pre-push] no enforced local gate chain for this branch")
        return
    for index, step in enumerate(steps, start=1):
        command = " ".join(step.argv)
        print(f"[pre-push] {index}. {step.label}: (cd {step.cwd} && {command})")


def main() -> int:
    args = parse_args()
    env = ensure_sdkroot(os.environ.copy())
    python = find_command("python3")
    git = find_command("git")
    alr = find_command("alr", fallback=Path.home() / "bin" / "alr")

    branch = args.branch or current_branch(git=git, env=env)
    steps = build_steps(
        branch=branch,
        python=python,
        alr=alr,
        git=git,
        include_diff=not args.skip_diff,
    )
    print_plan(branch, steps)
    if args.dry_run or not steps:
        return 0

    for step in steps:
        print(f"[pre-push] running: {step.label}")
        run(list(step.argv), cwd=step.cwd, env=env)
    print("[pre-push] local gate chain passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
