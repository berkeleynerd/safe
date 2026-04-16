"""Shared helpers for emitted GNATprove evaluation."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from .harness_common import COMPILER_ROOT, REPO_ROOT, find_command, require_safec, sha256_file
from .pr09_emit import emitted_body_file
from .proof_diagnostics import rewrite_gnatprove_output, write_line_map_sidecar
from .project_cache import (
    STDLIB_ADA_DIR,
    ProjectEmitError,
    emitted_primary_unit_for_source,
    ensure_project_emitted,
    ensure_safe_prove_root,
    proof_fingerprint,
    proof_project_text,
    safe_prove_paths,
    save_project_state,
    source_key,
    write_safe_prove_project,
)

ALR_FALLBACK = Path.home() / "bin" / "alr"
GNATPROVE_FALLBACK = Path.home() / ".alire" / "bin" / "gnatprove"

FLOW_SWITCHES = [
    "--mode=flow",
    "--report=all",
    "--warnings=error",
]


def prove_switches_for_level(level: int) -> list[str]:
    if level == 1:
        return [
            "--mode=prove",
            "--level=1",
            "--prover=cvc5,z3",
            "-j4",
            "--steps=0",
            "--timeout=30",
            "--report=all",
            "--warnings=error",
            "--checks-as-errors=on",
        ]
    if level == 2:
        return [
            "--mode=prove",
            "--level=2",
            "--prover=cvc5,z3,altergo",
            "-j4",
            "--steps=0",
            "--timeout=120",
            "--report=all",
            "--warnings=error",
            "--checks-as-errors=on",
        ]
    raise ValueError(f"unsupported proof level: {level}")


PROVE_SWITCHES = prove_switches_for_level(2)


SummaryCell = dict[str, int | str]
SummaryRow = dict[str, SummaryCell]
SummaryTable = dict[str, SummaryRow]
WITH_CLAUSE_RE = re.compile(r"^with\s+(.+);$", re.IGNORECASE)


@dataclass(frozen=True)
class ProofToolchain:
    safec: Path
    alr: str
    gnatprove: str
    env: dict[str, str]


@dataclass
class ProofRunResult:
    source: Path
    proof_root: Path
    passed: bool
    stage: str
    detail: str = ""
    flow_summary: SummaryRow | None = None
    prove_summary: SummaryRow | None = None
    stage_output: dict[str, str] = field(default_factory=dict)
    diagnostics_json: list[dict[str, object]] = field(default_factory=list)
    raw_stage_output: dict[str, str] = field(default_factory=dict)


def run_command(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory(prefix="safe-proof-cmd-") as temp_root_str:
        temp_root = Path(temp_root_str)
        stdout_path = temp_root / "stdout.txt"
        stderr_path = temp_root / "stderr.txt"
        with stdout_path.open("w+", encoding="utf-8") as stdout_handle, stderr_path.open(
            "w+", encoding="utf-8"
        ) as stderr_handle:
            process = subprocess.Popen(
                argv,
                cwd=cwd,
                env=os.environ.copy() if env is None else env,
                text=True,
                stdout=stdout_handle,
                stderr=stderr_handle,
            )
            timed_out = False
            try:
                returncode = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                process.kill()
                returncode = 124
                process.wait()

            stdout_handle.flush()
            stderr_handle.flush()
            stdout_handle.seek(0)
            stderr_handle.seek(0)
            stdout = stdout_handle.read()
            stderr = stderr_handle.read()
            if timed_out:
                if stderr:
                    stderr += "\n"
                stderr += f"timed out after {timeout}s"
            return subprocess.CompletedProcess(argv, returncode, stdout, stderr)


def first_message(completed: subprocess.CompletedProcess[str]) -> str:
    lines: list[str] = []
    for stream in (completed.stderr, completed.stdout):
        lines.extend(line.strip() for line in stream.splitlines() if line.strip())

    if not lines:
        return f"exit code {completed.returncode}"

    def severity(line: str) -> tuple[int, int]:
        lowered = line.lower()
        if ": info:" in lowered:
            return (7, 0)
        if ": error:" in lowered or " error:" in lowered or lowered.startswith("error:"):
            return (0, 0)
        if ": high:" in lowered:
            return (1, 0)
        if ": medium:" in lowered:
            return (2, 0)
        if ": low:" in lowered:
            return (3, 0)
        if "gnatprove:" in lowered:
            return (4, 0)
        if "warning:" in lowered:
            return (5, 0)
        return (6, 0)

    ranked = [
        (severity(line), index, line)
        for index, line in enumerate(lines)
        if ": info:" not in line.lower()
    ]
    if ranked:
        return min(ranked)[2]

    return lines[0]


def format_completed_output(completed: subprocess.CompletedProcess[str]) -> str:
    parts: list[str] = []
    if completed.stdout:
        parts.append(completed.stdout)
    if completed.stderr:
        if parts and not parts[-1].endswith("\n"):
            parts.append("\n")
        parts.append(completed.stderr)
    return "".join(parts)



def record_gnatprove_stage_output(
    result: ProofRunResult,
    stage: str,
    completed: subprocess.CompletedProcess[str],
    *,
    ada_dir: Path,
) -> None:
    raw_output = format_completed_output(completed)
    result.raw_stage_output[stage] = raw_output
    rewritten, diagnostics = rewrite_gnatprove_output(raw_output, ada_dir, stage=stage)
    result.stage_output[stage] = rewritten
    result.diagnostics_json.extend(diagnostics)

def non_info_lines(completed: subprocess.CompletedProcess[str]) -> list[str]:
    lines: list[str] = []
    for stream in (completed.stderr, completed.stdout):
        for raw_line in stream.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            lowered = line.lower()
            if ": info:" in lowered:
                continue
            lines.append(line)
    return lines


def allow_clean_nonzero_gnatprove_exit(
    completed: subprocess.CompletedProcess[str],
    total_row: SummaryRow,
) -> bool:
    if completed.returncode == 0:
        return True
    justified = int(total_row["justified"]["count"])
    unproved = int(total_row["unproved"]["count"])
    if justified != 0 or unproved != 0:
        return False
    return not non_info_lines(completed)


def prepare_proof_toolchain(
    *,
    env: dict[str, str] | None = None,
    build_frontend: bool = True,
) -> ProofToolchain:
    tool_env = os.environ.copy() if env is None else env.copy()
    alr = find_command("alr", ALR_FALLBACK)
    gnatprove = find_command("gnatprove", GNATPROVE_FALLBACK)
    if build_frontend:
        completed = run_command([alr, "build"], cwd=COMPILER_ROOT, env=tool_env)
        if completed.returncode != 0:
            raise RuntimeError(first_message(completed))
    safec = require_safec()
    return ProofToolchain(safec=safec, alr=alr, gnatprove=gnatprove, env=tool_env)


def safe_prove_root(source: Path) -> Path:
    return source.parent / "obj" / source.stem / "prove"


def prepare_proof_root(root: Path) -> dict[str, Path]:
    shutil.rmtree(root, ignore_errors=True)
    paths = {
        "root": root,
        "out": root / "out",
        "iface": root / "iface",
        "ada": root / "ada",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
    return paths


def leading_with_dependencies(source: Path) -> list[str]:
    dependencies: list[str] = []
    with source.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("--"):
                continue
            match = WITH_CLAUSE_RE.match(line)
            if match is None:
                break
            for item in match.group(1).split(","):
                dependency = item.strip()
                if dependency:
                    dependencies.append(dependency)
    return dependencies


def local_dependency_source(source_dir: Path, package_name: str) -> Path | None:
    direct = source_dir / f"{package_name}.safe"
    if direct.exists():
        return direct.resolve()
    needle = f"{package_name}.safe".lower()
    for candidate in source_dir.glob("*.safe"):
        if candidate.name.lower() == needle:
            return candidate.resolve()
    return None


def mirror_with_clauses_into_emitted_unit(source: Path, ada_dir: Path) -> None:
    # Keep in sync with project_cache.mirror_with_clauses_into_emitted_unit.
    dependencies = leading_with_dependencies(source)
    if not dependencies:
        return

    changed = False
    lower_dependencies = [dependency.lower() for dependency in dependencies]
    for suffix in (".ads", ".adb"):
        unit_path = ada_dir / f"{source.stem.lower()}{suffix}"
        if not unit_path.exists():
            continue
        lines = unit_path.read_text(encoding="utf-8").splitlines()
        insertion = 0
        existing_withs: set[str] = set()
        while insertion < len(lines):
            stripped = lines[insertion].strip()
            if not stripped:
                insertion += 1
                continue
            if stripped.lower().startswith("with ") and stripped.endswith(";"):
                existing_withs.add(stripped[5:-1].strip().lower())
                insertion += 1
                continue
            if stripped.lower().startswith("pragma ") and stripped.endswith(";"):
                insertion += 1
                continue
            break

        new_withs = [
            f"with {dependency};"
            for dependency, lowered in zip(dependencies, lower_dependencies)
            if lowered not in existing_withs
        ]
        if not new_withs:
            continue
        updated = lines[:insertion] + new_withs + lines[insertion:]
        unit_path.write_text("\n".join(updated) + "\n", encoding="utf-8")
        changed = True

    if changed:
        write_line_map_sidecar(ada_dir, source.stem)


def write_emitted_project(ada_dir: Path) -> Path:
    lines = [
        "project Build is",
        f'   for Source_Dirs use (".", "{STDLIB_ADA_DIR}");',
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


def compile_emitted_ada(
    ada_dir: Path,
    *,
    toolchain: ProofToolchain,
) -> subprocess.CompletedProcess[str]:
    gpr_path = write_emitted_project(ada_dir)
    argv = [
        toolchain.alr,
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
    return run_command(argv, cwd=COMPILER_ROOT, env=toolchain.env)


def parse_summary_cell(cell: str) -> SummaryCell:
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


def parse_gnatprove_summary(path: Path) -> SummaryTable:
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

    rows: SummaryTable = {}
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


def emit_source_for_proof(
    *,
    toolchain: ProofToolchain,
    source: Path,
    paths: dict[str, Path],
    interface_search_dir: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    argv = [
        str(toolchain.safec),
        "emit",
        str(source),
        "--out-dir",
        str(paths["out"]),
        "--interface-dir",
        str(paths["iface"]),
        "--ada-out-dir",
        str(paths["ada"]),
    ]
    if interface_search_dir is not None:
        argv.extend(["--interface-search-dir", str(interface_search_dir)])
    completed = run_command(
        argv,
        cwd=REPO_ROOT,
        env=toolchain.env,
    )
    return completed


def ensure_interface_dependencies(
    *,
    toolchain: ProofToolchain,
    source: Path,
    paths: dict[str, Path],
    stage_output: dict[str, str],
    log_stage: str,
    visited: set[Path] | None = None,
) -> str | None:
    seen = set() if visited is None else visited
    key = source.resolve()
    if key in seen:
        return None
    seen.add(key)

    logs: list[str] = []
    for dependency_name in leading_with_dependencies(source):
        dep_source = local_dependency_source(source.parent, dependency_name)
        if dep_source is None or dep_source == source.resolve():
            continue
        safei_path = paths["iface"] / f"{dep_source.stem.lower()}.safei.json"
        if safei_path.exists():
            continue
        error = ensure_interface_dependencies(
            toolchain=toolchain,
            source=dep_source,
            paths=paths,
            stage_output=stage_output,
            log_stage=log_stage,
            visited=seen,
        )
        if error is not None:
            return error

        dep_completed = run_command(
            [
                str(toolchain.safec),
                "emit",
                str(dep_source),
                "--out-dir",
                str(paths["out"]),
                "--interface-dir",
                str(paths["iface"]),
                "--ada-out-dir",
                str(paths["ada"]),
                "--interface-search-dir",
                str(paths["iface"]),
            ],
            cwd=REPO_ROOT,
            env=toolchain.env,
        )
        captured = format_completed_output(dep_completed)
        if captured:
            logs.append(captured)
        if dep_completed.returncode != 0:
            stage_output[log_stage] = "".join(logs)
            return (
                f"dependency interface emit failed for {dep_source.name}: "
                f"{first_message(dep_completed)}"
            )
        if not safei_path.exists():
            stage_output[log_stage] = "".join(logs)
            return f"dependency interface emit missing {safei_path.name}"
        mirror_with_clauses_into_emitted_unit(dep_source, paths["ada"])

    if logs:
        stage_output[log_stage] = stage_output.get(log_stage, "") + "".join(logs)
    return None


def summary_counts(row: SummaryRow | None) -> dict[str, int]:
    if row is None:
        return {"total": 0, "justified": 0, "unproved": 0}
    return {
        "total": int(row["total"]["count"]),
        "justified": int(row["justified"]["count"]),
        "unproved": int(row["unproved"]["count"]),
    }


def run_gnatprove_project(
    *,
    project_dir: Path,
    project_file: str,
    toolchain: ProofToolchain,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
) -> tuple[bool, str]:
    summary_path = project_dir / "obj" / "gnatprove" / "gnatprove.out"
    for mode, switches in (
        ("flow", FLOW_SWITCHES),
        ("prove", PROVE_SWITCHES if prove_switches is None else prove_switches),
    ):
        completed = run_command(
            [
                toolchain.alr,
                "exec",
                "--",
                toolchain.gnatprove,
                "-P",
                project_file,
                *switches,
            ],
            cwd=project_dir,
            env=toolchain.env,
            timeout=command_timeout,
        )
        try:
            rows = parse_gnatprove_summary(summary_path)
        except (FileNotFoundError, RuntimeError) as exc:
            if completed.returncode != 0:
                return False, f"{mode} failed: {first_message(completed)}"
            return False, f"{mode} summary error: {exc}"
        if not allow_clean_nonzero_gnatprove_exit(completed, rows["Total"]):
            return False, f"{mode} failed: {first_message(completed)}"
    return True, ""



def tool_identity(value: str) -> str:
    candidate = Path(value)
    if candidate.is_absolute() and candidate.exists():
        return sha256_file(candidate)
    return value


def compile_cached_proof_project(
    project_paths: dict[str, Path],
    *,
    ada_dir: Path,
    source: Path,
    toolchain: ProofToolchain,
) -> subprocess.CompletedProcess[str]:
    argv = [
        toolchain.alr,
        "exec",
        "--",
        "gprbuild",
        "-c",
        "-P",
        str(project_paths["gpr"]),
        emitted_primary_unit_for_source(ada_dir, source) + ".adb",
    ]
    if (ada_dir / "gnat.adc").exists():
        argv.extend(["-cargs", f"-gnatec={ada_dir / 'gnat.adc'}"])
    return run_command(argv, cwd=COMPILER_ROOT, env=toolchain.env)


def run_cached_source_proof(
    *,
    toolchain: ProofToolchain,
    source: Path,
    run_check: bool,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
    target_bits: int = 64,
) -> ProofRunResult:
    result = ProofRunResult(
        source=source,
        proof_root=safe_prove_paths(source, target_bits=target_bits)["root"],
        passed=False,
        stage="check" if run_check else "emit",
    )

    try:
        safec_hash = sha256_file(toolchain.safec)
        shared_paths, state, sources = ensure_project_emitted(
            safec=toolchain.safec,
            safec_hash=safec_hash,
            source=source,
            env=toolchain.env,
            run_check=run_check,
            stage_output=result.stage_output,
            log_stage=result.stage,
            target_bits=target_bits,
        )
    except ProjectEmitError as exc:
        result.stage = exc.stage
        result.detail = exc.detail
        if exc.output and exc.stage not in result.stage_output:
            result.stage_output[exc.stage] = exc.output
        return result

    project_text = proof_project_text(
        ada_dir=shared_paths["ada"],
        has_gnat_adc=(shared_paths["ada"] / "gnat.adc").exists(),
    )
    fingerprint = proof_fingerprint(
        source=source,
        sources=sources,
        state=state,
        safec_hash=safec_hash,
        gnatprove_id=tool_identity(toolchain.gnatprove),
        flow_switches=FLOW_SWITCHES,
        prove_switches=PROVE_SWITCHES if prove_switches is None else prove_switches,
        project_text=project_text,
        shared_paths=shared_paths,
        target_bits=target_bits,
    )
    cached = state["proofs"].get(source_key(source))
    cached_project_paths = safe_prove_paths(source, target_bits=target_bits)
    cached_artifacts_present = (
        cached_project_paths["root"].exists() and cached_project_paths["summary"].exists()
    )
    if cached and cached.get("fingerprint") == fingerprint and cached.get("passed"):
        if cached_artifacts_present:
            result.stage = "prove"
            result.passed = True
            result.flow_summary = cached.get("flow_summary")
            result.prove_summary = cached.get("prove_summary")
            result.detail = ""
            return result
        state["proofs"].pop(source_key(source), None)
        save_project_state(shared_paths, state)

    project_paths = ensure_safe_prove_root(source, target_bits=target_bits)
    write_safe_prove_project(project_paths, ada_dir=shared_paths["ada"])

    compile_completed = compile_cached_proof_project(
        project_paths,
        ada_dir=shared_paths["ada"],
        source=source,
        toolchain=toolchain,
    )
    result.stage = "compile"
    result.stage_output["compile"] = format_completed_output(compile_completed)
    if compile_completed.returncode != 0:
        result.detail = f"compile failed: {first_message(compile_completed)}"
        state["proofs"].pop(source_key(source), None)
        save_project_state(shared_paths, state)
        return result

    adc_path = shared_paths["ada"] / "gnat.adc"
    summary_path = project_paths["summary"]
    for mode, switches in (
        ("flow", FLOW_SWITCHES),
        ("prove", PROVE_SWITCHES if prove_switches is None else prove_switches),
    ):
        argv = [
            toolchain.alr,
            "exec",
            "--",
            toolchain.gnatprove,
            "-P",
            str(project_paths["gpr"]),
            *switches,
        ]
        if adc_path.exists():
            argv.extend(["-cargs", f"-gnatec={adc_path}"])
        completed = run_command(
            argv,
            cwd=COMPILER_ROOT,
            env=toolchain.env,
            timeout=command_timeout,
        )
        result.stage = mode
        record_gnatprove_stage_output(result, mode, completed, ada_dir=shared_paths["ada"])
        try:
            rows = parse_gnatprove_summary(summary_path)
        except (FileNotFoundError, RuntimeError) as exc:
            result.detail = (
                f"{mode} failed: {first_message(completed)}"
                if completed.returncode != 0
                else f"{mode} summary error: {exc}"
            )
            state["proofs"].pop(source_key(source), None)
            save_project_state(shared_paths, state)
            return result

        total_row = rows["Total"]
        if not allow_clean_nonzero_gnatprove_exit(completed, total_row):
            result.detail = f"{mode} failed: {first_message(completed)}"
            state["proofs"].pop(source_key(source), None)
            save_project_state(shared_paths, state)
            return result
        if mode == "flow":
            result.flow_summary = total_row
        else:
            result.prove_summary = total_row
        justified = int(total_row["justified"]["count"])
        unproved = int(total_row["unproved"]["count"])
        if justified != 0 or unproved != 0:
            result.detail = f"{mode} summary has justified={justified}, unproved={unproved}"
            state["proofs"].pop(source_key(source), None)
            save_project_state(shared_paths, state)
            return result

    result.passed = True
    result.detail = ""
    state["proofs"][source_key(source)] = {
        "fingerprint": fingerprint,
        "passed": True,
        "flow_summary": result.flow_summary,
        "prove_summary": result.prove_summary,
    }
    save_project_state(shared_paths, state)
    return result

def run_source_proof(
    *,
    toolchain: ProofToolchain,
    source: Path,
    proof_root: Path,
    run_check: bool,
    prove_switches: list[str] | None = None,
    command_timeout: int | None = None,
) -> ProofRunResult:
    result = ProofRunResult(
        source=source,
        proof_root=proof_root,
        passed=False,
        stage="check" if run_check else "emit",
    )

    paths = prepare_proof_root(proof_root)
    dependency_error = ensure_interface_dependencies(
        toolchain=toolchain,
        source=source,
        paths=paths,
        stage_output=result.stage_output,
        log_stage=result.stage,
    )
    if dependency_error is not None:
        result.detail = dependency_error
        return result

    interface_search_dir = paths["iface"] if any(paths["iface"].glob("*.safei.json")) else None

    if run_check:
        check_completed = run_command(
            [
                str(toolchain.safec),
                "check",
                str(source),
                *(
                    ["--interface-search-dir", str(interface_search_dir)]
                    if interface_search_dir is not None
                    else []
                ),
            ],
            cwd=REPO_ROOT,
            env=toolchain.env,
        )
        result.stage_output["check"] = result.stage_output.get("check", "") + format_completed_output(
            check_completed
        )
        if check_completed.returncode != 0:
            result.detail = f"check failed: {first_message(check_completed)}"
            return result

    emit_completed = emit_source_for_proof(
        toolchain=toolchain,
        source=source,
        paths=paths,
        interface_search_dir=interface_search_dir,
    )
    result.stage = "emit"
    result.stage_output["emit"] = format_completed_output(emit_completed)
    if emit_completed.returncode != 0:
        result.detail = f"emit failed: {first_message(emit_completed)}"
        return result
    mirror_with_clauses_into_emitted_unit(source, paths["ada"])

    compile_completed = compile_emitted_ada(paths["ada"], toolchain=toolchain)
    result.stage = "compile"
    result.stage_output["compile"] = format_completed_output(compile_completed)
    if compile_completed.returncode != 0:
        result.detail = f"compile failed: {first_message(compile_completed)}"
        return result

    gpr_path = write_emitted_project(paths["ada"])
    adc_path = paths["ada"] / "gnat.adc"
    summary_path = paths["ada"] / "obj" / "gnatprove" / "gnatprove.out"

    for mode, switches in (
        ("flow", FLOW_SWITCHES),
        ("prove", PROVE_SWITCHES if prove_switches is None else prove_switches),
    ):
        argv = [
            toolchain.alr,
            "exec",
            "--",
            toolchain.gnatprove,
            "-P",
            str(gpr_path),
            *switches,
        ]
        if adc_path.exists():
            argv.extend(["-cargs", f"-gnatec={adc_path}"])
        completed = run_command(
            argv,
            cwd=COMPILER_ROOT,
            env=toolchain.env,
            timeout=command_timeout,
        )
        result.stage = mode
        record_gnatprove_stage_output(result, mode, completed, ada_dir=paths["ada"])
        try:
            rows = parse_gnatprove_summary(summary_path)
        except (FileNotFoundError, RuntimeError) as exc:
            result.detail = (
                f"{mode} failed: {first_message(completed)}"
                if completed.returncode != 0
                else f"{mode} summary error: {exc}"
            )
            return result

        total_row = rows["Total"]
        if not allow_clean_nonzero_gnatprove_exit(completed, total_row):
            result.detail = f"{mode} failed: {first_message(completed)}"
            return result
        if mode == "flow":
            result.flow_summary = total_row
        else:
            result.prove_summary = total_row
        justified = int(total_row["justified"]["count"])
        unproved = int(total_row["unproved"]["count"])
        if justified != 0 or unproved != 0:
            result.detail = f"{mode} summary has justified={justified}, unproved={unproved}"
            return result

    result.passed = True
    result.detail = ""
    return result


__all__ = [
    "FLOW_SWITCHES",
    "PROVE_SWITCHES",
    "ProofRunResult",
    "ProofToolchain",
    "compile_emitted_ada",
    "emit_source_for_proof",
    "first_message",
    "format_completed_output",
    "parse_gnatprove_summary",
    "prepare_proof_root",
    "prepare_proof_toolchain",
    "prove_switches_for_level",
    "run_cached_source_proof",
    "run_command",
    "run_gnatprove_project",
    "run_source_proof",
    "safe_prove_root",
    "summary_counts",
    "write_emitted_project",
]
