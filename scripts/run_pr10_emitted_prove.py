#!/usr/bin/env python3
"""Run the PR10 emitted-output GNATprove prove gate."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    managed_scratch_root,
    require,
    write_report,
)
from _lib.proof_report import build_three_way_report, split_proof_fixtures
from _lib.pr10_emit import REPO_ROOT, compile_and_prove_fixture, corpus_paths


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr10-emitted-prove-report.json"


def generate_report(*, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, object]:
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr10-prove-") as temp_root:
        fixtures: list[dict[str, object]] = []
        for source in corpus_paths():
            fixture_root = temp_root / source.stem
            result = compile_and_prove_fixture(
                source=source,
                root=fixture_root,
                env=env,
                mode="prove",
            )
            summary = result["prove"]["summary"]["total"]  # type: ignore[index]
            require(
                summary["justified"]["count"] == 0,
                f"{source}: justified checks must be zero",
            )
            require(
                summary["unproved"]["count"] == 0,
                f"{source}: unproved checks must be zero",
            )
            fixtures.append(result)

        semantic_floor, canonical_fixtures, machine_fixtures = split_proof_fixtures(fixtures)
        return build_three_way_report(
            identity={},
            semantic_floor=semantic_floor,
            canonical_proof_detail={
                "fixtures": canonical_fixtures,
                "notes": [
                    "PR10 selected emitted outputs compile and pass GNATprove prove with all-proved-only semantics.",
                    "The prove gate treats warnings as errors and requires zero justified plus zero unproved checks.",
                ],
            },
            machine_sensitive={
                "fixtures": machine_fixtures,
            },
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env, scratch_root=args.scratch_root),
        label="PR10 emitted prove",
    )
    write_report(args.report, report)
    print(f"pr10 emitted prove: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr10 emitted prove: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
