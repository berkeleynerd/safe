#!/usr/bin/env python3
"""Validate execution tracker invariants and scoped repo facts."""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Sequence, Set

from _lib.harness_common import (
    display_path,
    ensure_deterministic_env,
    evidence_policy_sha256,
    finalize_deterministic_report,
    find_command,
    load_evidence_policy,
    policy_metadata,
    require,
    resolve_generated_path,
    run,
    serialize_report,
    sha256_text,
    write_report,
)
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
FINALIZED_REPORT_METADATA_KEYS = frozenset({"deterministic", "report_sha256", "repeat_sha256"})
REPORT_SYNC_SPECS = {
    "execution/reports/pr09-ada-emission-baseline-report.json": {
        "entry_list_key": "slice_reports",
        "entry_id_key": "script",
        "entry_sha_key": "report_sha256",
        "children": {
            "scripts/run_pr09a_emitter_surface.py": "execution/reports/pr09a-emitter-surface-report.json",
            "scripts/run_pr09a_emitter_mvp.py": "execution/reports/pr09a-emitter-mvp-report.json",
            "scripts/run_pr09b_sequential_semantics.py": "execution/reports/pr09b-sequential-semantics-report.json",
            "scripts/run_pr09b_concurrency_output.py": "execution/reports/pr09b-concurrency-output-report.json",
            "scripts/run_pr09b_snapshot_refresh.py": "execution/reports/pr09b-snapshot-refresh-report.json",
        },
    },
    "execution/reports/pr10-emitted-baseline-report.json": {
        "entry_list_key": "slice_reports",
        "entry_id_key": "script",
        "entry_sha_key": "report_sha256",
        "children": {
            "scripts/run_pr10_contract_baseline.py": "execution/reports/pr10-contract-baseline-report.json",
            "scripts/run_pr10_emitted_flow.py": "execution/reports/pr10-emitted-flow-report.json",
            "scripts/run_pr10_emitted_prove.py": "execution/reports/pr10-emitted-prove-report.json",
        },
    },
}
PR101_CHILD_REPORTS = {
    "pr08_frontend_baseline": "execution/reports/pr08-frontend-baseline-report.json",
    "pr09_ada_emission_baseline": "execution/reports/pr09-ada-emission-baseline-report.json",
    "pr10_emitted_baseline": "execution/reports/pr10-emitted-baseline-report.json",
    "emitted_hardening_regressions": "execution/reports/emitted-hardening-regressions-report.json",
    "pr101a_companion_proof_verification": "execution/reports/pr101a-companion-proof-verification-report.json",
    "pr101b_template_proof_verification": "execution/reports/pr101b-template-proof-verification-report.json",
}
PERFORMANCE_DOC_REQUIREMENTS = {
    "docs/frontend_scale_limits.md": [
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
        "cliff-detection gate, not a benchmark commitment",
        "raw timings are intentionally kept out of committed evidence",
        "Fixed-point Rule 5 work, general discriminants, channels/tasks/concurrency, and other unsupported surfaces are out of scope",
    ],
    "compiler_impl/README.md": [
        "docs/frontend_scale_limits.md",
        "cliff-detection gate, not a benchmark commitment",
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
    ],
    "release/frontend_runtime_decision.md": [
        "docs/frontend_scale_limits.md",
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
        "PR08 starts from this cleaned PR07 baseline and must extend the live path rather than revive deleted legacy packages.",
    ],
}
DOCUMENTATION_ARCHITECTURE_DOC_REQUIREMENTS = {
    "README.md": [
        "docs/frontend_architecture_baseline.md",
        "docs/frontend_scale_limits.md",
        "compiler_impl/README.md",
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
        "Ada-native `safec lex` / `ast` / `validate-mir` / `analyze-mir` / `check` / `emit`",
        "Python remains glue/orchestration only around the compiler.",
        "PR08 is now the supported frontend baseline, and later work continues on that live Ada-native path rather than reviving deleted packages.",
    ],
    "compiler_impl/README.md": [
        "../docs/frontend_architecture_baseline.md",
        "../docs/frontend_scale_limits.md",
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
        "All current user-facing `safec` commands are Ada-native for that supported surface.",
        "Python remains glue/orchestration only around the compiler.",
        "The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.",
        "PR08 extends the live `Check_*` + `Mir_*` pipeline, and the current frontend baseline is now PR08.",
    ],
    "release/frontend_runtime_decision.md": [
        "../docs/frontend_architecture_baseline.md",
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
        "Ada-native runtime commands:",
        "Python is glue/orchestration only.",
        "The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.",
        "PR06.9.1 through PR06.9.13 established the hardened pre-PR07 baseline, and PR07 extends that same live path.",
        "PR08 starts from this cleaned PR07 baseline and must extend the live path rather than revive deleted legacy packages.",
    ],
    "docs/frontend_architecture_baseline.md": [
        "`safec lex`",
        "`safec ast`",
        "`safec validate-mir`",
        "`safec analyze-mir`",
        "`safec check`",
        "`safec emit`",
        "Python is glue/orchestration only.",
        "No user-facing `safec` command depends on Python at runtime.",
        "`Check_*`",
        "`Mir_*`",
        "`Lexer`",
        "`Source`",
        "`Types`",
        "`Diagnostics`",
        "`Json`",
        "The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.",
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
        "PR08 extends the live path rather than reviving deleted legacy packages, and the current supported frontend baseline is now PR08 rather than PR07.",
    ],
    "docs/frontend_scale_limits.md": [
        "frontend_architecture_baseline.md",
        "the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern",
    ],
}
DOCUMENTATION_ARCHITECTURE_REQUIRED_LINKS = {
    "README.md": [
        "docs/frontend_architecture_baseline.md",
        "docs/frontend_scale_limits.md",
        "compiler_impl/README.md",
    ],
    "compiler_impl/README.md": [
        "../docs/frontend_architecture_baseline.md",
        "../docs/frontend_scale_limits.md",
    ],
    "release/frontend_runtime_decision.md": [
        "../docs/frontend_architecture_baseline.md",
    ],
    "docs/frontend_scale_limits.md": [
        "frontend_architecture_baseline.md",
    ],
}
DOCUMENTATION_ARCHITECTURE_STALE_MARKERS = {
    "README.md": [
        "PR00–PR06.9.1 sequential frontend landed",
        "EXEC_SUMMARY.md",
        "CHANGELOG.md",
        "PR07 starts from the cleaned PR06.9.x frontend baseline.",
    ],
    "compiler_impl/README.md": [
        "through PR06.9.8",
        "through PR06.9.12",
        "PR06.8 runtime doctrine:",
        "PR06.9.3 hardens that boundary",
        "PR06.9.10 hardens portability assumptions",
        "PR07 must extend the live `Check_*` + `Mir_*` pipeline.",
    ],
    "release/frontend_runtime_decision.md": [
        "PR06.5 and PR06.6 removed the MIR validator and MIR analyzer",
        "PR06.8 cuts `safec ast` and `safec emit` over",
        "Before `PR07`, the roadmap now inserts a `PR06.9.1` through `PR06.9.13` stabilization series",
        "PR07 starts from this cleaned baseline and must extend the live path rather than revive deleted legacy packages.",
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
    "scripts/run_pr081_local_concurrency_frontend.py",
    "scripts/run_pr082_local_concurrency_analysis.py",
    "scripts/run_pr083_interface_contracts.py",
    "scripts/run_pr083a_public_constants.py",
    "scripts/run_pr09a_emitter_surface.py",
    "scripts/run_pr09a_emitter_mvp.py",
    "scripts/run_pr09b_sequential_semantics.py",
    "scripts/run_pr09b_concurrency_output.py",
    "scripts/run_pr09b_snapshot_refresh.py",
    "scripts/run_pr09_ada_emission_baseline.py",
]
PORTABILITY_PATH_LOOKUP_SCRIPTS = [
    "scripts/run_pr0693_runtime_boundary.py",
    "scripts/run_pr068_ada_ast_emit_no_python.py",
    "scripts/run_pr06910_portability_environment.py",
    "scripts/run_pr081_local_concurrency_frontend.py",
    "scripts/run_pr082_local_concurrency_analysis.py",
    "scripts/run_pr083_interface_contracts.py",
    "scripts/run_pr083a_public_constants.py",
    "scripts/_lib/pr09_emit.py",
    "scripts/run_pr09_ada_emission_baseline.py",
    "scripts/run_local_pre_push.py",
]
GLUE_SAFETY_AUDITED_SCRIPTS = [
    "safe",
    "scripts/_lib/gate_manifest.py",
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
    "scripts/run_pr081_local_concurrency_frontend.py",
    "scripts/run_pr082_local_concurrency_analysis.py",
    "scripts/run_pr083_interface_contracts.py",
    "scripts/run_pr083a_public_constants.py",
    "scripts/_lib/pr09_emit.py",
    "scripts/run_pr09a_emitter_surface.py",
    "scripts/run_pr09a_emitter_mvp.py",
    "scripts/run_pr09b_sequential_semantics.py",
    "scripts/run_pr09b_concurrency_output.py",
    "scripts/run_pr09b_snapshot_refresh.py",
    "scripts/run_pr09_ada_emission_baseline.py",
    "scripts/run_pr102_rule5_boundary_closure.py",
    "scripts/run_pr103_sequential_proof_expansion.py",
    "scripts/run_pr104_gnatprove_evidence_parser_hardening.py",
    "scripts/run_pr105_ada_emitter_maintenance_hardening.py",
    "scripts/run_pr106_sequential_proof_corpus_expansion.py",
    "scripts/safe_cli.py",
    "scripts/safe_lsp.py",
    "scripts/run_rosetta_corpus.py",
    "scripts/run_pr111_language_evaluation_harness.py",
    "scripts/run_pr112_parser_completeness_phase1.py",
    "scripts/run_pr113_discriminated_types_tuples_structured_returns.py",
    "scripts/run_pr113a_proof_checkpoint1.py",
    "scripts/run_pr114_signature_control_flow_syntax.py",
    "scripts/run_gate_pipeline.py",
    "scripts/run_local_pre_push.py",
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
    "scripts/run_pr081_local_concurrency_frontend.py",
    "scripts/run_pr082_local_concurrency_analysis.py",
    "scripts/run_pr083_interface_contracts.py",
    "scripts/run_pr083a_public_constants.py",
    "scripts/run_pr09a_emitter_surface.py",
    "scripts/run_pr09a_emitter_mvp.py",
    "scripts/run_pr09b_sequential_semantics.py",
    "scripts/run_pr09b_concurrency_output.py",
    "scripts/run_pr09b_snapshot_refresh.py",
    "scripts/run_pr09_ada_emission_baseline.py",
    "scripts/run_pr102_rule5_boundary_closure.py",
    "scripts/run_pr103_sequential_proof_expansion.py",
    "scripts/run_pr104_gnatprove_evidence_parser_hardening.py",
    "scripts/run_pr105_ada_emitter_maintenance_hardening.py",
    "scripts/run_pr106_sequential_proof_corpus_expansion.py",
    "scripts/run_rosetta_corpus.py",
    "scripts/run_pr111_language_evaluation_harness.py",
    "scripts/run_pr112_parser_completeness_phase1.py",
    "scripts/run_pr113_discriminated_types_tuples_structured_returns.py",
    "scripts/run_pr113a_proof_checkpoint1.py",
    "scripts/run_pr114_signature_control_flow_syntax.py",
]
GLUE_SAFETY_PATH_COMMANDS = ("python3", "alr", "git")
GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS = {
    "scripts/run_pr05_d27_harness.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr06_ownership_harness.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr0691_semantic_correctness.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr081_local_concurrency_frontend.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr082_local_concurrency_analysis.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr083_interface_contracts.py": "fixture metadata extraction via read_expected_reason",
    "scripts/run_pr083a_public_constants.py": "fixture metadata extraction via read_expected_reason and synthetic parity source generation",
    "scripts/run_pr102_rule5_boundary_closure.py": "fixture metadata extraction via read_expected_reason and diagnostics golden comparison",
    "scripts/run_pr103_sequential_proof_expansion.py": "fixture source-fragment checks and emitted structural assertions for the fixed PR10.3 ownership corpus",
    "scripts/run_pr106_sequential_proof_corpus_expansion.py": "fixture source-fragment checks and emitted structural assertions for the fixed PR10.6 sequential corpus",
    "scripts/run_pr113a_proof_checkpoint1.py": "fixture source-fragment checks and emitted structural assertions for the fixed PR11.3a sequential checkpoint corpus",
    "scripts/run_pr114_signature_control_flow_syntax.py": "fixture source-fragment checks and emitted structural assertions for the fixed PR11.4 syntax cutover corpus",
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
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]+\]\(([^)]+)\)")
EVIDENCE_POLICY = load_evidence_policy()
EVIDENCE_POLICY_SHA256 = evidence_policy_sha256(EVIDENCE_POLICY)
GENERATED_OUTPUTS_POLICY = EVIDENCE_POLICY["generated_outputs"]
DOCUMENTATION_POLICY = EVIDENCE_POLICY["documentation_architecture"]
PORTABILITY_POLICY = EVIDENCE_POLICY["portability"]
GLUE_SAFETY_POLICY = EVIDENCE_POLICY["glue_safety"]
ENVIRONMENT_POLICY = EVIDENCE_POLICY["environment"]
EXECUTION_STATE_REPORT_PATH = REPO_ROOT / GENERATED_OUTPUTS_POLICY["reports_root"] / "execution-state-validation-report.json"
EXECUTION_STATE_EVIDENCE = str(EXECUTION_STATE_REPORT_PATH.relative_to(REPO_ROOT))

