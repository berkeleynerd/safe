"""Safe CLI workflow checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from _lib.test_harness import (
    REPO_ROOT,
    SAFE_CLI,
    SAFE_REPL,
    VSCODE_PACKAGE_JSON,
    VSCODE_README,
    RunCounts,
    clear_project_artifacts,
    ensure_sdkroot,
    executable_name,
    first_message,
    record_result,
    repo_rel,
    run_command,
    safe_build_executable,
    safe_prove_summary_path,
)

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
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_field_build.safe",
        "5\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_array_component_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_tick_build.safe",
        "42\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_bounded_string_index_build.safe",
        "h\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_array_build.safe",
        "32\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_string_plain_build.safe",
        "hello\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr212_string_literal_build.safe",
        "111\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr226_remainder_boolean_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr223_imported_enum_comparison_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr225_imported_string_literal_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr224_imported_generic_string_aggregate_build.safe",
        "demo\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110a_optional_string_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110a_optional_growable_build.safe",
        "3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_build.safe",
        "40\n3\n30\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_empty_build.safe",
        "0\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_string_build.safe",
        "Bob\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_growable_build.safe",
        "2\n8\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110c_map_build.safe",
        "15\n20\n1\n2\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110c_map_string_build.safe",
        "Bob\nAda\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110c_map_list_build.safe",
        "3\n3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr213_map_entry_build.safe",
        "11\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr220_for_of_composite_unroll_build.safe",
        "Ada\nAda\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111a_builtin_methods_build.safe",
        "30\n15\n20\n2\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111b_interface_builtin_build.safe",
        "1\n20\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111c_generic_build.safe",
        "3\n9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111c_imported_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1111c_imported_alias_and_collision_build.safe",
        "10\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112a_shared_task_build.safe",
        "4\n5\n3\n2\n",
        True,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112b_shared_update_build.safe",
        "4\n7\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr227_shared_snapshot_order_build.safe",
        "17\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr227_public_shared_snapshot_order_build.safe",
        "17\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr228_shared_field_condition_build.safe",
        "17\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr228_imported_shared_condition_build.safe",
        "17\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr228_shared_loop_exit_condition_build.safe",
        "17\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_string_build.safe",
        "start\ninner\nworld\nBob\nright\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_container_fields_build.safe",
        "3\nBob\n3\n2\nAda\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112c_layered_growable_type_build.safe",
        "3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1122f2_shared_bounded_string_field_build.safe",
        "world\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1122f2_shared_optional_string_none_build.safe",
        "cleared\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_list_root_build.safe",
        "4\n4\n3\n9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_map_root_build.safe",
        "2\n2\n1\n1\n1\n10\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_map_indexed_remove_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_growable_root_build.safe",
        "3\n7\n2\n9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112e_imported_shared_record_build.safe",
        "1\n7\n8\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112e_imported_shared_list_build.safe",
        "2\n3\n9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112e_imported_shared_map_build.safe",
        "2\n2\n1\n0\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112f_shared_record_ceiling_build.safe",
        "20\n",
        True,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112f_shared_container_ceiling_build.safe",
        "14\n",
        True,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1112f_mixed_channel_shared_build.safe",
        "18\n",
        True,
    ),
    (
        REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_receive.safe",
        "7\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_timeout.safe",
        "9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "interfaces" / "pr119a_select_zero_delay_ready.safe",
        "4\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr230_top_level_select_delay_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_tuple_string_build.safe",
        "ok\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_string_field_runtime_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_string_array_component_runtime_build.safe",
        "Bob\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_param_runtime_build.safe",
        "7\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_result_runtime_build.safe",
        "2\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_field_runtime_build.safe",
        "20\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_array_component_runtime_build.safe",
        "3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_empty_growable_array_literal_build.safe",
        "0\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_runtime_self_assign_build.safe",
        "Ada\n5\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_for_of_fixed_build.safe",
        "60\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_for_of_growable_build.safe",
        "60\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_for_of_heap_element_build.safe",
        "a\nbc\ndef\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_nested_growable_array_literal_build.safe",
        "4\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_fixed_to_growable_build.safe",
        "25\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_to_fixed_literal_build.safe",
        "40\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d_growable_to_fixed_slice_build.safe",
        "16\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_for_of_string_build.safe",
        "5\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_string_order_build.safe",
        "15\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_string_case_build.safe",
        "3\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118d1_growable_to_fixed_guard_build.safe",
        "10\n20\n10\n20\ndone\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        "Ada\nBob\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        "1\n2\n9\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_tuple_string_channel_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_record_string_channel_build.safe",
        "Ada\nBob\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        "1\nAda\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr119d_send_single_eval_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118e1_mutual_family_build.safe",
        "41\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "interfaces" / "pr169_safe_elaborate_collision.safe",
        "41\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_build.safe",
        "30\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_arg_order_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1116_nominal_integer_build.safe",
        "43\n41\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1116_imported_nominal_build.safe",
        "41\n6\n6\n",
        False,
    ),
]

BUILD_REJECT_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_root_with_clause.safe",
        "local dependency source not found for package `missing_helper`",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_arithmetic_typed_integer.safe",
        "nominal arithmetic requires operands from the same nominal type family or in-range integer literals",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_cross_family.safe",
        "object initializer type does not match declared type",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_cross_family_arith.safe",
        "nominal arithmetic requires operands from the same nominal type family or in-range integer literals",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_derived_implicit.safe",
        "object initializer type does not match declared type",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_implicit_integer.safe",
        "object initializer type does not match declared type",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_literal_oob.safe",
        "integer literal 11 is outside range of nominal-family type user_id (0 .. 10)",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_non_integer_parent.safe",
        "nominal type aliases require an integer-family parent in PR11.16",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_to_integer.safe",
        "object initializer type does not match declared type",
    ),
    (
        REPO_ROOT / "tests" / "negative" / "neg_pr1116_nominal_typed_integer_comparison.safe",
        "nominal comparisons require operands from the same nominal type family or integer literals within the nominal target's bounds",
    ),
]

RUN_SUCCESS_CASES = [
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
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_build.safe",
        "30\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr118k_try_arg_order_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1110b_list_empty_build.safe",
        "0\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1113a_sum_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1113b_sum_match_build.safe",
        "1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1113c_provider_shape.safe",
        "3\n0\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1113c_imported_sum_build.safe",
        "3\n0\n5\n1\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1113c_imported_string_sum_build.safe",
        "Ada\n",
        False,
    ),
    (
        REPO_ROOT / "tests" / "build" / "pr1113c_imported_overlap_build.safe",
        "2\n7\n",
        False,
    ),
]

RUN_REJECT_CASES = [
    (
        REPO_ROOT / "tests" / "build" / "pr118c2_root_with_clause.safe",
        "local dependency source not found for package `missing_helper`",
    ),
]

DEPLOY_REJECT_ARGV_CASES = [
    (
        [
            "deploy",
            "--simulate",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--board",
    ),
    (
        [
            "deploy",
            "--board",
            "not-a-board",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "invalid choice",
    ),
    (
        [
            "deploy",
            "--target",
            "bogus",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "requires target 'stm32f4', got 'bogus'",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "tests/build/pr118c2_root_with_clause.safe",
        ],
        "safe deploy: imported roots with leading `with` clauses are not supported for this command yet",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "--expect-value",
            "42",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--watch-symbol and --expect-value must be provided together",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--simulate",
            "--watch-symbol",
            "entry_integer_result__result",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--watch-symbol and --expect-value must be provided together",
    ),
    (
        [
            "deploy",
            "--board",
            "stm32f4-discovery",
            "--watch-symbol",
            "entry_integer_result__result",
            "--expect-value",
            "42",
            "tests/build/pr118c2_entry_build.safe",
        ],
        "--watch-symbol is currently supported only with --simulate",
    ),
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

def run_ensure_sdkroot_case() -> tuple[bool, str]:
    calls: list[tuple[list[str], dict[str, str]]] = []

    def fake_xcrun_runner(
        argv: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if kwargs.get("text") is not True or kwargs.get("capture_output") is not True or kwargs.get("check") is not False:
            raise AssertionError("unexpected xcrun runner flags")
        probe_env = kwargs.get("env")
        if not isinstance(probe_env, dict):
            raise AssertionError("missing xcrun env")
        calls.append((argv, probe_env))
        return subprocess.CompletedProcess(argv, 0, stdout="/fake/sdk\n", stderr="")

    env = {
        "PATH": "/usr/bin",
        "SDKROOT": "/stale/sdk",
        "MACOSX_DEPLOYMENT_TARGET": "16.0",
    }
    updated = ensure_sdkroot(env, platform_name="darwin", xcrun_runner=fake_xcrun_runner)
    if len(calls) != 1:
        return False, f"unexpected xcrun calls {calls!r}"
    argv, probe_env = calls[0]
    if argv != ["xcrun", "--sdk", "macosx", "--show-sdk-path"]:
        return False, f"unexpected xcrun argv {argv!r}"
    if probe_env.get("PATH") != env["PATH"]:
        return False, f"unexpected xcrun PATH {probe_env.get('PATH')!r}"
    if "MACOSX_DEPLOYMENT_TARGET" in probe_env:
        return False, "xcrun env should not include MACOSX_DEPLOYMENT_TARGET"
    if updated.get("SDKROOT") != "/fake/sdk":
        return False, f"unexpected SDKROOT {updated.get('SDKROOT')!r}"
    if "MACOSX_DEPLOYMENT_TARGET" in updated:
        return False, "MACOSX_DEPLOYMENT_TARGET should be removed on darwin"
    if updated.get("PATH") != env["PATH"]:
        return False, f"PATH changed unexpectedly to {updated.get('PATH')!r}"
    if env.get("SDKROOT") != "/stale/sdk" or env.get("MACOSX_DEPLOYMENT_TARGET") != "16.0":
        return False, "ensure_sdkroot mutated the input environment"
    return True, ""

def run_safe_build_case(
    source: Path,
    expected_stdout: str,
    *,
    allow_timeout: bool,
) -> tuple[bool, str]:
    clear_project_artifacts(source)
    build = run_command(
        [sys.executable, str(SAFE_CLI), "build", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if build.returncode != 0:
        return False, f"build failed: {first_message(build)}"

    executable = safe_build_executable(source)
    if not executable.exists():
        return False, f"missing executable {executable}"
    expected_banner = f"safe build: OK ({repo_rel(executable)})\n"
    if build.stdout != expected_banner:
        return False, f"unexpected build stdout {build.stdout!r}"
    if build.stderr:
        return False, f"unexpected build stderr {build.stderr!r}"

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
    clear_project_artifacts(source)
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


def run_safe_run_case(
    source: Path,
    expected_stdout: str,
    *,
    allow_timeout: bool,
) -> tuple[bool, str]:
    clear_project_artifacts(source)
    argv = [sys.executable, str(SAFE_CLI), "run", repo_rel(source)]
    if not allow_timeout:
        completed = run_command(argv, cwd=REPO_ROOT)
        if completed.returncode != 0:
            return False, f"safe run failed: {first_message(completed)}"
        if completed.stdout != expected_stdout:
            return False, f"unexpected stdout {completed.stdout!r}"
        if completed.stderr:
            return False, f"unexpected stderr {completed.stderr!r}"
        if "safe build: OK (" in completed.stdout:
            return False, f"unexpected build banner in stdout {completed.stdout!r}"
        return True, ""

    build = run_command(
        [sys.executable, str(SAFE_CLI), "build", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if build.returncode != 0:
        return False, f"safe build failed: {first_message(build)}"

    executable = safe_build_executable(source)
    if not executable.exists():
        return False, f"missing executable {executable}"

    try:
        run = run_command(
            [str(executable)],
            cwd=executable.parent,
            timeout=0.3,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if not stdout.startswith(expected_stdout):
            return False, f"unexpected stdout before timeout {stdout!r}"
        return True, ""
    if run.returncode != 0:
        return False, f"executable failed: {first_message(run)}"
    stdout = run.stdout
    if not stdout.startswith(expected_stdout):
        return False, f"unexpected stdout before timeout {stdout!r}"
    if "safe build: OK (" in stdout:
        return False, f"unexpected build banner in stdout {stdout!r}"
    return True, ""


def run_safe_run_reject_case(source: Path, expected_message: str) -> tuple[bool, str]:
    clear_project_artifacts(source)
    completed = run_command(
        [sys.executable, str(SAFE_CLI), "run", repo_rel(source)],
        cwd=REPO_ROOT,
    )
    if completed.returncode == 0:
        return False, "safe run unexpectedly succeeded"
    output = completed.stderr or completed.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
    return True, ""


def run_safe_run_mutated_iterable_case() -> tuple[bool, str]:
    source_text = """package mutated_iterable_runtime

   plain : string = "Ada";
   total : integer = 0;

   function rewrite (value : mut string)
      value = "Bob";

   rewrite (plain);

   for ch of plain
      if ch == "B" or ch == "o" or ch == "b"
         total = total + 1;

   print (total)
