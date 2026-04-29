#!/usr/bin/env python3
"""Report Phase 1I.C schema-vs-documentation alignment audit hits."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
BASELINE_PATH = REPO_ROOT / "audit" / "phase1i_schema_doc_alignment_baseline.json"
AUDIT_DOC = REPO_ROOT / "docs" / "compiler_pre_pr12_audit.md"
ARTIFACT_CONTRACT_DOC = REPO_ROOT / "docs" / "artifact_contract.md"
TRANSLATION_RULES_DOC = REPO_ROOT / "compiler" / "translation_rules.md"
AST_SCHEMA_PATH = REPO_ROOT / "compiler" / "ast_schema.json"
TRACEABILITY_MD = REPO_ROOT / "docs" / "traceability_matrix.md"
TRACEABILITY_CSV = REPO_ROOT / "docs" / "traceability_matrix.csv"
OUTPUT_CONTRACT_VALIDATOR = REPO_ROOT / "scripts" / "validate_output_contracts.py"
HARNESS_COMMON = REPO_ROOT / "scripts" / "_lib" / "harness_common.py"

CATEGORIES = (
    "artifact-contract-shape",
    "audit-doc-baseline-count",
    "audit-doc-baseline-status",
    "frozen-commit-freshness",
    "schema-ast-reference",
)
PATTERNS = (
    "artifact-contract-diagnostics-format",
    "artifact-contract-format-version",
    "artifact-contract-optional-field",
    "artifact-contract-required-field",
    "artifact-contract-target-bits",
    "audit-doc-baseline-summary",
    "audit-doc-category-count",
    "audit-doc-category-classification",
    "frozen-commit-value",
    "translation-rules-ast-node",
)
ALIGNMENT_STATUSES = ("aligned", "mismatch", "missing-target", "unknown")

BASELINE_BY_PHASE = {
    "1C": REPO_ROOT / "audit" / "phase1c_arithmetic_baseline.json",
    "1D": REPO_ROOT / "audit" / "phase1d_gnatprove_trust_baseline.json",
    "1E": REPO_ROOT / "audit" / "phase1e_spark_mode_off_baseline.json",
    "1F": REPO_ROOT / "audit" / "phase1f_dead_raise_baseline.json",
    "1G": REPO_ROOT / "audit" / "phase1g_spec_body_contract_baseline.json",
    "1H": REPO_ROOT / "audit" / "phase1h_stdlib_contract_baseline.json",
    "1I.A": REPO_ROOT / "audit" / "phase1i_docs_fixture_drift_baseline.json",
    "1I.B": REPO_ROOT / "audit" / "phase1i_code_snippet_drift_baseline.json",
}

NUMBER_WORDS = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
}


@dataclass(frozen=True)
class Claim:
    category: str
    pattern: str
    path: Path
    line: int
    claim_key: str
    claim_text: str
    verification_target: str
    doc_value: object
    actual_value: object
    alignment_status: str


@dataclass(frozen=True)
class ArtifactClaim:
    claim_key: str
    marker: str
    pattern: str
    doc_value: str
    actual: Callable[[], tuple[str, str]]


def repo_rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def normalized_text(text: str) -> str:
    return " ".join(text.strip().split())


def fingerprint_for(claim: Claim) -> str:
    seed = (
        f"{claim.category}\0{repo_rel(claim.path)}\0{claim.claim_key}\0"
        f"{normalized_text(claim.claim_text)}\0{claim.verification_target}"
    )
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]


def load_json(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise TypeError(f"{repo_rel(path)} top-level value is not an object")
    return payload


def baseline_entries(path: Path) -> list[dict[str, object]]:
    payload = load_json(path)
    entries = payload.get("entries", [])
    if not isinstance(entries, list):
        raise TypeError(f"{repo_rel(path)} entries field is not a list")
    return [entry for entry in entries if isinstance(entry, dict)]


def count_by(entries: Iterable[dict[str, object]], field: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for entry in entries:
        value = str(entry.get(field, ""))
        counts[value] = counts.get(value, 0) + 1
    return counts


def classification_summary(entries: list[dict[str, object]]) -> str:
    if not entries:
        return "none"
    counts = count_by(entries, "classification")
    if len(counts) == 1:
        return next(iter(counts))
    return ", ".join(f"{key}:{counts[key]}" for key in sorted(counts))


def load_baseline_state() -> dict[str, dict[str, object]]:
    state: dict[str, dict[str, object]] = {}
    for phase, path in BASELINE_BY_PHASE.items():
        entries = baseline_entries(path)
        state[phase] = {
            "path": path,
            "entries": entries,
            "categories": count_by(entries, "category"),
            "classifications": count_by(entries, "classification"),
        }
    return state


def clean_cell(text: str) -> str:
    value = text.strip()
    value = re.sub(r"^\*\*(.*)\*\*$", r"\1", value)
    value = value.strip("`").strip()
    return value


def parse_count(value: str) -> int | None:
    cleaned = clean_cell(value).replace(",", "")
    match = re.search(r"\d+", cleaned)
    if match is not None:
        return int(match.group(0))
    lowered = cleaned.lower()
    return NUMBER_WORDS.get(lowered)


def status_for_count(doc_value: object, actual_value: object) -> str:
    return "aligned" if doc_value == actual_value else "mismatch"


def make_count_claim(
    *,
    phase: str,
    path: Path,
    line: int,
    table_label: str,
    key: str,
    doc_value: int,
    actual_value: int | None,
    claim_text: str,
    pattern: str,
) -> Claim:
    effective_actual = 0 if actual_value is None and doc_value == 0 else actual_value
    status = (
        "missing-target"
        if effective_actual is None
        else status_for_count(doc_value, effective_actual)
    )
    target = f"{repo_rel(BASELINE_BY_PHASE[phase])}:{key}"
    return Claim(
        category="audit-doc-baseline-count",
        pattern=pattern,
        path=path,
        line=line,
        claim_key=f"{phase}:{table_label}:{key}",
        claim_text=claim_text,
        verification_target=target,
        doc_value=doc_value,
        actual_value="" if effective_actual is None else effective_actual,
        alignment_status=status,
    )


def make_status_claim(
    *,
    phase: str,
    path: Path,
    line: int,
    table_label: str,
    key: str,
    doc_value: str,
    actual_value: str,
    claim_text: str,
) -> Claim:
    return Claim(
        category="audit-doc-baseline-status",
        pattern="audit-doc-category-classification",
        path=path,
        line=line,
        claim_key=f"{phase}:{table_label}:{key}:classification",
        claim_text=claim_text,
        verification_target=f"{repo_rel(BASELINE_BY_PHASE[phase])}:{key}:classification",
        doc_value=doc_value,
        actual_value=actual_value,
        alignment_status=status_for_count(doc_value, actual_value),
    )


def phase_from_heading(line: str) -> tuple[bool, str | None]:
    match = re.match(r"^#{2,3}\s+Phase\s+(1[A-Z](?:\.[A-Z])?)\b", line)
    if match is None:
        return False, None
    phase = match.group(1)
    return True, phase if phase in BASELINE_BY_PHASE else None


def table_cells(line: str) -> list[str] | None:
    if not line.startswith("|") or "---" in line:
        return None
    cells = [clean_cell(cell) for cell in line.strip().strip("|").split("|")]
    if len(cells) < 2 or cells[0] in {"Category", "Status", "Language", "Package"}:
        return None
    return cells


def actual_count_for_row(
    *,
    phase: str,
    row_key: str,
    baseline_state: dict[str, dict[str, object]],
) -> int | None:
    state = baseline_state[phase]
    entries = state["entries"]
    assert isinstance(entries, list)
    if row_key == "Total":
        return len(entries)
    categories = state["categories"]
    assert isinstance(categories, dict)
    raw = categories.get(row_key)
    return int(raw) if raw is not None else None


def actual_classification_for_row(
    *,
    phase: str,
    row_key: str,
    baseline_state: dict[str, dict[str, object]],
) -> str:
    entries = baseline_state[phase]["entries"]
    assert isinstance(entries, list)
    if row_key == "Total":
        return classification_summary(entries)
    matching = [entry for entry in entries if entry.get("category") == row_key]
    return classification_summary(matching)


def prose_summary_claims(
    *,
    phase: str,
    line_number: int,
    line: str,
    next_line: str,
    baseline_state: dict[str, dict[str, object]],
) -> list[Claim]:
    if not re.search(r"\b(?:Current|Final) baseline(?: entries)?:", line):
        return []
    combined = normalized_text(f"{line} {next_line}")
    total_match = re.search(r"baseline(?: entries)?:\s+([^:.;]+)", combined, re.IGNORECASE)
    if total_match is None:
        return []
    doc_count = parse_count(total_match.group(1))
    if doc_count is None:
        return []
    entries = baseline_state[phase]["entries"]
    assert isinstance(entries, list)
    claims = [
        make_count_claim(
            phase=phase,
            path=AUDIT_DOC,
            line=line_number,
            table_label="prose-summary",
            key="total",
            doc_value=doc_count,
            actual_value=len(entries),
            claim_text=combined,
            pattern="audit-doc-baseline-summary",
        )
    ]
    status_counts: dict[str, int] = {}
    for count_text, classification in re.findall(
        r"(\d+)\s+`?(candidate|needs-repro|confirmed-defect|accepted-with-rationale)`?",
        combined,
    ):
        status_counts[classification] = int(count_text)
    if status_counts:
        doc_value = ", ".join(f"{key}:{status_counts[key]}" for key in sorted(status_counts))
        actual_counts = baseline_state[phase]["classifications"]
        assert isinstance(actual_counts, dict)
        actual_value = ", ".join(
            f"{key}:{int(actual_counts[key])}" for key in sorted(actual_counts)
        )
        claims.append(
            Claim(
                category="audit-doc-baseline-status",
                pattern="audit-doc-baseline-summary",
                path=AUDIT_DOC,
                line=line_number,
                claim_key=f"{phase}:prose-summary:classification",
                claim_text=combined,
                verification_target=f"{repo_rel(BASELINE_BY_PHASE[phase])}:classification",
                doc_value=doc_value,
                actual_value=actual_value,
                alignment_status=status_for_count(doc_value, actual_value),
            )
        )
    return claims


def iter_audit_doc_baseline_claims() -> Iterable[Claim]:
    baseline_state = load_baseline_state()
    lines = AUDIT_DOC.read_text(encoding="utf-8").splitlines()
    phase: str | None = None
    table_header: tuple[str, ...] = ()
    table_label = ""
    previous_non_empty = ""
    for index, line in enumerate(lines, start=1):
        phase_heading, new_phase = phase_from_heading(line)
        if phase_heading:
            phase = new_phase
            table_header = ()
            table_label = ""
        stripped = line.strip()
        if phase is not None:
            next_line = lines[index] if index < len(lines) else ""
            yield from prose_summary_claims(
                phase=phase,
                line_number=index,
                line=line,
                next_line=next_line,
                baseline_state=baseline_state,
            )
        if stripped and not stripped.startswith("|"):
            previous_non_empty = stripped.rstrip(":")
        if phase is None:
            continue
        if line.startswith("|") and "---" not in line:
            raw_cells = [clean_cell(cell) for cell in line.strip().strip("|").split("|")]
            if raw_cells and raw_cells[0] in {"Category", "Status", "Language", "Package"}:
                table_header = tuple(raw_cells)
                table_label = previous_non_empty
                continue
        cells = table_cells(line)
        if cells is None:
            continue
        row_key = cells[0]
        doc_count = parse_count(cells[1])
        if doc_count is not None and table_header and table_header[0] == "Category":
            actual_count = actual_count_for_row(
                phase=phase,
                row_key=row_key,
                baseline_state=baseline_state,
            )
            yield make_count_claim(
                phase=phase,
                path=AUDIT_DOC,
                line=index,
                table_label=table_label or "table",
                key=row_key,
                doc_value=doc_count,
                actual_value=actual_count,
                claim_text=normalized_text(line),
                pattern="audit-doc-category-count",
            )
        if table_header and table_header[0] == "Category" and len(cells) >= 3:
            classification_index = (
                table_header.index("Current classification")
                if "Current classification" in table_header
                else 2
            )
            if classification_index >= len(cells):
                continue
            doc_classification = clean_cell(cells[classification_index])
            if doc_classification:
                yield make_status_claim(
                    phase=phase,
                    path=AUDIT_DOC,
                    line=index,
                    table_label=table_label or "table",
                    key=row_key,
                    doc_value=doc_classification,
                    actual_value=actual_classification_for_row(
                        phase=phase,
                        row_key=row_key,
                        baseline_state=baseline_state,
                    ),
                    claim_text=normalized_text(line),
                )


def ast_node_names() -> set[str]:
    schema = load_json(AST_SCHEMA_PATH)
    nodes = schema.get("nodes", [])
    if not isinstance(nodes, list):
        raise TypeError("compiler/ast_schema.json nodes field is not a list")
    return {
        str(node.get("node_type"))
        for node in nodes
        if isinstance(node, dict) and isinstance(node.get("node_type"), str)
    }


def iter_ast_reference_claims() -> Iterable[Claim]:
    nodes = ast_node_names()
    lines = TRANSLATION_RULES_DOC.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines, start=1):
        segments: list[str] = []
        if "AST:" in line:
            segments.append(line.split("AST:", 1)[1])
        if "**AST node:**" in line:
            segments.append(line.split("**AST node:**", 1)[1])
        seen_on_line: set[str] = set()
        for segment in segments:
            for match in re.finditer(r"`([A-Z][A-Za-z0-9_]+)`", segment):
                node_name = match.group(1)
                if node_name in seen_on_line:
                    continue
                seen_on_line.add(node_name)
                present = node_name in nodes
                yield Claim(
                    category="schema-ast-reference",
                    pattern="translation-rules-ast-node",
                    path=TRANSLATION_RULES_DOC,
                    line=index,
                    claim_key=f"ast-node:{node_name}",
                    claim_text=normalized_text(line),
                    verification_target=f"{repo_rel(AST_SCHEMA_PATH)}:nodes.{node_name}",
                    doc_value=node_name,
                    actual_value="present" if present else "missing",
                    alignment_status="aligned" if present else "missing-target",
                )


def text_contains(path: Path, needle: str) -> bool:
    return needle in path.read_text(encoding="utf-8")


def actual_presence(path: Path, needle: str) -> tuple[str, str]:
    return ("present" if text_contains(path, needle) else "missing", repo_rel(path))


def actual_value_when_present(path: Path, needle: str, value: str) -> tuple[str, str]:
    return (value if text_contains(path, needle) else "missing", repo_rel(path))


def actual_target_bits_values() -> tuple[str, str]:
    text = OUTPUT_CONTRACT_VALIDATOR.read_text(encoding="utf-8")
    present = (
        re.search(r"bits\s+not\s+in\s+\{\s*32\s*,\s*64\s*\}", text) is not None
        and re.search(r"must\s+be\s+32\s+or\s+64", text) is not None
    )
    return ("32|64" if present else "missing", repo_rel(OUTPUT_CONTRACT_VALIDATOR))


def actual_target_bits_equality() -> tuple[str, str]:
    text = OUTPUT_CONTRACT_VALIDATOR.read_text(encoding="utf-8")
    present = (
        re.search(
            r'typed_payload\[\s*"target_bits"\s*\]\s*!=\s*mir_payload\[\s*"target_bits"\s*\]',
            text,
        )
        is not None
        and re.search(
            r'typed_payload\[\s*"target_bits"\s*\]\s*!=\s*safei_payload\[\s*"target_bits"\s*\]',
            text,
        )
        is not None
    )
    return ("typed=mir=safei" if present else "missing", repo_rel(OUTPUT_CONTRACT_VALIDATOR))


def artifact_claims() -> list[ArtifactClaim]:
    return [
        ArtifactClaim(
            "typed-format-version",
            '`typed.json` with `format: "typed-v6"`',
            "artifact-contract-format-version",
            "typed-v6",
            lambda: actual_value_when_present(
                OUTPUT_CONTRACT_VALIDATOR, "typed-v6", "typed-v6"
            ),
        ),
        ArtifactClaim(
            "mir-format-version",
            '`mir.json` with `format: "mir-v4"`',
            "artifact-contract-format-version",
            "mir-v4",
            lambda: actual_value_when_present(
                OUTPUT_CONTRACT_VALIDATOR, "mir-v4", "mir-v4"
            ),
        ),
        ArtifactClaim(
            "safei-format-version",
            '`safei.json` with `format: "safei-v5"`',
            "artifact-contract-format-version",
            "safei-v5",
            lambda: actual_value_when_present(
                OUTPUT_CONTRACT_VALIDATOR, "safei-v5", "safei-v5"
            ),
        ),
        ArtifactClaim(
            "diagnostics-format-version",
            "`diagnostics-v0` remains the current stable diagnostics shape",
            "artifact-contract-diagnostics-format",
            "diagnostics-v0",
            lambda: actual_value_when_present(
                HARNESS_COMMON, "diagnostics-v0", "diagnostics-v0"
            ),
        ),
        ArtifactClaim(
            "required-format-field",
            "- `format`",
            "artifact-contract-required-field",
            "required",
            lambda: actual_value_when_present(
                OUTPUT_CONTRACT_VALIDATOR, '"format"', "required"
            ),
        ),
        ArtifactClaim(
            "required-target-bits-field",
            "- `target_bits`",
            "artifact-contract-required-field",
            "required",
            lambda: actual_value_when_present(
                OUTPUT_CONTRACT_VALIDATOR, '"target_bits"', "required"
            ),
        ),
        ArtifactClaim(
            "target-bits-values",
            "`target_bits` must be either `32` or `64`.",
            "artifact-contract-target-bits",
            "32|64",
            actual_target_bits_values,
        ),
        ArtifactClaim(
            "target-bits-equality",
            "same `target_bits` value across the typed,",
            "artifact-contract-target-bits",
            "typed=mir=safei",
            actual_target_bits_equality,
        ),
        ArtifactClaim(
            "interface-members-field",
            "`interface_members`",
            "artifact-contract-optional-field",
            "present",
            lambda: actual_presence(OUTPUT_CONTRACT_VALIDATOR, "interface_members"),
        ),
        ArtifactClaim(
            "shared-object-field",
            "- `is_shared`",
            "artifact-contract-optional-field",
            "present",
            lambda: actual_presence(OUTPUT_CONTRACT_VALIDATOR, "is_shared"),
        ),
        ArtifactClaim(
            "required-ceiling-field",
            "- `required_ceiling`",
            "artifact-contract-optional-field",
            "present",
            lambda: actual_presence(OUTPUT_CONTRACT_VALIDATOR, "required_ceiling"),
        ),
        ArtifactClaim(
            "generic-formals-field",
            "- `generic_formals`",
            "artifact-contract-optional-field",
            "present",
            lambda: actual_presence(OUTPUT_CONTRACT_VALIDATOR, "generic_formals"),
        ),
        ArtifactClaim(
            "generic-origin-field",
            "- `generic_origin`",
            "artifact-contract-optional-field",
            "present",
            lambda: actual_presence(OUTPUT_CONTRACT_VALIDATOR, "generic_origin"),
        ),
        ArtifactClaim(
            "generic-actual-types-field",
            "- `generic_actual_types`",
            "artifact-contract-optional-field",
            "present",
            lambda: actual_presence(OUTPUT_CONTRACT_VALIDATOR, "generic_actual_types"),
        ),
        ArtifactClaim(
            "template-source-field",
            "- `template_source`",
            "artifact-contract-optional-field",
            "present",
            lambda: actual_presence(OUTPUT_CONTRACT_VALIDATOR, "template_source"),
        ),
    ]


def find_line(path: Path, marker: str) -> tuple[int, str] | None:
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines, start=1):
        if marker in line:
            return index, normalized_text(line)
    return None


def iter_artifact_contract_claims() -> Iterable[Claim]:
    for item in artifact_claims():
        location = find_line(ARTIFACT_CONTRACT_DOC, item.marker)
        if location is None:
            yield Claim(
                category="artifact-contract-shape",
                pattern=item.pattern,
                path=ARTIFACT_CONTRACT_DOC,
                line=0,
                claim_key=item.claim_key,
                claim_text="",
                verification_target=f"{repo_rel(ARTIFACT_CONTRACT_DOC)}:marker.{item.claim_key}",
                doc_value=item.doc_value,
                actual_value="missing",
                alignment_status="missing-target",
            )
            continue
        line, claim_text = location
        actual_value, target = item.actual()
        status = "aligned" if actual_value == item.doc_value else "mismatch"
        if actual_value == "missing":
            status = "missing-target"
        yield Claim(
            category="artifact-contract-shape",
            pattern=item.pattern,
            path=ARTIFACT_CONTRACT_DOC,
            line=line,
            claim_key=item.claim_key,
            claim_text=claim_text,
            verification_target=target,
            doc_value=item.doc_value,
            actual_value=actual_value,
            alignment_status=status,
        )


def ast_schema_frozen_commit() -> str:
    commit = load_json(AST_SCHEMA_PATH).get("frozen_commit")
    if not isinstance(commit, str) or not commit:
        return ""
    return commit


def iter_frozen_commit_claims() -> Iterable[Claim]:
    commit = ast_schema_frozen_commit()
    if not commit:
        return
    short = commit[:7]

    rules_text = TRANSLATION_RULES_DOC.read_text(encoding="utf-8")
    rules_match = re.search(r"\*\*Frozen commit:\*\*\s+`([^`]+)`", rules_text)
    if rules_match is not None:
        line = rules_text[: rules_match.start()].count("\n") + 1
        doc_value = rules_match.group(1)
        yield Claim(
            category="frozen-commit-freshness",
            pattern="frozen-commit-value",
            path=TRANSLATION_RULES_DOC,
            line=line,
            claim_key="translation-rules-frozen-commit",
            claim_text=normalized_text(rules_text.splitlines()[line - 1]),
            verification_target=f"{repo_rel(AST_SCHEMA_PATH)}:frozen_commit",
            doc_value=doc_value,
            actual_value=commit,
            alignment_status=status_for_count(doc_value, commit),
        )

    trace_text = TRACEABILITY_MD.read_text(encoding="utf-8")
    trace_match = re.search(r"\*\*Frozen commit SHA:\*\*\s+`([^`]+)`", trace_text)
    if trace_match is not None:
        line = trace_text[: trace_match.start()].count("\n") + 1
        doc_value = trace_match.group(1)
        yield Claim(
            category="frozen-commit-freshness",
            pattern="frozen-commit-value",
            path=TRACEABILITY_MD,
            line=line,
            claim_key="traceability-md-frozen-commit",
            claim_text=normalized_text(trace_text.splitlines()[line - 1]),
            verification_target=f"{repo_rel(AST_SCHEMA_PATH)}:frozen_commit[:7]",
            doc_value=doc_value,
            actual_value=short,
            alignment_status=status_for_count(doc_value, short),
        )

    with TRACEABILITY_CSV.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        prefixes = {
            str(row.get("clause_id", "")).split("@", 1)[1].split(":", 1)[0]
            for row in reader
            if "@" in str(row.get("clause_id", ""))
        }
    doc_value = ",".join(sorted(prefixes))
    # The v1 traceability matrix uses one frozen schema commit. Multiple
    # prefixes would be a scope change that needs triage rather than silent
    # comparison against a single current schema prefix.
    status = status_for_count(doc_value, short) if len(prefixes) == 1 else "unknown"
    yield Claim(
        category="frozen-commit-freshness",
        pattern="frozen-commit-value",
        path=TRACEABILITY_CSV,
        line=2,
        claim_key="traceability-csv-clause-prefix",
        claim_text="traceability_matrix.csv clause_id frozen-commit prefixes",
        verification_target=f"{repo_rel(AST_SCHEMA_PATH)}:frozen_commit[:7]",
        doc_value=doc_value,
        actual_value=short,
        alignment_status=status,
    )


def existing_classifications() -> dict[str, dict[str, object]]:
    if not BASELINE_PATH.exists():
        return {}
    try:
        payload = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    if not isinstance(payload, dict):
        return {}
    entries = payload.get("entries", [])
    if not isinstance(entries, list):
        return {}
    return {
        str(entry.get("fingerprint")): entry
        for entry in entries
        if isinstance(entry, dict) and entry.get("fingerprint")
    }


def iter_claims() -> Iterable[Claim]:
    yield from iter_ast_reference_claims()
    yield from iter_audit_doc_baseline_claims()
    yield from iter_artifact_contract_claims()
    yield from iter_frozen_commit_claims()


def scan() -> dict[str, object]:
    prior = existing_classifications()
    entries: list[dict[str, object]] = []
    seen_fingerprints: dict[str, Claim] = {}
    for claim in iter_claims():
        if claim.alignment_status not in ALIGNMENT_STATUSES:
            raise ValueError(f"invalid alignment_status {claim.alignment_status!r}")
        fingerprint = fingerprint_for(claim)
        previous = seen_fingerprints.get(fingerprint)
        if previous is not None:
            raise ValueError(
                "duplicate Phase 1I.C fingerprint "
                f"{fingerprint} for {repo_rel(previous.path)}:{previous.line} "
                f"and {repo_rel(claim.path)}:{claim.line}"
            )
        seen_fingerprints[fingerprint] = claim
        prior_entry = prior.get(fingerprint, {})
        entries.append(
            {
                "fingerprint": fingerprint,
                "category": claim.category,
                "pattern": claim.pattern,
                "path": repo_rel(claim.path),
                "line": claim.line,
                "claim_key": claim.claim_key,
                "claim_text": claim.claim_text,
                "verification_target": claim.verification_target,
                "doc_value": claim.doc_value,
                "actual_value": claim.actual_value,
                "alignment_status": claim.alignment_status,
                "classification": prior_entry.get("classification", "candidate"),
                "rationale": prior_entry.get("rationale", ""),
                "follow_up": prior_entry.get("follow_up", ""),
            }
        )
    entries.sort(
        key=lambda item: (
            str(item["category"]),
            str(item["path"]),
            str(item["claim_key"]),
            str(item["verification_target"]),
        )
    )
    return {
        "version": 1,
        "generated_by": "python3 scripts/audit_docs_schema_alignment.py --json",
        "scope": [
            "compiler/translation_rules.md",
            "compiler/ast_schema.json",
            "docs/compiler_pre_pr12_audit.md",
            "docs/artifact_contract.md",
            "docs/traceability_matrix.md",
            "docs/traceability_matrix.csv",
        ],
        "classifications": [
            "candidate",
            "needs-repro",
            "confirmed-defect",
            "accepted-with-rationale",
        ],
        "entries": entries,
    }


def counts_by_category(payload: dict[str, object]) -> dict[str, int]:
    counts = {category: 0 for category in CATEGORIES}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                category = str(entry.get("category", "unclassified"))
                counts[category] = counts.get(category, 0) + 1
    return counts


def counts_by_alignment_status(payload: dict[str, object]) -> dict[str, int]:
    counts = {status: 0 for status in ALIGNMENT_STATUSES}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                status = str(entry.get("alignment_status", "unknown"))
                counts[status] = counts.get(status, 0) + 1
    return counts


def print_summary(
    payload: dict[str, object],
    baseline_entries: dict[str, dict[str, object]] | None = None,
) -> None:
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"[Phase 1I.C] {category}: {count}")
    for status, count in sorted(counts_by_alignment_status(payload).items()):
        print(f"[Phase 1I.C] alignment {status}: {count}")
    entries = payload.get("entries", [])
    if baseline_entries is None:
        baseline_entries = existing_classifications()
    current = {
        str(entry.get("fingerprint"))
        for entry in entries
        if isinstance(entry, dict) and entry.get("fingerprint")
    }
    new_count = len(current - set(baseline_entries))
    missing_count = len(set(baseline_entries) - current)
    print(f"[Phase 1I.C] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1I.C] new outside baseline: {new_count}")
    print(f"[Phase 1I.C] missing from baseline: {missing_count}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1I.C Schema-Vs-Doc Alignment Inventory")
    print()
    print("## Counts")
    print()
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"- `{category}`: {count}")
    print()
    print("## Alignment")
    print()
    for status, count in sorted(counts_by_alignment_status(payload).items()):
        print(f"- `{status}`: {count}")
    print()
    print("## Hits")
    print()
    entries = payload.get("entries", [])
    if not isinstance(entries, list) or not entries:
        print("No hits.")
        return
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        print(
            f"- `{entry.get('category')}` `{entry.get('path')}:{entry.get('line')}` "
            f"`{entry.get('alignment_status')}` `{entry.get('classification')}`"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print structured JSON report")
    parser.add_argument(
        "--summary",
        action="store_true",
        help="print category counts, alignment counts, and baseline drift",
    )
    args = parser.parse_args()

    payload = scan()
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    elif args.summary:
        print_summary(payload)
    else:
        print_markdown(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
