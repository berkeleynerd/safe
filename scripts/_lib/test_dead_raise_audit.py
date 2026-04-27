"""Baseline-gated checks for the Phase 1F dead-raise scanner."""

from __future__ import annotations

import json
import subprocess
import sys

import audit_dead_raise
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_dead_raise.py"
BASELINE_PATH = audit_dead_raise.BASELINE_PATH
PHASE_LABEL = "Phase 1F dead raise"
REQUIRED_FIELDS = (
    "fingerprint",
    "category",
    "pattern",
    "path",
    "line",
    "line_numbers",
    "first_line_text",
    "line_text",
    "fallthrough_line",
    "fallthrough_line_number",
    "multiplicity",
    "classification",
    "rationale",
    "follow_up",
)


def validate_entries(payload: object, label: str) -> tuple[bool, str]:
    return baseline_audit_gate.validate_entries(
        payload,
        label,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_dead_raise.CATEGORIES,
        valid_patterns=audit_dead_raise.PATTERNS,
    )


def read_baseline_payload() -> tuple[dict[str, object] | None, str]:
    return baseline_audit_gate.read_baseline_payload(BASELINE_PATH, repo_root=REPO_ROOT)


def compare_live_scan_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    return baseline_audit_gate.compare_live_scan_to_baseline(
        live_payload,
        baseline_payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_dead_raise.CATEGORIES,
        valid_patterns=audit_dead_raise.PATTERNS,
    )