"""

    with tempfile.TemporaryDirectory(prefix="safe-run-mutated-iterable-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "mutated_iterable_runtime.safe"
        source.write_text(source_text, encoding="utf-8")
        completed = run_command(
            [sys.executable, str(SAFE_CLI), "run", source.name],
            cwd=temp_root,
        )
        if completed.returncode != 0:
            return False, f"safe run failed: {first_message(completed)}"
        if completed.stdout != "3\n":
            return False, f"unexpected stdout {completed.stdout!r}"
        if completed.stderr:
            return False, f"unexpected stderr {completed.stderr!r}"
        if "safe build: OK (" in completed.stdout:
            return False, f"unexpected build banner in stdout {completed.stdout!r}"
    return True, ""


def run_safe_build_incremental_case() -> tuple[bool, str]:
    provider_text = """package provider_answer

   public subtype count is integer (0 to 100);
"""
    client_text = """with provider_answer;

subtype answer_count is provider_answer.count;
value : answer_count = 42;
print (value)
"""
    updated_provider_text = provider_text.replace("100", "50")

    with tempfile.TemporaryDirectory(prefix="safe-build-incremental-") as temp_root_str:
        temp_root = Path(temp_root_str)
        provider = temp_root / "provider_answer.safe"
        client = temp_root / "client_answer.safe"
        provider.write_text(provider_text, encoding="utf-8")
        client.write_text(client_text, encoding="utf-8")

        build = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build.returncode != 0:
            return False, f"initial build failed: {first_message(build)}"

        executable = temp_root / "obj" / "client_answer" / "target-64" / executable_name()
        emitted_client = temp_root / ".safe-build" / "target-64" / "ada" / "client_answer.adb"
        if not emitted_client.exists():
            return False, f"missing cached emitted unit {emitted_client}"
        if not executable.exists():
            return False, f"missing executable {executable}"

        run = run_command([str(executable)], cwd=executable.parent)
        if run.returncode != 0:
            return False, f"built executable failed: {first_message(run)}"
        if run.stdout != "42\n":
            return False, f"unexpected initial stdout {run.stdout!r}"

        emitted_mtime = emitted_client.stat().st_mtime_ns
        executable_mtime = executable.stat().st_mtime_ns

        build_cached = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build_cached.returncode != 0:
            return False, f"cached build failed: {first_message(build_cached)}"
        if emitted_client.stat().st_mtime_ns != emitted_mtime:
            return False, "cached build rewrote emitted Ada"
        if executable.stat().st_mtime_ns != executable_mtime:
            return False, "cached build rewrote executable"

        cached_text = emitted_client.read_text(encoding="utf-8")
        emitted_client.write_text("corrupted emitted Ada\n", encoding="utf-8")
        build_corrupt = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build_corrupt.returncode != 0:
            return False, f"artifact-recovery build failed: {first_message(build_corrupt)}"
        if emitted_client.read_text(encoding="utf-8") != cached_text:
            return False, "corrupted emitted Ada was not regenerated"

        provider.write_text(updated_provider_text, encoding="utf-8")
        build_updated = run_command([sys.executable, str(SAFE_CLI), "build", client.name], cwd=temp_root)
        if build_updated.returncode != 0:
            return False, f"dependency-invalidated build failed: {first_message(build_updated)}"
        if emitted_client.stat().st_mtime_ns == emitted_mtime:
            return False, "dependency interface change did not re-emit client"
        run_updated = run_command([str(executable)], cwd=executable.parent)
        if run_updated.returncode != 0:
            return False, f"updated executable failed: {first_message(run_updated)}"
        if run_updated.stdout != "42\n":
            return False, f"unexpected updated stdout {run_updated.stdout!r}"

        clean_build = run_command([sys.executable, str(SAFE_CLI), "build", "--clean", client.name], cwd=temp_root)
        if clean_build.returncode != 0:
            return False, f"clean build failed: {first_message(clean_build)}"
        if not (temp_root / ".safe-build" / "target-64" / "state.json").exists():
            return False, "clean build did not recreate project cache"

    return True, ""

def run_safe_prove_incremental_case() -> tuple[bool, str]:
    provider_text = """package provider_constant

   public subtype count is integer (0 to 10);
   public max_count : constant count = 4;
