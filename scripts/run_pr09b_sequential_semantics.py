#!/usr/bin/env python3
"""Run the PR09b sequential ownership and public-aspects gate."""

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


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr09b-sequential-semantics-report.json"
FIXTURES = [
    REPO_ROOT / "tests" / "positive" / "ownership_early_return.safe",
    REPO_ROOT / "tests" / "positive" / "ownership_move.safe",
    REPO_ROOT / "tests" / "positive" / "rule4_linked_list.safe",
]


def generate_report(*, safec: Path, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, object]:
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr09b-seq-") as temp_root:
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
            compile_result = compile_emitted_ada(
                ada_dir=root_a / "ada",
                env=env,
                temp_root=temp_root,
            )
            body_path = emitted_body_file(root_a / "ada")
            spec_path = body_path.with_suffix(".ads")
            body_text = body_path.read_text(encoding="utf-8")
            if fixture.name == "ownership_early_return.safe":
                required = [
                    "Return_Value : constant Integer := Outer.all.Value;",
                    "Free_Payload_Ptr (Inner);",
                    "Free_Payload_Ptr (Outer);",
                    "return Return_Value;",
                ]
                capture_index = body_text.find("Return_Value : constant Integer := Outer.all.Value;")
                inner_index = body_text.find("Free_Payload_Ptr (Inner);")
                outer_index = body_text.find("Free_Payload_Ptr (Outer);")
                return_index = body_text.find("return Return_Value;")
                require(
                    capture_index >= 0 and inner_index >= 0 and outer_index >= 0 and return_index >= 0,
                    f"{fixture}: missing early-return capture/cleanup fragments in emitted body",
                )
                require(
                    capture_index < inner_index < outer_index < return_index,
                    f"{fixture}: early-return path must capture the return value before freeing inner then outer owner",
                )
                spec_required = ["Global => null"]
            elif fixture.name == "ownership_move.safe":
                required = ["Source := null;", "Ada.Unchecked_Deallocation"]
                spec_required = ["Global => null"]
            else:
                required = ["Current.all.Next"]
                spec_required = ["Global => null"]
            fixtures.append(
                {
                    "fixture": repo_arg(fixture),
                    "determinism": determinism,
                    "compile": compile_result,
                    "structural_assertions": {
                        body_path.name: structural_assertions(
                            body_path,
                            required,
                        ),
                        spec_path.name: structural_assertions(
                            spec_path,
                            spec_required,
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
        label="PR09b sequential",
    )
    write_report(args.report, report)
    print(f"pr09b sequential semantics: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr09b sequential semantics: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
