"""Reporting-only checks for the Phase 1C arithmetic audit scanner."""

from __future__ import annotations

import json
import subprocess
import sys

from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_arithmetic.py"
BASELINE_PATH = REPO_ROOT / "audit" / "phase1c_arithmetic_baseline.json"


def run_summary_case() -> tuple[bool, str]:
    completed = subprocess.run(
        [sys.executable, str(AUDIT_SCRIPT), "--summary"],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.returncode != 0:
        return False, first_message(completed)
    return True, ""


def run_json_case() -> tuple[bool, str]:
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
    if not isinstance(payload, dict):
        return False, "scanner JSON top-level value is not an object"
    entries = payload.get("entries")
    if not isinstance(entries, list):
        return False, "scanner JSON missing entries list"
    for entry in entries:
        if not isinstance(entry, dict):
            return False, "scanner JSON entry is not an object"
        for field in ("fingerprint", "category", "pattern", "path", "line", "classification"):
            if field not in entry:
                return False, f"scanner JSON entry missing {field}"
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    if not BASELINE_PATH.exists():
        return False, f"missing baseline {BASELINE_PATH.relative_to(REPO_ROOT)}"
    try:
        payload = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return False, f"invalid baseline JSON: {exc}"
    if not isinstance(payload, dict):
        return False, "baseline top-level value is not an object"
    entries = payload.get("entries")
    if not isinstance(entries, list):
        return False, "baseline missing entries list"
    fingerprints: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            return False, "baseline entry is not an object"
        fingerprint = entry.get("fingerprint")
        if not isinstance(fingerprint, str) or not fingerprint:
            return False, "baseline entry missing fingerprint"
        if fingerprint in fingerprints:
            return False, f"duplicate baseline fingerprint {fingerprint}"
        fingerprints.add(fingerprint)
        classification = entry.get("classification")
        if classification not in {
            "candidate",
            "needs-repro",
            "confirmed-defect",
            "accepted-with-rationale",
        }:
            return False, f"invalid baseline classification {classification!r}"
    return True, ""


def run_arithmetic_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1c-arithmetic-audit:summary", run_summary_case())
    passed += record_result(failures, "phase1c-arithmetic-audit:json", run_json_case())
    passed += record_result(failures, "phase1c-arithmetic-audit:baseline", run_baseline_case())
    return passed, 0, failures
