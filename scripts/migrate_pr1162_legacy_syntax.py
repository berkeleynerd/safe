#!/usr/bin/env python3
"""Mechanically rewrite straightforward PR11.6.2 legacy-syntax cases."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from migrate_pr114_syntax import split_segments


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOTS = (
    REPO_ROOT / "tests",
    REPO_ROOT / "samples",
)
DECLARE_RE = re.compile(r"^\s*declare\s*$", re.IGNORECASE)
BEGIN_RE = re.compile(r"^\s*begin\s*$", re.IGNORECASE)
END_RE = re.compile(r"^\s*end\s*;?\s*$", re.IGNORECASE)
NULL_RE = re.compile(r"^\s*null\s*;?\s*$", re.IGNORECASE)
DECL_LINE_RE = re.compile(r"^(\s*)([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*(.+?)(\s*;?\s*)$")


class LegacySyntaxMigrationError(RuntimeError):
    """Raised when a source rewrite would need a non-mechanical semantic change."""


def visible_code(line: str) -> str:
    return "".join(text for kind, text in split_segments(line) if kind == "code")


def strip_newline(line: str) -> tuple[str, str]:
    if line.endswith("\r\n"):
        return (line[:-2], "\r\n")
    if line.endswith("\n"):
        return (line[:-1], "\n")
    return (line, "")


def code_indent(line: str) -> int:
    code = visible_code(line)
    return len(code) - len(code.lstrip(" "))


def rewrite_decl_line(line: str) -> str:
    body, newline = strip_newline(line)
    match = DECL_LINE_RE.match(body)
    if match is None:
        raise LegacySyntaxMigrationError("declare block contains a non-object declaration")
    indent, names, remainder, suffix = match.groups()
    remainder_code = visible_code(remainder).strip().lower()
    if remainder_code == "constant" or remainder_code.startswith("constant "):
        return line
    return f"{indent}var {names} : {remainder}{suffix}{newline}"


def block_is_tail(lines: list[str], *, after_index: int, indent: int) -> bool:
    for candidate in lines[after_index:]:
        code = visible_code(candidate).strip()
        if not code:
            continue
        return code_indent(candidate) < indent
    return True


def rewrite_safe_source(text: str) -> str:
    lines = text.splitlines(keepends=True)
    rewritten: list[str] = []
    index = 0

    while index < len(lines):
        line = lines[index]
        code = visible_code(line).strip()

        if NULL_RE.match(code):
            index += 1
            continue

        if not DECLARE_RE.match(code):
            rewritten.append(line)
            index += 1
            continue

        declare_indent = code_indent(line)
        decl_lines: list[str] = []
        body_lines: list[str] = []
        index += 1

        while index < len(lines) and not BEGIN_RE.match(visible_code(lines[index]).strip()):
            decl_lines.append(lines[index])
            index += 1
        if index >= len(lines):
            raise LegacySyntaxMigrationError("unterminated declare block: missing begin")
        index += 1

        while index < len(lines) and not (
            END_RE.match(visible_code(lines[index]).strip()) and code_indent(lines[index]) == declare_indent
        ):
            body_lines.append(lines[index])
            index += 1
        if index >= len(lines):
            raise LegacySyntaxMigrationError("unterminated declare block: missing end")

        if not block_is_tail(lines, after_index=index + 1, indent=declare_indent):
            raise LegacySyntaxMigrationError(
                "declare block is followed by more statements in the same suite; manual rewrite required"
            )

        for decl_line in decl_lines:
            code_only = visible_code(decl_line).strip()
            if not code_only:
                rewritten.append(decl_line)
                continue
            rewritten.append(rewrite_decl_line(decl_line))
        for body_line in body_lines:
            if NULL_RE.match(visible_code(body_line).strip()):
                continue
            rewritten.append(body_line)
        index += 1

    return "".join(rewritten)


def iter_safe_paths(roots: list[Path]) -> list[Path]:
    paths: list[Path] = []
    for root in roots:
        if root.is_file():
            if root.suffix == ".safe":
                paths.append(root)
            continue
        paths.extend(sorted(root.rglob("*.safe")))
    return sorted(set(paths))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="optional .safe paths or directories to rewrite")
    parser.add_argument("--check", action="store_true", help="report files that would change without rewriting")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    roots = [path.resolve() for path in (args.paths or list(DEFAULT_ROOTS))]
    changed: list[Path] = []

    for path in iter_safe_paths(roots):
        original = path.read_text(encoding="utf-8")
        try:
            updated = rewrite_safe_source(original)
        except LegacySyntaxMigrationError:
            continue
        if updated != original:
            changed.append(path)
            if not args.check:
                path.write_text(updated, encoding="utf-8")

    for path in changed:
        print(path.relative_to(REPO_ROOT))

    if args.check and changed:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
