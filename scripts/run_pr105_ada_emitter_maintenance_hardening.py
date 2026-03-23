#!/usr/bin/env python3
"""Run the PR10.5 Ada emitter maintenance-hardening milestone gate."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

from _lib.harness_common import (
    compact_result,
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    require,
    require_repo_command,
    write_report,
)
from _lib.pr09_emit import (
    COMPILER_ROOT,
    REPO_ROOT,
    compile_emitted_ada,
    emitted_body_file,
    emitted_spec_file,
    repo_arg,
)
from _lib.pr10_emit import emit_fixture, gnatprove_emitted_ada


DEFAULT_REPORT = (
    REPO_ROOT / "execution" / "reports" / "pr105-ada-emitter-maintenance-hardening-report.json"
)
OWNERSHIP_BORROW_FIXTURE = REPO_ROOT / "tests" / "positive" / "ownership_borrow.safe"

POSTCONDITION_CASES: list[dict[str, object]] = [
    {
        "id": "similar_name_selector",
        "source": """package Similar_Name_Post is

   type Payload is record
      X : Integer;
      X_Copy : Integer;
   end record;

   function Touch (Ref : access Payload) is
   begin
      Ref.all.X = Ref.all.X_Copy + Ref.all.X;
   end Touch;

end Similar_Name_Post;
""",
        "required_spec_fragments": [
            "pragma Unevaluated_Use_Of_Old (Allow);",
            "Post => Ref.all.X = (Ref.all.X_Copy + Ref.all.X'Old);",
        ],
        "forbidden_fragments": [
            "Ref.all.X'Old_Copy",
            "Ref_X_Snapshot_Copy",
        ],
    },
    {
        "id": "nested_selector",
        "source": """package Nested_Target_Post is

   type Inner is record
      Value : Integer;
   end record;

   type Outer is record
      Inner_Field : Inner;
   end record;

   function Touch (Ref : access Outer) is
   begin
      Ref.all.Inner_Field.Value = Ref.all.Inner_Field.Value + 1;
   end Touch;

end Nested_Target_Post;
""",
        "required_spec_fragments": [
            "pragma Unevaluated_Use_Of_Old (Allow);",
            "Post => Ref.all.Inner_Field.Value = (Ref.all.Inner_Field.Value'Old + 1);",
        ],
        "forbidden_fragments": [],
    },
    {
        "id": "repeated_target",
        "source": """package Repeated_Target_Post is

   type Payload is record
      X : Integer;
   end record;

   function Touch (Ref : access Payload) is
   begin
      Ref.all.X = Ref.all.X + Ref.all.X;
   end Touch;

end Repeated_Target_Post;
""",
        "required_spec_fragments": [
            "pragma Unevaluated_Use_Of_Old (Allow);",
            "Post => Ref.all.X = (Ref.all.X'Old + Ref.all.X'Old);",
        ],
        "forbidden_fragments": [],
    },
    {
        "id": "call_aggregate_target",
        "source": """package Call_Aggregate_Target_Post is

   type Payload is record
      X : Integer;
   end record;

   type Holder is record
      Chosen : Integer;
   end record;

   function Take (Item : Holder) returns Integer is
   begin
      return Item.Chosen;
   end Take;

   function Touch (Ref : access Payload) is
   begin
      Ref.all.X = Take ((Chosen = Ref.all.X));
   end Touch;

end Call_Aggregate_Target_Post;
""",
        "required_spec_fragments": [
            "pragma Unevaluated_Use_Of_Old (Allow);",
            "Post => Ref.all.X = Take ((Chosen => Ref.all.X'Old));",
        ],
        "forbidden_fragments": [],
    },
]

SUBTYPE_CASES: list[dict[str, object]] = [
    {
        "id": "integer_subtype_lowering",
        "source": """package Integer_Subtype_Hardening is

   subtype Small_Count is Integer;

   function Bump (Value : in out Small_Count) is
   begin
      Value = Value + 1;
   end Bump;

end Integer_Subtype_Hardening;
""",
        "required_body_fragments": [
            "Safe_Runtime.Wide_Integer (Value) + Safe_Runtime.Wide_Integer (1)",
            "Value := Small_Count ((Safe_Runtime.Wide_Integer (Value) + Safe_Runtime.Wide_Integer (1)));",
        ],
        "forbidden_body_fragments": [],
    },
    {
        "id": "float_subtype_no_integer_lowering",
        "source": """package Float_Subtype_Hardening is

   subtype Half_Component is Float;
   type Box is record
      X : Half_Component;
   end record;

   function Capture (Input : Box) returns Half_Component is
      Value : Half_Component = Input.X;
   begin
      return Value;
   end Capture;

