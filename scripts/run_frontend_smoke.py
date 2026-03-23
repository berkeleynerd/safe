#!/usr/bin/env python3
"""Build the frontend and run deterministic sequential smoke checks."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from _lib.gate_expectations import REPRESENTATIVE_EMIT_SAMPLES
from _lib.harness_common import (
    compiler_build_argv,
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    frontend_build_input_hash,
    normalize_text,
    require,
    require_repo_command,
    run,
    sha256_file,
    sha256_text,
    stable_emitted_artifact_sha256,
    stable_binary_sha256,
    write_report,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr00-pr04-frontend-smoke.json"
POSITIVE_AST = REPO_ROOT / "tests" / "positive" / "rule1_accumulate.safe"
CHECK_SAMPLE = REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe"
EMIT_SAMPLES = [REPO_ROOT / path for path in REPRESENTATIVE_EMIT_SAMPLES]
EQUALITY_CHECK = REPO_ROOT / "tests" / "positive" / "result_equality_check.safe"
LEGACY_TOKEN_FIXTURE = REPO_ROOT / "compiler_impl" / "tests" / "legacy_two_char_tokens.safe"
DIAGNOSTICS_EXIT = 1


def format_elapsed(seconds: float) -> str:
    return f"{seconds:.1f}s"


def log_progress(*, verbose: bool, message: str) -> None:
    if verbose:
        print(message)


def load_prior_report(*, report_path: Path) -> dict[str, Any] | None:
    candidate_paths: list[Path] = [report_path]
    if report_path != DEFAULT_REPORT:
        candidate_paths.append(DEFAULT_REPORT)
    for candidate in candidate_paths:
        if candidate.exists():
            return json.loads(candidate.read_text(encoding="utf-8"))
    return None


def repo_arg(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def find_subsequence(lexemes: list[str], expected: list[str]) -> int:
    limit = len(lexemes) - len(expected) + 1
    for start in range(max(limit, 0)):
        if lexemes[start : start + len(expected)] == expected:
            return start
    return -1


def assert_equality_tokens(result: dict[str, Any]) -> dict[str, Any]:
    payload = json.loads(result["stdout"])
    require(payload.get("format") == "tokens-v0", f"unexpected token format: {payload!r}")
    tokens = payload.get("tokens")
    require(isinstance(tokens, list), "token dump is missing tokens[]")
    lexemes = [token.get("lexeme") for token in tokens]
    require(all(isinstance(lexeme, str) for lexeme in lexemes), "token lexemes must be strings")

    sequences = [
        ["return", "S", "==", "0", ";"],
        ["return", "S", "!=", "0", ";"],
    ]
    for sequence in sequences:
        require(
            find_subsequence(lexemes, sequence) >= 0,
            f"missing token subsequence: {' '.join(sequence)}",
        )

    operator_counts = {
        "==": sum(
            1 for token in tokens if token.get("kind") == "symbol" and token.get("lexeme") == "=="
        ),
        "!=": sum(
            1 for token in tokens if token.get("kind") == "symbol" and token.get("lexeme") == "!="
        ),
    }
    require(operator_counts["=="] == 1, f"expected exactly one == token, got {operator_counts['==']}")
    require(operator_counts["!="] == 1, f"expected exactly one != token, got {operator_counts['!=']}")

    adjacent_equals_pairs = sum(
        1 for left, right in zip(lexemes, lexemes[1:]) if left == "=" and right == "="
    )
    require(adjacent_equals_pairs == 0, "unexpected adjacent '=' '=' tokens in equality fixture")

    return {
        "format": payload["format"],
        "required_subsequences": sequences,
        "operator_counts": operator_counts,
        "adjacent_equals_pairs": adjacent_equals_pairs,
    }


def assert_legacy_token_diagnostics(result: dict[str, Any]) -> dict[str, Any]:
    require(result["stdout"] == "", "legacy token regression should not emit token JSON on failure")
    stderr = result["stderr"]
    require(
        stderr.count("error[SC1001]") == 3,
        f"expected exactly three SC1001 diagnostics, got {stderr.count('error[SC1001]')}",
    )

    expected = {
        ":=": "Use current Safe syntax (`=` for assignment).",
        "=>": "Use current Safe syntax (`=` for named associations/aggregates and `then` for select arms).",
        "/=": "Use current Safe syntax (`!=` for inequality).",
    }
    for token, suggestion in expected.items():
        require(
            f'legacy token "{token}" is not allowed' in stderr,
            f"missing legacy-token diagnostic for {token}",
        )
        require(suggestion in stderr, f"missing suggestion text for {token}")

    return {
        "sc1001_count": 3,
        "legacy_tokens": list(expected.keys()),
        "suggestions": expected,
    }


def clean_frontend_build_outputs(safec: Path) -> None:
    shutil.rmtree(COMPILER_ROOT / "obj", ignore_errors=True)
    if safec.exists():
        safec.unlink()
    safec.parent.mkdir(parents=True, exist_ok=True)
    (COMPILER_ROOT / "alire" / "tmp").mkdir(parents=True, exist_ok=True)


def build_frontend(alr: str, env: dict[str, str]) -> dict[str, Any]:
    return run(compiler_build_argv(alr), cwd=COMPILER_ROOT, env=env)


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        f"out/{stem}.ast.json": root / "out" / f"{stem}.ast.json",
        f"out/{stem}.typed.json": root / "out" / f"{stem}.typed.json",
        f"out/{stem}.mir.json": root / "out" / f"{stem}.mir.json",
        f"iface/{stem}.safei.json": root / "iface" / f"{stem}.safei.json",
    }


def compute_build_input_hash(*, alr: str) -> str:
    return frontend_build_input_hash(alr=alr)


def resolve_build(
    *,
    alr: str,
    safec: Path,
    prior_report: dict[str, Any] | None,
    build_cache: dict[str, Any] | None,
    env: dict[str, str],
    verbose: bool = False,
) -> dict[str, Any]:
    hash_check_started = time.monotonic()
    current_build_input_hash = compute_build_input_hash(alr=alr)
    current_binary_sha256: str | None = None

    if safec.exists():
        current_binary_sha256 = stable_binary_sha256(safec)

    if safec.exists() and build_cache is not None:
        cached_build = build_cache.get("build")
        cached_binary_sha256 = build_cache.get("binary_sha256")
        if (
            isinstance(cached_build, dict)
            and cached_build.get("build_input_hash") == current_build_input_hash
            and isinstance(cached_binary_sha256, str)
            and current_binary_sha256 == cached_binary_sha256
        ):
            log_progress(
                verbose=verbose,
                message=(
                    "[frontend_smoke] build inputs unchanged, skipping clean rebuild "
                    f"({format_elapsed(time.monotonic() - hash_check_started)} hash check)"
                ),
            )
            return cached_build

    if safec.exists() and prior_report is not None:
        prior_build = prior_report.get("build")
        if (
            isinstance(prior_build, dict)
            and prior_build.get("build_input_hash") == current_build_input_hash
            and prior_build.get("binary_deterministic") is True
        ):
            validation_started = time.monotonic()
            clean_frontend_build_outputs(safec)
            validation_build = build_frontend(alr, env)
            require_repo_command(safec, "safec")
            rebuilt_binary_sha256 = stable_binary_sha256(safec)
            if current_binary_sha256 == rebuilt_binary_sha256:
                if build_cache is not None:
                    build_cache["build"] = prior_build
                    build_cache["binary_sha256"] = rebuilt_binary_sha256
                log_progress(
                    verbose=verbose,
                    message=(
                        "[frontend_smoke] build inputs unchanged, validated cached build "
                        f"({format_elapsed(time.monotonic() - validation_started)} rebuild, "
                        f"{format_elapsed(time.monotonic() - hash_check_started)} total)"
                    ),
                )
                return prior_build

            first_build = validation_build
            first_binary_sha256 = rebuilt_binary_sha256
            clean_frontend_build_outputs(safec)
            second_build = build_frontend(alr, env)
            require_repo_command(safec, "safec")
            second_binary_sha256 = stable_binary_sha256(safec)
            require(
                first_binary_sha256 == second_binary_sha256,
                "frontend build is non-deterministic: normalized compiler payload drifted across clean rebuilds",
            )
            build = {
                "command": first_build["command"],
                "cwd": first_build["cwd"],
                "returncodes": [first_build["returncode"], second_build["returncode"]],
                "binary_path": display_path(safec, repo_root=REPO_ROOT),
                "binary_deterministic": True,
                "build_input_hash": current_build_input_hash,
            }
            if build_cache is not None:
                build_cache["build"] = build
                build_cache["binary_sha256"] = second_binary_sha256
            log_progress(
                verbose=verbose,
                message=(
                    "[frontend_smoke] cached build drifted, reran clean rebuild proof "
                    f"({format_elapsed(time.monotonic() - validation_started)} total)"
                ),
            )
            return build

    rebuild_started = time.monotonic()
    clean_frontend_build_outputs(safec)
    first_build = build_frontend(alr, env)
    require_repo_command(safec, "safec")
    first_binary_sha256 = stable_binary_sha256(safec)
    clean_frontend_build_outputs(safec)
    second_build = build_frontend(alr, env)
    require_repo_command(safec, "safec")
    second_binary_sha256 = stable_binary_sha256(safec)
    require(
        first_binary_sha256 == second_binary_sha256,
        "frontend build is non-deterministic: normalized compiler payload drifted across clean rebuilds",
    )
    build = {
        "command": first_build["command"],
        "cwd": first_build["cwd"],
        "returncodes": [first_build["returncode"], second_build["returncode"]],
        "binary_path": display_path(safec, repo_root=REPO_ROOT),
        "binary_deterministic": True,
        "build_input_hash": current_build_input_hash,
    }
    if build_cache is not None:
        build_cache["build"] = build
        build_cache["binary_sha256"] = second_binary_sha256
    log_progress(
        verbose=verbose,
        message=f"[frontend_smoke] full clean rebuild proof ({format_elapsed(time.monotonic() - rebuild_started)})",
    )
    return build


def generate_report(
    *,
    alr: str,
    python: str,
    safec: Path,
    env: dict[str, str],
    prior_report: dict[str, Any] | None = None,
    build_cache: dict[str, Any] | None = None,
    verbose: bool = False,
) -> dict[str, Any]:
    build = resolve_build(
        alr=alr,
        safec=safec,
        prior_report=prior_report,
        build_cache=build_cache,
        env=env,
        verbose=verbose,
    )
    require_repo_command(safec, "safec")

    with tempfile.TemporaryDirectory(prefix="safec-smoke-") as temp_root_str:
        temp_root = Path(temp_root_str)
        ast_path = temp_root / "rule1_accumulate.ast.json"
        ast_run = run(
            [str(safec), "ast", repo_arg(POSITIVE_AST)],
            cwd=REPO_ROOT,
            env=env,
            stdout_path=ast_path,
            temp_root=temp_root,
        )
        ast_validate = run(
            [python, str(REPO_ROOT / "scripts" / "validate_ast_output.py"), str(ast_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        equality_lex_run = run(
            [str(safec), "lex", repo_arg(EQUALITY_CHECK)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        equality_assertions = assert_equality_tokens(equality_lex_run)

        legacy_lex_run = run(
            [str(safec), "lex", repo_arg(LEGACY_TOKEN_FIXTURE)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
            expected_returncode=DIAGNOSTICS_EXIT,
        )
        legacy_assertions = assert_legacy_token_diagnostics(legacy_lex_run)

        check_accumulate = run(
            [str(safec), "check", repo_arg(POSITIVE_AST)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        check_sequential = run(
            [str(safec), "check", repo_arg(CHECK_SAMPLE)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )

        deterministic_outputs: dict[str, dict[str, str]] = {}
        for sample in EMIT_SAMPLES:
            emit_a_root = temp_root / f"{sample.stem}-emit-a"
            emit_b_root = temp_root / f"{sample.stem}-emit-b"
            for root in (emit_a_root, emit_b_root):
                run(
                    [
                        str(safec),
                        "emit",
                        repo_arg(sample),
                        "--out-dir",
                        str(root / "out"),
                        "--interface-dir",
                        str(root / "iface"),
                    ],
                    cwd=REPO_ROOT,
                    env=env,
                    temp_root=temp_root,
                )

            expected_files = emitted_paths(emit_a_root, sample)
            observed_files = {
                str(path.relative_to(emit_a_root))
                for path in emit_a_root.rglob("*")
                if path.is_file()
            }
            if observed_files != set(expected_files):
                raise RuntimeError(
                    f"unexpected emitted files for {sample.name}: "
                    f"expected {sorted(expected_files)}, got {sorted(observed_files)}"
                )

            file_hashes: dict[str, str] = {}
            for relative, left in sorted(expected_files.items()):
                right = emit_b_root / relative
                left_bytes = left.read_bytes()
                right_bytes = right.read_bytes()
                if left_bytes != right_bytes:
                    raise RuntimeError(f"non-deterministic output for {sample.name}::{relative}")
                file_hashes[relative] = stable_emitted_artifact_sha256(left, temp_root=temp_root)
            deterministic_outputs[str(sample.relative_to(REPO_ROOT))] = file_hashes

        return {
            "build": build,
            "lex_equality": {
                **equality_lex_run,
                "assertions": equality_assertions,
            },
            "legacy_token_regression": {
                **legacy_lex_run,
                "assertions": legacy_assertions,
            },
            "ast": ast_run,
            "ast_validation": ast_validate,
            "check_runs": [check_accumulate, check_sequential],
            "deterministic_outputs": deterministic_outputs,
            "samples": {
                "ast": str(POSITIVE_AST.relative_to(REPO_ROOT)),
                "check": str(CHECK_SAMPLE.relative_to(REPO_ROOT)),
                "emit": [str(sample.relative_to(REPO_ROOT)) for sample in EMIT_SAMPLES],
                "equality_lex": str(EQUALITY_CHECK.relative_to(REPO_ROOT)),
                "legacy_lex": str(LEGACY_TOKEN_FIXTURE.relative_to(REPO_ROOT)),
            },
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--verbose", action="store_true", help="emit cache/rebuild timing logs")
    args = parser.parse_args()

    alr = find_command("alr", Path.home() / "bin" / "alr")
    python = find_command("python3")

    env = ensure_sdkroot(os.environ.copy())

    safec = COMPILER_ROOT / "bin" / "safec"
    prior_report = load_prior_report(report_path=args.report)
    build_cache: dict[str, Any] = {}
    report = finalize_deterministic_report(
        lambda: generate_report(
            alr=alr,
            python=python,
            safec=safec,
            env=env,
            prior_report=prior_report,
            build_cache=build_cache,
            verbose=args.verbose,
        ),
        label="PR00-PR04 frontend smoke",
    )

    write_report(args.report, report)
    print(f"frontend smoke: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"frontend smoke: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
