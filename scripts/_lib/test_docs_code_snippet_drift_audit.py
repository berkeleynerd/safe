"""Baseline-gated checks for the Phase 1I.B docs code-snippet drift scanner."""

from __future__ import annotations

import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

import audit_docs_code_snippet_drift
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_docs_code_snippet_drift.py"
BASELINE_PATH = audit_docs_code_snippet_drift.BASELINE_PATH
PHASE_LABEL = "Phase 1I.B docs code-snippet drift"
ACCEPTED = baseline_audit_gate.ACCEPTED
REQUIRED_FIELDS = (
    "fingerprint",
    "category",
    "pattern",
    "path",
    "block_index",
    "start_line",
    "end_line",
    "language",
    "first_line_text",
    "snippet_line_count",
    "snippet_digest",
    "classification",
    "rationale",
    "follow_up",
)
def validate_entries(payload: object, label: str) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_entries(
        payload,
        label,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_code_snippet_drift.CATEGORIES,
        valid_patterns=audit_docs_code_snippet_drift.PATTERNS,
    )
    if not ok:
        return False, message
    for entry in baseline_audit_gate.entries_for(payload):
        digest = entry.get("snippet_digest")
        if not isinstance(digest, str) or len(digest) != 64:
            return False, f"invalid {label} snippet_digest {digest!r}"
    return True, ""


def read_baseline_payload() -> tuple[dict[str, object] | None, str]:
    return baseline_audit_gate.read_baseline_payload(BASELINE_PATH, repo_root=REPO_ROOT)


def validate_closed_baseline(payload: dict[str, object]) -> tuple[bool, str]:
    return baseline_audit_gate.validate_closed_baseline(
        payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_code_snippet_drift.CATEGORIES,
        valid_patterns=audit_docs_code_snippet_drift.PATTERNS,
    )


def compare_live_scan_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    return baseline_audit_gate.compare_live_scan_to_baseline(
        live_payload,
        baseline_payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_code_snippet_drift.CATEGORIES,
        valid_patterns=audit_docs_code_snippet_drift.PATTERNS,
    )


