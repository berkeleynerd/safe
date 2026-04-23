#!/usr/bin/env python3
"""Run the Safe proof workflow in full prove or fast check mode."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from _lib.proof_eval import (
    ProofToolchain,
    prepare_proof_toolchain,
    prove_switches_for_level,
    run_cached_source_proof,
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
    PR11_11C_CHECKPOINT_FIXTURES,
    PR11_12A_CHECKPOINT_FIXTURES,
    PR11_12B_CHECKPOINT_FIXTURES,
    PR11_12C_CHECKPOINT_FIXTURES,
    PR11_12D_CHECKPOINT_FIXTURES,
    PR11_12E_CHECKPOINT_FIXTURES,
    PR11_12F_CHECKPOINT_FIXTURES,
    PR11_12_CHECKPOINT_FIXTURES,
    PR11_13A_CHECKPOINT_FIXTURES,
    PR11_13B_CHECKPOINT_FIXTURES,
    PR11_13C_CHECKPOINT_FIXTURES,
    PR11_13_CHECKPOINT_FIXTURES,
    PR11_16_CHECKPOINT_FIXTURES,
    PR11_23_PROOF_EXPANSION_FIXTURES,
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
    validate_manifest("PR11.11c checkpoint manifest", PR11_11C_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.12a checkpoint manifest", PR11_12A_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.12b checkpoint manifest", PR11_12B_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.12c checkpoint manifest", PR11_12C_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.12d checkpoint manifest", PR11_12D_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.12e checkpoint manifest", PR11_12E_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.12f checkpoint manifest", PR11_12F_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.12 checkpoint manifest", PR11_12_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.13a checkpoint manifest", PR11_13A_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.13b checkpoint manifest", PR11_13B_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.13c checkpoint manifest", PR11_13C_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.13 checkpoint manifest", PR11_13_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.16 checkpoint manifest", PR11_16_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.23 proof-expansion manifest", PR11_23_PROOF_EXPANSION_FIXTURES)
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


@dataclass
class GroupResult:
    proved: int = 0
    cached: int = 0
    failures: list[tuple[str, str]] = field(default_factory=list)


def combine_results(*results: GroupResult) -> GroupResult:
    combined = GroupResult()
    for result in results:
        combined.proved += result.proved
        combined.cached += result.cached
        combined.failures.extend(result.failures)
    return combined


def run_companion_project(
    *,
    project_dir: Path,
    project_file: str,
    toolchain: ProofToolchain,
    proof_mode: str,
    prove_switches: list[str] | None = None,
) -> tuple[bool, str]:
    return run_gnatprove_project(
        project_dir=project_dir,
        project_file=project_file,
        toolchain=toolchain,
        proof_mode=proof_mode,
        prove_switches=prove_switches,
    )


def print_summary(
    *,
    result: GroupResult,
    title: str | None = None,
    passed_label: str = "proved",
    trailing_blank_line: bool = False,
    show_cached: bool = False,
) -> None:
    prefix = f"{title}: " if title is not None else ""
    if show_cached:
        print(
            f"{prefix}{result.proved} {passed_label}, {result.cached} cached, "
            f"{len(result.failures)} failed"
        )
    else:
        print(f"{prefix}{result.proved} {passed_label}, {len(result.failures)} failed")
    if result.failures:
        print("Failures:")
        for label, detail in result.failures:
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
    proof_mode: str,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
    use_cache: bool = True,
) -> GroupResult:
    summary = GroupResult()

    action = "checking" if proof_mode == "check" else "proving"
    for fixture_rel in fixtures:
        print_progress(f"{action} {fixture_rel}")
        source = REPO_ROOT / fixture_rel
        if proof_mode == "prove" and use_cache:
            result = run_cached_source_proof(
                toolchain=toolchain,
                source=source,
                run_check=False,
                prove_switches=prove_switches,
                command_timeout=command_timeout,
            )
        else:
            result = run_source_proof(
                toolchain=toolchain,
                source=source,
                proof_root=temp_root / source.stem,
                run_check=False,
                proof_mode=proof_mode,
                prove_switches=prove_switches,
                command_timeout=command_timeout,
            )
        if result.passed:
            if result.used_cache:
                summary.cached += 1
            else:
                summary.proved += 1
        else:
            summary.failures.append((fixture_rel, result.detail))

    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("prove", "check"),
        default="prove",
        help="Run full proof (default) or fast legality-only gnatprove check.",
    )
    parser.add_argument(
        "--level",
        type=int,
        choices=(1, 2),
        default=1,
        help="GNATprove level for full prove mode (default: 1). Ignored in check mode.",
    )
    cache_group = parser.add_mutually_exclusive_group()
    cache_group.add_argument(
        "--cache",
        action="store_true",
        help="Reuse unchanged passing prove results. Enabled by default in prove mode and ignored in check mode.",
    )
    cache_group.add_argument(
        "--no-cache",
        action="store_true",
        help="Disable local proof-result reuse. Ignored in check mode.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    proof_mode = args.mode
    prove_switches = None if proof_mode == "check" else prove_switches_for_level(args.level)
    passed_label = "checked" if proof_mode == "check" else "proved"
    companion_action = "checking" if proof_mode == "check" else "proving"
    use_cache = proof_mode == "prove" and (args.cache or not args.no_cache)

    try:
        validate_manifests()
        toolchain = prepare_proof_toolchain(env=os.environ.copy())
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_proofs: ERROR: {exc}", file=sys.stderr)
        return 1

    if use_cache:
        print_progress("cache reuse enabled (--no-cache to disable)")

    companion_result = GroupResult()

    for project_rel, project_file in COMPANION_PROJECTS:
        project_dir = REPO_ROOT / project_rel
        print_progress(f"{companion_action} {project_rel}/{project_file}")
        ok, detail = run_companion_project(
            project_dir=project_dir,
            project_file=project_file,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
        )
        if ok:
            companion_result.proved += 1
        else:
            companion_result.failures.append((project_rel, detail))

    with tempfile.TemporaryDirectory(prefix="safe-proofs-") as temp_root_str:
        temp_root = Path(temp_root_str)
        checkpoint_a = run_fixture_group(
            fixtures=PR11_8A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_b = run_fixture_group(
            fixtures=PR11_8B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_e = run_fixture_group(
            fixtures=PR11_8E_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_f = run_fixture_group(
            fixtures=PR11_8F_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_g1 = run_fixture_group(
            fixtures=PR11_8G1_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_g2 = run_fixture_group(
            fixtures=PR11_8G2_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_i = run_fixture_group(
            fixtures=PR11_8I_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_i1 = run_fixture_group(
            fixtures=PR11_8I1_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_k = run_fixture_group(
            fixtures=PR11_8K_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_10a = run_fixture_group(
            fixtures=PR11_10A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_10b = run_fixture_group(
            fixtures=PR11_10B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_10c = run_fixture_group(
            fixtures=PR11_10C_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_11a = run_fixture_group(
            fixtures=PR11_11A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_11b = run_fixture_group(
            fixtures=PR11_11B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_11c = run_fixture_group(
            fixtures=PR11_11C_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_12a = run_fixture_group(
            fixtures=PR11_12A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_12b = run_fixture_group(
            fixtures=PR11_12B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_12c = run_fixture_group(
            fixtures=PR11_12C_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_12d = run_fixture_group(
            fixtures=PR11_12D_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_12e = run_fixture_group(
            fixtures=PR11_12E_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_12f = run_fixture_group(
            fixtures=PR11_12F_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_13a = run_fixture_group(
            fixtures=PR11_13A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_13b = run_fixture_group(
            fixtures=PR11_13B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_13c = run_fixture_group(
            fixtures=PR11_13C_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_16 = run_fixture_group(
            fixtures=PR11_16_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        checkpoint_23_expansion = run_fixture_group(
            fixtures=PR11_23_PROOF_EXPANSION_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )
        regression = run_fixture_group(
            fixtures=EMITTED_PROOF_REGRESSION_FIXTURES,
            temp_root=temp_root,
            toolchain=toolchain,
            proof_mode=proof_mode,
            prove_switches=prove_switches,
            use_cache=use_cache,
        )

    checkpoint_10d = combine_results(checkpoint_10a, checkpoint_10b, checkpoint_10c)
    checkpoint_12 = combine_results(
        checkpoint_12a,
        checkpoint_12b,
        checkpoint_12c,
        checkpoint_12d,
        checkpoint_12e,
        checkpoint_12f,
    )
    checkpoint_13 = combine_results(checkpoint_13a, checkpoint_13b, checkpoint_13c)
    total = combine_results(
        companion_result,
        checkpoint_a,
        checkpoint_b,
        checkpoint_e,
        checkpoint_f,
        checkpoint_g1,
        checkpoint_g2,
        checkpoint_i,
        checkpoint_i1,
        checkpoint_k,
        checkpoint_10a,
        checkpoint_10b,
        checkpoint_10c,
        checkpoint_11a,
        checkpoint_11b,
        checkpoint_11c,
        checkpoint_12a,
        checkpoint_12b,
        checkpoint_12c,
        checkpoint_12d,
        checkpoint_12e,
        checkpoint_12f,
        checkpoint_13a,
        checkpoint_13b,
        checkpoint_13c,
        checkpoint_16,
        checkpoint_23_expansion,
        regression,
    )
    show_cached = proof_mode == "prove"

    print_summary(
        result=companion_result,
        title="Companion baselines",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_a,
        title="PR11.8a checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_b,
        title="PR11.8b checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_e,
        title="PR11.8e checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_f,
        title="PR11.8f checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_g1,
        title="PR11.8g.1 checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_g2,
        title="PR11.8g.2 checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_i,
        title="PR11.8i checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_i1,
        title="PR11.8i.1 checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_k,
        title="PR11.8k checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_10a,
        title="PR11.10a checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_10b,
        title="PR11.10b checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_10c,
        title="PR11.10c checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_10d,
        title="PR11.10d checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_11a,
        title="PR11.11a checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_11b,
        title="PR11.11b checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_11c,
        title="PR11.11c checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_12a,
        title="PR11.12a checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_12b,
        title="PR11.12b checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_12c,
        title="PR11.12c checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_12d,
        title="PR11.12d checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_12e,
        title="PR11.12e checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_12f,
        title="PR11.12f checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_12,
        title="PR11.12 checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_13a,
        title="PR11.13a checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_13b,
        title="PR11.13b checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_13c,
        title="PR11.13c checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_13,
        title="PR11.13 checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_16,
        title="PR11.16 checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=checkpoint_23_expansion,
        title="PR11.23 proof-expansion checkpoint",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(
        result=regression,
        title="Emitted proof regressions",
        passed_label=passed_label,
        trailing_blank_line=True,
        show_cached=show_cached,
    )
    print_summary(result=total, passed_label=passed_label, show_cached=show_cached)
    return 0 if not total.failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
