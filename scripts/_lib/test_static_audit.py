"""Static audit guards for compiler-internal fail-closed walkers."""

from __future__ import annotations

from dataclasses import dataclass
import re
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _lib.test_harness import REPO_ROOT, RunCounts, record_result


@dataclass(frozen=True)
class AuditedCase:
    label: str
    path: Path
    anchor: str
    end_anchor: str
    case_expr: str
    allow_silent_others: bool = False
    reason: str = ""
    inline_case: bool = False


SRC = REPO_ROOT / "compiler_impl" / "src"

AUDITED_WALKER_CASES: tuple[AuditedCase, ...] = (
    AuditedCase(
        "emit-statements.invalidate-mutated-call-actual-lengths.visit",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Invalidate_Mutated_Call_Actual_Lengths",
        "end Invalidate_Mutated_Call_Actual_Lengths;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-statements.expr-uses-name",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Expr_Uses_Name",
        "end Expr_Uses_Name;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit-statements.statement-uses-name",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Statement_Uses_Name",
        "end Statement_Uses_Name;",
        "Statement.Kind",
    ),
    AuditedCase(
        "emit-statements.statement-blocks-overwrite-scan",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Statement_Blocks_Overwrite_Scan",
        "end Statement_Blocks_Overwrite_Scan;",
        "Statement.Kind",
    ),
    AuditedCase(
        "emit-statements.statement-overwrites-name-before-read",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Statement_Overwrites_Name_Before_Read",
        "end Statement_Overwrites_Name_Before_Read;",
        "Statement.Kind",
    ),
    AuditedCase(
        "emit-statements.walk-statement-structure.statement",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Walk_Statement_Structure",
        "end Walk_Statement_Structure;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-statements.walk-statement-structure.select-arm",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Walk_Statement_Structure",
        "end Walk_Statement_Structure;",
        "Arm.Kind",
    ),
    AuditedCase(
        "emit-statements.statements-declare-name",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Statements_Declare_Name",
        "end Statements_Declare_Name;",
        "Nested.Kind",
    ),
    AuditedCase(
        "emit-statements.expr-mutating-call-count",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Expr_Mutating_Call_Count",
        "end Expr_Mutating_Call_Count;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit-statements.statement-write-count",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Statement_Write_Count",
        "end Statement_Write_Count;",
        "Stmt.Kind",
    ),
    AuditedCase(
        "emit-statements.counted-while-expr-contains-call",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Expr_Contains_Call",
        "end Expr_Contains_Call;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit-statements.counted-while-analyze-statement",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Append_Counted_While_Lower_Bound_Invariant",
        "end Append_Counted_While_Lower_Bound_Invariant;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-statements.counted-while-select-arm",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Append_Counted_While_Lower_Bound_Invariant",
        "end Append_Counted_While_Lower_Bound_Invariant;",
        "Arm.Kind",
    ),
    AuditedCase(
        "emit-statements.shared-condition-needs-snapshot",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "function Expr_Needs_Shared_Condition_Snapshot",
        "end Expr_Needs_Shared_Condition_Snapshot;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit-statements.shared-condition-collect-snapshots",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Collect_Shared_Condition_Snapshots",
        "end Collect_Shared_Condition_Snapshots;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit-statements.analyze-accumulator-statement",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Analyze_Accumulator_Statement",
        "end Analyze_Accumulator_Statement;",
        "Stmt.Kind",
    ),
    AuditedCase(
        "emit-statements.collect-growable-accumulators",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Collect_Growable_Accumulators",
        "end Collect_Growable_Accumulators;",
        "Nested.Kind",
    ),
    AuditedCase(
        "emit-statements.analyze-string-growth-statement",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Analyze_String_Growth_Statement",
        "end Analyze_String_Growth_Statement;",
        "Stmt.Kind",
    ),
    AuditedCase(
        "emit-statements.collect-string-growth-accumulators",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Collect_String_Growth_Accumulators",
        "end Collect_String_Growth_Accumulators;",
        "Nested.Kind",
    ),
    AuditedCase(
        "emit-statements.collect-string-accumulators",
        SRC / "safe_frontend-ada_emit-statements.adb",
        "procedure Collect_String_Accumulators",
        "end Collect_String_Accumulators;",
        "Nested.Kind",
    ),
    AuditedCase(
        "emit-proofs.subprogram-uses-global-name.statements",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Subprogram_Uses_Global_Name",
        "end Subprogram_Uses_Global_Name;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-proofs.subprogram-uses-global-name.select-arm",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Subprogram_Uses_Global_Name",
        "end Subprogram_Uses_Global_Name;",
        "Arm.Kind",
    ),
    AuditedCase(
        "emit-proofs.render-global-aspect.expr",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Render_Global_Aspect",
        "end Render_Global_Aspect;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit-proofs.render-global-aspect.statements",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Render_Global_Aspect",
        "end Render_Global_Aspect;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-proofs.render-global-aspect.select-arm",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Render_Global_Aspect",
        "end Render_Global_Aspect;",
        "Arm.Kind",
    ),
    AuditedCase(
        "emit-proofs.access-param-precondition.expr-special-case",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Render_Access_Param_Precondition",
        "end Render_Access_Param_Precondition;",
        "Expr.Kind",
        allow_silent_others=True,
        reason="default is followed by generic child traversal for every expression field",
    ),
    AuditedCase(
        "emit-proofs.access-param-precondition.statements",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Render_Access_Param_Precondition",
        "end Render_Access_Param_Precondition;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-proofs.access-param-precondition.select-arm",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Render_Access_Param_Precondition",
        "end Render_Access_Param_Precondition;",
        "Arm.Kind",
    ),
    AuditedCase(
        "emit-proofs.recursive-variant.expr",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Recursive_Variant_Image",
        "end Recursive_Variant_Image;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit-proofs.recursive-variant.statements",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Recursive_Variant_Image",
        "end Recursive_Variant_Image;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-proofs.recursive-variant.select-arm-expression",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Recursive_Variant_Image",
        "end Recursive_Variant_Image;",
        "Arm.Kind",
        inline_case=True,
    ),
    AuditedCase(
        "emit-proofs.structural-traversal-accumulator.statements",
        SRC / "safe_frontend-ada_emit-proofs.adb",
        "function Render_Structural_Accumulator return Boolean",
        "end Render_Structural_Accumulator;",
        "Item.Kind",
        allow_silent_others=True,
        reason="return False disables structural traversal lowering",
    ),
    AuditedCase(
        "emit.public-shared-helper.expr-local",
        SRC / "safe_frontend-ada_emit.adb",
        "function Decl_Uses_Shared_Object_Name",
        "end Decl_Uses_Shared_Object_Name;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit.public-shared-helper.expr",
        SRC / "safe_frontend-ada_emit.adb",
        "function Expr_Uses_Public_Shared_Helper",
        "end Expr_Uses_Public_Shared_Helper;",
        "Expr.Kind",
    ),
    AuditedCase(
        "emit.public-shared-helper.statements",
        SRC / "safe_frontend-ada_emit.adb",
        "function Statements_Use_Public_Shared_Helper",
        "end Statements_Use_Public_Shared_Helper;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit.public-shared-helper.select-arm",
        SRC / "safe_frontend-ada_emit.adb",
        "function Statements_Use_Public_Shared_Helper",
        "end Statements_Use_Public_Shared_Helper;",
        "Arm.Kind",
    ),
    AuditedCase(
        "emit-internal.statement-contains-exit",
        SRC / "safe_frontend-ada_emit-internal.adb",
        "function Statement_Contains_Exit",
        "end Statement_Contains_Exit;",
        "Item.Kind",
    ),
    AuditedCase(
        "emit-internal.statement-falls-through",
        SRC / "safe_frontend-ada_emit-internal.adb",
        "function Statement_Falls_Through",
        "end Statement_Falls_Through;",
        "Item.Kind",
    ),
    AuditedCase(
        "mir-bronze.walk-expr",
        SRC / "safe_frontend-mir_bronze.adb",
        "procedure Walk_Expr",
        "end Walk_Expr;",
        "Expr.Kind",
    ),
    AuditedCase(
        "mir-bronze.summary-for-op",
        SRC / "safe_frontend-mir_bronze.adb",
        "function Summary_For",
        "end Summary_For;",
        "Op.Kind",
    ),
    AuditedCase(
        "mir-bronze.summary-for-terminator",
        SRC / "safe_frontend-mir_bronze.adb",
        "function Summary_For",
        "end Summary_For;",
        "Block.Terminator.Kind",
    ),
    AuditedCase(
        "mir-bronze.summary-for-select-arm",
        SRC / "safe_frontend-mir_bronze.adb",
        "function Summary_For",
        "end Summary_For;",
        "Arm.Kind",
    ),
)

