#!/usr/bin/env python3
"""Run the end-to-end Safe samples workflow."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

from _lib.proof_eval import ProofToolchain, prepare_proof_toolchain, run_source_proof
from _lib.test_harness import should_skip_ceiling_tests

REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
STDLIB_ADA_DIR = COMPILER_ROOT / "stdlib" / "ada"
SAMPLES_ROOT = REPO_ROOT / "samples" / "rosetta"
RUN_TIMEOUT_SECONDS = 2.0
PRINT_SAMPLE = "samples/rosetta/text/hello_print.safe"
PRODUCER_CONSUMER_SAMPLE = "samples/rosetta/concurrency/producer_consumer.safe"
GENERATED_SUPPORT_MARKERS = (
    "--  Generated Safe print support",
    "--  Safe Language Runtime Type Definitions",
)


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


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


def build_toolchain() -> ProofToolchain:
    return prepare_proof_toolchain(env=os.environ.copy())


def print_summary(*, passed: int, skipped: int, failures: list[tuple[str, str]]) -> None:
    summary = f"{passed} passed"
    if skipped:
        summary += f", {skipped} skipped"
    summary += f", {len(failures)} failed"
    print(summary)
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")


def emitted_primary_unit(ada_dir: Path) -> str:
    candidates = sorted(
        path
        for path in ada_dir.glob("*.adb")
        if path.stem != "main" and not is_generated_support_file(path)
    )
    if not candidates:
        raise FileNotFoundError(f"expected emitted Ada body in {ada_dir}")
    return candidates[0].stem


def is_generated_support_file(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        first_lines = path.read_text(encoding="utf-8").splitlines()[:2]
    except OSError:
        return False
    return any(line in GENERATED_SUPPORT_MARKERS for line in first_lines)


def generated_support_files(ada_dir: Path) -> tuple[list[Path], list[Path]]:
    specs = sorted(
        path for path in ada_dir.glob("*.ads") if is_generated_support_file(path)
    )
    bodies = sorted(
        path for path in ada_dir.glob("*.adb") if is_generated_support_file(path)
    )
    return specs, bodies


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


def has_emitted_main(ada_dir: Path) -> bool:
    return (ada_dir / "main.adb").exists()


def expected_stdout(sample: Path) -> str | None:
    return {
        "samples/rosetta/arithmetic/collatz_bounded.safe": "8\n",
        "samples/rosetta/arithmetic/factorial.safe": "120\n",
        "samples/rosetta/arithmetic/fibonacci.safe": "89\n",
        "samples/rosetta/arithmetic/gcd.safe": "6\n",
        "samples/rosetta/concurrency/producer_consumer.safe": "42\n",
        "samples/rosetta/data_structures/fixed_to_growable.safe": "10\n",
        "samples/rosetta/data_structures/growable_sum.safe": "60\n",
        "samples/rosetta/data_structures/growable_to_fixed.safe": "16\n",
        "samples/rosetta/text/enum_dispatch.safe": "store\n",
        "samples/rosetta/text/bounded_prefix.safe": "ok\n",
        "samples/rosetta/text/grade_message.safe": "good\n",
        "samples/rosetta/text/hello_print.safe": "hello\n",
        "samples/rosetta/text/opcode_dispatch.safe": "load\n",
    }.get(repo_rel(sample))


def project_text(paths: dict[str, Path]) -> str:
    lines = [
        "project Build is",
        f'   for Source_Dirs use ("{paths["root"]}", "{paths["ada"]}", "{STDLIB_ADA_DIR}");',
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
    toolchain: ProofToolchain,
    sample: Path,
    temp_root: Path,
) -> str | None:
    sample_label = repo_rel(sample)

    try:
        completed = run_command([str(toolchain.safec), "check", sample_label], cwd=REPO_ROOT)
    except subprocess.TimeoutExpired:
        return stage_error("check", "timed out")
    if completed.returncode != 0:
        return stage_error("check", first_message(completed))

    paths = sample_build_paths(temp_root, sample)
    ensure_build_dirs(paths)

    emit_command = [
        str(toolchain.safec),
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

    support_specs, support_bodies = generated_support_files(paths["ada"])
    if support_specs or support_bodies:
        return stage_error("emit", "unexpected generated print support files")

    if not has_emitted_main(paths["ada"]):
        paths["main"].write_text(driver_text(sample, unit_name), encoding="utf-8")
    paths["gpr"].write_text(project_text(paths), encoding="utf-8")

    build_command = [
        toolchain.alr,
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

    proof_result = run_source_proof(
        toolchain=toolchain,
        source=sample,
        proof_root=paths["root"] / "prove",
        run_check=True,
    )
    if not proof_result.passed:
        return stage_error("prove", proof_result.detail)

    return None


def main() -> int:
    try:
        skip_ceiling_tests, ceiling_skip_reason = should_skip_ceiling_tests()
    except ValueError as exc:
        print(f"run_samples: ERROR: {exc}", file=sys.stderr)
        return 1

    try:
        toolchain = build_toolchain()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_samples: ERROR: {exc}", file=sys.stderr)
        return 1

    if skip_ceiling_tests:
        print(
            "Skipping ceiling-priority sample — "
            f"{ceiling_skip_reason}. 1 sample will be skipped. "
            "Set SAFE_SKIP_CEILING_TESTS=never to force run."
        )

    passed = 0
    skipped = 0
    failures: list[tuple[str, str]] = []
    samples = sorted(SAMPLES_ROOT.rglob("*.safe"))

    with tempfile.TemporaryDirectory(prefix="safe-samples-") as temp_dir:
        temp_root = Path(temp_dir)
        for sample in samples:
            if skip_ceiling_tests and repo_rel(sample) == PRODUCER_CONSUMER_SAMPLE:
                skipped += 1
                continue
            detail = run_sample(toolchain=toolchain, sample=sample, temp_root=temp_root)
            if detail is None:
                passed += 1
            else:
                failures.append((repo_rel(sample), detail))

    print_summary(passed=passed, skipped=skipped, failures=failures)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
