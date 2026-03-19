#!/usr/bin/env python3
"""Run the PR06.8 Ada-native ast/emit no-Python gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.gate_expectations import REPRESENTATIVE_EMIT_SAMPLES
from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    normalize_text,
    read_diag_json,
    require,
    require_repo_command,
    run,
    write_report,
)
from _lib.platform_assumptions import (
    MASKED_PYTHON_INTERPRETERS,
    STATIC_PYTHON_INVOCATION_PATTERNS,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr068-ada-ast-emit-no-python-report.json"
AST_SAMPLE = REPO_ROOT / "tests" / "positive" / "rule1_accumulate.safe"
EMIT_SAMPLES = [REPO_ROOT / path for path in REPRESENTATIVE_EMIT_SAMPLES]
NEGATIVE_EMIT_SAMPLE = REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe"
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
PACKAGE_GLOBAL_SOURCE = """package Package_Global_Owner is
   type Value is range 0 to 10;
   type Value_Ptr is access all Value;
   Owner : Value_Ptr = new (1 as Value);

   function Read returns Value is
   begin
      return Owner.all;
   end Read;
end Package_Global_Owner;
"""
PACKAGE_GLOBAL_ARRAY_SOURCE = """package Package_Global_Array is
   type Index is range 1 to 4;
   type Element is range 0 to 20;
   type Table is array (Index) of Element;
   Data : Table;

   function Read returns Element is
   begin
      Data (Index.First) = 5;
      return Data (Index.First);
   end Read;
end Package_Global_Array;
"""
PACKAGE_GLOBAL_RECORD_SOURCE = """package Package_Global_Record is
   type Config is record
      Rate : Natural;
      Limit : Natural;
   end record;

   Current : Config = (Rate = 1, Limit = 2);

   function Read returns Natural is
   begin
      return Current.Rate;
   end Read;
end Package_Global_Record;
"""
PACKAGE_GLOBAL_OBSERVE_SOURCE = """package Package_Global_Observe is
   type Config is record
      Rate : Natural;
   end record;

   type Config_Ptr is access Config;

   Owner : Config_Ptr = new ((Rate = 100) as Config);

   function Read_Config (Ref : access constant Config) returns Integer is
   begin
      return Ref.all.Rate;
   end Read_Config;

   function Read returns Integer is
   begin
      return Read_Config (Owner.Access);
   end Read;
