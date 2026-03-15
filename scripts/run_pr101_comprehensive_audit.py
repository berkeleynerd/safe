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

from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    require,
    run,
    sha256_file,
    sha256_text,
    write_report,
)
from _lib.pr09_emit import REPO_ROOT, alr_command


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr101-comprehensive-audit-report.json"
TRACKER_PATH = REPO_ROOT / "execution" / "tracker.json"
DASHBOARD_PATH = REPO_ROOT / "execution" / "dashboard.md"
README_PATH = REPO_ROOT / "README.md"
COMPILER_README_PATH = REPO_ROOT / "compiler_impl" / "README.md"
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"
MATRIX_PATH = REPO_ROOT / "docs" / "emitted_output_verification_matrix.md"
POST_PR10_SCOPE_PATH = REPO_ROOT / "docs" / "post_pr10_scope.md"
AUDIT_DOC_PATH = REPO_ROOT / "docs" / "pr10_refinement_audit.md"

BASELINE_SCRIPTS = [
    REPO_ROOT / "scripts" / "run_pr08_frontend_baseline.py",
    REPO_ROOT / "scripts" / "run_pr09_ada_emission_baseline.py",
    REPO_ROOT / "scripts" / "run_pr10_emitted_baseline.py",
    REPO_ROOT / "scripts" / "run_emitted_hardening_regressions.py",
]
EXPECTED_PR101_ACCEPTANCE = [
    "Authoritative PR08, PR09, PR10, supplemental hardening, companion/template verification, and execution-state baselines rerun serially and establish the audit truth baseline.",
    "docs/pr10_refinement_audit.md classifies every current post-PR10 residual and current PR10/post-PR10 claim surface using the required finding schema and allowed dispositions.",
    "docs/post_pr10_scope.md and docs/emitted_output_verification_matrix.md are normalized to the audit outcome, and the first concrete PR10.2+ follow-on tasks are defined in execution/tracker.json.",
]
EXPECTED_PR101_EVIDENCE = [
    "execution/reports/pr101-comprehensive-audit-report.json",
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
PROMOTED_TASKS = ("PR10.2", "PR10.3", "PR10.4")
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
    "`PR10.3` — Sequential emitted proof-corpus expansion beyond the frozen PR10 subset",
    "`PR10.4` — GNATprove evidence and parser hardening",
]
EXPECTED_MATRIX_SNIPPETS = [
    "frontend Silver ownership analysis is the mechanism that prevents use-after-free",
    "PR10.3",
    "PS-007",
    "PS-019",
    "PS-031",
    "docs/pr10_refinement_audit.md",
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
EXPECTED_WORKFLOW_SNIPPETS = [
    "pr101-comprehensive-audit:",
    "python3 scripts/run_pr101_comprehensive_audit.py",
    "git diff --exit-code execution/reports/pr101-comprehensive-audit-report.json",
]
EXPECTED_PRE_PUSH_SNIPPETS = [
    "\"scripts/run_pr101_comprehensive_audit.py\"",
]


def load_tracker() -> dict[str, Any]:
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def require_contains(text: str, snippet: str, label: str) -> None:
    require(snippet in text, f"{label}: expected to contain {snippet!r}")


def compact_result(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "command": result["command"],
        "cwd": result["cwd"],
        "returncode": result["returncode"],
    }


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


def normalized_assumptions_hash(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    normalized = re.sub(r"^# Generated: .*\n", "", text, flags=re.MULTILINE)
    return sha256_text(normalized)


def snapshot_text(path: Path) -> str | None:
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8")


def restore_text(path: Path, original: str | None) -> None:
    if original is None:
        if path.exists():
            path.unlink()
        return
    path.write_text(original, encoding="utf-8")


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


def run_python_gate(*, python: str, script: Path, env: dict[str, str], temp_root: Path) -> dict[str, Any]:
    report_path = temp_root / f"{script.stem}.json"
    result = run(
        [python, str(script), "--report", str(report_path)],
        cwd=REPO_ROOT,
        env=env,
        temp_root=temp_root,
    )
    payload = json.loads(report_path.read_text(encoding="utf-8"))
    return {
        "script": display_path(script, repo_root=REPO_ROOT),
        "result": compact_result(result),
        "report_sha256": payload["report_sha256"],
        "deterministic": payload["deterministic"],
    }


def run_companion_verify(*, env: dict[str, str]) -> dict[str, Any]:
    bash = find_command("bash")
    alr = alr_command()
    companion_root = REPO_ROOT / "companion" / "gen"

    assumptions_path = REPO_ROOT / "companion" / "assumptions_extracted.txt"
    original_assumptions = snapshot_text(assumptions_path)
    build = run([alr, "build"], cwd=companion_root, env=env)
    flow = run(
        [alr, "exec", "--", "gnatprove", "-P", "companion.gpr", "--mode=flow", "--report=all", "--warnings=error"],
        cwd=companion_root,
        env=env,
    )
    prove = run(
        [
            alr,
            "exec",
            "--",
            "gnatprove",
            "-P",
            "companion.gpr",
            "--mode=prove",
            "--level=2",
            "--prover=cvc5,z3,altergo",
            "--steps=0",
            "--timeout=120",
            "--report=all",
            "--warnings=error",
            "--checks-as-errors=on",
        ],
        cwd=companion_root,
        env=env,
    )
    try:
        extract = run([bash, "scripts/extract_assumptions.sh"], cwd=REPO_ROOT, env=env)
        extracted_hash = normalized_assumptions_hash(assumptions_path)
        diff = run([bash, "scripts/diff_assumptions.sh"], cwd=REPO_ROOT, env=env)
    finally:
        restore_text(assumptions_path, original_assumptions)
    prove_golden_hash = sha256_file(REPO_ROOT / "companion" / "gen" / "prove_golden.txt")
    gnatprove_out_hash = sha256_file(REPO_ROOT / "companion" / "gen" / "obj" / "gnatprove" / "gnatprove.out")
    return {
        "build": compact_result(build),
        "flow": compact_result(flow),
        "prove": compact_result(prove),
        "extract_assumptions": compact_result(extract),
        "diff_assumptions": compact_result(diff),
        "assumptions_extracted_sha256": extracted_hash,
        "prove_golden_sha256": prove_golden_hash,
        "gnatprove_out_sha256": gnatprove_out_hash,
    }


def run_templates_verify(*, env: dict[str, str]) -> dict[str, Any]:
    bash = find_command("bash")
    alr = alr_command()
    templates_root = REPO_ROOT / "companion" / "templates"

    assumptions_path = REPO_ROOT / "companion" / "assumptions_extracted.txt"
    original_assumptions = snapshot_text(assumptions_path)
    build = run([alr, "build"], cwd=templates_root, env=env)
    flow = run(
        [alr, "exec", "--", "gnatprove", "-P", "templates.gpr", "--mode=flow", "--report=all", "--warnings=error"],
        cwd=templates_root,
        env=env,
    )
    prove = run(
        [
            alr,
            "exec",
            "--",
            "gnatprove",
            "-P",
            "templates.gpr",
            "--mode=prove",
            "--level=2",
            "--prover=cvc5,z3,altergo",
            "--steps=0",
            "--timeout=120",
            "--report=all",
            "--warnings=error",
            "--checks-as-errors=on",
        ],
        cwd=templates_root,
        env=env,
    )
    extract_env = env.copy()
    extract_env["PROVE_OUT"] = "companion/templates/obj/gnatprove"
    diff_env = env.copy()
    diff_env["PROVE_GOLDEN"] = "companion/templates/prove_golden.txt"
    diff_env["PROVE_OUT"] = "companion/templates/obj/gnatprove/gnatprove.out"
    try:
        extract = run([bash, "scripts/extract_assumptions.sh"], cwd=REPO_ROOT, env=extract_env)
        extracted_hash = normalized_assumptions_hash(assumptions_path)
        diff = run([bash, "scripts/diff_assumptions.sh"], cwd=REPO_ROOT, env=diff_env)
    finally:
        restore_text(assumptions_path, original_assumptions)
    prove_golden_hash = sha256_file(REPO_ROOT / "companion" / "templates" / "prove_golden.txt")
    gnatprove_out_hash = sha256_file(REPO_ROOT / "companion" / "templates" / "obj" / "gnatprove" / "gnatprove.out")
    return {
        "build": compact_result(build),
        "flow": compact_result(flow),
        "prove": compact_result(prove),
        "extract_assumptions": compact_result(extract),
        "diff_assumptions": compact_result(diff),
        "assumptions_extracted_sha256": extracted_hash,
        "prove_golden_sha256": prove_golden_hash,
        "gnatprove_out_sha256": gnatprove_out_hash,
    }


def run_baseline_truth(*, env: dict[str, str]) -> dict[str, Any]:
    python = find_command("python3")
    with tempfile.TemporaryDirectory(prefix="pr101-audit-") as temp_root_str:
        temp_root = Path(temp_root_str)
        gates = [run_python_gate(python=python, script=script, env=env, temp_root=temp_root) for script in BASELINE_SCRIPTS]
        return {
            "python_gates": gates,
            "companion_verify": run_companion_verify(env=env),
            "templates_verify": run_templates_verify(env=env),
        }


def build_report(*, baseline_truth: dict[str, Any]) -> dict[str, Any]:
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
    require(tracker.get("next_task_id") == "PR10.2", "next_task_id must advance to PR10.2 after PR10.1")
    for task_id in PROMOTED_TASKS:
        require(task_id in task_map, f"tracker must define promoted task {task_id}")
        require(task_map[task_id]["status"] == "planned", f"{task_id} must remain planned")
        require(task_map[task_id]["depends_on"] == ["PR10.1"], f"{task_id} must depend on PR10.1")

    rendered_dashboard = run([find_command("python3"), "scripts/render_execution_status.py"], cwd=REPO_ROOT, env=ensure_sdkroot(os.environ.copy()))
    dashboard_text = DASHBOARD_PATH.read_text(encoding="utf-8")
    require(dashboard_text == rendered_dashboard["stdout"], "execution/dashboard.md must match render_execution_status.py")
    require_contains(dashboard_text, "- **Next task:** `PR10.2`", "execution/dashboard.md")
    require_contains(dashboard_text, "| PR10.1 | done | PR10 | 1 |", "execution/dashboard.md")
    require_contains(dashboard_text, "| PR10.2 | planned | PR10.1 | 0 |", "execution/dashboard.md")

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

    readme_text = README_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_README_SNIPPETS:
        require_contains(readme_text, snippet, "README.md")

    compiler_readme_text = COMPILER_README_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_COMPILER_README_SNIPPETS:
        require_contains(compiler_readme_text, snippet, "compiler_impl/README.md")

    workflow_text = WORKFLOW_PATH.read_text(encoding="utf-8")
    for snippet in EXPECTED_WORKFLOW_SNIPPETS:
        require_contains(workflow_text, snippet, ".github/workflows/ci.yml")

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
        promoted_targets == Counter({"PR10.2": 3, "PR10.3": 1, "PR10.4": 1}),
        "promoted follow-on findings must match the audited PR10.2/PR10.3/PR10.4 split",
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
        "workflow": sha256_file(WORKFLOW_PATH),
    }

    return {
        "task": "PR10.1",
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
        "baseline_truth": baseline_truth,
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
            "promoted_tasks": {
                task_id: {
                    "status": task_map[task_id]["status"],
                    "depends_on": task_map[task_id]["depends_on"],
                }
                for task_id in PROMOTED_TASKS
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    env = ensure_sdkroot(os.environ.copy())
    baseline_truth = run_baseline_truth(env=env)
    baseline_truth["execution_state_validation"] = compact_result(
        run([find_command("python3"), "scripts/validate_execution_state.py"], cwd=REPO_ROOT, env=env)
    )
    report = finalize_deterministic_report(
        lambda: build_report(baseline_truth=baseline_truth),
        label="PR10.1 comprehensive audit",
    )
    write_report(args.report, report)
    if args.report != DEFAULT_REPORT:
        write_report(DEFAULT_REPORT, report)
    print(f"pr10.1 comprehensive audit: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr10.1 comprehensive audit: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
