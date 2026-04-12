"""Embedded smoke listing checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import sys

from _lib.embedded_eval import parse_monitor_value
from _lib.test_harness import EMBEDDED_SMOKE, REPO_ROOT, RunCounts, first_message, record_result, run_command

EMBEDDED_SMOKE_CASES = [
    "binary_shift_result",
    "delay_scope_result",
    "entry_integer_result",
    "package_integer_result",
    "producer_consumer_result",
    "scoped_receive_result",
    "select_priority_result",
    "select_single_ready_result",
    "select_timeout_cursor_result",
    "string_channel_result",
]

EMBEDDED_SMOKE_CONCURRENCY_CASES = [
    "delay_scope_result",
    "producer_consumer_result",
    "scoped_receive_result",
    "select_priority_result",
    "select_single_ready_result",
    "select_timeout_cursor_result",
    "string_channel_result",
]

EMBEDDED_SMOKE_SUITES = [
    "all",
    "concurrency",
]

def run_embedded_case_listing(
    *,
    suite_name: str,
    expected_cases: list[str],
) -> tuple[bool, str]:
    completed = run_command(
        [sys.executable, str(EMBEDDED_SMOKE), "--list-cases", "--suite", suite_name],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        return False, f"embedded case listing failed for {suite_name}: {first_message(completed)}"
    expected = "".join(f"{name}\n" for name in expected_cases)
    if completed.stdout != expected:
        return False, f"unexpected embedded case list for {suite_name} {completed.stdout!r}"
    if completed.stderr:
        return False, f"unexpected embedded case stderr for {suite_name} {completed.stderr!r}"
    return True, ""


def run_embedded_suite_listing() -> tuple[bool, str]:
    completed = run_command(
        [sys.executable, str(EMBEDDED_SMOKE), "--list-suites"],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        return False, f"embedded suite listing failed: {first_message(completed)}"
    expected = "".join(f"{name}\n" for name in EMBEDDED_SMOKE_SUITES)
    if completed.stdout != expected:
        return False, f"unexpected embedded suite list {completed.stdout!r}"
    if completed.stderr:
        return False, f"unexpected embedded suite stderr {completed.stderr!r}"
    return True, ""


def run_embedded_monitor_parsing_checks() -> tuple[bool, str]:
    cases = [
        ("renode-hex", "0x00000001\n", 1),
        ("openocd-mdw", "0x20000000: 00000001 \n", 1),
        ("openocd-mdw-hex", "0x20000000: 0x00000002\n", 2),
    ]
    for label, text, expected in cases:
        actual = parse_monitor_value(text)
        if actual != expected:
            return False, f"{label} parsed as {actual}, expected {expected}"
    return True, ""



def run_embedded_checks() -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []
    passed += record_result(failures, "embedded smoke suite listing", run_embedded_suite_listing())
    passed += record_result(
        failures,
        "embedded smoke case listing",
        run_embedded_case_listing(suite_name="all", expected_cases=EMBEDDED_SMOKE_CASES),
    )
    passed += record_result(
        failures,
        "embedded smoke concurrency listing",
        run_embedded_case_listing(
            suite_name="concurrency",
            expected_cases=EMBEDDED_SMOKE_CONCURRENCY_CASES,
        ),
    )
    passed += record_result(failures, "embedded monitor parsing", run_embedded_monitor_parsing_checks())
    return passed, 0, failures
