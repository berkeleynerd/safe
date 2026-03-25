#!/usr/bin/env python3
"""Run the PR09b concurrency output and gnat.adc gate."""

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
    emitted_body_file,
    ensure_emit_success,
    repo_arg,
    require_safec,
    structural_assertions,
)


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr09b-concurrency-output-report.json"
FIXTURES = [
    REPO_ROOT / "tests" / "positive" / "channel_pingpong.safe",
    REPO_ROOT / "tests" / "positive" / "channel_pipeline.safe",
    REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
]
EXPECTED_GNAT_ADC = (
    "pragma Partition_Elaboration_Policy(Sequential);\n"
    "pragma Profile(Jorvik);\n"
)


def generate_report(*, safec: Path, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, object]:
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr09b-conc-") as temp_root:
        fixtures: list[dict[str, object]] = []

        for fixture in FIXTURES:
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
            ada_dir = root_a / "ada"
            require((ada_dir / "gnat.adc").exists(), f"{fixture}: expected gnat.adc")
            require(
                (ada_dir / "gnat.adc").read_text(encoding="utf-8") == EXPECTED_GNAT_ADC,
                f"{fixture}: gnat.adc content drifted",
            )
            compile_result = compile_emitted_ada(
                ada_dir=ada_dir,
                env=env,
                temp_root=temp_root,
            )
            body_path = emitted_body_file(ada_dir)
            spec_path = body_path.with_suffix(".ads")
            spec_fragments = ["protected type", "task "]
            if fixture.name == "select_with_delay.safe":
                spec_fragments.append("Try_Receive (Value : in out Message; Success : out Boolean);")
                body_fragments = ["Select_Polls", "Try_Receive (", "delay 0.001;", "Success := False;"]
            else:
                body_fragments = [".Send (", ".Receive ("]
            fixtures.append(
                {
                    "fixture": repo_arg(fixture),
                    "determinism": determinism,
                    "compile": compile_result,
                    "gnat_adc": {
                        "path": "gnat.adc",
                        "content": EXPECTED_GNAT_ADC,
                    },
                    "structural_assertions": {
                        spec_path.name: structural_assertions(
                            spec_path,
                            spec_fragments,
                        ),
                        body_path.name: structural_assertions(
                            body_path,
                            body_fragments,
                        ),
                    },
                }
            )

        return {"fixtures": fixtures}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--scratch-root", type=Path)
    args = parser.parse_args()

    safec = require_safec()
    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(safec=safec, env=env, scratch_root=args.scratch_root),
        label="PR09b concurrency",
    )
    write_report(args.report, report)
    print(f"pr09b concurrency output: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr09b concurrency output: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