CASE_START_RE = re.compile(r"^\s*case\b.*\bis\b", re.IGNORECASE)
END_CASE_RE = re.compile(r"\bend\s+case\s*;", re.IGNORECASE)
WHEN_RE = re.compile(r"^\s*when\b", re.IGNORECASE)
WHEN_OTHERS_RE = re.compile(
    r"^\s*when\s+(?:[A-Za-z][A-Za-z0-9_]*\s*:\s*)?others\s*=>",
    re.IGNORECASE,
)
SILENT_DEFAULT_RE = re.compile(
    r"(\bnull\s*;|\breturn\s+False\s*;|\breturn\s+0\s*;|Empty_Vector)",
    re.IGNORECASE,
)
WHEN_OTHERS_OK_MARKER = "when-others-ok:"

PARSER_RESOLVER_WHEN_OTHERS_MARKER_AUDIT_PATHS: tuple[Path, ...] = tuple(
    sorted(
        path
        for path in SRC.glob("safe_frontend-check_*.adb")
        if path.name.startswith(
            ("safe_frontend-check_parse", "safe_frontend-check_resolve")
        )
    )
)

WHEN_OTHERS_MARKER_AUDIT_PATHS: tuple[Path, ...] = (
    *PARSER_RESOLVER_WHEN_OTHERS_MARKER_AUDIT_PATHS,
    SRC / "safe_frontend-ada_emit.adb",
    SRC / "safe_frontend-ada_emit-expressions.adb",
    SRC / "safe_frontend-ada_emit-internal.adb",
    SRC / "safe_frontend-ada_emit-proofs.adb",
    SRC / "safe_frontend-ada_emit-statements.adb",
    SRC / "safe_frontend-ada_emit-types.adb",
    SRC / "safe_frontend-check_emit.adb",
    SRC / "safe_frontend-check_lower.adb",
    SRC / "safe_frontend-driver.adb",
    SRC / "safe_frontend-json.adb",
    SRC / "safe_frontend-mir_analyze.adb",
    SRC / "safe_frontend-mir_json.adb",
    SRC / "safe_frontend-mir_validate.adb",
    SRC / "safe_frontend-mir_write.adb",
)


