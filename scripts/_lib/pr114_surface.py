"""Shared corpus and structural expectations for the PR11.4 syntax cutover."""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path
from typing import Any

from .pr09_emit import REPO_ROOT


PR114_POSITIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe",
        "coverage_note": "No-result callables now use source-level function syntax while emitted Ada still lowers them to procedures.",
        "source_fragments": (
            "function Copy (Input : Small; Output : out Small) is",
        ),
        "ast_snippets": ('"node_type":"ProcedureSpecification"',),
        "ast_absent_snippets": ('"node_type":"FunctionSpecification"',),
        "typed_snippets": ('"name":"Copy"',),
        "mir_snippets": ('"name":"Copy"',),
        "safei_snippets": ("function Copy",),
        "ada_snippets": (
            "procedure Copy",
            "Output := Local;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_string_param.safe",
        "coverage_note": "The cutover composes with the PR11.2 text surface and keeps signature returns source-only.",
        "source_fragments": (
            "function Echo (Name : in String) returns String is",
        ),
        "ast_snippets": ('"node_type":"FunctionSpecification"',),
        "typed_snippets": ('"identifier":"String"',),
        "mir_snippets": ('"tag":"string"',),
        "safei_snippets": ("function Echo", "returns String"),
        "ada_snippets": (
            "function Echo(Name : String) return String is",
            'return Echo ("hello");',
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
        "coverage_note": "Else-if chains are now source-only and still emit to Ada elsif without changing the lowered conditional shape.",
        "source_fragments": (
            "else if A != null then",
            "else if B != null then",
        ),
        "typed_snippets": ('"name":"Max_Of_Two"',),
        "mir_snippets": ('"name":"Max_Of_Two"',),
        "safei_snippets": ("function Max_Of_Two",),
        "ada_snippets": (
            "elsif (A /= null) then",
            "elsif (B /= null) then",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule2_slice.safe",
        "coverage_note": "Source ranges now use to for subtype declarations and explicit for-loop ranges while emitted Ada preserves ..",
        "source_fragments": (
            "type Index is range 1 to 100;",
            "for I in First to Last loop",
        ),
        "typed_snippets": ('"identifier":"Index"',),
        "mir_snippets": ('"name":"Last_In_Subrange"',),
        "safei_snippets": ("function Last_In_Subrange",),
        "ada_snippets": (
            "type Index is range 1 .. 100;",
            "for I in First .. Last loop",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_discriminant_constraints.safe",
        "coverage_note": "The cutover composes with the PR11.3 discriminant surface without perturbing discriminant-aware typed/MIR/emitted structure.",
        "source_fragments": (
            "type Packet (Active : Boolean = True, Kind : Character = 'A', Count : Integer = 0) is",
        ),
        "typed_snippets": ('"discriminants":[', '"name":"Kind"', '"name":"Count"'),
        "mir_snippets": ('"discriminants":[', '"discriminant_constraints":[', '"name":"Count"'),
        "safei_snippets": ("Packet", "__constraint_Packet_Active_true_Kind_A_Count_2"),
        "ada_snippets": (
            "type Packet (Active : Boolean := True; Kind : Character := 'A'; Count : Integer := 0) is record",
            "subtype Safe_constraint_Packet_Active_true_Kind_A_Count_2 is Packet (Active => True, Kind => 'A', Count => 2);",
        ),
    },
)

PR114_NEGATIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_procedure.safe",
        "reason": "source_frontend_error",
        "message": "legacy `procedure` is not allowed in subprogram declarations; use `function`",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_signature_return.safe",
        "reason": "source_frontend_error",
        "message": "legacy `return` is not allowed in subprogram signatures; use `returns`",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_elsif.safe",
        "reason": "source_frontend_error",
        "message": "legacy `elsif` is not allowed in conditional chains; use `else if`",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_range_dots.safe",
        "reason": "source_frontend_error",
        "message": "legacy `..` is not allowed in source ranges; use `to`",
    },
)


def positive_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR114_POSITIVE_CASES]


def negative_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR114_NEGATIVE_CASES]


def corpus_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR114_POSITIVE_CASES]


def negative_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR114_NEGATIVE_CASES]


def strip_safe_comments(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        marker = line.find("--")
        lines.append(line if marker < 0 else line[:marker])
    return "\n".join(lines)


def normalize_source_text(text: str) -> str:
    return " ".join(text.split())


def normalized_source_fragments(item: dict[str, Any]) -> Sequence[str]:
    return tuple(normalize_source_text(fragment) for fragment in item["source_fragments"])
