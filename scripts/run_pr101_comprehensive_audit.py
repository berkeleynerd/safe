#!/usr/bin/env python3
"""Run the PR10.1 comprehensive assessment and refinement audit."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from _lib.gate_manifest import DeterminismClass, NODES
from _lib.harness_common import (
    canonicalize_serialized_child_result,
    compact_result,
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    load_pipeline_input,
    load_evidence_policy,
    require,
    require_pipeline_report,
    require_pipeline_result,
    resolve_generated_path,
    run,
    sha256_file,
    write_report,
)
from _lib.pr09_emit import REPO_ROOT
from _lib.pr101_verification import verification_report_reference
from _lib.proof_report import (
    build_three_way_report,
    split_command_result,
)


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr101-comprehensive-audit-report.json"
TRACKER_PATH = REPO_ROOT / "execution" / "tracker.json"
DASHBOARD_PATH = REPO_ROOT / "execution" / "dashboard.md"
README_PATH = REPO_ROOT / "README.md"
COMPILER_README_PATH = REPO_ROOT / "compiler_impl" / "README.md"
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"
PIPELINE_VERIFY_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "pipeline-verify.yml"
MATRIX_PATH = REPO_ROOT / "docs" / "emitted_output_verification_matrix.md"
POST_PR10_SCOPE_PATH = REPO_ROOT / "docs" / "post_pr10_scope.md"
AUDIT_DOC_PATH = REPO_ROOT / "docs" / "pr10_refinement_audit.md"
TUTORIAL_PATH = REPO_ROOT / "docs" / "tutorial.md"

BASELINE_SCRIPTS = [
    REPO_ROOT / "scripts" / "run_pr08_frontend_baseline.py",
    REPO_ROOT / "scripts" / "run_pr09_ada_emission_baseline.py",
    REPO_ROOT / "scripts" / "run_pr10_emitted_baseline.py",
    REPO_ROOT / "scripts" / "run_emitted_hardening_regressions.py",
]
PIPELINE_BASELINE_IDS = {
    "run_pr08_frontend_baseline.py": "pr08_frontend_baseline",
    "run_pr09_ada_emission_baseline.py": "pr09_ada_emission_baseline",
    "run_pr10_emitted_baseline.py": "pr10_emitted_baseline",
    "run_emitted_hardening_regressions.py": "emitted_hardening_regressions",
}
BASELINE_NODES = {
    node.id: node
    for node in NODES
    if node.id in set(PIPELINE_BASELINE_IDS.values())
}
EVIDENCE_POLICY = load_evidence_policy()
EXPECTED_PR101_ACCEPTANCE = [
    "Authoritative PR08, PR09, PR10, supplemental hardening, companion/template verification, and execution-state baselines rerun serially and establish the audit truth baseline.",
    "docs/pr10_refinement_audit.md classifies every current post-PR10 residual and current PR10/post-PR10 claim surface using the required finding schema and allowed dispositions.",
    "docs/post_pr10_scope.md and docs/emitted_output_verification_matrix.md are normalized to the audit outcome, and the first concrete PR10.2+ follow-on tasks are defined in execution/tracker.json.",
]
EXPECTED_PR101_EVIDENCE = [
    "execution/reports/pr101a-companion-proof-verification-report.json",
    "execution/reports/pr101b-template-proof-verification-report.json",
    "execution/reports/pr101-comprehensive-audit-report.json",
]
VERIFICATION_REPORT_SPECS = {
    "pr101a_companion_proof_verification": {
        "script": REPO_ROOT / "scripts" / "run_pr101a_companion_proof_verification.py",
        "report": REPO_ROOT / "execution" / "reports" / "pr101a-companion-proof-verification-report.json",
    },
    "pr101b_template_proof_verification": {
        "script": REPO_ROOT / "scripts" / "run_pr101b_template_proof_verification.py",
        "report": REPO_ROOT / "execution" / "reports" / "pr101b-template-proof-verification-report.json",
    },
}
VERIFICATION_REPORT_ORDER = tuple(VERIFICATION_REPORT_SPECS)
EXPECTED_PR104_ACCEPTANCE = [
    "Pure-Python regression tests cover scripts/run_pr101_comprehensive_audit.py parsing helpers (split_table_row, parse_findings, parse_residuals, parse_summary_counts), including malformed-table cases and multi-target target-cell parsing.",
    "The emitted proof and audit harnesses verify explicit gnat.adc application and fail deterministically if concurrency compile/flow/prove commands lose the concrete -gnatec=<ada_dir>/gnat.adc argument.",
    "The GNATprove evidence path documents and enforces the repo's proof-repeatability policy for emitted gates, including the current --steps=0 plus bounded-timeout profile and an explicit statement about whether committed session artifacts are part of the reproducibility contract.",
    "parse_task_id() is extended to handle three-level milestone IDs (e.g., PR06.9.8) that already exist in the tracker's own task list, so forward-stability checks match the project's actual ID convention rather than silently rejecting valid historical IDs.",
    "Dependent deterministic report rollups are de-cascaded so parent reports do not churn solely because child report hashes changed: freshness checks rerun child gates into comparison artifacts or validate stable path-level invariants, and portability/glue/doc hardening reports avoid repo-wide unittest-count summaries that change for unrelated test additions.",
    "A dedicated PR10.4 gate, report, and CI job keep the hardened evidence path and parser-regression surface under committed deterministic coverage.",
]
EXPECTED_PR104_EVIDENCE = [
    "execution/reports/pr104-gnatprove-evidence-parser-hardening-report.json",
]
EXPECTED_PR105_ACCEPTANCE = [
    "The three broad Constraint_Error catch-alls in compiler_impl/src/safe_frontend-ada_emit.adb are removed or narrowed so malformed-state failures are not collapsed into generic emitter internal errors.",
    "Unreachable post-Raise_Unsupported fallback returns are removed, integer-type classification is made subtype-aware, name-based type lookup/render helpers are unified, and the duplicated Render_Object_Decl_Text bodies are consolidated into one shared implementation path.",
    "String-based alias-postcondition 'Old insertion is replaced with AST-aware rendering, with focused regression coverage for similar-name, nested-selector, and repeated-target cases.",
    "A dedicated PR10.5 gate, report, and CI job keep the emitter-maintenance refactor deterministic and evidence-backed.",
]
EXPECTED_PR105_EVIDENCE = [
    "execution/reports/pr105-ada-emitter-maintenance-hardening-report.json",
]
EXPECTED_PR106_ACCEPTANCE = [
    "The PR10.6 sequential proof corpus is the exact 27-fixture set consisting of tests/positive/constant_access_deref_write.safe, tests/positive/constant_channel_capacity.safe, tests/positive/constant_discriminant_default.safe, tests/positive/constant_range_bound.safe, tests/positive/constant_shadow_mutable.safe, tests/positive/constant_task_priority.safe, tests/positive/emitter_surface_proc.safe, tests/positive/emitter_surface_record.safe, tests/positive/result_equality_check.safe, tests/positive/result_guarded_access.safe, tests/positive/rule1_accumulate.safe, tests/positive/rule1_conversion.safe, tests/positive/rule1_return.safe, tests/positive/rule2_binary_search.safe, tests/positive/rule2_iteration.safe, tests/positive/rule2_lookup.safe, tests/positive/rule2_matrix.safe, tests/positive/rule2_slice.safe, tests/positive/rule3_average.safe, tests/positive/rule3_modulo.safe, tests/positive/rule3_percent.safe, tests/positive/rule3_remainder.safe, tests/positive/rule4_conditional.safe, tests/positive/rule4_deref.safe, tests/positive/rule4_factory.safe, tests/positive/rule4_linked_list.safe, and tests/positive/rule4_optional.safe; that set may not be silently shrunk.",
    "The positive-path concurrency fixtures tests/positive/channel_pingpong.safe, tests/positive/channel_pipeline_compute.safe, and tests/positive/channel_pipeline.safe are explicitly excluded from PR10.6 and remain outside this sequential proof corpus.",
    "That exact 27-fixture sequential subset passes compile, GNATprove flow, and GNATprove prove under the all-proved-only policy with dedicated deterministic evidence and emitted-structure/source-fragment assertions.",
    "docs/emitted_output_verification_matrix.md, docs/pr10_refinement_audit.md, execution/tracker.json, README.md, and the dedicated PR10.6 gate/CI/local-workflow surfaces distinguish the completed PR10.6 sequential closure from the still-open concurrency/runtime residuals.",
]
EXPECTED_PR106_EVIDENCE = [
    "execution/reports/pr106-sequential-proof-corpus-expansion-report.json",
]
EXPECTED_PR111_ACCEPTANCE = [
    "A one-command `safe build <file.safe>` wrapper, static VSCode grammar, and disposable diagnostics shim exist as explicitly non-frozen tooling surfaces for language evaluation.",
    "PR11.1 creates and validates a starter Rosetta/sample corpus consisting of fibonacci.safe, gcd.safe, factorial.safe, collatz_bounded.safe, bubble_sort.safe, binary_search.safe, bounded_stack.safe, and producer_consumer.safe; linked_list_reverse.safe and prime_sieve_pipeline.safe remain candidate expansions, while trapezoidal_rule.safe and newton_sqrt_bounded.safe remain deferred to later numeric work.",
    "None of the PR11.1 starter-corpus candidates depend on PR11.2 string/case support, and PR11.1 remains a `safec check` -> `safec emit --ada-out-dir` -> `gprbuild` compile milestone rather than emitted-proof expansion; proof re-enters later via PR11.3a, PR11.8a, and the parallel PR11.8b concurrency track.",
]
EXPECTED_PR111_EVIDENCE = [
    "execution/reports/pr111-language-evaluation-harness-report.json",
]
EXPECTED_PR112_ACCEPTANCE = [
    "The parser is extended for string/character literals and case statements without absorbing richer constant-evaluation work (`PS-001`) or named-number support (`PS-010`).",
    "Resolver/emitter support and positive/negative tests are added for the accepted string/character and case-statement surface.",
    "The Rosetta/sample corpus grows with programs unlocked by strings/chars and case statements after the PR11.1 starter set lands.",
]
EXPECTED_PR112_EVIDENCE = [
    "execution/reports/pr112-parser-completeness-phase1-report.json",
]
EXPECTED_PR113_ACCEPTANCE = [
    "The accepted subset covers record discriminants only, including multiple scalar discriminants, defaults, explicit constraints on objects/parameters/results, bounded variant-part support, and a compile-only emitted corpus that locks those semantics.",
    "Anonymous tuple types, tuple returns/destructuring/field access/channel elements, and the predefined builtin `result` plus `ok` / `fail(String)` conventions are admitted for the current value-type subset rather than being deferred beyond PR11.3.",
    "Access discriminants, nested tuples, access/task/channel tuple elements, richer variant alternatives, generic `result` forms, and general user-declared `String` fields remain explicitly deferred rather than being absorbed into the milestone.",
]
EXPECTED_PR113_EVIDENCE = [
    "execution/reports/pr113-discriminated-types-tuples-structured-returns-report.json",
]
EXPECTED_PR113A_ACCEPTANCE = [
    "The PR11.3a sequential proof checkpoint corpus is the exact 11-fixture set consisting of tests/positive/pr112_character_case.safe, tests/positive/pr112_discrete_case.safe, tests/positive/pr112_string_param.safe, tests/positive/pr112_case_scrutinee_once.safe, tests/positive/pr113_discriminant_constraints.safe, tests/positive/pr113_tuple_destructure.safe, tests/positive/pr113_structured_result.safe, tests/positive/pr113_variant_guard.safe, tests/positive/constant_discriminant_default.safe, tests/positive/result_equality_check.safe, and tests/positive/result_guarded_access.safe; tests/positive/pr113_tuple_channel.safe is explicitly excluded from this sequential checkpoint and its proof debt stays on PR11.8b.",
    "That exact checkpoint corpus passes compile, GNATprove flow, and GNATprove prove under the all-proved-only policy with dedicated deterministic evidence, and the checkpoint gate keeps the corpus non-shrinkable with emitted-structure assertions for the PR11.2/PR11.3 surfaces it covers.",
    "PR11.3a remains a value-only sequential checkpoint: Rosetta samples stay compile-only, tuple-channel proof remains deferred to PR11.8b, and `PS-029` is explicitly bounded rather than broadened before this checkpoint claims proof closure.",
]
EXPECTED_PR113A_EVIDENCE = [
    "execution/reports/pr113a-proof-checkpoint1-report.json",
]
EXPECTED_PR114_ACCEPTANCE = [
    "PR11.4 is a deliberate cutover rather than a coexistence milestone: legacy `procedure`, signature `return`, `elsif`, and `..` spellings are removed from the admitted Safe source surface once the milestone lands.",
    "The full PR11.4 quartet lands together: all callables use `function`, result-bearing signatures use `returns`, conditional chains use `else if`, and source-level inclusive ranges use `to`, while typing/MIR/safei/emitted Ada semantics remain stable for already-supported programs.",
    "The `.safe` corpus, Rosetta samples, docs/examples, VSCode grammar/docs, and a dedicated deterministic PR11.4 gate are migrated together, with explicit negative coverage that locks rejection of each removed legacy spelling.",
]
EXPECTED_PR114_EVIDENCE = [
    "execution/reports/pr114-signature-control-flow-syntax-report.json",
]
EXPECTED_PR102_ACCEPTANCE = [
    "The exact six-fixture PR10.2 Rule 5 positive corpus is tests/positive/rule5_filter.safe, tests/positive/rule5_interpolate.safe, tests/positive/rule5_normalize.safe, tests/positive/rule5_statistics.safe, tests/positive/rule5_temperature.safe, and tests/positive/rule5_vector_normalize.safe; that merged PR07-plus-PR10 set is non-shrinkable and each fixture is frontend-accepted, Ada-emitted, compile-valid, and passes emitted GNATprove flow and prove under the all-proved-only policy.",
    "The source-level Rule 5 negative contract remains tests/negative/neg_rule5_div_zero.safe -> fp_division_by_zero, tests/negative/neg_rule5_infinity.safe -> infinity_at_narrowing, tests/negative/neg_rule5_nan.safe -> nan_at_narrowing, tests/negative/neg_rule5_overflow.safe -> fp_overflow_at_narrowing, and tests/negative/neg_rule5_uninitialized.safe -> fp_uninitialized_at_narrowing; unsupported float-evaluator shapes use the new fp_unsupported_expression_at_narrowing reason under MIR analysis parity coverage instead of being mislabeled as overflow.",
    "While loops outside the current derivable Loop_Variant proof surface are rejected during safec check with loop_variant_not_derivable, and a dedicated PR10.2 gate, report, CI job, tracker/docs update, and deterministic diagnostics-golden set capture the resulting Rule 5 plus convergence-loop boundary without weakening the frozen PR10 claim.",
]
EXPECTED_PR103_ACCEPTANCE = [
    "The first PR10.3 ownership expansion corpus consists of tests/positive/ownership_borrow.safe, tests/positive/ownership_observe.safe, tests/positive/ownership_observe_access.safe, tests/positive/ownership_return.safe, tests/positive/ownership_inout.safe, and tests/positive/ownership_early_return.safe, and that named set may not be silently shrunk.",
    "Those six ownership fixtures pass compile, GNATprove flow, and GNATprove prove under the all-proved-only policy.",
    "docs/emitted_output_verification_matrix.md and related audit/docs surfaces distinguish the frozen PR10 claim from the now-proved PR10.3 ownership expansion set and retarget remaining sequential proof expansion to PR10.6.",
    "A dedicated PR10.3 gate, report, and CI wiring keep the expanded sequential proof corpus deterministic and evidence-backed.",
]
EXPECTED_PR103_EVIDENCE = [
    "execution/reports/pr103-sequential-proof-expansion-report.json",
]
ALLOWED_DISPOSITIONS = {
    "fix-in-pr101",
    "promote-to-pr10x",
    "retain-in-post-pr10",
    "close-as-fixed",
    "close-as-duplicate",
    "close-as-spec-excluded",
    "close-as-pretracked",
}
PROMOTED_TASKS = ("PR10.4", "PR10.5", "PR10.6")
PROMOTED_DEPENDENCIES = {
    "PR10.4": ["PR10.1"],
    "PR10.5": ["PR10.1"],
    "PR10.6": ["PR10.3"],
}
RETAINED_PRIORITY_COUNTS = {
    "blocking-if-needed": 14,
    "nice-to-have": 3,
    "long-term": 16,
    "Total": 33,
}
EXPECTED_AUDIT_SNIPPETS = [
    "The PR10.1 gate reruns the following authoritative serial baseline:",
    "`scripts/run_pr08_frontend_baseline.py`",
    "`scripts/run_pr09_ada_emission_baseline.py`",
    "`scripts/run_pr10_emitted_baseline.py`",
    "`scripts/run_emitted_hardening_regressions.py`",
    "`PR10.2` — Rule 5 proof-boundary closure and loop-termination diagnostics",
    "`PR10.3` — Ownership emitted proof-corpus expansion beyond the frozen PR10 `ownership_move` representative",
    "`PR10.4` — GNATprove evidence and parser hardening, including audit-parser regression tests, explicit `gnat.adc` sentinels, proof-repeatability policy, and deterministic report de-cascading (completed)",
    "`PR10.5` — Ada emitter maintenance hardening (completed)",
    "`PR10.6` — Remaining sequential emitted proof-corpus expansion beyond the completed ownership set (completed)",
    "`next_task_id` advances to `PR11.1`",
]
EXPECTED_MATRIX_SNIPPETS = [
    "frontend Silver ownership analysis is the mechanism that prevents use-after-free",
    "Post-PR10 ownership proof-expansion set",
    "ownership_borrow.safe",
    "ownership_early_return.safe",
    "PR10.3",
    "PR10.6",
    "PR10.2 keeps the frozen PR10 Rule 5 row above intact while closing the broader",
    "fp_unsupported_expression_at_narrowing",
    "loop_variant_not_derivable",
    "PS-007",
    "PS-019",
    "PS-031",
    "docs/pr10_refinement_audit.md",
    "PR11.3a Sequential Checkpoint Corpus",
    "`tests/positive/pr113_tuple_channel.safe` remains outside that proof set",
    "PR11.8b",
]
EXPECTED_POST_PR10_SNIPPETS = [
    "PS-001",
    "PS-033",
    "docs/pr10_refinement_audit.md",
]
EXPECTED_README_SNIPPETS = [
    "| PR10.1 refinement audit | [`docs/pr10_refinement_audit.md`](docs/pr10_refinement_audit.md) |",
    "the PR10.1 comprehensive audit job",
    "PR10.1 then audits the current post-PR10 claim surfaces, normalises the residual ledger, and defines the next tracked follow-on series starting at `PR10.2`.",
]
EXPECTED_COMPILER_README_SNIPPETS = [
    "The PR10.1 comprehensive audit gate is:",
    "later tracked milestones may exist",
    "execution/reports/pr101-comprehensive-audit-report.json",
]
EXPECTED_CI_WORKFLOW_SNIPPETS = [
    "execution-guard:",
    "python3 scripts/validate_execution_state.py --authority ci",
    "lint-safe-syntax:",
    "scripts/lint_safe_syntax.sh",
    "spark-verify:",
    "Build & Verify SPARK Companion",
    "templates-verify:",
    "Build & Verify Emission Templates",
]
EXPECTED_PIPELINE_VERIFY_WORKFLOW_SNIPPETS = [
    "pipeline-verify:",
    "Run canonical gate pipeline verify",
    "python3 scripts/run_gate_pipeline.py verify --authority ci",
]
EXPECTED_PRE_PUSH_SNIPPETS = [
    "\"scripts/run_pr09_ada_emission_baseline.py\"",
    "\"scripts/run_pr104_gnatprove_evidence_parser_hardening.py\"",
    "\"scripts/run_pr101_comprehensive_audit.py\"",
    "\"scripts/run_pr103_sequential_proof_expansion.py\"",
    "\"scripts/run_pr106_sequential_proof_corpus_expansion.py\"",
    "\"scripts/run_pr111_language_evaluation_harness.py\"",
    "\"scripts/run_pr112_parser_completeness_phase1.py\"",
    "\"scripts/run_pr113_discriminated_types_tuples_structured_returns.py\"",
    "\"scripts/run_pr113a_proof_checkpoint1.py\"",
    "\"scripts/run_pr114_signature_control_flow_syntax.py\"",
]
EXPECTED_TUTORIAL_SNIPPETS = [
    "Ada-native `safec` frontend plus emitted-output proof",
    "docs/safec_end_to_end_cli_tutorial.md",
    "working compiler frontend",
    "proof pipeline",
]


def load_tracker() -> dict[str, Any]:
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def require_contains(text: str, snippet: str, label: str) -> None:
    require(snippet in text, f"{label}: expected to contain {snippet!r}")


def parse_task_id(value: object) -> tuple[int, int | None] | None:
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r"PR(\d+)(?:\.(\d+)(?:\.(\d+))?[A-Za-z0-9]*)?", value)
    if match is None:
        return None
    major = int(match.group(1))
    minor = int(match.group(2)) if match.group(2) is not None else None
    return (major, minor)


def task_is_at_or_beyond_pr102(value: object) -> bool:
    if value is None:
        return True
    parsed = parse_task_id(value)
    if parsed is None:
        return False
    major, minor = parsed
    return major > 10 or (major == 10 and minor is not None and minor >= 2)


def task_is_at_or_beyond_pr112(value: object) -> bool:
    if value is None:
        return True
    parsed = parse_task_id(value)
    if parsed is None:
        return False
    major, minor = parsed
    return major > 11 or (major == 11 and minor is not None and minor >= 2)


def task_is_at_or_beyond_pr113(value: object) -> bool:
    if value is None:
        return True
    parsed = parse_task_id(value)
    if parsed is None:
        return False
    major, minor = parsed
    return major > 11 or (major == 11 and minor is not None and minor >= 3)


def task_is_at_or_beyond_pr113a(value: object) -> bool:
    if value is None:
        return True
    if not isinstance(value, str):
        return False
    if re.fullmatch(r"PR11\.3[A-Za-z0-9]+", value):
        return True
    parsed = parse_task_id(value)
    if parsed is None:
        return False
    major, minor = parsed
    return major > 11 or (major == 11 and minor is not None and minor > 3)


def task_is_at_or_beyond_pr114(value: object) -> bool:
    if value is None:
        return True
    parsed = parse_task_id(value)
    if parsed is None:
        return False
    major, minor = parsed
    return major > 11 or (major == 11 and minor is not None and minor >= 4)


def task_is_at_or_beyond_pr115(value: object) -> bool:
    if value is None:
        return True
    parsed = parse_task_id(value)
    if parsed is None:
        return False
    major, minor = parsed
    return major > 11 or (major == 11 and minor is not None and minor >= 5)

def split_table_row(line: str) -> list[str] | None:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return None
    cells = [cell.strip() for cell in stripped.split("|")[1:-1]]
    if not cells:
        return None
    if all(re.fullmatch(r"[:\- ]+", cell) for cell in cells):
        return None
    return cells


def parse_findings(text: str) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []
    for line in text.splitlines():
        cells = split_table_row(line)
        if not cells or len(cells) != 8 or not cells[0].startswith("`PR101-"):
            continue
        findings.append(
            {
                "id": cells[0].strip("`"),
                "area": cells[1].strip("`"),
                "claim_source": cells[2],
                "observed_reality": cells[3],
                "evidence": cells[4],
                "disposition": cells[5].strip("`"),
                "target": cells[6].replace("`", ""),
                "notes": cells[7],
            }
        )
    require(findings, "docs/pr10_refinement_audit.md: no audit findings found")
    return findings


def parse_residuals(text: str) -> list[dict[str, str]]:
    residuals: list[dict[str, str]] = []
    for line in text.splitlines():
        cells = split_table_row(line)
        if not cells or len(cells) != 5 or not cells[0].startswith("`PS-"):
            continue
        residuals.append(
            {
                "id": cells[0].strip("`"),
                "item": cells[1],
                "source": cells[2],
                "area": cells[3].strip("`"),
                "priority": cells[4].strip("`"),
            }
        )
    require(residuals, "docs/post_pr10_scope.md: no retained residuals found")
    return residuals


def parse_summary_counts(text: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for line in text.splitlines():
        cells = split_table_row(line)
        if not cells or len(cells) != 2:
            continue
        key = cells[0].strip("`*")
        value = cells[1].strip("`*")
        if key in {"blocking-if-needed", "nice-to-have", "long-term", "Total"} and value.isdigit():
            counts[key] = int(value)
    return counts


def canonicalize_baseline_gate_result(*, script: Path, result: dict[str, Any]) -> dict[str, Any]:
    del script
    return canonicalize_serialized_child_result(result)


def local_reused_gate_result(*, python: str, script: Path) -> dict[str, Any]:
    return {
        "command": [python, display_path(script, repo_root=REPO_ROOT)],
        "cwd": "$REPO_ROOT",
        "returncode": 0,
    }


def run_python_gate(
    *,
    python: str,
    script: Path,
    env: dict[str, str],
    temp_root: Path,
    extra_argv: list[str] | None = None,
) -> dict[str, Any]:
    report_path = temp_root / f"{script.stem}.json"
    argv = [python, str(script)]
    if extra_argv:
        argv.extend(extra_argv)
    argv.extend(["--report", str(report_path)])
    result = run(
        argv,
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    payload = json.loads(report_path.read_text(encoding="utf-8"))
    return {
        "script": display_path(script, repo_root=REPO_ROOT),
        "result": compact_result(canonicalize_baseline_gate_result(script=script, result=result)),
        "report_sha256": payload["report_sha256"],
        "deterministic": payload["deterministic"],
    }


def load_baseline_gate_reference(
    *,
    python: str,
    script: Path,
    generated_root: Path | None = None,
) -> dict[str, Any]:
    node_id = PIPELINE_BASELINE_IDS[script.name]
    node = BASELINE_NODES[node_id]
    require(node.report_path is not None, f"{node_id}: report path required")
    report_path = resolve_generated_path(
        node.report_path,
        generated_root=generated_root,
        policy=EVIDENCE_POLICY,
        repo_root=REPO_ROOT,
    )
    payload = json.loads(report_path.read_text(encoding="utf-8"))
    require(payload.get("deterministic") is True, f"{display_path(report_path, repo_root=REPO_ROOT)} must be deterministic")
    require(
        payload.get("report_sha256") == payload.get("repeat_sha256"),
        f"{display_path(report_path, repo_root=REPO_ROOT)} report hashes must match",
    )
    return {
        "script": display_path(script, repo_root=REPO_ROOT),
        "result": local_reused_gate_result(python=python, script=script),
        "report_sha256": payload["report_sha256"],
        "deterministic": payload["deterministic"],
    }


def load_verification_report_reference(
    *,
    node_id: str,
    generated_root: Path | None = None,
) -> dict[str, Any]:
    spec = VERIFICATION_REPORT_SPECS[node_id]
    report_path = resolve_generated_path(
        spec["report"],
        generated_root=generated_root,
        policy=EVIDENCE_POLICY,
        repo_root=REPO_ROOT,
    )
    payload = json.loads(report_path.read_text(encoding="utf-8"))
    require(payload.get("deterministic") is True, f"{display_path(report_path, repo_root=REPO_ROOT)} must be deterministic")
    require(
        payload.get("report_sha256") == payload.get("repeat_sha256"),
        f"{display_path(report_path, repo_root=REPO_ROOT)} report hashes must match",
    )
    return verification_report_reference(
        node_id=node_id,
        script=display_path(spec["script"], repo_root=REPO_ROOT),
        report_sha256=payload["report_sha256"],
        deterministic=payload["deterministic"],
    )


def run_baseline_truth(
    *,
    env: dict[str, str],
    authority: str,
    generated_root: Path | None = None,
) -> dict[str, Any]:
    python = find_command("python3")
    with tempfile.TemporaryDirectory(prefix="pr101-audit-") as temp_root_str:
        temp_root = Path(temp_root_str)
        gates: list[dict[str, Any]] = []
        for script in BASELINE_SCRIPTS:
            node_id = PIPELINE_BASELINE_IDS[script.name]
            node = BASELINE_NODES[node_id]
            if authority == "local" and node.determinism_class is DeterminismClass.CI_AUTHORITATIVE:
                gates.append(
                    load_baseline_gate_reference(
                        python=python,
                        script=script,
                        generated_root=generated_root,
                    )
                )
                continue
            extra_argv: list[str] = []
            if authority and script.name == "run_pr10_emitted_baseline.py":
                extra_argv.extend(["--authority", authority])
            if node.supports_generated_root and generated_root is not None:
                extra_argv.extend(["--generated-root", str(generated_root)])
            gates.append(
                run_python_gate(
                    python=python,
                    script=script,
                    env=env,
                    temp_root=temp_root,
                    extra_argv=extra_argv,
                )
            )
        return {
            "python_gates": gates,
            "verification_reports": [
                load_verification_report_reference(node_id=node_id, generated_root=generated_root)
                for node_id in VERIFICATION_REPORT_ORDER
            ],
        }


def pipeline_baseline_truth(*, env: dict[str, Any], pipeline_input: dict[str, Any]) -> dict[str, Any]:
    gates: list[dict[str, Any]] = []
    for script in BASELINE_SCRIPTS:
        node_id = PIPELINE_BASELINE_IDS[script.name]
        result = require_pipeline_result(pipeline_input, node_id=node_id)
        payload = require_pipeline_report(pipeline_input, node_id=node_id)
        gates.append(
            {
                "script": display_path(script, repo_root=REPO_ROOT),
                "result": compact_result(canonicalize_baseline_gate_result(script=script, result=result)),
                "report_sha256": payload["report_sha256"],
                "deterministic": payload["deterministic"],
            }
        )

    verification_reports: list[dict[str, Any]] = []
    for node_id in VERIFICATION_REPORT_ORDER:
        payload = require_pipeline_report(pipeline_input, node_id=node_id)
        verification_reports.append(
            verification_report_reference(
                node_id=node_id,
                script=display_path(VERIFICATION_REPORT_SPECS[node_id]["script"], repo_root=REPO_ROOT),
                report_sha256=payload["report_sha256"],
                deterministic=payload["deterministic"],
            )
        )

    return {
        "python_gates": gates,
        "verification_reports": verification_reports,
    }


def baseline_gate_hashes(*, baseline_truth: dict[str, Any]) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for gate in baseline_truth["python_gates"]:
        node_id = PIPELINE_BASELINE_IDS[Path(gate["script"]).name]
        hashes[node_id] = gate["report_sha256"]
    return hashes


def verification_report_hashes(*, baseline_truth: dict[str, Any]) -> dict[str, str]:
    return {
        entry["node_id"]: entry["report_sha256"]
        for entry in baseline_truth["verification_reports"]
    }


def semantic_floor_from_baseline_truth(*, baseline_truth: dict[str, Any]) -> dict[str, Any]:
    return {
        "baseline_gate_hashes": baseline_gate_hashes(baseline_truth=baseline_truth),
        "child_report_hashes": verification_report_hashes(baseline_truth=baseline_truth),
    }


def split_python_gate_entry(gate: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    canonical_result, machine_result = split_command_result(gate["result"])
    canonical = {
        "script": gate["script"],
        "result": canonical_result,
        "report_sha256": gate["report_sha256"],
        "deterministic": gate["deterministic"],
    }
    machine = {
        "script": gate["script"],
        "result": machine_result,
    }
    return canonical, machine


def split_baseline_truth(
    *,
    baseline_truth: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    canonical_python: list[dict[str, Any]] = []
    machine_python: list[dict[str, Any]] = []
    for gate in baseline_truth["python_gates"]:
        canonical_gate, machine_gate = split_python_gate_entry(gate)
        canonical_python.append(canonical_gate)
        machine_python.append(machine_gate)

    canonical = {
        "python_gates": canonical_python,
        "verification_reports": baseline_truth["verification_reports"],
    }
    machine = {
        "python_gates": machine_python,
    }
    return canonical, machine


def build_report(*, baseline_truth: dict[str, Any], generated_root: Path | None) -> dict[str, Any]:
    tracker = load_tracker()
    task_map = {task["id"]: task for task in tracker["tasks"]}
    require(task_map["PR10"]["status"] == "done", "PR10 must remain marked done")
    require("PR10.1" in task_map, "tracker must define PR10.1")
    require(task_map["PR10.1"]["status"] == "done", "PR10.1 must be marked done")
    require(task_map["PR10.1"]["depends_on"] == ["PR10"], "PR10.1 must depend on PR10")
    require(
        task_map["PR10.1"]["acceptance"] == EXPECTED_PR101_ACCEPTANCE,
        "PR10.1 acceptance text must match the canonical audit contract",
    )
    require(
        task_map["PR10.1"]["evidence"] == EXPECTED_PR101_EVIDENCE,
        "PR10.1 evidence must list the committed audit report",
    )
    require("PR10.2" in task_map, "tracker must define PR10.2")
    require(
        task_map["PR10.2"]["status"] in {"planned", "ready", "in_progress", "done"},
        "PR10.2 must remain a live tracked follow-on milestone",
    )
    require(
        task_map["PR10.2"]["acceptance"] == EXPECTED_PR102_ACCEPTANCE,
        "PR10.2 acceptance text must match the committed Rule 5 boundary-closure contract",
    )
    require("PR10.3" in task_map, "tracker must define PR10.3")
    require(task_map["PR10.3"]["status"] == "done", "PR10.3 must be marked done")
    require(task_map["PR10.3"]["depends_on"] == ["PR10.1"], "PR10.3 must depend on PR10.1")
    require(
        task_map["PR10.3"]["acceptance"] == EXPECTED_PR103_ACCEPTANCE,
        "PR10.3 acceptance text must match the committed ownership proof-expansion contract",
    )
    require(
        task_map["PR10.3"]["evidence"] == EXPECTED_PR103_EVIDENCE,
        "PR10.3 evidence must list the committed ownership proof-expansion report",
    )
    require(
        task_is_at_or_beyond_pr102(tracker.get("next_task_id")),
        "next_task_id must remain at or beyond PR10.2 after PR10.1",
    )
    require("PR11.1" in task_map, "tracker must define PR11.1")
    require(task_map["PR11.1"]["status"] == "done", "PR11.1 must be marked done")
    require(
        task_map["PR11.1"]["depends_on"] == ["PR10.4", "PR10.5", "PR10.6"],
        "PR11.1 must depend on PR10.4, PR10.5, and PR10.6",
    )
    require(
        task_map["PR11.1"]["acceptance"] == EXPECTED_PR111_ACCEPTANCE,
        "PR11.1 acceptance text must match the committed language-evaluation harness contract",
    )
    require(
        task_map["PR11.1"]["evidence"] == EXPECTED_PR111_EVIDENCE,
        "PR11.1 evidence must list the committed language-evaluation harness report",
    )
    require("PR11.2" in task_map, "tracker must define PR11.2")
    require(task_map["PR11.2"]["status"] == "done", "PR11.2 must be marked done")
    require(task_map["PR11.2"]["depends_on"] == ["PR11.1"], "PR11.2 must depend on PR11.1")
    require(
        task_map["PR11.2"]["acceptance"] == EXPECTED_PR112_ACCEPTANCE,
        "PR11.2 acceptance text must match the committed parser-completeness phase 1 contract",
    )
    require(
        task_map["PR11.2"]["evidence"] == EXPECTED_PR112_EVIDENCE,
        "PR11.2 evidence must list the committed parser-completeness phase 1 report",
    )
    require(
        task_is_at_or_beyond_pr113(tracker.get("next_task_id")),
        "next_task_id must remain at or beyond PR11.3 after PR11.2",
    )
    require("PR11.3" in task_map, "tracker must define PR11.3")
    require(
        task_map["PR11.3"]["status"] == "done",
        "PR11.3 must be marked done",
    )
    require(task_map["PR11.3"]["depends_on"] == ["PR11.2"], "PR11.3 must depend on PR11.2")
    require(
        task_map["PR11.3"]["acceptance"] == EXPECTED_PR113_ACCEPTANCE,
        "PR11.3 acceptance text must match the committed discriminant/tuple/result contract",
    )
    require(
        task_map["PR11.3"]["evidence"] == EXPECTED_PR113_EVIDENCE,
        "PR11.3 evidence must list the committed discriminant/tuple/result report",
    )
    require(
        task_is_at_or_beyond_pr113a(tracker.get("next_task_id")),
        "next_task_id must remain at or beyond PR11.3a after PR11.3",
    )
    require("PR11.3a" in task_map, "tracker must define PR11.3a")
    require(task_map["PR11.3a"]["depends_on"] == ["PR11.3"], "PR11.3a must depend on PR11.3")
    require(
        task_map["PR11.3a"]["acceptance"] == EXPECTED_PR113A_ACCEPTANCE,
        "PR11.3a acceptance text must match the committed tuple/discriminant proof-checkpoint contract",
    )
    require(
        task_map["PR11.3a"]["status"] == "done",
        "PR11.3a must be marked done",
    )
    require(
        task_map["PR11.3a"]["evidence"] == EXPECTED_PR113A_EVIDENCE,
        "PR11.3a evidence must list the committed proof-checkpoint report",
    )
    require(
        task_is_at_or_beyond_pr114(tracker.get("next_task_id")),
        "next_task_id must remain at or beyond PR11.4 after PR11.3a",
    )
    require("PR11.4" in task_map, "tracker must define PR11.4")
    require(task_map["PR11.4"]["depends_on"] == ["PR11.3a"], "PR11.4 must depend on PR11.3a")
    require(
        task_map["PR11.4"]["acceptance"] == EXPECTED_PR114_ACCEPTANCE,
        "PR11.4 acceptance text must match the committed syntax cutover contract",
    )
    require(
        task_map["PR11.4"]["status"] == "done",
        "PR11.4 must be marked done",
    )
    require(
        task_map["PR11.4"]["evidence"] == EXPECTED_PR114_EVIDENCE,
        "PR11.4 evidence must list the committed syntax-cutover report",
    )
    require(
        task_is_at_or_beyond_pr115(tracker.get("next_task_id")),
        "next_task_id must remain at or beyond PR11.5 after PR11.4",
    )
    for task_id in PROMOTED_TASKS:
        require(task_id in task_map, f"tracker must define promoted task {task_id}")
        require(
            task_map[task_id]["status"] in {"planned", "ready", "in_progress", "done"},
            f"{task_id} must remain a live tracked follow-on milestone",
        )
        require(
            task_map[task_id]["depends_on"] == PROMOTED_DEPENDENCIES[task_id],
            f"{task_id} must depend on {PROMOTED_DEPENDENCIES[task_id]}",
        )
    require(
        task_map["PR10.4"]["acceptance"] == EXPECTED_PR104_ACCEPTANCE,
        "PR10.4 acceptance text must match the tightened parser/evidence hardening scope",
    )
    require(task_map["PR10.4"]["status"] == "done", "PR10.4 must be marked done")
    require(
        task_map["PR10.4"]["evidence"] == EXPECTED_PR104_EVIDENCE,
        "PR10.4 evidence must list the committed parser/evidence hardening report",
    )
    require(
        task_map["PR10.5"]["acceptance"] == EXPECTED_PR105_ACCEPTANCE,
        "PR10.5 acceptance text must match the committed Ada emitter maintenance-hardening scope",
    )
    require(task_map["PR10.5"]["status"] == "done", "PR10.5 must be marked done")
    require(
        task_map["PR10.5"]["evidence"] == EXPECTED_PR105_EVIDENCE,
        "PR10.5 evidence must list the committed Ada emitter maintenance-hardening report",
    )
    require(
        task_map["PR10.6"]["acceptance"] == EXPECTED_PR106_ACCEPTANCE,
        "PR10.6 acceptance text must match the committed sequential proof-corpus closure contract",
    )
    require(task_map["PR10.6"]["status"] == "done", "PR10.6 must be marked done")
    require(
        task_map["PR10.6"]["evidence"] == EXPECTED_PR106_EVIDENCE,
        "PR10.6 evidence must list the committed sequential proof-corpus expansion report",
    )

    rendered_dashboard = run([find_command("python3"), "scripts/render_execution_status.py"], cwd=REPO_ROOT, env=ensure_sdkroot(os.environ.copy()))
    dashboard_text = resolve_generated_path(
        DASHBOARD_PATH,
        generated_root=generated_root,
        policy=EVIDENCE_POLICY,
        repo_root=REPO_ROOT,
    ).read_text(encoding="utf-8")
    require(dashboard_text == rendered_dashboard["stdout"], "execution/dashboard.md must match render_execution_status.py")
    require_contains(
        dashboard_text,
        f"| PR10.1 | done | PR10 | {len(EXPECTED_PR101_EVIDENCE)} |",
        "execution/dashboard.md",
    )
    require_contains(dashboard_text, "| PR10.3 | done | PR10.1 | 1 |", "execution/dashboard.md")
    next_task_match = re.search(r"- \*\*Next task:\*\* `([^`]+)`", dashboard_text)
    require(next_task_match is not None, "execution/dashboard.md must render the next-task line")
    require(
        task_is_at_or_beyond_pr115(next_task_match.group(1) if next_task_match is not None else None),
        "execution/dashboard.md must show a next task at or beyond PR11.5 (or none)",
    )
    require(
        re.search(r"\| PR10\.4 \| done \| PR10\.1 \| \d+ \|", dashboard_text)
        is not None,
        "execution/dashboard.md must contain the completed PR10.4 row",
    )

    audit_text = AUDIT_DOC_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_AUDIT_SNIPPETS:
        require_contains(audit_text, snippet, "docs/pr10_refinement_audit.md")
    findings = parse_findings(audit_text)

    finding_ids = {finding["id"] for finding in findings}
    require(len(finding_ids) == len(findings), "docs/pr10_refinement_audit.md: finding IDs must be unique")

    residual_text = POST_PR10_SCOPE_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_POST_PR10_SNIPPETS:
        require_contains(residual_text, snippet, "docs/post_pr10_scope.md")
    residuals = parse_residuals(residual_text)
    residual_ids = {item["id"] for item in residuals}
    require(len(residual_ids) == len(residuals), "docs/post_pr10_scope.md: residual IDs must be unique")
    counts = parse_summary_counts(residual_text)
    require(counts == RETAINED_PRIORITY_COUNTS, "docs/post_pr10_scope.md: summary counts must match retained residuals")

    matrix_text = MATRIX_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_MATRIX_SNIPPETS:
        require_contains(matrix_text, snippet, "docs/emitted_output_verification_matrix.md")

    tutorial_text = TUTORIAL_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_TUTORIAL_SNIPPETS:
        require_contains(tutorial_text, snippet, "docs/tutorial.md")
    require(
        "There is no Safe compiler implementation in this repo yet." not in tutorial_text,
        "docs/tutorial.md must not claim the repo lacks a Safe compiler implementation",
    )
    require(
        "there is no compiler yet" not in tutorial_text,
        "docs/tutorial.md must not claim there is no compiler yet",
    )

    readme_text = README_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_README_SNIPPETS:
        require_contains(readme_text, snippet, "README.md")

    compiler_readme_text = COMPILER_README_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_COMPILER_README_SNIPPETS:
        require_contains(compiler_readme_text, snippet, "compiler_impl/README.md")

    workflow_text = WORKFLOW_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_CI_WORKFLOW_SNIPPETS:
        require_contains(workflow_text, snippet, ".github/workflows/ci.yml")

    pipeline_verify_workflow_text = PIPELINE_VERIFY_WORKFLOW_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_PIPELINE_VERIFY_WORKFLOW_SNIPPETS:
        require_contains(
            pipeline_verify_workflow_text,
            snippet,
            ".github/workflows/pipeline-verify.yml",
        )

    pre_push_text = (REPO_ROOT / "scripts" / "run_local_pre_push.py").read_text(encoding="utf-8")
    for snippet in EXPECTED_PRE_PUSH_SNIPPETS:
        require_contains(pre_push_text, snippet, "scripts/run_local_pre_push.py")

    retained_targets = Counter()
    promoted_targets = Counter()
    disposition_counts: Counter[str] = Counter()
    area_counts: Counter[str] = Counter()
    closed_removed: list[dict[str, str]] = []
    promoted_candidates: dict[str, list[str]] = defaultdict(list)

    for finding in findings:
        disposition = finding["disposition"]
        require(disposition in ALLOWED_DISPOSITIONS, f"{finding['id']}: invalid disposition {disposition}")
        require(finding["area"], f"{finding['id']}: area must not be empty")
        require(finding["claim_source"], f"{finding['id']}: claim source must not be empty")
        require(finding["observed_reality"], f"{finding['id']}: observed reality must not be empty")
        require(finding["evidence"], f"{finding['id']}: evidence must not be empty")
        require(finding["target"], f"{finding['id']}: target must not be empty")
        disposition_counts[disposition] += 1
        area_counts[finding["area"]] += 1

        if disposition == "retain-in-post-pr10":
            require(finding["target"] in residual_ids, f"{finding['id']}: retained target must exist in post-PR10 ledger")
            retained_targets[finding["target"]] += 1
        elif disposition == "promote-to-pr10x":
            require(finding["target"] in PROMOTED_TASKS, f"{finding['id']}: promoted target must be a tracked PR10.x task")
            promoted_targets[finding["target"]] += 1
            promoted_candidates[finding["target"]].append(finding["id"])
        else:
            closed_removed.append(
                {
                    "id": finding["id"],
                    "disposition": disposition,
                    "target": finding["target"],
                }
            )

    require(
        set(retained_targets) == residual_ids,
        "every retained post-PR10 residual must be justified by exactly one retain-in-post-pr10 finding",
    )
    require(
        all(count == 1 for count in retained_targets.values()),
        "each retained post-PR10 residual must be targeted by exactly one retain-in-post-pr10 finding",
    )
    require(
        promoted_targets == Counter({"PR10.4": 1, "PR10.5": 6, "PR10.6": 1}),
        "promoted follow-on findings must match the live post-PR10.3 PR10.4/PR10.5/PR10.6 split",
    )

    retained_priority_counts = Counter(item["priority"] for item in residuals)
    require(
        retained_priority_counts == Counter(
            {"blocking-if-needed": 14, "nice-to-have": 3, "long-term": 16}
        ),
        "retained post-PR10 priorities must match the normalized ledger counts",
    )

    artifact_hashes = {
        "audit_doc": sha256_file(AUDIT_DOC_PATH),
        "post_pr10_scope": sha256_file(POST_PR10_SCOPE_PATH),
        "matrix": sha256_file(MATRIX_PATH),
        "tracker": sha256_file(TRACKER_PATH),
        "dashboard": sha256_file(DASHBOARD_PATH),
        "readme": sha256_file(README_PATH),
        "compiler_readme": sha256_file(COMPILER_README_PATH),
        "ci_workflow": sha256_file(WORKFLOW_PATH),
        "pipeline_verify_workflow": sha256_file(PIPELINE_VERIFY_WORKFLOW_PATH),
    }
    semantic_floor = semantic_floor_from_baseline_truth(baseline_truth=baseline_truth)
    canonical_baseline_truth, machine_baseline_truth = split_baseline_truth(baseline_truth=baseline_truth)

    return build_three_way_report(
        identity={"task": "PR10.1"},
        semantic_floor=semantic_floor,
        canonical_proof_detail={
            "audited_surfaces": [
                "spec/TBD consistency",
                "frontend parser/resolver/analyzer supported surface",
                "emitted Ada/SPARK proof surface",
                "ownership/concurrency/runtime boundaries",
                "companion and emission-template verification",
                "tooling/evidence/report determinism",
                "traceability and docs",
                "open review and deferred concerns",
            ],
            "baseline_truth": canonical_baseline_truth,
            "finding_counts": {
                "total": len(findings),
                "by_area": dict(sorted(area_counts.items())),
                "by_disposition": dict(sorted(disposition_counts.items())),
            },
            "promoted_follow_on_candidates": [
                {
                    "task": task_id,
                    "title": task_map[task_id]["title"],
                    "finding_ids": promoted_candidates[task_id],
                }
                for task_id in PROMOTED_TASKS
            ],
            "retained_post_pr10_residuals": [
                {
                    "id": item["id"],
                    "priority": item["priority"],
                    "area": item["area"],
                }
                for item in residuals
            ],
            "closed_removed_residuals": closed_removed,
            "artifact_hashes": artifact_hashes,
            "tracker": {
                "next_task_id": tracker["next_task_id"],
                "pr101_status": task_map["PR10.1"]["status"],
                "pr101_evidence": task_map["PR10.1"]["evidence"],
                "pr111_status": task_map["PR11.1"]["status"],
                "pr111_evidence": task_map["PR11.1"]["evidence"],
                "promoted_tasks": {
                    task_id: {
                        "status": task_map[task_id]["status"],
                        "depends_on": task_map[task_id]["depends_on"],
                    }
                    for task_id in PROMOTED_TASKS
                },
            },
        },
        machine_sensitive={
            "baseline_truth": machine_baseline_truth,
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--pipeline-input", type=Path)
    parser.add_argument("--generated-root", type=Path)
    parser.add_argument("--authority", choices=("local", "ci"), default="local")
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    pipeline_input = load_pipeline_input(args.pipeline_input)
    baseline_truth = (
        pipeline_baseline_truth(env=env, pipeline_input=pipeline_input)
        if pipeline_input
        else run_baseline_truth(
            env=env,
            authority=args.authority,
            generated_root=args.generated_root,
        )
    )
    report = finalize_deterministic_report(
        lambda: build_report(
            baseline_truth=baseline_truth,
            generated_root=args.generated_root,
        ),
        label="PR10.1 comprehensive audit",
    )
    write_report(args.report, report)
    print(f"pr10.1 comprehensive audit: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr10.1 comprehensive audit: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
