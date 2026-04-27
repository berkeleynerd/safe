"""Reporting-only checks for the Phase 1E SPARK_Mode Off scanner."""

from __future__ import annotations

import json
import subprocess
import sys

import audit_spark_mode_off
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_spark_mode_off.py"
BASELINE_PATH = REPO_ROOT / "audit" / "phase1e_spark_mode_off_baseline.json"
VALID_CLASSIFICATIONS = {
    "candidate",
    "needs-repro",
    "confirmed-defect",
    "accepted-with-rationale",
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
            "multiplicity",
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
    # Match Phase 1C/1D audit behavior: run_tests.py emits audit summaries visibly.
    audit_spark_mode_off.print_summary(
        payload,
        baseline_entries=audit_spark_mode_off.existing_classifications(),
    )
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    if not BASELINE_PATH.exists():
        return False, f"missing baseline {BASELINE_PATH.relative_to(REPO_ROOT)}"
    try:
        payload = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return False, f"invalid baseline JSON: {exc}"
    ok, message = validate_entries(payload, "baseline")
    if not ok:
        return False, message
    return True, ""


def run_comment_scanner_case() -> tuple[bool, str]:
    line = 'Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2); -- SPARK_Mode (Off)'
    stripped = audit_spark_mode_off.strip_comments_keep_strings(line)
    if "--" in stripped:
        return False, "comment scanner retained Ada comment text"
    if '"pragma SPARK_Mode (Off);"' not in stripped:
        return False, "comment scanner removed string-literal target text"
    if not audit_spark_mode_off.PATTERNS[0].regex.search(stripped):
        return False, "pragma pattern did not match generated string literal"
    return True, ""


def run_category_assignment_case() -> tuple[bool, str]:
    emitted = REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-ada_emit.adb"
    runtime = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "io.adb"
    pragma_pattern = audit_spark_mode_off.PATTERNS[0]
    aspect_pattern = audit_spark_mode_off.PATTERNS[1]
    cases = {
        "emitted-spark-off-pragma": audit_spark_mode_off.category_for(emitted, pragma_pattern),
        "emitted-spark-off-aspect": audit_spark_mode_off.category_for(emitted, aspect_pattern),
        "runtime-spark-off-pragma": audit_spark_mode_off.category_for(runtime, pragma_pattern),
        "runtime-spark-off-aspect": audit_spark_mode_off.category_for(runtime, aspect_pattern),
    }
    for expected, actual in cases.items():
        if actual != expected:
            return False, f"expected {expected}, got {actual}"
    return True, ""


def run_spark_mode_off_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1e-spark-mode-off-audit:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1e-spark-mode-off-audit:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1e-spark-mode-off-audit:comment-scanner",
        run_comment_scanner_case(),
    )
    passed += record_result(
        failures,
        "phase1e-spark-mode-off-audit:category-assignment",
        run_category_assignment_case(),
    )
    return passed, 0, failures
