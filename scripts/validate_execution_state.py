#!/usr/bin/env python3
"""Validate execution tracker invariants and scoped repo facts."""

from __future__ import annotations

import argparse
import ast
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Sequence, Set

from _lib.harness_common import serialize_report
from _lib.platform_assumptions import (
    DOCUMENTED_PYTHON_FORMS,
    MACOS_SDK_DISCOVERY_FORMS,
    MASKED_PYTHON_INTERPRETERS,
    PATH_LOOKUP_POLICY_TEXT,
    SHELL_POLICY_TEXT,
    STATIC_PYTHON_INVOCATION_PATTERNS,
    SUPPORTED_FRONTEND_ENVIRONMENTS,
    SUPPORTED_PLATFORM_POLICY_TEXT,
    TEMPDIR_POLICY_TEXT,
    UNSUPPORTED_FRONTEND_ENVIRONMENTS,
    UNSUPPORTED_PLATFORM_POLICY_TEXT,
)
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
            r"\bSpawn\b",
            r"\bNon_Blocking_Spawn\b",
            r"\bGNAT\.Expect\b",
            *STATIC_PYTHON_INVOCATION_PATTERNS,
        ],
    ),
    (
        "compiler_impl/src/safe_frontend-*.ads",
        [
            r"\bRun_Backend\b",
            r"\bBackend_Script\b",
            r"\bGNAT\.OS_Lib\b",
            r"pr05_backend\.py",
            r"\bSpawn\b",
            r"\bNon_Blocking_Spawn\b",
            r"\bGNAT\.Expect\b",
            *STATIC_PYTHON_INVOCATION_PATTERNS,
        ],
    ),
    (
        "compiler_impl/src/safec.adb",
        [
            r"\bRun_Backend\b",
            r"\bBackend_Script\b",
            r"pr05_backend\.py",
            r"\bSpawn\b",
            r"\bNon_Blocking_Spawn\b",
            r"\bGNAT\.Expect\b",
            *STATIC_PYTHON_INVOCATION_PATTERNS,
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
EVIDENCE_FORBIDDEN_MARKERS = [
    "Build finished successfully in",
    "GPRBUILD ",
    "Python ",
    "/Users/",
    "/home/runner/",
]
PERFORMANCE_DOC_REQUIREMENTS = {
    "docs/frontend_scale_limits.md": [
        "PR05/PR06 supported subset only",
        "cliff-detection gate, not a benchmark commitment",
        "raw timings are intentionally kept out of committed evidence",
        "Rule 5, result safety, channels/tasks/concurrency, and other unsupported surfaces are out of scope",
    ],
    "compiler_impl/README.md": [
        "docs/frontend_scale_limits.md",
        "PR06.9.12",
        "cliff-detection gate, not a benchmark commitment",
    ],
    "release/frontend_runtime_decision.md": [
        "docs/frontend_scale_limits.md",
        "PR06.9.12",
        "cliff-detection gate, not a benchmark commitment",
    ],
}
ENVIRONMENT_DOC_REQUIREMENTS = {
    "compiler_impl/README.md": [
        SUPPORTED_PLATFORM_POLICY_TEXT,
        UNSUPPORTED_PLATFORM_POLICY_TEXT,
        PATH_LOOKUP_POLICY_TEXT,
        TEMPDIR_POLICY_TEXT,
        SHELL_POLICY_TEXT,
        *MACOS_SDK_DISCOVERY_FORMS,
        *DOCUMENTED_PYTHON_FORMS,
    ],
    "release/frontend_runtime_decision.md": [
        SUPPORTED_PLATFORM_POLICY_TEXT,
        UNSUPPORTED_PLATFORM_POLICY_TEXT,
        PATH_LOOKUP_POLICY_TEXT,
        TEMPDIR_POLICY_TEXT,
        SHELL_POLICY_TEXT,
        *MACOS_SDK_DISCOVERY_FORMS,
        *DOCUMENTED_PYTHON_FORMS,
    ],
    "docs/macos_alire_toolchain_repair.md": [
        "developer recovery procedure",
        "not a compiler runtime dependency",
        *MACOS_SDK_DISCOVERY_FORMS,
    ],
}
PORTABILITY_MODULE_REQUIREMENTS = {
    "scripts/run_pr0693_runtime_boundary.py": [
        "MASKED_PYTHON_INTERPRETERS",
    ],
    "scripts/run_pr068_ada_ast_emit_no_python.py": [
        "MASKED_PYTHON_INTERPRETERS",
        "STATIC_PYTHON_INVOCATION_PATTERNS",
    ],
    "scripts/validate_execution_state.py": [
        "STATIC_PYTHON_INVOCATION_PATTERNS",
        "SUPPORTED_PLATFORM_POLICY_TEXT",
        "UNSUPPORTED_PLATFORM_POLICY_TEXT",
    ],
}
PORTABILITY_TEMPDIR_SCRIPTS = [
    "scripts/run_pr0693_runtime_boundary.py",
    "scripts/run_pr068_ada_ast_emit_no_python.py",
]
PORTABILITY_PATH_LOOKUP_SCRIPTS = [
    "scripts/run_pr0693_runtime_boundary.py",
    "scripts/run_pr068_ada_ast_emit_no_python.py",
    "scripts/run_pr06910_portability_environment.py",
]
GLUE_SAFETY_AUDITED_SCRIPTS = [
    "scripts/run_frontend_smoke.py",
    "scripts/run_pr05_d27_harness.py",
    "scripts/run_pr06_ownership_harness.py",
    "scripts/run_pr065_ada_mir_validator.py",
    "scripts/run_pr066_ada_mir_analyzer.py",
    "scripts/run_pr067_ada_check_cutover.py",
    "scripts/run_pr068_ada_ast_emit_no_python.py",
    "scripts/run_pr0691_semantic_correctness.py",
    "scripts/run_pr0692_lowering_cfg_integrity.py",
    "scripts/run_pr0693_runtime_boundary.py",
    "scripts/run_pr0694_output_contract_stability.py",
    "scripts/run_pr0695_diagnostic_stability.py",
    "scripts/run_pr0696_unsupported_feature_boundary.py",
    "scripts/run_pr0697_gate_quality.py",
    "scripts/run_pr0698_legacy_package_cleanup.py",
    "scripts/run_pr0699_build_reproducibility.py",
    "scripts/run_pr06910_portability_environment.py",
    "scripts/run_pr06911_glue_script_safety.py",
    "scripts/run_pr06912_performance_scale_sanity.py",
    "scripts/validate_execution_state.py",
    "scripts/validate_ast_output.py",
    "scripts/validate_output_contracts.py",
    "scripts/render_execution_status.py",
]
GLUE_SAFETY_REPORT_SCRIPTS = [
    "scripts/run_frontend_smoke.py",
    "scripts/run_pr05_d27_harness.py",
    "scripts/run_pr06_ownership_harness.py",
    "scripts/run_pr065_ada_mir_validator.py",
    "scripts/run_pr066_ada_mir_analyzer.py",
    "scripts/run_pr067_ada_check_cutover.py",
    "scripts/run_pr068_ada_ast_emit_no_python.py",
    "scripts/run_pr0691_semantic_correctness.py",
    "scripts/run_pr0692_lowering_cfg_integrity.py",
    "scripts/run_pr0693_runtime_boundary.py",
    "scripts/run_pr0694_output_contract_stability.py",
    "scripts/run_pr0695_diagnostic_stability.py",
    "scripts/run_pr0696_unsupported_feature_boundary.py",
    "scripts/run_pr0697_gate_quality.py",
    "scripts/run_pr0698_legacy_package_cleanup.py",
    "scripts/run_pr0699_build_reproducibility.py",
    "scripts/run_pr06910_portability_environment.py",
    "scripts/run_pr06911_glue_script_safety.py",
    "scripts/run_pr06912_performance_scale_sanity.py",
]
GLUE_SAFETY_PATH_COMMANDS = ("python3", "alr", "git")
GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS = {
    "scripts/run_pr05_d27_harness.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr06_ownership_harness.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr0691_semantic_correctness.py": "fixture metadata extraction via read_expected_reason",
}
GLUE_SAFETY_DIRECT_SAFE_READ_PATTERNS = [
    r'"[^"\n]*\.safe"\s*\)\.read_text\(',
    r"'[^'\n]*\.safe'\s*\)\.read_text\(",
    r'"[^"\n]*\.safe"\s*\)\.open\(',
    r"'[^'\n]*\.safe'\s*\)\.open\(",
]
GLUE_SAFETY_REPO_LOCAL_COMMAND_PATTERNS = {
    "safec": [
        r"COMPILER_ROOT\s*/\s*['\"]bin['\"]\s*/\s*['\"]safec['\"]",
        r"REPO_ROOT\s*/\s*['\"]compiler_impl['\"]\s*/\s*['\"]bin['\"]\s*/\s*['\"]safec['\"]",
    ],
}
PLATFORM_ASSUMPTIONS_IMPORT_PATTERN = (
    r"^\s*(?:from\s+_lib\.platform_assumptions\s+import\b|import\s+_lib\.platform_assumptions\b)"
)


def fail(message: str) -> None:
    raise ValueError(message)


def _call_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = _call_name(node.value)
        if prefix is None:
            return node.attr
        return f"{prefix}.{node.attr}"
    return None


def _has_prefix_keyword(node: ast.Call) -> bool:
    for keyword in node.keywords:
        if keyword.arg == "prefix":
            return True
    return False


def _safe_source_binding_name(
    node: ast.AST,
    *,
    imported_path_names: Set[str],
) -> str | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.endswith(".safe"):
        return node.value
    if isinstance(node, ast.Call):
        call_name = _call_name(node.func)
        if (
            call_name in imported_path_names
            or call_name == "pathlib.Path"
        ) and node.args:
            first_arg = node.args[0]
            if isinstance(first_arg, ast.Constant) and isinstance(first_arg.value, str) and first_arg.value.endswith(".safe"):
                return first_arg.value
    return None


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


def find_nested_key_paths(value: Any, key: str, prefix: str = "") -> List[str]:
    paths: List[str] = []
    if isinstance(value, dict):
        for child_key, child_value in value.items():
            child_prefix = f"{prefix}.{child_key}" if prefix else child_key
            if child_key == key:
                paths.append(child_prefix)
            paths.extend(find_nested_key_paths(child_value, key, child_prefix))
    elif isinstance(value, list):
        for index, child_value in enumerate(value):
            child_prefix = f"{prefix}[{index}]" if prefix else f"[{index}]"
            paths.extend(find_nested_key_paths(child_value, key, child_prefix))
    return paths


def evidence_reproducibility_report(
    *,
    tracker: Dict[str, Any],
    repo_root: Path = REPO_ROOT,
    forbidden_markers: Sequence[str] = EVIDENCE_FORBIDDEN_MARKERS,
) -> Dict[str, Any]:
    evidence_files: List[str] = []
    missing_files: List[str] = []
    noncanonical_files: List[str] = []
    tool_version_fields: List[str] = []
    marker_violations: List[str] = []
    seen: Set[str] = set()

    for task in tracker.get("tasks", []):
        if task.get("status") != "done":
            continue
        for evidence in task.get("evidence", []):
            if not evidence.endswith(".json") or evidence in seen:
                continue
            seen.add(evidence)
            evidence_files.append(evidence)
            path = repo_root / evidence
            if not path.exists():
                missing_files.append(evidence)
                continue
            raw = path.read_text(encoding="utf-8")
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError as exc:
                noncanonical_files.append(f"{evidence}: invalid JSON ({exc.msg})")
                continue
            if raw != serialize_report(payload):
                noncanonical_files.append(evidence)
            for nested in find_nested_key_paths(payload, "tool_versions"):
                tool_version_fields.append(f"{evidence}:{nested}")
            for marker in forbidden_markers:
                if marker in raw:
                    marker_violations.append(f"{evidence}:{marker}")

    return {
        "evidence_files": evidence_files,
        "missing_files": missing_files,
        "noncanonical_files": noncanonical_files,
        "tool_version_fields": tool_version_fields,
        "marker_violations": marker_violations,
    }


def check_evidence_reproducibility(
    tracker: Dict[str, Any],
    *,
    repo_root: Path = REPO_ROOT,
) -> None:
    report = evidence_reproducibility_report(tracker=tracker, repo_root=repo_root)
    if report["missing_files"]:
        fail(f"missing evidence files: {report['missing_files']}")
    if report["noncanonical_files"]:
        fail(f"noncanonical evidence files: {report['noncanonical_files']}")
    if report["tool_version_fields"]:
        fail(f"evidence reports still contain tool_versions: {report['tool_version_fields']}")
    if report["marker_violations"]:
        fail(
            "evidence reports contain host-specific or transient markers: "
            f"{report['marker_violations']}"
        )


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


def environment_assumptions_report(
    *,
    repo_root: Path = REPO_ROOT,
    doc_requirements: Dict[str, Sequence[str]] = ENVIRONMENT_DOC_REQUIREMENTS,
    runtime_source_globs: Sequence[str] = (
        "compiler_impl/src/*.adb",
        "compiler_impl/src/*.ads",
    ),
    python_patterns: Sequence[str] = STATIC_PYTHON_INVOCATION_PATTERNS,
    module_requirements: Dict[str, Sequence[str]] = PORTABILITY_MODULE_REQUIREMENTS,
    tempdir_scripts: Sequence[str] = PORTABILITY_TEMPDIR_SCRIPTS,
    path_lookup_scripts: Sequence[str] = PORTABILITY_PATH_LOOKUP_SCRIPTS,
) -> Dict[str, Any]:
    missing_doc_files: List[str] = []
    doc_policy_violations: List[str] = []
    docs_scanned: List[str] = []
    for relative_path, required_markers in doc_requirements.items():
        docs_scanned.append(relative_path)
        path = repo_root / relative_path
        if not path.exists():
            missing_doc_files.append(relative_path)
            continue
        text = path.read_text(encoding="utf-8")
        for marker in required_markers:
            if marker not in text:
                doc_policy_violations.append(f"{relative_path}:{marker}")

    runtime_source_files: List[str] = []
    runtime_source_violations: List[str] = []
    seen_sources: Set[Path] = set()
    for pattern in runtime_source_globs:
        for path in sorted(repo_root.glob(pattern)):
            if path in seen_sources:
                continue
            seen_sources.add(path)
            runtime_source_files.append(str(path.relative_to(repo_root)))
            text = path.read_text(encoding="utf-8")
            for token in python_patterns:
                if re.search(token, text, flags=re.IGNORECASE):
                    runtime_source_violations.append(f"{path.relative_to(repo_root)}:{token}")

    portability_module_violations: List[str] = []
    scripts_scanned = sorted(set(module_requirements) | set(tempdir_scripts) | set(path_lookup_scripts))
    for relative_path, required_tokens in module_requirements.items():
        path = repo_root / relative_path
        if not path.exists():
            portability_module_violations.append(f"{relative_path}:missing")
            continue
        text = path.read_text(encoding="utf-8")
        if not re.search(PLATFORM_ASSUMPTIONS_IMPORT_PATTERN, text, flags=re.MULTILINE):
            portability_module_violations.append(f"{relative_path}:platform_assumptions import missing")
        for token in required_tokens:
            if token not in text:
                portability_module_violations.append(f"{relative_path}:{token}")

    tempdir_convention_violations: List[str] = []
    for relative_path in tempdir_scripts:
        path = repo_root / relative_path
        if not path.exists():
            tempdir_convention_violations.append(f"{relative_path}:missing")
            continue
        text = path.read_text(encoding="utf-8")
        if "TemporaryDirectory(prefix=" not in text:
            tempdir_convention_violations.append(relative_path)

    path_lookup_violations: List[str] = []
    for relative_path in path_lookup_scripts:
        path = repo_root / relative_path
        if not path.exists():
            path_lookup_violations.append(f"{relative_path}:missing")
            continue
        text = path.read_text(encoding="utf-8")
        if "find_command(" not in text:
            path_lookup_violations.append(relative_path)

    shell_assumption_violations: List[str] = []
    for relative_path in scripts_scanned:
        path = repo_root / relative_path
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        try:
            tree = ast.parse(text, filename=str(path))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                for keyword in node.keywords:
                    if keyword.arg == "shell" and isinstance(keyword.value, ast.Constant) and keyword.value.value is True:
                        shell_assumption_violations.append(f"{relative_path}:shell=True")
                if (
                    isinstance(node.func, ast.Attribute)
                    and isinstance(node.func.value, ast.Name)
                    and node.func.value.id == "os"
                    and node.func.attr == "system"
                ):
                    shell_assumption_violations.append(f"{relative_path}:os.system")

    return {
        "supported_platforms": list(SUPPORTED_FRONTEND_ENVIRONMENTS),
        "unsupported_platforms": list(UNSUPPORTED_FRONTEND_ENVIRONMENTS),
        "masked_python_interpreters": list(MASKED_PYTHON_INTERPRETERS),
        "python_invocation_patterns": list(python_patterns),
        "docs_scanned": docs_scanned,
        "missing_doc_files": missing_doc_files,
        "doc_policy_violations": doc_policy_violations,
        "runtime_source_files": runtime_source_files,
        "runtime_source_violations": runtime_source_violations,
        "scripts_scanned": scripts_scanned,
        "portability_module_violations": portability_module_violations,
        "tempdir_convention_violations": tempdir_convention_violations,
        "path_lookup_violations": path_lookup_violations,
        "shell_assumption_violations": shell_assumption_violations,
    }


def check_environment_assumptions(
    *,
    repo_root: Path = REPO_ROOT,
    doc_requirements: Dict[str, Sequence[str]] = ENVIRONMENT_DOC_REQUIREMENTS,
    runtime_source_globs: Sequence[str] = (
        "compiler_impl/src/*.adb",
        "compiler_impl/src/*.ads",
    ),
    python_patterns: Sequence[str] = STATIC_PYTHON_INVOCATION_PATTERNS,
    module_requirements: Dict[str, Sequence[str]] = PORTABILITY_MODULE_REQUIREMENTS,
    tempdir_scripts: Sequence[str] = PORTABILITY_TEMPDIR_SCRIPTS,
    path_lookup_scripts: Sequence[str] = PORTABILITY_PATH_LOOKUP_SCRIPTS,
) -> None:
    report = environment_assumptions_report(
        repo_root=repo_root,
        doc_requirements=doc_requirements,
        runtime_source_globs=runtime_source_globs,
        python_patterns=python_patterns,
        module_requirements=module_requirements,
        tempdir_scripts=tempdir_scripts,
        path_lookup_scripts=path_lookup_scripts,
    )
    if report["missing_doc_files"]:
        fail(f"missing portability docs: {report['missing_doc_files']}")
    if report["doc_policy_violations"]:
        fail(f"missing portability policy markers: {report['doc_policy_violations']}")
    if report["runtime_source_violations"]:
        fail(f"runtime sources still reference Python invocation patterns: {report['runtime_source_violations']}")
    if report["portability_module_violations"]:
        fail(
            "portability-sensitive scripts are not sourced from shared assumptions: "
            f"{report['portability_module_violations']}"
        )
    if report["tempdir_convention_violations"]:
        fail(
            "portability-sensitive scripts must use deterministic TemporaryDirectory prefixes: "
            f"{report['tempdir_convention_violations']}"
        )
    if report["path_lookup_violations"]:
        fail(
            "portability-sensitive scripts must use PATH-based command discovery: "
            f"{report['path_lookup_violations']}"
        )
    if report["shell_assumption_violations"]:
        fail(
            "portability-sensitive scripts must remain shell-free: "
            f"{report['shell_assumption_violations']}"
        )


def performance_scale_sanity_report(
    *,
    repo_root: Path = REPO_ROOT,
    doc_requirements: Dict[str, Sequence[str]] = PERFORMANCE_DOC_REQUIREMENTS,
) -> Dict[str, Any]:
    docs_scanned: List[str] = []
    missing_doc_files: List[str] = []
    doc_policy_violations: List[str] = []
    for relative_path, markers in doc_requirements.items():
        docs_scanned.append(relative_path)
        path = repo_root / relative_path
        if not path.exists():
            missing_doc_files.append(relative_path)
            continue
        text = path.read_text(encoding="utf-8")
        for marker in markers:
            if marker not in text:
                doc_policy_violations.append(f"{relative_path}:{marker}")
    return {
        "docs_scanned": docs_scanned,
        "missing_doc_files": missing_doc_files,
        "doc_policy_violations": doc_policy_violations,
    }


def check_performance_scale_sanity(
    *,
    repo_root: Path = REPO_ROOT,
    doc_requirements: Dict[str, Sequence[str]] = PERFORMANCE_DOC_REQUIREMENTS,
) -> None:
    report = performance_scale_sanity_report(
        repo_root=repo_root,
        doc_requirements=doc_requirements,
    )
    if report["missing_doc_files"]:
        fail(f"missing performance/scale docs: {report['missing_doc_files']}")
    if report["doc_policy_violations"]:
        fail(f"missing performance/scale policy markers: {report['doc_policy_violations']}")


def glue_script_safety_report(
    *,
    repo_root: Path = REPO_ROOT,
    audited_scripts: Sequence[str] = GLUE_SAFETY_AUDITED_SCRIPTS,
    report_scripts: Sequence[str] = GLUE_SAFETY_REPORT_SCRIPTS,
    path_commands: Sequence[str] = GLUE_SAFETY_PATH_COMMANDS,
    allowed_safe_source_readers: Dict[str, str] = GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS,
) -> Dict[str, Any]:
    missing_script_violations: List[str] = []
    subprocess_import_violations: List[str] = []
    subprocess_call_violations: List[str] = []
    shell_assumption_violations: List[str] = []
    tempdir_violations: List[str] = []
    report_helper_violations: List[str] = []
    command_lookup_violations: List[str] = []
    unauthorized_safe_source_readers: List[str] = []
    safe_source_readers: List[Dict[str, str]] = []

    for relative_path in audited_scripts:
        path = repo_root / relative_path
        if not path.exists():
            missing_script_violations.append(relative_path)
            continue

        text = path.read_text(encoding="utf-8")
        tree = ast.parse(text, filename=str(path))
        imported_subprocess_names: Set[str] = set()
        imported_tempfile_module_names: Set[str] = set()
        imported_tempfile_function_names: Dict[str, str] = {}
        imported_harness_names: Set[str] = set()
        imported_os_module_names: Set[str] = set()
        imported_os_shell_names: Dict[str, str] = {}
        imported_path_names: Set[str] = {"Path"}
        safe_source_bindings: Set[str] = set()

        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name == "subprocess":
                        subprocess_import_violations.append(f"{relative_path}:subprocess")
                        imported_subprocess_names.add(alias.asname or alias.name)
                    if alias.name == "tempfile":
                        imported_tempfile_module_names.add(alias.asname or alias.name)
                    if alias.name == "os":
                        imported_os_module_names.add(alias.asname or alias.name)
                    if alias.name == "pathlib":
                        imported_path_names.add(f"{alias.asname or alias.name}.Path")
            elif isinstance(node, ast.ImportFrom):
                if node.module == "subprocess":
                    for alias in node.names:
                        subprocess_import_violations.append(f"{relative_path}:subprocess.{alias.name}")
                        imported_subprocess_names.add(alias.asname or alias.name)
                elif node.module == "tempfile":
                    for alias in node.names:
                        imported_tempfile_function_names[alias.asname or alias.name] = alias.name
                elif node.module == "_lib.harness_common":
                    for alias in node.names:
                        imported_harness_names.add(alias.asname or alias.name)
                elif node.module == "os":
                    for alias in node.names:
                        name = alias.asname or alias.name
                        if alias.name in {"system", "popen"}:
                            imported_os_shell_names[name] = alias.name
                        else:
                            imported_os_module_names.add(name)
                elif node.module == "pathlib":
                    for alias in node.names:
                        if alias.name == "Path":
                            imported_path_names.add(alias.asname or alias.name)
            elif isinstance(node, ast.Assign):
                bound_name = _safe_source_binding_name(node.value, imported_path_names=imported_path_names)
                if bound_name is None:
                    continue
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        safe_source_bindings.add(target.id)

        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue

            call_name = _call_name(node.func)
            if call_name is None:
                continue

            base_name = call_name.split(".")[-1]
            tempfile_name = imported_tempfile_function_names.get(call_name, base_name)
            os_shell_name = imported_os_shell_names.get(call_name, base_name)

            if (
                call_name.startswith("subprocess.")
                or call_name in imported_subprocess_names
            ):
                subprocess_call_violations.append(f"{relative_path}:{call_name}")

            for keyword in node.keywords:
                if keyword.arg == "shell" and isinstance(keyword.value, ast.Constant) and keyword.value.value is True:
                    shell_assumption_violations.append(f"{relative_path}:shell=True")

            if (
                os_shell_name in {"system", "popen"}
                and (
                    call_name in {"os.system", "os.popen"}
                    or (
                        isinstance(node.func, ast.Attribute)
                        and isinstance(node.func.value, ast.Name)
                        and node.func.value.id in imported_os_module_names
                    )
                    or (
                        isinstance(node.func, ast.Name)
                        and node.func.id in imported_os_shell_names
                    )
                )
            ):
                shell_assumption_violations.append(f"{relative_path}:os.{os_shell_name}")

            if tempfile_name == "TemporaryDirectory":
                imported = (
                    call_name == "tempfile.TemporaryDirectory"
                    or (
                        isinstance(node.func, ast.Attribute)
                        and isinstance(node.func.value, ast.Name)
                        and node.func.value.id in imported_tempfile_module_names
                    )
                    or call_name in imported_tempfile_function_names
                )
                if imported and not _has_prefix_keyword(node):
                    tempdir_violations.append(f"{relative_path}:TemporaryDirectory")
            elif tempfile_name == "NamedTemporaryFile":
                imported = (
                    call_name == "tempfile.NamedTemporaryFile"
                    or (
                        isinstance(node.func, ast.Attribute)
                        and isinstance(node.func.value, ast.Name)
                        and node.func.value.id in imported_tempfile_module_names
                    )
                    or call_name in imported_tempfile_function_names
                )
                if imported and not _has_prefix_keyword(node):
                    tempdir_violations.append(f"{relative_path}:NamedTemporaryFile")
            elif tempfile_name == "mkdtemp":
                imported = (
                    call_name == "tempfile.mkdtemp"
                    or (
                        isinstance(node.func, ast.Attribute)
                        and isinstance(node.func.value, ast.Name)
                        and node.func.value.id in imported_tempfile_module_names
                    )
                    or call_name in imported_tempfile_function_names
                )
                if imported and not _has_prefix_keyword(node):
                    tempdir_violations.append(f"{relative_path}:mkdtemp")

            if call_name == "run" and node.args:
                argv = node.args[0]
                if isinstance(argv, (ast.List, ast.Tuple)) and argv.elts:
                    head = argv.elts[0]
                    if isinstance(head, ast.Constant) and isinstance(head.value, str):
                        command = head.value
                        if command in path_commands and f'find_command("{command}")' not in text and f"find_command('{command}')" not in text:
                            command_lookup_violations.append(f"{relative_path}:{command}")

            if relative_path not in allowed_safe_source_readers:
                safe_reader_violation = False
                if (
                    isinstance(node.func, ast.Name)
                    and node.func.id == "open"
                    and node.args
                ):
                    first_arg = node.args[0]
                    if (
                        isinstance(first_arg, ast.Constant)
                        and isinstance(first_arg.value, str)
                        and first_arg.value.endswith(".safe")
                    ) or (
                        isinstance(first_arg, ast.Name) and first_arg.id in safe_source_bindings
                    ):
                        safe_reader_violation = True
                elif (
                    isinstance(node.func, ast.Attribute)
                    and node.func.attr in {"read_text", "open"}
                ):
                    target = node.func.value
                    if isinstance(target, ast.Name) and target.id in safe_source_bindings:
                        safe_reader_violation = True
                    elif _safe_source_binding_name(target, imported_path_names=imported_path_names) is not None:
                        safe_reader_violation = True
                if safe_reader_violation:
                    unauthorized_safe_source_readers.append(f"{relative_path}:{node.func.attr if isinstance(node.func, ast.Attribute) else 'open'}")

        if relative_path in report_scripts:
            has_finalize = any(
                isinstance(node, ast.Call) and _call_name(node.func) == "finalize_deterministic_report"
                for node in ast.walk(tree)
            )
            has_write = any(
                isinstance(node, ast.Call) and _call_name(node.func) == "write_report"
                for node in ast.walk(tree)
            )
            if not has_finalize:
                report_helper_violations.append(f"{relative_path}:finalize_deterministic_report")
            if not has_write:
                report_helper_violations.append(f"{relative_path}:write_report")

        for command, patterns in GLUE_SAFETY_REPO_LOCAL_COMMAND_PATTERNS.items():
            if any(re.search(pattern, text) for pattern in patterns):
                if "require_repo_command(" not in text:
                    command_lookup_violations.append(f"{relative_path}:{command}")
                break

        if relative_path in allowed_safe_source_readers:
            safe_source_readers.append(
                {
                    "script": relative_path,
                    "category": allowed_safe_source_readers[relative_path],
                }
            )

        if (
            relative_path not in allowed_safe_source_readers
            and "read_expected_reason(" in text
            and "read_expected_reason" in imported_harness_names
        ):
            unauthorized_safe_source_readers.append(f"{relative_path}:read_expected_reason")

    return {
        "audited_scripts": list(audited_scripts),
        "report_scripts": list(report_scripts),
        "path_command_policy": list(path_commands),
        "safe_source_readers": safe_source_readers,
        "missing_script_violations": missing_script_violations,
        "subprocess_import_violations": subprocess_import_violations,
        "subprocess_call_violations": subprocess_call_violations,
        "shell_assumption_violations": shell_assumption_violations,
        "tempdir_violations": tempdir_violations,
        "report_helper_violations": report_helper_violations,
        "command_lookup_violations": command_lookup_violations,
        "unauthorized_safe_source_readers": unauthorized_safe_source_readers,
    }


def check_glue_script_safety(
    *,
    repo_root: Path = REPO_ROOT,
    audited_scripts: Sequence[str] = GLUE_SAFETY_AUDITED_SCRIPTS,
    report_scripts: Sequence[str] = GLUE_SAFETY_REPORT_SCRIPTS,
    path_commands: Sequence[str] = GLUE_SAFETY_PATH_COMMANDS,
    allowed_safe_source_readers: Dict[str, str] = GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS,
) -> None:
    report = glue_script_safety_report(
        repo_root=repo_root,
        audited_scripts=audited_scripts,
        report_scripts=report_scripts,
        path_commands=path_commands,
        allowed_safe_source_readers=allowed_safe_source_readers,
    )
    if report["missing_script_violations"]:
        fail(f"glue safety audit is missing expected scripts: {report['missing_script_violations']}")
    if report["subprocess_import_violations"]:
        fail(f"glue scripts import subprocess directly: {report['subprocess_import_violations']}")
    if report["subprocess_call_violations"]:
        fail(f"glue scripts call subprocess directly: {report['subprocess_call_violations']}")
    if report["shell_assumption_violations"]:
        fail(f"glue scripts are not shell-free: {report['shell_assumption_violations']}")
    if report["tempdir_violations"]:
        fail(f"glue scripts use non-deterministic temp APIs: {report['tempdir_violations']}")
    if report["report_helper_violations"]:
        fail(f"glue scripts bypass report helpers: {report['report_helper_violations']}")
    if report["command_lookup_violations"]:
        fail(f"glue scripts bypass PATH-based command discovery: {report['command_lookup_violations']}")
    if report["unauthorized_safe_source_readers"]:
        fail(
            "glue scripts read raw .safe source outside approved metadata paths: "
            f"{report['unauthorized_safe_source_readers']}"
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
    check_evidence_reproducibility(tracker)
    check_runtime_boundary()
    check_environment_assumptions()
    check_legacy_frontend_cleanup()
    check_glue_script_safety()
    check_performance_scale_sanity()
    print("execution state: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"execution state: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