# Runtime values are policy-backed even though the historical literal defaults
# remain above for audit readability and diff review.
DOCUMENTATION_ARCHITECTURE_DOC_REQUIREMENTS = DOCUMENTATION_POLICY["doc_requirements"]
DOCUMENTATION_ARCHITECTURE_REQUIRED_LINKS = DOCUMENTATION_POLICY["required_links"]
DOCUMENTATION_ARCHITECTURE_STALE_MARKERS = DOCUMENTATION_POLICY["stale_markers"]
PORTABILITY_MODULE_REQUIREMENTS = PORTABILITY_POLICY["module_requirements"]
ENVIRONMENT_DOC_REQUIREMENTS = PORTABILITY_POLICY["doc_requirements"]
PORTABILITY_TEMPDIR_SCRIPTS = PORTABILITY_POLICY["tempdir_scripts"]
PORTABILITY_PATH_LOOKUP_SCRIPTS = PORTABILITY_POLICY["path_lookup_scripts"]
GLUE_SAFETY_AUDITED_SCRIPTS = GLUE_SAFETY_POLICY["audited_scripts"]
GLUE_SAFETY_REPORT_SCRIPTS = GLUE_SAFETY_POLICY["report_scripts"]
GLUE_SAFETY_PATH_COMMANDS = tuple(GLUE_SAFETY_POLICY["path_commands"])
GLUE_SAFETY_ALLOWED_SAFE_SOURCE_READERS = GLUE_SAFETY_POLICY["allowed_safe_source_readers"]


