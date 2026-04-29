"""Baseline-gated checks for the Phase 1I.C schema-vs-doc alignment scanner."""

from __future__ import annotations

import json
import subprocess
import sys
from collections import Counter

import audit_docs_schema_alignment
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_docs_schema_alignment.py"
BASELINE_PATH = audit_docs_schema_alignment.BASELINE_PATH
PHASE_LABEL = "Phase 1I.C schema-doc alignment"
ACCEPTED = baseline_audit_gate.ACCEPTED
REQUIRED_FIELDS = (
    "fingerprint",
    "category",
    "pattern",
    "path",
    "line",
    "claim_key",
    "claim_text",
    "verification_target",
    "doc_value",
    "actual_value",
    "alignment_status",
    "classification",
    "rationale",
    "follow_up",
)


def validate_alignment_statuses(payload: dict[str, object], label: str) -> tuple[bool, str]:
    for entry in baseline_audit_gate.entries_for(payload):
        status = entry.get("alignment_status")
        if status not in audit_docs_schema_alignment.ALIGNMENT_STATUSES:
            return False, f"invalid {label} alignment_status {status!r}"
    return True, ""


def validate_entries(payload: object, label: str) -> tuple[bool, str]:
    if not isinstance(payload, dict):
        return False, f"{label} is not a dict"
    ok, message = baseline_audit_gate.validate_entries(
        payload,
        label,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_schema_alignment.CATEGORIES,
        valid_patterns=audit_docs_schema_alignment.PATTERNS,
    )
    if not ok:
        return False, message
    return validate_alignment_statuses(payload, label)


def validate_closed_baseline(payload: dict[str, object]) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_closed_baseline(
        payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_schema_alignment.CATEGORIES,
        valid_patterns=audit_docs_schema_alignment.PATTERNS,
    )
    if not ok:
        return False, message
    return validate_alignment_statuses(payload, "baseline")


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
        valid_categories=audit_docs_schema_alignment.CATEGORIES,
        valid_patterns=audit_docs_schema_alignment.PATTERNS,
    )


