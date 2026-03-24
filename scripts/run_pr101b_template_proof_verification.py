#!/usr/bin/env python3
"""Run the PR10.1 template proof verification child report."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from _lib.attestation_compression import RETIRED_ARCHIVE_REPORT_PATHS
from _lib.harness_common import display_path, ensure_sdkroot, finalize_deterministic_report, write_report
from _lib.pr09_emit import REPO_ROOT
from _lib.pr101_verification import build_verification_report, run_templates_verify


DEFAULT_REPORT = RETIRED_ARCHIVE_REPORT_PATHS["pr101b_template_proof_verification"]


def generate_report(*, env: dict[str, str]) -> dict[str, object]:
    return build_verification_report(
        task="PR10.1",
        verification="templates",
        group=run_templates_verify(env=env),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env),
        label="PR10.1 template proof verification",
    )
    write_report(args.report, report)
    print(f"pr101b template proof verification: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr101b template proof verification: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
