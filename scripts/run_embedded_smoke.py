#!/usr/bin/env python3
"""Run the local Renode-based embedded smoke lane."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path

from _lib.embedded_eval import (
    BoardConfig,
    DEFAULT_TIMEOUT_SECONDS,
    REPO_ROOT,
    build_compiler,
    build_embedded_image,
    detect_arm_triplet,
    emit_source,
    ensure_board_assets,
    ensure_work_dirs,
    require_embedded_commands,
    resolve_board,
    result_channel_driver_text,
    result_driver_text,
    run_under_renode,
    startup_driver_text,
    temporary_root,
    verify_runtime_available,
    work_paths,
    write_support_files,
)
from _lib.pr111_language_eval import emitted_primary_unit


EMBEDDED_TESTS_ROOT = REPO_ROOT / "tests" / "embedded"


@dataclass(frozen=True)
class EmbeddedCase:
    name: str
    source: Path
    expected_result: int
    driver_mode: str = "result"


CASES = {
    "entry_integer_result": EmbeddedCase(
        name="entry_integer_result",
        source=EMBEDDED_TESTS_ROOT / "entry_integer_result.safe",
        expected_result=42,
    ),
    "package_integer_result": EmbeddedCase(
        name="package_integer_result",
        source=EMBEDDED_TESTS_ROOT / "package_integer_result.safe",
        expected_result=42,
    ),
    "binary_shift_result": EmbeddedCase(
        name="binary_shift_result",
        source=EMBEDDED_TESTS_ROOT / "binary_shift_result.safe",
        expected_result=32,
    ),
    "scoped_receive_result": EmbeddedCase(
        name="scoped_receive_result",
        source=EMBEDDED_TESTS_ROOT / "scoped_receive_result.safe",
        expected_result=4,
        driver_mode="channel",
    ),
    "producer_consumer_result": EmbeddedCase(
        name="producer_consumer_result",
        source=EMBEDDED_TESTS_ROOT / "producer_consumer_result.safe",
        expected_result=42,
        driver_mode="channel",
    ),
    "delay_scope_result": EmbeddedCase(
        name="delay_scope_result",
        source=EMBEDDED_TESTS_ROOT / "delay_scope_result.safe",
        expected_result=2,
        driver_mode="channel",
    ),
    "select_priority_result": EmbeddedCase(
        name="select_priority_result",
        source=EMBEDDED_TESTS_ROOT / "select_priority_result.safe",
        expected_result=1,
        driver_mode="channel",
    ),
    "string_channel_result": EmbeddedCase(
        name="string_channel_result",
        source=EMBEDDED_TESTS_ROOT / "string_channel_result.safe",
        expected_result=3,
    ),
}


SUITES = {
    "all": sorted(CASES),
    "concurrency": [
        "delay_scope_result",
        "producer_consumer_result",
        "scoped_receive_result",
        "select_priority_result",
        "string_channel_result",
    ],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the local Renode-based embedded Safe smoke lane."
    )
    parser.add_argument(
        "--target",
        choices=("stm32f4",),
        default="stm32f4",
        help="Embedded target to exercise.",
    )
    parser.add_argument(
        "--case",
        action="append",
        choices=sorted(CASES),
        help="Limit the run to one or more named cases.",
    )
    parser.add_argument(
        "--suite",
        choices=sorted(SUITES),
        default="all",
        help="Run one named case suite (default: all).",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"Per-case timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS:g}).",
    )
    parser.add_argument(
        "--keep-temp",
        action="store_true",
        help="Preserve successful temp roots instead of deleting them.",
    )
    parser.add_argument(
        "--list-cases",
        action="store_true",
        help="Print the available embedded smoke cases and exit.",
    )
    parser.add_argument(
        "--list-suites",
        action="store_true",
        help="Print the available embedded smoke suites and exit.",
    )
    return parser.parse_args()


def suite_case_names(suite_name: str) -> list[str]:
    return SUITES[suite_name]


def selected_cases(names: list[str] | None, suite_name: str) -> list[EmbeddedCase]:
    if not names:
        return [CASES[name] for name in suite_case_names(suite_name)]
    return [CASES[name] for name in names]


def selected_boards(target_name: str) -> list[BoardConfig]:
    return [resolve_board("stm32f4-discovery", target_name)]


def preserve_or_cleanup(root: Path, *, keep_temp: bool, success: bool) -> Path | None:
    if keep_temp or not success:
        return root
    shutil.rmtree(root, ignore_errors=True)
    return None


def write_case_source(path: Path, contents: str) -> None:
    path.write_text(textwrap.dedent(contents).lstrip(), encoding="utf-8")


def driver_text_for_case(case: EmbeddedCase, unit_name: str) -> str:
    if case.driver_mode == "channel":
        return result_channel_driver_text(unit_name, case.expected_result)
    return result_driver_text(unit_name, case.expected_result)


def run_case(
    *,
    board: BoardConfig,
    safec: Path,
    gprbuild: str,
    renode: str,
    nm: str,
    triplet: str,
    case: EmbeddedCase,
    timeout_seconds: float,
    keep_temp: bool,
    env: dict[str, str],
) -> tuple[bool, str, Path | None]:
    root = temporary_root(f"{board.target}-{case.name}")
    paths = work_paths(root)
    ensure_work_dirs(paths)

    ok, detail = emit_source(safec=safec, source=case.source, paths=paths, env=env)
    if not ok:
        return False, detail, preserve_or_cleanup(root, keep_temp=keep_temp, success=False)

    unit_name = emitted_primary_unit(paths["ada"])
    write_support_files(
        paths=paths,
        driver_source=driver_text_for_case(case, unit_name),
        board=board,
    )

    ok, detail = build_embedded_image(
        gprbuild=gprbuild,
        triplet=triplet,
        runtime=board.runtime,
        paths=paths,
        env=env,
    )
    if not ok:
        return False, detail, preserve_or_cleanup(root, keep_temp=keep_temp, success=False)

    ok, detail = run_under_renode(
        renode=renode,
        nm=nm,
        paths=paths,
        timeout_seconds=timeout_seconds,
        env=env,
    )
    return ok, detail, preserve_or_cleanup(root, keep_temp=keep_temp, success=ok)


def write_jorvik_probe_source(path: Path) -> None:
    write_case_source(
        path,
        """
        package embedded_jorvik_probe

           task worker with priority = 10
              loop
                 delay 0.05
        """,
    )


def run_jorvik_probe(
    *,
    board: BoardConfig,
    safec: Path,
    gprbuild: str,
    renode: str,
    nm: str,
    triplet: str,
    timeout_seconds: float,
    keep_temp: bool,
    env: dict[str, str],
) -> tuple[bool, str, Path | None]:
    root = temporary_root(f"{board.target}-jorvik-probe")
    source = root / "embedded_jorvik_probe.safe"
    paths = work_paths(root)
    ensure_work_dirs(paths)
    write_jorvik_probe_source(source)

    ok, detail = emit_source(safec=safec, source=source, paths=paths, env=env)
    if not ok:
        return False, detail, preserve_or_cleanup(root, keep_temp=keep_temp, success=False)

    unit_name = emitted_primary_unit(paths["ada"])
    write_support_files(
        paths=paths,
        driver_source=startup_driver_text(unit_name),
        board=board,
    )

    ok, detail = build_embedded_image(
        gprbuild=gprbuild,
        triplet=triplet,
        runtime=board.runtime,
        paths=paths,
        env=env,
    )
    if not ok:
        return False, detail, preserve_or_cleanup(root, keep_temp=keep_temp, success=False)

    ok, detail = run_under_renode(
        renode=renode,
        nm=nm,
        paths=paths,
        timeout_seconds=timeout_seconds,
        env=env,
    )
    return ok, detail, preserve_or_cleanup(root, keep_temp=keep_temp, success=ok)


def print_case_list(*, suite_name: str) -> int:
    for name in suite_case_names(suite_name):
        print(name)
    return 0


def print_suite_list() -> int:
    for name in sorted(SUITES):
        print(name)
    return 0


def print_summary(*, target_name: str, passed: int, total: int) -> None:
    print(f"{target_name}: {passed} passed, {total - passed} failed")


def main() -> int:
    args = parse_args()
    if args.list_suites:
        return print_suite_list()
    if args.list_cases:
        return print_case_list(suite_name=args.suite)

    cases = selected_cases(args.case, args.suite)
    env = os.environ.copy()

    boards = selected_boards(args.target)
    board = boards[0]

    try:
        safec = build_compiler()
        triplet, _ = detect_arm_triplet()
        commands = require_embedded_commands(
            triplet=triplet,
            need_renode=True,
            need_openocd=False,
            need_readelf=False,
        )
        ensure_board_assets(board, need_renode=True, need_openocd=False)
        ok, detail = verify_runtime_available(
            gnatls=commands["gnatls"],
            triplet=triplet,
            runtime=board.runtime,
            env=env,
        )
        if not ok:
            raise RuntimeError(detail)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"run_embedded_smoke: ERROR: {exc}", file=sys.stderr)
        return 1

    probe_ok, probe_detail, probe_root = run_jorvik_probe(
        board=board,
        safec=safec,
        gprbuild=commands["gprbuild"],
        renode=commands["renode"],
        nm=commands["nm"],
        triplet=triplet,
        timeout_seconds=args.timeout,
        keep_temp=args.keep_temp,
        env=env,
    )
    if not probe_ok:
        print(
            f"{board.target}: 0/{len(cases)} cases passed "
            "(Jorvik runtime probe failed before running tests)"
        )
        suffix = f" (artifacts: {probe_root})" if probe_root is not None else ""
        print("Failures:")
        print(f" - {board.target}: Jorvik runtime probe failed: {probe_detail}{suffix}")
        return 1

    passed = 0
    failures: list[tuple[str, str, Path | None]] = []
    for case in cases:
        ok, detail, preserved = run_case(
            board=board,
            safec=safec,
            gprbuild=commands["gprbuild"],
            renode=commands["renode"],
            nm=commands["nm"],
            triplet=triplet,
            case=case,
            timeout_seconds=args.timeout,
            keep_temp=args.keep_temp,
            env=env,
        )
        if ok:
            passed += 1
        else:
            failures.append((f"{board.target}:{case.name}", detail, preserved))

    print_summary(target_name=board.target, passed=passed, total=len(cases))
    print(f"{passed} passed, {len(failures)} failed")
    if failures:
        print("Failures:")
        for label, detail, preserved in failures:
            suffix = f" (artifacts: {preserved})" if preserved is not None else ""
            print(f" - {label}: {detail}{suffix}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
