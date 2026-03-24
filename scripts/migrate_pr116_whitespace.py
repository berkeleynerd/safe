#!/usr/bin/env python3
"""Mechanically rewrite Safe source files to the PR11.6 meaningful-whitespace surface."""

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

FUNCTION_START_RE = re.compile(r"^\s*(?:public\s+)?function\b", re.IGNORECASE)
PACKAGE_IS_RE = re.compile(r"^(\s*package\b.+?)\s+is(\s*)$", re.IGNORECASE)
TASK_IS_RE = re.compile(r"^(\s*task\b.+?)\s+is(\s*)$", re.IGNORECASE)
CASE_IS_RE = re.compile(r"^(\s*case\b.+?)\s+is(\s*)$", re.IGNORECASE)
IF_THEN_RE = re.compile(r"^(\s*if\b.+?)\s+then(\s*)$", re.IGNORECASE)
ELSE_IF_THEN_RE = re.compile(r"^(\s*else\s+if\b.+?)\s+then(\s*)$", re.IGNORECASE)
WHEN_THEN_RE = re.compile(r"^(\s*when\b.+?)\s+then(\s*)$", re.IGNORECASE)
WHEN_INLINE_THEN_RE = re.compile(r"^(\s*)(when\b.+?)\s+then\s+(.+?)\s*$", re.IGNORECASE)
DELAY_THEN_RE = re.compile(r"^(\s*delay\b.+?)\s+then(\s*)$", re.IGNORECASE)
DELAY_INLINE_THEN_RE = re.compile(r"^(\s*)(delay\b.+?)\s+then\s+(.+?)\s*$", re.IGNORECASE)
WHILE_LOOP_RE = re.compile(r"^(\s*while\b.+?)\s+loop(\s*)$", re.IGNORECASE)
FOR_LOOP_RE = re.compile(r"^(\s*for\b.+?)\s+loop(\s*)$", re.IGNORECASE)
END_IF_RE = re.compile(r"^\s*end\s+if\s*;?\s*$", re.IGNORECASE)
END_LOOP_RE = re.compile(r"^\s*end\s+loop\s*;?\s*$", re.IGNORECASE)
END_CASE_RE = re.compile(r"^\s*end\s+case\s*;?\s*$", re.IGNORECASE)
END_RECORD_RE = re.compile(r"^\s*end\s+record\s*;?\s*$", re.IGNORECASE)
END_SELECT_RE = re.compile(r"^\s*end\s+select\s*;?\s*$", re.IGNORECASE)
END_WHEN_RE = re.compile(r"^\s*end\s+when\s*;?\s*$", re.IGNORECASE)
END_NAMED_RE = re.compile(r"^\s*end\s+[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s*;?\s*$", re.IGNORECASE)
END_BARE_RE = re.compile(r"^\s*end\s*;\s*$", re.IGNORECASE)
BEGIN_RE = re.compile(r"^\s*begin\s*$", re.IGNORECASE)


def strip_newline(line: str) -> tuple[str, str]:
    if line.endswith("\r\n"):
        return (line[:-2], "\r\n")
    if line.endswith("\n"):
        return (line[:-1], "\n")
    return (line, "")


def split_content_and_comment(line: str) -> tuple[str, str]:
    content = []
    comment = ""
    for kind, text in split_segments(line):
        if kind == "comment":
            comment = text
            break
        content.append(text)
    return ("".join(content), comment)


def ends_with_trailing_is(content: str) -> bool:
    return bool(re.search(r"\bis\s*$", content, flags=re.IGNORECASE))


def drop_trailing_is(content: str) -> str:
    return re.sub(r"\s+is(\s*)$", r"\1", content, count=1, flags=re.IGNORECASE)


def rewrite_line_content(content: str) -> tuple[str, str | None]:
    if match := PACKAGE_IS_RE.match(content):
        return (match.group(1) + match.group(2), "package")
    if match := TASK_IS_RE.match(content):
        return (match.group(1) + match.group(2), "task")
    if match := ELSE_IF_THEN_RE.match(content):
        return (match.group(1) + match.group(2), None)
    if match := IF_THEN_RE.match(content):
        return (match.group(1) + match.group(2), "if")
    if match := WHILE_LOOP_RE.match(content):
        return (match.group(1) + match.group(2), "loop")
    if match := FOR_LOOP_RE.match(content):
        return (match.group(1) + match.group(2), "loop")
    if match := CASE_IS_RE.match(content):
        return (match.group(1) + match.group(2), "case")
    if match := WHEN_THEN_RE.match(content):
        return (match.group(1) + match.group(2), None)
    if match := DELAY_THEN_RE.match(content):
        return (match.group(1) + match.group(2), None)
    return (content, None)