end Package_Global_Observe;
"""
BANNED_DRIVER_TOKENS = [
    "Run_Backend",
    "Backend_Script",
    "GNAT.OS_Lib",
    "pr05_backend.py",
    "Python3 :",
]
RUNTIME_SOURCE_PATTERNS = [
    (
        "compiler_impl/src/safe_frontend-*.adb",
        [r"\bRun_Backend\b", r"\bBackend_Script\b", r"pr05_backend\.py", r"\bGNAT\.OS_Lib\b", *STATIC_PYTHON_INVOCATION_PATTERNS],
    ),
    (
        "compiler_impl/src/safe_frontend-*.ads",
        [r"\bRun_Backend\b", r"\bBackend_Script\b", r"pr05_backend\.py", r"\bGNAT\.OS_Lib\b", *STATIC_PYTHON_INVOCATION_PATTERNS],
    ),
    (
        "compiler_impl/src/safec.adb",
        [r"\bRun_Backend\b", r"\bBackend_Script\b", r"pr05_backend\.py", *STATIC_PYTHON_INVOCATION_PATTERNS],
    ),
]


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


def repo_cli_path(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def make_masked_env(temp_root: Path) -> tuple[dict[str, str], dict[str, Path], Path]:
    stub_dir = temp_root / "python-mask"
    stub_dir.mkdir(parents=True, exist_ok=True)
    blocked_log = temp_root / "blocked-python.log"
    stub_paths: dict[str, Path] = {}
    for interpreter in MASKED_PYTHON_INTERPRETERS:
        stub_path = stub_dir / interpreter
        stub_path.write_text(
            "\n".join(
                [
                    "#!/bin/sh",
                    f'echo "blocked {interpreter} spawn: $*" >> "$PR068_BLOCKED_LOG"',
                    f'echo "{interpreter} masked for PR06.8 ast/emit gate" >&2',
                    "exit 97",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        stub_path.chmod(0o755)
        stub_paths[interpreter] = stub_path

    env = os.environ.copy()
    env["PATH"] = str(stub_dir) + os.pathsep + env.get("PATH", "")
    env["PR068_BLOCKED_LOG"] = str(blocked_log)
    return env, stub_paths, blocked_log


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_runtime_boundary() -> dict[str, Any]:
    driver_path = COMPILER_ROOT / "src" / "safe_frontend-driver.adb"
    driver_text = driver_path.read_text(encoding="utf-8")
    missing = [token for token in BANNED_DRIVER_TOKENS if token in driver_text]
    require(not missing, f"driver still contains banned runtime tokens: {missing}")
    backend_path = COMPILER_ROOT / "backend" / "pr05_backend.py"
    require(not backend_path.exists(), f"legacy runtime backend still present: {backend_path}")
    scanned_files: list[str] = []
    violations: list[str] = []
    for pattern, denylist in RUNTIME_SOURCE_PATTERNS:
        for path in sorted(REPO_ROOT.glob(pattern)):
            scanned_files.append(str(path.relative_to(REPO_ROOT)))
            text = path.read_text(encoding="utf-8")
            for token in denylist:
                if re.search(token, text, flags=re.IGNORECASE):
                    violations.append(f"{path.relative_to(REPO_ROOT)}:{token}")
    require(not violations, f"runtime boundary violations: {violations}")
    return {
        "driver": str(driver_path.relative_to(REPO_ROOT)),
        "banned_tokens_absent": BANNED_DRIVER_TOKENS,
        "legacy_backend_removed": True,
        "scanned_files": scanned_files,
        "violations": violations,
    }


def assert_no_files(root: Path) -> dict[str, Any]:
    if not root.exists():
        return {"exists": False, "files": []}
    files = sorted(str(path.relative_to(root)) for path in root.rglob("*") if path.is_file())
    require(not files, f"expected no emitted files under {root}, saw {files}")
    return {"exists": True, "files": files}


def block_map(graph: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {block["id"]: block for block in graph["blocks"]}


def reachable_block_ids(graph: dict[str, Any]) -> list[str]:
    blocks = block_map(graph)
    pending = [graph["entry_bb"]]
    seen: set[str] = set()
    while pending:
        current = pending.pop(0)
        if current in seen or current not in blocks:
            continue
        seen.add(current)
        terminator = blocks[current]["terminator"]
        kind = terminator["kind"]
        if kind == "jump":
            pending.append(terminator["target"])
        elif kind == "branch":
            pending.append(terminator["true_target"])
            pending.append(terminator["false_target"])
    return sorted(seen)


def assert_cfg_invariants(mir_payload: dict[str, Any], *, source: str) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for graph in mir_payload["graphs"]:
        reachable = set(reachable_block_ids(graph))
        patched_dead_blocks: list[str] = []
        for block in graph["blocks"]:
            block_id = block["id"]
            terminator = block["terminator"]
            kind = terminator["kind"]
            if kind == "<unknown>":
                if block_id in reachable:
                    raise RuntimeError(
                        f"{source}: graph {graph['name']} has reachable unterminated block {block_id}"
                    )
                raise RuntimeError(
                    f"{source}: graph {graph['name']} still contains unknown terminator at {block_id}"
                )
            if kind == "jump" and terminator["target"] == block_id:
                patched_dead_blocks.append(block_id)
                require(
                    block_id not in reachable,
                    f"{source}: graph {graph['name']} has reachable self-jump patch block {block_id}",
                )
        results.append(
            {
                "graph": graph["name"],
                "reachable_blocks": sorted(reachable),
                "patched_dead_blocks": patched_dead_blocks,
            }
        )
    return results


def graph_by_name(mir_payload: dict[str, Any], name: str) -> dict[str, Any]:
    for graph in mir_payload["graphs"]:
        if graph["name"] == name:
            return graph
    raise RuntimeError(f"missing graph {name!r}")


def local_by_name(graph: dict[str, Any], name: str) -> dict[str, Any]:
    for item in graph["locals"]:
        if item["name"] == name:
            return item
    raise RuntimeError(f"missing local {name!r} in graph {graph['name']!r}")


def first_return_value(graph: dict[str, Any]) -> dict[str, Any]:
    for block in graph["blocks"]:
        if block["terminator"]["kind"] == "return" and block["terminator"]["value"] is not None:
            return block["terminator"]["value"]
    raise RuntimeError(f"missing return value in graph {graph['name']!r}")


def emit_inline_source_case(
    *,
    name: str,
    text: str,
    safec: Path,
    env: dict[str, str],
    validation_env: dict[str, str],
    python: str,
    temp_root: Path,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    source = temp_root / f"{name}.safe"
    source.write_text(text, encoding="utf-8")
    emit_root = temp_root / f"{name}-emit"
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
    ast_output = emit_root / "out" / f"{name}.ast.json"
    typed_output = emit_root / "out" / f"{name}.typed.json"
    mir_output = emit_root / "out" / f"{name}.mir.json"
    safei_output = emit_root / "iface" / f"{name}.safei.json"

    ast_validate = run(
        [python, str(AST_VALIDATOR), str(ast_output)],
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
    typed_payload = load_json(typed_output)
    mir_payload = load_json(mir_output)
    safei_payload = load_json(safei_output)
    require(typed_payload.get("format") == "typed-v2", f"{typed_output}: expected typed-v2")
    require(mir_payload.get("format") == "mir-v2", f"{mir_output}: expected mir-v2")
    require(safei_payload.get("format") == "safei-v1", f"{safei_output}: expected safei-v1")
    require(diagnostics["diagnostics"] == [], f"{mir_output}: expected zero diagnostics")
    require(mir_payload["source_path"] == str(source), f"{mir_output}: source_path must preserve CLI path")

    return emit_run, ast_validate, mir_validate, mir_analyze, typed_payload, mir_payload, safei_payload


def assert_package_global_cases(
    safec: Path,
    *,
    env: dict[str, str],
    validation_env: dict[str, str],
    python: str,
    temp_root: Path,
) -> dict[str, Any]:
    results: dict[str, Any] = {}
    cases = [
        ("package_global_owner", PACKAGE_GLOBAL_SOURCE),
        ("package_global_array", PACKAGE_GLOBAL_ARRAY_SOURCE),
        ("package_global_record", PACKAGE_GLOBAL_RECORD_SOURCE),
        ("package_global_observe", PACKAGE_GLOBAL_OBSERVE_SOURCE),
    ]

    for name, text in cases:
        (
            emit_run,
            ast_validate,
            mir_validate,
            mir_analyze,
            typed_payload,
            mir_payload,
            safei_payload,
        ) = emit_inline_source_case(
            name=name,
            text=text,
            safec=safec,
            env=env,
            validation_env=validation_env,
            python=python,
            temp_root=temp_root,
        )
        case_result: dict[str, Any] = {
            "source": f"$TMPDIR/{name}.safe",
            "emit": emit_run,
            "ast_validation": ast_validate,
            "mir_validation": mir_validate,
            "mir_analysis": {
                **mir_analyze,
                "diagnostics": read_diag_json(mir_analyze["stdout"], f"{name}.mir.json"),
            },
            "typed_format": typed_payload["format"],
            "safei_format": safei_payload["format"],
            "cfg_invariants": assert_cfg_invariants(mir_payload, source=name),
        }

        if name == "package_global_owner":
            graph = graph_by_name(mir_payload, "Read")
            owner_local = local_by_name(graph, "Owner")
            return_value = first_return_value(graph)
            require(owner_local["kind"] == "global", "package_global_owner: Owner must lower as a global local")
            require(
                owner_local["type"]["name"] == "Value_Ptr",
                f"package_global_owner: expected Owner type Value_Ptr, saw {owner_local['type']['name']!r}",
            )
            require(return_value["tag"] == "select", "package_global_owner: expected select return expression")
            require(
                return_value["prefix"]["type"] == "Value_Ptr",
                f"package_global_owner: expected select prefix type Value_Ptr, saw {return_value['prefix'].get('type')!r}",
            )
            case_result["owner_local"] = owner_local
            case_result["return_value"] = return_value

        if name == "package_global_array":
            graph = graph_by_name(mir_payload, "Read")
            data_local = local_by_name(graph, "Data")
            return_value = first_return_value(graph)
            require(data_local["kind"] == "global", "package_global_array: Data must lower as a global local")
            require(
                data_local["type"]["name"] == "Table",
                f"package_global_array: expected Data type Table, saw {data_local['type']['name']!r}",
            )
            require(
                return_value["tag"] == "resolved_index",
                f"package_global_array: expected resolved_index return, saw {return_value['tag']!r}",
            )
            require(
                return_value["prefix"]["type"] == "Table",
                f"package_global_array: expected indexed prefix type Table, saw {return_value['prefix'].get('type')!r}",
            )
            case_result["data_local"] = data_local
            case_result["return_value"] = return_value

        if name == "package_global_record":
            graph = graph_by_name(mir_payload, "Read")
            current_local = local_by_name(graph, "Current")
            return_value = first_return_value(graph)
            init_ops = [op for op in graph["blocks"][0]["ops"] if op["kind"] == "assign" and op["target"]["name"] == "Current"]
            require(current_local["kind"] == "global", "package_global_record: Current must lower as a global local")
            require(
                current_local["type"]["name"] == "Config",
                f"package_global_record: expected Current type Config, saw {current_local['type']['name']!r}",
            )
            require(init_ops and init_ops[0]["declaration_init"], "package_global_record: Current init must stay declaration_init")
            require(return_value["tag"] == "select", "package_global_record: expected select return expression")
            require(
                return_value["prefix"]["type"] == "Config",
                f"package_global_record: expected select prefix type Config, saw {return_value['prefix'].get('type')!r}",
            )
            case_result["current_local"] = current_local
            case_result["return_value"] = return_value

        if name == "package_global_observe":
            read_graph = graph_by_name(mir_payload, "Read")
            callee_graph = graph_by_name(mir_payload, "Read_Config")
            owner_local = local_by_name(read_graph, "Owner")
            ref_local = local_by_name(callee_graph, "Ref")
            return_value = first_return_value(read_graph)
            require(owner_local["kind"] == "global", "package_global_observe: Owner must lower as a global local")
            require(
                owner_local["type"]["name"] == "Config_Ptr",
                f"package_global_observe: expected Owner type Config_Ptr, saw {owner_local['type']['name']!r}",
            )
            require(
                ref_local["ownership_role"] == "Observe",
                f"package_global_observe: expected Ref ownership_role Observe, saw {ref_local['ownership_role']!r}",
            )
            require(return_value["tag"] == "call", "package_global_observe: expected return call expression")
            require(
                return_value["args"][0]["tag"] == "select" and return_value["args"][0]["selector"] == "Access",
                "package_global_observe: expected call argument Owner.Access",
            )
            require(
                return_value["args"][0]["prefix"]["type"] == "Config_Ptr",
                f"package_global_observe: expected Owner.Access prefix type Config_Ptr, saw {return_value['args'][0]['prefix'].get('type')!r}",
            )
            case_result["owner_local"] = owner_local
            case_result["ref_local"] = ref_local
            case_result["return_value"] = return_value

        results[name] = case_result

    return results


def generate_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="safec-pr068-") as temp_root_str:
        temp_root = Path(temp_root_str)
        masked_env, stub_paths, blocked_log = make_masked_env(temp_root)
        masked_env = ensure_sdkroot(masked_env)

        ast_path = temp_root / "rule1_accumulate.ast.json"
        ast_run = run(
            [str(safec), "ast", repo_cli_path(AST_SAMPLE)],
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
                    repo_cli_path(sample),
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
                    repo_cli_path(sample),
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
            mir_payload = load_json(mir_output)
            require(mir_payload.get("format") == "mir-v2", f"{mir_output}: expected mir-v2")
            safei_payload = load_json(interface_output)
            require(safei_payload.get("format") == "safei-v1", f"{interface_output}: expected safei-v1")

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
                    "cfg_invariants": assert_cfg_invariants(
                        mir_payload, source=str(sample.relative_to(REPO_ROOT))
                    ),
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
                repo_cli_path(NEGATIVE_EMIT_SAMPLE),
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

        return {
            "runtime_rule": assert_runtime_boundary(),
            "samples": {
                "ast": str(AST_SAMPLE.relative_to(REPO_ROOT)),
                "emit": [str(sample.relative_to(REPO_ROOT)) for sample in EMIT_SAMPLES],
                "negative_emit": str(NEGATIVE_EMIT_SAMPLE.relative_to(REPO_ROOT)),
                "package_global_emit": [
                    "$TMPDIR/package_global_owner.safe",
                    "$TMPDIR/package_global_array.safe",
                    "$TMPDIR/package_global_record.safe",
                    "$TMPDIR/package_global_observe.safe",
                ],
            },
            "ast_no_python": {
                "run": ast_run,
                "validation": ast_validate,
            },
            "emit_no_python": {
                "samples": emit_samples,
                "package_global_emit": assert_package_global_cases(
                    safec,
                    env=masked_env,
                    validation_env=env,
                    python=python,
                    temp_root=temp_root,
                ),
                "negative_emit": {
                    "run": negative_emit,
                    "outputs": negative_files,
                },
            },
            "deterministic_outputs": deterministic_outputs,
            "python_mask": {
                "stub_paths": {
                    name: normalize_text(str(path), temp_root=temp_root)
                    for name, path in sorted(stub_paths.items())
                },
                "blocked_log": normalize_text(str(blocked_log), temp_root=temp_root),
                "blocked_spawns": blocked_entries,
            },
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    find_command("alr", Path.home() / "bin" / "alr")
    env = ensure_sdkroot(os.environ.copy())

    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    if not safec.exists():
        raise RuntimeError(f"expected compiled binary at {safec}")

    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, python=python, env=env),
        label="PR06.8 ast/emit no-Python",
    )
    write_report(args.report, report)
    print(f"pr068 ast/emit gate: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr068 ast/emit gate: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
