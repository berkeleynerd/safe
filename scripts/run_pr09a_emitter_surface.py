#!/usr/bin/env python3
"""Run the PR09a emitter surface gate."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    managed_scratch_root,
    require,
    write_report,
)
from _lib.pr09_emit import (
    REPO_ROOT,
    compile_emitted_ada,
    emit_with_determinism,
    emitted_ada_files,
    emitted_body_file,
    ensure_emit_failure_is_atomic,
    ensure_emit_success,
    file_hashes,
    repo_arg,
    require_safec,
    run_emit,
    structural_assertions,
)


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr09a-emitter-surface-report.json"
SURFACE_FIXTURES = [
    REPO_ROOT / "tests" / "positive" / "emitter_surface_record.safe",
    REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe",
]
DISCRIMINANT_FIXTURE = REPO_ROOT / "tests" / "positive" / "pr09_emitter_discriminant.safe"


def seed_file(path: Path, contents: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")


def generate_report(*, safec: Path, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, object]:
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr09a-surface-") as temp_root:
        positives: list[dict[str, object]] = []

        for fixture in SURFACE_FIXTURES:
            root_a = temp_root / f"{fixture.stem}-a"
            root_b = temp_root / f"{fixture.stem}-b"
            determinism = emit_with_determinism(
                safec=safec,
                source=fixture,
                root_a=root_a,
                root_b=root_b,
                env=env,
                temp_root=temp_root,
            )
            ensure_emit_success(source=fixture, root=root_a)
            compile_result = compile_emitted_ada(
                ada_dir=root_a / "ada",
                env=env,
                temp_root=temp_root,
            )
            ada_files = emitted_ada_files(root_a / "ada")
            require("safe_runtime.ads" not in ada_files, f"{fixture}: slice-1 fixture should not need safe_runtime.ads")
            require("gnat.adc" not in ada_files, f"{fixture}: slice-1 fixture should not need gnat.adc")

            body_path = emitted_body_file(root_a / "ada")
            spec_path = body_path.with_suffix(".ads")
            positives.append(
                {
                    "fixture": repo_arg(fixture),
                    "ada_files": ada_files,
                    "determinism": determinism,
                    "compile": compile_result,
                    "structural_assertions": {
                        spec_path.name: structural_assertions(
                            spec_path,
                            ["pragma SPARK_Mode (On);", "with SPARK_Mode => On", "package "],
                        ),
                        body_path.name: structural_assertions(
                            body_path,
                            ["package body "],
                        ),
                    },
                }
            )

        discriminant_root = temp_root / "discriminant"
        root_a = discriminant_root / "a"
        root_b = discriminant_root / "b"
        discriminant_determinism = emit_with_determinism(
            safec=safec,
            source=DISCRIMINANT_FIXTURE,
            root_a=root_a,
            root_b=root_b,
            env=env,
            temp_root=temp_root,
        )
        ensure_emit_success(source=DISCRIMINANT_FIXTURE, root=root_a)
        discriminant_compile = compile_emitted_ada(
            ada_dir=root_a / "ada",
            env=env,
            temp_root=temp_root,
        )
        discriminant_files = emitted_ada_files(root_a / "ada")
        require("safe_runtime.ads" not in discriminant_files, f"{DISCRIMINANT_FIXTURE}: boolean-discriminant subset should not need safe_runtime.ads")
        require("gnat.adc" not in discriminant_files, f"{DISCRIMINANT_FIXTURE}: boolean-discriminant subset should not need gnat.adc")
        discriminant_body = emitted_body_file(root_a / "ada")
        discriminant_spec = discriminant_body.with_suffix(".ads")

        stale_root = temp_root / "support-preservation"
        for name in ("out", "iface", "ada"):
            (stale_root / name).mkdir(parents=True, exist_ok=True)
        seed_file(stale_root / "ada" / "safe_runtime.ads", "-- stale runtime\n")
        seed_file(stale_root / "ada" / "gnat.adc", "-- stale adc\n")
        stale_before = file_hashes(stale_root / "ada")
        run_emit(
            safec=safec,
            source=SURFACE_FIXTURES[0],
            out_dir=stale_root / "out",
            iface_dir=stale_root / "iface",
            ada_dir=stale_root / "ada",
            env=env,
            temp_root=temp_root,
        )
        ensure_emit_success(source=SURFACE_FIXTURES[0], root=stale_root)
        stale_after = file_hashes(stale_root / "ada")
        require(
            stale_before["safe_runtime.ads"] == stale_after["safe_runtime.ads"],
            f"{SURFACE_FIXTURES[0]}: existing safe_runtime.ads should be preserved",
        )
        require(
            stale_before["gnat.adc"] == stale_after["gnat.adc"],
            f"{SURFACE_FIXTURES[0]}: existing gnat.adc should be preserved",
        )

        return {
            "positive_fixtures": positives,
            "boolean_discriminant_fixture": {
                "fixture": repo_arg(DISCRIMINANT_FIXTURE),
                "ada_files": discriminant_files,
                "determinism": discriminant_determinism,
                "compile": discriminant_compile,
                "structural_assertions": {
                    discriminant_spec.name: structural_assertions(
                        discriminant_spec,
                        [
                            "type emitter_result (ok : boolean := False) is record",
                            "case ok is",
                            "when True =>",
                            "when False =>",
                        ],
                    ),
                    discriminant_body.name: structural_assertions(
                        discriminant_body,
                        ["package body pr09_emitter_discriminant with SPARK_Mode => On is"],
                    ),
                },
            },
            "shared_support_files_preserved": {
                "fixture": repo_arg(SURFACE_FIXTURES[0]),
                "before": stale_before,
                "after": stale_after,
            },
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    safec = require_safec()
    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, env=env, scratch_root=args.scratch_root),
        label="PR09a surface",
    )
    write_report(args.report, report)
    print(f"pr09a emitter surface: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr09a emitter surface: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
