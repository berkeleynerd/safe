"""Shared helpers for ``scripts/run_tests.py`` section modules."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

from _lib.harness_common import (
    COMPILER_ROOT,
    REPO_ROOT,
    ensure_sdkroot,
    find_command as harness_find_command,
    run_capture,
)

SAFEC_PATH = COMPILER_ROOT / "bin" / "safec"
ALR_FALLBACK = Path.home() / "bin" / "alr"
DIAGNOSTIC_EXIT_CODE = 1
SAFE_CLI = REPO_ROOT / "scripts" / "safe_cli.py"
SAFE_REPL = REPO_ROOT / "scripts" / "safe_repl.py"
EMBEDDED_SMOKE = REPO_ROOT / "scripts" / "run_embedded_smoke.py"
VALIDATE_OUTPUT_CONTRACTS = REPO_ROOT / "scripts" / "validate_output_contracts.py"
VALIDATE_AST_OUTPUT = REPO_ROOT / "scripts" / "validate_ast_output.py"
VSCODE_README = REPO_ROOT / "editors" / "vscode" / "README.md"
VSCODE_PACKAGE_JSON = REPO_ROOT / "editors" / "vscode" / "package.json"
LOCAL_WITH_RE = re.compile(r"^\s*with\s+([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)\s*;\s*$")

EMITTED_GNATPROVE_WARNING_RE = re.compile(
    r"pragma\s+Warnings\s*\(\s*GNATprove\b.*?\);",
    re.IGNORECASE | re.DOTALL,
)
EMITTED_ASSUME_RE = re.compile(
    r"pragma\s+Assume\s*\(.*?\);",
    re.IGNORECASE | re.DOTALL,
)

CaseResult = tuple[bool, str]
Failure = tuple[str, str]
RunCounts = tuple[int, int, list[Failure]]


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def find_command(name: str, fallback: Path | None = None) -> str:
    return harness_find_command(name, fallback)


def run_command(
    argv: list[str],
    *,
    cwd: Path,
    input_text: str | None = None,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    if input_text is None and timeout is None:
        return run_capture(argv, cwd=cwd, env=env)
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        input=input_text,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def first_message(completed: subprocess.CompletedProcess[str]) -> str:
    for stream in (completed.stderr, completed.stdout):
        for line in stream.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped
    return f"exit code {completed.returncode}"


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    marker = "Expected diagnostic output:\n------------------------------------------------------------------------\n"
    start = text.index(marker) + len(marker)
    end = text.index("\n------------------------------------------------------------------------\n", start)
    return text[start:end]


def build_compiler() -> Path:
    alr = find_command("alr", ALR_FALLBACK)
    completed = run_command([alr, "build"], cwd=COMPILER_ROOT)
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    if not SAFEC_PATH.exists():
        raise FileNotFoundError(f"missing safec binary at {SAFEC_PATH}")
    return SAFEC_PATH


def check_fixture(
    safec: Path,
    source: Path,
    *,
    expected_returncode: int,
    extra_args: list[str] | None = None,
) -> CaseResult:
    argv = [str(safec), "check", repo_rel(source), *(extra_args or [])]
    completed = run_command(argv, cwd=REPO_ROOT)
    ok = completed.returncode == expected_returncode
    return ok, first_message(completed)


def print_summary(*, passed: int, skipped: int, failures: list[Failure]) -> None:
    summary = f"{passed} passed"
    if skipped:
        summary += f", {skipped} skipped"
    summary += f", {len(failures)} failed"
    print(summary)
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")


def record_result(failures: list[Failure], label: str, result: CaseResult) -> int:
    ok, detail = result
    if ok:
        return 1
    failures.append((label, detail))
    return 0


def executable_name() -> str:
    return "main.exe" if os.name == "nt" else "main"


def safe_build_executable(source: Path, *, target_bits: int = 64) -> Path:
    return source.parent / "obj" / source.stem / f"target-{target_bits}" / executable_name()


def safe_prove_summary_path(source: Path, *, target_bits: int = 64) -> Path:
    return source.parent / "obj" / source.stem / f"prove-{target_bits}" / "obj" / "gnatprove" / "gnatprove.out"


def clear_project_artifacts(source: Path) -> None:
    shutil.rmtree(source.parent / ".safe-build", ignore_errors=True)
    shutil.rmtree(source.parent / "obj" / source.stem, ignore_errors=True)


def emit_case_ada_text(
    safec: Path,
    *,
    label: str,
    source: Path,
    temp_root: Path,
) -> tuple[Path, str]:
    def local_dependency_sources(root: Path) -> list[Path]:
        found: list[Path] = []
        seen: set[Path] = set()
        pending = [root]

        while pending:
            current = pending.pop()
            try:
                text = current.read_text(encoding="utf-8")
            except OSError:
                continue

            for line in text.splitlines():
                match = LOCAL_WITH_RE.match(line)
                if match is None:
                    continue
                candidate = current.parent / f"{match.group(1).split('.')[-1]}.safe"
                if candidate == root or not candidate.exists() or candidate in seen:
                    continue
                seen.add(candidate)
                found.append(candidate)
                pending.append(candidate)

        return found

    case_root = temp_root / f"{source.stem}-{label}"
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    dependencies = local_dependency_sources(source)
    for dependency in dependencies:
        dep_emit = run_command(
            [
                str(safec),
                "emit",
                repo_rel(dependency),
                "--out-dir",
                str(out_dir),
                "--interface-dir",
                str(iface_dir),
                "--interface-search-dir",
                str(iface_dir),
            ],
            cwd=REPO_ROOT,
        )
        if dep_emit.returncode != 0:
            raise RuntimeError(
                f"dependency emit failed for {repo_rel(dependency)}: "
                f"{first_message(dep_emit)}"
            )

    emit_args = [
        str(safec),
        "emit",
        repo_rel(source),
        "--out-dir",
        str(out_dir),
        "--interface-dir",
        str(iface_dir),
        "--ada-out-dir",
        str(ada_dir),
    ]
    if dependencies:
        emit_args.extend(["--interface-search-dir", str(iface_dir)])

    emit = run_command(emit_args, cwd=REPO_ROOT)
    if emit.returncode != 0:
        raise RuntimeError(f"emit failed: {first_message(emit)}")

    emitted_text = ""
    ada_file_found = False
    for path in sorted(ada_dir.iterdir()):
        if path.suffix in {".adb", ".ads"}:
            ada_file_found = True
            emitted_text += path.read_text(encoding="utf-8")

    if not ada_file_found:
        raise RuntimeError(f"emit produced no Ada sources in {ada_dir}")

    return ada_dir, emitted_text
