#!/usr/bin/env python3
"""Run the PR06.9.4 output contract stability gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
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
    require,
    require_repo_command,
    run,
    stable_emitted_artifact_sha256,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr0694-output-contract-stability-report.json"
)
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"
OUTPUT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"
CORPUS_SAMPLES = [
    *(REPO_ROOT / path for path in REPRESENTATIVE_EMIT_SAMPLES),
    REPO_ROOT / "tests" / "positive" / "ownership_inout.safe",
]
PUBLIC_INTERFACE_SOURCE = """package Public_Interface is
   public type Counter is range 0 to 10;
   public Seed : Counter = 1;

   public function Identity (Value : Counter) returns Counter is
   begin
      return Value;
   end Identity;
end Public_Interface;
"""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def emitted_paths(root: Path, sample_name: str) -> dict[str, Path]:
    stem = sample_name.lower()
    return {
        f"out/{stem}.ast.json": root / "out" / f"{stem}.ast.json",
        f"out/{stem}.typed.json": root / "out" / f"{stem}.typed.json",
        f"out/{stem}.mir.json": root / "out" / f"{stem}.mir.json",
        f"iface/{stem}.safei.json": root / "iface" / f"{stem}.safei.json",
    }


def assert_emitted_file_set(root: Path, sample_name: str) -> dict[str, Path]:
    expected_files = emitted_paths(root, sample_name)
    observed = {
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file()
    }
    expected = set(expected_files)
    require(
        observed == expected,
        f"{sample_name}: unexpected emitted files: expected {sorted(expected)}, got {sorted(observed)}",
    )
    return expected_files


def observed_emitted_files(root: Path) -> set[str]:
    return {
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file()
    }


def run_emit_case(
    *,
    name: str,
    source: Path,
    safec: Path,
    python: str,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, Any]:
    emit_a = temp_root / f"{name}-emit-a"
    emit_b = temp_root / f"{name}-emit-b"

    emit_runs = []
    for root in (emit_a, emit_b):
        emit_runs.append(
            run(
                [
                    str(safec),
                    "emit",
                    str(source),
                    "--out-dir",
                    str(root / "out"),
                    "--interface-dir",
                    str(root / "iface"),
                ],
                cwd=REPO_ROOT,
                env=env,
                temp_root=temp_root,
            )
        )

    left_paths = assert_emitted_file_set(emit_a, name)
    right_paths = assert_emitted_file_set(emit_b, name)
    require(
        observed_emitted_files(emit_a) == observed_emitted_files(emit_b),
        f"{name}: emit runs produced different file sets",
    )

    file_hashes: dict[str, str] = {}
    format_tags: dict[str, str] = {}
    path_values: dict[str, str] = {}
    for relative, left in sorted(left_paths.items()):
        right = right_paths[relative]
        left_bytes = left.read_bytes()
        right_bytes = right.read_bytes()
        require(left_bytes == right_bytes, f"{name}: non-deterministic output for {relative}")
        file_hashes[relative] = stable_emitted_artifact_sha256(left, temp_root=temp_root)

    ast_path = left_paths[f"out/{name}.ast.json"]
    typed_path = left_paths[f"out/{name}.typed.json"]
    mir_path = left_paths[f"out/{name}.mir.json"]
    safei_path = left_paths[f"iface/{name}.safei.json"]

    ast_validate = run(
        [python, str(AST_VALIDATOR), str(ast_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    contract_validate = run(
        [
            python,
            str(OUTPUT_VALIDATOR),
            "--ast",
            str(ast_path),
            "--typed",
            str(typed_path),
            "--mir",
            str(mir_path),
            "--safei",
            str(safei_path),
            "--source-path",
            str(source),
        ],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    mir_validate = run(
        [str(safec), "validate-mir", str(mir_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )

    ast_payload = load_json(ast_path)
    typed_payload = load_json(typed_path)
    mir_payload = load_json(mir_path)
    safei_payload = load_json(safei_path)

    require(typed_payload["ast"] == ast_payload, f"{name}: typed.ast must equal standalone AST")
    require(
        typed_payload["package_name"] == mir_payload["package_name"] == safei_payload["package_name"],
        f"{name}: package_name must agree across typed/mir/safei",
    )
    require(
        mir_payload["source_path"] == str(source),
        f"{name}: mir source_path must preserve exact source path",
    )

    format_tags["typed"] = typed_payload["format"]
    format_tags["mir"] = mir_payload["format"]
    format_tags["safei"] = safei_payload["format"]
    path_values["mir_source_path"] = normalize_text(mir_payload["source_path"], temp_root=temp_root)

    typed_exec_names = [item["name"] for item in typed_payload["executables"]]
    safei_exec_names = [item["name"] for item in safei_payload["executables"]]
    require(
        typed_exec_names == safei_exec_names,
        f"{name}: executable ordering must agree between typed and safei",
    )

    result = {
        "source": normalize_text(str(source), temp_root=temp_root),
        "emit_runs": emit_runs,
        "validators": {
            "ast": ast_validate,
            "output_contracts": contract_validate,
            "mir": mir_validate,
        },
        "file_hashes": file_hashes,
        "format_tags": format_tags,
        "mir_source_path": path_values["mir_source_path"],
        "typed_executable_names": typed_exec_names,
        "safei_executable_names": safei_exec_names,
        "typed_public_declaration_names": [item["name"] for item in typed_payload["public_declarations"]],
        "safei_public_declaration_names": [item["name"] for item in safei_payload["public_declarations"]],
    }

    if name == "public_interface":
        expected_public_names = ["Counter", "Seed", "Identity"]
        expected_public_kinds = ["TypeDeclaration", "ObjectDeclaration", "SubprogramBody"]
        typed_public = typed_payload["public_declarations"]
        safei_public = safei_payload["public_declarations"]
        require(typed_public, "public_interface: typed-v2 public_declarations must be non-empty")
        require(safei_public, "public_interface: safei-v1 public_declarations must be non-empty")
        require(
            [item["name"] for item in typed_public] == expected_public_names,
            "public_interface: typed-v2 public declaration ordering drifted",
        )
        require(
            [item["kind"] for item in typed_public] == expected_public_kinds,
            "public_interface: typed-v2 public declaration kinds drifted",
        )
        require(
            [item["name"] for item in safei_public] == expected_public_names,
            "public_interface: safei-v1 public declaration ordering drifted",
        )
        require(
            [item["kind"] for item in safei_public] == expected_public_kinds,
            "public_interface: safei-v1 public declaration kinds drifted",
        )
        require(
            typed_public == safei_public,
            "public_interface: public declarations must match between typed-v2 and safei-v1",
        )
        require(
            typed_exec_names == ["Identity"],
            "public_interface: executable ordering drifted",
        )
        result["public_contract"] = {
            "expected_names": expected_public_names,
            "expected_kinds": expected_public_kinds,
        }

    return result


def generate_report(*, safec: Path, python: str, env: dict[str, str]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pr0694-contracts-") as temp_root_str:
        temp_root = Path(temp_root_str)
        inline_root = temp_root / "inline-sources"
        inline_root.mkdir(parents=True, exist_ok=True)
        corpus_results: dict[str, Any] = {}
        for sample in CORPUS_SAMPLES:
            corpus_results[sample.stem.lower()] = run_emit_case(
                name=sample.stem.lower(),
                source=sample,
                safec=safec,
                python=python,
                env=env,
                temp_root=temp_root,
            )

        inline_source = inline_root / "public_interface.safe"
        inline_source.write_text(PUBLIC_INTERFACE_SOURCE, encoding="utf-8")
        inline_result = run_emit_case(
            name="public_interface",
            source=inline_source,
            safec=safec,
            python=python,
            env=env,
            temp_root=temp_root,
        )

        return {
            "task": "PR06.9.4",
            "status": "ok",
            "inputs": {
                "corpus_samples": [str(path.relative_to(REPO_ROOT)) for path in CORPUS_SAMPLES],
                "inline_samples": ["public_interface"],
            },
            "cases": {
                "corpus": corpus_results,
                "inline": {"public_interface": inline_result},
            },
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    python = find_command("python3")
    find_command("alr", Path.home() / "bin" / "alr")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    env = ensure_sdkroot(os.environ.copy())

    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, python=python, env=env),
        label="PR06.9.4 output contract stability",
    )
    write_report(args.report, report)
    print(f"pr0694 output contract stability: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
