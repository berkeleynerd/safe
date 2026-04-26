"""AST, output-contract, and MIR-shape checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

from _lib.test_harness import (
    DIAGNOSTIC_EXIT_CODE,
    REPO_ROOT,
    VALIDATE_AST_OUTPUT,
    VALIDATE_OUTPUT_CONTRACTS,
    RunCounts,
    first_message,
    record_result,
    repo_rel,
    run_command,
)

AST_CONTRACT_CASES = [
    REPO_ROOT / "tests" / "positive" / "pr118k_try_propagation.safe",
    REPO_ROOT / "tests" / "positive" / "pr118k_match.safe",
    REPO_ROOT / "tests" / "positive" / "pr1110a_optional_guarded.safe",
    REPO_ROOT / "tests" / "positive" / "pr1110b_list_basics.safe",
    REPO_ROOT / "tests" / "positive" / "pr1110c_map_basics.safe",
    REPO_ROOT / "tests" / "positive" / "pr1111a_method_syntax.safe",
    REPO_ROOT / "tests" / "positive" / "pr1111b_interface_local.safe",
    REPO_ROOT / "tests" / "positive" / "pr1111c_generic_basics.safe",
    REPO_ROOT / "tests" / "positive" / "pr1112a_shared_field_access.safe",
    REPO_ROOT / "tests" / "positive" / "pr1112b_shared_snapshot.safe",
    REPO_ROOT / "tests" / "positive" / "pr1113a_sum_construction.safe",
    REPO_ROOT / "tests" / "positive" / "pr1113b_sum_match.safe",
]

OUTPUT_CONTRACT_CASES = [
    REPO_ROOT / "tests" / "positive" / "pr118c2_package_print.safe",
    REPO_ROOT / "tests" / "positive" / "pr118c2_entry_print.safe",
    REPO_ROOT / "tests" / "build" / "pr118d_for_of_growable_build.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_mutual_family.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_generic.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr118k_try_while_contract.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_list.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_shared_ceiling.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_shared_helper_prefix.safe",
    REPO_ROOT / "tests" / "interfaces" / "provider_transitive_shared.safe",
    REPO_ROOT / "tests" / "positive" / "pr376_match_arm_type_walk.safe",
]

OUTPUT_CONTRACT_REJECT_CASES = [
    (
        "safei-bad-return-flag",
        REPO_ROOT / "tests" / "interfaces" / "provider_binary.safe",
        "subprograms[0].return_is_access_def must be a boolean",
    ),
    (
        "safei-template-source-key-on-non-generic",
        REPO_ROOT / "tests" / "interfaces" / "provider_binary.safe",
        "subprograms[0].template_source is only valid for generic subprograms",
    ),
    (
        "safei-shared-required-ceiling-nonpositive",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_ceiling.safe",
        "objects[0].required_ceiling must be a positive integer",
    ),
]

def run_target_bits_emit_contract_case(safec: Path) -> tuple[bool, str]:
    source_text = """package target_bits_emit

   public max_value : constant integer = 2147483647
