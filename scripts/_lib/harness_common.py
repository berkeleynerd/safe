"""Shared harness helpers for repository gate scripts."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MACOS_SDKROOT = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")


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
        if "=" in item:
            prefix, suffix = item.split("=", 1)
            candidate = Path(suffix)
            if candidate.is_absolute():
                if temp_root is not None and temp_root in candidate.parents:
                    normalized.append(prefix + "=$TMPDIR/" + str(candidate.relative_to(temp_root)))
                elif repo_root in candidate.parents:
                    normalized.append(prefix + "=" + str(candidate.relative_to(repo_root)))
                else:
                    normalized.append(prefix + "=" + candidate.name)
                continue
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
        return name
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
    env: dict[str, str],
    *,
    platform_name: str = sys.platform,
    xcrun_runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    fallback_sdkroot: Path = DEFAULT_MACOS_SDKROOT,
) -> dict[str, str]:
    if platform_name != "darwin" or env.get("SDKROOT"):
        return env
    try:
        xcrun = xcrun_runner(
            ["xcrun", "--show-sdk-path"],
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError:
        xcrun = None
    if xcrun is not None and xcrun.returncode == 0:
        discovered = xcrun.stdout.strip()
        if discovered:
            updated = env.copy()
            updated["SDKROOT"] = discovered
            return updated
    if fallback_sdkroot.exists():
        updated = env.copy()
        updated["SDKROOT"] = str(fallback_sdkroot)
        return updated
    return env


def read_diag_json(stdout: str, label: str) -> dict[str, Any]:
    payload = json.loads(stdout)
    require(payload.get("format") == "diagnostics-v0", f"{label}: unexpected diagnostics format")
    require(isinstance(payload.get("diagnostics"), list), f"{label}: diagnostics must be a list")
    return payload


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def stable_binary_sha256(path: Path) -> str:
    with tempfile.TemporaryDirectory(prefix="safec-binary-hash-") as temp_root_str:
        projected = Path(temp_root_str) / path.name
        shutil.copy2(path, projected)

        strip = shutil.which("strip")
        if strip is not None:
            # Fresh rebuilds can drift in debug/link metadata even when the
            # executable payload is stable. Compare a stripped copy first so
            # the gate proves reproducible runtime content rather than host-
            # specific debug bookkeeping.
            strip_run = subprocess.run(
                [strip, "-S", str(projected)],
                text=True,
                capture_output=True,
                check=False,
            )
            require(
                strip_run.returncode == 0,
                f"strip -S failed for {path}: {strip_run.stderr.strip()}",
            )

        if sys.platform == "darwin":
            # Mach-O links also carry an ad hoc signature that changes when the
            # stripped copy path changes. Remove it from the comparison copy.
            codesign = shutil.which("codesign")
            if codesign is not None:
                subprocess.run(
                    [codesign, "--remove-signature", str(projected)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )

        return sha256_file(projected)


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


def finalize_deterministic_report(
    generator: Callable[[], dict[str, Any]],
    *,
    label: str,
) -> dict[str, Any]:
    report = generator()
    repeat_report = generator()
    serialized = serialize_report(report)
    repeat_serialized = serialize_report(repeat_report)
    report_sha256 = sha256_text(serialized)
    repeat_sha256 = sha256_text(repeat_serialized)
    require(serialized == repeat_serialized, f"{label} report generation is non-deterministic")
    finalized = dict(report)
    finalized["deterministic"] = True
    finalized["report_sha256"] = report_sha256
    finalized["repeat_sha256"] = repeat_sha256
    return finalized


def rerun_report_gate_and_compare(
    *,
    python: str,
    script: Path,
    committed_report_path: Path,
    cwd: Path,
    env: dict[str, str] | None = None,
    temp_root: Path,
    repo_root: Path = REPO_ROOT,
) -> dict[str, Any]:
    temp_report_path = temp_root / committed_report_path.name
    result = run(
        [python, str(script), "--report", str(temp_report_path)],
        cwd=cwd,
        env=env,
        temp_root=temp_root,
        repo_root=repo_root,
    )
    require(committed_report_path.exists(), f"missing committed report: {committed_report_path}")
    require(temp_report_path.exists(), f"expected temp report at {temp_report_path}")

    committed_text = committed_report_path.read_text(encoding="utf-8")
    temp_text = temp_report_path.read_text(encoding="utf-8")
    committed_payload = json.loads(committed_text)
    temp_payload = json.loads(temp_text)

    require(
        committed_payload.get("deterministic") is True,
        f"{display_path(committed_report_path, repo_root=repo_root)}: expected deterministic committed report",
    )
    require(
        committed_payload.get("report_sha256") == committed_payload.get("repeat_sha256"),
        f"{display_path(committed_report_path, repo_root=repo_root)}: committed report hashes must match",
    )
    require(
        temp_payload.get("deterministic") is True,
        f"{display_path(temp_report_path, repo_root=repo_root)}: expected deterministic temp report",
    )
    require(
        temp_payload.get("report_sha256") == temp_payload.get("repeat_sha256"),
        f"{display_path(temp_report_path, repo_root=repo_root)}: temp report hashes must match",
    )
    require(
        temp_text == committed_text,
        f"{display_path(script, repo_root=repo_root)} rerun drifted from committed report "
        f"{display_path(committed_report_path, repo_root=repo_root)}",
    )
    return {
        "script": display_path(script, repo_root=repo_root),
        "committed_report_path": display_path(committed_report_path, repo_root=repo_root),
        "rerun": {
            "command": result["command"],
            "cwd": result["cwd"],
            "returncode": result["returncode"],
        },
        "matches_committed_report": True,
    }


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"Expected diagnostic output:\n-+\n(.*)\n-+\n", text, flags=re.DOTALL)
    if match:
        return match.group(1).rstrip() + "\n"
    raise RuntimeError(f"missing expected diagnostic output block in {path}")


def read_expected_reason(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^-- Expected:\s+REJECT\s+([a-z_]+)\s*$", text, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"missing expected reason header in {path}")
    return match.group(1)
