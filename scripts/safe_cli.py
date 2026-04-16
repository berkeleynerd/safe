#!/usr/bin/env python3
"""Repo-local prototype `safe` CLI for PR11.1."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

from _lib.embedded_eval import (
    DEFAULT_TIMEOUT_SECONDS,
    build_embedded_image,
    detect_arm_triplet,
    deploy_root,
    emit_source,
    ensure_board_assets,
    ensure_work_dirs,
    require_embedded_commands,
    resolve_board,
    reset_root,
    run_under_openocd,
    run_under_renode_observe,
    run_under_renode,
    startup_driver_text,
    verify_runtime_available,
    work_paths,
    write_support_files,
)
from _lib.harness_common import ensure_sdkroot, run_capture, run_passthrough, sha256_file
from _lib.project_cache import (
    ProjectEmitError,
    build_fingerprint,
    ensure_project_emitted,
    ensure_safe_build_root,
    project_cache_root,
    reset_project_cache,
    reset_cached_source_proof,
    reset_root_workdirs,
    save_project_state,
    source_key,
    write_safe_build_support_files,
)
from _lib.proof_eval import (
    prepare_proof_toolchain,
    prove_switches_for_level,
    run_cached_source_proof,
    summary_counts,
)
from _lib.proof_inventory import EXCLUDED_PROOF_PATHS
from _lib.pr111_language_eval import (
    COMPILER_ROOT,
    REPO_ROOT,
    emitted_primary_unit,
    ensure_safe_build_executable,
    repo_rel_or_abs,
    require_source_file,
    resolve_source_arg,
    safe_build_command,
    safec_path,
)


USAGE = """usage:
  safe build [--clean] [--clean-proofs] [--no-prove] [--verbose] [--level 1|2] [--target-bits 32|64] <file.safe>
  safe prove [--verbose] [--level 1|2] [--target-bits 32|64] [file.safe]
  safe deploy [--target stm32f4] --board stm32f4-discovery [--simulate] [--watch-symbol NAME --expect-value N] [--timeout SECONDS] <file.safe>
  safe run   [--no-prove] [--verbose] [--level 1|2] [--target-bits 32|64] <file.safe>
  safe check <safec check args...>
  safe emit  <safec emit args...>