"""
    client_text = """with provider_constant;

package client_constant

   subtype index is integer (0 to provider_constant.max_count);
"""
    updated_provider_text = provider_text.replace("4", "5")

    with tempfile.TemporaryDirectory(prefix="safe-prove-incremental-") as temp_root_str:
        temp_root = Path(temp_root_str)
        provider = temp_root / "provider_constant.safe"
        client = temp_root / "client_constant.safe"
        provider.write_text(provider_text, encoding="utf-8")
        client.write_text(client_text, encoding="utf-8")

        prove = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove.returncode != 0:
            return False, f"initial prove failed: {first_message(prove)}"
        if "safe prove: PASS" not in prove.stdout:
            return False, f"missing PASS verdict in initial prove {prove.stdout!r}"

        summary_path = safe_prove_summary_path(client, target_bits=64)
        if not summary_path.exists():
            return False, f"missing proof summary {summary_path}"
        summary_mtime = summary_path.stat().st_mtime_ns

        prove_cached = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove_cached.returncode != 0:
            return False, f"cached prove failed: {first_message(prove_cached)}"
        if summary_path.stat().st_mtime_ns != summary_mtime:
            return False, "cached prove reran GNATprove"

        proof_root = temp_root / "obj" / "client_constant" / "prove-64"
        shutil.rmtree(proof_root)
        prove_missing_artifacts = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove_missing_artifacts.returncode != 0:
            return False, f"artifact-recovery prove failed: {first_message(prove_missing_artifacts)}"
        if not summary_path.exists():
            return False, "proof cache miss did not recreate GNATprove summary"
        recreated_summary_mtime = summary_path.stat().st_mtime_ns
        if recreated_summary_mtime == summary_mtime:
            return False, "missing proof artifacts did not rerun GNATprove"
        summary_mtime = recreated_summary_mtime

        provider.write_text(updated_provider_text, encoding="utf-8")
        prove_updated = run_command([sys.executable, str(SAFE_CLI), "prove", client.name], cwd=temp_root)
        if prove_updated.returncode != 0:
            return False, f"dependency-invalidated prove failed: {first_message(prove_updated)}"
        if summary_path.stat().st_mtime_ns == summary_mtime:
            return False, "dependency change did not rerun GNATprove"

    return True, ""


def run_target_bits_check_case(safec: Path) -> tuple[bool, str]:
    source_text = """subtype over is integer (0 to 2147483648);