def run_live_scan_case() -> tuple[bool, str]:
    completed = subprocess.run(
        [sys.executable, str(AUDIT_SCRIPT), "--json"],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return False, first_message(completed)
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        return False, f"invalid scanner JSON: {exc}"
    ok, message = validate_entries(payload, "scanner JSON")
    if not ok:
        return False, message
    audit_dead_raise.print_summary(
        payload,
        baseline_entries=audit_dead_raise.existing_classifications(),
    )
    entries = payload.get("entries", [])
    if not isinstance(entries, list):
        return False, "scanner JSON entries field is not a list"
    if len(entries) != 8:
        return False, f"expected 8 Phase 1F inventory entries, found {len(entries)}"
    unexpected = [
        entry
        for entry in entries
        if isinstance(entry, dict)
        and entry.get("path") != "compiler_impl/src/safe_frontend-check_resolve.adb"
    ]
    if unexpected:
        return False, f"unexpected Phase 1F inventory path: {unexpected[0].get('path')}"
    baseline, message = read_baseline_payload()
    if baseline is None:
        return False, message
    ok, message = validate_entries(baseline, "baseline")
    if not ok:
        return False, message
    ok, message = compare_live_scan_to_baseline(payload, baseline)
    if not ok:
        return False, message
    if message:
        print(message)
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    payload, message = read_baseline_payload()
    if payload is None:
        return False, message
    return validate_entries(payload, "baseline")


def synthetic_entry(
    fingerprint: str,
    *,
    classification: str = baseline_audit_gate.ACCEPTED,
    rationale: str = "Accepted: synthetic Phase 1F test entry.",
) -> dict[str, object]:
    return {
        "fingerprint": fingerprint,
        "category": "no-return-helper-fallthrough",
        "pattern": "no-return-helper-statement",
        "path": "compiler_impl/src/synthetic.adb",
        "line": 1,
        "line_numbers": [1],
        "first_line_text": "Raise_Diag (Diag);",
        "line_text": "Raise_Diag (Diag);",
        "fallthrough_line": "return Default_Integer;",
        "fallthrough_line_number": 2,
        "multiplicity": 1,
        "classification": classification,
        "rationale": rationale,
        "follow_up": "Phase 1F resolver fallback cleanup PR",
    }


def run_inventory_gate_self_check_case() -> tuple[bool, str]:
    return baseline_audit_gate.run_gate_self_check(
        phase_label=PHASE_LABEL,
        synthetic_entry=synthetic_entry,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_dead_raise.CATEGORIES,
        valid_patterns=audit_dead_raise.PATTERNS,
    )


def run_no_return_pragma_parsing_case() -> tuple[bool, str]:
    names = audit_dead_raise.no_return_names_from_line("pragma No_Return (Raise_A, Raise_B);")
    if names != {"Raise_A", "Raise_B"}:
        return False, f"multi-name No_Return pragma parsed as {sorted(names)!r}"
    commented = audit_dead_raise.no_return_names_from_line("-- pragma No_Return (Ignored);")
    literal = audit_dead_raise.no_return_names_from_line('Text := "pragma No_Return (Ignored);";')
    if commented or literal:
        return False, "No_Return pragma parser should ignore comments and string literals"
    return True, ""


def synthetic_scan(source: str) -> list[dict[str, object]]:
    path = REPO_ROOT / "compiler_impl" / "src" / "synthetic.adb"
    entries = audit_dead_raise.scan_source(
        path,
        source,
        no_return_names={"Raise_Diag"},
        prior={},
    )
    return list(entries.values())


def run_helper_call_fallthrough_case() -> tuple[bool, str]:
    entries = synthetic_scan(
        """
procedure Demo is
begin
   Raise_Diag (Diag);
   return Default_Integer;
end Demo;
"""
    )
    if len(entries) != 1:
        return False, f"expected one helper-call fallthrough, found {len(entries)}"
    entry = entries[0]
    if entry.get("category") != "no-return-helper-fallthrough":
        return False, f"unexpected category {entry.get('category')}"
    if entry.get("fallthrough_line") != "return Default_Integer;":
        return False, f"unexpected fallthrough {entry.get('fallthrough_line')!r}"
    return True, ""


def run_direct_raise_fallthrough_case() -> tuple[bool, str]:
    entries = synthetic_scan(
        """
procedure Demo is
begin
   raise Program_Error;
   Result := 1;
end Demo;
"""
    )
    if len(entries) != 1:
        return False, f"expected one direct-raise fallthrough, found {len(entries)}"
    if entries[0].get("category") != "direct-raise-fallthrough":
        return False, f"unexpected category {entries[0].get('category')}"
    return True, ""


def run_delimiter_only_case() -> tuple[bool, str]:
    entries = synthetic_scan(
        """
procedure Demo is
begin
   Raise_Diag (Diag);
end Demo;
"""
    )
    if entries:
        return False, "delimiter after no-return helper should not be reported as fallthrough"
    return True, ""


def run_branch_boundary_case() -> tuple[bool, str]:
    entries = synthetic_scan(
        """
function Demo return Integer is
begin
   if Failed then
      Raise_Diag (Diag);
   end if;
   return 1;
end Demo;
"""
    )
    if entries:
        return False, "fallthrough after end if is reachable when the branch is not taken"
    return True, ""


def run_nested_block_case() -> tuple[bool, str]:
    entries = synthetic_scan(
        """
function Demo return Integer is
begin
   declare
      Diag : Diagnostic;
   begin
      Raise_Diag (Diag);
   end;
   return Default_Integer;
end Demo;
"""
    )
    if len(entries) != 1:
        return False, f"expected one nested-block fallthrough, found {len(entries)}"
    if entries[0].get("pattern") != "no-return-helper-nested-block":
        return False, f"unexpected pattern {entries[0].get('pattern')}"
    return True, ""


def run_comment_and_string_case() -> tuple[bool, str]:
    entries = synthetic_scan(
        """
procedure Demo is
begin
   --  Raise_Diag (Diag);
   Message := "Raise_Diag (Diag);";
   return Default_Integer;
end Demo;
"""
    )
    if entries:
        return False, "comments and string-literal helper names should not be scanned"
    return True, ""


def run_dead_raise_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1f-dead-raise-audit:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:gate-self-check",
        run_inventory_gate_self_check_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:no-return-pragma-parsing",
        run_no_return_pragma_parsing_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:helper-call-fallthrough",
        run_helper_call_fallthrough_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:direct-raise-fallthrough",
        run_direct_raise_fallthrough_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:delimiter-only",
        run_delimiter_only_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:branch-boundary",
        run_branch_boundary_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:nested-block",
        run_nested_block_case(),
    )
    passed += record_result(
        failures,
        "phase1f-dead-raise-audit:comment-and-string",
        run_comment_and_string_case(),
    )
    return passed, 0, failures
