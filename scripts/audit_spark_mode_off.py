#!/usr/bin/env python3
"""Report Phase 1E SPARK_Mode Off island audit hits."""

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
BASELINE_PATH = REPO_ROOT / "audit" / "phase1e_spark_mode_off_baseline.json"
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
    kind: str
    name: str
    regex: re.Pattern[str]


PATTERNS: tuple[Pattern, ...] = (
    Pattern(
        "pragma",
        "spark-mode-off-pragma",
        re.compile(r"SPARK_Mode\s*\(\s*Off\s*\)", re.IGNORECASE),
    ),
    Pattern(
        "aspect",
        "spark-mode-off-aspect",
        re.compile(r"SPARK_Mode\s*=>\s*Off\b", re.IGNORECASE),
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


def normalized_line(line: str) -> str:
    return " ".join(line.strip().split())


def domain_for(path: Path) -> str:
    rel = repo_rel(path)
    if rel.startswith("compiler_impl/src/safe_frontend-ada_emit"):
        return "emitted"
    if rel.startswith("compiler_impl/stdlib/ada/") or rel.startswith("companion/"):
        return "runtime"
    return "other"


def category_for(path: Path, pattern: Pattern) -> str:
    return f"{domain_for(path)}-spark-off-{pattern.kind}"


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
    source_lines: dict[Path, list[tuple[int, str, str]]] = {}

    def sources_for(roots: tuple[Path, ...]) -> list[Path]:
        paths: set[Path] = set()
        for root in roots:
            if root not in root_sources:
                root_sources[root] = tuple(iter_sources(root))
            paths.update(root_sources[root])
        return sorted(paths)

    def lines_for(path: Path) -> list[tuple[int, str, str]]:
        if path not in source_lines:
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except UnicodeDecodeError:
                source_lines[path] = []
            else:
                processed: list[tuple[int, str, str]] = []
                for line_number, raw_line in enumerate(lines, start=1):
                    code_line = strip_comments_keep_strings(raw_line)
                    norm = normalized_line(code_line)
                    if norm:
                        processed.append((line_number, code_line, norm))
                source_lines[path] = processed
        return source_lines[path]

    for pattern in PATTERNS:
        for path in sources_for(SCAN_ROOTS):
            for line_number, code_line, norm in lines_for(path):
                if not pattern.regex.search(code_line):
                    continue
                category = category_for(path, pattern)
                fingerprint = fingerprint_for(category, path, pattern.name, norm)
                prior_entry = prior.get(fingerprint, {})
                entry = entries.setdefault(
                    fingerprint,
                    {
                        "fingerprint": fingerprint,
                        "category": category,
                        "pattern": pattern.name,
                        "path": repo_rel(path),
                        "line": line_number,
                        "line_numbers": [],
                        "first_line_text": norm,
                        "multiplicity": 0,
                        "classification": prior_entry.get("classification", "candidate"),
                        "rationale": prior_entry.get("rationale", ""),
                        "follow_up": prior_entry.get("follow_up", ""),
                    },
                )
                entry["multiplicity"] = int(entry["multiplicity"]) + 1
                line_numbers = entry["line_numbers"]
                assert isinstance(line_numbers, list)
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
        "generated_by": "python3 scripts/audit_spark_mode_off.py --json",
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
    counts = {
        "emitted-spark-off-aspect": 0,
        "emitted-spark-off-pragma": 0,
        "runtime-spark-off-aspect": 0,
        "runtime-spark-off-pragma": 0,
    }
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
        print(f"[Phase 1E] {category}: {counts[category]}")
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
    print(f"[Phase 1E] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1E] new outside baseline: {new_count}")
    print(f"[Phase 1E] missing from baseline: {missing_count}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1E SPARK Mode Off Island Audit Report")
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
