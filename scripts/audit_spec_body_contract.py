#!/usr/bin/env python3
"""Report Phase 1G spec/body no-return contract audit hits."""

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
BASELINE_PATH = REPO_ROOT / "audit" / "phase1g_spec_body_contract_baseline.json"
CATEGORIES = ("spec-no-return-contract",)
PATTERNS = ("spec-no-return-pragma",)
BODY_STATUSES = ("raises", "returns", "missing", "unknown")
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
class SpecContract:
    helper_name: str
    pragma_line: int
    pragma_end_line: int
    pragma_text: str
    first_line_text: str
    declaration_line: int | None


@dataclass(frozen=True)
class BodyEvidence:
    path: Path
    line: int | None
    status: str


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
    except (OSError, UnicodeDecodeError):
        return None


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


def sanitized_source(text: str) -> str:
    return "\n".join(strip_comments_and_strings(line) for line in text.splitlines())


def normalized_text(text: str) -> str:
    return " ".join(text.strip().split())


def first_line_text(text: str) -> str:
    for line in text.splitlines():
        normalized = normalized_text(line)
        if normalized:
            return normalized
    return ""


def statement_has_semicolon(line: str) -> bool:
    return ";" in line


def starts_with_keyword(text: str, keyword: str) -> bool:
    return text == keyword or text.startswith((f"{keyword} ", f"{keyword};"))


def is_structural_header(line: str) -> bool:
    text = normalized_text(line).lower()
    if not text:
        return False
    if text.startswith(("procedure ", "function ")):
        return False
    return (
        text in {"begin", "declare", "else", "exception", "private"}
        or text.endswith((" is", " record", "=>"))
        or starts_with_keyword(text, "loop")
        or text.startswith(
            (
                "case ",
                "elsif ",
                "for ",
                "if ",
                "package ",
                "protected ",
                "task ",
                "type ",
                "while ",
            )
        )
    )


def iter_statements(text: str) -> Iterable[Statement]:
    start_line: int | None = None
    code_parts: list[str] = []
    display_parts: list[str] = []
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        code_line = strip_comments_and_strings(raw_line)
        display_line = strip_comments_keep_strings(raw_line)
        if start_line is None and not normalized_text(code_line):
            continue
        if start_line is None and not statement_has_semicolon(code_line):
            if is_structural_header(code_line):
                continue
        if start_line is None:
            start_line = line_number
        code_parts.append(code_line)
        display_parts.append(display_line)
        if not statement_has_semicolon(code_line):
            continue
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


def no_return_names_from_statement(statement: Statement) -> list[str]:
    match = re.search(
        r"\bpragma\s+No_Return\s*\((?P<names>[^)]*)\)\s*;",
        statement.code_text,
        re.IGNORECASE,
    )
    if match is None:
        return []
    names = [name.strip() for name in match.group("names").split(",")]
    return [name for name in names if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name)]


def procedure_name_from_statement(statement: Statement) -> str | None:
    match = re.match(
        r"\s*procedure\s+(?P<name>[A-Za-z][A-Za-z0-9_]*)\b",
        statement.code_text,
        re.IGNORECASE,
    )
    if match is None:
        return None
    return match.group("name")


def nearest_declaration_line(lines: list[int], pragma_line: int) -> int | None:
    prior = [line for line in lines if line <= pragma_line]
    if prior:
        return max(prior)
    return None


def collect_spec_contracts(text: str) -> list[SpecContract]:
    statements = list(iter_statements(text))
    declarations: dict[str, list[int]] = {}
    for statement in statements:
        name = procedure_name_from_statement(statement)
        if name is not None:
            declarations.setdefault(name.lower(), []).append(statement.start_line)

    contracts: list[SpecContract] = []
    for statement in statements:
        for helper_name in no_return_names_from_statement(statement):
            declaration_line = nearest_declaration_line(
                declarations.get(helper_name.lower(), []),
                statement.start_line,
            )
            contracts.append(
                SpecContract(
                    helper_name=helper_name,
                    pragma_line=statement.start_line,
                    pragma_end_line=statement.end_line,
                    pragma_text=statement.display_text,
                    first_line_text=statement.first_line_text,
                    declaration_line=declaration_line,
                )
            )
    return contracts


