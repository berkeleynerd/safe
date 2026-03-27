#!/usr/bin/env python3
"""Repo-local prototype `safe` CLI for PR11.1."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

from _lib.harness_common import ensure_sdkroot, run_passthrough
from _lib.pr111_language_eval import (
    COMPILER_ROOT,
    REPO_ROOT,
    ensure_safe_build_executable,
    prepare_safe_build_root,
    repo_rel_or_abs,
    require_source_file,
    resolve_source_arg,
    safe_build_command,
    safec_path,
    write_safe_build_support_files,
)


USAGE = """usage:
  safe build <file.safe>
  safe check <safec check args...>
  safe emit  <safec emit args...>
"""


def print_usage(stream: object = sys.stderr) -> int:
    print(USAGE, file=stream, end="")
    return 2


def run_subprocess(argv: list[str], *, cwd: Path, env: dict[str, str]) -> int:
    return run_passthrough(argv, cwd=cwd, env=env)


def source_has_leading_with_clause(source: Path) -> bool:
    with source.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("--"):
                continue
            return bool(re.match(r"with\b", line))
    return False


def pass_through(command: str, args: list[str]) -> int:
    env = ensure_sdkroot(os.environ.copy())
    safec = safec_path()
    return run_subprocess([str(safec), command, *args], cwd=Path.cwd(), env=env)


def safe_build(source_arg: str) -> int:
    env = ensure_sdkroot(os.environ.copy())
    safec = safec_path()
    source = require_source_file(resolve_source_arg(source_arg))
    if source_has_leading_with_clause(source):
        print(
            "safe build: root files with `with` clauses are not supported yet; "
            "use `safec emit` plus manual `gprbuild` for multi-file programs",
            file=sys.stderr,
        )
        return 1
    paths = prepare_safe_build_root(source)

    check_code = run_subprocess([str(safec), "check", str(source)], cwd=REPO_ROOT, env=env)
    if check_code != 0:
        return check_code

    emit_code = run_subprocess(
        [
            str(safec),
            "emit",
            str(source),
            "--out-dir",
            str(paths["out"]),
            "--interface-dir",
            str(paths["iface"]),
            "--ada-out-dir",
            str(paths["ada"]),
        ],
        cwd=REPO_ROOT,
        env=env,
    )
    if emit_code != 0:
        return emit_code

    write_safe_build_support_files(paths)
    build_code = run_subprocess(safe_build_command(paths), cwd=COMPILER_ROOT, env=env)
    if build_code != 0:
        return build_code

    executable = ensure_safe_build_executable(paths)
    print(f"safe build: OK ({repo_rel_or_abs(executable)})")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        return print_usage(sys.stderr)
    if args[0] in {"-h", "--help"}:
        print(USAGE, file=sys.stdout, end="")
        return 0

    command = args[0]
    if command == "build":
        if len(args) != 2:
            return print_usage()
        return safe_build(args[1])
    if command in {"check", "emit"}:
        if len(args) < 2:
            return print_usage()
        return pass_through(command, args[1:])
    return print_usage()


if __name__ == "__main__":
    raise SystemExit(main())
