"""Rewrite GNATprove diagnostics into Safe-native source diagnostics."""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Iterable, Sequence

from .proof_diagnostic_catalog import DEFAULT_CATALOG, ProofDiagnosticPattern

DIAG_RE = re.compile(
    r"^(?P<file>[^:]+\.(?:adb|ads)):(?P<line>\d+):(?P<col>\d+): "
    r"(?P<severity>high|medium|low|error|warning|info): (?P<message>.*)$",
    re.IGNORECASE,
)
SAFE_MARKER = "-- safe:"
LINE_MAP_FORMAT = "safe-line-map-v0"


@dataclass(frozen=True)
class LineMapEntry:
    ada_file: str
    ada_line: int
    safe_file: str
    safe_line: int
    safe_col: int


@dataclass(frozen=True)
class LineMapEntries:
    ada_lines: tuple[int, ...]
    entries: tuple[LineMapEntry, ...]


@dataclass(frozen=True)
class GnatproveDiag:
    ada_file: str
    ada_line: int
    ada_col: int
    severity: str
    message: str


@dataclass(frozen=True)
class SafeDiagnostic:
    file: str
    line: int
    column: int
    severity: str
    message: str
    fix: str
    raw_gnatprove_message: str
    ada_file: str
    ada_line: int
    ada_column: int
    stage: str

    def to_json(self) -> dict[str, object]:
        return {
            "file": self.file,
            "line": self.line,
            "column": self.column,
            "severity": self.severity,
            "message": self.message,
            "fix": self.fix,
            "raw_gnatprove_message": self.raw_gnatprove_message,
            "ada_file": self.ada_file,
            "ada_line": self.ada_line,
            "ada_column": self.ada_column,
            "stage": self.stage,
        }


LineMap = dict[str, LineMapEntries]


def parse_gnatprove_diagnostic(line: str) -> GnatproveDiag | None:
    match = DIAG_RE.match(line.strip())
    if match is None:
        return None
    return GnatproveDiag(
        ada_file=match.group("file"),
        ada_line=int(match.group("line")),
        ada_col=int(match.group("col")),
        severity=match.group("severity").lower(),
        message=match.group("message"),
    )


def _entry_payloads_from_text(ada_file: str, text: str) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for ada_line, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        if not stripped.startswith(SAFE_MARKER):
            continue
        payload = stripped[len(SAFE_MARKER) :].strip()
        try:
            safe_file, safe_line, safe_col = payload.rsplit(":", 2)
            safe_line_int = int(safe_line)
            safe_col_int = int(safe_col)
        except ValueError:
            continue
        if safe_line_int <= 0 or safe_col_int <= 0:
            continue
        entries.append(
            {
                "ada_file": ada_file,
                "ada_line": ada_line,
                "safe_file": safe_file,
                "safe_line": safe_line_int,
                "safe_col": safe_col_int,
            }
        )
    return entries


def build_line_map_payload(ada_dir: Path, unit: str) -> dict[str, object]:
    stem = unit.lower()
    entries: list[dict[str, object]] = []
    for suffix in (".ads", ".adb"):
        path = ada_dir / f"{stem}{suffix}"
        if not path.exists():
            continue
        entries.extend(_entry_payloads_from_text(path.name, path.read_text(encoding="utf-8")))
    return {"format": LINE_MAP_FORMAT, "unit": stem, "entries": entries}


def write_line_map_sidecar(ada_dir: Path, unit: str) -> Path:
    stem = unit.lower()
    path = ada_dir / f"{stem}_line_map.json"
    payload = build_line_map_payload(ada_dir, stem)
    path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
    return path


def mirror_with_clauses_into_emitted_unit_files(
    *,
    source_stem: str,
    dependencies: Sequence[str],
    ada_dir: Path,
) -> None:
    if not dependencies:
        return

    changed = False
    lowered_dependencies = [dependency.lower() for dependency in dependencies]
    for suffix in (".ads", ".adb"):
        unit_path = ada_dir / f"{source_stem.lower()}{suffix}"
        if not unit_path.exists():
            continue
        lines = unit_path.read_text(encoding="utf-8").splitlines()
        insertion = 0
        existing_withs: set[str] = set()
        while insertion < len(lines):
            stripped = lines[insertion].strip()
            if not stripped:
                insertion += 1
                continue
            if stripped.lower().startswith("with ") and stripped.endswith(";"):
                existing_withs.add(stripped[5:-1].strip().lower())
                insertion += 1
                continue
            if stripped.lower().startswith("pragma ") and stripped.endswith(";"):
                insertion += 1
                continue
            break

        additions = [
            f"with {dependency};"
            for dependency, lowered in zip(dependencies, lowered_dependencies)
            if lowered not in existing_withs
        ]
        if not additions:
            continue
        unit_path.write_text(
            "\n".join(lines[:insertion] + additions + lines[insertion:]) + "\n",
            encoding="utf-8",
        )
        changed = True

    if changed:
        write_line_map_sidecar(ada_dir, source_stem)