def fail(message: str) -> None:
    raise ValueError(message)


def generated_repo_path(path: Path, *, generated_root: Path | None) -> Path:
    return resolve_generated_path(
        path,
        generated_root=generated_root,
        policy=EVIDENCE_POLICY,
        repo_root=REPO_ROOT,
    )


def policy_fields(*, sections: list[str]) -> dict[str, Any]:
    return policy_metadata(policy_sha256=EVIDENCE_POLICY_SHA256, sections=sections)


def check_generated_output_cleanliness(*, env: dict[str, str]) -> None:
    git = find_command("git")
    reports_root = Path(GENERATED_OUTPUTS_POLICY["reports_root"])
    dashboard = Path(GENERATED_OUTPUTS_POLICY["dashboard"])
    result = run(
        [
            git,
            "status",
            "--porcelain",
            "--untracked-files=no",
            "--",
            str(reports_root),
            str(dashboard),
        ],
        cwd=REPO_ROOT,
        env=env,
    )
    lines = result["stdout"].splitlines()
    lines.sort()
    if lines:
        fail(
            "ratchet-owned generated outputs must be clean before preflight:\n"
            + "\n".join(lines)
        )


def require_sorted_strings(values: Sequence[str], *, label: str) -> None:
    if list(values) != sorted(values):
        fail(f"{label} must be sorted by repo-relative path")


