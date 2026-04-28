#!/usr/bin/env python3
"""Report Phase 1F dead-code-after-unconditional-raise audit hits."""

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
BASELINE_PATH = REPO_ROOT / "audit" / "phase1f_dead_raise_baseline.json"
CATEGORIES = (
    "direct-raise-fallthrough",
    "no-return-helper-fallthrough",
)
PATTERNS = (
    "direct-raise-statement",
    "direct-raise-nested-block",
    "no-return-helper-statement",
    "no-return-helper-nested-block",
)
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
class Statement:
    start_line: int
    end_line: int
    code_text: str
    display_text: str
    first_line_text: str


@dataclass(frozen=True)
class NoReturnTrigger:
    category: str
    pattern: str


def repo_rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def iter_sources(root: Path, *, suffixes: set[str]) -> Iterable[Path]:
    if not root.exists():
        return
    if root.is_file():
        if root.suffix.lower() in suffixes:
            yield root
        return
    if not root.is_dir():
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(name for name in dirnames if name not in SKIPPED_SOURCE_DIRS)
        for filename in sorted(filenames):
            path = Path(dirpath) / filename
            if path.suffix.lower() in suffixes:
                yield path


def read_utf8_text_or_none(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None


def iter_source_texts(*, suffixes: set[str]) -> Iterable[tuple[Path, str]]:
    for root in SCAN_ROOTS:
        for path in iter_sources(root, suffixes=suffixes):
            text = read_utf8_text_or_none(path)
            if text is not None:
                yield path, text


def strip_comments_keep_strings(line: str) -> str:
    """Return an Ada line without comments, preserving string contents."""

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


def strip_comments_and_strings(line: str) -> str:
    """Return an Ada line without comments or string-literal contents."""

    result: list[str] = []
    in_string = False
    index = 0
    while index < len(line):
        char = line[index]
        nxt = line[index + 1] if index + 1 < len(line) else ""
        if not in_string and char == "-" and nxt == "-":
            break
        if char == '"':
            result.append('"')
            if in_string and nxt == '"':
                index += 2
                continue
            in_string = not in_string
        elif in_string:
            result.append(" ")
        else:
            result.append(char)
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


def has_statement_semicolon(line: str) -> bool:
    return ";" in line


def starts_with_keyword(text: str, keyword: str) -> bool:
    return text == keyword or text.startswith((f"{keyword} ", f"{keyword};"))


def is_statement_header(line: str) -> bool:
    text = normalized_text(line).lower()
    return (
        text in {"begin", "declare", "else"}
        or text.endswith(" is")
        or text.endswith("=>")
        or starts_with_keyword(text, "loop")
        or text.startswith(
            (
                "case ",
                "elsif ",
                "for ",
                "function ",
                "if ",
                "package ",
                "procedure ",
                "type ",
                "subtype ",
                "when ",
                "while ",
            )
        )
    )


def starts_multiline_statement(line: str) -> bool:
    text = normalized_text(line)
    return bool(
        re.match(r"^(raise|return)\b", text, re.IGNORECASE)
        or re.match(r"^[A-Za-z][A-Za-z0-9_]*\s*(?:\(|:=)", text)
        or re.match(r"^[A-Za-z][A-Za-z0-9_]*$", text)
    )


def iter_statements(lines: list[str]) -> Iterable[Statement]:
    start_line: int | None = None
    code_parts: list[str] = []
    display_parts: list[str] = []
    for line_number, raw_line in enumerate(lines, start=1):
        code_line = strip_comments_and_strings(raw_line)
        display_line = strip_comments_keep_strings(raw_line)
        if start_line is None and not normalized_text(code_line):
            continue
        if start_line is None and not has_statement_semicolon(code_line):
            if is_statement_header(code_line) or not starts_multiline_statement(code_line):
                code_text = normalized_text(code_line)
                display_text = normalized_text(display_line)
                if code_text:
                    yield Statement(
                        start_line=line_number,
                        end_line=line_number,
                        code_text=code_text,
                        display_text=display_text,
                        first_line_text=display_text,
                    )
                continue
        if start_line is None:
            start_line = line_number
        code_parts.append(code_line)
        display_parts.append(display_line)
        if has_statement_semicolon(code_line):
            code_text = normalized_text("\n".join(code_parts))
            display_text = normalized_text("\n".join(display_parts))
            if code_text:
                yield Statement(
                    start_line=start_line,
                    end_line=line_number,
                    code_text=code_text,
                    display_text=display_text,
                    first_line_text=first_line_text("\n".join(display_parts)),
                )
            start_line = None
            code_parts = []
            display_parts = []


NO_RETURN_PRAGMA_RE = re.compile(
    r"\bpragma\s+No_Return\s*\(([^)]*)\)",
    re.IGNORECASE,
)
IDENTIFIER_RE = re.compile(r"\b[A-Za-z][A-Za-z0-9_]*\b")


def no_return_names_from_line(raw_line: str) -> set[str]:
    line = strip_comments_and_strings(raw_line)
    names: set[str] = set()
    for match in NO_RETURN_PRAGMA_RE.finditer(line):
        names.update(IDENTIFIER_RE.findall(match.group(1)))
    return names


def collect_no_return_names_from_sources(sources: Iterable[tuple[Path, str]]) -> set[str]:
    names: set[str] = set()
    for _path, text in sources:
        for raw_line in text.splitlines():
            names.update(no_return_names_from_line(raw_line))
    return names


def collect_no_return_names() -> set[str]:
    return collect_no_return_names_from_sources(iter_source_texts(suffixes={".adb", ".ads"}))


def no_return_patterns(no_return_names: set[str]) -> tuple[re.Pattern[str], ...]:
    return tuple(
        re.compile(
            r"^" + re.escape(name) + r"\b\s*(?:\(|;)",
            re.IGNORECASE,
        )
        for name in sorted(no_return_names)
    )


def no_return_trigger(
    statement: Statement,
    no_return_name_patterns: tuple[re.Pattern[str], ...],
    *,
    nested_block: bool = False,
) -> NoReturnTrigger | None:
    text = re.sub(
        r"^when\b.*?=>\s*",
        "",
        statement.code_text,
        count=1,
        flags=re.IGNORECASE,
    )
    if re.match(r"^raise\b", text, re.IGNORECASE):
        return NoReturnTrigger(
            category="direct-raise-fallthrough",
            pattern="direct-raise-nested-block" if nested_block else "direct-raise-statement",
        )
    for name_re in no_return_name_patterns:
        if name_re.match(text):
            return NoReturnTrigger(
                category="no-return-helper-fallthrough",
                pattern=(
                    "no-return-helper-nested-block"
                    if nested_block
                    else "no-return-helper-statement"
                ),
            )
    return None


def is_delimiter(statement: Statement) -> bool:
    text = statement.code_text.lower()
    return text.startswith(
        (
            "and ",
            "case ",
            "elsif ",
            "for ",
            "function ",
            "if ",
            "or ",
            "package ",
            "procedure ",
            "type ",
            "subtype ",
            "when ",
            "while ",
        )
    ) or any(
        starts_with_keyword(text, keyword)
        for keyword in ("begin", "declare", "else", "end", "exception", "loop")
    )


def is_executable_fallthrough(statement: Statement) -> bool:
    return not is_delimiter(statement)


def simple_nested_block_is_no_return(
    statements: list[Statement],
    no_return_index: int,
    end_index: int,
    no_return_name_patterns: tuple[re.Pattern[str], ...],
) -> NoReturnTrigger | None:
    end_text = statements[end_index].code_text.lower()
    if not re.fullmatch(r"end\s*;", end_text):
        return None
    # This inventory heuristic intentionally covers anonymous nested blocks only.
    # Named blocks such as "Label : begin ... end Label;" are left for triage if
    # they ever appear in the Phase 1F surface.
    block_start = None
    for index in range(no_return_index - 1, -1, -1):
        if statements[index].code_text.lower() == "begin":
            block_start = index
            break
    if block_start is None:
        return None
    trigger = no_return_trigger(
        statements[no_return_index],
        no_return_name_patterns,
        nested_block=True,
    )
    if trigger is None:
        return None
    block_body = statements[block_start + 1 : end_index]
    if any(statement.code_text.lower().startswith("exception") for statement in block_body):
        return None

    branch_depth = 0
    for statement in block_body:
        text = statement.code_text.lower()
        if statement is statements[no_return_index]:
            return None if branch_depth else trigger
        if any(
            starts_with_keyword(text, keyword)
            for keyword in ("if", "case", "for", "while", "loop")
        ):
            branch_depth += 1
        elif text.startswith(("end if", "end case", "end loop")) and branch_depth:
            branch_depth -= 1
    return None


def fingerprint_for(
    category: str,
    path: Path,
    pattern_name: str,
    line_fingerprint_text: str,
    fallthrough_fingerprint_text: str,
) -> str:
    seed = (
        f"{category}\0{repo_rel(path)}\0{pattern_name}\0"
        f"{normalized_text(line_fingerprint_text)}\0"
        f"{normalized_text(fallthrough_fingerprint_text)}"
    )
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


def record_entry(
    entries: dict[str, dict[str, object]],
    *,
    path: Path,
    trigger: NoReturnTrigger,
    raise_statement: Statement,
    fallthrough_statement: Statement,
    prior: dict[str, dict[str, object]],
) -> None:
    fingerprint = fingerprint_for(
        trigger.category,
        path,
        trigger.pattern,
        raise_statement.code_text,
        fallthrough_statement.code_text,
    )
    prior_entry = prior.get(fingerprint, {})
    entry = entries.setdefault(
        fingerprint,
        {
            "fingerprint": fingerprint,
            "category": trigger.category,
            "pattern": trigger.pattern,
            "path": repo_rel(path),
            "line": raise_statement.start_line,
            "line_numbers": [],
            "first_line_text": raise_statement.first_line_text,
            "line_text": raise_statement.display_text,
            "fallthrough_line": fallthrough_statement.display_text,
            "fallthrough_line_number": fallthrough_statement.start_line,
            "multiplicity": 0,
            "classification": prior_entry.get("classification", "candidate"),
            "rationale": prior_entry.get("rationale", ""),
            "follow_up": prior_entry.get(
                "follow_up",
                "Phase 1F resolver fallback cleanup PR",
            ),
        },
    )
    entry["multiplicity"] = int(entry["multiplicity"]) + 1
    line_numbers = entry["line_numbers"]
    if not isinstance(line_numbers, list):
        raise TypeError(f"line_numbers must be a list for fingerprint {fingerprint}")
    if raise_statement.start_line not in line_numbers:
        line_numbers.append(raise_statement.start_line)


def scan_source(
    path: Path,
    text: str,
    *,
    no_return_names: set[str] | None = None,
    no_return_name_patterns: tuple[re.Pattern[str], ...] | None = None,
    prior: dict[str, dict[str, object]] | None = None,
) -> dict[str, dict[str, object]]:
    if prior is None:
        prior = {}
    statements = list(iter_statements(text.splitlines()))
    if no_return_name_patterns is None:
        no_return_name_patterns = no_return_patterns(no_return_names or set())
    entries: dict[str, dict[str, object]] = {}
    for index, statement in enumerate(statements):
        trigger = no_return_trigger(statement, no_return_name_patterns)
        if trigger is not None and index + 1 < len(statements):
            fallthrough = statements[index + 1]
            if is_executable_fallthrough(fallthrough):
                record_entry(
                    entries,
                    path=path,
                    trigger=trigger,
                    raise_statement=statement,
                    fallthrough_statement=fallthrough,
                    prior=prior,
                )
            continue

        if (
            statement.code_text.lower().startswith("end")
            and index >= 1
            and index + 1 < len(statements)
        ):
            nested_trigger = simple_nested_block_is_no_return(
                statements,
                index - 1,
                index,
                no_return_name_patterns,
            )
            fallthrough = statements[index + 1]
            if nested_trigger is not None and is_executable_fallthrough(fallthrough):
                record_entry(
                    entries,
                    path=path,
                    trigger=nested_trigger,
                    raise_statement=statements[index - 1],
                    fallthrough_statement=fallthrough,
                    prior=prior,
                )
    return entries


def scan() -> dict[str, object]:
    prior = existing_classifications()
    sources = list(iter_source_texts(suffixes={".adb", ".ads"}))
    no_return_names = collect_no_return_names_from_sources(sources)
    compiled_no_return_patterns = no_return_patterns(no_return_names)
    entries: dict[str, dict[str, object]] = {}
    for path, text in sources:
        if path.suffix.lower() != ".adb":
            continue
        source_entries = scan_source(
            path,
            text,
            no_return_name_patterns=compiled_no_return_patterns,
            prior=prior,
        )
        entries.update(source_entries)

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
        "generated_by": "python3 scripts/audit_dead_raise.py --json",
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
    counts = {category: 0 for category in CATEGORIES}
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
    counts = counts_by_category(payload)
    for category in sorted(counts):
        print(f"[Phase 1F] {category}: {counts[category]}")
    entries = payload.get("entries", [])
    if baseline_entries is None:
        baseline_entries = existing_classifications()
    current = {
        str(entry.get("fingerprint"))
        for entry in entries
        if isinstance(entry, dict) and entry.get("fingerprint")
    }
    print(f"[Phase 1F] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1F] new outside baseline: {len(current - set(baseline_entries))}")
    print(f"[Phase 1F] missing from baseline: {len(set(baseline_entries) - current)}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1F Dead Code After Unconditional Raise Audit Report")
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
        print(f"  - trigger: {entry.get('first_line_text')}")
        print(f"  - fallthrough: {entry.get('fallthrough_line')}")


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
