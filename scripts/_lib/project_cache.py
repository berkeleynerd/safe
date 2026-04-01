"""Shared per-project incremental cache helpers for repo-local CLI commands."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .harness_common import REPO_ROOT, sha256_file, sha256_text
from .pr09_emit import emitted_body_file
from .pr111_language_eval import executable_name, safe_build_main_text

CACHE_VERSION = 1
STDLIB_ADA_DIR = REPO_ROOT / "compiler_impl" / "stdlib" / "ada"
WITH_CLAUSE_RE = re.compile(r"^with\s+(.+);$", re.IGNORECASE)


@dataclass
class ProjectEmitError(RuntimeError):
    stage: str
    detail: str
    output: str = ""


def run_capture(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
) -> subprocess.CompletedProcess[str]:
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


def format_output(completed: subprocess.CompletedProcess[str]) -> str:
    chunks: list[str] = []
    if completed.stdout:
        chunks.append(completed.stdout)
    if completed.stderr:
        if chunks and not chunks[-1].endswith("\n"):
            chunks.append("\n")
        chunks.append(completed.stderr)
    return "".join(chunks)


def emit_source(
    *,
    safec: Path,
    source: Path,
    paths: dict[str, Path],
    env: dict[str, str],
    interface_dir: Path | None,
) -> subprocess.CompletedProcess[str]:
    argv = [
        str(safec),
        "emit",
        str(source),
        "--out-dir",
        str(paths["out"]),
        "--interface-dir",
        str(paths["iface"]),
        "--ada-out-dir",
        str(paths["ada"]),
    ]
    if interface_dir is not None:
        argv.extend(["--interface-search-dir", str(interface_dir)])
    return run_capture(argv, cwd=REPO_ROOT, env=env)


def ensure_project_emitted(
    *,
    safec: Path,
    source: Path,
    env: dict[str, str],
    run_check: bool,
    stage_output: dict[str, str] | None = None,
    log_stage: str = "check",
) -> tuple[dict[str, Path], dict, list[Path]]:
    paths, state = prepare_project_cache(source)
    sources = resolve_project_sources(source)
    logs: list[str] = []
    captured_output = stage_output if stage_output is not None else {}
    emitted_units: list[Path] = []

    for unit in sources:
        previous = state["units"].get(source_key(unit))
        metadata = source_metadata(unit, previous)
        direct_dependencies = leading_with_dependencies(unit)
        dependency_interfaces: dict[str, str] = {}
        for dependency_name in direct_dependencies:
            dependency_source = local_dependency_source(unit.parent, dependency_name)
            if dependency_source is None:
                raise ProjectEmitError(
                    log_stage,
                    f"local dependency source not found for package `{dependency_name}` referenced by {unit.name}",
                )
            dependency_interfaces[source_key(dependency_source)] = interface_hash(paths, dependency_source)

        if unit_entry_is_current(
            paths=paths,
            previous=previous,
            metadata=metadata,
            direct_dependencies=direct_dependencies,
            dependency_interfaces=dependency_interfaces,
        ):
            emitted_units.append(unit)
            continue

        interface_dir = prepare_interface_search_dir(paths, unit, emitted_units)
        if run_check and unit == source:
            check_completed = run_capture(
                [
                    str(safec),
                    "check",
                    str(source),
                    *(
                        ["--interface-search-dir", str(interface_dir)]
                        if interface_dir is not None
                        else []
                    ),
                ],
                cwd=REPO_ROOT,
                env=env,
            )
            check_output = "".join(logs) + format_output(check_completed)
            logs.clear()
            if check_output:
                captured_output["check"] = captured_output.get("check", "") + check_output
            if check_completed.returncode != 0:
                raise ProjectEmitError("check", f"check failed: {first_message(check_completed)}", check_output)

        emit_completed = emit_source(
            safec=safec,
            source=unit,
            paths=paths,
            env=env,
            interface_dir=interface_dir,
        )
        emit_output = format_output(emit_completed)
        if unit == source:
            if emit_output:
                captured_output["emit"] = emit_output
        elif emit_output:
            logs.append(emit_output)

        if emit_completed.returncode != 0:
            if unit == source:
                raise ProjectEmitError("emit", f"emit failed: {first_message(emit_completed)}", emit_output)
            combined = "".join(logs)
            if combined:
                captured_output[log_stage] = captured_output.get(log_stage, "") + combined
            raise ProjectEmitError(
                log_stage,
                f"dependency interface emit failed for {unit.name}: {first_message(emit_completed)}",
                combined,
            )

        mirror_with_clauses_into_emitted_unit(unit, paths["ada"])
        record_unit_state(
            state,
            source=unit,
            metadata=metadata,
            direct_dependencies=direct_dependencies,
            dependency_interfaces=dependency_interfaces,
            artifact_hashes=unit_artifact_hashes(paths, unit),
        )
        emitted_units.append(unit)

    save_project_state(paths, state)
    return paths, state, sources


def default_project_state() -> dict:
    return {
        "version": CACHE_VERSION,
        "units": {},
        "builds": {},
        "proofs": {},
    }


def project_cache_root(source: Path) -> Path:
    return source.parent / ".safe-build"


def project_cache_paths(source: Path) -> dict[str, Path]:
    root = project_cache_root(source)
    return {
        "root": root,
        "state": root / "state.json",
        "out": root / "out",
        "iface": root / "iface",
        "ada": root / "ada",
    }


def reset_project_cache(source: Path) -> None:
    shutil.rmtree(project_cache_root(source), ignore_errors=True)


def prepare_project_cache(source: Path) -> tuple[dict[str, Path], dict]:
    paths = project_cache_paths(source)
    payload: dict | None = None
    if paths["state"].exists():
        try:
            payload = json.loads(paths["state"].read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            payload = None
    if payload is not None and payload.get("version") != CACHE_VERSION:
        shutil.rmtree(paths["root"], ignore_errors=True)
        payload = None

    for key in ("root", "out", "iface", "ada"):
        paths[key].mkdir(parents=True, exist_ok=True)

    state = default_project_state() if payload is None else payload
    state.setdefault("version", CACHE_VERSION)
    state.setdefault("units", {})
    state.setdefault("builds", {})
    state.setdefault("proofs", {})
    return paths, state


def save_project_state(paths: dict[str, Path], state: dict) -> None:
    state["version"] = CACHE_VERSION
    paths["state"].write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def source_key(source: Path) -> str:
    return str(source.resolve())


def source_metadata(source: Path, previous: dict | None = None) -> dict[str, int | str]:
    stat = source.stat()
    size = stat.st_size
    mtime_ns = stat.st_mtime_ns
    return {
        "source_size": size,
        "source_mtime_ns": mtime_ns,
        "source_hash": sha256_file(source),
    }


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


def resolve_project_sources(root_source: Path) -> list[Path]:
    ordered: list[Path] = []
    permanent: set[Path] = set()
    temporary: set[Path] = set()

    def visit(source: Path) -> None:
        resolved = source.resolve()
        if resolved in permanent:
            return
        if resolved in temporary:
            raise RuntimeError(f"dependency cycle detected while resolving {source.name}")
        temporary.add(resolved)
        for dependency_name in leading_with_dependencies(resolved):
            dependency_source = local_dependency_source(resolved.parent, dependency_name)
            if dependency_source is None:
                raise RuntimeError(
                    f"local dependency source not found for package `{dependency_name}` referenced by {resolved.name}"
                )
            visit(dependency_source)
        temporary.remove(resolved)
        permanent.add(resolved)
        ordered.append(resolved)

    visit(root_source)
    return ordered


def mirror_with_clauses_into_emitted_unit(source: Path, ada_dir: Path) -> None:
    dependencies = leading_with_dependencies(source)
    if not dependencies:
        return

    lowered_dependencies = [dependency.lower() for dependency in dependencies]
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
        additions = [
            f"with {dependency};"
            for dependency, lowered in zip(dependencies, lowered_dependencies)
            if lowered not in existing_withs
        ]
        if not additions:
            continue
        unit_path.write_text("\n".join(lines[:insertion] + additions + lines[insertion:]) + "\n", encoding="utf-8")


def unit_artifact_hashes(paths: dict[str, Path], source: Path) -> dict[str, str]:
    stem = source.stem.lower()
    candidates = [
        paths["out"] / f"{stem}.ast.json",
        paths["out"] / f"{stem}.typed.json",
        paths["out"] / f"{stem}.mir.json",
        paths["iface"] / f"{stem}.safei.json",
        paths["ada"] / f"{stem}.ads",
        paths["ada"] / f"{stem}.adb",
    ]
    hashes: dict[str, str] = {}
    for path in candidates:
        if path.exists():
            hashes[str(path.relative_to(paths["root"]))] = sha256_file(path)
    return hashes


def unit_artifacts_present(paths: dict[str, Path], artifact_hashes: dict[str, str]) -> bool:
    return all((paths["root"] / relative).exists() for relative in artifact_hashes)


def interface_hash(paths: dict[str, Path], source: Path) -> str:
    safei_path = paths["iface"] / f"{source.stem.lower()}.safei.json"
    if not safei_path.exists():
        raise FileNotFoundError(f"missing dependency interface {safei_path.name}")
    return sha256_file(safei_path)


def prepare_interface_search_dir(paths: dict[str, Path], unit: Path, dependencies: list[Path]) -> Path | None:
    if not dependencies:
        return None
    search_dir = paths["root"] / "iface-search" / unit.stem.lower()
    shutil.rmtree(search_dir, ignore_errors=True)
    search_dir.mkdir(parents=True, exist_ok=True)
    for dependency in dependencies:
        source = paths["iface"] / f"{dependency.stem.lower()}.safei.json"
        if not source.exists():
            raise FileNotFoundError(f"missing dependency interface {source.name}")
        shutil.copy2(source, search_dir / source.name)
    return search_dir


def record_unit_state(
    state: dict,
    *,
    source: Path,
    metadata: dict[str, int | str],
    direct_dependencies: list[str],
    dependency_interfaces: dict[str, str],
    artifact_hashes: dict[str, str],
) -> None:
    entry = {
        **metadata,
        "direct_dependencies": direct_dependencies,
        "dependency_interfaces": dependency_interfaces,
        "artifact_hashes": artifact_hashes,
    }
    entry["emit_signature"] = sha256_text(
        json.dumps(
            {
                "source_hash": entry["source_hash"],
                "direct_dependencies": direct_dependencies,
                "dependency_interfaces": dependency_interfaces,
                "artifact_hashes": artifact_hashes,
            },
            sort_keys=True,
        )
    )
    state["units"][source_key(source)] = entry


def unit_entry_is_current(
    *,
    paths: dict[str, Path],
    previous: dict | None,
    metadata: dict[str, int | str],
    direct_dependencies: list[str],
    dependency_interfaces: dict[str, str],
) -> bool:
    if previous is None:
        return False
    if previous.get("source_hash") != metadata["source_hash"]:
        return False
    if previous.get("direct_dependencies") != direct_dependencies:
        return False
    if previous.get("dependency_interfaces") != dependency_interfaces:
        return False
    artifact_hashes = previous.get("artifact_hashes", {})
    return bool(artifact_hashes) and unit_artifacts_present(paths, artifact_hashes)


def unit_emit_signature(state: dict, source: Path) -> str:
    entry = state["units"].get(source_key(source))
    if not entry:
        raise KeyError(f"missing cached unit state for {source}")
    signature = entry.get("emit_signature")
    if not signature:
        raise KeyError(f"missing cached emit signature for {source}")
    return str(signature)


def shared_support_hashes(paths: dict[str, Path], sources: list[Path]) -> dict[str, str]:
    owned_names = {f"{source.stem.lower()}.ads" for source in sources}
    owned_names.update(f"{source.stem.lower()}.adb" for source in sources)
    hashes: dict[str, str] = {}
    for path in sorted(paths["ada"].glob("*")):
        if not path.is_file():
            continue
        if path.name in owned_names or path.name == "main.adb":
            continue
        hashes[str(path.relative_to(paths["root"]))] = sha256_file(path)
    return hashes


def safe_build_paths(source: Path) -> dict[str, Path]:
    root = source.parent / "obj" / source.stem
    return {
        "root": root,
        "obj": root / "obj",
        "gpr": root / "build.gpr",
        "main": root / "main.adb",
        "exe": root / executable_name(),
    }


def ensure_safe_build_root(source: Path) -> dict[str, Path]:
    paths = safe_build_paths(source)
    paths["root"].mkdir(parents=True, exist_ok=True)
    paths["obj"].mkdir(parents=True, exist_ok=True)
    return paths


def safe_prove_paths(source: Path) -> dict[str, Path]:
    root = source.parent / "obj" / source.stem / "prove"
    return {
        "root": root,
        "obj": root / "obj",
        "gpr": root / "build.gpr",
        "summary": root / "obj" / "gnatprove" / "gnatprove.out",
    }


def ensure_safe_prove_root(source: Path) -> dict[str, Path]:
    paths = safe_prove_paths(source)
    shutil.rmtree(paths["root"], ignore_errors=True)
    paths["root"].mkdir(parents=True, exist_ok=True)
    paths["obj"].mkdir(parents=True, exist_ok=True)
    return paths


def reset_root_workdirs(source: Path) -> None:
    shutil.rmtree(source.parent / "obj" / source.stem, ignore_errors=True)


def emitted_primary_unit_for_source(ada_dir: Path, source: Path) -> str:
    source_body = ada_dir / f"{source.stem.lower()}.adb"
    if source_body.exists():
        return source_body.stem
    body = emitted_body_file(ada_dir)
    if body.stem == "main":
        candidates = sorted(path for path in ada_dir.glob("*.adb") if path.stem != "main")
        if candidates:
            return candidates[0].stem
    return body.stem


def safe_build_project_text(*, ada_dir: Path, has_gnat_adc: bool) -> str:
    lines = [
        "project Build is",
        f'   for Source_Dirs use (".", "{ada_dir}", "{STDLIB_ADA_DIR}");',
        '   for Object_Dir use "obj";',
        '   for Exec_Dir use ".";',
        '   for Main use ("main.adb");',
    ]
    if has_gnat_adc:
        lines.extend(
            [
                "   package Compiler is",
                f'      for Default_Switches ("Ada") use ("-gnatec={ada_dir / "gnat.adc"}");',
                "   end Compiler;",
            ]
        )
    lines.append("end Build;")
    return "\n".join(lines) + "\n"


def proof_project_text(*, ada_dir: Path, has_gnat_adc: bool) -> str:
    lines = [
        "project Build is",
        f'   for Source_Dirs use ("{ada_dir}", "{STDLIB_ADA_DIR}");',
        '   for Object_Dir use "obj";',
    ]
    if has_gnat_adc:
        lines.extend(
            [
                "   package Compiler is",
                f'      for Default_Switches ("Ada") use ("-gnatec={ada_dir / "gnat.adc"}");',
                "   end Compiler;",
            ]
        )
    lines.append("end Build;")
    return "\n".join(lines) + "\n"


def write_safe_build_support_files(paths: dict[str, Path], *, ada_dir: Path, source: Path) -> tuple[str, str]:
    unit_name = emitted_primary_unit_for_source(ada_dir, source)
    main_text = ""
    if unit_name == "main":
        if paths["main"].exists():
            paths["main"].unlink()
    else:
        main_text = safe_build_main_text(unit_name)
        current_main = paths["main"].read_text(encoding="utf-8") if paths["main"].exists() else None
        if current_main != main_text:
            paths["main"].write_text(main_text, encoding="utf-8")

    project_text = safe_build_project_text(ada_dir=ada_dir, has_gnat_adc=(ada_dir / "gnat.adc").exists())
    current_project = paths["gpr"].read_text(encoding="utf-8") if paths["gpr"].exists() else None
    if current_project != project_text:
        paths["gpr"].write_text(project_text, encoding="utf-8")
    return main_text, project_text


def write_safe_prove_project(paths: dict[str, Path], *, ada_dir: Path) -> str:
    project_text = proof_project_text(ada_dir=ada_dir, has_gnat_adc=(ada_dir / "gnat.adc").exists())
    paths["gpr"].write_text(project_text, encoding="utf-8")
    return project_text


def build_fingerprint(
    *,
    source: Path,
    sources: list[Path],
    state: dict,
    safec_hash: str,
    main_text: str,
    project_text: str,
    shared_paths: dict[str, Path],
) -> str:
    return sha256_text(
        json.dumps(
            {
                "kind": "build",
                "version": CACHE_VERSION,
                "source": source_key(source),
                "safec_hash": safec_hash,
                "units": [unit_emit_signature(state, item) for item in sources],
                "shared_support": shared_support_hashes(shared_paths, sources),
                "main_text": main_text,
                "project_text": project_text,
            },
            sort_keys=True,
        )
    )


def proof_fingerprint(
    *,
    source: Path,
    sources: list[Path],
    state: dict,
    safec_hash: str,
    gnatprove_id: str,
    flow_switches: list[str],
    prove_switches: list[str],
    project_text: str,
    shared_paths: dict[str, Path],
) -> str:
    return sha256_text(
        json.dumps(
            {
                "kind": "prove",
                "version": CACHE_VERSION,
                "source": source_key(source),
                "safec_hash": safec_hash,
                "gnatprove_id": gnatprove_id,
                "flow_switches": flow_switches,
                "prove_switches": prove_switches,
                "units": [unit_emit_signature(state, item) for item in sources],
                "shared_support": shared_support_hashes(shared_paths, sources),
                "project_text": project_text,
            },
            sort_keys=True,
        )
    )