def tool_first_line(argv: list[str], *, env: dict[str, str]) -> str:
    result = run(argv, cwd=REPO_ROOT, env=env)
    line = result["stdout"].splitlines()[0].strip() if result["stdout"].splitlines() else ""
    if not line:
        fail(f"unable to determine tool version from {' '.join(argv)}")
    return line


def resolve_tool_command(*, authority: str, name: str) -> str:
    toolchain_pins = ENVIRONMENT_POLICY[authority].get("toolchain_pins", {})
    toolchain_root = Path.home() / ".local" / "share" / "alire" / "toolchains"
    if name == "gnat":
        pin = toolchain_pins.get("gnat_native")
        if pin:
            matches = sorted(toolchain_root.glob(f"gnat_native_{pin}_*/bin/gnat"))
            if matches:
                return str(matches[0])
    elif name == "gprbuild":
        pin = toolchain_pins.get("gprbuild")
        if pin:
            matches = sorted(toolchain_root.glob(f"gprbuild_{pin}_*/bin/gprbuild"))
            if matches:
                return str(matches[0])
    elif name == "gnatprove":
        fallback = Path.home() / ".alire" / "bin" / "gnatprove"
        if fallback.exists():
            return str(fallback)
        return find_command(name, fallback=fallback)
    return find_command(name)


def normalized_python_version() -> str:
    return f"{sys.version_info.major}.{sys.version_info.minor}"


def check_environment_preconditions(*, authority: str, env: dict[str, str]) -> dict[str, Any]:
    required_env = ENVIRONMENT_POLICY["required_env"]
    env_violations: list[str] = []
    for key, value in required_env.items():
        if env.get(key) != value:
            env_violations.append(f"{key}={env.get(key)!r} expected {value!r}")

    python_versions = ENVIRONMENT_POLICY[authority]["python_versions"]
    python_version = normalized_python_version()
    if python_version not in python_versions:
        fail(f"python {python_version} not permitted for authority {authority}: {python_versions}")

    gnat_versions = ENVIRONMENT_POLICY[authority]["gnat_versions"]
    gnat_version = tool_first_line([resolve_tool_command(authority=authority, name="gnat"), "--version"], env=env)
    if not any(gnat_version.startswith(prefix) for prefix in gnat_versions):
        fail(f"gnat version {gnat_version!r} not permitted for authority {authority}: {gnat_versions}")

    gnatprove_versions = ENVIRONMENT_POLICY[authority]["gnatprove_versions"]
    gnatprove_version = tool_first_line(
        [resolve_tool_command(authority=authority, name="gnatprove"), "--version"],
        env=env,
    )
    if not any(gnatprove_version.startswith(prefix) for prefix in gnatprove_versions):
        fail(
            f"gnatprove version {gnatprove_version!r} not permitted for authority {authority}: {gnatprove_versions}"
        )

    gprbuild_versions = ENVIRONMENT_POLICY[authority]["gprbuild_versions"]
    gprbuild_version = tool_first_line(
        [resolve_tool_command(authority=authority, name="gprbuild"), "--version"],
        env=env,
    )
    if not any(gprbuild_version.startswith(prefix) for prefix in gprbuild_versions):
        fail(
            f"gprbuild version {gprbuild_version!r} not permitted for authority {authority}: {gprbuild_versions}"
        )

    alr_candidates = ENVIRONMENT_POLICY[authority]["alr_paths"]
    alr_path = ""
    for candidate in alr_candidates:
        expanded = Path(candidate.replace("~", str(Path.home())))
        try:
            alr_path = find_command(expanded.name if candidate == "alr" else str(expanded), fallback=expanded)
            break
        except FileNotFoundError:
            continue
    if not alr_path:
        fail(f"alr not found for authority {authority}: {alr_candidates}")

    if env_violations:
        fail(f"deterministic environment violations: {env_violations}")

    return {
        **policy_fields(sections=["environment"]),
        "authority": authority,
        "required_env": required_env,
        "python_version": python_version,
        "gnat_version": gnat_version,
        "gnatprove_version": gnatprove_version,
        "gprbuild_version": gprbuild_version,
        "alr_path": alr_path,
        "toolchain_pins": dict(ENVIRONMENT_POLICY[authority].get("toolchain_pins", {})),
    }


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


def _unwrap_str_call(node: ast.AST) -> ast.AST:
    if (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "str"
        and len(node.args) == 1
        and not node.keywords
    ):
        return node.args[0]
    return node


def _repo_local_command_for_expr(
    node: ast.AST,
    *,
    command_bindings: Dict[str, Set[str]],
) -> str | None:
    candidate = _unwrap_str_call(node)
    if isinstance(candidate, ast.Name):
        for command, bindings in command_bindings.items():
            if candidate.id in bindings:
                return command
        return None
    try:
        candidate_text = ast.unparse(candidate)
    except Exception:
        return None
    for command, patterns in GLUE_SAFETY_REPO_LOCAL_COMMAND_PATTERNS.items():
        if any(re.search(pattern, candidate_text) for pattern in patterns):
            return command
    return None


