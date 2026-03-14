#!/usr/bin/env python3
"""Run the PR10 emitted-output GNATprove prove gate."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    require,
    write_report,
)
from _lib.pr10_emit import REPO_ROOT, compile_and_prove_fixture, corpus_paths


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr10-emitted-prove-report.json"


def generate_report(*, env: dict[str, str]) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="pr10-prove-") as temp_root_str:
        temp_root = Path(temp_root_str)
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

        return {
            "fixtures": fixtures,
            "notes": [
                "PR10 selected emitted outputs compile and pass GNATprove prove with all-proved-only semantics.",
                "The prove gate treats warnings as errors and requires zero justified plus zero unproved checks.",
            ],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env),
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