"""


def print_usage(stream: object = sys.stderr) -> int:
    print(USAGE, file=stream, end="")
    return 2


def run_subprocess(argv: list[str], *, cwd: Path, env: dict[str, str]) -> int:
    return run_passthrough(argv, cwd=cwd, env=env)


def replay_completed_output(completed: object) -> None:
    stdout = getattr(completed, "stdout", "")
    stderr = getattr(completed, "stderr", "")
    if stdout:
        print(stdout, end="", file=sys.stdout)
    if stderr:
        print(stderr, end="", file=sys.stderr)


def run_quiet_stage(argv: list[str], *, cwd: Path, env: dict[str, str]) -> int:
    completed = run_capture(argv, cwd=cwd, env=env)
    if completed.returncode != 0:
        replay_completed_output(completed)
    return completed.returncode


def source_has_leading_with_clause(source: Path) -> bool:
    with source.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("--"):
                continue
            return bool(re.match(r"with\b", line))
    return False


def reject_multi_file_root(command: str) -> int:
    print(
        f"safe {command}: imported roots with leading `with` clauses are not supported for this command yet; "
        "use `safec emit` plus manual `gprbuild` for the current deploy flow",
        file=sys.stderr,
    )
    return 1


def add_target_bits_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--target-bits",
        type=int,
        choices=(32, 64),
        default=64,
        help="Target integer width for the compiler pipeline (default: 64).",
    )


def add_proof_level_argument(parser: argparse.ArgumentParser, *, default: int) -> None:
    parser.add_argument(
        "--level",
        type=int,
        choices=(1, 2),
        default=default,
        help=f"GNATprove proof level (default: {default}).",
    )


def add_verbose_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Replay captured failing-stage tool output after Safe diagnostics.",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="safe build",
        description="Build a Safe source into a native executable and, by default, prove the selected root.",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Clear the local build cache for this project before rebuilding.",
    )
    parser.add_argument(
        "--clean-proofs",
        action="store_true",
        help="Clear cached proof results for the selected root before proving.",
    )
    parser.add_argument(
        "--no-prove",
        action="store_true",
        help="Skip the post-build root proof step.",
    )
    add_verbose_argument(parser)
    add_proof_level_argument(parser, default=1)
    add_target_bits_argument(parser)
    parser.add_argument("source", help="Safe source to build.")
    return parser


def prove_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="safe prove",
        description="Run the emitted GNATprove audit for one or more Safe sources.",
    )
    add_verbose_argument(parser)
    add_proof_level_argument(parser, default=2)
    add_target_bits_argument(parser)
    parser.add_argument(
        "source",
        nargs="?",
        help="Safe source to prove. If omitted, prove all .safe files in the current directory.",
    )
    return parser


def run_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="safe run",
        description="Build, prove by default, and run a Safe source as a native executable.",
    )
    parser.add_argument(
        "--no-prove",
        action="store_true",
        help="Skip the post-build root proof step.",
    )
    add_verbose_argument(parser)
    add_proof_level_argument(parser, default=1)
    add_target_bits_argument(parser)
    parser.add_argument("source", help="Safe source to run.")
    return parser


def deploy_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="safe deploy",
        description="Build and deploy a single-file Safe program to STM32F4 Discovery.",
    )
    parser.add_argument(
        "--target",
        help="Optional target name. If omitted it is inferred from --board.",
    )
    parser.add_argument(
        "--board",
        required=True,
        choices=("stm32f4-discovery",),
        help="Board to simulate or flash.",
    )
    parser.add_argument(
        "--simulate",
        action="store_true",
        help="Run under Renode instead of flashing hardware.",
    )
    parser.add_argument(
        "--watch-symbol",
        help="ELF symbol name to observe under Renode after startup completes.",
    )
    parser.add_argument(
        "--expect-value",
        type=lambda text: int(text, 0),
        help="Expected scalar value for --watch-symbol (decimal or 0x-prefixed).",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"Startup timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS:g}).",
    )
    parser.add_argument("source", help="Single-file Safe source to deploy.")
    return parser


def pass_through(command: str, args: list[str]) -> int:
    env = ensure_sdkroot(os.environ.copy())
    safec = safec_path()
    return run_subprocess([str(safec), command, *args], cwd=Path.cwd(), env=env)


def parse_build_args(args: list[str]) -> argparse.Namespace | int:
    parser = build_parser()
    try:
        return parser.parse_args(args)
    except SystemExit as exc:
        return int(exc.code)


def parse_prove_args(args: list[str]) -> argparse.Namespace | int:
    parser = prove_parser()
    try:
        return parser.parse_args(args)
    except SystemExit as exc:
        return int(exc.code)


def parse_run_args(args: list[str]) -> argparse.Namespace | int:
    parser = run_parser()
    try:
        return parser.parse_args(args)
    except SystemExit as exc:
        return int(exc.code)


def proof_skip_reason(exc: Exception) -> str:
    text = str(exc)
    prefix = "required command not found: "
    if text.startswith(prefix):
        return f"{text.removeprefix(prefix)} not found"
    return text


def repo_relative_source(source: Path) -> str | None:
    try:
        return source.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return None


def source_uses_default_proof_gate(source: Path) -> bool:
    repo_relative = repo_relative_source(source)
    if repo_relative is None:
        return False
    return repo_relative not in EXCLUDED_PROOF_PATHS


def diagnostics_sidecar_path(source: Path) -> Path:
    return project_cache_root(source) / "diagnostics.json"


def clear_diagnostics_sidecar_path(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def clear_diagnostics_sidecar(source: Path) -> None:
    clear_diagnostics_sidecar_path(diagnostics_sidecar_path(source))


def write_diagnostics_sidecar_payload(path: Path, diagnostics: list[dict[str, object]]) -> None:
    if not diagnostics:
        clear_diagnostics_sidecar_path(path)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(diagnostics, indent=2) + "\n", encoding="utf-8")


def write_diagnostics_sidecar(result: object) -> None:
    source = getattr(result, "source", None)
    diagnostics = getattr(result, "diagnostics_json", [])
    if not isinstance(source, Path):
        return
    write_diagnostics_sidecar_payload(diagnostics_sidecar_path(source), diagnostics)


def stage_output_for_user(result: object) -> str:
    stage_output = getattr(result, "stage_output", {})
    stage = getattr(result, "stage", "")
    return stage_output.get(stage, "")


def print_captured_stage_output(captured: str) -> None:
    print(
        captured,
        end="" if captured.endswith("\n") else "\n",
        file=sys.stderr,
    )


def report_proof_failure(command_label: str, result: object, *, verbose: bool = False) -> None:
    write_diagnostics_sidecar(result)
    print(f"safe {command_label}: PROOF FAILED", file=sys.stderr)
    captured = stage_output_for_user(result)
    if captured:
        print_captured_stage_output(captured)
    else:
        detail = getattr(result, "detail", "")
        if detail:
            print(f"  {detail}", file=sys.stderr)
    if verbose:
        replay_failure_logs(result)


def build_source(
    source_arg: str,
    *,
    clean: bool,
    clean_proofs: bool,
    no_prove: bool,
    prove_level: int,
    target_bits: int,
    command_label: str,
    verbose: bool = False,
) -> tuple[dict[str, str], Path] | int:
    env = ensure_sdkroot(os.environ.copy())
    safec = safec_path()
    safec_hash = sha256_file(safec)
    source = require_source_file(resolve_source_arg(source_arg))
    clear_diagnostics_sidecar(source)

    if clean:
        reset_project_cache(source)
        reset_root_workdirs(source)

    try:
        shared_paths, state, sources = ensure_project_emitted(
            safec=safec,
            safec_hash=safec_hash,
            source=source,
            env=env,
            run_check=True,
            target_bits=target_bits,
        )
    except ProjectEmitError as exc:
        if exc.output:
            print(exc.output, end="" if exc.output.endswith("\n") else "\n", file=sys.stderr)
        else:
            print(f"safe {command_label}: {exc.detail}", file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(f"safe {command_label}: {exc}", file=sys.stderr)
        return 1

    paths = ensure_safe_build_root(source, target_bits=target_bits)
    main_text, project_text = write_safe_build_support_files(paths, ada_dir=shared_paths["ada"], source=source)
    fingerprint = build_fingerprint(
        source=source,
        sources=sources,
        state=state,
        safec_hash=safec_hash,
        main_text=main_text,
        project_text=project_text,
        shared_paths=shared_paths,
        target_bits=target_bits,
    )
    cached = state["builds"].get(source_key(source))
    executable: Path
    if cached and cached.get("fingerprint") == fingerprint and paths["exe"].exists():
        executable = ensure_safe_build_executable(paths)
    else:
        build_code = run_quiet_stage(safe_build_command(paths), cwd=COMPILER_ROOT, env=env)
        if build_code != 0:
            state["builds"].pop(source_key(source), None)
            save_project_state(shared_paths, state)
            return build_code

        executable = ensure_safe_build_executable(paths)
        state["builds"][source_key(source)] = {
            "fingerprint": fingerprint,
            "executable": str(executable),
        }
        save_project_state(shared_paths, state)

    if clean_proofs:
        reset_cached_source_proof(shared_paths, state, source, target_bits=target_bits)

    if not no_prove and source_uses_default_proof_gate(source):
        try:
            toolchain = prepare_proof_toolchain(env=env, build_frontend=False)
        except (FileNotFoundError, RuntimeError) as exc:
            print(f"safe {command_label}: proof skipped ({proof_skip_reason(exc)})", file=sys.stderr)
        else:
            result = run_cached_source_proof(
                toolchain=toolchain,
                source=source,
                run_check=False,
                prove_switches=prove_switches_for_level(prove_level),
                target_bits=target_bits,
            )
            if not result.passed:
                report_proof_failure(command_label, result, verbose=verbose)
                return 1
    return env, executable


def safe_build(args: argparse.Namespace) -> int:
    built = build_source(
        args.source,
        clean=args.clean,
        clean_proofs=args.clean_proofs,
        no_prove=args.no_prove,
        prove_level=args.level,
        target_bits=args.target_bits,
        command_label="build",
        verbose=args.verbose,
    )
    if isinstance(built, int):
        return built
    _, executable = built
    print(f"safe build: OK ({repo_rel_or_abs(executable)})")
    return 0


def safe_run(args: argparse.Namespace) -> int:
    built = build_source(
        args.source,
        clean=False,
        clean_proofs=False,
        no_prove=args.no_prove,
        prove_level=args.level,
        target_bits=args.target_bits,
        command_label="run",
        verbose=args.verbose,
    )
    if isinstance(built, int):
        return built
    env, executable = built
    return run_subprocess([str(executable)], cwd=executable.parent, env=env)


def display_source_for_user(source: Path, *, cwd: Path) -> str:
    try:
        return str(source.relative_to(cwd))
    except ValueError:
        return repo_rel_or_abs(source)


def format_pass_summary(result: object) -> str:
    flow = summary_counts(getattr(result, "flow_summary", None))
    prove = summary_counts(getattr(result, "prove_summary", None))
    return (
        f"flow total={flow['total']} justified={flow['justified']} unproved={flow['unproved']}; "
        f"prove total={prove['total']} justified={prove['justified']} unproved={prove['unproved']}"
    )


def replay_failure_logs(result: object) -> None:
    stage = getattr(result, "stage", "")
    raw_stage_output = getattr(result, "raw_stage_output", {})
    stage_output = getattr(result, "stage_output", {})
    captured = raw_stage_output.get(stage, "")
    if not captured:
        captured = stage_output.get(stage, "")
    if not captured:
        return
    print(f"--- {stage} output ---", file=sys.stderr)
    print(captured, end="" if captured.endswith("\n") else "\n", file=sys.stderr)


def selected_prove_sources(source_arg: str | None, *, cwd: Path) -> list[Path]:
    if source_arg is not None:
        return [require_source_file(resolve_source_arg(source_arg, cwd=cwd))]
    candidates = sorted(path.resolve() for path in cwd.glob("*.safe") if path.is_file())
    return candidates


def safe_prove(args: argparse.Namespace) -> int:
    cwd = Path.cwd().resolve()
    sources = selected_prove_sources(args.source, cwd=cwd)
    if not sources:
        print("safe prove: no .safe files found in the current directory", file=sys.stderr)
        return 1

    env = ensure_sdkroot(os.environ.copy())
    try:
        toolchain = prepare_proof_toolchain(env=env, build_frontend=False)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"safe prove: {exc}", file=sys.stderr)
        return 1

    diagnostics_by_sidecar: dict[Path, list[dict[str, object]]] = {}
    for sidecar_path in {diagnostics_sidecar_path(source) for source in sources}:
        clear_diagnostics_sidecar_path(sidecar_path)

    passed = 0
    failed = 0
    for source in sources:
        result = run_cached_source_proof(
            toolchain=toolchain,
            source=source,
            run_check=True,
            prove_switches=prove_switches_for_level(args.level),
            target_bits=args.target_bits,
        )
        label = display_source_for_user(source, cwd=cwd)
        if result.passed:
            passed += 1
            print(f"PASS {label} ({format_pass_summary(result)})")
            continue
        failed += 1
        print(f"FAIL {label} [{result.stage}] {result.detail}")
        if result.stage in {"flow", "prove"}:
            diagnostics = getattr(result, "diagnostics_json", [])
            if diagnostics:
                diagnostics_by_sidecar.setdefault(
                    diagnostics_sidecar_path(source),
                    [],
                ).extend(diagnostics)
            captured = stage_output_for_user(result)
            if captured:
                print_captured_stage_output(captured)
        if args.verbose:
            replay_failure_logs(result)

    for sidecar_path, diagnostics in diagnostics_by_sidecar.items():
        write_diagnostics_sidecar_payload(sidecar_path, diagnostics)

    print(f"{passed} passed, {failed} failed")
    verdict = "PASS" if failed == 0 else "FAIL"
    print(f"safe prove: {verdict}")
    return 0 if failed == 0 else 1


def parse_deploy_args(args: list[str]) -> argparse.Namespace | int:
    parser = deploy_parser()
    try:
        return parser.parse_args(args)
    except SystemExit as exc:
        return int(exc.code)


def safe_deploy(args: argparse.Namespace) -> int:
    env = ensure_sdkroot(os.environ.copy())
    source = require_source_file(resolve_source_arg(args.source))
    if source_has_leading_with_clause(source):
        return reject_multi_file_root("deploy")

    if (args.watch_symbol is None) != (args.expect_value is None):
        print(
            "safe deploy: --watch-symbol and --expect-value must be provided together",
            file=sys.stderr,
        )
        return 1
    if args.watch_symbol is not None and not args.simulate:
        print(
            "safe deploy: --watch-symbol is currently supported only with --simulate",
            file=sys.stderr,
        )
        return 1

    try:
        board = resolve_board(args.board, args.target)
        triplet, _ = detect_arm_triplet()
        commands = require_embedded_commands(
            triplet=triplet,
            need_renode=args.simulate,
            need_openocd=not args.simulate,
            need_readelf=(not args.simulate) or (args.watch_symbol is not None),
        )
        ensure_board_assets(board, need_renode=args.simulate, need_openocd=not args.simulate)
        ok, detail = verify_runtime_available(
            gnatls=commands["gnatls"],
            triplet=triplet,
            runtime=board.runtime,
            env=env,
        )
        if not ok:
            raise RuntimeError(detail)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"safe deploy: {exc}", file=sys.stderr)
        return 1

    root = deploy_root(source, board.name)
    paths = work_paths(root)
    reset_root(root)
    ensure_work_dirs(paths)

    safec = safec_path()
    ok, detail = emit_source(safec=safec, source=source, paths=paths, env=env)
    if not ok:
        print(f"safe deploy: {detail} (artifacts: {repo_rel_or_abs(root)})", file=sys.stderr)
        return 1

    unit_name = emitted_primary_unit(paths["ada"])
    write_support_files(
        paths=paths,
        driver_source=startup_driver_text(unit_name),
        board=board if args.simulate else None,
    )
    ok, detail = build_embedded_image(
        gprbuild=commands["gprbuild"],
        triplet=triplet,
        runtime=board.runtime,
        paths=paths,
        env=env,
    )
    if not ok:
        print(f"safe deploy: {detail} (artifacts: {repo_rel_or_abs(root)})", file=sys.stderr)
        return 1

    if args.simulate:
        if args.watch_symbol is not None:
            ok, detail = run_under_renode_observe(
                renode=commands["renode"],
                nm=commands["nm"],
                readelf=commands["readelf"],
                paths=paths,
                timeout_seconds=args.timeout,
                env=env,
                watch_symbol=args.watch_symbol,
                expect_value=args.expect_value,
            )
        else:
            ok, detail = run_under_renode(
                renode=commands["renode"],
                nm=commands["nm"],
                paths=paths,
                timeout_seconds=args.timeout,
                env=env,
            )
        if not ok:
            print(f"safe deploy: {detail} (artifacts: {repo_rel_or_abs(root)})", file=sys.stderr)
            return 1
        print(f"safe deploy: OK (simulated on {board.name}; {repo_rel_or_abs(paths['exe'])})")
        return 0

    ok, detail = run_under_openocd(
        openocd=commands["openocd"],
        nm=commands["nm"],
        readelf=commands["readelf"],
        paths=paths,
        board=board,
        timeout_seconds=args.timeout,
        env=env,
    )
    if not ok:
        print(f"safe deploy: {detail} (artifacts: {repo_rel_or_abs(paths['exe'])})", file=sys.stderr)
        return 1
    print(f"safe deploy: OK (flashed {board.name}; {repo_rel_or_abs(paths['exe'])})")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        return print_usage(sys.stderr)
    if args[0] in {"-h", "--help"}:
        print(USAGE, file=sys.stdout, end="")
        return 0

    command = args[0]
    if command == "build":
        parsed = parse_build_args(args[1:])
        if isinstance(parsed, int):
            return parsed
        return safe_build(parsed)
    if command == "prove":
        parsed = parse_prove_args(args[1:])
        if isinstance(parsed, int):
            return parsed
        return safe_prove(parsed)
    if command == "deploy":
        parsed = parse_deploy_args(args[1:])
        if isinstance(parsed, int):
            return parsed
        return safe_deploy(parsed)
    if command == "run":
        parsed = parse_run_args(args[1:])
        if isinstance(parsed, int):
            return parsed
        return safe_run(parsed)
    if command in {"check", "emit"}:
        if len(args) < 2:
            return print_usage()
        return pass_through(command, args[1:])
    return print_usage()


if __name__ == "__main__":
    raise SystemExit(main())