def _require_repo_command_info(
    node: ast.AST,
    *,
    command_bindings: Dict[str, Set[str]],
) -> tuple[str | None, str | None]:
    if not isinstance(node, ast.Call) or _call_name(node.func) != "require_repo_command" or len(node.args) < 2:
        return (None, None)

    command_name: str | None = None
    command_literal = node.args[1]
    if isinstance(command_literal, ast.Constant) and isinstance(command_literal.value, str):
        if command_literal.value in GLUE_SAFETY_REPO_LOCAL_COMMAND_PATTERNS:
            command_name = command_literal.value

    resolved_from_expr = _repo_local_command_for_expr(node.args[0], command_bindings=command_bindings)
    if command_name is None:
        command_name = resolved_from_expr
    elif resolved_from_expr is not None and resolved_from_expr != command_name:
        return (None, None)

    if command_name is None:
        return (None, None)

    candidate = _unwrap_str_call(node.args[0])
    if isinstance(candidate, ast.Name):
        return (command_name, candidate.id)
    return (command_name, None)


def _local_markdown_links(text: str) -> list[str]:
    links: list[str] = []
    for target in MARKDOWN_LINK_PATTERN.findall(text):
        candidate = target.strip()
        if not candidate or candidate.startswith("#"):
            continue
        if "://" in candidate or candidate.startswith("mailto:"):
            continue
        links.append(candidate)
    return links


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
        entries = list((tests_root / subdir).iterdir())
        if subdir == "golden":
            count = len([entry for entry in entries if entry.is_dir()])
        else:
            count = len([entry for entry in entries if entry.is_file()])
        distribution[subdir] = count
        total += count
    distribution["total"] = total
    return distribution


def check_test_distribution(tracker: Dict[str, Any], *, tests_root: Path = REPO_ROOT / "tests") -> None:
    expected = tracker["repo_facts"]["tests"]
    actual = count_test_files(tests_root)
    if expected != actual:
        fail(f"test distribution mismatch: expected {expected}, actual {actual}")


def check_dashboard_freshness(tracker: Dict[str, Any], *, generated_root: Path | None = None) -> None:
    rendered = render_dashboard(tracker)
    existing = generated_repo_path(DASHBOARD_PATH, generated_root=generated_root).read_text(encoding="utf-8")
    if rendered != existing:
        fail("execution/dashboard.md is stale; run scripts/render_execution_status.py --write")


def finalized_report_sha(payload: Dict[str, Any]) -> str:
    base_payload = {key: value for key, value in payload.items() if key not in FINALIZED_REPORT_METADATA_KEYS}
    return sha256_text(serialize_report(base_payload))


