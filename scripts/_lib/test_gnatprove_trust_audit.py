"""Baseline-gated checks for the Phase 1D GNATprove trust-boundary scanner."""

from __future__ import annotations

import json
import subprocess
import sys

import audit_gnatprove_trust
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_gnatprove_trust.py"
BASELINE_PATH = REPO_ROOT / "audit" / "phase1d_gnatprove_trust_baseline.json"
ACCEPTED = "accepted-with-rationale"
VALID_CLASSIFICATIONS = {
    "candidate",
    "needs-repro",
    "confirmed-defect",
    ACCEPTED,
}


def validate_entries(payload: object, label: str) -> tuple[bool, str]:
    if not isinstance(payload, dict):
        return False, f"{label} top-level value is not an object"
    entries = payload.get("entries")
    if not isinstance(entries, list):
        return False, f"{label} missing entries list"
    fingerprints: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            return False, f"{label} entry is not an object"
        for field in (
            "fingerprint",
            "category",
            "pattern",
            "path",
            "line",
            "line_numbers",
            "first_line_text",
            "line_text",
            "classification",
            "rationale",
            "follow_up",
        ):
            if field not in entry:
                return False, f"{label} entry missing {field}"
        fingerprint = entry.get("fingerprint")
        if not isinstance(fingerprint, str) or not fingerprint:
            return False, f"{label} entry missing fingerprint"
        if fingerprint in fingerprints:
            return False, f"duplicate {label} fingerprint {fingerprint}"
        fingerprints.add(fingerprint)
        classification = entry.get("classification")
        if classification not in VALID_CLASSIFICATIONS:
            return False, f"invalid {label} classification {classification!r}"
    return True, ""


def entries_for(payload: dict[str, object]) -> list[dict[str, object]]:
    entries = payload["entries"]
    if not isinstance(entries, list):
        raise ValueError(f"entries field is not a list: {type(entries)!r}")
    return [entry for entry in entries if isinstance(entry, dict)]


def fingerprint_map(payload: dict[str, object]) -> dict[str, dict[str, object]]:
    return {str(entry["fingerprint"]): entry for entry in entries_for(payload)}


def describe_entry(entry: dict[str, object]) -> str:
    return (
        f"{entry.get('fingerprint')} "
        f"{entry.get('category')} "
        f"{entry.get('path')}:{entry.get('line')} "
        f"{entry.get('pattern')}"
    )


def read_baseline_payload() -> tuple[dict[str, object] | None, str]:
    if not BASELINE_PATH.exists():
        return None, f"missing baseline {BASELINE_PATH.relative_to(REPO_ROOT)}"
    try:
        payload = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return None, f"invalid baseline JSON: {exc}"
    if not isinstance(payload, dict):
        return None, "baseline top-level value is not an object"
    return payload, ""


def validate_closed_baseline(payload: dict[str, object]) -> tuple[bool, str]:
    ok, message = validate_entries(payload, "baseline")
    if not ok:
        return False, message
    for entry in entries_for(payload):
        classification = entry.get("classification")
        if classification != ACCEPTED:
            return (
                False,
                "closed Phase 1D baseline may only contain "
                f"{ACCEPTED!r}; found {classification!r} at {describe_entry(entry)}",
            )
        rationale = entry.get("rationale")
        if not isinstance(rationale, str) or not rationale.strip():
            return False, f"accepted baseline entry missing rationale: {describe_entry(entry)}"
    return True, ""


def compare_live_scan_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    live = fingerprint_map(live_payload)
    baseline = fingerprint_map(baseline_payload)
    new_fingerprints = sorted(set(live) - set(baseline))
    if new_fingerprints:
        examples = "; ".join(
            describe_entry(live[fingerprint]) for fingerprint in new_fingerprints[:5]
        )
        suffix = "" if len(new_fingerprints) <= 5 else f"; ... {len(new_fingerprints) - 5} more"
        return (
            False,
            "Phase 1D GNATprove trust audit found "
            f"{len(new_fingerprints)} new fingerprint(s) outside the baseline: "
            f"{examples}{suffix}",
        )
    missing_fingerprints = sorted(set(baseline) - set(live))
    if missing_fingerprints:
        examples = "; ".join(
            describe_entry(baseline[fingerprint]) for fingerprint in missing_fingerprints[:5]
        )
        suffix = "" if len(missing_fingerprints) <= 5 else f"; ... {len(missing_fingerprints) - 5} more"
        return (
            True,
            "Phase 1D GNATprove trust audit baseline drift: "
            f"{len(missing_fingerprints)} fingerprint(s) no longer in live scan "
            f"(report-only): {examples}{suffix}",
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
    # Match Phase 1C audit behavior: run_tests.py emits audit summaries visibly.
    audit_gnatprove_trust.print_summary(
        payload,
        baseline_entries=audit_gnatprove_trust.existing_classifications(),
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
    return True, ""


def run_statement_scanner_case() -> tuple[bool, str]:
    source = (
        'pragma Annotate (GNATprove, Intentional, "overflow (see A-05); safe");\n'
        "Afterward;"
    )
    end = audit_gnatprove_trust.statement_end(source, 0)
    if end is None:
        return False, "statement scanner did not find pragma terminator"
    matched = source[:end]
    if '"overflow (see A-05); safe"' not in matched:
        return False, "statement scanner truncated string-literal punctuation"
    if matched.endswith("Afterward;"):
        return False, "statement scanner consumed the following statement"
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
    rationale: str = "Accepted: synthetic trust-boundary test entry.",
) -> dict[str, object]:
    return {
        "fingerprint": fingerprint,
        "category": "synthetic",
        "pattern": "synthetic-pattern",
        "path": "compiler_impl/src/synthetic.adb",
        "line": 1,
        "line_numbers": [1],
        "first_line_text": "pragma Synthetic;",
        "line_text": "pragma Synthetic;",
        "multiplicity": 1,
        "classification": classification,
        "rationale": rationale,
        "follow_up": "",
    }


def run_gate_self_check_case() -> tuple[bool, str]:
    known_entry = synthetic_entry("known")
    baseline = {"entries": [known_entry]}
    new_entry = synthetic_entry("new")
    live_with_new = {"entries": [synthetic_entry("known"), new_entry]}
    ok, message = compare_live_scan_to_baseline(live_with_new, baseline)
    if ok or describe_entry(new_entry) not in message:
        return False, "new live fingerprint outside baseline did not fail gate"

    live_missing = {"entries": []}
    ok, message = compare_live_scan_to_baseline(live_missing, baseline)
    if not ok or describe_entry(known_entry) not in message:
        return False, f"missing live fingerprint should be reported only, got: {message}"

    open_baseline = {"entries": [synthetic_entry("known", classification="candidate")]}
    ok, message = validate_closed_baseline(open_baseline)
    if ok or "candidate" not in message:
        return False, "open baseline classification did not fail closed-baseline validation"

    empty_rationale = {"entries": [synthetic_entry("known", rationale="")]}
    ok, message = validate_closed_baseline(empty_rationale)
    if ok or "rationale" not in message:
        return False, "accepted baseline entry with empty rationale did not fail validation"

    return True, ""


def run_gnatprove_trust_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1d-gnatprove-trust-audit:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1d-gnatprove-trust-audit:statement-scanner",
        run_statement_scanner_case(),
    )
    passed += record_result(
        failures,
        "phase1d-gnatprove-trust-audit:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1d-gnatprove-trust-audit:gate-self-check",
        run_gate_self_check_case(),
    )
    return passed, 0, failures