def line_number_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def expected_body_path(spec_path: Path) -> Path:
    return spec_path.with_suffix(".adb")


def procedure_body_match(helper_name: str, text: str) -> re.Match[str] | None:
    named_end_pattern = re.compile(
        rf"(?ims)^[ \t]*procedure\s+{re.escape(helper_name)}\b.*?\bis\b"
        rf"(?P<body>.*?)^[ \t]*end\s+{re.escape(helper_name)}\s*;",
    )
    source = sanitized_source(text)
    match = named_end_pattern.search(source)
    if match is not None:
        return match
    anonymous_end_pattern = re.compile(
        rf"(?ims)^[ \t]*procedure\s+{re.escape(helper_name)}\b.*?\bis\b"
        rf"(?P<body>.*?)^[ \t]*end\s*;",
    )
    return anonymous_end_pattern.search(source)


def executable_statements(text: str) -> list[Statement]:
    result: list[Statement] = []
    for statement in iter_statements(text):
        normalized = statement.code_text.lower()
        if not normalized:
            continue
        if any(
            starts_with_keyword(normalized, keyword)
            for keyword in ("begin", "declare", "exception", "end")
        ):
            continue
        result.append(statement)
    return result


def starts_with_no_return_call(text: str, names: set[str]) -> bool:
    for name in names:
        if re.match(rf"^{re.escape(name)}\b\s*(?:\(|;)", text, re.IGNORECASE):
            return True
    return False


def body_status_for_source(
    helper_name: str,
    text: str,
    *,
    known_no_return_names: set[str],
) -> tuple[str, int | None]:
    match = procedure_body_match(helper_name, text)
    if match is None:
        return "missing", None
    body_line = line_number_for_offset(sanitized_source(text), match.start())
    body_text = match.group("body")
    begin_match = re.search(r"(?im)^\s*begin\b", body_text)
    if begin_match is None:
        return "unknown", body_line
    executable_region = body_text[begin_match.end() :]
    exception_match = re.search(r"(?im)^\s*exception\b", executable_region)
    has_exception_handler = exception_match is not None
    if exception_match is not None:
        executable_region = executable_region[: exception_match.start()]
    if re.search(r"(?im)^\s*(if|case|loop|for|while|select)\b", executable_region):
        return "unknown", body_line
    statements = executable_statements(executable_region)
    if not statements:
        return ("unknown" if has_exception_handler else "returns"), body_line
    final = statements[-1].code_text
    if re.match(r"^raise\b", final, re.IGNORECASE):
        return "raises", body_line
    if starts_with_no_return_call(final, {helper_name}):
        return "unknown", body_line
    other_no_return_names = {
        name for name in known_no_return_names if name.lower() != helper_name.lower()
    }
    if starts_with_no_return_call(final, other_no_return_names):
        return "raises", body_line
    return ("unknown" if has_exception_handler else "returns"), body_line


def body_evidence_for(
    spec_path: Path,
    helper_name: str,
    *,
    known_no_return_names: set[str],
) -> BodyEvidence:
    body_path = expected_body_path(spec_path)
    text = read_utf8_text_or_none(body_path)
    if text is None:
        return BodyEvidence(path=body_path, line=None, status="missing")
    status, line = body_status_for_source(
        helper_name,
        text,
        known_no_return_names=known_no_return_names,
    )
    return BodyEvidence(path=body_path, line=line, status=status)