def report_sync_report(
    *,
    repo_root: Path = REPO_ROOT,
    generated_root: Path | None = None,
    report_specs: Dict[str, Dict[str, Any]] = REPORT_SYNC_SPECS,
) -> Dict[str, Any]:
    umbrella_reports = sorted(report_specs)
    child_reports_checked: Set[str] = set()
    missing_files: List[str] = []
    invalid_reports: List[str] = []
    metadata_hash_violations: List[str] = []
    missing_entries: List[str] = []
    unexpected_entries: List[str] = []
    child_report_sha_mismatches: List[str] = []

    for umbrella_rel in umbrella_reports:
        spec = report_specs[umbrella_rel]
        umbrella_path = generated_repo_path(repo_root / umbrella_rel, generated_root=generated_root)
        if not umbrella_path.exists():
            missing_files.append(umbrella_rel)
            continue
        try:
            umbrella_payload = json.loads(umbrella_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            invalid_reports.append(f"{umbrella_rel}: invalid JSON ({exc.msg})")
            continue
        if not isinstance(umbrella_payload, dict):
            invalid_reports.append(f"{umbrella_rel}: report root must be an object")
            continue

        umbrella_expected_sha = finalized_report_sha(umbrella_payload)
        if (
            umbrella_payload.get("deterministic") is not True
            or umbrella_payload.get("report_sha256") != umbrella_expected_sha
            or umbrella_payload.get("repeat_sha256") != umbrella_expected_sha
        ):
            metadata_hash_violations.append(
                f"{umbrella_rel}: expected report_sha256/repeat_sha256 {umbrella_expected_sha}"
            )

        entries = umbrella_payload.get(spec["entry_list_key"])
        if not isinstance(entries, list):
            invalid_reports.append(f"{umbrella_rel}: missing list {spec['entry_list_key']}")
            continue

        actual_entries: Dict[str, str] = {}
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                invalid_reports.append(f"{umbrella_rel}: {spec['entry_list_key']}[{index}] must be an object")
                continue
            entry_id = entry.get(spec["entry_id_key"])
            entry_sha = entry.get(spec["entry_sha_key"])
            if not isinstance(entry_id, str) or not isinstance(entry_sha, str):
                invalid_reports.append(
                    f"{umbrella_rel}: {spec['entry_list_key']}[{index}] missing {spec['entry_id_key']} or {spec['entry_sha_key']}"
                )
                continue
            actual_entries[entry_id] = entry_sha

        expected_children: Dict[str, str] = spec["children"]
        for entry_id in sorted(expected_children):
            if entry_id not in actual_entries:
                missing_entries.append(f"{umbrella_rel}:{entry_id}")
                continue
            child_rel = expected_children[entry_id]
            child_reports_checked.add(child_rel)
            child_path = generated_repo_path(repo_root / child_rel, generated_root=generated_root)
            if not child_path.exists():
                missing_files.append(child_rel)
                continue
            try:
                child_payload = json.loads(child_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                invalid_reports.append(f"{child_rel}: invalid JSON ({exc.msg})")
                continue
            if not isinstance(child_payload, dict):
                invalid_reports.append(f"{child_rel}: report root must be an object")
                continue

            child_expected_sha = finalized_report_sha(child_payload)
            if (
                child_payload.get("deterministic") is not True
                or child_payload.get("report_sha256") != child_expected_sha
                or child_payload.get("repeat_sha256") != child_expected_sha
            ):
                metadata_hash_violations.append(
                    f"{child_rel}: expected report_sha256/repeat_sha256 {child_expected_sha}"
                )
            if actual_entries[entry_id] != child_expected_sha:
                child_report_sha_mismatches.append(
                    f"{umbrella_rel}:{entry_id}->{child_rel} expected {actual_entries[entry_id]} actual {child_expected_sha}"
                )

        for entry_id in sorted(actual_entries):
            if entry_id not in expected_children:
                unexpected_entries.append(f"{umbrella_rel}:{entry_id}")

    return {
        "umbrella_reports": umbrella_reports,
        "child_reports_checked": sorted(child_reports_checked),
        "missing_files": missing_files,
        "invalid_reports": invalid_reports,
        "metadata_hash_violations": metadata_hash_violations,
        "missing_entries": missing_entries,
        "unexpected_entries": unexpected_entries,
        "child_report_sha_mismatches": child_report_sha_mismatches,
    }


def check_report_sync(
    *,
    repo_root: Path = REPO_ROOT,
    generated_root: Path | None = None,
    report_specs: Dict[str, Dict[str, Any]] = REPORT_SYNC_SPECS,
) -> None:
    report = report_sync_report(repo_root=repo_root, generated_root=generated_root, report_specs=report_specs)
    if report["missing_files"]:
        fail(f"missing synchronized reports: {report['missing_files']}")
    if report["invalid_reports"]:
        fail(f"invalid synchronized reports: {report['invalid_reports']}")
    if report["metadata_hash_violations"]:
        fail(f"synchronized report hash metadata drifted: {report['metadata_hash_violations']}")
    if report["missing_entries"]:
        fail(f"umbrella reports are missing expected child entries: {report['missing_entries']}")
    if report["unexpected_entries"]:
        fail(f"umbrella reports contain unexpected child entries: {report['unexpected_entries']}")
    if report["child_report_sha_mismatches"]:
        fail(f"umbrella reports reference stale child report hashes: {report['child_report_sha_mismatches']}")


def check_pr101_report_sync(
    *,
    repo_root: Path = REPO_ROOT,
    generated_root: Path | None = None,
) -> None:
    pr101_rel = "execution/reports/pr101-comprehensive-audit-report.json"
    pr101_path = generated_repo_path(repo_root / pr101_rel, generated_root=generated_root)
    payload = json.loads(pr101_path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), f"{pr101_rel}: report root must be an object")
    expected_sha = finalized_report_sha(payload)
    if (
        payload.get("deterministic") is not True
        or payload.get("report_sha256") != expected_sha
        or payload.get("repeat_sha256") != expected_sha
    ):
        fail(f"{pr101_rel}: expected report_sha256/repeat_sha256 {expected_sha}")

    floor = payload.get("semantic_floor")
    require(isinstance(floor, dict), f"{pr101_rel}: semantic_floor must be an object")
    baseline_gate_hashes = floor.get("baseline_gate_hashes")
    require(isinstance(baseline_gate_hashes, dict), f"{pr101_rel}: missing semantic_floor.baseline_gate_hashes")
    child_report_hashes = floor.get("child_report_hashes")
    require(isinstance(child_report_hashes, dict), f"{pr101_rel}: missing semantic_floor.child_report_hashes")

    for node_id, child_rel in PR101_CHILD_REPORTS.items():
        child_path = generated_repo_path(repo_root / child_rel, generated_root=generated_root)
        child_payload = json.loads(child_path.read_text(encoding="utf-8"))
        require(isinstance(child_payload, dict), f"{child_rel}: report root must be an object")
        child_sha = finalized_report_sha(child_payload)
        if (
            child_payload.get("deterministic") is not True
            or child_payload.get("report_sha256") != child_sha
            or child_payload.get("repeat_sha256") != child_sha
        ):
            fail(f"{child_rel}: expected report_sha256/repeat_sha256 {child_sha}")

        if node_id.startswith("pr101"):
            recorded = child_report_hashes.get(node_id)
            require(recorded == child_sha, f"{pr101_rel}: {node_id} hash mismatch")
        else:
            recorded = baseline_gate_hashes.get(node_id)
            require(recorded == child_sha, f"{pr101_rel}: {node_id} hash mismatch")


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
    generated_root: Path | None = None,
    forbidden_markers: Sequence[str] = EVIDENCE_FORBIDDEN_MARKERS,
    ignored_evidence: Sequence[str] = (),
) -> Dict[str, Any]:
    evidence_files: List[str] = []
    missing_files: List[str] = []
    noncanonical_files: List[str] = []
    tool_version_fields: List[str] = []
    marker_violations: List[str] = []
    seen: Set[str] = set()
    ignored = set(ignored_evidence)

    for task in tracker.get("tasks", []):
        if task.get("status") != "done":
            continue
        for evidence in task.get("evidence", []):
            if not evidence.endswith(".json") or evidence in seen or evidence in ignored:
                continue
            seen.add(evidence)
            evidence_files.append(evidence)
            path = generated_repo_path(repo_root / evidence, generated_root=generated_root)
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
    generated_root: Path | None = None,
    ignored_evidence: Sequence[str] = (),
) -> None:
    report = evidence_reproducibility_report(
        tracker=tracker,
        repo_root=repo_root,
        generated_root=generated_root,
        ignored_evidence=ignored_evidence,
    )
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
        if "TemporaryDirectory(prefix=" not in text and "managed_scratch_root(" not in text:
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
        **policy_fields(sections=["environment", "portability"]),
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


