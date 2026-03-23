#!/usr/bin/env python3
"""Run the PR10.4 GNATprove evidence and parser-hardening milestone gate."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    compact_result,
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    managed_scratch_root,
    require,
    require_repo_command,
    run,
    write_report,
)
from _lib.proof_report import (
    build_three_way_report,
    command_profile,
    split_command_result,
    split_proof_fixtures,
)
from _lib.pr09_emit import COMPILER_ROOT, REPO_ROOT, compile_emitted_ada, repo_arg
from _lib.pr10_emit import (
    PROVE_SWITCHES,
    emit_fixture,
    gnatprove_emitted_ada,
    require_explicit_gnat_adc,
)


DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr104-gnatprove-evidence-parser-hardening-report.json"
)
AUDIT_HARDENING_TESTS = "scripts.tests.test_pr101_audit_hardening"
CONCURRENCY_FIXTURE = REPO_ROOT / "tests" / "concurrency" / "select_with_delay_multiarm.safe"
GNATPROVE_PROFILE_DOC = REPO_ROOT / "docs" / "gnatprove_profile.md"

PR06910_REPORT = REPO_ROOT / "execution" / "reports" / "pr06910-portability-environment-report.json"
PR06911_REPORT = REPO_ROOT / "execution" / "reports" / "pr06911-glue-script-safety-report.json"
PR06913_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr06913-documentation-architecture-clarity-report.json"
)

EXPECTED_PROVE_SWITCHES = [
    "--mode=prove",
    "--level=2",
    "--prover=cvc5,z3,altergo",
    "--steps=0",
    "--timeout=120",
    "--report=all",
    "--warnings=error",
    "--checks-as-errors=on",
]
EXPECTED_GNATPROVE_PROFILE_SNIPPETS = [
    "### 4.7 Emitted-Proof Reproducibility Contract",
    "`--mode=prove --level=2 --prover=cvc5,z3,altergo --steps=0 --timeout=120 --report=all --warnings=error --checks-as-errors=on`",
    "deterministic reports plus normalized GNATprove summaries",
    "GNATprove session artifacts are not committed and are not part of the reproducibility contract",
]

def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def require_command_contains(command: list[str], expected_items: list[str], *, label: str) -> None:
    for item in expected_items:
        require(item in command, f"{label}: missing required switch {item}")


def require_no_hash_fields(payload: Any, *, label: str) -> None:
    if isinstance(payload, dict):
        for key, value in payload.items():
            require(
                key not in {"report_sha256", "repeat_sha256"},
                f"{label}: child report hash field {key} must be absent",
            )
            require_no_hash_fields(value, label=label)
    elif isinstance(payload, list):
        for item in payload:
            require_no_hash_fields(item, label=label)


def verify_proof_profile_doc() -> dict[str, Any]:
    text = GNATPROVE_PROFILE_DOC.read_text(encoding="utf-8")
    for snippet in EXPECTED_GNATPROVE_PROFILE_SNIPPETS:
        require(snippet in text, f"{display_path(GNATPROVE_PROFILE_DOC, repo_root=REPO_ROOT)} missing snippet: {snippet}")
    return {
        "path": display_path(GNATPROVE_PROFILE_DOC, repo_root=REPO_ROOT),
        "required_snippets": EXPECTED_GNATPROVE_PROFILE_SNIPPETS,
    }


def verify_parser_tests(*, python: str, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    result = run(
        [python, "-m", "unittest", AUDIT_HARDENING_TESTS],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    return compact_result(result)


def verify_concurrency_evidence(*, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    fixture_root = temp_root / CONCURRENCY_FIXTURE.stem
    outputs = emit_fixture(source=CONCURRENCY_FIXTURE, root=fixture_root, env=env)
    compile_result = compile_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=fixture_root,
    )
    flow_result = gnatprove_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=fixture_root,
        mode="flow",
    )
    prove_result = gnatprove_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=fixture_root,
        mode="prove",
    )

    require_explicit_gnat_adc(compile_result["command"], fixture=CONCURRENCY_FIXTURE, label="compile")
    require_explicit_gnat_adc(flow_result["command"], fixture=CONCURRENCY_FIXTURE, label="flow")
    require_explicit_gnat_adc(prove_result["command"], fixture=CONCURRENCY_FIXTURE, label="prove")
    require(PROVE_SWITCHES == EXPECTED_PROVE_SWITCHES, "shared PROVE_SWITCHES must match the committed PR10 profile")
    require_command_contains(prove_result["command"], EXPECTED_PROVE_SWITCHES, label=repo_arg(CONCURRENCY_FIXTURE))
    require(
        flow_result["summary"]["total"]["justified"]["count"] == 0,
        f"{repo_arg(CONCURRENCY_FIXTURE)}: flow justified checks must be zero",
    )
    require(
        flow_result["summary"]["total"]["unproved"]["count"] == 0,
        f"{repo_arg(CONCURRENCY_FIXTURE)}: flow unproved checks must be zero",
    )
    require(
        prove_result["summary"]["total"]["justified"]["count"] == 0,
        f"{repo_arg(CONCURRENCY_FIXTURE)}: justified checks must be zero",
    )
    require(
        prove_result["summary"]["total"]["unproved"]["count"] == 0,
        f"{repo_arg(CONCURRENCY_FIXTURE)}: unproved checks must be zero",
    )

    return {
        "fixture": repo_arg(CONCURRENCY_FIXTURE),
        "compile": compact_result(compile_result),
        "flow": flow_result,
        "prove": prove_result,
        "prove_profile": {
            "shared_switches": list(PROVE_SWITCHES),
            "actual_command": prove_result["command"],
        },
    }


def verify_decascaded_reports() -> dict[str, Any]:
    pr06910 = load_json(PR06910_REPORT)
    pr06911 = load_json(PR06911_REPORT)
    pr06913 = load_json(PR06913_REPORT)

    require("unit_tests" not in pr06910, "PR06.9.10 report must not include repo-wide unit test summaries")
    require("unit_tests" not in pr06911, "PR06.9.11 report must not include repo-wide unit test summaries")
    require_no_hash_fields(pr06911["reruns"], label="PR06.9.11 reruns")
    require_no_hash_fields(
        pr06911["referenced_deterministic_reports"],
        label="PR06.9.11 referenced_deterministic_reports",
    )
    require_no_hash_fields(pr06913["reruns"], label="PR06.9.13 reruns")

    for key in ("runtime_boundary", "gate_quality", "portability_environment"):
        require(
            pr06911["reruns"][key].get("matches_committed_report") is True,
            f"PR06.9.11 {key} must record comparison success",
        )
    for key in ("frontend_smoke", "build_reproducibility"):
        require(
            pr06911["referenced_deterministic_reports"][key].get("matches_committed_report") is True,
            f"PR06.9.11 {key} must record comparison success",
        )
    for key in (
        "runtime_boundary",
        "legacy_package_cleanup",
        "portability_environment",
        "gate_quality",
        "glue_script_safety",
        "performance_scale_sanity",
    ):
        require(
            pr06913["reruns"][key].get("matches_committed_report") is True,
            f"PR06.9.13 {key} must record comparison success",
        )

    return {
        "committed_report_contracts": {
            "pr06910": {
                "report_path": display_path(PR06910_REPORT, repo_root=REPO_ROOT),
                "unit_tests_absent": True,
            },
            "pr06911": {
                "report_path": display_path(PR06911_REPORT, repo_root=REPO_ROOT),
                "unit_tests_absent": True,
                "hash_fields_absent": True,
                "comparison_fields_present": True,
            },
            "pr06913": {
                "report_path": display_path(PR06913_REPORT, repo_root=REPO_ROOT),
                "hash_fields_absent": True,
                "comparison_fields_present": True,
            },
        },
    }


def generate_report(*, python: str, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, Any]:
    require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr104-evidence-hardening-") as temp_root:
        parser_regressions = verify_parser_tests(python=python, env=env, temp_root=temp_root)
        emitted_concurrency_evidence = verify_concurrency_evidence(env=env, temp_root=temp_root)
        gnatprove_profile_doc = verify_proof_profile_doc()
        de_cascaded_reports = verify_decascaded_reports()

    semantic_floor, canonical_fixtures, machine_fixtures = split_proof_fixtures(
        [emitted_concurrency_evidence]
    )
    parser_canonical, parser_machine = split_command_result(parser_regressions)
    prove_profile = canonical_fixtures[0].pop("prove_profile")
    canonical_fixtures[0]["prove_profile"] = {
        "shared_switches": prove_profile["shared_switches"],
        "command_profile": command_profile(prove_profile["actual_command"]),
    }
    machine_fixtures[0]["prove_profile"] = {
        "actual_command": prove_profile["actual_command"],
    }
    return build_three_way_report(
        identity={
            "task": "PR10.4",
            "status": "ok",
        },
        semantic_floor=semantic_floor,
        canonical_proof_detail={
            "parser_regressions": parser_canonical,
            "emitted_concurrency_evidence": canonical_fixtures[0],
            "gnatprove_profile_doc": gnatprove_profile_doc,
            "de_cascaded_reports": de_cascaded_reports,
        },
        machine_sensitive={
            "parser_regressions": parser_machine,
            "emitted_concurrency_evidence": machine_fixtures[0],
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    python = find_command("python3")
    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(python=python, env=env, scratch_root=args.scratch_root),
        label="PR10.4 GNATprove evidence and parser hardening",
    )
    write_report(args.report, report)
    print(f"pr104 gnatprove evidence and parser hardening: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr104 gnatprove evidence and parser hardening: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
