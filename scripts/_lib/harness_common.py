"""Shared harness helpers for repository gate scripts."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]


def normalize_text(text: str, *, temp_root: Path | None = None, repo_root: Path = REPO_ROOT) -> str:
    result = text
    if temp_root is not None:
        result = result.replace(str(temp_root), "$TMPDIR")
    return result.replace(str(repo_root), "$REPO_ROOT")


def normalize_argv(
    argv: list[str], *, temp_root: Path | None = None, repo_root: Path = REPO_ROOT
) -> list[str]:
    normalized: list[str] = []
    for item in argv:
        candidate = Path(item)
        if candidate.is_absolute():
            if temp_root is not None and temp_root in candidate.parents:
                normalized.append("$TMPDIR/" + str(candidate.relative_to(temp_root)))
            elif repo_root in candidate.parents:
                normalized.append(str(candidate.relative_to(repo_root)))
            else:
                normalized.append(candidate.name)
        else:
            normalized.append(item)
    return normalized


def find_command(name: str, fallback: Path | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def require_repo_command(path: Path, name: str) -> Path:
    if path.exists():
        return path
    raise FileNotFoundError(f"required repo-local command not found: {name} at {path}")


def run(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    stdout_path: Path | None = None,
    temp_root: Path | None = None,
    expected_returncode: int = 0,
    repo_root: Path = REPO_ROOT,
) -> dict[str, Any]:
    if stdout_path is not None:
        stdout_path.parent.mkdir(parents=True, exist_ok=True)
        with stdout_path.open("w", encoding="utf-8") as handle:
            completed = subprocess.run(
                argv,
                cwd=cwd,
                env=env,
                text=True,
                stdout=handle,
                stderr=subprocess.PIPE,
                check=False,
            )
        stdout_text = stdout_path.read_text(encoding="utf-8")
    else:
        completed = subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        stdout_text = completed.stdout

    result = {
        "command": normalize_argv(argv, temp_root=temp_root, repo_root=repo_root),
        "cwd": normalize_text(str(cwd), temp_root=temp_root, repo_root=repo_root),
        "returncode": completed.returncode,
        "stdout": normalize_text(stdout_text, temp_root=temp_root, repo_root=repo_root),
        "stderr": normalize_text(completed.stderr, temp_root=temp_root, repo_root=repo_root),
    }
    if completed.returncode != expected_returncode:
        raise RuntimeError(json.dumps(result, indent=2))
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def ensure_sdkroot(
    env: dict[str, str], *, platform_name: str = sys.platform
) -> dict[str, str]:
    if platform_name != "darwin" or env.get("SDKROOT"):
        return env
    candidate = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
    if candidate.exists():
        updated = env.copy()
        updated["SDKROOT"] = str(candidate)
        return updated
    return env


def tool_versions(*, python: str | None = None, alr: str | None = None) -> dict[str, str]:
    versions: dict[str, str] = {}
    if python is not None:
        versions["python3"] = (
            subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stdout.strip()
            or subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stderr.strip()
        )
    if alr is not None:
        versions["alr"] = subprocess.run(
            [alr, "--version"], text=True, capture_output=True, check=False
        ).stdout.strip()
    gprbuild = shutil.which("gprbuild")
    if gprbuild:
        versions["gprbuild"] = (
            subprocess.run([gprbuild, "--version"], text=True, capture_output=True, check=False)
            .stdout.splitlines()[0]
        )
    return versions


def read_diag_json(stdout: str, label: str) -> dict[str, Any]:
    payload = json.loads(stdout)
    require(payload.get("format") == "diagnostics-v0", f"{label}: unexpected diagnostics format")
    require(isinstance(payload.get("diagnostics"), list), f"{label}: diagnostics must be a list")
    return payload


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def display_path(path: Path, *, repo_root: Path = REPO_ROOT) -> str:
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def serialize_report(report: dict[str, Any]) -> str:
    return json.dumps(report, indent=2, sort_keys=True) + "\n"


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(serialize_report(report), encoding="utf-8")


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"Expected diagnostic output:\n-+\n(.*)\n-+\n", text, flags=re.DOTALL)
    if not match:
        raise RuntimeError(f"could not extract expected block from {path}")
    return match.group(1).rstrip() + "\n"


def read_expected_reason(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^-- Expected:\s+REJECT\s+([a-z_]+)\s*$", text, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"missing expected reason header in {path}")
    return match.group(1)