def documentation_architecture_clarity_report(
    *,
    repo_root: Path = REPO_ROOT,
    doc_requirements: Dict[str, Sequence[str]] = DOCUMENTATION_ARCHITECTURE_DOC_REQUIREMENTS,
    required_links: Dict[str, Sequence[str]] = DOCUMENTATION_ARCHITECTURE_REQUIRED_LINKS,
    stale_markers: Dict[str, Sequence[str]] = DOCUMENTATION_ARCHITECTURE_STALE_MARKERS,
) -> Dict[str, Any]:
    docs_scanned = sorted(set(doc_requirements) | set(required_links) | set(stale_markers))
    missing_doc_files: List[str] = []
    doc_policy_violations: List[str] = []
    missing_required_links: List[str] = []
    unresolved_local_links: List[str] = []
    stale_boundary_violations: List[str] = []

    for relative_path in docs_scanned:
        path = repo_root / relative_path
        if not path.exists():
            missing_doc_files.append(relative_path)
            continue
        text = path.read_text(encoding="utf-8")
        for marker in doc_requirements.get(relative_path, []):
            if marker not in text:
                doc_policy_violations.append(f"{relative_path}:{marker}")
        for marker in stale_markers.get(relative_path, []):
            if marker in text:
                stale_boundary_violations.append(f"{relative_path}:{marker}")

        local_links = _local_markdown_links(text)
        link_targets = {target.split("#", 1)[0] for target in local_links}
        for target in required_links.get(relative_path, []):
            if target not in link_targets:
                missing_required_links.append(f"{relative_path}:{target}")

        for target in local_links:
            clean_target = target.split("#", 1)[0]
            if not clean_target:
                continue
            candidate = Path(clean_target)
            if candidate.is_absolute():
                unresolved_local_links.append(f"{relative_path}:{target}")
                continue
            resolved = (path.parent / clean_target).resolve()
            try:
                resolved.relative_to(repo_root.resolve())
            except ValueError:
                unresolved_local_links.append(f"{relative_path}:{target}")
                continue
            if not resolved.exists():
                unresolved_local_links.append(f"{relative_path}:{target}")

    return {
        **policy_fields(sections=["documentation_architecture"]),
        "docs_scanned": docs_scanned,
        "missing_doc_files": missing_doc_files,
        "doc_policy_violations": doc_policy_violations,
        "missing_required_links": missing_required_links,
        "unresolved_local_links": unresolved_local_links,
        "stale_boundary_violations": stale_boundary_violations,
    }


def check_documentation_architecture_clarity(
    *,
    repo_root: Path = REPO_ROOT,
    doc_requirements: Dict[str, Sequence[str]] = DOCUMENTATION_ARCHITECTURE_DOC_REQUIREMENTS,
    required_links: Dict[str, Sequence[str]] = DOCUMENTATION_ARCHITECTURE_REQUIRED_LINKS,
    stale_markers: Dict[str, Sequence[str]] = DOCUMENTATION_ARCHITECTURE_STALE_MARKERS,
) -> None:
    report = documentation_architecture_clarity_report(
        repo_root=repo_root,
        doc_requirements=doc_requirements,
        required_links=required_links,
        stale_markers=stale_markers,
    )
    if report["missing_doc_files"]:
        fail(f"missing architecture-baseline docs: {report['missing_doc_files']}")
    if report["doc_policy_violations"]:
        fail(f"missing architecture/boundary policy markers: {report['doc_policy_violations']}")
    if report["missing_required_links"]:
        fail(f"missing architecture/boundary cross-links: {report['missing_required_links']}")
    if report["unresolved_local_links"]:
        fail(f"unresolved local markdown links: {report['unresolved_local_links']}")
    if report["stale_boundary_violations"]:
        fail(f"stale frontend-boundary wording remains: {report['stale_boundary_violations']}")


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
        repo_local_command_bindings: Dict[str, Set[str]] = {
            command: set() for command in GLUE_SAFETY_REPO_LOCAL_COMMAND_PATTERNS
        }
        validated_repo_local_command_bindings: Dict[str, Set[str]] = {
            command: set() for command in GLUE_SAFETY_REPO_LOCAL_COMMAND_PATTERNS
        }

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
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        if bound_name is not None:
                            safe_source_bindings.add(target.id)
                        repo_local_command = _repo_local_command_for_expr(
                            node.value,
                            command_bindings=repo_local_command_bindings,
                        )
                        if repo_local_command is not None:
                            repo_local_command_bindings[repo_local_command].add(target.id)
                        required_command, _ = _require_repo_command_info(
                            node.value,
                            command_bindings=repo_local_command_bindings,
                        )
                        if required_command is not None:
                            repo_local_command_bindings[required_command].add(target.id)
                            validated_repo_local_command_bindings[required_command].add(target.id)

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
                    repo_local_command = _repo_local_command_for_expr(
                        head,
                        command_bindings=repo_local_command_bindings,
                    )
                    if repo_local_command is not None:
                        candidate = _unwrap_str_call(head)
                        if not (
                            isinstance(candidate, ast.Name)
                            and candidate.id in validated_repo_local_command_bindings[repo_local_command]
                        ):
                            command_lookup_violations.append(f"{relative_path}:{repo_local_command}")

            required_command, required_name = _require_repo_command_info(
                node,
                command_bindings=repo_local_command_bindings,
            )
            if required_command is not None and required_name is not None:
                validated_repo_local_command_bindings[required_command].add(required_name)

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
        **policy_fields(sections=["glue_safety"]),
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


