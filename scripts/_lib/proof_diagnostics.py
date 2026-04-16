"""Rewrite GNATprove diagnostics into Safe-native source diagnostics."""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Iterable

from .proof_diagnostic_catalog import DEFAULT_CATALOG, ProofDiagnosticPattern

DIAG_RE = re.compile(
    r"^(?P<file>.+\.(?:adb|ads)):(?P<line>\d+):(?P<col>\d+): "
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


LineMap = dict[str, list[LineMapEntry]]


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
        marker = line.find(SAFE_MARKER)
        if marker < 0:
            continue
        payload = line[marker + len(SAFE_MARKER) :].strip()
        try:
            safe_file, safe_line, safe_col = payload.rsplit(":", 2)
            safe_line_int = int(safe_line)
            safe_col_int = int(safe_col)
        except ValueError:
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
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


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
    line_maps: LineMap = {}
    for path in sorted(ada_dir.glob("*_line_map.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
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
            line_maps.setdefault(entry.ada_file, []).append(entry)
    for entries in line_maps.values():
        entries.sort(key=lambda item: item.ada_line)
    return line_maps


def lookup_line_map_entry(line_maps: LineMap, ada_file: str, ada_line: int) -> LineMapEntry | None:
    entries = line_maps.get(Path(ada_file).name)
    if not entries:
        return None
    lines = [entry.ada_line for entry in entries]
    index = bisect_right(lines, ada_line) - 1
    if index < 0:
        return None
    return entries[index]


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
) -> tuple[str, list[dict[str, object]]]:
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
    "parse_gnatprove_diagnostic",
    "render_safe_diagnostic",
    "rewrite_diagnostic",
    "rewrite_gnatprove_output",
    "write_line_map_sidecar",
]
