"""Baseline checks for the Phase 1G spec/body contract scanner."""

from __future__ import annotations

import json
import subprocess
import sys

import audit_spec_body_contract
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_spec_body_contract.py"
BASELINE_PATH = audit_spec_body_contract.BASELINE_PATH
PHASE_LABEL = "Phase 1G spec/body contract"
ACCEPTED = baseline_audit_gate.ACCEPTED
REQUIRED_FIELDS = (
    "fingerprint",
    "category",
    "pattern",
    "path",
    "line",
    "line_numbers",
    "first_line_text",
    "line_text",
    "helper_name",
    "declaration_line",
    "body_path",
    "body_line",
    "body_status",
    "classification",
    "rationale",
    "follow_up",
)


def validate_body_statuses(payload: dict[str, object], label: str) -> tuple[bool, str]:
    for entry in baseline_audit_gate.entries_for(payload):
        body_status = entry.get("body_status")
        if body_status not in audit_spec_body_contract.BODY_STATUSES:
            return False, f"invalid {label} body_status {body_status!r}"
    return True, ""


def validate_entries(payload: object, label: str) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_entries(
        payload,
        label,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_spec_body_contract.CATEGORIES,
        valid_patterns=audit_spec_body_contract.PATTERNS,
    )
    if not ok:
        return False, message
    assert isinstance(payload, dict)
    return validate_body_statuses(payload, label)


def validate_closed_baseline(payload: dict[str, object]) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_closed_baseline(
        payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_spec_body_contract.CATEGORIES,
        valid_patterns=audit_spec_body_contract.PATTERNS,
    )
    if not ok:
        return False, message
    return validate_body_statuses(payload, "baseline")


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
        valid_categories=audit_spec_body_contract.CATEGORIES,
        valid_patterns=audit_spec_body_contract.PATTERNS,
    )


def compare_body_status_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    """Validate cross-file body metadata separately from the spec fingerprint."""

    live = baseline_audit_gate.fingerprint_map(live_payload)
    baseline = baseline_audit_gate.fingerprint_map(baseline_payload)
    for fingerprint in sorted(set(live) & set(baseline)):
        live_status = live[fingerprint].get("body_status")
        baseline_status = baseline[fingerprint].get("body_status")
        if live_status != baseline_status:
            helper = live[fingerprint].get("helper_name")
            return (
                False,
                f"{PHASE_LABEL} body_status drift for {helper}: "
                f"{baseline_status!r} -> {live_status!r} at "
                f"{baseline_audit_gate.describe_entry(live[fingerprint])}",
            )
    return True, ""


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
    audit_spec_body_contract.print_summary(
        payload,
        baseline_entries=audit_spec_body_contract.existing_classifications(),
    )
    baseline, message = read_baseline_payload()
    if baseline is None:
        return False, message
    ok, message = validate_closed_baseline(baseline)
    if not ok:
        return False, message
    ok, message = compare_live_scan_to_baseline(payload, baseline)
    if not ok:
        return False, message
    # Missing fingerprints are report-only drift; surface the helper message when present.
    if message:
        print(message)
    ok, message = compare_body_status_to_baseline(payload, baseline)
    if not ok:
        return False, message
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    payload, message = read_baseline_payload()
    if payload is None:
        return False, message
    return validate_closed_baseline(payload)


def synthetic_entry(
    fingerprint: str,
    *,
    classification: str = ACCEPTED,
    rationale: str = "Accepted: synthetic Phase 1G test entry.",
    body_status: str = "raises",
) -> dict[str, object]:
    return {
        "fingerprint": fingerprint,
        "category": "spec-no-return-contract",
        "pattern": "spec-no-return-pragma",
        "path": "compiler_impl/src/synthetic.ads",
        "line": 1,
        "line_numbers": [1],
        "first_line_text": "pragma No_Return (Raise_Diag);",
        "line_text": "pragma No_Return (Raise_Diag);",
        "helper_name": "Raise_Diag",
        "declaration_line": 1,
        "body_path": "compiler_impl/src/synthetic.adb",
        "body_line": 1,
        "body_status": body_status,
        "classification": classification,
        "rationale": rationale,
        "follow_up": "Phase 1G spec/body contract triage PR",
    }


def run_gate_self_check_case() -> tuple[bool, str]:
    known_entry = synthetic_entry("known")
    ok, message = compare_live_scan_to_baseline(
        {"entries": [known_entry]},
        {"entries": [synthetic_entry("known")]},
    )
    if not ok or message:
        return False, f"known live fingerprint should pass silently, got: {message}"
    return baseline_audit_gate.run_gate_self_check(
        phase_label=PHASE_LABEL,
        synthetic_entry=synthetic_entry,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_spec_body_contract.CATEGORIES,
        valid_patterns=audit_spec_body_contract.PATTERNS,
    )


def run_spec_contract_parsing_case() -> tuple[bool, str]:
    contracts = audit_spec_body_contract.collect_spec_contracts(
        """
package Synthetic is
   procedure Raise_Diag (Message : String);
   pragma No_Return (Raise_Diag);
end Synthetic;
""",
    )
    if len(contracts) != 1:
        return False, f"expected one No_Return contract, found {len(contracts)}"
    contract = contracts[0]
    if contract.helper_name != "Raise_Diag" or contract.declaration_line != 3:
        return False, f"unexpected contract {contract!r}"
    return True, ""


