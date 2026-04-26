#!/usr/bin/env python3
"""Report Phase 1C wide-integer arithmetic audit hits."""

from __future__ import annotations

import argparse
import hashlib
import json
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
BASELINE_PATH = REPO_ROOT / "audit" / "phase1c_arithmetic_baseline.json"


@dataclass(frozen=True)
class Pattern:
    category: str
    name: str
    regex: re.Pattern[str]
    roots: tuple[Path, ...] = SCAN_ROOTS


PATTERNS: tuple[Pattern, ...] = (
    Pattern(
        "model-domain",
        "wide-domain-definition",
        re.compile(
            r"INT64_(LOW|HIGH)|subtype\s+Wide_Integer\s+is|"
            r"Wide_Integer\s*(is\s+range|is\s+new|:=)|"
            r"Wide_Integer_Limits|Long_Long_Long_Integer",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "target-bits",
        "target-bits-propagation",
        re.compile(
            r"--target-bits|Target_Bits|target_bits|Integer_Type\s*\(|"
            r"Is_Valid_Target_Bits",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "host-wide-arithmetic",
        "host-wide-expression",
        re.compile(
            r"Wide_Integer\s*[\+\-\*/]|[\+\-\*/]\s*Wide_Integer|"
            r"abs\s+\w*Wide|Long_Long_Long_Integer\s*[\+\-\*/]|"
            r"\.\.\s*Wide_Integer",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "overflow-check-path",
        "mir-overflow-analysis",
        re.compile(
            r"Overflow_Checked|intermediate_overflow|Division_Interval|"
            r"Eval_Int_Expr|Interval_Contains|INT64_(LOW|HIGH)",
            re.IGNORECASE,
        ),
        roots=(REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-mir_analyze.adb",),
    ),
    Pattern(
        "emitted-wide",
        "emitted-wide-image",
        re.compile(
            r"Safe_Runtime\.Wide_Integer|Trim_Wide_Image|To_Wide_Integer|"
            r"From_Wide_Integer",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "stdlib-length",
        "stdlib-length-wide",
        re.compile(r"Long_Long_Integer|Long_Long_Long_Integer", re.IGNORECASE),
        roots=(REPO_ROOT / "compiler_impl" / "stdlib" / "ada",),
    ),
)


def repo_rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def iter_sources(root: Path) -> Iterable[Path]:
    if root.is_file():
        if root.suffix.lower() in {".adb", ".ads"}:
            yield root
        return
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in {".adb", ".ads"}:
            yield path


def source_paths() -> list[Path]:
    paths: set[Path] = set()
    for root in SCAN_ROOTS:
        paths.update(iter_sources(root))
    return sorted(paths)


def strip_comment_and_find_strings(line: str) -> tuple[str, set[int]]:
    """Return a line without Ada comments plus offsets inside same-line strings."""

    result: list[str] = []
    string_offsets: set[int] = set()
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
                string_offsets.add(index)
                string_offsets.add(index + 1)
                result.append(nxt)
                index += 2
                continue
            in_string = not in_string
            string_offsets.add(index)
        elif in_string:
            string_offsets.add(index)
        index += 1
    return "".join(result), string_offsets


def normalized_line(line: str) -> str:
    return " ".join(line.strip().split())


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
    for pattern in PATTERNS:
        pattern_paths: set[Path] = set()
        for root in pattern.roots:
            pattern_paths.update(iter_sources(root))
        for path in sorted(pattern_paths):
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except UnicodeDecodeError:
                continue
            for line_number, raw_line in enumerate(lines, start=1):
                code_line, string_offsets = strip_comment_and_find_strings(raw_line)
                for match in pattern.regex.finditer(code_line):
                    if match.start() in string_offsets:
                        continue
                    norm = normalized_line(code_line)
                    if not norm:
                        continue
                    fingerprint = fingerprint_for(pattern.category, path, pattern.name, norm)
                    prior_entry = prior.get(fingerprint, {})
                    entry = entries.setdefault(
                        fingerprint,
                        {
                            "fingerprint": fingerprint,
                            "category": pattern.category,
                            "pattern": pattern.name,
                            "path": repo_rel(path),
                            "line": line_number,
                            "line_numbers": [],
                            "line_text": norm,
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
        "generated_by": "python3 scripts/audit_arithmetic.py --json",
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


def print_summary(payload: dict[str, object]) -> None:
    counts = counts_by_category(payload)
    for category in sorted(counts):
        print(f"[Phase 1C] {category}: {counts[category]}")
    entries = payload.get("entries", [])
    baseline_entries = existing_classifications()
    current = {
        str(entry.get("fingerprint"))
        for entry in entries
        if isinstance(entry, dict) and entry.get("fingerprint")
    }
    new_count = len(current - set(baseline_entries))
    missing_count = len(set(baseline_entries) - current)
    print(f"[Phase 1C] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1C] new outside baseline: {new_count}")
    print(f"[Phase 1C] missing from baseline: {missing_count}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1C Arithmetic Audit Report")
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
        print(f"  - {entry.get('line_text')}")


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
