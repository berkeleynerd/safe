#!/usr/bin/env python3
"""Mechanical rewrites for the PR11.7 reference-surface cutover."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from migrate_pr114_syntax import split_segments


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOTS = (
    REPO_ROOT / "tests",
    REPO_ROOT / "samples",
    REPO_ROOT / "compiler_impl" / "tests",
)
SKIPPED_REFERENCE_SIGNAL_NEGATIVE_FIXTURES = {
    "neg_pr117_explicit_all.safe",
    "neg_pr117_lowercase_access_binding.safe",
    "neg_pr117_lowercase_access_field.safe",
    "neg_pr117_uppercase_attribute.safe",
    "neg_pr117_uppercase_builtin_type.safe",
    "neg_pr117_uppercase_value_binding.safe",
}
BUILTIN_TYPE_NAMES = (
    "integer",
    "natural",
    "boolean",
    "character",
    "string",
    "result",
    "float",
    "long_float",
    "duration",
)
BUILTIN_FUNCTION_NAMES = (
    "ok",
    "fail",
)
BOOLEAN_LITERALS = (
    "true",
    "false",
)
ATTRIBUTE_NAMES = (
    "access",
    "first",
    "last",
    "length",
)
TYPE_ACCESS_RE = re.compile(
    r"^\s*(?:public\s+)?type\s+([A-Za-z_]\w*)\s+is\s+(?:not\s+null\s+)?access\b",
    re.IGNORECASE,
)
TYPE_DECL_RE = re.compile(r"^\s*(?:public\s+)?type\s+([A-Za-z_]\w*)\b", re.IGNORECASE)
TYPE_WITH_DISCRIMINANTS_RE = re.compile(
    r"^\s*(?:public\s+)?type\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s+is\b",
    re.IGNORECASE,
)
SUBTYPE_RE = re.compile(r"^\s*(?:public\s+)?subtype\s+([A-Za-z_]\w*)\b", re.IGNORECASE)
PACKAGE_RE = re.compile(r"^\s*package\s+([A-Za-z_]\w*)\b", re.IGNORECASE)
FUNCTION_RE = re.compile(r"^\s*(?:public\s+)?function\s+([A-Za-z_]\w*)\b", re.IGNORECASE)
CHANNEL_RE = re.compile(r"^\s*(?:public\s+)?channel\s+([A-Za-z_]\w*)\s*:\s*(.+?)\s+capacity\b", re.IGNORECASE)
TASK_RE = re.compile(r"^\s*(?:public\s+)?task\s+([A-Za-z_]\w*)\b", re.IGNORECASE)
DECL_LINE_RE = re.compile(
    r"^\s*(?:public\s+)?(?:var\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*(.+?)\s*;?\s*$",
    re.IGNORECASE,
)
PARAM_FRAGMENT_RE = re.compile(r"([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*([^();]+)")
MODE_RE = re.compile(r"^(in\s+out|out|in)\s+", re.IGNORECASE)
CONST_RE = re.compile(r"^constant\s+", re.IGNORECASE)
FOR_LOOP_RE = re.compile(r"^\s*for\s+([A-Za-z_]\w*)\s+in\b", re.IGNORECASE)
SELECT_BINDING_RE = re.compile(r"^\s*when\s+([A-Za-z_]\w*)\s*:\s*([^;]+?)\s+from\b", re.IGNORECASE)
DESTRUCTURE_DECL_RE = re.compile(
    r"^\s*\(([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\)\s*:\s*(.+?)\s*=\s*.+$",
    re.IGNORECASE,
)


class ReferenceSurfaceMigrationError(RuntimeError):
    """Raised when a preview rewrite would need semantic judgement."""


def visible_code(line: str) -> str:
    return "".join(text for kind, text in split_segments(line) if kind == "code")


def code_indent(line: str) -> int:
    code = visible_code(line)
    return len(code) - len(code.lstrip(" "))


def normalize_spaces(value: str) -> str:
    return " ".join(value.split())


def preferred_name(name: str, *, is_reference: bool) -> str:
    if not name:
        return name
    if is_reference:
        return name[0].upper() + name[1:]
    return name.lower()


def type_base_name(type_text: str) -> str:
    cleaned = normalize_spaces(CONST_RE.sub("", MODE_RE.sub("", type_text.strip())))
    match = re.match(r"((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*)", cleaned)
    if match is None:
        return ""
    return match.group(1).split(".")[-1]


def is_access_type(type_text: str, access_types: set[str]) -> bool:
    cleaned = normalize_spaces(CONST_RE.sub("", MODE_RE.sub("", type_text.strip())))
    lowered = cleaned.lower()
    if lowered.startswith("not null access ") or lowered.startswith("access "):
        return True
    base_name = type_base_name(cleaned)
    return base_name != "" and base_name.lower() in access_types


def collect_access_types(text: str) -> set[str]:
    access_types: set[str] = set()
    for line in text.splitlines():
        code = visible_code(line).strip()
        if not code:
            continue
        access_match = TYPE_ACCESS_RE.match(code)
        if access_match:
            access_types.add(access_match.group(1).lower())
    return access_types


def lower_builtin_spelling(segment: str) -> str:
    updated = segment
    for name in BUILTIN_TYPE_NAMES + BUILTIN_FUNCTION_NAMES + BOOLEAN_LITERALS:
        updated = re.sub(rf"\b{re.escape(name)}\b", name, updated, flags=re.IGNORECASE)
    for name in ATTRIBUTE_NAMES:
        updated = re.sub(rf"\.{re.escape(name)}\b", "." + name, updated, flags=re.IGNORECASE)
    return updated


def collect_public_rename_map(paths: list[Path]) -> tuple[dict[str, str], set[str]]:
    access_types: set[str] = set()
    for path in paths:
        access_types.update(collect_access_types(path.read_text(encoding="utf-8")))

    rename_map: dict[str, str] = {}

    def record_global(name: str) -> None:
        lowered = preferred_name(name, is_reference=False)
        prior = rename_map.get(name)
        if prior is not None and prior != lowered:
            raise ReferenceSurfaceMigrationError(f"inconsistent rewrite target for {name!r}")
        rename_map[name] = lowered

    for path in paths:
        for line in path.read_text(encoding="utf-8").splitlines():
            code = visible_code(line).strip()
            if not code:
                continue
            if package_match := PACKAGE_RE.match(code):
                record_global(package_match.group(1))
                continue
            if not code.lower().startswith("public "):
                continue
            if subtype_match := SUBTYPE_RE.match(code):
                record_global(subtype_match.group(1))
                continue
            if channel_match := CHANNEL_RE.match(code):
                record_global(channel_match.group(1))
                continue
            if task_match := TASK_RE.match(code):
                record_global(task_match.group(1))
                continue
            if function_match := FUNCTION_RE.match(code):
                record_global(function_match.group(1))
                continue
            if type_match := TYPE_DECL_RE.match(code):
                record_global(type_match.group(1))
                continue
            if decl_match := DECL_LINE_RE.match(code):
                names_text, type_text = decl_match.groups()
                if is_access_type(type_text, access_types):
                    continue
                for raw_name in (part.strip() for part in names_text.split(",")):
                    record_global(raw_name)
    return (
        {original: renamed for original, renamed in rename_map.items() if original != renamed},
        access_types,
    )


def collect_rename_map(
    text: str,
    *,
    external_renames: dict[str, str] | None = None,
    access_types: set[str] | None = None,
) -> dict[str, str]:
    known_access_types = set(access_types or ())
    known_access_types.update(collect_access_types(text))
    rename_map: dict[str, str] = dict(external_renames or {})
    inside_record = False
    record_indent = 0
    inside_signature = False
    paren_depth = 0

    def record_rename(raw_name: str, *, is_reference: bool | None) -> None:
        if raw_name.lower() in BUILTIN_TYPE_NAMES or raw_name.lower() in BUILTIN_FUNCTION_NAMES:
            return
        if is_reference is None:
            new_name = preferred_name(raw_name, is_reference=False)
        else:
            new_name = preferred_name(raw_name, is_reference=is_reference)
        if raw_name in rename_map and rename_map[raw_name] != new_name:
            raise ReferenceSurfaceMigrationError(
                f"inconsistent rewrite target for {raw_name!r}"
            )
        rename_map[raw_name] = new_name

    for line in text.splitlines():
        code = visible_code(line).strip()
        if not code:
            continue

        line_indent = code_indent(line)
        lowered = code.lower()
        if inside_record and line_indent <= record_indent and not lowered.startswith(("when ", "case ")):
            inside_record = False
        if lowered.startswith("type ") and lowered.endswith(" is record"):
            inside_record = True
            record_indent = line_indent

        type_with_discriminants = TYPE_WITH_DISCRIMINANTS_RE.match(code)
        if type_with_discriminants:
            record_rename(type_with_discriminants.group(1), is_reference=None)
            for match in PARAM_FRAGMENT_RE.finditer(type_with_discriminants.group(2)):
                names_text, _ = match.groups()
                for raw_name in (part.strip() for part in names_text.split(",")):
                    record_rename(raw_name, is_reference=False)
            continue

        package_match = PACKAGE_RE.match(code)
        if package_match:
            record_rename(package_match.group(1), is_reference=None)
            continue

        subtype_match = SUBTYPE_RE.match(code)
        if subtype_match:
            record_rename(subtype_match.group(1), is_reference=None)
            continue

        channel_match = CHANNEL_RE.match(code)
        if channel_match:
            record_rename(channel_match.group(1), is_reference=False)
            continue

        task_match = TASK_RE.match(code)
        if task_match:
            record_rename(task_match.group(1), is_reference=False)
            continue

        type_match = TYPE_DECL_RE.match(code)
        if type_match:
            record_rename(type_match.group(1), is_reference=None)
            continue

        function_match = FUNCTION_RE.match(code)
        if function_match:
            record_rename(function_match.group(1), is_reference=None)
            inside_signature = True
            paren_depth = code.count("(") - code.count(")")
            if "(" in code:
                param_fragment = code.split("(", 1)[1]
                if ")" in param_fragment:
                    param_fragment = param_fragment.split(")", 1)[0]
                for match in PARAM_FRAGMENT_RE.finditer(param_fragment):
                    names_text, type_text = match.groups()
                    is_reference = is_access_type(type_text, known_access_types)
                    for raw_name in (part.strip() for part in names_text.split(",")):
                        record_rename(raw_name, is_reference=is_reference)
            if paren_depth <= 0:
                inside_signature = False
            continue

        if inside_signature:
            for match in PARAM_FRAGMENT_RE.finditer(code):
                names_text, type_text = match.groups()
                is_reference = is_access_type(type_text, known_access_types)
                for raw_name in (part.strip() for part in names_text.split(",")):
                    record_rename(raw_name, is_reference=is_reference)
            paren_depth += code.count("(") - code.count(")")
            if paren_depth <= 0:
                inside_signature = False
            continue

        for_loop_match = FOR_LOOP_RE.match(code)
        if for_loop_match:
            record_rename(for_loop_match.group(1), is_reference=False)
            continue

        select_binding_match = SELECT_BINDING_RE.match(code)
        if select_binding_match:
            record_rename(
                select_binding_match.group(1),
                is_reference=is_access_type(select_binding_match.group(2), known_access_types),
            )
            continue

        destructure_match = DESTRUCTURE_DECL_RE.match(code)
        if destructure_match:
            names_text, _ = destructure_match.groups()
            for raw_name in (part.strip() for part in names_text.split(",")):
                record_rename(raw_name, is_reference=False)
            continue

        if lowered.startswith(
            (
                "if ",
                "else",
                "while ",
                "for ",
                "loop",
                "return",
                "case ",
                "when ",
                "select",
                "delay ",
                "send ",
                "receive ",
                "try_send ",
                "try_receive ",
                "task ",
            )
        ):
            continue

        match = DECL_LINE_RE.match(code)
        if match is None:
            continue

        names_text, type_text = match.groups()
        is_reference = is_access_type(type_text, known_access_types)
        for raw_name in (part.strip() for part in names_text.split(",")):
            record_rename(raw_name, is_reference=is_reference)

    inverse: dict[str, str] = {}
    for original, renamed in rename_map.items():
        prior = inverse.get(renamed)
        if prior is not None and prior != original:
            raise ReferenceSurfaceMigrationError(
                f"rewrites for {prior!r} and {original!r} both target {renamed!r}"
            )
        inverse[renamed] = original
    return {original: renamed for original, renamed in rename_map.items() if original != renamed}


def rewrite_code_segment(segment: str, rename_map: dict[str, str], *, strip_all: bool) -> str:
    updated = lower_builtin_spelling(segment)
    if rename_map:
        pattern = re.compile(
            r"\b(" + "|".join(sorted((re.escape(name) for name in rename_map), key=len, reverse=True)) + r")\b"
        )
        updated = pattern.sub(lambda match: rename_map[match.group(1)], updated)
    if strip_all:
        while True:
            rewritten = re.sub(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.all\b", r"\1", updated)
            if rewritten == updated:
                break
            updated = rewritten
    return updated


def rewrite_safe_source(
    text: str,
    *,
    mode: str,
    external_renames: dict[str, str] | None = None,
    access_types: set[str] | None = None,
) -> str:
    rename_map = (
        collect_rename_map(text, external_renames=external_renames, access_types=access_types)
        if mode in {"reference-signal", "combined"}
        else {}
    )
    strip_all = mode in {"implicit-deref", "combined"}
    rewritten: list[str] = []
    for line in text.splitlines(keepends=True):
        parts: list[str] = []
        for kind, segment in split_segments(line):
            if kind == "code":
                parts.append(rewrite_code_segment(segment, rename_map, strip_all=strip_all))
            else:
                parts.append(segment)
        rewritten.append("".join(parts))
    return "".join(rewritten)


def should_skip_path(path: Path) -> bool:
    return (
        path.name in SKIPPED_REFERENCE_SIGNAL_NEGATIVE_FIXTURES
        and "tests" in path.parts
        and "negative" in path.parts
    )


def iter_safe_paths(roots: list[Path]) -> list[Path]:
    paths: list[Path] = []
    for root in roots:
        if root.is_file():
            if root.suffix == ".safe" and not should_skip_path(root):
                paths.append(root)
            continue
        paths.extend(sorted(path for path in root.rglob("*.safe") if not should_skip_path(path)))
    return sorted(set(paths))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="optional .safe paths or directories to rewrite")
    parser.add_argument(
        "--mode",
        choices=("reference-signal", "implicit-deref", "combined"),
        required=True,
        help="rewrite mode to apply",
    )
    parser.add_argument("--check", action="store_true", help="report files that would change without rewriting")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    roots = [path.resolve() for path in (args.paths or list(DEFAULT_ROOTS))]
    changed: list[Path] = []
    safe_paths = iter_safe_paths(roots)
    public_renames, access_types = collect_public_rename_map(safe_paths)

    for path in safe_paths:
        original = path.read_text(encoding="utf-8")
        try:
            updated = rewrite_safe_source(
                original,
                mode=args.mode,
                external_renames=public_renames,
                access_types=access_types,
            )
        except ReferenceSurfaceMigrationError:
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
