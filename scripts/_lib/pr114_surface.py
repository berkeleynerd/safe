"""Shared corpus and structural expectations for the PR11.4 syntax cutover."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .harness_common import normalize_source_text, normalized_source_fragments, strip_safe_comments
from .pr09_emit import REPO_ROOT


PR114_POSITIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "positive" / "emitter_surface_proc.safe",
        "coverage_note": "No-result callables now use source-level function syntax while emitted Ada still lowers them to procedures.",
        "source_fragments": (
            "function copy (input : small; output : out small)",
        ),
        "ast_snippets": ('"node_type":"ProcedureSpecification"',),
        "ast_absent_snippets": ('"node_type":"FunctionSpecification"',),
        "typed_snippets": ('"name":"copy"',),
        "mir_snippets": ('"name":"copy"',),
        "safei_snippets": ("function copy",),
        "ada_snippets": (
            "procedure copy",
            "output := local;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_string_param.safe",
        "coverage_note": "The cutover composes with the PR11.2 text surface and keeps signature returns source-only.",
        "source_fragments": (
            "function echo (name : in string) returns string",
        ),
        "ast_snippets": ('"node_type":"FunctionSpecification"',),
        "typed_snippets": ('"identifier":"string"',),
        "mir_snippets": ('"tag":"string"',),
        "safei_snippets": ("function echo", "returns string"),
        "ada_snippets": (
            "function echo(name : string) return string is",
            'return echo ("hello");',
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule4_conditional.safe",
        "coverage_note": "Else-if chains are now source-only and still emit to Ada elsif without changing the lowered conditional shape.",
        "source_fragments": (
            "else if A != null",
            "else if B != null",
        ),
        "typed_snippets": ('"name":"max_of_two"',),
        "mir_snippets": ('"name":"max_of_two"',),
        "safei_snippets": ("function max_of_two",),
        "ada_snippets": (
            "elsif (A /= null) then",
            "elsif (B /= null) then",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule2_slice.safe",
        "coverage_note": "Source ranges now use to for subtype declarations and explicit for-loop ranges while emitted Ada preserves ..",
        "source_fragments": (
            "type index is range 1 to 100;",
            "for i in first to last",
        ),
        "typed_snippets": ('"identifier":"index"',),
        "mir_snippets": ('"name":"last_in_subrange"',),
        "safei_snippets": ("function last_in_subrange",),
        "ada_snippets": (
            "type index is range 1 .. 100;",
            "for i in first .. last loop",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_discriminant_constraints.safe",
        "coverage_note": "The cutover composes with the PR11.3 discriminant surface without perturbing discriminant-aware typed/MIR/emitted structure.",
        "source_fragments": (
            "type packet (active : boolean = true, kind : character = 'A', count : integer = 0) is",
        ),
        "typed_snippets": ('"discriminants":[', '"name":"kind"', '"name":"count"'),
        "mir_snippets": ('"discriminants":[', '"discriminant_constraints":[', '"name":"count"'),
        "safei_snippets": ("packet", "__constraint_packet_active_true_kind_A_count_2"),
        "ada_snippets": (
            "type packet (active : boolean := True; kind : character := 'A'; count : integer := 0) is record",
            "subtype Safe_constraint_packet_active_true_kind_A_count_2 is packet (active => True, kind => 'A', count => 2);",
        ),
    },
)

PR114_NEGATIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_procedure.safe",
        "reason": "source_frontend_error",
        "message": "removed source spelling `procedure` is not allowed in subprogram declarations",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_signature_return.safe",
        "reason": "source_frontend_error",
        "message": "removed source spelling `return` is not allowed in subprogram signatures",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_elsif.safe",
        "reason": "source_frontend_error",
        "message": "removed source spelling `elsif` is not allowed in conditional chains",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr114_legacy_range_dots.safe",
        "reason": "source_frontend_error",
        "message": "removed source spelling `..` is not allowed in source ranges",
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