def fingerprint_for(
    category: str,
    path: Path,
    pattern_name: str,
    helper_name: str,
    normalized: str,
) -> str:
    seed = f"{category}\0{repo_rel(path)}\0{pattern_name}\0{helper_name}\0{normalized}"
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
    spec_sources: list[tuple[Path, str]] = []
    for root in SCAN_ROOTS:
        for path in iter_sources(root, suffixes={".ads"}):
            text = read_utf8_text_or_none(path)
            if text is not None:
                spec_sources.append((path, text))

    spec_contracts: list[tuple[Path, SpecContract]] = []
    for path, text in spec_sources:
        for contract in collect_spec_contracts(text):
            spec_contracts.append((path, contract))
    known_no_return_names = {contract.helper_name for _, contract in spec_contracts}

    entries: list[dict[str, object]] = []
    for path, contract in spec_contracts:
        category = "spec-no-return-contract"
        pattern_name = "spec-no-return-pragma"
        normalized = normalized_text(contract.pragma_text)
        fingerprint = fingerprint_for(
            category,
            path,
            pattern_name,
            contract.helper_name,
            normalized,
        )
        prior_entry = prior.get(fingerprint, {})
        body = body_evidence_for(
            path,
            contract.helper_name,
            known_no_return_names=known_no_return_names,
        )
        entries.append(
            {
                "fingerprint": fingerprint,
                "category": category,
                "pattern": pattern_name,
                "path": repo_rel(path),
                "line": contract.pragma_line,
                "line_numbers": list(range(contract.pragma_line, contract.pragma_end_line + 1)),
                "first_line_text": contract.first_line_text,
                "line_text": normalized,
                "helper_name": contract.helper_name,
                "declaration_line": contract.declaration_line,
                "body_path": repo_rel(body.path),
                "body_line": body.line,
                "body_status": body.status,
                "classification": prior_entry.get("classification", "candidate"),
                "rationale": prior_entry.get("rationale", ""),
                "follow_up": prior_entry.get("follow_up", "Phase 1G spec/body contract triage PR"),
            }
        )

    sorted_entries = sorted(
        entries,
        key=lambda item: (
            str(item["category"]),
            str(item["path"]),
            int(item["line"]),
            str(item["helper_name"]),
        ),
    )
    return {
        "version": 1,
        "generated_by": "python3 scripts/audit_spec_body_contract.py --json",
        "scope": [repo_rel(path) for path in SCAN_ROOTS],
        "classifications": [
            "candidate",
            "needs-repro",
            "confirmed-defect",
            "accepted-with-rationale",
        ],
        "body_statuses": list(BODY_STATUSES),
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


def counts_by_body_status(payload: dict[str, object]) -> dict[str, int]:
    counts = {status: 0 for status in BODY_STATUSES}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                status = str(entry.get("body_status", "unknown"))
                counts[status] = counts.get(status, 0) + 1
    return counts


def print_summary(
    payload: dict[str, object],
    baseline_entries: dict[str, dict[str, object]] | None = None,
) -> None:
    counts = counts_by_category(payload)
    for category in sorted(counts):
        print(f"[Phase 1G] {category}: {counts[category]}")
    for status, count in sorted(counts_by_body_status(payload).items()):
        print(f"[Phase 1G] body_status {status}: {count}")
    entries = payload.get("entries", [])
    if baseline_entries is None:
        baseline_entries = existing_classifications()
    current = {
        str(entry.get("fingerprint"))
        for entry in entries
        if isinstance(entry, dict) and entry.get("fingerprint")
    }
    print(f"[Phase 1G] baseline entries: {len(baseline_entries)}")
    print(f"[Phase 1G] new outside baseline: {len(current - set(baseline_entries))}")
    print(f"[Phase 1G] missing from baseline: {len(set(baseline_entries) - current)}")


def print_markdown(payload: dict[str, object]) -> None:
    print("# Phase 1G Spec/Body Contract Audit Report")
    print()
    print("## Counts")
    print()
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"- `{category}`: {count}")
    for status, count in sorted(counts_by_body_status(payload).items()):
        print(f"- `body_status:{status}`: {count}")
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
            f"`{entry.get('helper_name')}` `{entry.get('body_status')}` "
            f"`{entry.get('classification')}`"
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
