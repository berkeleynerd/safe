#!/usr/bin/env python3
"""Run the PR06.9.3 runtime-boundary enforcement gate."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from validate_execution_state import runtime_boundary_report


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr0693-runtime-boundary-report.json"

LEX_SUCCESS = REPO_ROOT / "tests" / "positive" / "result_equality_check.safe"
LEX_FAILURE = REPO_ROOT / "compiler_impl" / "tests" / "legacy_two_char_tokens.safe"
AST_SUCCESS = REPO_ROOT / "tests" / "positive" / "rule1_accumulate.safe"
CHECK_SUCCESS = REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe"
CHECK_FAILURE = REPO_ROOT / "tests" / "negative" / "neg_rule4_moved.safe"
EMIT_SUCCESS = REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe"
EMIT_FAILURE = REPO_ROOT / "tests" / "negative" / "neg_rule1_overflow.safe"
INVALID_MIR = COMPILER_ROOT / "tests" / "mir_validation" / "invalid_scope_id.json"
VALID_MIR_V1 = COMPILER_ROOT / "tests" / "mir_validation" / "valid_mir_v1.json"
DIVISION_BY_ZERO_MIR = COMPILER_ROOT / "tests" / "mir_analysis" / "pr05_division_by_zero.json"
AST_VALIDATOR = REPO_ROOT / "scripts" / "validate_ast_output.py"


def normalize_text(text: str, *, temp_root: Path | None = None) -> str:
    result = text
    if temp_root is not None:
        result = result.replace(str(temp_root), "$TMPDIR")
    return result.replace(str(REPO_ROOT), "$REPO_ROOT")


def normalize_argv(argv: list[str], *, temp_root: Path | None = None) -> list[str]:
    normalized: list[str] = []
    for item in argv:
        candidate = Path(item)
        if candidate.is_absolute():
            if temp_root is not None and temp_root in candidate.parents:
                normalized.append("$TMPDIR/" + str(candidate.relative_to(temp_root)))
            elif REPO_ROOT in candidate.parents:
                normalized.append(str(candidate.relative_to(REPO_ROOT)))
            else:
                normalized.append(candidate.name)
        else:
            normalized.append(item)
    return normalized


def find_command(name: str, fallback: Path | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def require_repo_command(path: Path, name: str) -> Path:
    if path.exists():
        return path
    raise FileNotFoundError(f"required repo-local command not found: {name} ({path})")


def run(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    stdout_path: Path | None = None,
    temp_root: Path | None = None,
    expected_returncode: int = 0,
) -> dict[str, Any]:
    if stdout_path is not None:
        stdout_path.parent.mkdir(parents=True, exist_ok=True)
        with stdout_path.open("w", encoding="utf-8") as handle:
            completed = subprocess.run(
                argv,
                cwd=cwd,
                env=env,
                text=True,
                stdout=handle,
                stderr=subprocess.PIPE,
                check=False,
            )
        stdout_text = stdout_path.read_text(encoding="utf-8")
    else:
        completed = subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        stdout_text = completed.stdout

    result = {
        "command": normalize_argv(argv, temp_root=temp_root),
        "cwd": normalize_text(str(cwd), temp_root=temp_root),
        "returncode": completed.returncode,
        "stdout": normalize_text(stdout_text, temp_root=temp_root),
        "stderr": normalize_text(completed.stderr, temp_root=temp_root),
    }
    if completed.returncode != expected_returncode:
        raise RuntimeError(json.dumps(result, indent=2))
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def ensure_sdkroot(env: dict[str, str]) -> dict[str, str]:
    if sys.platform != "darwin" or env.get("SDKROOT"):
        return env
    candidate = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
    if candidate.exists():
        updated = env.copy()
        updated["SDKROOT"] = str(candidate)
        return updated
    return env


def tool_versions(python: str, alr: str) -> dict[str, str]:
    versions: dict[str, str] = {}
    versions["python3"] = (
        subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stdout.strip()
        or subprocess.run([python, "--version"], text=True, capture_output=True, check=False).stderr.strip()
    )
    versions["alr"] = subprocess.run([alr, "--version"], text=True, capture_output=True, check=False).stdout.strip()
    gprbuild = shutil.which("gprbuild")
    if gprbuild:
        banner = subprocess.run(
            [gprbuild, "--version"], text=True, capture_output=True, check=False
        ).stdout.splitlines()[0]
        versions["gprbuild"] = banner.split(" (", 1)[0]
    return versions


def make_masked_env(temp_root: Path) -> tuple[dict[str, str], dict[str, Path], Path]:
    stub_dir = temp_root / "python-mask"
    stub_dir.mkdir(parents=True, exist_ok=True)
    blocked_log = temp_root / "blocked-python.log"
    stub_paths: dict[str, Path] = {}
    for interpreter in ("python3", "python", "python3.11"):
        stub_path = stub_dir / interpreter
        stub_path.write_text(
            "\n".join(
                [
                    "#!/bin/sh",
                    f'echo "blocked {interpreter} spawn: $*" >> "$PR0693_BLOCKED_LOG"',
                    f'echo "{interpreter} masked for PR06.9.3 runtime-boundary gate" >&2',
                    "exit 97",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        stub_path.chmod(0o755)
        stub_paths[interpreter] = stub_path

    env = os.environ.copy()
    env["PATH"] = str(stub_dir) + os.pathsep + env.get("PATH", "")
    env["PR0693_BLOCKED_LOG"] = str(blocked_log)
    return env, stub_paths, blocked_log


def read_blocked_log(blocked_log: Path, *, temp_root: Path) -> list[str]:
    if not blocked_log.exists():
        return []
    return [
        normalize_text(line.rstrip(), temp_root=temp_root)
        for line in blocked_log.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def require_no_blocked_spawns(blocked_log: Path, *, temp_root: Path, label: str) -> list[str]:
    blocked = read_blocked_log(blocked_log, temp_root=temp_root)
    require(not blocked, f"{label}: unexpected python spawns: {blocked}")
    return blocked


def read_diag_json(stdout: str, source: str) -> dict[str, Any]:
    payload = json.loads(stdout)
    require(payload.get("format") == "diagnostics-v0", f"{source}: unexpected diagnostics format")
    require(isinstance(payload.get("diagnostics"), list), f"{source}: diagnostics must be a list")
    return payload


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_equality_tokens(result: dict[str, Any]) -> dict[str, Any]:
    payload = json.loads(result["stdout"])
    require(payload.get("format") == "tokens-v0", "lex success: expected tokens-v0 output")
    tokens = payload.get("tokens")
    require(isinstance(tokens, list), "lex success: missing tokens[]")
    lexemes = [token.get("lexeme") for token in tokens]
    require("==" in lexemes, "lex success: missing == token")
    require("!=" in lexemes, "lex success: missing != token")
    return {
        "format": payload["format"],
        "token_count": len(tokens),
        "operators_present": ["==", "!="],
    }


def assert_legacy_token_failure(result: dict[str, Any], *, label: str) -> dict[str, Any]:
    require(result["stdout"] == "", f"{label}: expected empty stdout")
    stderr = result["stderr"]
    require(stderr.count("error[SC1001]") == 3, f"{label}: expected three SC1001 diagnostics")
    for token in (":=", "=>", "/="):
        require(f'legacy token "{token}" is not allowed' in stderr, f"{label}: missing {token} diagnostic")
    return {
        "sc1001_count": 3,
        "legacy_tokens": [":=", "=>", "/="],
    }


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        f"out/{stem}.ast.json": root / "out" / f"{stem}.ast.json",
        f"out/{stem}.typed.json": root / "out" / f"{stem}.typed.json",
        f"out/{stem}.mir.json": root / "out" / f"{stem}.mir.json",
        f"iface/{stem}.safei.json": root / "iface" / f"{stem}.safei.json",
    }


def assert_no_files(root: Path) -> dict[str, Any]:
    if not root.exists():
        return {"exists": False, "files": []}
    files = sorted(str(path.relative_to(root)) for path in root.rglob("*") if path.is_file())
    require(not files, f"expected no emitted files under {root}, saw {files}")
    return {"exists": True, "files": files}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    args.report.parent.mkdir(parents=True, exist_ok=True)

    python = find_command("python3")
    alr = find_command("alr", Path.home() / "bin" / "alr")
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    validation_env = ensure_sdkroot(os.environ.copy())

    with tempfile.TemporaryDirectory(prefix="pr0693-runtime-") as temp_root_str:
        temp_root = Path(temp_root_str)
        masked_env, stub_paths, blocked_log = make_masked_env(temp_root)
        masked_env = ensure_sdkroot(masked_env)
        runtime_rule = runtime_boundary_report()
        require(
            not runtime_rule["legacy_backend_present"],
            "runtime boundary: legacy backend must remain absent",
        )
        require(
            not runtime_rule["violations"],
            f"runtime boundary: static violations present: {runtime_rule['violations']}",
        )

        lex_success = run(
            [str(safec), "lex", str(LEX_SUCCESS)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
        )
        lex_success_assertions = assert_equality_tokens(lex_success)
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="lex success")

        lex_failure = run(
            [str(safec), "lex", str(LEX_FAILURE)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        lex_failure_assertions = assert_legacy_token_failure(lex_failure, label="lex failure")
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="lex failure")

        ast_output = temp_root / "rule1_accumulate.ast.json"
        ast_success = run(
            [str(safec), "ast", str(AST_SUCCESS)],
            cwd=REPO_ROOT,
            env=masked_env,
            stdout_path=ast_output,
            temp_root=temp_root,
        )
        ast_validation = run(
            [python, str(AST_VALIDATOR), str(ast_output)],
            cwd=REPO_ROOT,
            env=validation_env,
            temp_root=temp_root,
        )
        ast_payload = load_json(ast_output)
        require(isinstance(ast_payload, dict), "ast success: expected JSON object")
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="ast success")

        ast_failure = run(
            [str(safec), "ast", str(LEX_FAILURE)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        ast_failure_assertions = assert_legacy_token_failure(ast_failure, label="ast failure")
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="ast failure")

        check_diag_success = run(
            [str(safec), "check", "--diag-json", str(CHECK_SUCCESS)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
        )
        check_diag_success_payload = read_diag_json(check_diag_success["stdout"], str(CHECK_SUCCESS))
        require(
            check_diag_success_payload["diagnostics"] == [],
            "check --diag-json success: expected zero diagnostics",
        )
        require_no_blocked_spawns(
            blocked_log, temp_root=temp_root, label="check --diag-json success"
        )

        check_plain_success = run(
            [str(safec), "check", str(CHECK_SUCCESS)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
        )
        require(check_plain_success["stdout"] == "", "check success: expected empty stdout")
        require(check_plain_success["stderr"] == "", "check success: expected empty stderr")
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="check success")

        check_diag_failure = run(
            [str(safec), "check", "--diag-json", str(CHECK_FAILURE)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        check_diag_failure_payload = read_diag_json(check_diag_failure["stdout"], str(CHECK_FAILURE))
        require(
            check_diag_failure_payload["diagnostics"]
            and check_diag_failure_payload["diagnostics"][0]["reason"] == "use_after_move",
            "check --diag-json failure: expected use_after_move",
        )
        require_no_blocked_spawns(
            blocked_log, temp_root=temp_root, label="check --diag-json failure"
        )

        check_plain_failure = run(
            [str(safec), "check", str(CHECK_FAILURE)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        require(check_plain_failure["stdout"] == "", "check failure: expected empty stdout")
        require(
            "neg_rule4_moved.safe" in check_plain_failure["stderr"]
            and "dereference of moved access value" in check_plain_failure["stderr"],
            "check failure: expected moved-dereference diagnostic",
        )
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="check failure")

        emit_root = temp_root / "emit-success"
        emit_success = run(
            [
                str(safec),
                "emit",
                str(EMIT_SUCCESS),
                "--out-dir",
                str(emit_root / "out"),
                "--interface-dir",
                str(emit_root / "iface"),
            ],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
        )
        emit_files = emitted_paths(emit_root, EMIT_SUCCESS)
        observed_emit_files = sorted(
            str(path.relative_to(emit_root))
            for path in emit_root.rglob("*")
            if path.is_file()
        )
        require(
            observed_emit_files == sorted(emit_files),
            f"emit success: unexpected emitted files {observed_emit_files}",
        )
        emit_ast_validation = run(
            [python, str(AST_VALIDATOR), str(emit_files[f'out/{EMIT_SUCCESS.stem.lower()}.ast.json'])],
            cwd=REPO_ROOT,
            env=validation_env,
            temp_root=temp_root,
        )
        typed_payload = load_json(emit_files[f"out/{EMIT_SUCCESS.stem.lower()}.typed.json"])
        mir_payload = load_json(emit_files[f"out/{EMIT_SUCCESS.stem.lower()}.mir.json"])
        safei_payload = load_json(emit_files[f"iface/{EMIT_SUCCESS.stem.lower()}.safei.json"])
        require(typed_payload.get("format") == "typed-v2", "emit success: expected typed-v2")
        require(mir_payload.get("format") == "mir-v2", "emit success: expected mir-v2")
        require(safei_payload.get("format") == "safei-v0", "emit success: expected safei-v0")
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="emit success")

        negative_emit_root = temp_root / "emit-failure"
        emit_failure = run(
            [
                str(safec),
                "emit",
                str(EMIT_FAILURE),
                "--out-dir",
                str(negative_emit_root / "out"),
                "--interface-dir",
                str(negative_emit_root / "iface"),
            ],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        emit_failure_outputs = {
            "out": assert_no_files(negative_emit_root / "out"),
            "iface": assert_no_files(negative_emit_root / "iface"),
        }
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="emit failure")

        emitted_mir = emit_files[f"out/{EMIT_SUCCESS.stem.lower()}.mir.json"]

        validate_mir_success = run(
            [str(safec), "validate-mir", str(emitted_mir)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
        )
        require(
            validate_mir_success["stdout"].startswith("validate-mir: OK ("),
            "validate-mir success: expected OK banner",
        )
        require(validate_mir_success["stderr"] == "", "validate-mir success: expected empty stderr")
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="validate-mir success")

        validate_mir_failure = run(
            [str(safec), "validate-mir", str(INVALID_MIR)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        require(
            "unknown scope_id" in validate_mir_failure["stderr"],
            "validate-mir failure: expected unknown scope_id",
        )
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="validate-mir failure")

        analyze_diag_success = run(
            [str(safec), "analyze-mir", "--diag-json", str(emitted_mir)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
        )
        analyze_diag_success_payload = read_diag_json(analyze_diag_success["stdout"], str(emitted_mir))
        require(
            analyze_diag_success_payload["diagnostics"] == [],
            "analyze-mir --diag-json success: expected zero diagnostics",
        )
        require_no_blocked_spawns(
            blocked_log, temp_root=temp_root, label="analyze-mir --diag-json success"
        )

        analyze_diag_failure = run(
            [str(safec), "analyze-mir", "--diag-json", str(DIVISION_BY_ZERO_MIR)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        analyze_diag_failure_payload = read_diag_json(
            analyze_diag_failure["stdout"], str(DIVISION_BY_ZERO_MIR)
        )
        require(
            analyze_diag_failure_payload["diagnostics"]
            and analyze_diag_failure_payload["diagnostics"][0]["reason"] == "division_by_zero",
            "analyze-mir --diag-json failure: expected division_by_zero",
        )
        require_no_blocked_spawns(
            blocked_log, temp_root=temp_root, label="analyze-mir --diag-json failure"
        )

        analyze_plain_success = run(
            [str(safec), "analyze-mir", str(emitted_mir)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
        )
        require(
            analyze_plain_success["stdout"].startswith("analyze-mir: OK ("),
            "analyze-mir success: expected OK banner",
        )
        require(analyze_plain_success["stderr"] == "", "analyze-mir success: expected empty stderr")
        require_no_blocked_spawns(blocked_log, temp_root=temp_root, label="analyze-mir success")

        analyze_plain_failure = run(
            [str(safec), "analyze-mir", str(VALID_MIR_V1)],
            cwd=REPO_ROOT,
            env=masked_env,
            temp_root=temp_root,
            expected_returncode=1,
        )
        require(
            "analyze-mir requires mir-v2 input" in analyze_plain_failure["stderr"],
            "analyze-mir failure: expected mir-v2 rejection",
        )
        require(analyze_plain_failure["stdout"] == "", "analyze-mir failure: expected empty stdout")
        blocked_spawns = require_no_blocked_spawns(
            blocked_log, temp_root=temp_root, label="analyze-mir failure"
        )

        report = {
            "tool_versions": tool_versions(python, alr),
            "runtime_rule": runtime_rule,
            "python_mask": {
                "stub_paths": {
                    name: normalize_text(str(path), temp_root=temp_root)
                    for name, path in sorted(stub_paths.items())
                },
                "blocked_log": normalize_text(str(blocked_log), temp_root=temp_root),
                "blocked_spawns": blocked_spawns,
            },
            "commands": {
                "lex": {
                    "success": {"run": lex_success, "assertions": lex_success_assertions},
                    "failure": {"run": lex_failure, "assertions": lex_failure_assertions},
                },
                "ast": {
                    "success": {
                        "run": ast_success,
                        "validation": ast_validation,
                        "output_path": normalize_text(str(ast_output), temp_root=temp_root),
                    },
                    "failure": {"run": ast_failure, "assertions": ast_failure_assertions},
                },
                "check": {
                    "diag_json_success": {
                        "run": check_diag_success,
                        "diagnostics": check_diag_success_payload,
                    },
                    "plain_success": {"run": check_plain_success},
                    "diag_json_failure": {
                        "run": check_diag_failure,
                        "diagnostics": check_diag_failure_payload,
                    },
                    "plain_failure": {"run": check_plain_failure},
                },
                "emit": {
                    "success": {
                        "run": emit_success,
                        "ast_validation": emit_ast_validation,
                        "outputs": {
                            relative: normalize_text(str(path), temp_root=temp_root)
                            for relative, path in sorted(emit_files.items())
                        },
                        "formats": {
                            "typed": typed_payload["format"],
                            "mir": mir_payload["format"],
                            "safei": safei_payload["format"],
                        },
                    },
                    "failure": {
                        "run": emit_failure,
                        "outputs": emit_failure_outputs,
                    },
                },
                "validate_mir": {
                    "success": {"run": validate_mir_success},
                    "failure": {"run": validate_mir_failure},
                },
                "analyze_mir_diag_json": {
                    "success": {
                        "run": analyze_diag_success,
                        "diagnostics": analyze_diag_success_payload,
                    },
                    "failure": {
                        "run": analyze_diag_failure,
                        "diagnostics": analyze_diag_failure_payload,
                    },
                },
                "analyze_mir_plain": {
                    "success": {"run": analyze_plain_success},
                    "failure": {"run": analyze_plain_failure},
                },
            },
        }

    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"pr0693 runtime-boundary gate: OK ({args.report})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr0693 runtime-boundary gate: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
