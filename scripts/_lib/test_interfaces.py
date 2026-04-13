"""Interface import/export checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

from _lib.test_harness import (
    DIAGNOSTIC_EXIT_CODE,
    REPO_ROOT,
    RunCounts,
    first_message,
    record_result,
    repo_rel,
    run_command,
)

INTERFACE_CASES = [
    (
        "types",
        REPO_ROOT / "tests" / "interfaces" / "provider_types.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_types.safe",
        0,
    ),
    (
        "channel",
        REPO_ROOT / "tests" / "interfaces" / "provider_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_channel.safe",
        0,
    ),
    (
        "object",
        REPO_ROOT / "tests" / "interfaces" / "provider_object.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_object.safe",
        0,
    ),
    (
        "constant-range",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_int.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_range.safe",
        0,
    ),
    (
        "constant-capacity",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_int.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_capacity.safe",
        0,
    ),
    (
        "constant-bool",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_bool.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_bool.safe",
        0,
    ),
    (
        "constant-missing-value",
        REPO_ROOT / "tests" / "interfaces" / "provider_constant_unsupported.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_constant_missing_value.safe",
        1,
    ),
    (
        "transitive-channel-provider-ceiling",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_provider_ceiling.safe",
        0,
    ),
    (
        "transitive-channel-client-ceiling",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_client_ceiling.safe",
        0,
    ),
    (
        "shared-provider-ceiling",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_ceiling.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_shared_provider_ceiling.safe",
        0,
    ),
    (
        "transitive-shared-ok",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_shared.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_shared_ok.safe",
        0,
    ),
    (
        "transitive-global-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_global.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_global_ok.safe",
        1,
    ),
    (
        "imported-global-length-attribute-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_string_object.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_length_attribute_rejected.safe",
        1,
    ),
    (
        "imported-borrow-observe",
        REPO_ROOT / "tests" / "interfaces" / "provider_imported_call_ownership.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_borrow_observe.safe",
        0,
    ),
    (
        "mutual-family",
        REPO_ROOT / "tests" / "interfaces" / "provider_mutual_family.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_mutual_family.safe",
        0,
    ),
    (
        "directional-channel-receive-only",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_receive_only.safe",
        0,
    ),
    (
        "directional-channel-send-contract-violation",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_send_contract_violation.safe",
        1,
    ),
    (
        "binary",
        REPO_ROOT / "tests" / "interfaces" / "provider_binary.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_binary.safe",
        0,
    ),
    (
        "entry-with-clause",
        REPO_ROOT / "tests" / "interfaces" / "provider_types.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_entry_with_clause.safe",
        0,
    ),
    (
        "entry-import-rejected",
        REPO_ROOT / "tests" / "interfaces" / "entry_helper.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_import_entry_rejected.safe",
        1,
    ),
    (
        "enum",
        REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_enum.safe",
        0,
    ),
    (
        "enum-unqualified-import-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_enum_unqualified.safe",
        1,
    ),
    (
        "enum-literal-assign-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_enum.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_enum_literal_assign.safe",
        1,
    ),
    (
        "optional",
        REPO_ROOT / "tests" / "interfaces" / "provider_optional.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_optional.safe",
        0,
    ),
    (
        "list",
        REPO_ROOT / "tests" / "interfaces" / "provider_list.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_list.safe",
        0,
    ),
    (
        "map",
        REPO_ROOT / "tests" / "interfaces" / "provider_map.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_map.safe",
        0,
    ),
    (
        "list-method",
        REPO_ROOT / "tests" / "interfaces" / "provider_list.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_list_method.safe",
        0,
    ),
    (
        "optional-method",
        REPO_ROOT / "tests" / "interfaces" / "provider_optional.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_optional_method.safe",
        0,
    ),
    (
        "imported-method-observe",
        REPO_ROOT / "tests" / "interfaces" / "provider_imported_call_ownership.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_method_observe.safe",
        0,
    ),
    (
        "imported-interface",
        REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_printable.safe",
        0,
    ),
    (
        "imported-generic",
        REPO_ROOT / "tests" / "interfaces" / "provider_generic.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_generic.safe",
        0,
    ),
    (
        "imported-generic-constraint",
        REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_generic_constraint.safe",
        0,
    ),
    (
        "shared-record",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_record.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_shared_record.safe",
        0,
    ),
    (
        "shared-list",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_list.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_shared_list.safe",
        0,
    ),
    (
        "shared-map",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_map.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_shared_map.safe",
        0,
    ),
    (
        "shared-mut-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_list.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_shared_mut_reject.safe",
        1,
    ),
    (
        "sum-shape",
        REPO_ROOT / "tests" / "interfaces" / "provider_sum_shape.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_sum_shape.safe",
        0,
    ),
]

INTERFACE_REJECT_CASES = [
    (
        "imported-channel-elab-send",
        REPO_ROOT / "tests" / "interfaces" / "provider_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_channel_elab_send.safe",
        "unit-scope elaboration must not perform imported channel operations",
    ),
    (
        "imported-channel-elab-receive",
        REPO_ROOT / "tests" / "interfaces" / "provider_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_channel_elab_receive.safe",
        "unit-scope elaboration must not perform imported channel operations",
    ),
    (
        "imported-channel-elab-try-receive",
        REPO_ROOT / "tests" / "interfaces" / "provider_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_channel_elab_try_receive.safe",
        "unit-scope elaboration must not perform imported channel operations",
    ),
    (
        "select-public-channel",
        REPO_ROOT / "tests" / "interfaces" / "provider_select_channel.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_select_channel.safe",
        "PR11.9a temporarily admits select arms only on same-unit non-public channels",
    ),
    (
        "ambiguous-imported-method",
        REPO_ROOT / "tests" / "interfaces" / "provider_optional.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_optional_method_ambiguous.safe",
        "ambiguous method call `unwrap_or_zero`",
    ),
    (
        "ambiguous-interface-satisfaction",
        REPO_ROOT / "tests" / "interfaces" / "provider_printable.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_printable_ambiguous.safe",
        "does not satisfy interface",
    ),
    (
        "imported-generic-missing-type-args",
        REPO_ROOT / "tests" / "interfaces" / "provider_generic.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_generic_missing_args.safe",
        "requires explicit type arguments in PR11.11c",
    ),
    (
        "sum-bare-imported-constructor",
        REPO_ROOT / "tests" / "interfaces" / "provider_sum_shape.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_sum_shape_bare_constructor.safe",
        "object initializer type does not match declared type",
    ),
]

STATIC_INTERFACE_CASES = [
    (
        "legacy-channel-unconstrained",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_legacy_transitive_channel_unconstrained.safe",
        0,
    ),
    (
        "legacy-channel-requires-regen",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_receive_only.safe",
        1,
    ),
    (
        "legacy-channel-result-function-rejected",
        REPO_ROOT / "tests" / "interfaces" / "provider_pr222_legacy_channel_result.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_pr222_legacy_channel_result.safe",
        1,
    ),
    (
        "bad-return-flag-type",
        REPO_ROOT / "tests" / "interfaces" / "provider_bad_return_flag.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_bad_return_flag.safe",
        1,
    ),
    (
        "missing-unit-kind",
        REPO_ROOT / "tests" / "interfaces" / "provider_missing_unit_kind.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_missing_unit_kind.safe",
        1,
    ),
    (
        "bad-sum-metadata",
        REPO_ROOT / "tests" / "interfaces" / "provider_bad_sum.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_bad_sum.safe",
        1,
    ),
    (
        "bad-zero-payload-sum-metadata",
        REPO_ROOT / "tests" / "interfaces" / "provider_bad_zero_sum.safei.json",
        REPO_ROOT / "tests" / "interfaces" / "client_bad_zero_sum.safe",
        1,
    ),
]

def run_interface_case(
    safec: Path,
    *,
    label: str,
    provider: Path,
    client: Path,
    expected_returncode: int,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / label
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
            repo_rel(provider),
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
        return False, f"provider emit failed: {first_message(emit)}"

    safei_path = iface_dir / f"{provider.stem.lower()}.safei.json"
    if not safei_path.exists():
        return False, f"provider emit missing {safei_path.name}"

    completed = run_command(
        [
            str(safec),
            "check",
            repo_rel(client),
            "--interface-search-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != expected_returncode:
        expectation = str(expected_returncode)
        return False, f"expected exit {expectation}, got {completed.returncode}: {first_message(completed)}"
    return True, ""


def run_interface_reject_case(
    safec: Path,
    *,
    label: str,
    provider: Path,
    client: Path,
    expected_message: str,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / label
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
            repo_rel(provider),
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
        return False, f"provider emit failed: {first_message(emit)}"

    completed = run_command(
        [
            str(safec),
            "check",
            repo_rel(client),
            "--interface-search-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != DIAGNOSTIC_EXIT_CODE:
        return False, f"expected exit {DIAGNOSTIC_EXIT_CODE}, got {completed.returncode}: {first_message(completed)}"
    output = completed.stderr or completed.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""


def run_static_interface_case(
    safec: Path,
    *,
    label: str,
    safei: Path,
    client: Path,
    expected_returncode: int,
    temp_root: Path,
) -> tuple[bool, str]:
    case_root = temp_root / label
    iface_dir = case_root / "iface"
    iface_dir.mkdir(parents=True, exist_ok=True)

    safei_target = iface_dir / safei.name
    shutil.copyfile(safei, safei_target)

    completed = run_command(
        [
            str(safec),
            "check",
            repo_rel(client),
            "--interface-search-dir",
            str(iface_dir),
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != expected_returncode:
        expectation = str(expected_returncode)
        return False, f"expected exit {expectation}, got {completed.returncode}: {first_message(completed)}"
    return True, ""

def run_interface_target_bits_case(safec: Path) -> tuple[bool, str]:
    provider = REPO_ROOT / "tests" / "interfaces" / "provider_types.safe"
    client = REPO_ROOT / "tests" / "interfaces" / "client_types.safe"
    legacy_safei = REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safei.json"
    legacy_client = REPO_ROOT / "tests" / "interfaces" / "client_transitive_channel_receive_only.safe"

    with tempfile.TemporaryDirectory(prefix="safe-interface-target-bits-") as temp_root_str:
        temp_root = Path(temp_root_str)

        mismatch_root = temp_root / "mismatch"
        out_dir = mismatch_root / "out"
        iface_dir = mismatch_root / "iface"
        ada_dir = mismatch_root / "ada"
        out_dir.mkdir(parents=True, exist_ok=True)
        iface_dir.mkdir(parents=True, exist_ok=True)
        ada_dir.mkdir(parents=True, exist_ok=True)

        emit = run_command(
            [
                str(safec),
                "emit",
                "--target-bits",
                "64",
                repo_rel(provider),
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
            return False, f"64-bit provider emit failed: {first_message(emit)}"

        mismatch = run_command(
            [
                str(safec),
                "check",
                "--target-bits",
                "32",
                repo_rel(client),
                "--interface-search-dir",
                str(iface_dir),
            ],
            cwd=REPO_ROOT,
        )
        if mismatch.returncode != DIAGNOSTIC_EXIT_CODE:
            return False, f"32-bit imported-interface mismatch unexpectedly returned {mismatch.returncode}: {first_message(mismatch)}"
        mismatch_output = mismatch.stderr or mismatch.stdout
        expected = "imported interface `provider_types` target_bits 64 does not match current target_bits 32"
        if expected not in mismatch_output:
            return False, f"missing target_bits mismatch diagnostic in {mismatch_output!r}"

        legacy_root = temp_root / "legacy"
        legacy_iface_dir = legacy_root / "iface"
        legacy_iface_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(legacy_safei, legacy_iface_dir / legacy_safei.name)

        legacy = run_command(
            [
                str(safec),
                "check",
                "--target-bits",
                "32",
                repo_rel(legacy_client),
                "--interface-search-dir",
                str(legacy_iface_dir),
            ],
            cwd=REPO_ROOT,
        )
        if legacy.returncode != DIAGNOSTIC_EXIT_CODE:
            return False, f"32-bit legacy interface unexpectedly returned {legacy.returncode}: {first_message(legacy)}"
        legacy_output = legacy.stderr or legacy.stdout
        expected_legacy = "imported interface `provider_transitive_channel` target_bits 64 does not match current target_bits 32"
        if expected_legacy not in legacy_output:
            return False, f"missing legacy target_bits mismatch diagnostic in {legacy_output!r}"

    return True, ""



def run_interface_checks(safec: Path, *, temp_root: Path) -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []

    for label, provider, client, expected_returncode in INTERFACE_CASES:
        passed += record_result(
            failures,
            f"{repo_rel(provider)} -> {repo_rel(client)}",
            run_interface_case(
                safec,
                label=label,
                provider=provider,
                client=client,
                expected_returncode=expected_returncode,
                temp_root=temp_root,
            ),
        )

    for label, provider, client, expected_message in INTERFACE_REJECT_CASES:
        passed += record_result(
            failures,
            f"{repo_rel(provider)} -> {repo_rel(client)}",
            run_interface_reject_case(
                safec,
                label=label,
                provider=provider,
                client=client,
                expected_message=expected_message,
                temp_root=temp_root,
            ),
        )

    for label, safei, client, expected_returncode in STATIC_INTERFACE_CASES:
        passed += record_result(
            failures,
            f"{repo_rel(safei)} -> {repo_rel(client)}",
            run_static_interface_case(
                safec,
                label=label,
                safei=safei,
                client=client,
                expected_returncode=expected_returncode,
                temp_root=temp_root,
            ),
        )

    return passed, 0, failures


def run_interface_target_bits_checks(safec: Path) -> RunCounts:
    failures: list[tuple[str, str]] = []
    passed = record_result(failures, "interface target_bits", run_interface_target_bits_case(safec))
    return passed, 0, failures
