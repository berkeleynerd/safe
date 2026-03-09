#!/usr/bin/env python3
"""Run the PR06.8 Ada-native ast/emit no-Python gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr068-ada-ast-emit-no-python-report.json"
AST_SAMPLE = REPO_ROOT / "tests" / "positive" / "rule1_accumulate.safe"
EMIT_SAMPLES = [
    REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
    REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
]
NEGATIVE_EMIT_SAMPLE = REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe"
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
PACKAGE_GLOBAL_SOURCE = """package Package_Global_Owner is
   type Value is range 0 .. 10;
   type Value_Ptr is access all Value;
   Owner : Value_Ptr = new (1 as Value);

   function Read return Value is
   begin
      return Owner.all;
   end Read;
end Package_Global_Owner;
"""
BANNED_DRIVER_TOKENS = [
    "Run_Backend",
    "Backend_Script",
    "GNAT.OS_Lib",
    "pr05_backend.py",
    "Python3 :",
]


def normalize_text(text: str, *, temp_root: Path | None = None) -> str:
    result = text
    if temp_root is not None:
        result = result.replace(str(temp_root), "$TMPDIR")
    return result.replace(str(REPO_ROOT), "$REPO_ROOT")


def normalize_argv(argv: list[str], *, temp_root: Path | None = None) -> list[str]:
    normalized: list[str] = []
    for item in argv:
        candidate = Path(item)
        if candidate.is_absolute():
            if temp_root is not None and temp_root in candidate.parents:
                normalized.append("$TMPDIR/" + str(candidate.relative_to(temp_root)))
            elif REPO_ROOT in candidate.parents:
                normalized.append(str(candidate.relative_to(REPO_ROOT)))
            else:
                normalized.append(candidate.name)
        else:
            normalized.append(item)
    return normalized


def find_command(name: str, fallback: Path | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def run(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    stdout_path: Path | None = None,
    temp_root: Path | None = None,
    expected_returncode: int = 0,
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
        "command": normalize_argv(argv, temp_root=temp_root),
        "cwd": normalize_text(str(cwd), temp_root=temp_root),
        "returncode": completed.returncode,
        "stdout": normalize_text(stdout_text, temp_root=temp_root),
        "stderr": normalize_text(completed.stderr, temp_root=temp_root),
    }
    if completed.returncode != expected_returncode:
        raise RuntimeError(json.dumps(result, indent=2))
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def ensure_sdkroot(env: dict[str, str]) -> dict[str, str]:
    if sys.platform != "darwin" or env.get("SDKROOT"):
        return env
    candidate = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
    if candidate.exists():
        updated = env.copy()
        updated["SDKROOT"] = str(candidate)
        return updated
    return env


def tool_versions(python: str, alr: str) -> dict[str, str]:
    versions: dict[str, str] = {}
    versions["python3"] = (
        subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stdout.strip()
        or subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stderr.strip()
    )
    versions["alr"] = subprocess.run([alr, "--version"], text=True, capture_output=True, check=False).stdout.strip()
    gprbuild = shutil.which("gprbuild")
    if gprbuild:
        versions["gprbuild"] = subprocess.run(
            [gprbuild, "--version"], text=True, capture_output=True, check=False
        ).stdout.splitlines()[0]
    return versions


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        f"out/{stem}.ast.json": root / "out" / f"{stem}.ast.json",
        f"out/{stem}.typed.json": root / "out" / f"{stem}.typed.json",
        f"out/{stem}.mir.json": root / "out" / f"{stem}.mir.json",
        f"iface/{stem}.safei.json": root / "iface" / f"{stem}.safei.json",
    }


def make_masked_env(temp_root: Path) -> tuple[dict[str, str], Path, Path]:
    stub_dir = temp_root / "python-mask"
    stub_dir.mkdir(parents=True, exist_ok=True)
    blocked_log = temp_root / "blocked-python.log"
    stub_path = stub_dir / "python3"
    stub_path.write_text(
        "\n".join(
            [
                "#!/bin/sh",
                'echo "blocked python3 spawn: $*" >> "$PR068_BLOCKED_LOG"',
                'echo "python3 masked for PR06.8 ast/emit gate" >&2',
                "exit 97",
                "",
            ]
        ),
        encoding="utf-8",
    )
    stub_path.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = str(stub_dir) + os.pathsep + env.get("PATH", "")
    env["PR068_BLOCKED_LOG"] = str(blocked_log)
    return env, stub_path, blocked_log


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_driver_cutover() -> dict[str, Any]:
    driver_path = COMPILER_ROOT / "src" / "safe_frontend-driver.adb"
    driver_text = driver_path.read_text(encoding="utf-8")
    missing = [token for token in BANNED_DRIVER_TOKENS if token in driver_text]
    require(not missing, f"driver still contains banned runtime tokens: {missing}")
    backend_path = COMPILER_ROOT / "backend" / "pr05_backend.py"
    require(not backend_path.exists(), f"legacy runtime backend still present: {backend_path}")
    return {
        "driver": str(driver_path.relative_to(REPO_ROOT)),
        "banned_tokens_absent": BANNED_DRIVER_TOKENS,
        "legacy_backend_removed": True,
    }


def read_diag_json(stdout: str, source: str) -> dict[str, Any]:
    payload = json.loads(stdout)
    require(payload.get("format") == "diagnostics-v0", f"{source}: unexpected diagnostics format")
    require(isinstance(payload.get("diagnostics"), list), f"{source}: diagnostics must be a list")
    return payload


def assert_no_files(root: Path) -> dict[str, Any]:
    if not root.exists():
        return {"exists": False, "files": []}
    files = sorted(str(path.relative_to(root)) for path in root.rglob("*") if path.is_file())
    require(not files, f"expected no emitted files under {root}, saw {files}")
    return {"exists": True, "files": files}


def assert_package_global_emit(
    safec: Path,
    *,
    env: dict[str, str],
    validation_env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    source = temp_root / "package_global_owner.safe"
    source.write_text(PACKAGE_GLOBAL_SOURCE, encoding="utf-8")
    emit_root = temp_root / "package-global-emit"
    emit_run = run(
        [
            str(safec),
            "emit",
            str(source),
            "--out-dir",
            str(emit_root / "out"),
            "--interface-dir",
            str(emit_root / "iface"),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )

    stem = source.stem.lower()
    ast_output = emit_root / "out" / f"{stem}.ast.json"
    mir_output = emit_root / "out" / f"{stem}.mir.json"
    typed_output = emit_root / "out" / f"{stem}.typed.json"
    safei_output = emit_root / "iface" / f"{stem}.safei.json"

    ast_validate = run(
        [find_command("python3"), str(AST_VALIDATOR), str(ast_output)],
        cwd=REPO_ROOT,
        env=validation_env,
        temp_root=temp_root,
    )
    mir_validate = run(
        [str(safec), "validate-mir", str(mir_output)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    mir_analyze = run(
        [str(safec), "analyze-mir", "--diag-json", str(mir_output)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    diagnostics = read_diag_json(mir_analyze["stdout"], str(mir_output))
    require(diagnostics["diagnostics"] == [], f"{mir_output}: expected zero diagnostics")

    typed_payload = load_json(typed_output)
    mir_payload = load_json(mir_output)
    safei_payload = load_json(safei_output)
    require(typed_payload.get("format") == "typed-v2", f"{typed_output}: expected typed-v2")
    require(mir_payload.get("format") == "mir-v2", f"{mir_output}: expected mir-v2")
    require(safei_payload.get("format") == "safei-v0", f"{safei_output}: expected safei-v0")

    graph = mir_payload["graphs"][0]
    owner_locals = [item for item in graph["locals"] if item["name"] == "Owner"]
    require(owner_locals, f"{mir_output}: expected global local for package object Owner")
    owner_local = owner_locals[0]
    require(owner_local["kind"] == "global", f"{mir_output}: expected Owner local kind=global")
    require(owner_local["type"]["name"] == "Value_Ptr", f"{mir_output}: expected Owner type Value_Ptr")

    return_blocks = [block for block in graph["blocks"] if block["terminator"]["kind"] == "return"]
    require(return_blocks, f"{mir_output}: expected at least one return block")
    return_value = return_blocks[0]["terminator"]["value"]
    require(return_value["tag"] == "select", f"{mir_output}: expected return value select expression")
    require(
        return_value["prefix"]["type"] == "Value_Ptr",
        f"{mir_output}: expected select prefix type Value_Ptr, saw {return_value['prefix'].get('type')!r}",
    )

    return {
        "source": "$TMPDIR/package_global_owner.safe",
        "emit": emit_run,
        "ast_validation": ast_validate,
        "mir_validation": mir_validate,
        "mir_analysis": {
            **mir_analyze,
            "diagnostics": diagnostics,
        },
        "owner_local": owner_local,
        "return_value": return_value,
        "typed_format": typed_payload["format"],
        "safei_format": safei_payload["format"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    args.report.parent.mkdir(parents=True, exist_ok=True)

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    env = ensure_sdkroot(os.environ.copy())

    safec = COMPILER_ROOT / "bin" / "safec"
    if not safec.exists():
        raise RuntimeError(f"expected compiled binary at {safec}")

    with tempfile.TemporaryDirectory(prefix="safec-pr068-") as temp_root_str:
        temp_root = Path(temp_root_str)
        masked_env, stub_path, blocked_log = make_masked_env(temp_root)
        masked_env = ensure_sdkroot(masked_env)

        ast_path = temp_root / "rule1_accumulate.ast.json"
        ast_run = run(
            [str(safec), "ast", str(AST_SAMPLE)],
            cwd=REPO_ROOT,
            env=masked_env,
            stdout_path=ast_path,
            temp_root=temp_root,
        )
        ast_validate = run(
            [python, str(AST_VALIDATOR), str(ast_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )

        deterministic_outputs: dict[str, dict[str, str]] = {}
        emit_samples: list[dict[str, Any]] = []
        for sample in EMIT_SAMPLES:
            emit_a_root = temp_root / f"{sample.stem}-emit-a"
            emit_b_root = temp_root / f"{sample.stem}-emit-b"
            first_emit = run(
                [
                    str(safec),
                    "emit",
                    str(sample),
                    "--out-dir",
                    str(emit_a_root / "out"),
                    "--interface-dir",
                    str(emit_a_root / "iface"),
                ],
                cwd=REPO_ROOT,
                env=masked_env,
                temp_root=temp_root,
            )
            second_emit = run(
                [
                    str(safec),
                    "emit",
                    str(sample),
                    "--out-dir",
                    str(emit_b_root / "out"),
                    "--interface-dir",
                    str(emit_b_root / "iface"),
                ],
                cwd=REPO_ROOT,
                env=masked_env,
                temp_root=temp_root,
            )

            expected_files = emitted_paths(emit_a_root, sample)
            observed_files = {
                str(path.relative_to(emit_a_root))
                for path in emit_a_root.rglob("*")
                if path.is_file()
            }
            require(
                observed_files == set(expected_files),
                f"unexpected emitted files for {sample.name}: expected {sorted(expected_files)}, got {sorted(observed_files)}",
            )

            ast_output = expected_files[f"out/{sample.stem.lower()}.ast.json"]
            typed_output = expected_files[f"out/{sample.stem.lower()}.typed.json"]
            mir_output = expected_files[f"out/{sample.stem.lower()}.mir.json"]
            interface_output = expected_files[f"iface/{sample.stem.lower()}.safei.json"]

            emitted_ast_validate = run(
                [python, str(AST_VALIDATOR), str(ast_output)],
                cwd=REPO_ROOT,
                env=env,
                temp_root=temp_root,
            )
            mir_validate = run(
                [str(safec), "validate-mir", str(mir_output)],
                cwd=REPO_ROOT,
                env=masked_env,
                temp_root=temp_root,
            )
            mir_analyze = run(
                [str(safec), "analyze-mir", "--diag-json", str(mir_output)],
                cwd=REPO_ROOT,
                env=masked_env,
                temp_root=temp_root,
            )
            mir_diagnostics = read_diag_json(mir_analyze["stdout"], str(mir_output))
            require(
                mir_diagnostics["diagnostics"] == [],
                f"{mir_output}: expected analyze-mir to return zero diagnostics",
            )

            typed_payload = load_json(typed_output)
            require(typed_payload.get("format") == "typed-v2", f"{typed_output}: expected typed-v2")
            safei_payload = load_json(interface_output)
            require(safei_payload.get("format") == "safei-v0", f"{interface_output}: expected safei-v0")

            file_hashes: dict[str, str] = {}
            for relative, left in sorted(expected_files.items()):
                right = emit_b_root / relative
                left_bytes = left.read_bytes()
                right_bytes = right.read_bytes()
                if left_bytes != right_bytes:
                    raise RuntimeError(f"non-deterministic output for {sample.name}::{relative}")
                file_hashes[relative] = sha256(left)
            deterministic_outputs[str(sample.relative_to(REPO_ROOT))] = file_hashes

            emit_samples.append(
                {
                    "source": str(sample.relative_to(REPO_ROOT)),
                    "first_emit": first_emit,
                    "second_emit": second_emit,
                    "ast_validation": emitted_ast_validate,
                    "mir_validation": mir_validate,
                    "mir_analysis": {
                        **mir_analyze,
                        "diagnostics": mir_diagnostics,
                    },
                    "typed_format": typed_payload["format"],
                    "safei_format": safei_payload["format"],
                    "hashes": file_hashes,
                }
            )

        negative_root = temp_root / "negative-emit"
        negative_emit = run(
            [
                str(safec),
                "emit",
                str(NEGATIVE_EMIT_SAMPLE),
                "--out-dir",
                str(negative_root / "out"),
                "--interface-dir",
                str(negative_root / "iface"),
            ],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        negative_files = {
            "out": assert_no_files(negative_root / "out"),
            "iface": assert_no_files(negative_root / "iface"),
        }

        blocked_entries = (
            blocked_log.read_text(encoding="utf-8").splitlines() if blocked_log.exists() else []
        )
        require(not blocked_entries, f"unexpected Python spawns during ast/emit gate: {blocked_entries}")

        report = {
            "tool_versions": tool_versions(python, alr),
            "runtime_rule": assert_driver_cutover(),
            "samples": {
                "ast": str(AST_SAMPLE.relative_to(REPO_ROOT)),
                "emit": [str(sample.relative_to(REPO_ROOT)) for sample in EMIT_SAMPLES],
                "negative_emit": str(NEGATIVE_EMIT_SAMPLE.relative_to(REPO_ROOT)),
                "package_global_emit": "$TMPDIR/package_global_owner.safe",
            },
            "ast_no_python": {
                "run": ast_run,
                "validation": ast_validate,
            },
            "emit_no_python": {
                "samples": emit_samples,
                "package_global_emit": assert_package_global_emit(
                    safec,
                    env=masked_env,
                    validation_env=env,
                    temp_root=temp_root,
                ),
                "negative_emit": {
                    "run": negative_emit,
                    "outputs": negative_files,
                },
            },
            "deterministic_outputs": deterministic_outputs,
            "python_mask": {
                "stub_path": normalize_text(str(stub_path), temp_root=temp_root),
                "blocked_log": normalize_text(str(blocked_log), temp_root=temp_root),
                "blocked_spawns": blocked_entries,
            },
        }

    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"pr068 ast/emit gate: OK ({args.report})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr068 ast/emit gate: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