"""

    with tempfile.TemporaryDirectory(prefix="safe-target-bits-check-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_check.safe"
        source.write_text(source_text, encoding="utf-8")

        check64 = run_command(
            [str(safec), "check", "--target-bits", "64", source.name],
            cwd=temp_root,
        )
        if check64.returncode != 0:
            return False, f"64-bit check failed: {first_message(check64)}"

        check32 = run_command(
            [str(safec), "check", "--target-bits", "32", source.name],
            cwd=temp_root,
        )
        if check32.returncode == 0:
            return False, "32-bit check unexpectedly succeeded"

    return True, ""

def run_safe_build_target_bits_case() -> tuple[bool, str]:
    source_text = """value : integer = 7;
print (value)
"""

    with tempfile.TemporaryDirectory(prefix="safe-build-target-bits-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_build.safe"
        source.write_text(source_text, encoding="utf-8")

        for bits in (32, 64):
            build = run_command(
                [sys.executable, str(SAFE_CLI), "build", "--target-bits", str(bits), source.name],
                cwd=temp_root,
            )
            if build.returncode != 0:
                return False, f"{bits}-bit build failed: {first_message(build)}"
            executable = safe_build_executable(source, target_bits=bits)
            if not executable.exists():
                return False, f"missing {bits}-bit executable {executable}"
            run = run_command([str(executable)], cwd=executable.parent)
            if run.returncode != 0:
                return False, f"{bits}-bit executable failed: {first_message(run)}"
            if run.stdout != "7\n":
                return False, f"unexpected {bits}-bit stdout {run.stdout!r}"
            state_path = temp_root / ".safe-build" / f"target-{bits}" / "state.json"
            if not state_path.exists():
                return False, f"missing {bits}-bit project cache state {state_path}"

    return True, ""


def run_safe_prove_target_bits_case() -> tuple[bool, str]:
    source_text = """package target_bits_prove

   subtype count is integer (0 to 2147483647);
   value : constant count = 2147483647;