def _strip_comment(line: str) -> str:
    return line.split("--", 1)[0]


def _line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _case_pattern(entry: AuditedCase) -> re.Pattern[str]:
    case_expr = entry.case_expr
    escaped = re.escape(case_expr).replace(r"\ ", r"\s+")
    prefix = r"\bcase\s+" if entry.inline_case else r"^\s*case\s+"
    return re.compile(prefix + escaped + r"\s+is\b", re.MULTILINE)


def _find_case_block(entry: AuditedCase) -> tuple[int, list[str]]:
    text = entry.path.read_text(encoding="utf-8")
    anchor_offset = text.find(entry.anchor)
    if anchor_offset < 0:
        raise ValueError(f"missing anchor {entry.anchor!r}")

    end_offset = text.find(entry.end_anchor, anchor_offset)
    if end_offset < 0:
        raise ValueError(f"missing end anchor {entry.end_anchor!r}")

    body = text[anchor_offset:end_offset]
    match = _case_pattern(entry).search(body)
    if match is None:
        raise ValueError(
            f"missing case block for {entry.case_expr!r} after anchor {entry.anchor!r}"
        )

    case_offset = anchor_offset + match.start()
    case_line = _line_number(text, case_offset)
    prefix = body[: match.start()]
    start_index = prefix.count("\n")
    body_lines = body.splitlines()

    if entry.inline_case:
        inline_lines: list[str] = []
        for line in body_lines[start_index:]:
            inline_lines.append(line)
            # Inline audited case blocks are currently single-expression arms.
            # Revisit this terminator if inline arms grow nested statement calls.
            if "));" in line or ");" in line:
                break
        return case_line, inline_lines

    block_lines: list[str] = []
    depth = 0

    for line in body_lines[start_index:]:
        code = _strip_comment(line)
        if CASE_START_RE.search(code):
            depth += 1
        block_lines.append(line)
        if END_CASE_RE.search(code):
            depth -= 1
            if depth == 0:
                return case_line, block_lines

    raise ValueError(f"unterminated case block for {entry.case_expr!r}")


def _others_segments(block_lines: list[str]) -> list[str]:
    segments: list[str] = []
    for index, line in enumerate(block_lines):
        if not WHEN_OTHERS_RE.search(_strip_comment(line)):
            continue

        parts = [_strip_comment(line)]
        for next_line in block_lines[index + 1 :]:
            code = _strip_comment(next_line)
            if WHEN_RE.search(code) or END_CASE_RE.search(code):
                break
            parts.append(code)
        segments.append("\n".join(parts))
    return segments


