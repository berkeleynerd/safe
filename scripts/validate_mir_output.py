#!/usr/bin/env python3
"""Deprecated compatibility wrapper for `safec validate-mir`."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"


def find_safec() -> str:
    candidate = COMPILER_ROOT / "bin" / "safec"
    if candidate.exists():
        return str(candidate)
    found = shutil.which("safec")
    if found:
        return found
    raise FileNotFoundError(f"missing safec binary at {candidate}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mir_json", type=Path)
    args = parser.parse_args()

    print(
        "validate_mir_output.py is deprecated; use `safec validate-mir <file.mir.json>` "
        "directly. See companion/release/frontend_runtime_decision.md for the staged runtime plan.",
        file=sys.stderr,
    )

    completed = subprocess.run(
        [find_safec(), "validate-mir", str(args.mir_json)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    return completed.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FileNotFoundError as exc:
        print(f"validate_mir_output: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