def _entry_from_payload(payload: dict[str, object]) -> LineMapEntry | None:
    try:
        ada_file = str(payload["ada_file"])
        ada_line = int(payload["ada_line"])
        safe_file = str(payload["safe_file"])
        safe_line = int(payload["safe_line"])
        safe_col = int(payload["safe_col"])
    except (KeyError, TypeError, ValueError):
        return None
    return LineMapEntry(
        ada_file=Path(ada_file).name,
        ada_line=ada_line,
        safe_file=safe_file,
        safe_line=safe_line,
        safe_col=safe_col,
    )


def load_all_line_maps(ada_dir: Path) -> LineMap:
    grouped: dict[str, list[LineMapEntry]] = {}
    for path in sorted(ada_dir.glob("*_line_map.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(payload, dict):
            continue
        if payload.get("format") != LINE_MAP_FORMAT:
            continue
        entries = payload.get("entries")
        if not isinstance(entries, list):
            continue
        for raw_entry in entries:
            if not isinstance(raw_entry, dict):
                continue
            entry = _entry_from_payload(raw_entry)
            if entry is None:
                continue
            grouped.setdefault(entry.ada_file, []).append(entry)
    line_maps: LineMap = {}
    for ada_file, entries in grouped.items():
        entries.sort(key=lambda item: item.ada_line)
        line_maps[ada_file] = LineMapEntries(
            ada_lines=tuple(entry.ada_line for entry in entries),
            entries=tuple(entries),
        )
    return line_maps


def lookup_line_map_entry(line_maps: LineMap, ada_file: str, ada_line: int) -> LineMapEntry | None:
    mapped = line_maps.get(Path(ada_file).name)
    if mapped is None:
        return None
    index = bisect_right(mapped.ada_lines, ada_line) - 1
    if index < 0:
        return None
    return mapped.entries[index]


def classify_message(
    message: str,
    catalog: Iterable[ProofDiagnosticPattern] = DEFAULT_CATALOG,
) -> tuple[str, str]:
    for item in catalog:
        if item.gnatprove_re.search(message):
            return item.safe_message, item.fix_guidance
    return (
        "GNATprove could not verify generated proof obligation",
        "Run with `--verbose` to inspect the original GNATprove message.",
    )


def rewrite_diagnostic(
    diag: GnatproveDiag,
    line_maps: LineMap,
    *,
    stage: str,
    catalog: Iterable[ProofDiagnosticPattern] = DEFAULT_CATALOG,
) -> SafeDiagnostic:
    mapped = lookup_line_map_entry(line_maps, diag.ada_file, diag.ada_line)
    message, fix = classify_message(diag.message, catalog)
    if mapped is None:
        ada_file = Path(diag.ada_file).name
        return SafeDiagnostic(
            file=ada_file,
            line=diag.ada_line,
            column=diag.ada_col,
            severity=diag.severity,
            message=message,
            fix=fix,
            raw_gnatprove_message=diag.message,
            ada_file=ada_file,
            ada_line=diag.ada_line,
            ada_column=diag.ada_col,
            stage=stage,
        )
    return SafeDiagnostic(
        file=mapped.safe_file,
        line=mapped.safe_line,
        column=mapped.safe_col,
        severity=diag.severity,
        message=message,
        fix=fix,
        raw_gnatprove_message=diag.message,
        ada_file=Path(diag.ada_file).name,
        ada_line=diag.ada_line,
        ada_column=diag.ada_col,
        stage=stage,
    )


def render_safe_diagnostic(diag: SafeDiagnostic) -> str:
    return (
        f"{diag.file}:{diag.line}:{diag.column}: {diag.severity}: {diag.message}\n"
        f"  fix: {diag.fix}\n"
        f"  raw: {diag.raw_gnatprove_message}"
    )


def rewrite_gnatprove_output(
    raw_output: str,
    ada_dir: Path,
    *,
    stage: str,
    fallback_on_empty: bool = True,
    line_maps: LineMap | None = None,
) -> tuple[str, list[dict[str, object]]]:
    if line_maps is None:
        line_maps = load_all_line_maps(ada_dir)
    diagnostics: list[SafeDiagnostic] = []
    rendered: list[str] = []
    for line in raw_output.splitlines():
        parsed = parse_gnatprove_diagnostic(line)
        if parsed is None or parsed.severity == "info":
            continue
        safe_diag = rewrite_diagnostic(parsed, line_maps, stage=stage)
        diagnostics.append(safe_diag)
        rendered.append(render_safe_diagnostic(safe_diag))
    if not diagnostics:
        if not fallback_on_empty:
            return "", []
        return (
            "proof failed: no Safe-mappable diagnostics found; re-run with --verbose for raw output\n",
            [],
        )
    return "\n".join(rendered) + "\n", [item.to_json() for item in diagnostics]


__all__ = [
    "GnatproveDiag",
    "LineMapEntry",
    "SafeDiagnostic",
    "build_line_map_payload",
    "classify_message",
    "load_all_line_maps",
    "lookup_line_map_entry",
    "mirror_with_clauses_into_emitted_unit_files",
    "parse_gnatprove_diagnostic",
    "render_safe_diagnostic",
    "rewrite_diagnostic",
    "rewrite_gnatprove_output",
    "write_line_map_sidecar",
]
