#!/usr/bin/env python3
"""Run the end-to-end Safe samples workflow."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
SAMPLES_ROOT = REPO_ROOT / "samples" / "rosetta"
SAFEC_PATH = COMPILER_ROOT / "bin" / "safec"
ALR_FALLBACK = Path.home() / "bin" / "alr"
RUN_TIMEOUT_SECONDS = 2.0
PRINT_SAMPLE = "samples/rosetta/text/hello_print.safe"
PRODUCER_CONSUMER_SAMPLE = "samples/rosetta/concurrency/producer_consumer.safe"
SUPPORT_BODY_NAMES = {"safe_io.adb"}


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def find_command(name: str, fallback: Path | None = None) -> str:
    resolved = shutil.which(name)
    if resolved:
        return resolved
    if fallback is not None and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def run_command(
    argv: list[str],
    *,
    cwd: Path,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=os.environ.copy(),
        text=True,
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


def build_compiler() -> Path:
    alr = find_command("alr", ALR_FALLBACK)
    completed = run_command([alr, "build"], cwd=COMPILER_ROOT)
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    if not SAFEC_PATH.exists():
        raise FileNotFoundError(f"missing safec binary at {SAFEC_PATH}")
    return SAFEC_PATH


def print_summary(*, passed: int, failures: list[tuple[str, str]]) -> None:
    print(f"{passed} passed, {len(failures)} failed")
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")


def emitted_primary_unit(ada_dir: Path) -> str:
    candidates = sorted(
        path for path in ada_dir.glob("*.adb") if path.name not in SUPPORT_BODY_NAMES
    )
    if not candidates:
        raise FileNotFoundError(f"expected emitted Ada body in {ada_dir}")
    return candidates[0].stem


def executable_name() -> str:
    return "main.exe" if os.name == "nt" else "main"


def sample_build_paths(temp_root: Path, sample: Path) -> dict[str, Path]:
    relative_dir = sample.relative_to(SAMPLES_ROOT).with_suffix("")
    root = temp_root / relative_dir
    return {
        "root": root,
        "out": root / "out",
        "iface": root / "iface",
        "ada": root / "ada",
        "obj": root / "obj",
        "gpr": root / "build.gpr",
        "main": root / "main.adb",
        "exe": root / executable_name(),
    }


def ensure_build_dirs(paths: dict[str, Path]) -> None:
    paths["root"].mkdir(parents=True, exist_ok=True)
    paths["out"].mkdir(parents=True, exist_ok=True)
    paths["iface"].mkdir(parents=True, exist_ok=True)
    paths["ada"].mkdir(parents=True, exist_ok=True)
    paths["obj"].mkdir(parents=True, exist_ok=True)


def default_driver_text(unit_name: str) -> str:
    return (
        f"with {unit_name};\n"
        "\n"
        "procedure Main is\n"
        "begin\n"
        "   null;\n"
        "end Main;\n"
    )


def producer_consumer_driver_text(unit_name: str) -> str:
    return (
        "with GNAT.OS_Lib;\n"
        f"with {unit_name};\n"
        "\n"
        "procedure Main is\n"
        "begin\n"
        "   delay 0.2;\n"
        f"   if {unit_name}.result /= 42 then\n"
        "      GNAT.OS_Lib.OS_Exit (1);\n"
        "   end if;\n"
        "   GNAT.OS_Lib.OS_Exit (0);\n"
        "end Main;\n"
    )


def hello_print_driver_text(unit_name: str) -> str:
    return (
        f"with {unit_name};\n"
        "\n"
        "procedure Main is\n"
        "begin\n"
        f"   {unit_name}.Run;\n"
        "end Main;\n"
    )


def driver_text(sample: Path, unit_name: str) -> str:
    relative = repo_rel(sample)
    if relative == PRODUCER_CONSUMER_SAMPLE:
        return producer_consumer_driver_text(unit_name)
    if relative == PRINT_SAMPLE:
        return hello_print_driver_text(unit_name)
    return default_driver_text(unit_name)


def expected_stdout(sample: Path) -> str | None:
    if repo_rel(sample) == PRINT_SAMPLE:
        return "hello\n42\ntrue\n"
    return None


def expects_safe_io(sample: Path) -> bool:
    return repo_rel(sample) == PRINT_SAMPLE


def project_text(paths: dict[str, Path]) -> str:
    lines = [
        "project Build is",
        f'   for Source_Dirs use ("{paths["root"]}", "{paths["ada"]}");',
        f'   for Object_Dir use "{paths["obj"]}";',
        f'   for Exec_Dir use "{paths["root"]}";',
        '   for Main use ("main.adb");',
    ]
    gnat_adc = paths["ada"] / "gnat.adc"
    if gnat_adc.exists():
        lines.extend(
            [
                "   package Compiler is",
                f'      for Default_Switches ("Ada") use ("-gnatec={gnat_adc}");',
                "   end Compiler;",
            ]
        )
    lines.append("end Build;")
    return "\n".join(lines) + "\n"


def stage_error(stage: str, detail: str) -> str:
    return f"{stage}: {detail}"


def run_sample(
    *,
    safec: Path,
    sample: Path,
    temp_root: Path,
) -> str | None:
    sample_label = repo_rel(sample)

    try:
        completed = run_command([str(safec), "check", sample_label], cwd=REPO_ROOT)
    except subprocess.TimeoutExpired:
        return stage_error("check", "timed out")
    if completed.returncode != 0:
        return stage_error("check", first_message(completed))

    paths = sample_build_paths(temp_root, sample)
    ensure_build_dirs(paths)

    emit_command = [
        str(safec),
        "emit",
        sample_label,
        "--out-dir",
        str(paths["out"]),
        "--interface-dir",
        str(paths["iface"]),
        "--ada-out-dir",
        str(paths["ada"]),
    ]
    try:
        completed = run_command(emit_command, cwd=REPO_ROOT)
    except subprocess.TimeoutExpired:
        return stage_error("emit", "timed out")
    if completed.returncode != 0:
        return stage_error("emit", first_message(completed))

    try:
        unit_name = emitted_primary_unit(paths["ada"])
    except FileNotFoundError as exc:
        return stage_error("emit", str(exc))

    safe_io_spec = paths["ada"] / "safe_io.ads"
    safe_io_body = paths["ada"] / "safe_io.adb"
    if expects_safe_io(sample):
        if not safe_io_spec.exists() or not safe_io_body.exists():
            return stage_error("emit", "missing generated safe_io support files")
    elif safe_io_spec.exists() or safe_io_body.exists():
        return stage_error("emit", "unexpected generated safe_io support files")

    paths["main"].write_text(driver_text(sample, unit_name), encoding="utf-8")
    paths["gpr"].write_text(project_text(paths), encoding="utf-8")

    alr = find_command("alr", ALR_FALLBACK)
    build_command = [
        alr,
        "exec",
        "--",
        "gprbuild",
        "-P",
        str(paths["gpr"]),
        "main.adb",
    ]
    try:
        completed = run_command(build_command, cwd=COMPILER_ROOT)
    except subprocess.TimeoutExpired:
        return stage_error("build", "timed out")
    if completed.returncode != 0:
        return stage_error("build", first_message(completed))
    if not paths["exe"].exists():
        return stage_error("build", f"missing executable {paths['exe']}")

    try:
        completed = run_command([str(paths["exe"])], cwd=paths["root"], timeout=RUN_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        return stage_error("run", f"timed out after {RUN_TIMEOUT_SECONDS:.1f}s")
    if completed.returncode != 0:
        return stage_error("run", first_message(completed))

    expected = expected_stdout(sample)
    if expected is not None and completed.stdout != expected:
        return stage_error("run", f"unexpected stdout {completed.stdout!r}")

    return None


def main() -> int:
    try:
        safec = build_compiler()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_samples: ERROR: {exc}", file=sys.stderr)
        return 1

    passed = 0
    failures: list[tuple[str, str]] = []
    samples = sorted(SAMPLES_ROOT.rglob("*.safe"))

    with tempfile.TemporaryDirectory(prefix="safe-samples-") as temp_dir:
        temp_root = Path(temp_dir)
        for sample in samples:
            detail = run_sample(safec=safec, sample=sample, temp_root=temp_root)
            if detail is None:
                passed += 1
            else:
                failures.append((repo_rel(sample), detail))

    print_summary(passed=passed, failures=failures)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
