#!/usr/bin/env python3
"""Run the PR09a arithmetic MVP emitter gate."""

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
    emitted_spec_file,
    ensure_emit_success,
    repo_arg,
    require_safec,
    safe_runtime_matches_template,
    structural_assertions,
)


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr09a-emitter-mvp-report.json"
RULE1_FIXTURES = [
    REPO_ROOT / "tests" / "positive" / "rule1_averaging.safe",
    REPO_ROOT / "tests" / "positive" / "rule1_accumulate.safe",
    REPO_ROOT / "tests" / "positive" / "rule1_parameter.safe",
    REPO_ROOT / "tests" / "positive" / "rule1_return.safe",
    REPO_ROOT / "tests" / "positive" / "rule1_conversion.safe",
]


def generate_report(*, safec: Path, env: dict[str, str], scratch_root: Path | None = None) -> dict[str, object]:
    with managed_scratch_root(scratch_root=scratch_root, prefix="pr09a-mvp-") as temp_root:
        fixtures: list[dict[str, object]] = []

        for fixture in RULE1_FIXTURES:
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
            spec_path = emitted_spec_file(root_a / "ada")
            spec_fragments = ["Depends =>", "Output => Raw"] if fixture.name == "rule1_parameter.safe" else []
            safe_runtime_hashes = safe_runtime_matches_template(root_a / "ada")
            fixtures.append(
                {
                    "fixture": repo_arg(fixture),
                    "determinism": determinism,
                    "compile": compile_result,
                    "safe_runtime": safe_runtime_hashes,
                    "structural_assertions": {
                        body_path.name: structural_assertions(
                            body_path,
                            ["Safe_Runtime.Wide_Integer", "pragma Assert"],
                        ),
                        **(
                            {
                                spec_path.name: structural_assertions(
                                    spec_path,
                                    spec_fragments,
                                )
                            }
                            if spec_fragments
                            else {}
                        ),
                    },
                }
            )

        return {
            "fixtures": fixtures,
            "notes": [
                "PR09a emits compile-valid Ada/SPARK skeleton output on the rule1 subset.",
                "safe_runtime.ads remains byte-identical to companion/templates/safe_runtime.ads.",
            ],
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
        label="PR09a MVP",
    )
    write_report(args.report, report)
    print(f"pr09a emitter MVP: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr09a emitter MVP: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
