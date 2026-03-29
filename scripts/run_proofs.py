#!/usr/bin/env python3
"""Run the live all-proved-only Safe proof workflow."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
SAFEC_PATH = COMPILER_ROOT / "bin" / "safec"
ALR_FALLBACK = Path.home() / "bin" / "alr"
GNATPROVE_FALLBACK = Path.home() / ".alire" / "bin" / "gnatprove"
GENERATED_SUPPORT_MARKERS = (
    "--  Generated Safe print support",
    "--  Safe Language Runtime Type Definitions",
)

FLOW_SWITCHES = [
    "--mode=flow",
    "--report=all",
    "--warnings=error",
]

PROVE_SWITCHES = [
    "--mode=prove",
    "--level=2",
    "--prover=cvc5,z3,altergo",
    "--steps=0",
    "--timeout=120",
    "--report=all",
    "--warnings=error",
    "--checks-as-errors=on",
]

COMPANION_PROJECTS = [
    ("companion/gen", "companion.gpr"),
    ("companion/templates", "templates.gpr"),
]

PR11_8A_CHECKPOINT_FIXTURES = [
    "tests/positive/rule1_accumulate.safe",
    "tests/positive/rule1_averaging.safe",
    "tests/positive/rule1_conversion.safe",
    "tests/positive/rule1_parameter.safe",
    "tests/positive/rule1_return.safe",
    "tests/positive/rule2_binary_search.safe",
    "tests/positive/rule2_binary_search_function.safe",
    "tests/positive/rule2_iteration.safe",
    "tests/positive/rule2_lookup.safe",
    "tests/positive/rule2_matrix.safe",
    "tests/positive/rule2_slice.safe",
    "tests/positive/rule3_average.safe",
    "tests/positive/rule3_divide.safe",
    "tests/positive/rule3_modulo.safe",
    "tests/positive/rule3_percent.safe",
    "tests/positive/rule3_remainder.safe",
    "tests/positive/rule5_filter.safe",
    "tests/positive/rule5_interpolate.safe",
    "tests/positive/rule5_normalize.safe",
    "tests/positive/rule5_statistics.safe",
    "tests/positive/rule5_temperature.safe",
    "tests/positive/rule5_vector_normalize.safe",
    "tests/positive/constant_range_bound.safe",
    "tests/positive/constant_channel_capacity.safe",
    "tests/positive/constant_task_priority.safe",
    "tests/positive/pr112_character_case.safe",
    "tests/positive/pr112_discrete_case.safe",
    "tests/positive/pr112_string_param.safe",
    "tests/positive/pr112_case_scrutinee_once.safe",
    "tests/positive/pr113_discriminant_constraints.safe",
    "tests/positive/pr113_tuple_destructure.safe",
    "tests/positive/pr113_structured_result.safe",
    "tests/positive/pr113_variant_guard.safe",
    "tests/positive/constant_discriminant_default.safe",
    "tests/positive/result_equality_check.safe",
    "tests/positive/result_guarded_access.safe",
    "tests/positive/pr118_inline_integer_return.safe",
    "tests/positive/pr118_type_range_equivalent.safe",
]

PR11_8B_CHECKPOINT_FIXTURES = [
    "tests/concurrency/channel_ceiling_priority.safe",
    "tests/positive/channel_pipeline.safe",
    "tests/concurrency/exclusive_variable.safe",
    "tests/concurrency/fifo_ordering.safe",
    "tests/concurrency/multi_task_channel.safe",
    "tests/concurrency/select_delay_local_scope.safe",
    "tests/concurrency/select_priority.safe",
    "tests/concurrency/task_global_owner.safe",
    "tests/concurrency/task_priority_delay.safe",
    "tests/concurrency/try_ops.safe",
    "tests/positive/pr113_tuple_channel.safe",
]

PR11_8E_CHECKPOINT_FIXTURES = [
    "tests/positive/ownership_move.safe",
    "tests/positive/ownership_early_return.safe",
    "tests/positive/pr118e_not_null_self_reference.safe",
    "tests/positive/pr118e1_mutual_record_family.safe",
    "tests/concurrency/pr118c2_pre_task_init.safe",
]

PR11_8F_CHECKPOINT_FIXTURES = [
    "tests/positive/rule4_conditional.safe",
    "tests/positive/rule4_deref.safe",
    "tests/positive/rule4_factory.safe",
    "tests/positive/rule4_linked_list.safe",
    "tests/positive/rule4_linked_list_sum.safe",
    "tests/positive/rule4_optional.safe",
    "tests/positive/ownership_borrow.safe",
    "tests/positive/ownership_observe.safe",
    "tests/positive/ownership_observe_access.safe",
    "tests/positive/ownership_return.safe",
    "tests/positive/ownership_inout.safe",
]

EMITTED_PROOF_REGRESSION_FIXTURES = [
    "tests/concurrency/select_with_delay.safe",
    "tests/concurrency/select_with_delay_multiarm.safe",
    "tests/positive/channel_pingpong.safe",
    "tests/positive/channel_pipeline_compute.safe",
    "tests/positive/constant_access_deref_write.safe",
    "tests/positive/constant_shadow_mutable.safe",
    "tests/positive/emitter_surface_proc.safe",
    "tests/positive/emitter_surface_record.safe",
    "tests/positive/pr118c1_print.safe",
]

EMITTED_PROOF_FIXTURES = (
    PR11_8A_CHECKPOINT_FIXTURES
    + PR11_8B_CHECKPOINT_FIXTURES
    + PR11_8E_CHECKPOINT_FIXTURES
    + PR11_8F_CHECKPOINT_FIXTURES
    + EMITTED_PROOF_REGRESSION_FIXTURES
)


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
    argv: list[str], *, cwd: Path, timeout: int | None = None
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            argv,
            cwd=cwd,
            env=os.environ.copy(),
            text=True,
            capture_output=True,
            check=False,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if stderr:
            stderr += "\n"
        stderr += f"timed out after {timeout}s"
        return subprocess.CompletedProcess(argv, 124, stdout, stderr)


def first_message(completed: subprocess.CompletedProcess[str]) -> str:
    for stream in (completed.stderr, completed.stdout):
        for line in stream.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped
    return f"exit code {completed.returncode}"


def build_compiler() -> tuple[Path, str, str]:
    alr = find_command("alr", ALR_FALLBACK)
    gnatprove = find_command("gnatprove", GNATPROVE_FALLBACK)
    completed = run_command([alr, "build"], cwd=COMPILER_ROOT)
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    if not SAFEC_PATH.exists():
        raise FileNotFoundError(f"missing safec binary at {SAFEC_PATH}")
    return SAFEC_PATH, alr, gnatprove


def validate_manifest(
    name: str,
    entries: list[str],
    *,
    allow_missing: bool = False,
) -> None:
    seen: set[str] = set()
    duplicates: list[str] = []
    missing: list[str] = []

    for entry in entries:
        if entry in seen:
            duplicates.append(entry)
        else:
            seen.add(entry)
        if not allow_missing and not (REPO_ROOT / entry).exists():
            missing.append(entry)

    if duplicates:
        raise RuntimeError(f"{name} has duplicate entries: {', '.join(duplicates)}")
    if missing:
        raise RuntimeError(f"{name} has missing entries: {', '.join(missing)}")


def validate_manifests() -> None:
    validate_manifest("PR11.8a checkpoint manifest", PR11_8A_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8b checkpoint manifest", PR11_8B_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8e checkpoint manifest", PR11_8E_CHECKPOINT_FIXTURES)
    validate_manifest("PR11.8f checkpoint manifest", PR11_8F_CHECKPOINT_FIXTURES)
    validate_manifest("emitted proof regression manifest", EMITTED_PROOF_REGRESSION_FIXTURES)
    validate_manifest("emitted proof manifest", EMITTED_PROOF_FIXTURES)


def emitted_body_file(ada_dir: Path) -> Path:
    candidates = sorted(
        path
        for path in ada_dir.glob("*.adb")
        if not is_generated_support_file(path)
    )
    if not candidates:
        raise FileNotFoundError(f"{ada_dir}: expected emitted .adb file")
    return candidates[0]


def is_generated_support_file(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        first_lines = path.read_text(encoding="utf-8").splitlines()[:2]
    except OSError:
        return False
    return any(line in GENERATED_SUPPORT_MARKERS for line in first_lines)


def write_emitted_project(ada_dir: Path) -> Path:
    lines = [
        "project Build is",
        '   for Source_Dirs use (".");',
        '   for Object_Dir use "obj";',
    ]
    if (ada_dir / "gnat.adc").exists():
        lines.extend(
            [
                "   package Compiler is",
                '      for Default_Switches ("Ada") use ("-gnatec=gnat.adc");',
                "   end Compiler;",
            ]
        )
    lines.append("end Build;")

    gpr_path = ada_dir / "build.gpr"
    gpr_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return gpr_path


def compile_emitted_ada(ada_dir: Path, *, alr: str) -> subprocess.CompletedProcess[str]:
    gpr_path = write_emitted_project(ada_dir)
    argv = [
        alr,
        "exec",
        "--",
        "gprbuild",
        "-c",
        "-P",
        str(gpr_path),
        emitted_body_file(ada_dir).name,
    ]
    if (ada_dir / "gnat.adc").exists():
        argv.extend(["-cargs", f"-gnatec={ada_dir / 'gnat.adc'}"])
    return run_command(argv, cwd=COMPILER_ROOT)


def parse_summary_cell(cell: str) -> dict[str, int | str]:
    stripped = cell.strip()
    if stripped == ".":
        return {"count": 0, "detail": ""}
    match = re.match(r"^(?P<count>\d+)(?: \((?P<detail>.*)\))?$", stripped)
    if match is None:
        raise RuntimeError(f"unexpected GNATprove summary cell: {cell!r}")
    return {
        "count": int(match.group("count")),
        "detail": match.group("detail") or "",
    }


def parse_gnatprove_summary(path: Path) -> dict[str, dict[str, dict[str, int | str]]]:
    if not path.exists():
        raise FileNotFoundError(f"missing GNATprove summary: {path}")
    lines = path.read_text(encoding="utf-8").splitlines()
    expected_header = [
        "SPARK Analysis results",
        "Total",
        "Flow",
        "Provers",
        "Justified",
        "Unproved",
    ]

    header_index: int | None = None
    for index, line in enumerate(lines):
        parts = re.split(r"\s{2,}", line.strip())
        if parts == expected_header:
            header_index = index
            break
    if header_index is None:
        raise RuntimeError(f"missing GNATprove summary table header in {path}")

    rows: dict[str, dict[str, dict[str, int | str]]] = {}
    saw_row = False
    for line in lines[header_index + 1 :]:
        stripped = line.strip()
        if not stripped:
            if saw_row:
                break
            continue
        if set(stripped) == {"-"}:
            continue
        parts = re.split(r"\s{2,}", stripped)
        if len(parts) != 6:
            raise RuntimeError(f"malformed GNATprove summary row: {stripped!r}")
        label, total, flow, provers, justified, unproved = parts
        rows[label] = {
            "total": parse_summary_cell(total),
            "flow": parse_summary_cell(flow),
            "provers": parse_summary_cell(provers),
            "justified": parse_summary_cell(justified),
            "unproved": parse_summary_cell(unproved),
        }
        saw_row = True

    if "Total" not in rows:
        raise RuntimeError(f"GNATprove summary missing Total row in {path}")
    return rows


def run_companion_project(
    *,
    label: str,
    project_dir: Path,
    project_file: str,
    alr: str,
    gnatprove: str,
) -> tuple[bool, str]:
    summary_path = project_dir / "obj" / "gnatprove" / "gnatprove.out"
    for mode, switches in (("flow", FLOW_SWITCHES), ("prove", PROVE_SWITCHES)):
        completed = run_command(
            [alr, "exec", "--", gnatprove, "-P", project_file, *switches],
            cwd=project_dir,
        )
        if completed.returncode != 0:
            return False, f"{mode} failed: {first_message(completed)}"
        try:
            parse_gnatprove_summary(summary_path)
        except (FileNotFoundError, RuntimeError) as exc:
            return False, f"{mode} summary error: {exc}"
    return True, ""


def emit_fixture(safec: Path, source: Path, root: Path) -> tuple[Path, Path, Path]:
    out_dir = root / "out"
    iface_dir = root / "iface"
    ada_dir = root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    completed = run_command(
        [
            str(safec),
            "emit",
            repo_rel(source),
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
            "--ada-out-dir",
            str(ada_dir),
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    return out_dir, iface_dir, ada_dir


def run_emitted_fixture(
    *,
    safec: Path,
    source: Path,
    temp_root: Path,
    alr: str,
    gnatprove: str,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
) -> tuple[bool, str]:
    fixture_root = temp_root / source.stem
    try:
        _, _, ada_dir = emit_fixture(safec, source, fixture_root)
    except RuntimeError as exc:
        return False, f"emit failed: {exc}"

    compile_result = compile_emitted_ada(ada_dir, alr=alr)
    if compile_result.returncode != 0:
        return False, f"compile failed: {first_message(compile_result)}"

    gpr_path = write_emitted_project(ada_dir)
    adc_path = ada_dir / "gnat.adc"
    summary_path = ada_dir / "obj" / "gnatprove" / "gnatprove.out"

    prove_args = PROVE_SWITCHES if prove_switches is None else prove_switches

    for mode, switches in (("flow", FLOW_SWITCHES), ("prove", prove_args)):
        argv = [alr, "exec", "--", gnatprove, "-P", str(gpr_path), *switches]
        if adc_path.exists():
            argv.extend(["-cargs", f"-gnatec={adc_path}"])
        completed = run_command(argv, cwd=COMPILER_ROOT, timeout=command_timeout)
        if completed.returncode != 0:
            return False, f"{mode} failed: {first_message(completed)}"
        try:
            rows = parse_gnatprove_summary(summary_path)
        except (FileNotFoundError, RuntimeError) as exc:
            return False, f"{mode} summary error: {exc}"

        total_row = rows["Total"]
        justified = total_row["justified"]["count"]
        unproved = total_row["unproved"]["count"]
        if justified != 0 or unproved != 0:
            return False, f"{mode} summary has justified={justified}, unproved={unproved}"

    return True, ""


def print_summary(
    *,
    passed: int,
    failures: list[tuple[str, str]],
    title: str | None = None,
    trailing_blank_line: bool = False,
) -> None:
    prefix = f"{title}: " if title is not None else ""
    print(f"{prefix}{passed} proved, {len(failures)} failed")
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")
    if trailing_blank_line:
        print()


def run_fixture_group(
    *,
    safec: Path,
    fixtures: list[str],
    temp_root: Path,
    alr: str,
    gnatprove: str,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
) -> tuple[int, list[tuple[str, str]]]:
    passed = 0
    failures: list[tuple[str, str]] = []

    for fixture_rel in fixtures:
        source = REPO_ROOT / fixture_rel
        ok, detail = run_emitted_fixture(
            safec=safec,
            source=source,
            temp_root=temp_root,
            alr=alr,
            gnatprove=gnatprove,
            prove_switches=prove_switches,
            command_timeout=command_timeout,
        )
        if ok:
            passed += 1
        else:
            failures.append((fixture_rel, detail))

    return passed, failures


def main() -> int:
    try:
        validate_manifests()
        safec, alr, gnatprove = build_compiler()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_proofs: ERROR: {exc}", file=sys.stderr)
        return 1

    companion_passed = 0
    companion_failures: list[tuple[str, str]] = []
    checkpoint_a_passed = 0
    checkpoint_a_failures: list[tuple[str, str]] = []
    checkpoint_b_passed = 0
    checkpoint_b_failures: list[tuple[str, str]] = []
    checkpoint_e_passed = 0
    checkpoint_e_failures: list[tuple[str, str]] = []
    checkpoint_f_passed = 0
    checkpoint_f_failures: list[tuple[str, str]] = []
    regression_passed = 0
    regression_failures: list[tuple[str, str]] = []

    for project_rel, project_file in COMPANION_PROJECTS:
        project_dir = REPO_ROOT / project_rel
        ok, detail = run_companion_project(
            label=project_rel,
            project_dir=project_dir,
            project_file=project_file,
            alr=alr,
            gnatprove=gnatprove,
        )
        if ok:
            companion_passed += 1
        else:
            companion_failures.append((project_rel, detail))

    with tempfile.TemporaryDirectory(prefix="safe-proofs-") as temp_root_str:
        temp_root = Path(temp_root_str)
        checkpoint_a_passed, checkpoint_a_failures = run_fixture_group(
            safec=safec,
            fixtures=PR11_8A_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            alr=alr,
            gnatprove=gnatprove,
        )
        checkpoint_b_passed, checkpoint_b_failures = run_fixture_group(
            safec=safec,
            fixtures=PR11_8B_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            alr=alr,
            gnatprove=gnatprove,
        )
        checkpoint_e_passed, checkpoint_e_failures = run_fixture_group(
            safec=safec,
            fixtures=PR11_8E_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            alr=alr,
            gnatprove=gnatprove,
        )
        checkpoint_f_passed, checkpoint_f_failures = run_fixture_group(
            safec=safec,
            fixtures=PR11_8F_CHECKPOINT_FIXTURES,
            temp_root=temp_root,
            alr=alr,
            gnatprove=gnatprove,
        )
        regression_passed, regression_failures = run_fixture_group(
            safec=safec,
            fixtures=EMITTED_PROOF_REGRESSION_FIXTURES,
            temp_root=temp_root,
            alr=alr,
            gnatprove=gnatprove,
        )

    total_passed = (
        companion_passed
        + checkpoint_a_passed
        + checkpoint_b_passed
        + checkpoint_e_passed
        + checkpoint_f_passed
        + regression_passed
    )
    total_failures = (
        companion_failures
        + checkpoint_a_failures
        + checkpoint_b_failures
        + checkpoint_e_failures
        + checkpoint_f_failures
        + regression_failures
    )

    print_summary(
        passed=companion_passed,
        failures=companion_failures,
        title="Companion baselines",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_a_passed,
        failures=checkpoint_a_failures,
        title="PR11.8a checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_b_passed,
        failures=checkpoint_b_failures,
        title="PR11.8b checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_e_passed,
        failures=checkpoint_e_failures,
        title="PR11.8e checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=checkpoint_f_passed,
        failures=checkpoint_f_failures,
        title="PR11.8f checkpoint",
        trailing_blank_line=True,
    )
    print_summary(
        passed=regression_passed,
        failures=regression_failures,
        title="Emitted proof regressions",
        trailing_blank_line=True,
    )
    print_summary(passed=total_passed, failures=total_failures)
    return 0 if not total_failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
