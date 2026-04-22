#!/usr/bin/env python3
"""Install the repo-tracked Git hooks via ``core.hooksPath``."""

from __future__ import annotations

import stat
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
HOOKS_DIR = REPO_ROOT / ".githooks"
PRE_PUSH_HOOK = HOOKS_DIR / "pre-push"
LEGACY_PRE_PUSH = REPO_ROOT / ".git" / "hooks" / "pre-push"
TRACKED_HOOKS_PATH = ".githooks"


def run_git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def ensure_hook_executable(path: Path) -> None:
    mode = path.stat().st_mode
    execute_bits = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    path.chmod(mode | execute_bits)


def main() -> int:
    if not PRE_PUSH_HOOK.exists():
        print(
            f"install_git_hooks: missing tracked hook template at {PRE_PUSH_HOOK}",
            file=sys.stderr,
        )
        return 1

    try:
        ensure_hook_executable(PRE_PUSH_HOOK)
    except OSError as exc:
        print(
            f"install_git_hooks: unable to mark tracked hook executable at {PRE_PUSH_HOOK}: {exc}",
            file=sys.stderr,
        )
        return 1

    try:
        current = run_git("config", "--get", "core.hooksPath")
    except OSError as exc:
        print(f"install_git_hooks: unable to run git config: {exc}", file=sys.stderr)
        return 1
    if current.returncode not in (0, 1):
        message = current.stderr.strip() or current.stdout.strip() or "git config failed"
        print(f"install_git_hooks: {message}", file=sys.stderr)
        return 1

    current_path = current.stdout.strip()
    if LEGACY_PRE_PUSH.exists():
        print(
            "install_git_hooks: note: .git/hooks/pre-push will be bypassed in favor of "
            ".githooks/pre-push; if you had personal content there, compose it in your own wrapper.",
        )
    if current_path == TRACKED_HOOKS_PATH:
        print("install_git_hooks: core.hooksPath already set to .githooks")
        return 0

    try:
        configured = run_git("config", "core.hooksPath", TRACKED_HOOKS_PATH)
    except OSError as exc:
        print(f"install_git_hooks: unable to set core.hooksPath: {exc}", file=sys.stderr)
        return 1
    if configured.returncode != 0:
        message = configured.stderr.strip() or configured.stdout.strip() or "git config failed"
        print(f"install_git_hooks: {message}", file=sys.stderr)
        return 1

    print("install_git_hooks: configured core.hooksPath=.githooks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
