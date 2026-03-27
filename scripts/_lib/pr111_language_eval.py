"""Shared helpers for the PR11.1 language-evaluation harness."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from .harness_common import REPO_ROOT, require
from .pr09_emit import COMPILER_ROOT, alr_command, emitted_body_file, require_safec


STARTER_CORPUS = (
    "samples/rosetta/arithmetic/fibonacci.safe",
    "samples/rosetta/arithmetic/gcd.safe",
    "samples/rosetta/arithmetic/factorial.safe",
    "samples/rosetta/arithmetic/collatz_bounded.safe",
    "samples/rosetta/sorting/bubble_sort.safe",
    "samples/rosetta/sorting/binary_search.safe",
    "samples/rosetta/data_structures/bounded_stack.safe",
    "samples/rosetta/concurrency/producer_consumer.safe",
)

CANDIDATE_EXPANSIONS = (
    "linked_list_reverse.safe",
    "prime_sieve_pipeline.safe",
)

DEFERRED_CANDIDATES = (
    "trapezoidal_rule.safe",
    "newton_sqrt_bounded.safe",
)


def starter_corpus_paths() -> list[Path]:
    return [REPO_ROOT / relative for relative in STARTER_CORPUS]


def safe_launcher_path() -> Path:
    return REPO_ROOT / "safe"


def safe_build_root(source: Path) -> Path:
    return source.parent / "obj" / source.stem


def safe_build_paths(source: Path) -> dict[str, Path]:
    root = safe_build_root(source)
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


def executable_name() -> str:
    return "main.exe" if os.name == "nt" else "main"


def repo_rel_or_abs(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def prepare_safe_build_root(source: Path) -> dict[str, Path]:
    paths = safe_build_paths(source)
    shutil.rmtree(paths["root"], ignore_errors=True)
    paths["root"].mkdir(parents=True, exist_ok=True)
    paths["out"].mkdir(parents=True, exist_ok=True)
    paths["iface"].mkdir(parents=True, exist_ok=True)
    paths["ada"].mkdir(parents=True, exist_ok=True)
    paths["obj"].mkdir(parents=True, exist_ok=True)
    return paths


def emitted_primary_unit(ada_dir: Path) -> str:
    body = emitted_body_file(ada_dir)
    if body.stem == "main":
        candidates = sorted(
            path
            for path in ada_dir.glob("*.adb")
            if path.stem != "main" and not path.name.endswith("_safe_io.adb")
        )
        require(candidates, f"safe build: missing primary emitted body in {ada_dir}")
        body = candidates[0]
    return body.stem


def safe_build_main_text(unit_name: str) -> str:
    return (
        f"with {unit_name};\n"
        "\n"
        "procedure Main is\n"
        "begin\n"
        "   null;\n"
        "end Main;\n"
    )


def safe_build_project_text(
    *,
    has_gnat_adc: bool,
    gnat_adc_path: str = "ada/gnat.adc",
    platform_name: str = sys.platform,
) -> str:
    del platform_name
    lines = [
        "project Build is",
        '   for Source_Dirs use (".", "ada");',
        '   for Object_Dir use "obj";',
        '   for Exec_Dir use ".";',
        '   for Main use ("main.adb");',
    ]
    if has_gnat_adc:
        lines.extend(
            [
                "   package Compiler is",
                f'      for Default_Switches ("Ada") use ("-gnatec={gnat_adc_path}");',
                "   end Compiler;",
            ]
        )
    lines.append("end Build;")
    return "\n".join(lines) + "\n"


def write_safe_build_support_files(paths: dict[str, Path]) -> None:
    ada_main = paths["ada"] / "main.adb"
    if not paths["main"].exists() and not ada_main.exists():
        unit_name = emitted_primary_unit(paths["ada"])
        paths["main"].write_text(safe_build_main_text(unit_name), encoding="utf-8")
    paths["gpr"].write_text(
        safe_build_project_text(
            has_gnat_adc=(paths["ada"] / "gnat.adc").exists(),
            gnat_adc_path=str(paths["ada"] / "gnat.adc"),
        ),
        encoding="utf-8",
    )


def safe_build_command(paths: dict[str, Path]) -> list[str]:
    return [
        alr_command(),
        "exec",
        "--",
        "gprbuild",
        "-q",
        "-ws",
        "-P",
        str(paths["gpr"]),
        "main.adb",
        "-cargs:Ada",
        "-gnatws",
    ]


def ensure_safe_build_executable(paths: dict[str, Path]) -> Path:
    exe = paths["exe"]
    require(exe.exists(), f"safe build: missing executable {exe}")
    return exe


def resolve_source_arg(source_arg: str, *, cwd: Path | None = None) -> Path:
    base = cwd or Path.cwd()
    path = Path(source_arg)
    if not path.is_absolute():
        path = base / path
    return path.resolve()


def require_source_file(source: Path) -> Path:
    require(source.exists(), f"safe build: source not found: {source}")
    require(source.is_file(), f"safe build: source is not a file: {source}")
    require(source.suffix == ".safe", f"safe build: expected a .safe source file: {source}")
    return source


def safec_path() -> Path:
    return require_safec()


__all__ = [
    "CANDIDATE_EXPANSIONS",
    "COMPILER_ROOT",
    "DEFERRED_CANDIDATES",
    "REPO_ROOT",
    "STARTER_CORPUS",
    "emitted_primary_unit",
    "ensure_safe_build_executable",
    "executable_name",
    "prepare_safe_build_root",
    "repo_rel_or_abs",
    "require_source_file",
    "safe_build_command",
    "safe_build_main_text",
    "safe_build_paths",
    "safe_build_project_text",
    "safe_build_root",
    "safe_launcher_path",
    "safec_path",
    "starter_corpus_paths",
    "write_safe_build_support_files",
]
