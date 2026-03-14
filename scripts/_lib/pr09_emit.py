"""Shared helpers for PR09 Ada emission gates."""

from __future__ import annotations

import json
import os
import textwrap
from pathlib import Path
from typing import Any

from .harness_common import (
    REPO_ROOT,
    display_path,
    find_command,
    read_diag_json,
    require,
    require_repo_command,
    run,
    sha256_file,
)


COMPILER_ROOT = REPO_ROOT / "compiler_impl"
SAFE_RUNTIME_TEMPLATE = REPO_ROOT / "companion" / "templates" / "safe_runtime.ads"


def repo_arg(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def require_safec() -> Path:
    return require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")


def gprbuild_command() -> str:
    try:
        return find_command("gprbuild")
    except FileNotFoundError:
        for fallback in (
            Path.home() / ".alire" / "bin" / "gprbuild",
            Path.home() / ".local" / "bin" / "gprbuild",
        ):
            if fallback.exists():
                return str(fallback)
        raise


def python_command() -> str:
    return find_command("python3")


def emit_paths(root: Path, source: Path) -> dict[str, Path]:
    stem = source.stem.lower()
    return {
        "ast": root / "out" / f"{stem}.ast.json",
        "typed": root / "out" / f"{stem}.typed.json",
        "mir": root / "out" / f"{stem}.mir.json",
        "safei": root / "iface" / f"{stem}.safei.json",
    }


def list_files(root: Path) -> list[str]:
    if not root.exists():
        return []
    return sorted(str(path.relative_to(root)) for path in root.rglob("*") if path.is_file())


def file_hashes(root: Path) -> dict[str, str]:
    return {relative: sha256_file(root / relative) for relative in list_files(root)}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_emit(
    *,
    safec: Path,
    source: Path,
    out_dir: Path,
    iface_dir: Path,
    ada_dir: Path,
    env: dict[str, str],
    temp_root: Path,
    expected_returncode: int = 0,
) -> dict[str, Any]:
    return run(
        [
            str(safec),
            "emit",
            repo_arg(source),
            "--out-dir",
            str(out_dir),
            "--interface-dir",
            str(iface_dir),
            "--ada-out-dir",
            str(ada_dir),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=expected_returncode,
    )


def ensure_emit_success(
    *,
    source: Path,
    root: Path,
) -> dict[str, Path]:
    paths = emit_paths(root, source)
    for label, path in paths.items():
        require(path.exists(), f"{source}: missing {label} artifact {display_path(path)}")
    require((root / "ada").exists(), f"{source}: missing Ada output dir")
    adb_files = sorted(
        path
        for path in (root / "ada").glob("*.adb")
        if path.name != "safe_runtime.adb"
    )
    require(adb_files, f"{source}: expected emitted .adb file")
    return paths


def ensure_emit_failure_is_atomic(*, root: Path) -> dict[str, list[str]]:
    observed = {
        "out": list_files(root / "out"),
        "iface": list_files(root / "iface"),
        "ada": list_files(root / "ada"),
    }
    require(observed["out"] == [], f"unexpected JSON outputs after failed emit: {observed['out']}")
    require(observed["iface"] == [], f"unexpected interface outputs after failed emit: {observed['iface']}")
    require(observed["ada"] == [], f"unexpected Ada outputs after failed emit: {observed['ada']}")
    return observed


def emitted_ada_files(ada_dir: Path) -> list[str]:
    return sorted(path.name for path in ada_dir.glob("*") if path.is_file())


def emitted_body_file(ada_dir: Path) -> Path:
    candidates = sorted(
        path for path in ada_dir.glob("*.adb") if path.name != "safe_runtime.adb"
    )
    require(candidates, f"{display_path(ada_dir)}: expected emitted .adb file")
    return candidates[0]


def compare_dirs(left: Path, right: Path) -> dict[str, dict[str, str]]:
    left_files = list_files(left)
    right_files = list_files(right)
    require(left_files == right_files, f"non-deterministic file set: {left_files} vs {right_files}")
    hashes: dict[str, dict[str, str]] = {}
    for relative in left_files:
        left_path = left / relative
        right_path = right / relative
        require(
            left_path.read_bytes() == right_path.read_bytes(),
            f"non-deterministic file contents for {relative}",
        )
        hashes[relative] = {
            "sha256": sha256_file(left_path),
        }
    return hashes


def compare_against_snapshot(*, actual_dir: Path, golden_dir: Path) -> dict[str, dict[str, str]]:
    actual_files = list_files(actual_dir)
    golden_files = list_files(golden_dir)
    require(
        actual_files == golden_files,
        f"golden file-set mismatch: actual {actual_files}, expected {golden_files}",
    )
    report: dict[str, dict[str, str]] = {}
    for relative in actual_files:
        actual_path = actual_dir / relative
        golden_path = golden_dir / relative
        require(
            actual_path.read_bytes() == golden_path.read_bytes(),
            f"golden mismatch for {relative}",
        )
        report[relative] = {"sha256": sha256_file(actual_path)}
    return report


def structural_assertions(path: Path, required_fragments: list[str]) -> list[str]:
    text = path.read_text(encoding="utf-8")
    for fragment in required_fragments:
        require(fragment in text, f"{display_path(path)} missing required fragment: {fragment}")
    return required_fragments


def safe_runtime_matches_template(ada_dir: Path) -> dict[str, str]:
    emitted = ada_dir / "safe_runtime.ads"
    require(emitted.exists(), f"{display_path(ada_dir)}: expected safe_runtime.ads")
    template_text = SAFE_RUNTIME_TEMPLATE.read_text(encoding="utf-8")
    emitted_text = emitted.read_text(encoding="utf-8")
    require(emitted_text == template_text, "emitted safe_runtime.ads drifted from companion template")
    return {
        "emitted": sha256_file(emitted),
        "template": sha256_file(SAFE_RUNTIME_TEMPLATE),
    }


def compile_emitted_ada(
    *,
    ada_dir: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    gpr_path = ada_dir / "build.gpr"
    if (ada_dir / "gnat.adc").exists():
        compiler_pkg = textwrap.dedent(
            """\
               package Compiler is
                  for Default_Switches ("Ada") use ("-gnatec=gnat.adc");
               end Compiler;
            """
        )
    else:
        compiler_pkg = ""
    gpr_path.write_text(
        textwrap.dedent(
            f"""\
            project Build is
               for Source_Dirs use (".");
               for Object_Dir use "obj";
            {compiler_pkg}end Build;
            """
        ),
        encoding="utf-8",
    )
    return run(
        [
            gprbuild_command(),
            "-c",
            "-P",
            str(gpr_path),
            emitted_body_file(ada_dir).name,
        ],
        cwd=ada_dir,
        env=env,
        temp_root=temp_root,
    )


def emit_with_determinism(
    *,
    safec: Path,
    source: Path,
    root_a: Path,
    root_b: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    for root in (root_a, root_b):
        (root / "out").mkdir(parents=True, exist_ok=True)
        (root / "iface").mkdir(parents=True, exist_ok=True)
        (root / "ada").mkdir(parents=True, exist_ok=True)
        run_emit(
            safec=safec,
            source=source,
            out_dir=root / "out",
            iface_dir=root / "iface",
            ada_dir=root / "ada",
            env=env,
            temp_root=temp_root,
        )
        ensure_emit_success(source=source, root=root)

    return {
        "json_and_interface": compare_dirs(root_a / "out", root_b / "out")
        | compare_dirs(root_a / "iface", root_b / "iface"),
        "ada": compare_dirs(root_a / "ada", root_b / "ada"),
    }


def first_reason(result: dict[str, Any], label: str) -> str:
    payload = read_diag_json(result["stdout"], label)
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{label}: expected at least one diagnostic")
    return diagnostics[0]["reason"]
