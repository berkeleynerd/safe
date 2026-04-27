#!/usr/bin/env python3
"""Report Phase 1D GNATprove trust-boundary audit hits."""

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
SCAN_ROOTS = (
    REPO_ROOT / "compiler_impl" / "src",
    REPO_ROOT / "compiler_impl" / "stdlib" / "ada",
    REPO_ROOT / "companion",
)
BASELINE_PATH = REPO_ROOT / "audit" / "phase1d_gnatprove_trust_baseline.json"
SKIPPED_SOURCE_DIRS = {
    ".git",
    ".safe-build",
    "__pycache__",
    "alire",
    "bin",
    "gnatprove",
    "obj",
    "release",
}


@dataclass(frozen=True)
class Pattern:
    category: str
    name: str
    regex: re.Pattern[str]
    roots: tuple[Path, ...] = SCAN_ROOTS
    statement: bool = False


PATTERNS: tuple[Pattern, ...] = (
    Pattern(
        "assume-pragma",
        "pragma-assume",
        re.compile(r"pragma\s+Assume\s*\(", re.IGNORECASE),
        statement=True,
    ),
    Pattern(
        "gnatprove-annotate",
        "gnatprove-annotate",
        re.compile(r"pragma\s+Annotate\s*\(", re.IGNORECASE),
        statement=True,
    ),
    Pattern(
        "gnatprove-warning-suppression",
        "gnatprove-warning-off",
        re.compile(
            r"pragma\s+Warnings\s*\(\s*GNATprove\s*,\s*Off\b",
            re.IGNORECASE,
        ),
        statement=True,
    ),
    Pattern(
        "skip-proof-marker",
        "skip-proof-or-false-positive",
        re.compile(r"\bSkip_Proof\b|\bFalse_Positive\b", re.IGNORECASE),
    ),
)


def repo_rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def iter_sources(root: Path) -> Iterable[Path]:
    if not root.exists():
        return
    if root.is_file():
        if root.suffix.lower() in {".adb", ".ads"}:
            yield root
        return
    if not root.is_dir():
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(name for name in dirnames if name not in SKIPPED_SOURCE_DIRS)
        for filename in sorted(filenames):
            path = Path(dirpath) / filename
            if path.suffix.lower() in {".adb", ".ads"}:
                yield path


def strip_comments_keep_strings(line: str) -> str:
    """Return a line without Ada comments, preserving string literal contents."""

    result: list[str] = []
    in_string = False
    index = 0
    while index < len(line):
        char = line[index]
        nxt = line[index + 1] if index + 1 < len(line) else ""
        if not in_string and char == "-" and nxt == "-":
            break
        result.append(char)
        if char == '"':
            if in_string and nxt == '"':
                result.append(nxt)
                index += 2
                continue
            in_string = not in_string
        index += 1
    return "".join(result)


def normalized_text(text: str) -> str:
    return " ".join(text.strip().split())


def first_line_text(text: str) -> str:
    for line in text.splitlines():
        normalized = normalized_text(line)
        if normalized:
            return normalized
    return ""


def statement_end(text: str, start: int) -> int | None:
    """Return the offset after a statement semicolon, ignoring string content."""

    in_string = False
    index = start
    while index < len(text):
        char = text[index]
        nxt = text[index + 1] if index + 1 < len(text) else ""
        if char == '"':
            if in_string and nxt == '"':
                index += 2
                continue
            in_string = not in_string
        elif char == ";" and not in_string:
            return index + 1
        index += 1
    return None


def line_starts(text: str) -> list[int]:
    starts = [0]
    for match in re.finditer(r"\n", text):
        starts.append(match.end())
    return starts


def line_number_for(offset: int, starts: list[int]) -> int:
    low = 0
    high = len(starts)
    while low < high:
        mid = (low + high) // 2
        if starts[mid] <= offset:
            low = mid + 1
        else:
            high = mid
    return low