def compare_alignment_metadata_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    """Validate content-derived claim metadata separately from line display drift."""

    live = baseline_audit_gate.fingerprint_map(live_payload)
    baseline = baseline_audit_gate.fingerprint_map(baseline_payload)
    fields = ("doc_value", "actual_value", "alignment_status")
    for fingerprint in sorted(set(live) & set(baseline)):
        for field in fields:
            live_value = live[fingerprint].get(field)
            baseline_value = baseline[fingerprint].get(field)
            if live_value != baseline_value:
                return (
                    False,
                    f"{PHASE_LABEL} {field} drift: {baseline_value!r} -> "
                    f"{live_value!r} at {baseline_audit_gate.describe_entry(live[fingerprint])}",
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
    baseline, message = read_baseline_payload()
    if baseline is None:
        return False, message
    ok, message = validate_closed_baseline(baseline)
    if not ok:
        return False, message
    ok, message = compare_live_scan_to_baseline(payload, baseline)
    if not ok:
        return False, message
    if message:
        print(message)
    ok, message = compare_alignment_metadata_to_baseline(payload, baseline)
    if not ok:
        return False, message
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    payload, message = read_baseline_payload()
    if payload is None:
        return False, message
    ok, message = validate_closed_baseline(payload)
    if not ok:
        return False, message
    classifications = Counter(
        entry.get("classification") for entry in baseline_audit_gate.entries_for(payload)
    )
    expected = Counter({"accepted-with-rationale": 118})
    if classifications != expected:
        return False, f"unexpected Phase 1I.C triage distribution {classifications}"
    confirmed_keys = sorted(
        str(entry.get("claim_key", ""))
        for entry in baseline_audit_gate.entries_for(payload)
        if entry.get("classification") == "confirmed-defect"
    )
    if confirmed_keys:
        return False, f"unexpected Phase 1I.C confirmed-defect keys {confirmed_keys}"
    return True, ""


def synthetic_entry(
    fingerprint: str,
    *,
    classification: str = ACCEPTED,
    rationale: str = "Accepted: synthetic Phase 1I.C schema-doc entry.",
    line: int = 1,
    alignment_status: str = "aligned",
    doc_value: object = "Example",
    actual_value: object = "present",
) -> dict[str, object]:
    return {
        "fingerprint": fingerprint,
        "category": "schema-ast-reference",
        "pattern": "translation-rules-ast-node",
        "path": "compiler/translation_rules.md",
        "line": line,
        "claim_key": "ast-node:Example",
        "claim_text": "AST: `Example`",
        "verification_target": "compiler/ast_schema.json:nodes.Example",
        "doc_value": doc_value,
        "actual_value": actual_value,
        "alignment_status": alignment_status,
        "classification": classification,
        "rationale": rationale,
        "follow_up": "",
    }


def run_gate_self_check_case() -> tuple[bool, str]:
    ok, message = compare_live_scan_to_baseline(
        {"entries": [synthetic_entry("known")]},
        {"entries": [synthetic_entry("known")]},
    )
    if not ok or message:
        return False, f"known live fingerprint should pass silently, got: {message}"
    return baseline_audit_gate.run_gate_self_check(
        phase_label=PHASE_LABEL,
        synthetic_entry=synthetic_entry,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_schema_alignment.CATEGORIES,
        valid_patterns=audit_docs_schema_alignment.PATTERNS,
    )


def run_alignment_metadata_drift_gate_case() -> tuple[bool, str]:
    baseline = {
        "entries": [
            synthetic_entry(
                "same",
                alignment_status="aligned",
                doc_value="Example",
                actual_value="present",
            )
        ]
    }
    for drift_status in ("mismatch", "missing-target"):
        live = {"entries": [synthetic_entry("same", alignment_status=drift_status)]}
        ok, message = compare_alignment_metadata_to_baseline(live, baseline)
        if ok or "alignment_status" not in message or drift_status not in message:
            return False, f"alignment_status drift should fail, got: {message}"
    drift_cases = {
        "doc_value": synthetic_entry("same", doc_value="Other"),
        "actual_value": synthetic_entry("same", actual_value="missing"),
    }
    for field, entry in drift_cases.items():
        ok, message = compare_alignment_metadata_to_baseline({"entries": [entry]}, baseline)
        if ok or field not in message:
            return False, f"{field} drift should fail, got: {message}"
    return True, ""


def run_line_only_drift_gate_case() -> tuple[bool, str]:
    baseline = {"entries": [synthetic_entry("same", line=1)]}
    live = {"entries": [synthetic_entry("same", line=99)]}
    ok, message = compare_live_scan_to_baseline(live, baseline)
    if not ok or message:
        return False, f"line-only drift should not fail fingerprint gate, got: {message}"
    ok, message = compare_alignment_metadata_to_baseline(live, baseline)
    if not ok or message:
        return False, f"line-only drift should not fail metadata gate, got: {message}"
    return True, ""


def run_ast_reference_case() -> tuple[bool, str]:
    claims = list(audit_docs_schema_alignment.iter_ast_reference_claims())
    stale = [claim for claim in claims if claim.claim_key == "ast-node:AccessToObjectDefinition"]
    if stale:
        return False, "AccessToObjectDefinition should no longer be documented as an AST node"
    if len(claims) != 30:
        return False, f"expected 30 AST reference claims, got {len(claims)}"
    if any(claim.alignment_status != "aligned" for claim in claims):
        return False, "AST reference scanner should find only aligned references"
    return True, ""


def run_baseline_count_alignment_case() -> tuple[bool, str]:
    payload = audit_docs_schema_alignment.scan()
    entries = baseline_audit_gate.entries_for(payload)
    by_key = {entry["claim_key"]: entry for entry in entries}
    target_bits = by_key.get("1C:Baseline counts:target-bits")
    if target_bits is None:
        return False, "missing Phase 1C target-bits count claim"
    if (
        target_bits.get("doc_value") != 97
        or target_bits.get("actual_value") != 97
        or target_bits.get("alignment_status") != "aligned"
    ):
        return False, f"unexpected target-bits count claim {target_bits!r}"
    target_bits_classification = by_key.get("1C:Baseline counts:target-bits:classification")
    if target_bits_classification is None:
        return False, "missing Phase 1C target-bits classification claim"
    if (
        target_bits_classification.get("doc_value") != "accepted-with-rationale"
        or target_bits_classification.get("actual_value") != "accepted-with-rationale"
        or target_bits_classification.get("alignment_status") != "aligned"
    ):
        return (
            False,
            f"unexpected target-bits classification claim {target_bits_classification!r}",
        )
    prose_total = by_key.get("1C:prose-summary:total")
    if prose_total is None:
        return False, "missing Phase 1C prose total claim"
    if (
        prose_total.get("doc_value") != 245
        or prose_total.get("actual_value") != 245
        or prose_total.get("alignment_status") != "aligned"
    ):
        return False, f"unexpected Phase 1C prose total claim {prose_total!r}"
    prose_classification = by_key.get("1C:prose-summary:classification")
    if prose_classification is None:
        return False, "missing Phase 1C prose classification claim"
    if (
        prose_classification.get("doc_value") != "accepted-with-rationale:245, candidate:0"
        or prose_classification.get("actual_value") != "accepted-with-rationale:245, candidate:0"
        or prose_classification.get("alignment_status") != "aligned"
    ):
        return False, f"unexpected Phase 1C prose classification claim {prose_classification!r}"
    return True, ""


def run_artifact_contract_case() -> tuple[bool, str]:
    claims = list(audit_docs_schema_alignment.iter_artifact_contract_claims())
    if len(claims) != 15:
        return False, f"expected 15 artifact-contract claims, got {len(claims)}"
    by_key = {claim.claim_key: claim for claim in claims}
    diagnostics = by_key.get("diagnostics-format-version")
    if diagnostics is None or diagnostics.alignment_status != "aligned":
        return False, "diagnostics-v0 artifact-contract claim should align"
    target_bits = by_key.get("target-bits-equality")
    if target_bits is None or target_bits.actual_value != "typed=mir=safei":
        return False, "target_bits equality claim should verify typed=mir=safei"
    if any(claim.alignment_status != "aligned" for claim in claims):
        return False, "artifact-contract v1 curated claims should all align"
    return True, ""


def run_frozen_commit_case() -> tuple[bool, str]:
    claims = list(audit_docs_schema_alignment.iter_frozen_commit_claims())
    if len(claims) != 3:
        return False, f"expected 3 frozen-commit claims, got {len(claims)}"
    if any(claim.alignment_status != "aligned" for claim in claims):
        return False, "frozen-commit claims should align"
    return True, ""


def run_fingerprint_case() -> tuple[bool, str]:
    base = audit_docs_schema_alignment.Claim(
        category="schema-ast-reference",
        pattern="translation-rules-ast-node",
        path=REPO_ROOT / "compiler" / "translation_rules.md",
        line=10,
        claim_key="ast-node:Example",
        claim_text="AST: `Example`",
        verification_target="compiler/ast_schema.json:nodes.Example",
        doc_value="Example",
        actual_value="present",
        alignment_status="aligned",
    )
    shifted = audit_docs_schema_alignment.Claim(
        category=base.category,
        pattern=base.pattern,
        path=base.path,
        line=99,
        claim_key=base.claim_key,
        claim_text=base.claim_text,
        verification_target=base.verification_target,
        doc_value=base.doc_value,
        actual_value=base.actual_value,
        alignment_status=base.alignment_status,
    )
    changed_target = audit_docs_schema_alignment.Claim(
        category=base.category,
        pattern=base.pattern,
        path=base.path,
        line=base.line,
        claim_key=base.claim_key,
        claim_text=base.claim_text,
        verification_target="compiler/ast_schema.json:nodes.Other",
        doc_value=base.doc_value,
        actual_value=base.actual_value,
        alignment_status=base.alignment_status,
    )
    if audit_docs_schema_alignment.fingerprint_for(base) != (
        audit_docs_schema_alignment.fingerprint_for(shifted)
    ):
        return False, "fingerprint should ignore line-only display metadata"
    if audit_docs_schema_alignment.fingerprint_for(base) == (
        audit_docs_schema_alignment.fingerprint_for(changed_target)
    ):
        return False, "fingerprint should include verification target"
    return True, ""


def run_docs_schema_alignment_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1i-schema-doc-alignment:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:gate-self-check",
        run_gate_self_check_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:alignment-metadata-drift-gate",
        run_alignment_metadata_drift_gate_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:line-only-drift-gate",
        run_line_only_drift_gate_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:ast-reference",
        run_ast_reference_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:baseline-count-alignment",
        run_baseline_count_alignment_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:artifact-contract",
        run_artifact_contract_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:frozen-commit",
        run_frozen_commit_case(),
    )
    passed += record_result(
        failures,
        "phase1i-schema-doc-alignment:fingerprint",
        run_fingerprint_case(),
    )
    return passed, 0, failures