def rewrite_safe_source(text: str) -> str:
    lines = text.splitlines(keepends=True)
    rewritten: list[str] = []
    block_stack: list[str] = []
    inside_function_signature = False
    signature_paren_depth = 0

    for index, line in enumerate(lines):
        body, newline = strip_newline(line)
        content, comment = split_content_and_comment(body)
        stripped = content.strip()
        lowered = stripped.lower()

        if FUNCTION_START_RE.match(content):
            inside_function_signature = True
            signature_paren_depth = 0

        if inside_function_signature:
            signature_paren_depth += content.count("(") - content.count(")")
            if signature_paren_depth <= 0 and ends_with_trailing_is(content):
                content = drop_trailing_is(content)
                inside_function_signature = False
                signature_paren_depth = 0
                block_stack.append("subprogram")
                rewritten.append(content + comment + newline)
                continue
            if signature_paren_depth <= 0:
                next_starts_return_continuation = False
                for lookahead in lines[index + 1 :]:
                    next_body, _next_newline = strip_newline(lookahead)
                    next_content, _next_comment = split_content_and_comment(next_body)
                    next_stripped = next_content.strip().lower()
                    if not next_stripped:
                        continue
                    next_starts_return_continuation = next_stripped.startswith("returns")
                    break
                if not next_starts_return_continuation:
                    inside_function_signature = False
                    signature_paren_depth = 0
                    block_stack.append("subprogram")
                    rewritten.append(content + comment + newline)
                    continue

        if lowered == "declare":
            block_stack.append("declare-pending")
            rewritten.append(line)
            continue

        if match := WHEN_INLINE_THEN_RE.match(content):
            rewritten.append(f"{match.group(1)}{match.group(2)}{comment}{newline}")
            rewritten.append(f"{match.group(1)}   {match.group(3)}{newline}")
            continue

        if match := DELAY_INLINE_THEN_RE.match(content):
            rewritten.append(f"{match.group(1)}{match.group(2)}{comment}{newline}")
            rewritten.append(f"{match.group(1)}   {match.group(3)}{newline}")
            continue

        if BEGIN_RE.match(content):
            if block_stack and block_stack[-1] == "declare-pending":
                block_stack[-1] = "declare"
                rewritten.append(line)
            else:
                rewritten.append(comment + newline if comment else newline)
            continue

        if END_BARE_RE.match(content):
            if block_stack and block_stack[-1] == "declare":
                block_stack.pop()
                rewritten.append(line)
            else:
                rewritten.append(comment + newline if comment else newline)
            continue

        if END_IF_RE.match(content):
            if block_stack and block_stack[-1] == "if":
                block_stack.pop()
            rewritten.append(comment + newline if comment else newline)
            continue

        if END_LOOP_RE.match(content):
            if block_stack and block_stack[-1] == "loop":
                block_stack.pop()
            rewritten.append(comment + newline if comment else newline)
            continue

        if END_CASE_RE.match(content):
            if block_stack and block_stack[-1] == "case":
                block_stack.pop()
            rewritten.append(comment + newline if comment else newline)
            continue

        if END_RECORD_RE.match(content):
            if block_stack and block_stack[-1] == "record":
                block_stack.pop()
            rewritten.append(comment + newline if comment else newline)
            continue

        if END_SELECT_RE.match(content):
            if block_stack and block_stack[-1] == "select":
                block_stack.pop()
            rewritten.append(comment + newline if comment else newline)
            continue

        if END_WHEN_RE.match(content):
            rewritten.append(comment + newline if comment else newline)
            continue

        if END_NAMED_RE.match(content):
            if block_stack and block_stack[-1] in {"package", "subprogram", "task"}:
                block_stack.pop()
            rewritten.append(comment + newline if comment else newline)
            continue

        if re.match(r"^\s*select\s*$", content, flags=re.IGNORECASE):
            block_stack.append("select")
            rewritten.append(line)
            continue

        if re.match(r"^\s*loop\s*$", content, flags=re.IGNORECASE):
            block_stack.append("loop")
            rewritten.append(line)
            continue

        if re.match(r"^\s*type\b.+\bis\s+record\s*$", content, flags=re.IGNORECASE):
            block_stack.append("record")
            rewritten.append(line)
            continue

        updated, opened = rewrite_line_content(content)
        if opened is not None:
            block_stack.append(opened)
        rewritten.append(updated + comment + newline)

    return "".join(collapse_blank_line_runs(collapse_else_if_lines(rewritten)))


def collapse_else_if_lines(lines: list[str]) -> list[str]:
    collapsed: list[str] = []
    index = 0

    while index < len(lines):
        body, newline = strip_newline(lines[index])
        content, comment = split_content_and_comment(body)
        indent = len(content) - len(content.lstrip(" "))

        if content.strip() == "else" and comment == "" and index + 1 < len(lines):
            next_body, next_newline = strip_newline(lines[index + 1])
            next_content, next_comment = split_content_and_comment(next_body)
            next_indent = len(next_content) - len(next_content.lstrip(" "))
            next_stripped = next_content.lstrip()
            if next_indent == indent and next_stripped.startswith("if "):
                collapsed.append(
                    f"{' ' * indent}else if {next_stripped[3:]}{next_comment}{next_newline}"
                )
                index += 2
                continue

        collapsed.append(lines[index])
        index += 1

    return collapsed


def collapse_blank_line_runs(lines: list[str]) -> list[str]:
    collapsed: list[str] = []
    previous_blank = False

    for line in lines:
        body, _newline = strip_newline(line)
        is_blank = body.strip() == ""
        if is_blank and previous_blank:
            continue
        collapsed.append(line)
        previous_blank = is_blank

    return collapsed


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
        updated = rewrite_safe_source(original)
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