def compare_snippet_digest_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    live = baseline_audit_gate.fingerprint_map(live_payload)
    baseline = baseline_audit_gate.fingerprint_map(baseline_payload)
    for fingerprint in sorted(set(live) & set(baseline)):
        live_digest = live[fingerprint].get("snippet_digest")
        baseline_digest = baseline[fingerprint].get("snippet_digest")
        if live_digest != baseline_digest:
            return (
                False,
                f"{PHASE_LABEL} snippet_digest drift: {baseline_digest!r} -> "
                f"{live_digest!r} at {baseline_audit_gate.describe_entry(live[fingerprint])}",
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
    audit_docs_code_snippet_drift.print_summary(
        payload,
        baseline_entries=audit_docs_code_snippet_drift.existing_classifications(),
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
    if message:
        print(message)
    ok, message = compare_snippet_digest_to_baseline(payload, baseline)
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
    expected = Counter({"accepted-with-rationale": 291})
    if classifications != expected:
        return False, f"unexpected Phase 1I.B triage distribution {classifications}"
    return True, ""


def synthetic_entry(
    fingerprint: str,
    *,
    classification: str = ACCEPTED,
    rationale: str = "Accepted: synthetic Phase 1I.B code-snippet entry.",
    snippet_digest: str = "0" * 64,
    start_line: int = 1,
    end_line: int = 3,
) -> dict[str, object]:
    return {
        "fingerprint": fingerprint,
        "category": "current-safe-snippet",
        "pattern": "fenced-code-block",
        "path": "docs/synthetic.md",
        "block_index": 1,
        "start_line": start_line,
        "end_line": end_line,
        "language": "safe",
        "first_line_text": "package Demo is",
        "snippet_line_count": 1,
        "snippet_digest": snippet_digest,
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
        valid_categories=audit_docs_code_snippet_drift.CATEGORIES,
        valid_patterns=audit_docs_code_snippet_drift.PATTERNS,
    )


def run_snippet_digest_drift_gate_case() -> tuple[bool, str]:
    baseline = {"entries": [synthetic_entry("same", snippet_digest="0" * 64)]}
    live = {"entries": [synthetic_entry("same", snippet_digest="1" * 64)]}
    ok, message = compare_snippet_digest_to_baseline(live, baseline)
    if ok or "snippet_digest" not in message:
        return False, f"snippet_digest drift should fail, got: {message}"
    return True, ""


def run_line_only_drift_gate_case() -> tuple[bool, str]:
    baseline = {"entries": [synthetic_entry("same", start_line=1, end_line=3)]}
    live = {"entries": [synthetic_entry("same", start_line=9, end_line=11)]}
    ok, message = compare_live_scan_to_baseline(live, baseline)
    if not ok or message:
        return False, f"line-only drift should not fail fingerprint gate, got: {message}"
    ok, message = compare_snippet_digest_to_baseline(live, baseline)
    if not ok or message:
        return False, f"line-only drift should not fail digest gate, got: {message}"
    return True, ""


def run_fence_extraction_case() -> tuple[bool, str]:
    doc_path = REPO_ROOT / "docs" / "synthetic.md"
    lines = [
        "before",
        "````Safe ignored extra info",
        "package Demo is",
        "```python",
        "end Demo;",
        "````",
        "```",
        "plain",
        "```",
        "   ```bash",
        "   echo hi",
        "   ```",
    ]
    snippets = list(audit_docs_code_snippet_drift.snippets_from_lines(doc_path, lines))
    if len(snippets) != 3:
        return False, f"expected 3 snippets, got {len(snippets)}"
    first, second, third = snippets
    if first.language != "safe" or first.block_index != 1:
        return False, f"unexpected first snippet language/index {first.language} {first.block_index}"
    if second.language != audit_docs_code_snippet_drift.NO_LANGUAGE or second.block_index != 2:
        return False, f"unexpected second snippet language/index {second.language} {second.block_index}"
    if third.language != "bash" or third.block_index != 3:
        return False, f"unexpected indented snippet language/index {third.language} {third.block_index}"
    if audit_docs_code_snippet_drift.first_line_text(first) != "package Demo is":
        return False, "first non-empty snippet line was not selected for display"
    if audit_docs_code_snippet_drift.first_line_text(third) != "echo hi":
        return False, "indented snippet first line was not selected for display"
    return True, ""


def run_category_case() -> tuple[bool, str]:
    cases = {
        ("docs/syntax_proposals.md", "safe"): "historical-proposal-snippet",
        ("docs/tutorial.md", "safe"): "current-safe-snippet",
        ("spec/02-restrictions.md", "ada"): "current-ada-snippet",
        ("CLAUDE.md", "bash"): "current-shell-snippet",
        ("docs/vision.md", audit_docs_code_snippet_drift.NO_LANGUAGE): (
            "current-prose-or-data-snippet"
        ),
    }
    for (rel, language), expected in cases.items():
        snippet = audit_docs_code_snippet_drift.Snippet(
            doc_path=REPO_ROOT / rel,
            block_index=1,
            start_line=1,
            end_line=3,
            language=language,
            body_lines=("body",),
        )
        actual = audit_docs_code_snippet_drift.category_for(snippet)
        if actual != expected:
            return False, f"expected {expected} for {rel}/{language}, got {actual}"
    return True, ""


def run_fingerprint_case() -> tuple[bool, str]:
    doc_path = REPO_ROOT / "docs" / "synthetic.md"
    first = audit_docs_code_snippet_drift.fingerprint_for(
        category="current-safe-snippet",
        doc_path=doc_path,
        block_index=1,
        language="safe",
    )
    second = audit_docs_code_snippet_drift.fingerprint_for(
        category="current-safe-snippet",
        doc_path=doc_path,
        block_index=1,
        language="safe",
    )
    changed_index = audit_docs_code_snippet_drift.fingerprint_for(
        category="current-safe-snippet",
        doc_path=doc_path,
        block_index=2,
        language="safe",
    )
    if first != second:
        return False, "fingerprint should be stable for identical inputs"
    if first == changed_index:
        return False, "fingerprint should change when block index changes"
    snippet_a = audit_docs_code_snippet_drift.Snippet(
        doc_path=doc_path,
        block_index=1,
        start_line=1,
        end_line=3,
        language="safe",
        body_lines=("a",),
    )
    snippet_b = audit_docs_code_snippet_drift.Snippet(
        doc_path=doc_path,
        block_index=1,
        start_line=1,
        end_line=3,
        language="safe",
        body_lines=("b",),
    )
    if audit_docs_code_snippet_drift.snippet_digest(snippet_a) == (
        audit_docs_code_snippet_drift.snippet_digest(snippet_b)
    ):
        return False, "snippet digest should change when content changes"
    return True, ""


def run_unterminated_fence_case() -> tuple[bool, str]:
    doc_path = REPO_ROOT / "docs" / "synthetic.md"
    try:
        list(audit_docs_code_snippet_drift.snippets_from_lines(doc_path, ["```safe", "package X is"]))
    except ValueError as exc:
        message = str(exc)
        if "docs/synthetic.md:1" in message and "unterminated" in message:
            return True, ""
        return False, f"unterminated fence error lacked source context: {message}"
    return False, "unterminated fence did not fail loudly"


def run_docs_code_snippet_drift_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1i-code-snippet-drift:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:gate-self-check",
        run_gate_self_check_case(),
    )
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:snippet-digest-drift-gate",
        run_snippet_digest_drift_gate_case(),
    )
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:line-only-drift-gate",
        run_line_only_drift_gate_case(),
    )
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:fence-extraction",
        run_fence_extraction_case(),
    )
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:category",
        run_category_case(),
    )
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:fingerprint",
        run_fingerprint_case(),
    )
    passed += record_result(
        failures,
        "phase1i-code-snippet-drift:unterminated-fence",
        run_unterminated_fence_case(),
    )
    return passed, 0, failures
