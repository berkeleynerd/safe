"""Inventory-mode checks for the Phase 1I.A docs fixture-drift scanner."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

import audit_docs_fixture_drift
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_docs_fixture_drift.py"
BASELINE_PATH = audit_docs_fixture_drift.BASELINE_PATH
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


def payload_without_report_only_digest(payload: dict[str, object]) -> dict[str, object]:
    """Normalize Phase 1I.A inventory JSON for comparison.

    Inventory mode keeps display and schema metadata in lockstep with the
    committed baseline. Only target_digest is report-only because routine
    fixture-content edits should not force a docs-reference re-baseline.
    """

    comparable = deepcopy(payload)
    entries = comparable.get("entries")
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                entry.pop("target_digest", None)
    return comparable


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
    audit_docs_fixture_drift.print_summary(
        payload,
        baseline_entries=audit_docs_fixture_drift.existing_classifications(),
    )
    baseline, message = read_baseline_payload()
    if baseline is None:
        return False, message
    ok, message = validate_entries(baseline, "baseline")
    if not ok:
        return False, message
    # Inventory mode is intentionally stricter than closed baseline gates:
    # every field except target_digest must match the committed baseline.
    if payload_without_report_only_digest(payload) != payload_without_report_only_digest(baseline):
        return (
            False,
            "Phase 1I.A live scanner JSON differs from committed baseline "
            "outside report-only target_digest metadata",
        )
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    payload, message = read_baseline_payload()
    if payload is None:
        return False, message
    ok, message = validate_entries(payload, "baseline")
    if not ok:
        return False, message
    classifications = {
        entry.get("classification") for entry in baseline_audit_gate.entries_for(payload)
    }
    # The first triage PR relaxes this candidate-only inventory invariant.
    if classifications != {"candidate"}:
        return False, f"inventory baseline should contain only candidates, got {classifications}"
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


def run_digest_report_only_case() -> tuple[bool, str]:
    baseline = {
        "entries": [
            {
                "fingerprint": "same",
                "target_digest": "old",
            }
        ]
    }
    live = {
        "entries": [
            {
                "fingerprint": "same",
                "target_digest": "new",
            }
        ]
    }
    if payload_without_report_only_digest(baseline) != payload_without_report_only_digest(live):
        return False, "target_digest should be ignored by inventory-mode comparison"
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
        "phase1i-docs-fixture-drift:digest-report-only",
        run_digest_report_only_case(),
    )
    passed += record_result(
        failures,
        "phase1i-docs-fixture-drift:fingerprint",
        run_fingerprint_case(),
    )
    return passed, 0, failures