def run_comment_and_string_case() -> tuple[bool, str]:
    character_literal_line = """Quote : constant Character := '"'; procedure Raise_Diag;"""
    for stripper in (
        audit_spec_body_contract.strip_comments_keep_strings,
        audit_spec_body_contract.strip_comments_and_strings,
    ):
        stripped = stripper(character_literal_line)
        if "procedure Raise_Diag" not in stripped:
            return False, (
                f"{stripper.__name__} dropped text after double-quote character literal"
            )
    contracts = audit_spec_body_contract.collect_spec_contracts(
        """
package Synthetic is
   Message : constant String := "pragma No_Return (Ignored);";
   -- pragma No_Return (Ignored);
   procedure Raise_Diag;
   pragma No_Return (Raise_Diag);
end Synthetic;
""",
    )
    names = [contract.helper_name for contract in contracts]
    if names != ["Raise_Diag"]:
        return False, f"comment/string No_Return text should be ignored, got {names!r}"
    return True, ""


def run_overloaded_declaration_line_case() -> tuple[bool, str]:
    contracts = audit_spec_body_contract.collect_spec_contracts(
        """
package Synthetic is
   procedure Raise_Diag (Code : Integer);
   procedure Raise_Diag (Message : String);
   pragma No_Return (Raise_Diag);
end Synthetic;
""",
    )
    if len(contracts) != 1:
        return False, f"expected one No_Return contract, found {len(contracts)}"
    if contracts[0].declaration_line != 4:
        return False, f"expected nearest overload declaration line 4, got {contracts[0].declaration_line}"
    return True, ""


def body_status_fixture(source: str, *, helper_name: str = "Raise_Diag") -> str:
    status, _line = audit_spec_body_contract.body_status_for_source(
        helper_name,
        source,
        known_no_return_names={"Raise_Internal"},
    )
    return status


def run_body_status_cases() -> tuple[bool, str]:
    cases = {
        "raises": """
procedure Raise_Diag is
begin
   raise Program_Error;
end Raise_Diag;
""",
        "helper-call-raises": """
procedure Raise_Diag is
begin
   Raise_Internal ("failed");
end Raise_Diag;
""",
        "anonymous-end-raises": """
procedure Raise_Diag is
begin
   raise Program_Error;
end;
""",
        "nested-block-raises": """
procedure Raise_Diag is
begin
   declare
      Reason : Integer := 1;
   begin
      raise Program_Error;
   end;
end Raise_Diag;
""",
        "anonymous-end-nested-block-tail-helper": """
procedure Raise_Diag is
begin
   declare
   begin
      null;
   end;
   Raise_Internal ("failed");
end;
""",
        "returns": """
procedure Raise_Diag is
begin
   Result := 1;
end Raise_Diag;
""",
        "unknown": """
procedure Raise_Diag is
begin
   if Failed then
      raise Program_Error;
   end if;
end Raise_Diag;
""",
        "exception-handler-only": """
procedure Raise_Diag is
begin
exception
   when others =>
      raise Program_Error;
end Raise_Diag;
""",
        "self-recursive-unknown": """
procedure Raise_Diag is
begin
   Raise_Diag;
end Raise_Diag;
""",
        "missing": """
package body Synthetic is
end Synthetic;
""",
    }
    expected = {
        "raises": "raises",
        "helper-call-raises": "raises",
        "anonymous-end-raises": "raises",
        "nested-block-raises": "raises",
        "anonymous-end-nested-block-tail-helper": "raises",
        "returns": "returns",
        "unknown": "unknown",
        "exception-handler-only": "unknown",
        "self-recursive-unknown": "unknown",
        "missing": "missing",
    }
    for name, source in cases.items():
        actual = body_status_fixture(source)
        if actual != expected[name]:
            return False, f"{name} body_status expected {expected[name]!r}, got {actual!r}"
    return True, ""


def run_body_line_case() -> tuple[bool, str]:
    status, line = audit_spec_body_contract.body_status_for_source(
        "Raise_Diag",
        """

procedure Raise_Diag is
begin
   raise Program_Error;
end Raise_Diag;
""",
        known_no_return_names=set(),
    )
    if status != "raises" or line != 3:
        return False, f"expected body line 3 with raises status, got line={line}, status={status}"
    return True, ""


def run_missing_body_file_case() -> tuple[bool, str]:
    body = audit_spec_body_contract.body_evidence_for(
        REPO_ROOT / "compiler_impl" / "src" / "synthetic_missing.ads",
        "Raise_Diag",
        known_no_return_names=set(),
    )
    if body.status != "missing" or body.line is not None:
        return False, f"missing body file should report missing, got {body!r}"
    return True, ""


def run_body_status_drift_case() -> tuple[bool, str]:
    baseline = {"entries": [synthetic_entry("same", body_status="raises")]}
    for drift_status in ("returns", "missing", "unknown"):
        live = {"entries": [synthetic_entry("same", body_status=drift_status)]}
        ok, message = compare_body_status_to_baseline(live, baseline)
        if ok or "raises" not in message or drift_status not in message:
            return (
                False,
                "body_status drift should fail with both statuses for "
                f"drift_status={drift_status!r}, got: {message}",
            )
    return True, ""


def run_spec_body_contract_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1g-spec-body-contract-audit:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:gate-self-check",
        run_gate_self_check_case(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:spec-contract-parsing",
        run_spec_contract_parsing_case(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:comment-and-string",
        run_comment_and_string_case(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:overloaded-declaration-line",
        run_overloaded_declaration_line_case(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:body-status",
        run_body_status_cases(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:body-line",
        run_body_line_case(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:missing-body-file",
        run_missing_body_file_case(),
    )
    passed += record_result(
        failures,
        "phase1g-spec-body-contract-audit:body-status-drift",
        run_body_status_drift_case(),
    )
    return passed, 0, failures
