"""Inventory-mode checks for the Phase 1I.C schema-vs-doc alignment scanner."""

from __future__ import annotations

import json
import subprocess
import sys
from collections import Counter
from copy import deepcopy

import audit_docs_schema_alignment
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_docs_schema_alignment.py"
BASELINE_PATH = audit_docs_schema_alignment.BASELINE_PATH
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


def payload_without_line_positions(payload: dict[str, object]) -> dict[str, object]:
    normalized = deepcopy(payload)
    entries = normalized.get("entries")
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                entry.pop("line", None)
    return normalized


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


def read_baseline_payload() -> tuple[dict[str, object] | None, str]:
    return baseline_audit_gate.read_baseline_payload(BASELINE_PATH, repo_root=REPO_ROOT)


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
    ok, message = validate_entries(baseline, "baseline")
    if not ok:
        return False, message
    # Schema/documentation claims are content-anchored; line-only display
    # metadata may drift when nearby prose changes.
    if payload_without_line_positions(payload) != payload_without_line_positions(baseline):
        return (
            False,
            "Phase 1I.C live scanner JSON differs from committed baseline "
            "outside line-only display metadata",
        )
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    payload, message = read_baseline_payload()
    if payload is None:
        return False, message
    ok, message = validate_entries(payload, "baseline")
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
