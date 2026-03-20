"""Shared harness helpers for repository gate scripts."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Callable


REPO_ROOT = Path(__file__).resolve().parents[2]
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_MACOS_SDKROOT = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
EVIDENCE_POLICY_PATH = REPO_ROOT / "execution" / "evidence_policy.json"


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


def require_safec() -> Path:
    return require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")


def compiler_build_argv(alr: str) -> list[str]:
    # Keep Alire's workspace/config generation, but force gprbuild itself to
    # run serially to avoid occasional corrupt dependency archives on macOS.
    return [alr, "build", "--", "-j1", "-p"]


def ensure_deterministic_env(
    env: dict[str, str],
    *,
    required: dict[str, str] | None = None,
) -> dict[str, str]:
    updated = env.copy()
    policy_required = required or {
        "PYTHONHASHSEED": "0",
        "LC_ALL": "C.UTF-8",
        "TZ": "UTC",
    }
    for key, value in policy_required.items():
        updated.setdefault(key, value)
    return updated


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


def run_capture(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def run_passthrough(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
) -> int:
    completed = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        check=False,
    )
    return completed.returncode


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


def load_evidence_policy(path: Path = EVIDENCE_POLICY_PATH) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), f"{path}: evidence policy root must be an object")
    return payload


def evidence_policy_sha256(payload: dict[str, Any]) -> str:
    return sha256_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def policy_metadata(
    *,
    policy_sha256: str,
    sections: list[str],
) -> dict[str, Any]:
    return {
        "policy_sha256": policy_sha256,
        "policy_sections_used": sections,
    }


def generated_output_paths(policy: dict[str, Any]) -> tuple[Path, Path]:
    outputs = policy["generated_outputs"]
    return Path(outputs["reports_root"]), Path(outputs["dashboard"])


def resolve_generated_path(
    path: Path,
    *,
    generated_root: Path | None,
    policy: dict[str, Any],
    repo_root: Path = REPO_ROOT,
) -> Path:
    if generated_root is None:
        return path
    try:
        relative = path.relative_to(repo_root)
    except ValueError:
        return path
    reports_root, dashboard_path = generated_output_paths(policy)
    if relative == dashboard_path or reports_root in relative.parents:
        return generated_root / relative
    return path


def display_path(path: Path, *, repo_root: Path = REPO_ROOT) -> str:
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def normalize_source_text(text: str) -> str:
    return " ".join(text.split())


def normalized_source_fragments(
    item: dict[str, Any],
    *,
    key: str = "source_fragments",
) -> tuple[str, ...]:
    return tuple(normalize_source_text(fragment) for fragment in item[key])


def assert_text_fragments(*, text: str, fragments: list[str], label: str) -> list[str]:
    for fragment in fragments:
        require(fragment in text, f"{label} missing required fragment: {fragment}")
    return fragments


def assert_regexes(*, text: str, patterns: list[str], label: str) -> list[str]:
    for pattern in patterns:
        require(re.search(pattern, text, flags=re.MULTILINE) is not None, f"{label} missing required pattern: {pattern}")
    return patterns


def assert_order(*, text: str, fragments: list[str], label: str) -> list[str]:
    cursor = -1
    for fragment in fragments:
        index = text.find(fragment, cursor + 1)
        require(index >= 0, f"{label} missing ordered fragment: {fragment}")
        require(index > cursor, f"{label} fragment out of order: {fragment}")
        cursor = index
    return fragments


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "command": result["command"],
        "cwd": result["cwd"],
        "returncode": result["returncode"],
    }


def strip_safe_comments(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        marker = line.find("--")
        lines.append(line if marker < 0 else line[:marker])
    return "\n".join(lines)


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


def reference_committed_report(
    *,
    script: Path,
    committed_report_path: Path,
    generated_root: Path | None = None,
    policy: dict[str, Any] | None = None,
    repo_root: Path = REPO_ROOT,
) -> dict[str, Any]:
    resolved_report_path = (
        resolve_generated_path(
            committed_report_path,
            generated_root=generated_root,
            policy=policy or load_evidence_policy(),
            repo_root=repo_root,
        )
        if generated_root is not None
        else committed_report_path
    )
    require(resolved_report_path.exists(), f"missing committed report: {resolved_report_path}")
    committed_text = resolved_report_path.read_text(encoding="utf-8")
    committed_payload = json.loads(committed_text)
    require(
        isinstance(committed_payload, dict),
        f"{display_path(resolved_report_path, repo_root=repo_root)}: report root must be an object",
    )
    require(
        committed_payload.get("deterministic") is True,
        f"{display_path(resolved_report_path, repo_root=repo_root)}: expected deterministic committed report",
    )
    require(
        committed_payload.get("report_sha256") == committed_payload.get("repeat_sha256"),
        f"{display_path(resolved_report_path, repo_root=repo_root)}: committed report hashes must match",
    )
    return {
        "script": display_path(script, repo_root=repo_root),
        "committed_report_path": display_path(committed_report_path, repo_root=repo_root),
        "matches_committed_report": True,
    }


@contextmanager
def managed_scratch_root(*, scratch_root: Path | None, prefix: str):
    if scratch_root is not None:
        shutil.rmtree(scratch_root, ignore_errors=True)
        scratch_root.mkdir(parents=True, exist_ok=True)
        yield scratch_root
        return
    with tempfile.TemporaryDirectory(prefix=prefix) as temp_root_str:
        yield Path(temp_root_str)


def load_pipeline_input(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), f"{path}: pipeline input root must be an object")
    return payload


def require_pipeline_result(
    pipeline_input: dict[str, Any],
    *,
    node_id: str,
) -> dict[str, Any]:
    entry = pipeline_input.get(node_id)
    require(isinstance(entry, dict), f"pipeline input missing node {node_id}")
    result = entry.get("result")
    require(isinstance(result, dict), f"pipeline input node {node_id} missing result payload")
    return result


def require_pipeline_report(
    pipeline_input: dict[str, Any],
    *,
    node_id: str,
) -> dict[str, Any]:
    entry = pipeline_input.get(node_id)
    require(isinstance(entry, dict), f"pipeline input missing node {node_id}")
    report = entry.get("report")
    require(isinstance(report, dict), f"pipeline input node {node_id} missing report payload")
    return report


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
