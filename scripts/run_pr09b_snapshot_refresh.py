#!/usr/bin/env python3
"""Run the PR09b snapshot refresh gate."""

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
from _lib.pr09_emit import (
    REPO_ROOT,
    compare_against_snapshot,
    ensure_emit_success,
    repo_arg,
    require_safec,
    run_emit,
)


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr09b-snapshot-refresh-report.json"
SNAPSHOTS = [
    (
        REPO_ROOT / "tests" / "positive" / "rule1_averaging.safe",
        REPO_ROOT / "tests" / "golden" / "golden_sensors",
    ),
    (
        REPO_ROOT / "tests" / "positive" / "ownership_move.safe",
        REPO_ROOT / "tests" / "golden" / "golden_ownership",
    ),
    (
        REPO_ROOT / "tests" / "positive" / "channel_pipeline.safe",
        REPO_ROOT / "tests" / "golden" / "golden_pipeline",
    ),
]
RETIRED_SNAPSHOTS = [
    REPO_ROOT / "tests" / "golden" / "golden_sensors.ada",
    REPO_ROOT / "tests" / "golden" / "golden_ownership.ada",
    REPO_ROOT / "tests" / "golden" / "golden_pipeline.ada",
]


def generate_report(*, safec: Path, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, object]:
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr09b-snap-") as temp_root:
        snapshots: list[dict[str, object]] = []
        for retired in RETIRED_SNAPSHOTS:
            require(not retired.exists(), f"retired snapshot still present: {display_path(retired, repo_root=REPO_ROOT)}")
        for source, golden_dir in SNAPSHOTS:
            root = temp_root / source.stem
            for name in ("out", "iface", "ada"):
                (root / name).mkdir(parents=True, exist_ok=True)
            run_emit(
                safec=safec,
                source=source,
                out_dir=root / "out",
                iface_dir=root / "iface",
                ada_dir=root / "ada",
                env=env,
                temp_root=temp_root,
            )
            ensure_emit_success(source=source, root=root)
            snapshots.append(
                {
                    "fixture": repo_arg(source),
                    "golden_dir": display_path(golden_dir, repo_root=REPO_ROOT),
                    "hashes": compare_against_snapshot(
                        actual_dir=root / "ada",
                        golden_dir=golden_dir,
                    ),
                }
            )
        return {
            "retired_snapshots_absent": [
                display_path(path, repo_root=REPO_ROOT) for path in RETIRED_SNAPSHOTS
            ],
            "snapshots": snapshots,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    safec = require_safec()
    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, env=env, scratch_root=args.scratch_root),
        label="PR09b snapshots",
    )
    write_report(args.report, report)
    print(f"pr09b snapshot refresh: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr09b snapshot refresh: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
