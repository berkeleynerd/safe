#!/usr/bin/env python3
"""Remove removable Safe semicolon terminators using the compiler lexer."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from _lib.harness_common import REPO_ROOT


DEFAULT_ROOTS = (REPO_ROOT / "tests", REPO_ROOT / "samples")
SKIP_PRAGMA = "-- migrate: skip"
OPEN_BRACKETS = {"(", "[", "{"}
CLOSE_BRACKETS = {")", "]", "}"}


@dataclass(frozen=True)
class Semicolon:
    path: Path
    line: int
    col: int
    kind: str
    message: str = ""


@dataclass(frozen=True)
class Scan:
    files: int
    skipped: int
    semicolons: tuple[Semicolon, ...]

    @property
    def removable(self) -> tuple[Semicolon, ...]:
        return tuple(item for item in self.semicolons if item.kind == "removable")

    @property
    def unclassifiable(self) -> tuple[Semicolon, ...]:
        return tuple(item for item in self.semicolons if item.kind == "unclassifiable")

    def count(self, kind: str) -> int:
        return sum(1 for item in self.semicolons if item.kind == kind)


def safec_default() -> Path:
    return REPO_ROOT / "compiler_impl" / "bin" / "safec"


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def iter_safe_files(paths: Iterable[Path]) -> list[Path]:
    result: list[Path] = []
    for path in paths:
        absolute = path if path.is_absolute() else REPO_ROOT / path
        if absolute.is_file():
            if absolute.suffix == ".safe":
                result.append(absolute)
            continue
        if absolute.is_dir():
            result.extend(sorted(absolute.rglob("*.safe")))
    return sorted(set(result))


def load_tokens(safec: Path, path: Path) -> list[dict[str, Any]]:
    result = subprocess.run(
        [str(safec), "lex", str(path)],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{display_path(path)}: safec lex failed with exit {result.returncode}\n{result.stderr}"
        )
    payload = json.loads(result.stdout)
    if payload.get("format") != "tokens-v0":
        raise RuntimeError(f"{display_path(path)}: unsupported token format {payload.get('format')!r}")
    return list(payload["tokens"])


def tail_after_semicolon(lines: list[str], semi: Semicolon) -> str:
    if semi.line < 1 or semi.line > len(lines):
        raise RuntimeError(f"{display_path(semi.path)}:{semi.line}:{semi.col}: semicolon line is out of range")
    line = lines[semi.line - 1]
    index = semi.col - 1
    if index < 0 or index >= len(line) or line[index] != ";":
        raise RuntimeError(f"{display_path(semi.path)}:{semi.line}:{semi.col}: token/source mismatch")
    return line[index + 1 :].rstrip("\n")


def classify_file(safec: Path, path: Path) -> tuple[bool, list[Semicolon]]:
    text = path.read_text(encoding="utf-8")
    if SKIP_PRAGMA in text:
        return True, []

    lines = text.splitlines(keepends=True)
    tokens = load_tokens(safec, path)
    depth = 0
    semicolons: list[Semicolon] = []

    for token in tokens:
        lexeme = token["lexeme"]
        span = token["span"]
        if lexeme in CLOSE_BRACKETS:
            depth = max(0, depth - 1)

        if lexeme == ";":
            semi = Semicolon(path=path, line=int(span["start_line"]), col=int(span["start_col"]), kind="")
            tail = tail_after_semicolon(lines, semi).lstrip(" \t\r")
            if tail.startswith(";"):
                semicolons.append(
                    Semicolon(
                        path=path,
                        line=semi.line,
                        col=semi.col,
                        kind="unclassifiable",
                        message="double semicolon",
                    )
                )
            elif depth > 0:
                semicolons.append(Semicolon(path=path, line=semi.line, col=semi.col, kind="structural"))
            elif tail == "" or tail.startswith("--"):
                semicolons.append(Semicolon(path=path, line=semi.line, col=semi.col, kind="removable"))
            else:
                semicolons.append(Semicolon(path=path, line=semi.line, col=semi.col, kind="separator"))

        if lexeme in OPEN_BRACKETS:
            depth += 1

    return False, semicolons


def scan(safec: Path, files: list[Path]) -> Scan:
    skipped = 0
    semicolons: list[Semicolon] = []
    for path in files:
        was_skipped, items = classify_file(safec, path)
        if was_skipped:
            skipped += 1
        semicolons.extend(items)
    return Scan(files=len(files), skipped=skipped, semicolons=tuple(semicolons))


def remove_semicolons(items: Iterable[Semicolon]) -> int:
    by_path: dict[Path, list[Semicolon]] = {}
    for item in items:
        by_path.setdefault(item.path, []).append(item)

    for path, semicolons in by_path.items():
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        for item in sorted(semicolons, key=lambda semi: (semi.line, semi.col), reverse=True):
            line = lines[item.line - 1]
            index = item.col - 1
            if index < 0 or index >= len(line) or line[index] != ";":
                raise RuntimeError(f"{display_path(path)}:{item.line}:{item.col}: token/source mismatch")
            lines[item.line - 1] = line[:index] + line[index + 1 :]
        path.write_text("".join(lines), encoding="utf-8")
    return len(by_path)


def print_summary(label: str, result: Scan) -> None:
    print(
        f"{label}: files={result.files} skipped={result.skipped} "
        f"semicolons={len(result.semicolons)} removable={result.count('removable')} "
        f"structural={result.count('structural')} separators={result.count('separator')} "
        f"unclassifiable={result.count('unclassifiable')}"
    )


def print_findings(items: Iterable[Semicolon], *, limit: int = 20) -> None:
    for index, item in enumerate(items):
        if index >= limit:
            print(f"... {sum(1 for _ in items) - limit} more")
            break
        suffix = f": {item.message}" if item.message else ""
        print(f"{display_path(item.path)}:{item.line}:{item.col}: {item.kind}{suffix}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="fail if removable semicolons remain")
    mode.add_argument("--write", action="store_true", help="remove removable semicolons in-place")
    parser.add_argument("--safec", type=Path, default=safec_default(), help="path to safec binary")
    parser.add_argument("paths", nargs="*", type=Path, help="files or directories to scan")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    roots = args.paths if args.paths else list(DEFAULT_ROOTS)
    files = iter_safe_files(roots)
    before = scan(args.safec, files)
    print_summary("before", before)

    if before.unclassifiable:
        print_findings(before.unclassifiable, limit=50)
        return 2

    if args.check:
        if before.removable:
            print_findings(before.removable)
            return 1
        return 0

    changed_files = remove_semicolons(before.removable)
    after = scan(args.safec, files)
    print_summary("after", after)
    print(f"changed_files={changed_files}")
    if after.unclassifiable:
        print_findings(after.unclassifiable, limit=50)
        return 2
    if after.removable:
        print_findings(after.removable)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