"""

    with tempfile.TemporaryDirectory(prefix="safe-prove-target-bits-") as temp_root_str:
        temp_root = Path(temp_root_str)
        source = temp_root / "target_bits_prove.safe"
        source.write_text(source_text, encoding="utf-8")

        for bits in (32, 64):
            prove = run_command(
                [sys.executable, str(SAFE_CLI), "prove", "--target-bits", str(bits), source.name],
                cwd=temp_root,
            )
            if prove.returncode != 0:
                return False, f"{bits}-bit prove failed: {first_message(prove)}"
            summary_path = safe_prove_summary_path(source, target_bits=bits)
            if not summary_path.exists():
                return False, f"missing {bits}-bit proof summary {summary_path}"

        summary32 = safe_prove_summary_path(source, target_bits=32)
        mtime32 = summary32.stat().st_mtime_ns
        prove_cached = run_command(
            [sys.executable, str(SAFE_CLI), "prove", "--target-bits", "32", source.name],
            cwd=temp_root,
        )
        if prove_cached.returncode != 0:
            return False, f"cached 32-bit prove failed: {first_message(prove_cached)}"
        if summary32.stat().st_mtime_ns != mtime32:
            return False, "cached 32-bit prove reran GNATprove"

    return True, ""

def run_safe_cli_help_case(argv: list[str], expected_snippets: list[str]) -> tuple[bool, str]:
    completed = run_command([sys.executable, str(SAFE_CLI), *argv], cwd=REPO_ROOT)
    if completed.returncode != 0:
        return False, f"help command failed: {first_message(completed)}"
    text = completed.stdout + completed.stderr
    for snippet in expected_snippets:
        if snippet not in text:
            return False, f"missing help snippet {snippet!r}"
    return True, ""


def run_vscode_surface_docs_case() -> tuple[bool, str]:
    readme = VSCODE_README.read_text(encoding="utf-8")
    metadata = json.loads(VSCODE_PACKAGE_JSON.read_text(encoding="utf-8"))

    if "PR11.8c.1 compiler surface" in readme:
        return False, "VS Code README still advertises the stale PR11.8c.1 surface"
    if "syntax-only" not in readme:
        return False, "VS Code README no longer states the syntax-only boundary"
    if "post-v1.0 language server" not in readme:
        return False, "VS Code README no longer states the disposable-language-server boundary"
    if "PR11.8i" not in readme:
        return False, "VS Code README no longer names the current shipped milestone surface"

    description = str(metadata.get("description", ""))
    if "PR11.8c.1" in description:
        return False, "VS Code package.json description still advertises PR11.8c.1"
    if "PR11.8i" not in description:
        return False, "VS Code package.json description no longer names the current shipped surface"
    return True, ""


def run_safe_deploy_reject_case(argv: list[str], expected_message: str) -> tuple[bool, str]:
    completed = run_command([sys.executable, str(SAFE_CLI), *argv], cwd=REPO_ROOT)
    if completed.returncode == 0:
        return False, "safe deploy unexpectedly succeeded"
    output = completed.stderr or completed.stdout
    if expected_message not in output:
        return False, f"missing expected message {expected_message!r}"
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



def run_build_run_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []

    for source, expected_stdout, allow_timeout in BUILD_SUCCESS_CASES:
        passed += record_result(
            failures,
            f"safe build {repo_rel(source)}",
            run_safe_build_case(source, expected_stdout, allow_timeout=allow_timeout),
        )

    for source, expected_message in BUILD_REJECT_CASES:
        passed += record_result(
            failures,
            f"safe build {repo_rel(source)}",
            run_safe_build_reject_case(source, expected_message),
        )

    for source, expected_stdout, allow_timeout in RUN_SUCCESS_CASES:
        passed += record_result(
            failures,
            f"safe run {repo_rel(source)}",
            run_safe_run_case(source, expected_stdout, allow_timeout=allow_timeout),
        )

    for source, expected_message in RUN_REJECT_CASES:
        passed += record_result(
            failures,
            f"safe run {repo_rel(source)}",
            run_safe_run_reject_case(source, expected_message),
        )

    passed += record_result(failures, "safe run mutated iterable", run_safe_run_mutated_iterable_case())
    passed += record_result(failures, "safe build incremental", run_safe_build_incremental_case())
    return passed, 0, failures


def run_target_bits_check_section(safec: Path) -> RunCounts:
    failures: list[tuple[str, str]] = []
    passed = record_result(failures, "target-bits check", run_target_bits_check_case(safec))
    return passed, 0, failures


def run_post_interface_cli_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []

    passed += record_result(failures, "safe build target bits", run_safe_build_target_bits_case())

    for argv, expected in (
        (["--help"], ["safe build [--clean]", "--target-bits", "safe deploy", "safe run", "safe prove"]),
        (["deploy", "--help"], ["--board", "--simulate", "--watch-symbol", "--expect-value"]),
    ):
        passed += record_result(failures, f"safe cli help {' '.join(argv)}", run_safe_cli_help_case(argv, expected))

    passed += record_result(failures, "vscode surface docs", run_vscode_surface_docs_case())

    for argv, expected_message in DEPLOY_REJECT_ARGV_CASES:
        passed += record_result(
            failures,
            f"safe {' '.join(argv)}",
            run_safe_deploy_reject_case(argv, expected_message),
        )

    return passed, 0, failures


def run_prove_workflow_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    passed += record_result(failures, "safe prove incremental", run_safe_prove_incremental_case())
    passed += record_result(failures, "safe prove target bits", run_safe_prove_target_bits_case())
    return passed, 0, failures


def run_environment_repl_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []

    passed += record_result(failures, "ensure_sdkroot darwin normalization", run_ensure_sdkroot_case())

    for label, input_text, expected_stdout, expected_stderr_substring in REPL_CASES:
        passed += record_result(
            failures,
            label,
            run_repl_case(
                label=label,
                input_text=input_text,
                expected_stdout=expected_stdout,
                expected_stderr_substring=expected_stderr_substring,
            ),
        )

    return passed, 0, failures
