#!/usr/bin/env python3
"""Report Phase 1I.B docs code-snippet drift audit hits."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
BASELINE_PATH = REPO_ROOT / "audit" / "phase1i_code_snippet_drift_baseline.json"
CATEGORIES = (
    "current-ada-snippet",
    "current-prose-or-data-snippet",
    "current-safe-snippet",
    "current-shell-snippet",
    "historical-proposal-snippet",
)
PATTERNS = ("fenced-code-block",)
SHELL_LANGUAGES = {"bash", "sh", "shell"}
NO_LANGUAGE = "<none>"
OPENING_FENCE_RE = re.compile(r"^ {0,3}(`{3,})(.*)$")
CLOSING_FENCE_RE = re.compile(r"^ {0,3}(`{3,})\s*$")


@dataclass(frozen=True)
class Snippet:
    doc_path: Path
    block_index: int
    start_line: int
    end_line: int
    language: str
    body_lines: tuple[str, ...]


def repo_rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def normalized_text(text: str) -> str:
    return " ".join(text.strip().split())


def iter_doc_paths() -> Iterable[Path]:
    roots = [REPO_ROOT / "README.md", REPO_ROOT / "CLAUDE.md"]
    for root in roots:
        if root.exists() and root.is_file():
            yield root
    for root in (REPO_ROOT / "docs", REPO_ROOT / "spec"):
        if root.exists():
            yield from sorted(
                path
                for path in root.rglob("*.md")
                if path.is_file() and not repo_rel(path).startswith("docs/archive/")
            )


def language_from_fence(line: str) -> str:
    match = OPENING_FENCE_RE.match(line)
    if match is None:
        return NO_LANGUAGE
    info = match.group(2).strip()
    if not info:
        return NO_LANGUAGE
    return info.split()[0].lower()


def is_closing_fence(line: str, opening_fence_length: int) -> bool:
    match = CLOSING_FENCE_RE.match(line)
    return match is not None and len(match.group(1)) >= opening_fence_length


def snippets_from_lines(doc_path: Path, lines: list[str]) -> Iterable[Snippet]:
    in_block = False
    start_line = 0
    language = NO_LANGUAGE
    opening_fence_length = 0
    body_lines: list[str] = []
    block_index = 0
    for line_number, line in enumerate(lines, start=1):
        opening = OPENING_FENCE_RE.match(line)
        if not in_block and opening is not None:
            in_block = True
            start_line = line_number
            language = language_from_fence(line)
            opening_fence_length = len(opening.group(1))
            body_lines = []
            continue
        if in_block and is_closing_fence(line, opening_fence_length):
            block_index += 1
            yield Snippet(
                doc_path=doc_path,
                block_index=block_index,
                start_line=start_line,
                end_line=line_number,
                language=language,
                body_lines=tuple(body_lines),
            )
            in_block = False
            start_line = 0
            language = NO_LANGUAGE
            opening_fence_length = 0
            body_lines = []
            continue
        if in_block:
            body_lines.append(line)
    if in_block:
        raise ValueError(f"{repo_rel(doc_path)}:{start_line}: unterminated fenced code block")


def iter_snippets_for_doc(doc_path: Path) -> Iterable[Snippet]:
    try:
        lines = doc_path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return
    yield from snippets_from_lines(doc_path, lines)


def iter_snippets() -> Iterable[Snippet]:
    for doc_path in iter_doc_paths():
        yield from iter_snippets_for_doc(doc_path)


def category_for(snippet: Snippet) -> str:
    rel = repo_rel(snippet.doc_path)
    if rel == "docs/syntax_proposals.md":
        return "historical-proposal-snippet"
    if snippet.language == "safe":
        return "current-safe-snippet"
    if snippet.language == "ada":
        return "current-ada-snippet"
    if snippet.language in SHELL_LANGUAGES:
        return "current-shell-snippet"
    return "current-prose-or-data-snippet"


def first_line_text(snippet: Snippet) -> str:
    for line in snippet.body_lines:
        text = normalized_text(line)
        if text:
            return text
    return normalized_text(f"```{'' if snippet.language == NO_LANGUAGE else snippet.language}")


def snippet_digest(snippet: Snippet) -> str:
    body = "\n".join(snippet.body_lines) + "\n"
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def fingerprint_for(
    *,
    category: str,
    doc_path: Path,
    block_index: int,
    language: str,
) -> str:
    seed = f"{category}\0{repo_rel(doc_path)}\0{block_index}\0{language}"
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
    entries: list[dict[str, object]] = []
    for snippet in iter_snippets():
        category = category_for(snippet)
        fingerprint = fingerprint_for(
            category=category,
            doc_path=snippet.doc_path,
            block_index=snippet.block_index,
            language=snippet.language,
        )
        prior_entry = prior.get(fingerprint, {})
        entries.append(
            {
                "fingerprint": fingerprint,
                "category": category,
                "pattern": "fenced-code-block",
                "path": repo_rel(snippet.doc_path),
                "block_index": snippet.block_index,
                "start_line": snippet.start_line,
                "end_line": snippet.end_line,
                "language": snippet.language,
                "first_line_text": first_line_text(snippet),
                "snippet_line_count": len(snippet.body_lines),
                "snippet_digest": snippet_digest(snippet),
                "classification": prior_entry.get("classification", "candidate"),
                "rationale": prior_entry.get("rationale", ""),
                "follow_up": prior_entry.get("follow_up", ""),
            }
        )
    entries.sort(
        key=lambda item: (
            str(item["category"]),
            str(item["path"]),
            int(item["block_index"]),
            str(item["language"]),
        )
    )
    return {
        "version": 1,
        "generated_by": "python3 scripts/audit_docs_code_snippet_drift.py --json",
        "scope": ["README.md", "CLAUDE.md", "docs/**/*.md", "spec/**/*.md"],
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


def counts_by_language(payload: dict[str, object]) -> dict[str, int]:
    counts: dict[str, int] = {}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                language = str(entry.get("language", NO_LANGUAGE))
                counts[language] = counts.get(language, 0) + 1
    return counts


def print_summary(
    payload: dict[str, object],
    baseline_entries: dict[str, dict[str, object]] | None = None,
) -> None:
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"[Phase 1I.B] {category}: {count}")
    for language, count in sorted(counts_by_language(payload).items()):
        print(f"[Phase 1I.B] language {language}: {count}")
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
    print(f"[Phase 1I.B] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1I.B] new outside baseline: {new_count}")
    print(f"[Phase 1I.B] missing from baseline: {missing_count}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1I.B Code Snippet Drift Inventory")
    print()
    print("## Counts")
    print()
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"- `{category}`: {count}")
    print()
    print("## Languages")
    print()
    for language, count in sorted(counts_by_language(payload).items()):
        print(f"- `{language}`: {count}")
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
            f"- `{entry.get('category')}` `{entry.get('path')}:{entry.get('start_line')}` "
            f"`{entry.get('language')}` `{entry.get('classification')}`"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print structured JSON report")
    parser.add_argument(
        "--summary",
        action="store_true",
        help="print category counts, language counts, and baseline drift",
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
