#!/usr/bin/env python3
"""Run supplemental emitted-output hardening regressions beyond the frozen PR10 corpus."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from _lib.attestation_compression import RETIRED_ARCHIVE_REPORT_PATHS
from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    managed_scratch_root,
    read_diag_json,
    require,
    run,
    write_report,
)
from _lib.proof_report import (
    build_three_way_report,
    split_command_result,
    split_proof_fixtures,
)
from _lib.pr09_emit import (
    REPO_ROOT,
    compile_emitted_ada,
    emitted_body_file,
    emitted_spec_file,
    repo_arg,
    require_safec,
    run_emit,
)
from _lib.pr10_emit import emit_fixture, gnatprove_emitted_ada
from _lib.pr10_emit import require_explicit_gnat_adc


DEFAULT_REPORT = RETIRED_ARCHIVE_REPORT_PATHS["emitted_hardening_regressions"]
OWNERSHIP_FIXTURE = REPO_ROOT / "tests" / "positive" / "ownership_early_return.safe"
PROOF_FIXTURES = [
    REPO_ROOT / "tests" / "concurrency" / "select_with_delay_multiarm.safe",
]
REJECTED_CHANNEL_FIXTURES = [
    REPO_ROOT / "tests" / "concurrency" / "channel_access_type.safe",
    REPO_ROOT / "tests" / "negative" / "neg_channel_access_component.safe",
    REPO_ROOT / "tests" / "concurrency" / "try_send_ownership.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_ownership_binding.safe",
]

def ownership_early_return_regression(*, env: dict[str, str], temp_root: Path) -> dict[str, object]:
    root = temp_root / OWNERSHIP_FIXTURE.stem
    outputs = emit_fixture(source=OWNERSHIP_FIXTURE, root=root, env=env)
    compile_result = compile_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=temp_root,
    )
    body_path = emitted_body_file(outputs["ada_dir"])
    body_text = body_path.read_text(encoding="utf-8")
    required = [
        "Return_Value : constant integer := Outer.all.value;",
        "Free_payload_ptr (Inner);",
        "Free_payload_ptr (Outer);",
        "return Return_Value;",
    ]
    for fragment in required:
        require(fragment in body_text, f"{OWNERSHIP_FIXTURE}: missing emitted fragment {fragment!r}")

    capture_index = body_text.index("Return_Value : constant integer := Outer.all.value;")
    inner_index = body_text.index("Free_payload_ptr (Inner);")
    outer_index = body_text.index("Free_payload_ptr (Outer);")
    return_index = body_text.index("return Return_Value;")
    require(
        capture_index < inner_index < outer_index < return_index,
        f"{OWNERSHIP_FIXTURE}: return capture must precede cleanup, and cleanup must precede the return",
    )

    return {
        "fixture": repo_arg(OWNERSHIP_FIXTURE),
        "compile": compile_result,
        "structural_assertions": {
            body_path.name: required,
        },
    }


def supplemental_proof_fixture(*, source: Path, env: dict[str, str], temp_root: Path) -> dict[str, object]:
    root = temp_root / source.stem
    outputs = emit_fixture(source=source, root=root, env=env)
    ada_dir = outputs["ada_dir"]
    require((ada_dir / "gnat.adc").exists(), f"{source}: expected gnat.adc in emitted Ada output")

    compile_result = compile_emitted_ada(
        ada_dir=ada_dir,
        env=env,
        temp_root=temp_root,
    )
    require_explicit_gnat_adc(compile_result["command"], fixture=source, label="compile")

    flow_result = gnatprove_emitted_ada(
        ada_dir=ada_dir,
        env=env,
        temp_root=temp_root,
        mode="flow",
    )
    require_explicit_gnat_adc(flow_result["command"], fixture=source, label="flow")

    spec_path = emitted_spec_file(ada_dir)
    body_path = emitted_body_file(ada_dir)
    spec_text = spec_path.read_text(encoding="utf-8")
    body_text = body_path.read_text(encoding="utf-8")

    require(
        source.name == "select_with_delay_multiarm.safe",
        f"unexpected supplemental proof fixture: {source}",
    )
    require(
        "procedure Try_Receive (Value : in out message; Success : out Boolean);" in spec_text,
        f"{source}: expected in out Try_Receive channel contract in emitted spec",
    )
    require(
        "procedure Try_Receive (Value : in out message; Success : out Boolean) is" in body_text,
        f"{source}: expected in out Try_Receive channel contract in emitted body",
    )
    require("Value := message'First;" not in body_text, f"{source}: failed Try_Receive must not write message'First")
    structural = ["Select_Polls", "Try_Receive (", "Success := False;"]
    prove_result = gnatprove_emitted_ada(
        ada_dir=ada_dir,
        env=env,
        temp_root=temp_root,
        mode="prove",
    )
    require_explicit_gnat_adc(prove_result["command"], fixture=source, label="prove")
    flow_summary = flow_result["summary"]["total"]
    require(flow_summary["justified"]["count"] == 0, f"{source}: flow justified checks must be zero")
    require(flow_summary["unproved"]["count"] == 0, f"{source}: flow unproved checks must be zero")
    summary = prove_result["summary"]["total"]
    require(summary["justified"]["count"] == 0, f"{source}: justified checks must be zero")
    require(summary["unproved"]["count"] == 0, f"{source}: unproved checks must be zero")

    for fragment in structural:
        require(fragment in body_text or fragment in spec_text, f"{source}: missing structural fragment {fragment!r}")

    return {
        "fixture": repo_arg(source),
        "compile": compile_result,
        "flow": flow_result,
        "prove": prove_result,
        "structural_assertions": {
            spec_path.name: [fragment for fragment in structural if fragment in spec_text],
            body_path.name: [fragment for fragment in structural if fragment in body_text],
        },
    }


def rejected_channel_fixture(
    *,
    safec: Path,
    source: Path,
    env: dict[str, str],
    temp_root: Path,
) -> dict[str, object]:
    check_result = run(
        [str(safec), "check", "--diag-json", repo_arg(source)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    payload = read_diag_json(check_result["stdout"], repo_arg(source))
    diagnostics = payload.get("diagnostics", [])
    require(diagnostics, f"{source}: expected at least one diagnostic")
    first = diagnostics[0]
    require(first["reason"] == "source_frontend_error", f"{source}: expected source_frontend_error")
    require(
        "channel element type shall not be an access type or a composite type containing an access-type subcomponent"
        in first["message"],
        f"{source}: expected access-channel rejection message",
    )

    root = temp_root / f"{source.stem}-reject"
    out_dir = root / "out"
    iface_dir = root / "iface"
    ada_dir = root / "ada"
    out_dir.mkdir(parents=True, exist_ok=True)
    iface_dir.mkdir(parents=True, exist_ok=True)
    ada_dir.mkdir(parents=True, exist_ok=True)
    emit_result = run_emit(
        safec=safec,
        source=source,
        out_dir=out_dir,
        iface_dir=iface_dir,
        ada_dir=ada_dir,
        env=env,
        temp_root=temp_root,
        expected_returncode=1,
    )
    require(not any(out_dir.iterdir()), f"{source}: emit failure must leave out_dir empty")
    require(not any(iface_dir.iterdir()), f"{source}: emit failure must leave iface_dir empty")
    require(not any(ada_dir.iterdir()), f"{source}: emit failure must leave ada_dir empty")

    return {
        "fixture": repo_arg(source),
        "check": check_result,
        "emit": emit_result,
        "first_diagnostic": {
            "reason": first["reason"],
            "message": first["message"],
            "path": first["path"],
        },
    }


def split_ownership_fixture(fixture: dict[str, object]) -> tuple[dict[str, object], dict[str, object]]:
    compile_canonical, compile_machine = split_command_result(fixture["compile"])  # type: ignore[arg-type]
    canonical = {
        "fixture": fixture["fixture"],
        "compile": compile_canonical,
        "structural_assertions": fixture["structural_assertions"],
    }
    machine = {
        "fixture": fixture["fixture"],
        "compile": compile_machine,
    }
    return canonical, machine


def split_rejected_fixture(fixture: dict[str, object]) -> tuple[dict[str, object], dict[str, object]]:
    check_canonical, check_machine = split_command_result(fixture["check"])  # type: ignore[arg-type]
    emit_canonical, emit_machine = split_command_result(fixture["emit"])  # type: ignore[arg-type]
    canonical = {
        "fixture": fixture["fixture"],
        "check": check_canonical,
        "emit": emit_canonical,
        "first_diagnostic": fixture["first_diagnostic"],
    }
    machine = {
        "fixture": fixture["fixture"],
        "check": check_machine,
        "emit": emit_machine,
    }
    return canonical, machine


def generate_report(*, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, object]:
    safec = require_safec()
    with managed_scratch_root(scratch_root=scratch_root, prefix="emitted-hardening-") as temp_root:
        ownership = ownership_early_return_regression(env=env, temp_root=temp_root)
        supplemental_proof_fixtures = [
            supplemental_proof_fixture(source=fixture, env=env, temp_root=temp_root)
            for fixture in PROOF_FIXTURES
        ]
        rejected_access_channel_fixtures = [
            rejected_channel_fixture(safec=safec, source=fixture, env=env, temp_root=temp_root)
            for fixture in REJECTED_CHANNEL_FIXTURES
        ]

    semantic_floor, canonical_proof_fixtures, machine_proof_fixtures = split_proof_fixtures(
        supplemental_proof_fixtures
    )
    ownership_canonical, ownership_machine = split_ownership_fixture(ownership)
    canonical_rejected: list[dict[str, object]] = []
    machine_rejected: list[dict[str, object]] = []
    for fixture in rejected_access_channel_fixtures:
        canonical, machine = split_rejected_fixture(fixture)
        canonical_rejected.append(canonical)
        machine_rejected.append(machine)
    return build_three_way_report(
        identity={},
        semantic_floor=semantic_floor,
        canonical_proof_detail={
            "ownership_early_return": ownership_canonical,
            "supplemental_proof_fixtures": canonical_proof_fixtures,
            "rejected_access_channel_fixtures": canonical_rejected,
            "notes": [
                "This gate hardens emitted-output regressions beyond the frozen PR10 selected corpus.",
                "Ownership early-return ordering remains a structural emitted-Ada regression rather than a PR10 prove target.",
                "Supplemental concurrency fixtures require explicit -gnatec application for compile, flow, and prove.",
                "Access-typed channel element declarations are now rejected by the frontend and must not emit Ada artifacts.",
            ],
        },
        machine_sensitive={
            "ownership_early_return": ownership_machine,
            "supplemental_proof_fixtures": machine_proof_fixtures,
            "rejected_access_channel_fixtures": machine_rejected,
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env, scratch_root=args.scratch_root),
        label="emitted hardening regressions",
    )
    write_report(args.report, report)
    print(
        "emitted hardening regressions: OK "
        f"({display_path(args.report, repo_root=REPO_ROOT)})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"emitted hardening regressions: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
