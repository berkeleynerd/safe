"""Shared baseline-gate checks for audit scanner tests."""

from __future__ import annotations

import json
from collections.abc import Callable, Container, Iterable
from pathlib import Path


ACCEPTED = "accepted-with-rationale"
VALID_CLASSIFICATIONS = {
    "candidate",
    "needs-repro",
    "confirmed-defect",
    ACCEPTED,
}

Entry = dict[str, object]
Payload = dict[str, object]
CaseResult = tuple[bool, str]


def entries_for(payload: Payload) -> list[Entry]:
    entries = payload["entries"]
    if not isinstance(entries, list):
        raise ValueError(f"entries field is not a list: {type(entries)!r}")
    return [entry for entry in entries if isinstance(entry, dict)]


def fingerprint_map(payload: Payload) -> dict[str, Entry]:
    return {str(entry["fingerprint"]): entry for entry in entries_for(payload)}


def describe_entry(entry: Entry) -> str:
    return (
        f"{entry.get('fingerprint')} "
        f"{entry.get('category')} "
        f"{entry.get('path')}:{entry.get('line')} "
        f"{entry.get('pattern')}"
    )


def validate_entries(
    payload: object,
    label: str,
    *,
    required_fields: Iterable[str],
    valid_categories: Container[str] | None = None,
    valid_patterns: Container[str] | None = None,
    valid_classifications: Container[str] = VALID_CLASSIFICATIONS,
) -> CaseResult:
    if not isinstance(payload, dict):
        return False, f"{label} top-level value is not an object"
    entries = payload.get("entries")
    if not isinstance(entries, list):
        return False, f"{label} missing entries list"
    fields = tuple(required_fields)
    fingerprints: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            return False, f"{label} entry is not an object"
        for field in fields:
            if field not in entry:
                return False, f"{label} entry missing {field}"
        fingerprint = entry.get("fingerprint")
        if not isinstance(fingerprint, str) or not fingerprint:
            return False, f"{label} entry missing fingerprint"
        if fingerprint in fingerprints:
            return False, f"duplicate {label} fingerprint {fingerprint}"
        fingerprints.add(fingerprint)
        category = entry.get("category")
        if valid_categories is not None and category not in valid_categories:
            return False, f"invalid {label} category {category!r}"
        pattern = entry.get("pattern")
        if valid_patterns is not None and pattern not in valid_patterns:
            return False, f"invalid {label} pattern {pattern!r}"
        classification = entry.get("classification")
        if classification not in valid_classifications:
            return False, f"invalid {label} classification {classification!r}"
    return True, ""


