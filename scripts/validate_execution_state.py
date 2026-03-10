#!/usr/bin/env python3
"""Validate execution tracker invariants and scoped repo facts."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Sequence, Set

from render_execution_status import DASHBOARD_PATH, TRACKER_PATH, load_tracker, render_dashboard


REPO_ROOT = Path(__file__).resolve().parent.parent
META_COMMIT_PATH = REPO_ROOT / "meta" / "commit.txt"
ALLOWED_STATUSES = {"planned", "ready", "in_progress", "blocked", "done"}
LEGACY_RUNTIME_BACKEND = REPO_ROOT / "compiler_impl" / "backend" / "pr05_backend.py"
RUNTIME_BOUNDARY_PATTERNS = [
    (
        "compiler_impl/src/safe_frontend-*.adb",
        [
            r"\bRun_Backend\b",
            r"\bBackend_Script\b",
            r"\bGNAT\.OS_Lib\b",
            r"pr05_backend\.py",
            r"\bpython(?:3(?:\.\d+)?)?\b",
            r"\bSpawn\b",
            r"\bNon_Blocking_Spawn\b",
            r"\bGNAT\.Expect\b",
        ],
    ),
    (
        "compiler_impl/src/safe_frontend-*.ads",
        [
            r"\bRun_Backend\b",
            r"\bBackend_Script\b",
            r"\bGNAT\.OS_Lib\b",
            r"pr05_backend\.py",
            r"\bpython(?:3(?:\.\d+)?)?\b",
            r"\bSpawn\b",
            r"\bNon_Blocking_Spawn\b",
            r"\bGNAT\.Expect\b",
        ],
    ),
    (
        "compiler_impl/src/safec.adb",
        [
            r"\bRun_Backend\b",
            r"\bBackend_Script\b",
            r"pr05_backend\.py",
            r"\bpython(?:3(?:\.\d+)?)?\b",
            r"\bSpawn\b",
            r"\bNon_Blocking_Spawn\b",
            r"\bGNAT\.Expect\b",
        ],
    ),
]
SAFEC_ALLOWED_OS_LIB_USES = [
    "with GNAT.OS_Lib;",
    "GNAT.OS_Lib.OS_Exit",
]
LEGACY_FRONTEND_PACKAGES = [
    "Safe_Frontend.Ast",
    "Safe_Frontend.Parser",
    "Safe_Frontend.Semantics",
    "Safe_Frontend.Mir",
]
LEGACY_FRONTEND_REFERENCE_PATTERNS = {
    package: rf"\b{re.escape(package)}\b" for package in LEGACY_FRONTEND_PACKAGES
}
LEGACY_FRONTEND_FILE_NAMES = [
    "safe_frontend-ast.ads",
    "safe_frontend-ast.adb",
    "safe_frontend-parser.ads",
    "safe_frontend-parser.adb",
    "safe_frontend-semantics.ads",
    "safe_frontend-semantics.adb",
    "safe_frontend-mir.ads",
    "safe_frontend-mir.adb",
]
LEGACY_FRONTEND_LIVE_ROOT_PATTERNS = [
    "compiler_impl/src/safec.adb",
    "compiler_impl/src/safe_frontend-driver.adb",
    "compiler_impl/src/safe_frontend-check_*.adb",
    "compiler_impl/src/safe_frontend-check_*.ads",
    "compiler_impl/src/safe_frontend-mir_*.adb",
    "compiler_impl/src/safe_frontend-mir_*.ads",
    "compiler_impl/src/safe_frontend-lexer.adb",
    "compiler_impl/src/safe_frontend-lexer.ads",
    "compiler_impl/src/safe_frontend-source.adb",
    "compiler_impl/src/safe_frontend-source.ads",
    "compiler_impl/src/safe_frontend-types.adb",
    "compiler_impl/src/safe_frontend-types.ads",
    "compiler_impl/src/safe_frontend-diagnostics.adb",
    "compiler_impl/src/safe_frontend-diagnostics.ads",
    "compiler_impl/src/safe_frontend-json.adb",
    "compiler_impl/src/safe_frontend-json.ads",
]

SHA_CHECKS = [
    (REPO_ROOT / "README.md", r"\| Frozen spec commit \| `([0-9a-f]{7,40})` \|"),
    (
        REPO_ROOT / "release" / "status_report.md",
        r"\*\*Frozen spec commit:\*\* `([0-9a-f]{40})` \(short: `([0-9a-f]{7})`\)",
    ),
    (
        REPO_ROOT / "release" / "COMPANION_README.md",
        r"\*\*Frozen spec commit:\*\* `([0-9a-f]{40})`",
    ),
]


def fail(message: str) -> None:
    raise ValueError(message)


def check_tracker_schema(tracker: Dict[str, Any]) -> None:
    required_top_level = {"schema_version", "updated_at", "frozen_spec_sha", "active_task_id", "next_task_id", "repo_facts", "tasks"}
    missing = required_top_level - set(tracker)
    if missing:
        fail(f"tracker.json missing required keys: {sorted(missing)}")
    if tracker["schema_version"] != 1:
        fail("tracker.json schema_version must be 1")
    if not isinstance(tracker["tasks"], list) or not tracker["tasks"]:
        fail("tracker.json tasks must be a non-empty list")


def task_lookup(tasks: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    lookup: Dict[str, Dict[str, Any]] = {}
    for task in tasks:
        task_id = task.get("id")
        if not task_id:
            fail("every task requires a non-empty id")
        if task_id in lookup:
            fail(f"duplicate task id: {task_id}")
        lookup[task_id] = task
    return lookup


def check_status_rules(tracker: Dict[str, Any], tasks: List[Dict[str, Any]]) -> None:
    active = tracker.get("active_task_id")
    in_progress = [task["id"] for task in tasks if task.get("status") == "in_progress"]
    for task in tasks:
        if task.get("status") not in ALLOWED_STATUSES:
            fail(f"{task['id']} has invalid status {task.get('status')!r}")
        if task["status"] == "done" and not task.get("evidence"):
            fail(f"{task['id']} is done but has no evidence")
    if in_progress:
        if len(in_progress) != 1:
            fail(f"exactly one task may be in_progress, found {in_progress}")
        if active != in_progress[0]:
            fail(f"active_task_id {active!r} does not match in-progress task {in_progress[0]!r}")
    elif active is not None:
        fail("active_task_id must be null when no task is in_progress")


def check_dependencies(tasks: List[Dict[str, Any]]) -> None:
    lookup = task_lookup(tasks)
    for task in tasks:
        for dep in task.get("depends_on", []):
            if dep not in lookup:
                fail(f"{task['id']} depends on unknown task {dep}")

    visiting: Set[str] = set()
    visited: Set[str] = set()

    def visit(task_id: str) -> None:
        if task_id in visited:
            return
        if task_id in visiting:
            fail(f"dependency cycle detected at {task_id}")
        visiting.add(task_id)
        for dep in lookup[task_id].get("depends_on", []):
            visit(dep)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in lookup:
        visit(task_id)


def check_frozen_sha(tracker: Dict[str, Any]) -> str:
    meta_sha = META_COMMIT_PATH.read_text(encoding="utf-8").strip()
    if tracker["frozen_spec_sha"] != meta_sha:
        fail("tracker frozen_spec_sha does not match meta/commit.txt")
    return meta_sha


def check_documented_sha(meta_sha: str) -> None:
    short_sha = meta_sha[:7]
    for path, pattern in SHA_CHECKS:
        text = path.read_text(encoding="utf-8")
        match = re.search(pattern, text)
        if not match:
            fail(f"missing frozen-SHA reference in {path.relative_to(REPO_ROOT)}")
        values = [group for group in match.groups() if group]
        if not values:
            fail(f"could not parse frozen-SHA reference in {path.relative_to(REPO_ROOT)}")
        for value in values:
            if len(value) == 40 and value != meta_sha:
                fail(f"{path.relative_to(REPO_ROOT)} has full SHA {value}, expected {meta_sha}")
            if len(value) == 7 and value != short_sha:
                fail(f"{path.relative_to(REPO_ROOT)} has short SHA {value}, expected {short_sha}")

    ci_text = (REPO_ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    match = re.search(r'FROZEN_SHA: "([0-9a-f]{40})"', ci_text)
    if not match or match.group(1) != meta_sha:
        fail(".github/workflows/ci.yml FROZEN_SHA does not match meta/commit.txt")


def count_test_files(
    tests_root: Path = REPO_ROOT / "tests",
    subdirs: Sequence[str] = ("positive", "negative", "golden", "concurrency", "diagnostics_golden"),
) -> Dict[str, int]:
    distribution = {}
    total = 0
    for subdir in subdirs:
        count = len([entry for entry in (tests_root / subdir).iterdir() if entry.is_file()])
        distribution[subdir] = count
        total += count
    distribution["total"] = total
    return distribution


def check_test_distribution(tracker: Dict[str, Any], *, tests_root: Path = REPO_ROOT / "tests") -> None:
    expected = tracker["repo_facts"]["tests"]
    actual = count_test_files(tests_root)
    if expected != actual:
        fail(f"test distribution mismatch: expected {expected}, actual {actual}")


def check_dashboard_freshness(tracker: Dict[str, Any]) -> None:
    rendered = render_dashboard(tracker)
    existing = DASHBOARD_PATH.read_text(encoding="utf-8")
    if rendered != existing:
        fail("execution/dashboard.md is stale; run scripts/render_execution_status.py --write")


def runtime_boundary_report(
    *,
    repo_root: Path = REPO_ROOT,
    runtime_boundary_patterns: Sequence[tuple[str, Sequence[str]]] = RUNTIME_BOUNDARY_PATTERNS,
    legacy_runtime_backend: Path | None = None,
    safec_allowed_os_lib_uses: Sequence[str] = SAFEC_ALLOWED_OS_LIB_USES,
) -> Dict[str, Any]:
    if legacy_runtime_backend is None:
        legacy_runtime_backend = repo_root / "compiler_impl" / "backend" / "pr05_backend.py"

    violations: List[str] = []
    scanned_files: List[str] = []
    for pattern, denylist in runtime_boundary_patterns:
        for path in sorted(repo_root.glob(pattern)):
            scanned_files.append(str(path.relative_to(repo_root)))
            text = path.read_text(encoding="utf-8")
            for token in denylist:
                if re.search(token, text, flags=re.IGNORECASE):
                    violations.append(f"{path.relative_to(repo_root)}:{token}")

    safec_path = repo_root / "compiler_impl" / "src" / "safec.adb"
    safec_text = safec_path.read_text(encoding="utf-8")
    safec_remaining = safec_text
    for allowed in safec_allowed_os_lib_uses:
        safec_remaining = safec_remaining.replace(allowed, "")
    safec_remaining = re.sub(r"--.*$", "", safec_remaining, flags=re.MULTILINE)
    if re.search(r"\bGNAT\.OS_Lib\b", safec_remaining):
        violations.append(
            f"{safec_path.relative_to(repo_root)}:unexpected GNAT.OS_Lib use outside OS_Exit"
        )

    return {
        "legacy_backend_present": legacy_runtime_backend.exists(),
        "legacy_backend_path": str(legacy_runtime_backend.relative_to(repo_root)),
        "safec_allowed_os_lib_uses": list(safec_allowed_os_lib_uses),
        "scanned_files": scanned_files,
        "violations": violations,
    }


def check_runtime_boundary() -> None:
    report = runtime_boundary_report()
    if report["legacy_backend_present"]:
        fail(f"legacy runtime backend still present: {report['legacy_backend_path']}")

    violations = report["violations"]
    if violations:
        fail(f"runtime boundary violations: {violations}")


def legacy_frontend_cleanup_report(
    *,
    repo_root: Path = REPO_ROOT,
    package_names: Sequence[str] = LEGACY_FRONTEND_PACKAGES,
    file_names: Sequence[str] = LEGACY_FRONTEND_FILE_NAMES,
    live_root_patterns: Sequence[str] = LEGACY_FRONTEND_LIVE_ROOT_PATTERNS,
) -> Dict[str, Any]:
    source_root = repo_root / "compiler_impl" / "src"
    expected_files = [source_root / name for name in file_names]
    present_files = [
        str(path.relative_to(repo_root))
        for path in expected_files
        if path.exists()
    ]
    missing_files = [
        str(path.relative_to(repo_root))
        for path in expected_files
        if not path.exists()
    ]

    package_patterns = {
        package: LEGACY_FRONTEND_REFERENCE_PATTERNS.get(package, rf"\b{re.escape(package)}\b")
        for package in package_names
    }

    scanned_source_files = [
        path
        for suffix in ("*.adb", "*.ads")
        for path in sorted(source_root.glob(suffix))
    ]
    forbidden_references: List[str] = []
    for path in scanned_source_files:
        text = path.read_text(encoding="utf-8")
        for package, pattern in package_patterns.items():
            if re.search(pattern, text, flags=re.IGNORECASE):
                forbidden_references.append(f"{path.relative_to(repo_root)}:{package}")

    live_runtime_roots: List[str] = []
    live_runtime_reference_violations: List[str] = []
    live_runtime_files: List[Path] = []
    seen_live: Set[Path] = set()
    for pattern in live_root_patterns:
        for path in sorted(repo_root.glob(pattern)):
            if path not in seen_live:
                seen_live.add(path)
                live_runtime_files.append(path)
                live_runtime_roots.append(str(path.relative_to(repo_root)))
    for path in live_runtime_files:
        text = path.read_text(encoding="utf-8")
        for package, pattern in package_patterns.items():
            if re.search(pattern, text, flags=re.IGNORECASE):
                live_runtime_reference_violations.append(
                    f"{path.relative_to(repo_root)}:{package}"
                )

    return {
        "candidate_packages": list(package_names),
        "expected_files": [str(path.relative_to(repo_root)) for path in expected_files],
        "present_files": present_files,
        "missing_files": missing_files,
        "scanned_source_files": [str(path.relative_to(repo_root)) for path in scanned_source_files],
        "forbidden_references": forbidden_references,
        "live_runtime_roots": live_runtime_roots,
        "live_runtime_reference_violations": live_runtime_reference_violations,
        "retained_legacy_packages": [],
    }


def check_legacy_frontend_cleanup() -> None:
    report = legacy_frontend_cleanup_report()
    if report["present_files"]:
        fail(f"legacy frontend files still present: {report['present_files']}")
    if report["forbidden_references"]:
        fail(f"legacy frontend references still present: {report['forbidden_references']}")
    if report["live_runtime_reference_violations"]:
        fail(
            "live runtime roots still reference legacy frontend packages: "
            f"{report['live_runtime_reference_violations']}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tracker", type=Path, default=TRACKER_PATH)
    args = parser.parse_args()

    tracker = load_tracker(args.tracker)
    check_tracker_schema(tracker)
    tasks = tracker["tasks"]
    check_status_rules(tracker, tasks)
    check_dependencies(tasks)
    meta_sha = check_frozen_sha(tracker)
    check_documented_sha(meta_sha)
    check_test_distribution(tracker)
    check_dashboard_freshness(tracker)
    check_runtime_boundary()
    check_legacy_frontend_cleanup()
    print("execution state: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"execution state: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