POLICY_BACKED_REPORTS = [
    REPO_ROOT / "execution" / "reports" / "pr06910-portability-environment-report.json",
    REPO_ROOT / "execution" / "reports" / "pr06911-glue-script-safety-report.json",
    REPO_ROOT / "execution" / "reports" / "pr06913-documentation-architecture-clarity-report.json",
]


def check_policy_anchoring(*, generated_root: Path | None = None) -> list[str]:
    violations: list[str] = []
    for path in POLICY_BACKED_REPORTS:
        resolved = generated_repo_path(path, generated_root=generated_root)
        if not resolved.exists():
            violations.append(f"missing {display_path(path, repo_root=REPO_ROOT)}")
            continue
        payload = json.loads(resolved.read_text(encoding="utf-8"))
        if payload.get("policy_sha256") != EVIDENCE_POLICY_SHA256:
            violations.append(f"{display_path(path, repo_root=REPO_ROOT)}:policy_sha256")
        if not payload.get("policy_sections_used"):
            violations.append(f"{display_path(path, repo_root=REPO_ROOT)}:policy_sections_used")
    return violations


def run_preflight_phase(*, tracker: Dict[str, Any], authority: str, env: dict[str, str]) -> dict[str, Any]:
    check_tracker_schema(tracker)
    tasks = tracker["tasks"]
    check_status_rules(tracker, tasks)
    check_dependencies(tasks)
    meta_sha = check_frozen_sha(tracker)
    check_documented_sha(meta_sha)
    check_test_distribution(tracker)
    check_generated_output_cleanliness(env=env)
    return {
        "task": "execution-state",
        "phase": "preflight",
        "status": "ok",
        "preconditions": check_environment_preconditions(authority=authority, env=env),
        **policy_fields(sections=["environment"]),
    }


def run_final_phase(
    *,
    tracker: Dict[str, Any],
    authority: str,
    env: dict[str, str],
    generated_root: Path | None,
) -> dict[str, Any]:
    meta_sha = check_frozen_sha(tracker)
    check_documented_sha(meta_sha)
    check_dashboard_freshness(tracker, generated_root=generated_root)
    check_report_sync(generated_root=generated_root)
    check_pr101_report_sync(generated_root=generated_root)
    # This report is being generated by the current invocation, so the pipeline
    # validates it after write-out rather than requiring it to pre-exist here.
    check_evidence_reproducibility(
        tracker,
        generated_root=generated_root,
        ignored_evidence=(EXECUTION_STATE_EVIDENCE,),
    )
    check_runtime_boundary()
    check_environment_assumptions()
    check_legacy_frontend_cleanup()
    check_glue_script_safety()
    check_performance_scale_sanity()
    check_documentation_architecture_clarity()
    policy_violations = check_policy_anchoring(generated_root=generated_root)
    if policy_violations:
        fail(f"policy anchoring violations: {policy_violations}")
    return {
        "task": "execution-state",
        "phase": "final",
        "status": "ok",
        "authority": authority,
        # The generated root is transport state for staged verification. The
        # committed report records logical evidence locations only.
        "generated_root": None,
        "dashboard_path": display_path(DASHBOARD_PATH, repo_root=REPO_ROOT),
        "checks": {
            "dashboard_fresh": True,
            "evidence_reproducible": True,
            "report_sync": True,
            "runtime_boundary": True,
            "environment_assumptions": True,
            "legacy_frontend_cleanup": True,
            "glue_script_safety": True,
            "performance_scale_sanity": True,
            "documentation_architecture_clarity": True,
            "policy_anchoring": True,
        },
        **policy_fields(
            sections=[
                "environment",
                "documentation_architecture",
                "portability",
                "glue_safety",
            ]
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tracker", type=Path, default=TRACKER_PATH)
    parser.add_argument("--phase", choices=("full", "preflight", "final"), default="full")
    parser.add_argument("--generated-root", type=Path)
    parser.add_argument("--report", type=Path, default=EXECUTION_STATE_REPORT_PATH)
    parser.add_argument("--authority", choices=("local", "ci"), default="local")
    args = parser.parse_args()

    env = ensure_deterministic_env(os.environ.copy(), required=ENVIRONMENT_POLICY["required_env"])
    tracker = load_tracker(args.tracker)
    if args.phase == "preflight":
        run_preflight_phase(tracker=tracker, authority=args.authority, env=env)
        print("execution state preflight: OK")
        return 0

    if args.phase == "final":
        report = finalize_deterministic_report(
            lambda: run_final_phase(
                tracker=tracker,
                authority=args.authority,
                env=env,
                generated_root=args.generated_root,
            ),
            label="execution-state final validation",
        )
        write_report(args.report, report)
        print(f"execution state final: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
        return 0

    run_preflight_phase(tracker=tracker, authority=args.authority, env=env)
    report = finalize_deterministic_report(
        lambda: run_final_phase(
            tracker=tracker,
            authority=args.authority,
            env=env,
            generated_root=args.generated_root,
        ),
        label="execution-state final validation",
    )
    write_report(args.report, report)
    print(f"execution state: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"execution state: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
