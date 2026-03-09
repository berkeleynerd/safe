#!/usr/bin/env python3
"""Run PR06.5 Ada MIR validator fixtures and sample validation."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import display_path, find_command, require, run, tool_versions, write_report


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr065-ada-mir-validator-report.json"

VALID_FIXTURES = [
    COMPILER_ROOT / "tests" / "mir_validation" / "valid_mir_v1.json",
    COMPILER_ROOT / "tests" / "mir_validation" / "valid_mir_v2.json",
]

INVALID_FIXTURES = [
    COMPILER_ROOT / "tests" / "mir_validation" / "invalid_missing_terminator.json",
    COMPILER_ROOT / "tests" / "mir_validation" / "invalid_scope_id.json",
    COMPILER_ROOT / "tests" / "mir_validation" / "invalid_missing_declaration_init.json",
    COMPILER_ROOT / "tests" / "mir_validation" / "invalid_high_level_op.json",
    COMPILER_ROOT / "tests" / "mir_validation" / "invalid_block_numbering.json",
]

EMITTED_SAMPLES = [
    REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
    REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
    REPO_ROOT / "tests" / "positive" / "ownership_borrow.safe",
    REPO_ROOT / "tests" / "positive" / "ownership_return.safe",
]

HARNESSES = [
    REPO_ROOT / "scripts" / "run_pr05_d27_harness.py",
    REPO_ROOT / "scripts" / "run_pr06_ownership_harness.py",
]

LEGACY_VALIDATOR_NAME = "validate_mir_output.py"

LEGACY_REFERENCE_SCAN_PATHS = [
    REPO_ROOT / "README.md",
    REPO_ROOT / "compiler_impl" / "README.md",
    REPO_ROOT / "execution" / "tracker.json",
    REPO_ROOT / "execution" / "dashboard.md",
    REPO_ROOT / ".github" / "workflows" / "ci.yml",
    REPO_ROOT / "scripts" / "run_pr05_d27_harness.py",
    REPO_ROOT / "scripts" / "run_pr06_ownership_harness.py",
    REPO_ROOT / "scripts" / "run_frontend_smoke.py",
]
def validate_fixtures(safec: Path, env: dict[str, str]) -> dict[str, list[dict[str, Any]]]:
    valid_results: list[dict[str, Any]] = []
    invalid_results: list[dict[str, Any]] = []
    for fixture in VALID_FIXTURES:
        valid_results.append(
            {
                "fixture": str(fixture.relative_to(REPO_ROOT)),
                "result": run([str(safec), "validate-mir", str(fixture)], cwd=REPO_ROOT, env=env),
            }
        )
    for fixture in INVALID_FIXTURES:
        invalid_results.append(
            {
                "fixture": str(fixture.relative_to(REPO_ROOT)),
                "result": run(
                    [str(safec), "validate-mir", str(fixture)],
                    cwd=REPO_ROOT,
                    env=env,
                    expected_returncode=1,
                ),
            }
        )
    return {"valid": valid_results, "invalid": invalid_results}


def validate_emitted_samples(safec: Path, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for sample in EMITTED_SAMPLES:
        root = temp_root / sample.stem
        emit_result = run(
            [
                str(safec),
                "emit",
                str(sample),
                "--out-dir",
                str(root / "out"),
                "--interface-dir",
                str(root / "iface"),
            ],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        mir_path = root / "out" / f"{sample.stem.lower()}.mir.json"
        validate_result = run(
            [str(safec), "validate-mir", str(mir_path)],
            cwd=REPO_ROOT,
            env=env,
            temp_root=temp_root,
        )
        results.append(
            {
                "source": str(sample.relative_to(REPO_ROOT)),
                "emit": emit_result,
                "validate": validate_result,
            }
        )
    return results


def check_harness_cutover() -> dict[str, dict[str, bool]]:
    results: dict[str, dict[str, bool]] = {}
    for harness in HARNESSES:
        text = harness.read_text(encoding="utf-8")
        results[str(harness.relative_to(REPO_ROOT))] = {
            "uses_validate_mir": '"validate-mir"' in text,
            "uses_legacy_validator_script": LEGACY_VALIDATOR_NAME in text,
        }
        require(
            results[str(harness.relative_to(REPO_ROOT))]["uses_validate_mir"],
            f"{harness}: expected safec validate-mir cutover",
        )
        require(
            not results[str(harness.relative_to(REPO_ROOT))]["uses_legacy_validator_script"],
            f"{harness}: legacy Python validator reference still present",
        )
    return results


def check_legacy_reference_guard() -> dict[str, bool]:
    results: dict[str, bool] = {}
    for path in LEGACY_REFERENCE_SCAN_PATHS:
        text = path.read_text(encoding="utf-8")
        contains_legacy = LEGACY_VALIDATOR_NAME in text
        results[str(path.relative_to(REPO_ROOT))] = contains_legacy
        require(
            not contains_legacy,
            f"{path}: legacy validator reference still present",
        )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    alr = find_command("alr", Path.home() / "bin" / "alr")
    safec = COMPILER_ROOT / "bin" / "safec"
    require(safec.exists(), f"expected built compiler at {safec}")

    env = os.environ.copy()

    with tempfile.TemporaryDirectory(prefix="pr065-mir-") as temp_root_str:
        temp_root = Path(temp_root_str)
        report: dict[str, Any] = {
            "tool_versions": tool_versions(alr=alr),
            "fixtures": validate_fixtures(safec, env),
            "emitted_samples": validate_emitted_samples(safec, env, temp_root),
            "harness_cutover": check_harness_cutover(),
            "legacy_reference_guard": check_legacy_reference_guard(),
        }

    write_report(args.report, report)
    print(f"pr06.5 Ada MIR validator: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr06.5 Ada MIR validator: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
