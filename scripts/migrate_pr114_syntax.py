#!/usr/bin/env python3
"""Mechanically rewrite Safe source files to the PR11.4 syntax surface."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOTS = (
    REPO_ROOT / "tests",
    REPO_ROOT / "samples",
)
DECLARATION_START_RE = re.compile(r"^\s*(?:public\s+)?(function|procedure)\b")
PROCEDURE_DECL_RE = re.compile(r"^(\s*(?:public\s+)?)procedure\b")


def split_segments(line: str) -> list[tuple[str, str]]:
    segments: list[tuple[str, str]] = []
    index = 0
    length = len(line)

    while index < length:
        if line.startswith("--", index):
            segments.append(("comment", line[index:]))
            break

        char = line[index]
        if char == '"':
            end_index = index + 1
            while end_index < length:
                if line[end_index] == '"':
                    if end_index + 1 < length and line[end_index + 1] == '"':
                        end_index += 2
                        continue
                    end_index += 1
                    break
                end_index += 1
            segments.append(("string", line[index:end_index]))
            index = end_index
            continue

        if char == "'":
            end_index = index + 1
            while end_index < length:
                if line[end_index] == "'":
                    end_index += 1
                    break
                end_index += 1
            segments.append(("char", line[index:end_index]))
            index = end_index
            continue

        end_index = index
        while (
            end_index < length
            and not line.startswith("--", end_index)
            and line[end_index] not in "\"'"
        ):
            end_index += 1
        segments.append(("code", line[index:end_index]))
        index = end_index

    return segments


def rewrite_safe_source(text: str) -> str:
    lines = text.splitlines(keepends=True)
    inside_signature = False
    paren_depth = 0
    rewritten: list[str] = []

    for line in lines:
        segments = split_segments(line)
        visible_code = "".join(text for kind, text in segments if kind == "code")
        if DECLARATION_START_RE.match(visible_code):
            inside_signature = True
            paren_depth = 0

        has_returns = "returns" in visible_code
        replaced_return = False
        first_code = True
        updated_segments: list[str] = []

        for kind, segment in segments:
            if kind != "code":
                updated_segments.append(segment)
                continue

            updated = segment
            if first_code:
                updated = PROCEDURE_DECL_RE.sub(r"\1function", updated, count=1)
                first_code = False

            if inside_signature and not has_returns and not replaced_return:
                if re.search(r"\breturn\b", updated):
                    updated = re.sub(r"\breturn\b", "returns", updated, count=1)
                    replaced_return = True

            updated = re.sub(r"\belsif\b", "else if", updated)
            updated = re.sub(r"\s*\.\.\s*", " to ", updated)
            updated_segments.append(updated)

        rewritten_line = "".join(updated_segments)
        rewritten.append(rewritten_line)

        visible_rewritten = "".join(
            segment for kind, segment in split_segments(rewritten_line) if kind == "code"
        )
        if inside_signature:
            paren_depth += visible_rewritten.count("(") - visible_rewritten.count(")")
            if paren_depth <= 0 and (
                re.search(r"\bis\b", visible_rewritten) or visible_rewritten.rstrip().endswith(";")
            ):
                inside_signature = False
                paren_depth = 0

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
