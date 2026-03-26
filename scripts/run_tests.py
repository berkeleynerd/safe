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


def run_command(argv: list[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=os.environ.copy(),
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

    for source, golden in DIAGNOSTIC_GOLDEN_CASES:
        ok, detail = run_diagnostic_golden(safec, source, golden)
        label = f"{repo_rel(source)} -> {repo_rel(golden)}"
        if ok:
            passed += 1
        else:
            failures.append((label, detail))

    print_summary(passed=passed, failures=failures)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