def run_static_audit_case(entry: AuditedCase) -> tuple[bool, str]:
    try:
        case_line, block_lines = _find_case_block(entry)
    except ValueError as exc:
        return False, str(exc)

    silent_segments = [
        segment
        for segment in _others_segments(block_lines)
        if SILENT_DEFAULT_RE.search(segment)
    ]
    if silent_segments and not entry.allow_silent_others:
        rel = entry.path.relative_to(REPO_ROOT)
        return (
            False,
            f"{rel}:{case_line}: audited {entry.case_expr} block has silent "
            "`when others` fall-through",
        )

    return True, ""


def _first_nonblank_line_after(lines: list[str], index: int) -> tuple[int, str] | None:
    for marker_index in range(index + 1, len(lines)):
        if lines[marker_index].strip():
            return marker_index, lines[marker_index]
    return None


def _comment_payload(line: str) -> str | None:
    stripped = line.strip()
    if not stripped.startswith("--"):
        return None
    return stripped[2:].lstrip()


def run_when_others_marker_case(path: Path) -> tuple[bool, str]:
    """Require retained catch-alls to use a next-line rationale marker.

    Expected form:
        when others =>
           --  when-others-ok: <rationale>
    or:
        when Error : others =>
           --  when-others-ok: <rationale>
    The marker must appear on the following nonblank line; inline arrow-line
    markers are stripped as Ada comments before validation.
    """
    failures: list[str] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    rel = path.relative_to(REPO_ROOT)

    for index, line in enumerate(lines):
        code = _strip_comment(line)
        if not WHEN_OTHERS_RE.search(code):
            continue

        after_arrow = code.split("=>", 1)[1].strip()
        line_no = index + 1
        if after_arrow:
            failures.append(
                f"{rel}:{line_no}: retained catch-all must be multiline "
                f"and start with {WHEN_OTHERS_OK_MARKER!r}"
            )
            continue

        marker_line = _first_nonblank_line_after(lines, index)
        marker_payload = (
            _comment_payload(marker_line[1]) if marker_line is not None else None
        )
        if marker_payload is None or not marker_payload.startswith(
            WHEN_OTHERS_OK_MARKER
        ):
            failures.append(
                f"{rel}:{line_no}: retained catch-all lacks "
                f"{WHEN_OTHERS_OK_MARKER!r} rationale marker"
            )

    if failures:
        return False, "\n".join(failures)
    return True, ""


def run_when_others_regex_self_check() -> tuple[bool, str]:
    positives = [
        "when others =>",
        "  when others =>",
        "when Error : others =>",
        "  when E : others =>",
    ]
    negatives = [
        'Append_Line (Buffer, "when others =>", Depth);',
        'X := "when Error : others =>";',
        "-- when others => null;",
        "when_others_handler",
    ]

    failures: list[str] = []
    for item in positives:
        if not WHEN_OTHERS_RE.search(_strip_comment(item)):
            failures.append(f"should match retained catch-all: {item!r}")
    for item in negatives:
        if WHEN_OTHERS_RE.search(_strip_comment(item)):
            failures.append(f"should ignore non-arm text: {item!r}")

    if failures:
        return False, "\n".join(failures)
    return True, ""


def run_static_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    for entry in AUDITED_WALKER_CASES:
        passed += record_result(
            failures,
            f"static-audit:{entry.label}",
            run_static_audit_case(entry),
        )
    if len(PARSER_RESOLVER_WHEN_OTHERS_MARKER_AUDIT_PATHS) < 2:
        passed += record_result(
            failures,
            "static-audit:when-others-ok",
            (
                False,
                "expected at least 2 scoped parser/resolver sources, "
                f"found {len(PARSER_RESOLVER_WHEN_OTHERS_MARKER_AUDIT_PATHS)}",
            ),
        )
    passed += record_result(
        failures,
        "static-audit:when-others-regex",
        run_when_others_regex_self_check(),
    )
    for path in WHEN_OTHERS_MARKER_AUDIT_PATHS:
        if not path.exists():
            passed += record_result(
                failures,
                f"static-audit:when-others-ok:{path.relative_to(REPO_ROOT)}",
                (False, f"missing audited marker path: {path.relative_to(REPO_ROOT)}"),
            )
            continue
        passed += record_result(
            failures,
            f"static-audit:when-others-ok:{path.relative_to(REPO_ROOT)}",
            run_when_others_marker_case(path),
        )
    return passed, 0, failures


if __name__ == "__main__":
    ok, _skipped, failures = run_static_audit_checks()
    if failures:
        print(f"{ok} passed, {len(failures)} failed")
        for label, detail in failures:
            print(f" - {label}: {detail}")
        raise SystemExit(1)
    print(f"{ok} passed, 0 failed")
