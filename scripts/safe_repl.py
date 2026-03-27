#!/usr/bin/env python3
"""Single-file Safe REPL prototype for packageless entry units."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from _lib.harness_common import ensure_sdkroot
from _lib.pr111_language_eval import (
    COMPILER_ROOT,
    ensure_safe_build_executable,
    prepare_safe_build_root,
    safe_build_command,
    safec_path,
    write_safe_build_support_files,
)


TASK_RE = re.compile(r"^\s*task\b")


def run_command(argv: list[str], *, cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def first_message(completed: subprocess.CompletedProcess[str]) -> str:
    for stream in (completed.stderr, completed.stdout):
        for line in stream.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped
    return f"exit code {completed.returncode}"


def compile_and_run(
    *,
    safec: Path,
    env: dict[str, str],
    source: Path,
) -> tuple[bool, str]:
    paths = prepare_safe_build_root(source)
    source_text = source.read_text(encoding="utf-8")

    check = run_command([str(safec), "check", str(source)], cwd=COMPILER_ROOT.parent, env=env)
    if check.returncode != 0:
        return False, check.stderr or first_message(check)

    emit = run_command(
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
        cwd=COMPILER_ROOT.parent,
        env=env,
    )
    if emit.returncode != 0:
        return False, emit.stderr or first_message(emit)

    write_safe_build_support_files(paths)
    build = run_command(safe_build_command(paths), cwd=COMPILER_ROOT, env=env)
    if build.returncode != 0:
        return False, build.stderr or first_message(build)

    executable = ensure_safe_build_executable(paths)
    run = run_command([str(executable)], cwd=paths["root"], env=env)
    if run.returncode != 0:
        detail = run.stderr or run.stdout or first_message(run)
        return False, detail

    del source_text
    return True, run.stdout


def main() -> int:
    env = ensure_sdkroot(os.environ.copy())
    try:
        safec = safec_path()
    except Exception as exc:  # pragma: no cover - CLI setup path
        print(f"safe repl: ERROR: {exc}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="safe-repl-") as temp_dir:
        work_root = Path(temp_dir)
        source = work_root / "repl.safe"
        committed: list[str] = []

        for raw_line in sys.stdin:
            line = raw_line.rstrip("\n")
            stripped = line.strip()
            if not stripped:
                continue
            if TASK_RE.match(line):
                print("safe repl: task declarations are not supported in repl mode", file=sys.stderr)
                continue

            candidate = committed + [line]
            source.write_text("\n".join(candidate) + "\n", encoding="utf-8")
            ok, output = compile_and_run(safec=safec, env=env, source=source)
            if ok:
                committed = candidate
                if output:
                    print(output, end="")
            else:
                print(output.rstrip("\n"), file=sys.stderr)
                if committed:
                    source.write_text("\n".join(committed) + "\n", encoding="utf-8")
                else:
                    source.write_text("", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