def read_baseline_payload(
    baseline_path: Path,
    *,
    repo_root: Path,
) -> tuple[Payload | None, str]:
    if not baseline_path.exists():
        return None, f"missing baseline {baseline_path.relative_to(repo_root)}"
    try:
        payload = json.loads(baseline_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return None, f"invalid baseline JSON: {exc}"
    if not isinstance(payload, dict):
        return None, "baseline top-level value is not an object"
    return payload, ""


def validate_closed_baseline(
    payload: Payload,
    *,
    phase_label: str,
    required_fields: Iterable[str],
    valid_categories: Container[str] | None = None,
    valid_patterns: Container[str] | None = None,
) -> CaseResult:
    ok, message = validate_entries(
        payload,
        "baseline",
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if not ok:
        return False, message
    for entry in entries_for(payload):
        classification = entry.get("classification")
        if classification != ACCEPTED:
            return (
                False,
                f"closed {phase_label} baseline may only contain "
                f"{ACCEPTED!r}; found {classification!r} at {describe_entry(entry)}",
            )
        rationale = entry.get("rationale")
        if not isinstance(rationale, str) or not rationale.strip():
            return False, f"accepted baseline entry missing rationale: {describe_entry(entry)}"
    return True, ""


def compare_live_scan_to_baseline(
    live_payload: Payload,
    baseline_payload: Payload,
    *,
    phase_label: str,
    required_fields: Iterable[str],
    valid_categories: Container[str] | None = None,
    valid_patterns: Container[str] | None = None,
) -> CaseResult:
    ok, message = validate_entries(
        live_payload,
        "live scan",
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if not ok:
        return False, message
    ok, message = validate_entries(
        baseline_payload,
        "baseline",
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if not ok:
        return False, message
    live = fingerprint_map(live_payload)
    baseline = fingerprint_map(baseline_payload)
    new_fingerprints = sorted(set(live) - set(baseline))
    missing_fingerprints = sorted(set(baseline) - set(live))
    if new_fingerprints:
        examples = "; ".join(
            describe_entry(live[fingerprint]) for fingerprint in new_fingerprints[:5]
        )
        suffix = "" if len(new_fingerprints) <= 5 else f"; ... {len(new_fingerprints) - 5} more"
        message = (
            f"{phase_label} audit found "
            f"{len(new_fingerprints)} new fingerprint(s) outside the baseline: "
            f"{examples}{suffix}"
        )
        if missing_fingerprints:
            missing_examples = "; ".join(
                describe_entry(baseline[fingerprint]) for fingerprint in missing_fingerprints[:5]
            )
            missing_suffix = (
                ""
                if len(missing_fingerprints) <= 5
                else f"; ... {len(missing_fingerprints) - 5} more"
            )
            message += (
                ". Baseline drift also found "
                f"{len(missing_fingerprints)} fingerprint(s) no longer in live scan "
                f"(report-only): {missing_examples}{missing_suffix}"
            )
        return False, message
    if missing_fingerprints:
        examples = "; ".join(
            describe_entry(baseline[fingerprint]) for fingerprint in missing_fingerprints[:5]
        )
        suffix = (
            ""
            if len(missing_fingerprints) <= 5
            else f"; ... {len(missing_fingerprints) - 5} more"
        )
        return (
            True,
            f"{phase_label} audit baseline drift: "
            f"{len(missing_fingerprints)} fingerprint(s) no longer in live scan "
            f"(report-only): {examples}{suffix}",
        )
    return True, ""


def run_gate_self_check(
    *,
    phase_label: str,
    synthetic_entry: Callable[..., Entry],
    required_fields: Iterable[str],
    valid_categories: Container[str] | None = None,
    valid_patterns: Container[str] | None = None,
) -> CaseResult:
    known_entry = synthetic_entry("known")
    baseline = {"entries": [known_entry]}
    new_entry = synthetic_entry("new")
    live_with_new = {"entries": [synthetic_entry("known"), new_entry]}
    ok, message = compare_live_scan_to_baseline(
        live_with_new,
        baseline,
        phase_label=phase_label,
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if ok or describe_entry(new_entry) not in message:
        return False, "new live fingerprint outside baseline did not fail gate"

    live_missing = {"entries": []}
    ok, message = compare_live_scan_to_baseline(
        live_missing,
        baseline,
        phase_label=phase_label,
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if not ok or describe_entry(known_entry) not in message:
        return False, f"missing live fingerprint should be reported only, got: {message}"

    gone_entry = synthetic_entry("gone")
    mixed_baseline = {"entries": [known_entry, gone_entry]}
    mixed_live = {"entries": [synthetic_entry("known"), new_entry]}
    ok, message = compare_live_scan_to_baseline(
        mixed_live,
        mixed_baseline,
        phase_label=phase_label,
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if ok or describe_entry(new_entry) not in message or describe_entry(gone_entry) not in message:
        return False, f"mixed new/missing fingerprints should both be reported, got: {message}"

    open_baseline = {"entries": [synthetic_entry("known", classification="candidate")]}
    ok, message = validate_closed_baseline(
        open_baseline,
        phase_label=phase_label,
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if ok or "candidate" not in message:
        return False, "open baseline classification did not fail closed-baseline validation"

    empty_rationale = {"entries": [synthetic_entry("known", rationale="")]}
    ok, message = validate_closed_baseline(
        empty_rationale,
        phase_label=phase_label,
        required_fields=required_fields,
        valid_categories=valid_categories,
        valid_patterns=valid_patterns,
    )
    if ok or "rationale" not in message:
        return False, "accepted baseline entry with empty rationale did not fail validation"

    return True, ""