def fingerprint_for(category: str, path: Path, pattern_name: str, normalized: str) -> str:
    seed = f"{category}\0{repo_rel(path)}\0{pattern_name}\0{normalized}"
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
    root_sources: dict[Path, tuple[Path, ...]] = {}
    source_text: dict[Path, tuple[str, list[int]]] = {}

    def sources_for(roots: tuple[Path, ...]) -> list[Path]:
        paths: set[Path] = set()
        for root in roots:
            if root not in root_sources:
                root_sources[root] = tuple(iter_sources(root))
            paths.update(root_sources[root])
        return sorted(paths)

    def text_for(path: Path) -> tuple[str, list[int]]:
        if path not in source_text:
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except UnicodeDecodeError:
                source_text[path] = ("", [0])
            else:
                stripped = "\n".join(strip_comments_keep_strings(line) for line in lines)
                source_text[path] = (stripped, line_starts(stripped))
        return source_text[path]

    for pattern in PATTERNS:
        for path in sources_for(pattern.roots):
            text, starts = text_for(path)
            for match in pattern.regex.finditer(text):
                if pattern.statement:
                    end = statement_end(text, match.start())
                    if end is None:
                        continue
                    matched_text = text[match.start() : end]
                    match_end = end
                    if (
                        pattern.category == "gnatprove-annotate"
                        and not re.search(r"\bGNATprove\b", matched_text, re.IGNORECASE)
                    ):
                        continue
                else:
                    matched_text = match.group(0)
                    match_end = match.end()
                normalized = normalized_text(matched_text)
                if not normalized:
                    continue
                first_line = line_number_for(match.start(), starts)
                last_line = line_number_for(match_end, starts)
                fingerprint = fingerprint_for(pattern.category, path, pattern.name, normalized)
                prior_entry = prior.get(fingerprint, {})
                entry = entries.setdefault(
                    fingerprint,
                    {
                        "fingerprint": fingerprint,
                        "category": pattern.category,
                        "pattern": pattern.name,
                        "path": repo_rel(path),
                        "line": first_line,
                        "line_numbers": [],
                        "first_line_text": first_line_text(matched_text),
                        "line_text": normalized,
                        "multiplicity": 0,
                        "classification": prior_entry.get("classification", "candidate"),
                        "rationale": prior_entry.get("rationale", ""),
                        "follow_up": prior_entry.get("follow_up", ""),
                    },
                )
                entry["multiplicity"] = int(entry["multiplicity"]) + 1
                line_numbers = entry["line_numbers"]
                assert isinstance(line_numbers, list)
                for line_number in range(first_line, last_line + 1):
                    if line_number not in line_numbers:
                        line_numbers.append(line_number)

    sorted_entries = sorted(
        entries.values(),
        key=lambda item: (
            str(item["category"]),
            str(item["path"]),
            int(item["line"]),
            str(item["pattern"]),
        ),
    )
    return {
        "version": 1,
        "generated_by": "python3 scripts/audit_gnatprove_trust.py --json",
        "scope": [repo_rel(path) for path in SCAN_ROOTS],
        "classifications": [
            "candidate",
            "needs-repro",
            "confirmed-defect",
            "accepted-with-rationale",
        ],
        "entries": sorted_entries,
    }


def counts_by_category(payload: dict[str, object]) -> dict[str, int]:
    counts = {pattern.category: 0 for pattern in PATTERNS}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                category = str(entry.get("category", "unclassified"))
                counts[category] = counts.get(category, 0) + 1
    return counts


def print_summary(
    payload: dict[str, object],
    baseline_entries: dict[str, dict[str, object]] | None = None,
) -> None:
    """Print live counts against the provided or on-disk baseline entries."""

    counts = counts_by_category(payload)
    for category in sorted(counts):
        print(f"[Phase 1D] {category}: {counts[category]}")
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
    print(f"[Phase 1D] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1D] new outside baseline: {new_count}")
    print(f"[Phase 1D] missing from baseline: {missing_count}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1D GNATprove Trust Boundary Audit Report")
    print()
    print("## Counts")
    print()
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"- `{category}`: {count}")
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
            f"`{entry.get('pattern')}` `{entry.get('classification')}`"
        )
        print(f"  - {entry.get('first_line_text')}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print structured JSON report")
    parser.add_argument("--summary", action="store_true", help="print category counts only")
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
