"""Baseline-gated checks for the Phase 1I.A docs fixture-drift scanner."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

import audit_docs_fixture_drift
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_docs_fixture_drift.py"
BASELINE_PATH = audit_docs_fixture_drift.BASELINE_PATH
PHASE_LABEL = "Phase 1I.A docs fixture drift"
ACCEPTED = baseline_audit_gate.ACCEPTED
REQUIRED_FIELDS = (
    "fingerprint",
    "category",
    "pattern",
    "path",
    "line",
    "line_numbers",
    "first_line_text",
    "target_path",
    "target_kind",
    "target_status",
    "target_digest",
    "multiplicity",
    "classification",
    "rationale",
    "follow_up",
)


def validate_target_statuses(payload: dict[str, object], label: str) -> tuple[bool, str]:
    for entry in baseline_audit_gate.entries_for(payload):
        status = entry.get("target_status")
        if status not in audit_docs_fixture_drift.TARGET_STATUSES:
            return False, f"invalid {label} target_status {status!r}"
    return True, ""


def validate_entries(payload: object, label: str) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_entries(
        payload,
        label,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_fixture_drift.CATEGORIES,
        valid_patterns=audit_docs_fixture_drift.PATTERNS,
    )
    if not ok:
        return False, message
    if not isinstance(payload, dict):
        return False, f"{label} is not a dict"
    return validate_target_statuses(payload, label)


def validate_closed_baseline(payload: dict[str, object]) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_closed_baseline(
        payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_docs_fixture_drift.CATEGORIES,
        valid_patterns=audit_docs_fixture_drift.PATTERNS,
    )
    if not ok:
        return False, message
    return validate_target_statuses(payload, "baseline")


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
        valid_categories=audit_docs_fixture_drift.CATEGORIES,
        valid_patterns=audit_docs_fixture_drift.PATTERNS,
    )


def compare_target_status_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    live = baseline_audit_gate.fingerprint_map(live_payload)
    baseline = baseline_audit_gate.fingerprint_map(baseline_payload)
    for fingerprint in sorted(set(live) & set(baseline)):
        live_status = live[fingerprint].get("target_status")
        baseline_status = baseline[fingerprint].get("target_status")
        if live_status != baseline_status:
            return (
                False,
                f"{PHASE_LABEL} target_status drift: {baseline_status!r} -> "
                f"{live_status!r} at {baseline_audit_gate.describe_entry(live[fingerprint])}",
            )
    return True, ""


def target_digest_report_only_message(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> str:
    live = baseline_audit_gate.fingerprint_map(live_payload)
    baseline = baseline_audit_gate.fingerprint_map(baseline_payload)
    drifts = []
    for fingerprint in sorted(set(live) & set(baseline)):
        if live[fingerprint].get("target_digest") != baseline[fingerprint].get("target_digest"):
            drifts.append(baseline_audit_gate.describe_entry(live[fingerprint]))
    if not drifts:
        return ""
    examples = "; ".join(drifts[:5])
    suffix = "" if len(drifts) <= 5 else f"; ... {len(drifts) - 5} more"
    return f"{PHASE_LABEL} target_digest drift (report-only): {examples}{suffix}"


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
    audit_docs_fixture_drift.print_summary(
        payload,
        baseline_entries=audit_docs_fixture_drift.existing_classifications(),
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
    ok, message = compare_target_status_to_baseline(payload, baseline)
    if not ok:
        return False, message
    message = target_digest_report_only_message(payload, baseline)
    if message:
        print(message)
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
    expected = Counter({"accepted-with-rationale": 307})
    if classifications != expected:
        return False, f"unexpected Phase 1I.A triage distribution {classifications}"
    return True, ""


def synthetic_entry(
    fingerprint: str,
    *,
    classification: str = ACCEPTED,
    rationale: str = "Accepted: synthetic Phase 1I.A docs fixture entry.",
    target_status: str = "present",
    target_digest: str = "0" * 64,
    line: int = 1,
) -> dict[str, object]:
    return {
        "fingerprint": fingerprint,
        "category": "prose-path-reference",
        "pattern": "safe-fixture-path",
        "path": "docs/synthetic.md",
        "line": line,
        "line_numbers": [line],
        "first_line_text": "`tests/positive/rule1_accumulate.safe`",
        "target_path": "tests/positive/rule1_accumulate.safe",
        "target_kind": "safe-source",
        "target_status": target_status,
        "target_digest": target_digest,
        "multiplicity": 1,
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
        valid_categories=audit_docs_fixture_drift.CATEGORIES,
        valid_patterns=audit_docs_fixture_drift.PATTERNS,
    )


def run_target_status_drift_gate_case() -> tuple[bool, str]:
    baseline = {"entries": [synthetic_entry("same", target_status="present")]}
    live = {"entries": [synthetic_entry("same", target_status="missing", target_digest="")]}
    ok, message = compare_target_status_to_baseline(live, baseline)
    if ok or "present" not in message or "missing" not in message:
        return False, f"target_status drift should fail with both statuses, got: {message}"
    return True, ""


def run_target_digest_report_only_gate_case() -> tuple[bool, str]:
    baseline = {"entries": [synthetic_entry("same", target_digest="0" * 64)]}
    live = {"entries": [synthetic_entry("same", target_digest="1" * 64)]}
    message = target_digest_report_only_message(live, baseline)
    if "report-only" not in message:
        return False, f"target_digest drift should report without failing, got: {message}"
    return True, ""


def run_path_extraction_case() -> tuple[bool, str]:
    doc_path = REPO_ROOT / "docs" / "synthetic.md"
    line = (
        "See [`tests/positive/rule1_accumulate.safe`](../tests/positive/rule1_accumulate.safe), "
        "`samples/rosetta/text/hello_print.safe`, and "
        "`compiler_impl/tests/mir_analysis/pr102_fp_unsupported_expression_parity.json`."
    )
    refs = audit_docs_fixture_drift.references_from_line(doc_path, 7, line)
    targets = [ref.target_path for ref in refs]
    # Markdown links intentionally produce raw hits for both the label and URL.
    expected = [
        "tests/positive/rule1_accumulate.safe",
        "tests/positive/rule1_accumulate.safe",
        "samples/rosetta/text/hello_print.safe",
        "compiler_impl/tests/mir_analysis/pr102_fp_unsupported_expression_parity.json",
    ]
    if targets != expected:
        return False, f"unexpected extracted targets {targets!r}"
    patterns = [ref.pattern for ref in refs]
    if patterns != [
        "safe-fixture-path",
        "safe-fixture-path",
        "safe-fixture-path",
        "json-fixture-path",
    ]:
        return False, f"unexpected patterns {patterns!r}"
    try:
        audit_docs_fixture_drift.pattern_for("tests/positive/fixture.unsupported")
    except ValueError:
        pass
    else:
        return False, "unknown reference extension should fail loudly"
    if audit_docs_fixture_drift.pattern_for("tests/diagnostics_golden/example/") != (
        "golden-directory-path"
    ):
        return False, "diagnostics_golden directory references should be directory paths"
    if audit_docs_fixture_drift.target_kind_for("tests/golden/example.txt") != "golden-text":
        return False, "tests/golden .txt references should be classified as golden text"
    if audit_docs_fixture_drift.target_kind_for("samples/rosetta/text/example.txt") != "sample-text":
        return False, "sample .txt references should be classified as sample text"
    extensionless_refs = audit_docs_fixture_drift.references_from_line(
        doc_path,
        8,
        "Ignore `tests/golden/extensionless` because directory references keep a trailing slash.",
    )
    if extensionless_refs:
        return False, "extensionless golden references should not be scanned as directories"
    return True, ""


def run_category_case() -> tuple[bool, str]:
    cases = {
        "docs/emitted_output_verification_matrix.md": "emitted-matrix-path-reference",
        "docs/traceability_matrix.csv": "traceability-matrix-path-reference",
        "README.md": "prose-path-reference",
        "docs/tutorial.md": "prose-path-reference",
    }
    for rel, expected in cases.items():
        actual = audit_docs_fixture_drift.category_for(REPO_ROOT / rel)
        if actual != expected:
            return False, f"expected {expected} for {rel}, got {actual}"
    return True, ""


def run_target_metadata_case() -> tuple[bool, str]:
    present_status, present_digest = audit_docs_fixture_drift.target_metadata(
        "tests/positive/rule1_accumulate.safe"
    )
    if present_status != "present" or len(present_digest) != 64:
        return False, "present fixture did not produce a SHA-256 digest"
    missing_status, missing_digest = audit_docs_fixture_drift.target_metadata(
        "tests/positive/does_not_exist.safe"
    )
    if missing_status != "missing" or missing_digest != "":
        return False, "missing fixture did not produce missing/empty metadata"
    with tempfile.TemporaryDirectory(prefix="phase1i-outside-") as temp_root_str:
        outside = Path(temp_root_str) / "secret.txt"
        outside.write_text("do not read\n", encoding="utf-8")
        relative_from_fixture_dir = os.path.relpath(
            outside,
            REPO_ROOT / "tests" / "positive",
        )
        traversal_status, traversal_digest = audit_docs_fixture_drift.target_metadata(
            f"tests/positive/{relative_from_fixture_dir}"
        )
        if traversal_status != "missing" or traversal_digest != "":
            return False, "path traversal target should be treated as missing"
    with tempfile.TemporaryDirectory(prefix="phase1i-dir-digest-") as temp_root_str:
        temp_root = Path(temp_root_str)
        (temp_root / "b.txt").write_text("two\n", encoding="utf-8")
        (temp_root / "a.txt").write_text("one\n", encoding="utf-8")
        digest_a = audit_docs_fixture_drift.sha256_directory(temp_root)
        digest_b = audit_docs_fixture_drift.sha256_directory(temp_root)
        if digest_a != digest_b or len(digest_a) != 64:
            return False, "directory digest is not stable SHA-256 text"
    with tempfile.TemporaryDirectory(prefix="phase1i-dir-symlink-") as temp_root_str:
        temp_root = Path(temp_root_str)
        fixture_dir = temp_root / "fixture"
        fixture_dir.mkdir()
        outside = temp_root / "outside.txt"
        outside.write_text("outside-a\n", encoding="utf-8")
        (fixture_dir / "inside.txt").write_text("inside\n", encoding="utf-8")
        try:
            (fixture_dir / "outside-link.txt").symlink_to(outside)
        except OSError:
            pass
        else:
            digest_a = audit_docs_fixture_drift.sha256_directory(fixture_dir)
            outside.write_text("outside-b\n", encoding="utf-8")
            digest_b = audit_docs_fixture_drift.sha256_directory(fixture_dir)
            if digest_a != digest_b:
                return False, "directory digest should ignore symlink targets"
    with tempfile.TemporaryDirectory(prefix="phase1i-dir-symlink-dir-") as temp_root_str:
        temp_root = Path(temp_root_str)
        fixture_dir = temp_root / "fixture"
        fixture_dir.mkdir()
        outside_dir = temp_root / "outside-dir"
        outside_dir.mkdir()
        outside_file = outside_dir / "outside.txt"
        outside_file.write_text("outside-a\n", encoding="utf-8")
        (fixture_dir / "inside.txt").write_text("inside\n", encoding="utf-8")
        try:
            (fixture_dir / "outside-dir-link").symlink_to(outside_dir, target_is_directory=True)
        except OSError:
            pass
        else:
            digest_a = audit_docs_fixture_drift.sha256_directory(fixture_dir)
            outside_file.write_text("outside-b\n", encoding="utf-8")
            digest_b = audit_docs_fixture_drift.sha256_directory(fixture_dir)
            if digest_a != digest_b:
                return False, "directory digest should not traverse symlink directories"
    return True, ""


def run_fingerprint_case() -> tuple[bool, str]:
    doc_path = REPO_ROOT / "docs" / "synthetic.md"
    first = audit_docs_fixture_drift.fingerprint_for(
        category="prose-path-reference",
        doc_path=doc_path,
        target_path="tests/positive/rule1_accumulate.safe",
        pattern="safe-fixture-path",
    )
    second = audit_docs_fixture_drift.fingerprint_for(
        category="prose-path-reference",
        doc_path=doc_path,
        target_path="tests/positive/rule1_accumulate.safe",
        pattern="safe-fixture-path",
    )
    changed_target = audit_docs_fixture_drift.fingerprint_for(
        category="prose-path-reference",
        doc_path=doc_path,
        target_path="tests/positive/rule1_averaging.safe",
        pattern="safe-fixture-path",
    )
    if first != second:
        return False, "fingerprint should be stable for identical inputs"
    if first == changed_target:
        return False, "fingerprint should change when target path changes"
    return True, ""


def run_docs_fixture_drift_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1i-docs-fixture-drift:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:gate-self-check",
        run_gate_self_check_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:target-status-drift-gate",
        run_target_status_drift_gate_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:target-digest-report-only-gate",
        run_target_digest_report_only_gate_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:path-extraction",
        run_path_extraction_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:category",
        run_category_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:target-metadata",
        run_target_metadata_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:fingerprint",
        run_fingerprint_case(),
    )
    return passed, 0, failures
