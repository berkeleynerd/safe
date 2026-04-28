#!/usr/bin/env python3
"""Report Phase 1I.A docs-to-fixture path-reference audit hits."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
BASELINE_PATH = REPO_ROOT / "audit" / "phase1i_docs_fixture_drift_baseline.json"
CATEGORIES = (
    "emitted-matrix-path-reference",
    "prose-path-reference",
    "traceability-matrix-path-reference",
)
PATTERNS = (
    "diagnostic-golden-path",
    "golden-directory-path",
    "json-fixture-path",
    "safe-fixture-path",
)
TARGET_STATUSES = ("present", "missing")

PATH_REFERENCE_RE = re.compile(
    r"(?<![A-Za-z0-9_./-])("
    r"(?:\.{1,2}/)*(?:tests|samples)/(?:[^\s`\"()\],;]+/)*"
    r"[^\s`\"()\],;]+\.(?:safe|txt|json)"
    r"|(?:\.{1,2}/)*compiler_impl/tests/(?:[^\s`\"()\],;]+/)*"
    r"[^\s`\"()\],;]+\.json"
    r"|(?:\.{1,2}/)*tests/(?:golden|diagnostics_golden)/(?:[A-Za-z0-9_.-]+/)+"
    r")"
)


@dataclass(frozen=True)
class Reference:
    doc_path: Path
    line: int
    raw_target: str
    target_path: str
    first_line_text: str
    pattern: str
    target_kind: str


def repo_rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def normalized_text(text: str) -> str:
    return " ".join(text.strip().split())


def iter_doc_paths() -> Iterable[Path]:
    paths = [REPO_ROOT / "README.md"]
    docs_root = REPO_ROOT / "docs"
    if docs_root.exists():
        paths.extend(sorted(docs_root.rglob("*.md")))
        paths.extend(sorted(docs_root.rglob("*.csv")))
    for path in sorted(set(paths)):
        if path.exists() and path.is_file():
            yield path


def normalize_target_path(raw_target: str) -> str:
    target = raw_target.strip("<>`'\" ,:;").rstrip(".")
    while True:
        if target.startswith("../"):
            target = target[3:]
            continue
        if target.startswith("./"):
            target = target[2:]
            continue
        return target


def pattern_for(target_path: str) -> str:
    if target_path.endswith("/") and (
        target_path.startswith("tests/golden/")
        or target_path.startswith("tests/diagnostics_golden/")
    ):
        return "golden-directory-path"
    if target_path.endswith(".safe"):
        return "safe-fixture-path"
    if target_path.endswith(".txt"):
        return "diagnostic-golden-path"
    if target_path.endswith(".json"):
        return "json-fixture-path"
    raise ValueError(f"unsupported Phase 1I.A target path pattern: {target_path}")


def target_kind_for(target_path: str) -> str:
    if target_path.startswith("tests/golden/") and target_path.endswith("/"):
        return "golden-directory"
    if target_path.startswith("tests/diagnostics_golden/") and target_path.endswith("/"):
        return "diagnostic-golden-directory"
    if target_path.startswith("tests/golden/") and target_path.endswith(".txt"):
        return "golden-text"
    if target_path.startswith("tests/diagnostics_golden/") and target_path.endswith(".txt"):
        return "diagnostic-golden"
    if target_path.startswith("samples/") and target_path.endswith(".txt"):
        return "sample-text"
    if target_path.startswith("compiler_impl/tests/") and target_path.endswith(".json"):
        return "compiler-test-json"
    if target_path.endswith(".json"):
        return "test-json"
    if target_path.endswith(".safe"):
        if target_path.startswith("samples/"):
            return "safe-sample"
        parts = target_path.split("/")
        if len(parts) >= 3 and parts[0] == "tests":
            return f"safe-{parts[1]}"
        return "safe-fixture"
    return "fixture-directory"


def category_for(doc_path: Path) -> str:
    rel = repo_rel(doc_path)
    if rel == "docs/emitted_output_verification_matrix.md":
        return "emitted-matrix-path-reference"
    if rel == "docs/traceability_matrix.csv":
        return "traceability-matrix-path-reference"
    return "prose-path-reference"


def references_from_line(doc_path: Path, line_number: int, line: str) -> list[Reference]:
    refs: list[Reference] = []
    display_text = normalized_text(line)
    for match in PATH_REFERENCE_RE.finditer(line):
        raw_target = match.group(1)
        target_path = normalize_target_path(raw_target)
        if "*" in target_path:
            continue
        try:
            pattern = pattern_for(target_path)
        except ValueError as exc:
            raise ValueError(f"{repo_rel(doc_path)}:{line_number}: {exc}") from exc
        refs.append(
            Reference(
                doc_path=doc_path,
                line=line_number,
                raw_target=raw_target,
                target_path=target_path,
                first_line_text=display_text,
                pattern=pattern,
                target_kind=target_kind_for(target_path),
            )
        )
    return refs


def iter_references() -> Iterable[Reference]:
    for doc_path in iter_doc_paths():
        try:
            lines = doc_path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(lines, start=1):
            yield from references_from_line(doc_path, line_number, line)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_directory(path: Path) -> str:
    digest = hashlib.sha256()
    for root, dirs, files in os.walk(path, followlinks=False):
        root_path = Path(root)
        dirs[:] = sorted(name for name in dirs if not (root_path / name).is_symlink())
        for name in sorted(files):
            child = root_path / name
            if child.is_symlink() or not child.is_file():
                continue
            rel = child.relative_to(path).as_posix()
            digest.update(rel.encode("utf-8"))
            digest.update(b"\0")
            digest.update(sha256_file(child).encode("ascii"))
            digest.update(b"\0")
    return digest.hexdigest()


def target_metadata(target_path: str) -> tuple[str, str]:
    repo_root = REPO_ROOT.resolve()
    path = (REPO_ROOT / target_path).resolve()
    # Documentation text controls target_path; escaped paths are inventory misses.
    try:
        path.relative_to(repo_root)
    except ValueError:
        return "missing", ""
    if not path.exists():
        return "missing", ""
    if path.is_dir():
        return "present", sha256_directory(path)
    return "present", sha256_file(path)


def fingerprint_for(
    *,
    category: str,
    doc_path: Path,
    target_path: str,
    pattern: str,
) -> str:
    seed = f"{category}\0{repo_rel(doc_path)}\0{target_path}\0{pattern}"
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]


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


def scan() -> dict[str, object]:
    prior = existing_classifications()
    entries: dict[str, dict[str, object]] = {}
    target_metadata_cache: dict[str, tuple[str, str]] = {}
    for ref in iter_references():
        category = category_for(ref.doc_path)
        metadata = target_metadata_cache.get(ref.target_path)
        if metadata is None:
            metadata = target_metadata(ref.target_path)
            target_metadata_cache[ref.target_path] = metadata
        target_status, target_digest = metadata
        fingerprint = fingerprint_for(
            category=category,
            doc_path=ref.doc_path,
            target_path=ref.target_path,
            pattern=ref.pattern,
        )
        prior_entry = prior.get(fingerprint, {})
        entry = entries.setdefault(
            fingerprint,
            {
                "fingerprint": fingerprint,
                "category": category,
                "pattern": ref.pattern,
                "path": repo_rel(ref.doc_path),
                "line": ref.line,
                "line_numbers": [],
                "first_line_text": ref.first_line_text,
                "target_path": ref.target_path,
                "target_kind": ref.target_kind,
                "target_status": target_status,
                "target_digest": target_digest,
                "multiplicity": 0,
                "classification": prior_entry.get("classification", "candidate"),
                "rationale": prior_entry.get("rationale", ""),
                "follow_up": prior_entry.get("follow_up", ""),
            },
        )
        entry["multiplicity"] = int(entry["multiplicity"]) + 1
        line_numbers = entry["line_numbers"]
        if not isinstance(line_numbers, list):
            raise TypeError(f"line_numbers must be a list for fingerprint {fingerprint}")
        if ref.line not in line_numbers:
            line_numbers.append(ref.line)

    sorted_entries = sorted(
        entries.values(),
        key=lambda item: (
            str(item["category"]),
            str(item["path"]),
            str(item["target_path"]),
            int(item["line"]),
            str(item["pattern"]),
        ),
    )
    return {
        "version": 1,
        "generated_by": "python3 scripts/audit_docs_fixture_drift.py --json",
        "scope": ["README.md", "docs/**/*.md", "docs/**/*.csv"],
        "classifications": [
            "candidate",
            "needs-repro",
            "confirmed-defect",
            "accepted-with-rationale",
        ],
        "entries": sorted_entries,
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


def counts_by_target_status(payload: dict[str, object]) -> dict[str, int]:
    counts = {status: 0 for status in TARGET_STATUSES}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                status = str(entry.get("target_status", "unknown"))
                counts[status] = counts.get(status, 0) + 1
    return counts


def print_summary(
    payload: dict[str, object],
    baseline_entries: dict[str, dict[str, object]] | None = None,
) -> None:
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"[Phase 1I.A] {category}: {count}")
    for status, count in sorted(counts_by_target_status(payload).items()):
        print(f"[Phase 1I.A] target {status}: {count}")
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
    print(f"[Phase 1I.A] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1I.A] new outside baseline: {new_count}")
    print(f"[Phase 1I.A] missing from baseline: {missing_count}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1I.A Docs And Fixture Drift Inventory")
    print()
    print("## Counts")
    print()
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"- `{category}`: {count}")
    print()
    print("## Target Status")
    print()
    for status, count in sorted(counts_by_target_status(payload).items()):
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
            f"`{entry.get('target_path')}` `{entry.get('classification')}`"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print structured JSON report")
    parser.add_argument(
        "--summary",
        action="store_true",
        help="print category counts, target status counts, and baseline drift",
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