"""

    with tempfile.TemporaryDirectory(prefix="safe-target-bits-emit-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_emit.safe"
        source.write_text(source_text, encoding="utf-8")

        for bits in (32, 64):
            case_root = temp_root / f"emit-{bits}"
            out_dir = case_root / "out"
            iface_dir = case_root / "iface"
            ada_dir = case_root / "ada"
            out_dir.mkdir(parents=True, exist_ok=True)
            iface_dir.mkdir(parents=True, exist_ok=True)
            ada_dir.mkdir(parents=True, exist_ok=True)

            emit = run_command(
                [
                    str(safec),
                    "emit",
                    "--target-bits",
                    str(bits),
                    source.name,
                    "--out-dir",
                    str(out_dir),
                    "--interface-dir",
                    str(iface_dir),
                    "--ada-out-dir",
                    str(ada_dir),
                ],
                cwd=temp_root,
            )
            if emit.returncode != 0:
                return False, f"emit {bits}-bit failed: {first_message(emit)}"

            stem = source.stem.lower()
            validate = run_command(
                [
                    sys.executable,
                    str(VALIDATE_OUTPUT_CONTRACTS),
                    "--ast",
                    str(out_dir / f"{stem}.ast.json"),
                    "--typed",
                    str(out_dir / f"{stem}.typed.json"),
                    "--mir",
                    str(out_dir / f"{stem}.mir.json"),
                    "--safei",
                    str(iface_dir / f"{stem}.safei.json"),
                    "--source-path",
                    source.name,
                ],
                cwd=REPO_ROOT,
            )
            if validate.returncode != 0:
                return False, f"validate_output_contracts failed for {bits}-bit emit: {first_message(validate)}"

            typed_payload = json.loads((out_dir / f"{stem}.typed.json").read_text(encoding="utf-8"))
            mir_payload = json.loads((out_dir / f"{stem}.mir.json").read_text(encoding="utf-8"))
            safei_payload = json.loads((iface_dir / f"{stem}.safei.json").read_text(encoding="utf-8"))
            if typed_payload.get("target_bits") != bits:
                return False, f"typed target_bits mismatch for {bits}-bit emit: {typed_payload.get('target_bits')!r}"
            if mir_payload.get("target_bits") != bits:
                return False, f"mir target_bits mismatch for {bits}-bit emit: {mir_payload.get('target_bits')!r}"
            if safei_payload.get("target_bits") != bits:
                return False, f"safei target_bits mismatch for {bits}-bit emit: {safei_payload.get('target_bits')!r}"

    return True, ""


def run_output_contract_target_bits_reject_case(safec: Path) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="safe-target-bits-contract-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_contract.safe"
        source.write_text("print (0)\n", encoding="utf-8")
        out_dir = temp_root / "out"
        iface_dir = temp_root / "iface"
        ada_dir = temp_root / "ada"
        out_dir.mkdir(parents=True, exist_ok=True)
        iface_dir.mkdir(parents=True, exist_ok=True)
        ada_dir.mkdir(parents=True, exist_ok=True)

        emit = run_command(
            [
                str(safec),
                "emit",
                source.name,
                "--out-dir",
                str(out_dir),
                "--interface-dir",
                str(iface_dir),
                "--ada-out-dir",
                str(ada_dir),
            ],
            cwd=temp_root,
        )
        if emit.returncode != 0:
            return False, f"emit failed: {first_message(emit)}"

        stem = source.stem.lower()
        mir_path = out_dir / f"{stem}.mir.json"
        mir_payload = json.loads(mir_path.read_text(encoding="utf-8"))
        mir_payload["target_bits"] = 16
        mir_path.write_text(json.dumps(mir_payload, indent=2) + "\n", encoding="utf-8")

        validate = run_command(
            [
                sys.executable,
                str(VALIDATE_OUTPUT_CONTRACTS),
                "--ast",
                str(out_dir / f"{stem}.ast.json"),
                "--typed",
                str(out_dir / f"{stem}.typed.json"),
                "--mir",
                str(mir_path),
                "--safei",
                str(iface_dir / f"{stem}.safei.json"),
                "--source-path",
                source.name,
            ],
            cwd=REPO_ROOT,
        )
        if validate.returncode == 0:
            return False, "validate_output_contracts unexpectedly succeeded for invalid target_bits"
        output = validate.stderr or validate.stdout
        if "mir.json.target_bits must be 32 or 64" not in output:
            return False, f"missing target_bits validation message in {output!r}"

    return True, ""

def run_ast_contract_case(
    safec: Path,
    source: Path,
    *,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / f"ast-{source.stem}"
    case_root.mkdir(parents=True, exist_ok=True)
    ast_path = case_root / f"{source.stem.lower()}.ast.json"

    ast = run_command([str(safec), "ast", repo_rel(source)], cwd=REPO_ROOT)
    if ast.returncode != 0:
        return False, f"ast failed: {first_message(ast)}"
    ast_path.write_text(ast.stdout, encoding="utf-8")

    validate = run_command([sys.executable, str(VALIDATE_AST_OUTPUT), str(ast_path)], cwd=REPO_ROOT)
    if validate.returncode != 0:
        return False, first_message(validate)
    return True, ""


def run_output_contract_case(
    safec: Path,
    source: Path,
    *,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / source.stem
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
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
    if emit.returncode != 0:
        return False, f"emit failed: {first_message(emit)}"

    stem = source.stem.lower()
    validate = run_command(
        [
            sys.executable,
            str(VALIDATE_OUTPUT_CONTRACTS),
            "--ast",
            str(out_dir / f"{stem}.ast.json"),
            "--typed",
            str(out_dir / f"{stem}.typed.json"),
            "--mir",
            str(out_dir / f"{stem}.mir.json"),
            "--safei",
            str(iface_dir / f"{stem}.safei.json"),
            "--source-path",
            repo_rel(source),
        ],
        cwd=REPO_ROOT,
    )
    if validate.returncode != 0:
        return False, first_message(validate)
    return True, ""


def run_output_contract_reject_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    expected_message: str,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / f"{source.stem}-{label}"
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
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
    if emit.returncode != 0:
        return False, f"emit failed: {first_message(emit)}"

    stem = source.stem.lower()
    safei_path = iface_dir / f"{stem}.safei.json"
    payload = json.loads(safei_path.read_text(encoding="utf-8"))
    if label == "safei-bad-return-flag":
        subprograms = payload.get("subprograms")
        if not isinstance(subprograms, list) or not subprograms:
            return False, "emitted safei has no subprograms to mutate"
        subprograms[0]["return_is_access_def"] = "bad"
    elif label == "safei-template-source-key-on-non-generic":
        subprograms = payload.get("subprograms")
        if not isinstance(subprograms, list) or not subprograms:
            return False, "emitted safei has no subprograms to mutate"
        subprograms[0]["template_source"] = None
    elif label == "safei-shared-required-ceiling-nonpositive":
        objects = payload.get("objects")
        if not isinstance(objects, list) or not objects:
            return False, "emitted safei has no objects to mutate"
        objects[0]["required_ceiling"] = 0
    else:
        return False, f"unknown output contract reject case {label}"
    safei_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    validate = run_command(
        [
            sys.executable,
            str(VALIDATE_OUTPUT_CONTRACTS),
            "--ast",
            str(out_dir / f"{stem}.ast.json"),
            "--typed",
            str(out_dir / f"{stem}.typed.json"),
            "--mir",
            str(out_dir / f"{stem}.mir.json"),
            "--safei",
            str(safei_path),
            "--source-path",
            repo_rel(source),
        ],
        cwd=REPO_ROOT,
    )
    if validate.returncode == 0:
        return False, "validate_output_contracts unexpectedly succeeded"
    output = validate.stderr or validate.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""

def run_tuple_destructure_mir_type_case(safec: Path, *, temp_root: Path) -> tuple[bool, str]:
    source = REPO_ROOT / "tests" / "positive" / "pr113_tuple_destructure.safe"

    case_root = temp_root / "pr113-tuple-destructure-mir-type"
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
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
    if emit.returncode != 0:
        return False, f"emit failed: {first_message(emit)}"

    stem = source.stem.lower()
    mir_payload = json.loads((out_dir / f"{stem}.mir.json").read_text(encoding="utf-8"))
    read_second = next(
        (graph for graph in mir_payload.get("graphs", []) if graph.get("name") == "read_second"),
        None,
    )
    if read_second is None:
        return False, "missing read_second graph in tuple destructure MIR"

    expected_types = {
        "__safe_destructure_1": "__tuple_boolean_integer",
        "found": "boolean",
        "value": "integer",
    }
    found_types: dict[str, str] = {}

    for block in read_second.get("blocks", []):
        for op in block.get("ops", []):
            if op.get("kind") != "assign":
                continue
            target = op.get("target", {})
            if target.get("tag") != "ident":
                continue
            name = target.get("name")
            if name in expected_types and op.get("declaration_init") is True:
                found_types[name] = op.get("type")

    for name, expected in expected_types.items():
        actual = found_types.get(name)
        if actual != expected:
            return False, f"tuple destructure MIR type for {name!r} was {actual!r}, expected {expected!r}"

    return True, ""


def run_multi_decl_object_target_type_case(safec: Path, *, temp_root: Path) -> tuple[bool, str]:
    source = REPO_ROOT / "tests" / "positive" / "pr1122f1_multi_decl_object.safe"

    case_root = temp_root / "pr1122f1-multi-decl-object-mir-type"
    out_dir = case_root / "out"
    iface_dir = case_root / "iface"
    ada_dir = case_root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)

    emit = run_command(
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
    if emit.returncode != 0:
        return False, f"emit failed: {first_message(emit)}"

    stem = source.stem.lower()
    mir_payload = json.loads((out_dir / f"{stem}.mir.json").read_text(encoding="utf-8"))
    sum_pair = next(
        (graph for graph in mir_payload.get("graphs", []) if graph.get("name") == "sum_pair"),
        None,
    )
    if sum_pair is None:
        return False, "missing sum_pair graph in multi-name object declaration MIR"

    expected_types = {
        "left": "counter",
        "right": "counter",
    }
    found_types: dict[str, tuple[str | None, str | None]] = {}

    for block in sum_pair.get("blocks", []):
        for op in block.get("ops", []):
            if op.get("kind") != "assign":
                continue
            target = op.get("target", {})
            if target.get("tag") != "ident":
                continue
            name = target.get("name")
            if name in expected_types and op.get("declaration_init") is True:
                found_types[name] = (op.get("type"), target.get("type"))

    for name, expected in expected_types.items():
        actual = found_types.get(name)
        if actual is None:
            return False, f"missing declaration-init assign for {name!r} in multi-name object declaration MIR"
        op_type, target_type = actual
        if op_type != expected:
            return False, f"multi-name object decl MIR op type for {name!r} was {op_type!r}, expected {expected!r}"
        if target_type != expected:
            return False, f"multi-name object decl MIR target type for {name!r} was {target_type!r}, expected {expected!r}"

    return True, ""



def run_contract_checks(safec: Path, *, temp_root: Path) -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []

    for source in AST_CONTRACT_CASES:
        passed += record_result(
            failures,
            f"ast-contract:{repo_rel(source)}",
            run_ast_contract_case(safec, source, temp_root=temp_root),
        )

    for source in OUTPUT_CONTRACT_CASES:
        passed += record_result(
            failures,
            f"contracts:{repo_rel(source)}",
            run_output_contract_case(safec, source, temp_root=temp_root),
        )

    for label, source, expected_message in OUTPUT_CONTRACT_REJECT_CASES:
        passed += record_result(
            failures,
            f"contracts-reject:{label}:{repo_rel(source)}",
            run_output_contract_reject_case(
                safec,
                label=label,
                source=source,
                expected_message=expected_message,
                temp_root=temp_root,
            ),
        )

    passed += record_result(failures, "contracts-reject:target-bits", run_output_contract_target_bits_reject_case(safec))
    passed += record_result(failures, "target-bits emit contract", run_target_bits_emit_contract_case(safec))
    return passed, 0, failures


def run_mir_type_checks(safec: Path, *, temp_root: Path) -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    passed += record_result(
        failures,
        "mir-shape:tuple-destructure-type-names",
        run_tuple_destructure_mir_type_case(safec, temp_root=temp_root),
    )
    passed += record_result(
        failures,
        "mir-shape:multi-decl-object-target-types",
        run_multi_decl_object_target_type_case(safec, temp_root=temp_root),
    )
    return passed, 0, failures
