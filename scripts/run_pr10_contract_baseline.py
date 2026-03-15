#!/usr/bin/env python3
"""Run the PR10 contract baseline gate."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from _lib.harness_common import display_path, finalize_deterministic_report, require, write_report
from _lib.pr10_emit import (
    EXPECTED_COVERAGE,
    REPO_ROOT,
    normalize_source_text,
    normalized_source_fragments,
    selected_emitted_corpus,
)


DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr10-contract-baseline-report.json"
TRACKER_PATH = REPO_ROOT / "execution" / "tracker.json"
FRONTEND_BASELINE_PATH = REPO_ROOT / "docs" / "frontend_architecture_baseline.md"
MATRIX_PATH = REPO_ROOT / "docs" / "emitted_output_verification_matrix.md"
POST_PR10_SCOPE_PATH = REPO_ROOT / "docs" / "post_pr10_scope.md"
README_PATH = REPO_ROOT / "README.md"
COMPILER_README_PATH = REPO_ROOT / "compiler_impl" / "README.md"

EXPECTED_ACCEPTANCE = [
    "The selected emitted corpus spans Rules 1-5, ownership, and concurrency through the named PR10 fixtures.",
    "Selected emitted outputs build and pass GNATprove flow/prove with zero warnings, zero justified checks, and zero unproved checks.",
    "docs/emitted_output_verification_matrix.md is the canonical emitted-output coverage statement, and docs/post_pr10_scope.md records every residual gap beyond the selected corpus.",
]
EXPECTED_COVERAGE_LINES = [
    "Rule 1",
    "Rule 2",
    "Rule 3",
    "Rule 4",
    "Rule 5",
    "ownership",
    "concurrency",
]
MATRIX_REQUIRED_SNIPPETS = [
    "Coverage Notes",
    "Other currently emitted sequential fixtures outside the PR10 corpus",
    "Other currently emitted concurrency fixtures outside the PR10 corpus",
    "Channel access-type compile-only subset",
    "I/O seams outside pure emitted packages",
    "zero warnings",
    "zero justified checks",
    "zero unproved checks",
    "polling-based lowering",
]
POST_PR10_REQUIRED_SNIPPETS = [
    "Emitted-output GNATprove coverage beyond the selected PR10 sequential corpus",
    "Emitted-output GNATprove coverage beyond the selected PR10 concurrency corpus",
    "I/O seam wrapper obligations beyond direct emitted-package proof",
    "Jorvik/Ravenscar runtime scheduling, ceiling-locking, and polling-timing obligations beyond direct emitted-package proof",
    "Faithful source-level `select ... or delay ...` semantics beyond the current emitted polling-based lowering",
]


def load_tracker() -> dict[str, object]:
    return json.loads(TRACKER_PATH.read_text(encoding="utf-8"))


def require_contains(text: str, snippet: str, label: str) -> None:
    require(snippet in text, f"{label}: expected to contain {snippet!r}")


def row_contains(text: str, *parts: str) -> bool:
    pattern = r"\|[^\n]*" + r"[^\n]*".join(re.escape(part) for part in parts) + r"[^\n]*\|"
    return re.search(pattern, text) is not None


def extract_bullets_after(text: str, anchor: str, *, label: str) -> list[str]:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.strip() != anchor:
            continue
        bullets: list[str] = []
        started = False
        for candidate in lines[index + 1 :]:
            stripped = candidate.strip()
            if not stripped:
                if started:
                    break
                continue
            require(stripped.startswith("- "), f"{label}: expected bullet after {anchor!r}, found {stripped!r}")
            started = True
            bullets.append(stripped[2:])
        require(bullets, f"{label}: missing bullets after {anchor!r}")
        return bullets
    raise RuntimeError(f"{label}: missing anchor {anchor!r}")


def generate_report() -> dict[str, object]:
    tracker = load_tracker()
    task_map = {task["id"]: task for task in tracker["tasks"]}  # type: ignore[index]
    pr10 = task_map["PR10"]
    require(pr10["title"] == "GNATprove flow/prove gate on emitted output", "PR10 title must stay canonical")
    require(pr10["depends_on"] == ["PR09"], "PR10 must depend on PR09")
    require(pr10["acceptance"] == EXPECTED_ACCEPTANCE, "PR10 acceptance text must match the strengthened contract")

    selected_corpus = selected_emitted_corpus()
    expected_fixtures = [f"`{item['fixture']}`" for item in selected_corpus]
    expected_coverage = set(EXPECTED_COVERAGE)
    require(expected_coverage == EXPECTED_COVERAGE, "internal expected coverage must remain stable")

    matrix_text = MATRIX_PATH.read_text(encoding="utf-8")
    matrix_fixtures = extract_bullets_after(
        matrix_text,
        "The PR10 selected emitted corpus is:",
        label="docs/emitted_output_verification_matrix.md",
    )
    require(
        matrix_fixtures == expected_fixtures,
        "docs/emitted_output_verification_matrix.md: selected emitted corpus must match the PR10 helper list exactly",
    )
    matrix_coverage = extract_bullets_after(
        matrix_text,
        "That selected corpus explicitly spans:",
        label="docs/emitted_output_verification_matrix.md",
    )
    require(
        matrix_coverage == EXPECTED_COVERAGE_LINES,
        "docs/emitted_output_verification_matrix.md: coverage bullets must match the PR10 contract exactly",
    )
    observed_coverage = {item["coverage"] for item in selected_corpus}
    require(
        observed_coverage == EXPECTED_COVERAGE,
        "selected emitted corpus must cover Rules 1-5, ownership, and concurrency",
    )
    for snippet in MATRIX_REQUIRED_SNIPPETS:
        require_contains(matrix_text, snippet, "docs/emitted_output_verification_matrix.md")
    for item in selected_corpus:
        fixture_name = Path(item["fixture"]).name
        require(
            row_contains(matrix_text, item["feature"], fixture_name, item["matrix_note"]),
            "docs/emitted_output_verification_matrix.md: expected row "
            f"for {fixture_name} with feature {item['feature']!r} and note {item['matrix_note']!r}",
        )
        normalized_source = normalize_source_text((REPO_ROOT / item["fixture"]).read_text(encoding="utf-8"))
        for fragment in normalized_source_fragments(item):
            require(
                fragment in normalized_source,
                f"{item['fixture']}: missing required normalized source fragment {fragment!r}",
            )

    post_pr10_text = POST_PR10_SCOPE_PATH.read_text(encoding="utf-8")
    for snippet in POST_PR10_REQUIRED_SNIPPETS:
        require_contains(post_pr10_text, snippet, "docs/post_pr10_scope.md")

    baseline_text = FRONTEND_BASELINE_PATH.read_text(encoding="utf-8")
    require_contains(
        baseline_text,
        "PR10 adds selected emitted-output GNATprove `flow` / `prove` verification on top",
        "docs/frontend_architecture_baseline.md",
    )
    require_contains(
        baseline_text,
        "emitted-output GNATprove coverage beyond the selected PR10 corpus",
        "docs/frontend_architecture_baseline.md",
    )

    readme_text = README_PATH.read_text(encoding="utf-8")
    require_contains(
        readme_text,
        "[`docs/emitted_output_verification_matrix.md`](docs/emitted_output_verification_matrix.md)",
        "README.md",
    )
    require_contains(
        readme_text,
        "[`docs/post_pr10_scope.md`](docs/post_pr10_scope.md)",
        "README.md",
    )
    require_contains(
        readme_text,
        "the PR10 emitted-output GNATprove contract/flow/prove/baseline jobs",
        "README.md",
    )
    require_contains(
        readme_text,
        "selected emitted-output GNATprove `flow` / `prove` verification for Rules 1-5, ownership, and the current concurrency emission corpus under an all-proved-only policy",
        "README.md",
    )
    require_contains(
        readme_text,
        "known `codex/pr08...`, `codex/pr09...`, and `codex/pr10...` branches",
        "README.md",
    )

    compiler_readme_text = COMPILER_README_PATH.read_text(encoding="utf-8")
    require_contains(
        compiler_readme_text,
        "[`../docs/emitted_output_verification_matrix.md`](../docs/emitted_output_verification_matrix.md)",
        "compiler_impl/README.md",
    )
    require_contains(
        compiler_readme_text,
        "[`../docs/post_pr10_scope.md`](../docs/post_pr10_scope.md)",
        "compiler_impl/README.md",
    )
    require_contains(
        compiler_readme_text,
        "The PR10 contract baseline gate is:",
        "compiler_impl/README.md",
    )
    require_contains(
        compiler_readme_text,
        "The PR10 emitted prove gate is:",
        "compiler_impl/README.md",
    )

    return {
        "task": "PR10",
        "contract": {
            "acceptance": EXPECTED_ACCEPTANCE,
            "selected_corpus": [item["fixture"] for item in selected_emitted_corpus()],
            "coverage_categories": EXPECTED_COVERAGE_LINES,
        },
        "docs": {
            "frontend_baseline": display_path(FRONTEND_BASELINE_PATH, repo_root=REPO_ROOT),
            "matrix": display_path(MATRIX_PATH, repo_root=REPO_ROOT),
            "post_pr10_scope": display_path(POST_PR10_SCOPE_PATH, repo_root=REPO_ROOT),
            "readme": display_path(README_PATH, repo_root=REPO_ROOT),
            "compiler_readme": display_path(COMPILER_README_PATH, repo_root=REPO_ROOT),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    report = finalize_deterministic_report(
        generate_report,
        label="PR10 contract baseline",
    )
    write_report(args.report, report)
    print(f"pr10 contract baseline: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, FileNotFoundError) as exc:
        print(f"pr10 contract baseline: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
