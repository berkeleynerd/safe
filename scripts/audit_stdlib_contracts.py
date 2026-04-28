#!/usr/bin/env python3
"""Report Phase 1H stdlib runtime contract-boundary audit hits."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOT = REPO_ROOT / "compiler_impl" / "stdlib" / "ada"
BASELINE_PATH = REPO_ROOT / "audit" / "phase1h_stdlib_contract_baseline.json"
ASPECT_NAMES = ("Global", "Depends", "Pre", "Post", "Always_Terminates")
CATEGORIES = (
    "stdlib-generic-formal-contract",
    "stdlib-io-contract",
    "stdlib-spark-off-runtime-contract",
    "stdlib-spark-on-runtime-contract",
)
PATTERNS = ("stdlib-contract-subprogram",)
IMPLEMENTATION_SURFACES = (
    "spark-off-body",
    "spark-on-body",
    "expression-function",
    "generic-stub",
    "io-boundary",
    "missing",
    "unknown",
)


@dataclass(frozen=True)
class ContractDecl:
    path: Path
    line: int
    end_line: int
    package: str
    subprogram: str
    subprogram_kind: str
    first_line_text: str
    line_text: str


def repo_rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def normalized_text(text: str) -> str:
    return " ".join(text.strip().split())


def strip_comment(line: str) -> str:
    in_string = False
    index = 0
    result: list[str] = []
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


def statement_end(lines: list[str], start: int) -> int:
    """Return the inclusive index of an Ada declaration statement.

    Semicolons inside parameter lists do not terminate a subprogram declaration.
    This is intentionally line-oriented and string-aware, matching the scanner's
    reporting role rather than attempting full Ada parsing.
    """

    depth = 0
    in_string = False
    for index in range(start, len(lines)):
        line = strip_comment(lines[index])
        char_index = 0
        while char_index < len(line):
            char = line[char_index]
            nxt = line[char_index + 1] if char_index + 1 < len(line) else ""
            if char == '"':
                if in_string and nxt == '"':
                    char_index += 2
                    continue
                in_string = not in_string
            elif not in_string:
                if char == "(":
                    depth += 1
                elif char == ")" and depth > 0:
                    depth -= 1
                elif char == ";" and depth == 0:
                    return index
            char_index += 1
    return len(lines) - 1


def iter_specs() -> Iterable[Path]:
    if not SCAN_ROOT.exists():
        return
    yield from sorted(SCAN_ROOT.glob("*.ads"))


def read_utf8_text_or_none(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def collect_expression_functions(text: str) -> set[str]:
    names: set[str] = set()
    lines = text.splitlines()
    in_private = False
    index = 0
    while index < len(lines):
        line = strip_comment(lines[index])
        if re.match(r"^\s*private\s*$", line, re.IGNORECASE):
            in_private = True
            index += 1
            continue
        if not in_private:
            index += 1
            continue
        match = re.match(
            r"^\s*function\s+([A-Za-z][A-Za-z0-9_]*)\b",
            line,
            re.IGNORECASE,
        )
        if not match:
            index += 1
            continue
        end = statement_end(lines, index)
        block = "\n".join(strip_comment(line) for line in lines[index : end + 1])
        if re.search(r"\bis\s*\(", normalized_text(block), re.IGNORECASE):
            names.add(match.group(1))
        index = end + 1
    return names


def collect_contract_declarations(path: Path, text: str) -> list[ContractDecl]:
    lines = text.splitlines()
    declarations: list[ContractDecl] = []
    package_stack: list[str] = []
    in_private = False
    index = 0
    while index < len(lines):
        line = strip_comment(lines[index])
        package_match = re.match(
            r"^\s*package\s+([A-Za-z][A-Za-z0-9_]*)\b",
            line,
            re.IGNORECASE,
        )
        if package_match:
            name = package_match.group(1)
            if not package_stack or package_stack[-1] != name:
                package_stack.append(name)
        if re.match(r"^\s*private\s*$", line, re.IGNORECASE):
            in_private = True
            index += 1
            continue
        if in_private:
            index += 1
            continue

        match = re.match(
            r"^\s*(function|procedure)\s+([A-Za-z][A-Za-z0-9_]*)\b",
            line,
            re.IGNORECASE,
        )
        if not match:
            index += 1
            continue

        start = index
        end = statement_end(lines, start)
        block_lines = [strip_comment(line) for line in lines[start : end + 1]]
        text_block = "\n".join(block_lines)
        normalized = normalized_text(text_block)
        if any(re.search(rf"\b{name}\b", normalized) for name in ASPECT_NAMES):
            package = ".".join(package_stack) if package_stack else path.stem
            declarations.append(
                ContractDecl(
                    path=path,
                    line=start + 1,
                    end_line=end + 1,
                    package=package,
                    subprogram=match.group(2),
                    subprogram_kind=match.group(1).lower(),
                    first_line_text=normalized_text(block_lines[0]),
                    line_text=normalized,
                )
            )
        index = end + 1
    return declarations


def body_path_for(spec_path: Path) -> Path:
    return spec_path.with_suffix(".adb")


def body_spark_surface(body_path: Path) -> str:
    text = read_utf8_text_or_none(body_path)
    if text is None:
        return "missing"
    if re.search(r"SPARK_Mode\s*(?:=>|\()\s*Off\b", text, re.IGNORECASE):
        return "spark-off-body"
    if re.search(r"SPARK_Mode\s*(?:=>|\()\s*On\b", text, re.IGNORECASE):
        return "spark-on-body"
    return "unknown"


def category_for(decl: ContractDecl) -> str:
    if decl.package == "IO":
        return "stdlib-io-contract"
    if decl.package == "Safe_Array_Identity_Ops":
        return "stdlib-generic-formal-contract"
    if decl.package.startswith("Safe_Bounded_Strings"):
        return "stdlib-spark-on-runtime-contract"
    if decl.package in {
        "Safe_Array_RT",
        "Safe_Array_Identity_RT",
        "Safe_String_RT",
        "Safe_Ownership_RT",
    }:
        return "stdlib-spark-off-runtime-contract"
    raise ValueError(f"unsupported Phase 1H stdlib package {decl.package!r}")


def implementation_surface_for(
    decl: ContractDecl,
    *,
    expression_functions: set[str],
) -> tuple[str, Path]:
    if decl.package == "IO":
        return "io-boundary", body_path_for(decl.path)
    if decl.package == "Safe_Array_Identity_Ops":
        return "generic-stub", body_path_for(decl.path)
    if decl.subprogram in expression_functions:
        return "expression-function", decl.path
    return body_spark_surface(body_path_for(decl.path)), body_path_for(decl.path)


def fingerprint_for(decl: ContractDecl, category: str) -> str:
    seed = (
        f"{category}\0{repo_rel(decl.path)}\0{PATTERNS[0]}\0"
        f"{decl.package}\0{decl.subprogram}\0{decl.line_text}"
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


def scan() -> dict[str, object]:
    prior = existing_classifications()
    entries: list[dict[str, object]] = []
    for path in iter_specs():
        text = read_utf8_text_or_none(path)
        if text is None:
            continue
        expression_functions = collect_expression_functions(text)
        for decl in collect_contract_declarations(path, text):
            category = category_for(decl)
            surface, implementation_path = implementation_surface_for(
                decl,
                expression_functions=expression_functions,
            )
            fingerprint = fingerprint_for(decl, category)
            prior_entry = prior.get(fingerprint, {})
            entries.append(
                {
                    "fingerprint": fingerprint,
                    "category": category,
                    "pattern": PATTERNS[0],
                    "path": repo_rel(decl.path),
                    "line": decl.line,
                    "line_numbers": list(range(decl.line, decl.end_line + 1)),
                    "first_line_text": decl.first_line_text,
                    "line_text": decl.line_text,
                    "package": decl.package,
                    "subprogram": decl.subprogram,
                    "subprogram_kind": decl.subprogram_kind,
                    "implementation_path": repo_rel(implementation_path),
                    "implementation_surface": surface,
                    "classification": prior_entry.get("classification", "candidate"),
                    "rationale": prior_entry.get("rationale", ""),
                    "follow_up": prior_entry.get("follow_up", ""),
                }
            )

    entries.sort(
        key=lambda entry: (
            str(entry["category"]),
            str(entry["path"]),
            int(entry["line"]),
            str(entry["subprogram"]),
        )
    )
    return {
        "version": 1,
        "generated_by": "python3 scripts/audit_stdlib_contracts.py --json",
        "scope": [repo_rel(SCAN_ROOT)],
        "classifications": [
            "candidate",
            "needs-repro",
            "confirmed-defect",
            "accepted-with-rationale",
        ],
        "implementation_surfaces": list(IMPLEMENTATION_SURFACES),
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


def counts_by_surface(payload: dict[str, object]) -> dict[str, int]:
    counts = {surface: 0 for surface in IMPLEMENTATION_SURFACES}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                surface = str(entry.get("implementation_surface", "unknown"))
                counts[surface] = counts.get(surface, 0) + 1
    return counts


def counts_by_package(payload: dict[str, object]) -> dict[str, int]:
    counts: dict[str, int] = {}
    entries = payload.get("entries", [])
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                package = str(entry.get("package", "unknown"))
                counts[package] = counts.get(package, 0) + 1
    return counts


def print_summary(
    payload: dict[str, object],
    baseline_entries: dict[str, dict[str, object]] | None = None,
) -> None:
    for category, count in sorted(counts_by_category(payload).items()):
        print(f"[Phase 1H] {category}: {count}")
    for package, count in sorted(counts_by_package(payload).items()):
        print(f"[Phase 1H] package {package}: {count}")
    for surface, count in sorted(counts_by_surface(payload).items()):
        print(f"[Phase 1H] implementation_surface {surface}: {count}")
    entries = payload.get("entries", [])
    if baseline_entries is None:
        baseline_entries = existing_classifications()
    current = {
        str(entry.get("fingerprint"))
        for entry in entries
        if isinstance(entry, dict) and entry.get("fingerprint")
    }
    baseline = set(baseline_entries)
    print(f"[Phase 1H] baseline entries: {len(baseline)}")
    print(f"[Phase 1H] new outside baseline: {len(current - baseline)}")
    print(f"[Phase 1H] missing from baseline: {len(baseline - current)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="emit full JSON report")
    parser.add_argument("--summary", action="store_true", help="emit summary counts")
    args = parser.parse_args()

    payload = scan()
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    if args.summary or not args.json:
        print_summary(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