end Float_Subtype_Hardening;
""",
        "required_body_fragments": [
            "Value : Half_Component := Input.X;",
        ],
        "forbidden_body_fragments": [
            "Safe_Runtime.Wide_Integer",
            "pragma Assert (",
        ],
    },
]

def require_fragments(text: str, fragments: list[str], *, label: str) -> list[str]:
    for fragment in fragments:
        require(fragment in text, f"{label}: missing fragment {fragment!r}")
    return list(fragments)


def require_absent_fragments(text: str, fragments: list[str], *, label: str) -> list[str]:
    for fragment in fragments:
        require(fragment not in text, f"{label}: unexpected fragment {fragment!r}")
    return list(fragments)


def emit_and_compile_temp_source(
    *,
    source_name: str,
    source_text: str,
    env: dict[str, str],
    temp_root: Path,
) -> tuple[dict[str, Path], dict[str, Any], str, str]:
    temp_root.mkdir(parents=True, exist_ok=True)
    source_path = temp_root / source_name
    source_path.write_text(source_text, encoding="utf-8")
    outputs = emit_fixture(source=source_path, root=temp_root / source_path.stem, env=env)
    compile_result = compile_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=temp_root,
    )
    spec_text = emitted_spec_file(outputs["ada_dir"]).read_text(encoding="utf-8")
    body_text = emitted_body_file(outputs["ada_dir"]).read_text(encoding="utf-8")
    return outputs, compile_result, spec_text, body_text


def verify_ownership_borrow(*, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    outputs = emit_fixture(source=OWNERSHIP_BORROW_FIXTURE, root=temp_root / "ownership_borrow", env=env)
    compile_result = compile_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=temp_root,
    )
    flow_result = gnatprove_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=temp_root,
        mode="flow",
    )
    prove_result = gnatprove_emitted_ada(
        ada_dir=outputs["ada_dir"],
        env=env,
        temp_root=temp_root,
        mode="prove",
    )

    spec_path = emitted_spec_file(outputs["ada_dir"])
    body_path = emitted_body_file(outputs["ada_dir"])
    spec_text = spec_path.read_text(encoding="utf-8")
    body_text = body_path.read_text(encoding="utf-8")

    spec_fragments = require_fragments(
        spec_text,
        [
            "pragma Unevaluated_Use_Of_Old (Allow);",
            "Post => Ref.all.X = (Ref.all.X'Old + 1) and then Ref.all.Y = (Ref.all.Y'Old * 2);",
        ],
        label=repo_arg(OWNERSHIP_BORROW_FIXTURE),
    )
    body_fragments = require_fragments(
        body_text,
        [
            "Ref_X_Snapshot : constant Integer := Ref.all.X;",
            "Ref_Y_Snapshot : constant Integer := Ref.all.Y;",
            "Owner_X_Snapshot : constant Integer := Owner.all.X;",
        ],
        label=repo_arg(OWNERSHIP_BORROW_FIXTURE),
    )

    require(
        flow_result["summary"]["total"]["justified"]["count"] == 0,
        f"{repo_arg(OWNERSHIP_BORROW_FIXTURE)}: flow summary must have zero justified checks",
    )
    require(
        flow_result["summary"]["total"]["unproved"]["count"] == 0,
        f"{repo_arg(OWNERSHIP_BORROW_FIXTURE)}: flow summary must have zero unproved checks",
    )
    require(
        prove_result["summary"]["total"]["justified"]["count"] == 0,
        f"{repo_arg(OWNERSHIP_BORROW_FIXTURE)}: prove summary must have zero justified checks",
    )
    require(
        prove_result["summary"]["total"]["unproved"]["count"] == 0,
        f"{repo_arg(OWNERSHIP_BORROW_FIXTURE)}: prove summary must have zero unproved checks",
    )

    return {
        "fixture": repo_arg(OWNERSHIP_BORROW_FIXTURE),
        "compile": compact_result(compile_result),
        "flow": flow_result,
        "prove": prove_result,
        "structural_assertions": {
            spec_path.name: spec_fragments,
            body_path.name: body_fragments,
        },
    }


def verify_postcondition_cases(*, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in POSTCONDITION_CASES:
        case_root = temp_root / str(case["id"])
        _outputs, compile_result, spec_text, body_text = emit_and_compile_temp_source(
            source_name=f"{case['id']}.safe",
            source_text=str(case["source"]),
            env=env,
            temp_root=case_root,
        )
        results.append(
            {
                "case": case["id"],
                "compile": compact_result(compile_result),
                "spec_assertions": {
                    "required": require_fragments(
                        spec_text,
                        list(case["required_spec_fragments"]),
                        label=str(case["id"]),
                    ),
                    "forbidden": require_absent_fragments(
                        spec_text + "\n" + body_text,
                        list(case["forbidden_fragments"]),
                        label=str(case["id"]),
                    ),
                },
            }
        )
    return results


def verify_subtype_cases(*, env: dict[str, str], temp_root: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in SUBTYPE_CASES:
        case_root = temp_root / str(case["id"])
        _outputs, compile_result, _spec_text, body_text = emit_and_compile_temp_source(
            source_name=f"{case['id']}.safe",
            source_text=str(case["source"]),
            env=env,
            temp_root=case_root,
        )
        results.append(
            {
                "case": case["id"],
                "compile": compact_result(compile_result),
                "body_assertions": {
                    "required": require_fragments(
                        body_text,
                        list(case["required_body_fragments"]),
                        label=str(case["id"]),
                    ),
                    "forbidden": require_absent_fragments(
                        body_text,
                        list(case["forbidden_body_fragments"]),
                        label=str(case["id"]),
                    ),
                },
            }
        )
    return results


def generate_report(*, env: dict[str, str]) -> dict[str, Any]:
    require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")
    with tempfile.TemporaryDirectory(prefix="pr105-emitter-hardening-") as temp_root_str:
        temp_root = Path(temp_root_str)
        return {
            "task": "PR10.5",
            "status": "ok",
            "ownership_borrow_regression": verify_ownership_borrow(env=env, temp_root=temp_root),
            "alias_postcondition_regressions": verify_postcondition_cases(env=env, temp_root=temp_root),
            "subtype_classification_regressions": verify_subtype_cases(env=env, temp_root=temp_root),
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    report = finalize_deterministic_report(
        lambda: generate_report(env=env),
        label="PR10.5 Ada emitter maintenance hardening",
    )
    write_report(args.report, report)
    print(
        "pr105 ada emitter maintenance hardening: OK "
        f"({display_path(args.report, repo_root=REPO_ROOT)})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr105 ada emitter maintenance hardening: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
