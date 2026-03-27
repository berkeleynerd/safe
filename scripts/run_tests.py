#!/usr/bin/env python3
"""Run the minimal Safe test workflow."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
SAFEC_PATH = COMPILER_ROOT / "bin" / "safec"
ALR_FALLBACK = Path.home() / "bin" / "alr"
DIAGNOSTIC_EXIT_CODE = 1
SAFE_CLI = REPO_ROOT / "scripts" / "safe_cli.py"
SAFE_REPL = REPO_ROOT / "scripts" / "safe_repl.py"
VALIDATE_OUTPUT_CONTRACTS = REPO_ROOT / "scripts" / "validate_output_contracts.py"

# These fixtures live in category directories that do not match the
# compiler's current acceptance boundary, so keep the expectations explicit.
NEGATIVE_SUCCESS_FIXTURES = {
    REPO_ROOT / "tests" / "negative" / "neg_chan_empty_recv.safe",
    REPO_ROOT / "tests" / "negative" / "neg_chan_full_send.safe",
}

CONCURRENCY_REJECT_FIXTURES = {
    REPO_ROOT / "tests" / "concurrency" / "channel_access_type.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_ownership_binding.safe",
    REPO_ROOT / "tests" / "concurrency" / "try_send_ownership.safe",
}

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
        "transitive-global-ok",
        REPO_ROOT / "tests" / "interfaces" / "provider_transitive_global.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_transitive_global_ok.safe",
        0,
    ),
    (
        "imported-borrow-observe",
        REPO_ROOT / "tests" / "interfaces" / "provider_imported_call_ownership.safe",
        REPO_ROOT / "tests" / "interfaces" / "client_imported_borrow_observe.safe",
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
]

DIAGNOSTIC_GOLDEN_CASES = [
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_double_move.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_double_move.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_borrow_conflict.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_borrow_conflict.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_use_after_move.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_use_after_move.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_lifetime.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_lifetime_violation.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_observe_mutate.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_observe_mutation.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_target_not_null.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_move_target_not_null.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_source_maybe_null.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_move_source_not_nonnull.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_anon_reassign.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_anonymous_access_reassign.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_anon_reassign_join.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_anonymous_access_reassign_join.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_own_observe_requires_access.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_observe_requires_access.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_overflow.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule2_oob.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_index_oob.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule3_zero_div.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_zero_div.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule4_null_deref.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_null_deref.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_nan.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_nan.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_result_unguarded.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_result_unguarded.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_result_mutated.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_result_mutated.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_div_zero.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_div_zero.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_infinity.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_infinity.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_overflow.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_overflow.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_rule5_uninitialized.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_rule5_uninitialized.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_while_variant_not_derivable.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_loop_variant_not_derivable.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr117_uppercase_identifier.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_lowercase_spelling.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118_removed_natural.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118_removed_natural.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118b1_send_contract.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118b1_send_contract.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_invalid_binary_width.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_invalid_binary_width.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_implicit_integer_binary_mix.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_implicit_integer_binary_mix.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_shift_count_out_of_range.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_shift_count_out_of_range.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_binary_to_integer_oob.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_binary_to_integer_oob.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c_mixed_logical_operators.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c_mixed_logical_operators.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c1_print_expression.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c1_print_expression.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c1_print_bare_identifier.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c1_print_bare_identifier.txt",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr118c1_print_unsupported_type.safe",
        REPO_ROOT / "tests" / "diagnostics_golden" / "diag_pr118c1_print_unsupported_type.txt",
    ),
]

BUILD_SUCCESS_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_package_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_entry_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_package_pre_task.safe",
        "41\n",
        True,
    ),
]

BUILD_REJECT_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_root_with_clause.safe",
        "safe build: root files with `with` clauses are not supported yet",
    ),
]

OUTPUT_CONTRACT_CASES = [
    REPO_ROOT / "tests" / "positive" / "pr118c2_package_print.safe",
    REPO_ROOT / "tests" / "positive" / "pr118c2_entry_print.safe",
]

REPL_CASES = [
    (
        "repl-prints",
        "value : integer = 41;\nprint (value + 1)\n",
        "42\n",
        None,
    ),
    (
        "repl-rejects-bad-line",
        "value : integer = 41;\nprint (missing_name)\nprint (value + 1)\n",
        "42\n",
        "missing_name",
    ),
    (
        "repl-rejects-task",
        "task worker\n",
        "",
        "task declarations are not supported in repl mode",
    ),
]


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
    argv: list[str],
    *,
    cwd: Path,
    input_text: str | None = None,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=os.environ.copy(),
        text=True,
        input=input_text,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def first_message(completed: subprocess.CompletedProcess[str]) -> str:
    for stream in (completed.stderr, completed.stdout):
        for line in stream.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped
    return f"exit code {completed.returncode}"


def extract_expected_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    marker = "Expected diagnostic output:\n------------------------------------------------------------------------\n"
    start = text.index(marker) + len(marker)
    end = text.index("\n------------------------------------------------------------------------\n", start)
    return text[start:end]


def build_compiler() -> Path:
    alr = find_command("alr", ALR_FALLBACK)
    completed = run_command([alr, "build"], cwd=COMPILER_ROOT)
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    if not SAFEC_PATH.exists():
        raise FileNotFoundError(f"missing safec binary at {SAFEC_PATH}")
    return SAFEC_PATH


def check_fixture(
    safec: Path,
    source: Path,
    *,
    expected_returncode: int,
    extra_args: list[str] | None = None,
) -> tuple[bool, str]:
    argv = [str(safec), "check", repo_rel(source), *(extra_args or [])]
    completed = run_command(argv, cwd=REPO_ROOT)
    ok = completed.returncode == expected_returncode
    return ok, first_message(completed)


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


def run_diagnostic_golden(safec: Path, source: Path, golden: Path) -> tuple[bool, str]:
    completed = run_command([str(safec), "check", repo_rel(source)], cwd=REPO_ROOT)
    if completed.returncode != DIAGNOSTIC_EXIT_CODE:
        return False, f"expected exit {DIAGNOSTIC_EXIT_CODE}, got {completed.returncode}"
    expected = extract_expected_block(golden)
    if completed.stderr.rstrip("\n") != expected.rstrip("\n"):
        return False, f"stderr mismatch against {repo_rel(golden)}"
    return True, ""


def print_summary(*, passed: int, failures: list[tuple[str, str]]) -> None:
    print(f"{passed} passed, {len(failures)} failed")
    if failures:
        print("Failures:")
        for label, detail in failures:
            print(f" - {label}: {detail}")


def executable_name() -> str:
    return "main.exe" if os.name == "nt" else "main"


def safe_build_executable(source: Path) -> Path:
    return source.parent / ".safe-build" / source.stem / executable_name()


def run_safe_build_case(
    source: Path,
    expected_stdout: str,
    *,
    allow_timeout: bool,
) -> tuple[bool, str]:
    build = run_command(
        [sys.executable, str(SAFE_CLI), "build", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if build.returncode != 0:
        return False, f"build failed: {first_message(build)}"

    executable = safe_build_executable(source)
    if not executable.exists():
        return False, f"missing executable {executable}"

    try:
        run = run_command(
            [str(executable)],
            cwd=executable.parent,
            timeout=0.3 if allow_timeout else None,
        )
    except subprocess.TimeoutExpired as exc:
        if not allow_timeout:
            return False, "executable timed out"
        stdout = exc.stdout or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if not stdout.startswith(expected_stdout):
            return False, f"unexpected stdout before timeout {stdout!r}"
        return True, ""

    if run.returncode != 0:
        return False, f"executable failed: {first_message(run)}"
    if allow_timeout:
        if not run.stdout.startswith(expected_stdout):
            return False, f"unexpected stdout {run.stdout!r}"
    elif run.stdout != expected_stdout:
        return False, f"unexpected stdout {run.stdout!r}"
    return True, ""


def run_safe_build_reject_case(source: Path, expected_message: str) -> tuple[bool, str]:
    build = run_command(
        [sys.executable, str(SAFE_CLI), "build", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if build.returncode == 0:
        return False, "build unexpectedly succeeded"
    output = build.stderr or build.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
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


def run_repl_case(
    *,
    label: str,
    input_text: str,
    expected_stdout: str,
    expected_stderr_substring: str | None,
) -> tuple[bool, str]:
    completed = run_command(
        [sys.executable, str(SAFE_REPL)],
        cwd=REPO_ROOT,
        input_text=input_text,
    )
    if completed.returncode != 0:
        return False, f"repl failed: {first_message(completed)}"
    if completed.stdout != expected_stdout:
        return False, f"unexpected stdout {completed.stdout!r}"
    if expected_stderr_substring is not None and expected_stderr_substring not in completed.stderr:
        return False, f"missing expected stderr {expected_stderr_substring!r}"
    return True, ""


def main() -> int:
    try:
        safec = build_compiler()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_tests: ERROR: {exc}", file=sys.stderr)
        return 1

    passed = 0
    failures: list[tuple[str, str]] = []

    positive_fixtures = sorted((REPO_ROOT / "tests" / "positive").glob("*.safe"))
    negative_fixtures = sorted((REPO_ROOT / "tests" / "negative").glob("*.safe"))
    concurrency_fixtures = sorted((REPO_ROOT / "tests" / "concurrency").glob("*.safe"))

    for fixture in positive_fixtures:
        ok, detail = check_fixture(safec, fixture, expected_returncode=0)
        if ok:
            passed += 1
        else:
            failures.append((repo_rel(fixture), detail))

    for fixture in negative_fixtures:
        expected_returncode = 0 if fixture in NEGATIVE_SUCCESS_FIXTURES else DIAGNOSTIC_EXIT_CODE
        ok, detail = check_fixture(safec, fixture, expected_returncode=expected_returncode)
        if ok:
            passed += 1
        else:
            failures.append((repo_rel(fixture), detail))

    for fixture in concurrency_fixtures:
        expected_returncode = DIAGNOSTIC_EXIT_CODE if fixture in CONCURRENCY_REJECT_FIXTURES else 0
        ok, detail = check_fixture(safec, fixture, expected_returncode=expected_returncode)
        if ok:
            passed += 1
        else:
            failures.append((repo_rel(fixture), detail))

    with tempfile.TemporaryDirectory(prefix="safe-tests-") as temp_root_str:
        temp_root = Path(temp_root_str)
        for label, provider, client, expected_returncode in INTERFACE_CASES:
            ok, detail = run_interface_case(
                safec,
                label=label,
                provider=provider,
                client=client,
                expected_returncode=expected_returncode,
                temp_root=temp_root,
            )
            pair_label = f"{repo_rel(provider)} -> {repo_rel(client)}"
            if ok:
                passed += 1
            else:
                failures.append((pair_label, detail))

        for label, safei, client, expected_returncode in STATIC_INTERFACE_CASES:
            ok, detail = run_static_interface_case(
                safec,
                label=label,
                safei=safei,
                client=client,
                expected_returncode=expected_returncode,
                temp_root=temp_root,
            )
            pair_label = f"{repo_rel(safei)} -> {repo_rel(client)}"
            if ok:
                passed += 1
            else:
                failures.append((pair_label, detail))

        for source in OUTPUT_CONTRACT_CASES:
            ok, detail = run_output_contract_case(safec, source, temp_root=temp_root)
            label = f"contracts:{repo_rel(source)}"
            if ok:
                passed += 1
            else:
                failures.append((label, detail))

    for source, golden in DIAGNOSTIC_GOLDEN_CASES:
        ok, detail = run_diagnostic_golden(safec, source, golden)
        label = f"{repo_rel(source)} -> {repo_rel(golden)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for source, expected_stdout, allow_timeout in BUILD_SUCCESS_CASES:
        ok, detail = run_safe_build_case(source, expected_stdout, allow_timeout=allow_timeout)
        label = f"safe build {repo_rel(source)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for source, expected_message in BUILD_REJECT_CASES:
        ok, detail = run_safe_build_reject_case(source, expected_message)
        label = f"safe build {repo_rel(source)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    for label, input_text, expected_stdout, expected_stderr_substring in REPL_CASES:
        ok, detail = run_repl_case(
            label=label,
            input_text=input_text,
            expected_stdout=expected_stdout,
            expected_stderr_substring=expected_stderr_substring,
        )
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    print_summary(passed=passed, failures=failures)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
