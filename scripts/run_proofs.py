#!/usr/bin/env python3
"""Run the live all-proved-only Safe proof workflow."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

from _lib.proof_eval import (
    ProofToolchain,
    prepare_proof_toolchain,
    run_gnatprove_project,
    run_source_proof,
)
from _lib.proof_inventory import (
    COMPANION_PROJECTS,
    EMITTED_PROOF_EXCLUSIONS,
    EMITTED_PROOF_FIXTURES,
    EMITTED_PROOF_REGRESSION_FIXTURES,
    PR11_8A_CHECKPOINT_FIXTURES,
    PR11_8B_CHECKPOINT_FIXTURES,
    PR11_8E_CHECKPOINT_FIXTURES,
    PR11_8F_CHECKPOINT_FIXTURES,
    PR11_8G1_CHECKPOINT_FIXTURES,
    PR11_8G2_CHECKPOINT_FIXTURES,
    PR11_8I_CHECKPOINT_FIXTURES,
    PR11_8I1_CHECKPOINT_FIXTURES,
    PR11_8K_CHECKPOINT_FIXTURES,
    PR11_10A_CHECKPOINT_FIXTURES,
    PR11_10B_CHECKPOINT_FIXTURES,
    PR11_10C_CHECKPOINT_FIXTURES,
    PR11_10D_CHECKPOINT_FIXTURES,
    PR11_11A_CHECKPOINT_FIXTURES,
    PR11_11B_CHECKPOINT_FIXTURES,
    PROOF_COVERAGE_ROOTS,
    iter_proof_coverage_paths,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def validate_manifest(
    name: str,
    entries: list[str],
    *,
    allow_missing: bool = False,
) -> None:
    seen: set[str] = set()
    duplicates: list[str] = []
    missing: list[str] = []

    for entry in entries:
        if entry in seen:
            duplicates.append(entry)
        else:
            seen.add(entry)
        if not allow_missing and not (REPO_ROOT / entry).exists():
            missing.append(entry)

    if duplicates:
        raise RuntimeError(f"{name} has duplicate entries: {', '.join(duplicates)}")
    if missing:
        raise RuntimeError(f"{name} has missing entries: {', '.join(missing)}")


def validate_manifests() -> None:
    validate_manifest("PR11.8a checkpoint manifest", PR11_8A_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8b checkpoint manifest", PR11_8B_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8e checkpoint manifest", PR11_8E_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8f checkpoint manifest", PR11_8F_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8g.1 checkpoint manifest", PR11_8G1_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8g.2 checkpoint manifest", PR11_8G2_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8i checkpoint manifest", PR11_8I_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8i.1 checkpoint manifest", PR11_8I1_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8k checkpoint manifest", PR11_8K_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.10a checkpoint manifest", PR11_10A_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.10b checkpoint manifest", PR11_10B_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.10c checkpoint manifest", PR11_10C_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.10d checkpoint manifest", PR11_10D_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.11a checkpoint manifest", PR11_11A_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.11b checkpoint manifest", PR11_11B_CHECKPOINT_FIXTURES)
    validate_manifest("emitted proof regression manifest", EMITTED_PROOF_REGRESSION_FIXTURES)
    validate_manifest("emitted proof manifest", EMITTED_PROOF_FIXTURES)
    validate_manifest(
        "emitted proof exclusion inventory",
        [entry.path for entry in EMITTED_PROOF_EXCLUSIONS],
    )

    missing_metadata = [
        entry.path
        for entry in EMITTED_PROOF_EXCLUSIONS
        if not entry.reason or not entry.owner or not entry.milestone
    ]
    if missing_metadata:
        raise RuntimeError(
            "emitted proof exclusions missing reason/owner/milestone metadata: "
            + ", ".join(missing_metadata)
        )

    managed = set(EMITTED_PROOF_FIXTURES)
    exclusions = {entry.path for entry in EMITTED_PROOF_EXCLUSIONS}
    overlap = sorted(managed & exclusions)
    if overlap:
        raise RuntimeError(
            "emitted proof fixtures also listed as exclusions: " + ", ".join(overlap)
        )

    covered = managed | exclusions
    uncovered = [
        entry
        for entry in iter_proof_coverage_paths(REPO_ROOT)
        if entry not in covered
    ]
    if uncovered:
        detail = ", ".join(uncovered)
        raise RuntimeError(
            "proof coverage inventory leaves uncovered fixtures under "
            + ", ".join(PROOF_COVERAGE_ROOTS)
            + ": "
            + detail
        )

def run_companion_project(
    *,
    project_dir: Path,
    project_file: str,
    toolchain: ProofToolchain,
) -> tuple[bool, str]:
    return run_gnatprove_project(
        project_dir=project_dir,
        project_file=project_file,
        toolchain=toolchain,
    )


def print_summary(
    *,
    passed: int,
    failures: list[tuple[str, str]],
    title: str | None = None,
    trailing_blank_line: bool = False,
) -> None:
    prefix = f"{title}: " if title is not None else ""
    print(f"{prefix}{passed} proved, {len(failures)} failed")
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")
    if trailing_blank_line:
        print()


def print_progress(message: str) -> None:
    print(f"[run_proofs] {message}", flush=True)


def run_fixture_group(
    *,
    fixtures: list[str],
    temp_root: Path,
    toolchain: ProofToolchain,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
) -> tuple[int, list[tuple[str, str]]]:
    passed = 0
    failures: list[tuple[str, str]] = []

    for fixture_rel in fixtures:
        print_progress(f"proving {fixture_rel}")
        source = REPO_ROOT / fixture_rel
        result = run_source_proof(
            toolchain=toolchain,
            source=source,
            proof_root=temp_root / source.stem,
            run_check=False,
            prove_switches=prove_switches,
            command_timeout=command_timeout,
        )
        if result.passed:
            passed += 1
        else:
            failures.append((fixture_rel, result.detail))

    return passed, failures


def main() -> int:
    try:
        validate_manifests()
        toolchain = prepare_proof_toolchain(env=os.environ.copy())
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_proofs: ERROR: {exc}", file=sys.stderr)
        return 1

    companion_passed = 0
    companion_failures: list[tuple[str, str]] = []
    checkpoint_a_passed = 0
    checkpoint_a_failures: list[tuple[str, str]] = []
    checkpoint_b_passed = 0
    checkpoint_b_failures: list[tuple[str, str]] = []
    checkpoint_e_passed = 0
    checkpoint_e_failures: list[tuple[str, str]] = []
    checkpoint_f_passed = 0
    checkpoint_f_failures: list[tuple[str, str]] = []
    checkpoint_g1_passed = 0
    checkpoint_g1_failures: list[tuple[str, str]] = []
    checkpoint_g2_passed = 0
    checkpoint_g2_failures: list[tuple[str, str]] = []
    checkpoint_i_passed = 0
    checkpoint_i_failures: list[tuple[str, str]] = []
    checkpoint_i1_passed = 0
    checkpoint_i1_failures: list[tuple[str, str]] = []
    checkpoint_k_passed = 0
    checkpoint_k_failures: list[tuple[str, str]] = []
    checkpoint_10a_passed = 0
    checkpoint_10a_failures: list[tuple[str, str]] = []
    checkpoint_10b_passed = 0
    checkpoint_10b_failures: list[tuple[str, str]] = []
    checkpoint_10c_passed = 0
    checkpoint_10c_failures: list[tuple[str, str]] = []
    checkpoint_10d_passed = 0
    checkpoint_10d_failures: list[tuple[str, str]] = []
    checkpoint_11a_passed = 0
    checkpoint_11a_failures: list[tuple[str, str]] = []
    checkpoint_11b_passed = 0
    checkpoint_11b_failures: list[tuple[str, str]] = []
    regression_passed = 0
    regression_failures: list[tuple[str, str]] = []

    for project_rel, project_file in COMPANION_PROJECTS:
        project_dir = REPO_ROOT / project_rel
        print_progress(f"proving {project_rel}/{project_file}")
        ok, detail = run_companion_project(
            project_dir=project_dir,
            project_file=project_file,
            toolchain=toolchain,
        )
        if ok:
            companion_passed += 1
        else:
            companion_failures.append((project_rel, detail))

    with tempfile.TemporaryDirectory(prefix="safe-proofs-") as temp_root_str:
        temp_root = Path(temp_root_str)
        checkpoint_a_passed, checkpoint_a_failures = run_fixture_group(
            fixtures=PR11_8A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_b_passed, checkpoint_b_failures = run_fixture_group(
            fixtures=PR11_8B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_e_passed, checkpoint_e_failures = run_fixture_group(
            fixtures=PR11_8E_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_f_passed, checkpoint_f_failures = run_fixture_group(
            fixtures=PR11_8F_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_g1_passed, checkpoint_g1_failures = run_fixture_group(
            fixtures=PR11_8G1_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_g2_passed, checkpoint_g2_failures = run_fixture_group(
            fixtures=PR11_8G2_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_i_passed, checkpoint_i_failures = run_fixture_group(
            fixtures=PR11_8I_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_i1_passed, checkpoint_i1_failures = run_fixture_group(
            fixtures=PR11_8I1_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_k_passed, checkpoint_k_failures = run_fixture_group(
            fixtures=PR11_8K_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_10a_passed, checkpoint_10a_failures = run_fixture_group(
            fixtures=PR11_10A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_10b_passed, checkpoint_10b_failures = run_fixture_group(
            fixtures=PR11_10B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_10c_passed, checkpoint_10c_failures = run_fixture_group(
            fixtures=PR11_10C_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_11a_passed, checkpoint_11a_failures = run_fixture_group(
            fixtures=PR11_11A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        checkpoint_11b_passed, checkpoint_11b_failures = run_fixture_group(
            fixtures=PR11_11B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )
        regression_passed, regression_failures = run_fixture_group(
            fixtures=EMITTED_PROOF_REGRESSION_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
        )

    checkpoint_10d_passed = (
        checkpoint_10a_passed + checkpoint_10b_passed + checkpoint_10c_passed
    )
    checkpoint_10d_failures = (
        checkpoint_10a_failures + checkpoint_10b_failures + checkpoint_10c_failures
    )

    total_passed = (
        companion_passed
        + checkpoint_a_passed
        + checkpoint_b_passed
        + checkpoint_e_passed
        + checkpoint_f_passed
        + checkpoint_g1_passed
        + checkpoint_g2_passed
        + checkpoint_i_passed
        + checkpoint_i1_passed
        + checkpoint_k_passed
        + checkpoint_10a_passed
        + checkpoint_10b_passed
        + checkpoint_10c_passed
        + checkpoint_11a_passed
        + checkpoint_11b_passed
        + regression_passed
    )
    total_failures = (
        companion_failures
        + checkpoint_a_failures
        + checkpoint_b_failures
        + checkpoint_e_failures
        + checkpoint_f_failures
        + checkpoint_g1_failures
        + checkpoint_g2_failures
        + checkpoint_i_failures
        + checkpoint_i1_failures
        + checkpoint_k_failures
        + checkpoint_10a_failures
        + checkpoint_10b_failures
        + checkpoint_10c_failures
        + checkpoint_11a_failures
        + checkpoint_11b_failures
        + regression_failures
    )

    print_summary(
        passed=companion_passed,
        failures=companion_failures,
        title="Companion baselines",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_a_passed,
        failures=checkpoint_a_failures,
        title="PR11.8a checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_b_passed,
        failures=checkpoint_b_failures,
        title="PR11.8b checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_e_passed,
        failures=checkpoint_e_failures,
        title="PR11.8e checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_f_passed,
        failures=checkpoint_f_failures,
        title="PR11.8f checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_g1_passed,
        failures=checkpoint_g1_failures,
        title="PR11.8g.1 checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_g2_passed,
        failures=checkpoint_g2_failures,
        title="PR11.8g.2 checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_i_passed,
        failures=checkpoint_i_failures,
        title="PR11.8i checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_i1_passed,
        failures=checkpoint_i1_failures,
        title="PR11.8i.1 checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_k_passed,
        failures=checkpoint_k_failures,
        title="PR11.8k checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_10a_passed,
        failures=checkpoint_10a_failures,
        title="PR11.10a checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_10b_passed,
        failures=checkpoint_10b_failures,
        title="PR11.10b checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_10c_passed,
        failures=checkpoint_10c_failures,
        title="PR11.10c checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_10d_passed,
        failures=checkpoint_10d_failures,
        title="PR11.10d checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_11a_passed,
        failures=checkpoint_11a_failures,
        title="PR11.11a checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_11b_passed,
        failures=checkpoint_11b_failures,
        title="PR11.11b checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=regression_passed,
        failures=regression_failures,
        title="Emitted proof regressions",
        trailing_blank_line=True,
    )
    print_summary(passed=total_passed, failures=total_failures)
    return 0 if not total_failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
