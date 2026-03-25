"""Shared corpus and structural expectations for the PR11.5 statement ergonomics gate."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .pr09_emit import REPO_ROOT


PR115_POSITIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_var_basic.safe",
        "coverage_note": "Statement-local `var` declarations lower to the existing local object-declaration surface and allow omitted simple-statement semicolons.",
        "source_fragments": (
            "var Local : Counter = Input",
            "Local = Input return Local",
        ),
        "typed_snippets": ('"name":"Bump"',),
        "mir_snippets": ('"name":"Bump"',),
        "safei_snippets": ("function Bump",),
        "ada_snippets": (
            "Local : Counter := Input;",
            "Local := Input;",
            "return Local;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_compound_terminators.safe",
        "coverage_note": "Compound statement terminators may omit semicolons on later lines without changing the lowered control-flow structure.",
        "source_fragments": (
            "else if Current < 5",
            "for I in 1 to 2",
            "return Current",
        ),
        "typed_snippets": ('"name":"Adjust"',),
        "mir_snippets": ('"name":"Adjust"',),
        "safei_snippets": ("function Adjust",),
        "ada_snippets": (
            "elsif (Current < 5) then",
            "for I in 1 .. 2 loop",
            "Current := 5;",
            "end loop;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_case_terminator.safe",
        "coverage_note": "The final `end case` statement terminator may be omitted while `end when;` arm separators remain explicit.",
        "source_fragments": (
            "when others Result = True; return Result",
        ),
        "typed_snippets": ('"name":"Normalize"',),
        "mir_snippets": ('"name":"Normalize"',),
        "safei_snippets": ("function Normalize",),
        "ada_snippets": (
            "case Input is",
            "when 0 =>",
            "end case;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_legacy_local_decl.safe",
        "coverage_note": "Legacy statement-local `Name : Type` declarations remain admitted in PR11.5; `var` is additive rather than a cutover.",
        "source_fragments": (
            "Current : Counter = 0 Current = 1",
        ),
        "typed_snippets": ('"name":"Build"',),
        "mir_snippets": ('"name":"Build"',),
        "safei_snippets": ("function Build",),
        "ada_snippets": (
            "Current : Counter := 0;",
            "Current := 1;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_declare_terminator.safe",
        "coverage_note": "Statement-local declarations may omit their trailing terminator while still lowering to the same local-object surface.",
        "source_fragments": (
            "var Temp : Counter = 1 return Temp",
        ),
        "typed_snippets": ('"name":"Compute"',),
        "mir_snippets": ('"name":"Compute"',),
        "safei_snippets": ("function Compute",),
        "ada_snippets": (
            "Temp : Counter := 1;",
            "return Temp;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_multiline_return.safe",
        "coverage_note": "Value-returning functions still admit multiline `return` expressions; optional terminators do not turn them into bare returns.",
        "source_fragments": (
            "return Input;",
        ),
        "typed_snippets": ('"name":"Identity"',),
        "mir_snippets": ('"name":"Identity"',),
        "safei_snippets": ("function Identity",),
        "ada_snippets": (
            "return Input;",
        ),
    },
)

PR115_NEGATIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr115_same_line_missing_semicolon.safe",
        "reason": "source_frontend_error",
        "message": "expected `;`",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr115_var_package_item.safe",
        "reason": "source_frontend_error",
        "message": "statement-local `var` declarations are only allowed in executable statement sequences",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr115_var_declare_item.safe",
        "reason": "source_frontend_error",
        "message": "expected `:`",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr115_missing_declaration_semicolon.safe",
        "reason": "source_frontend_error",
        "message": "expected `;`",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr115_missing_case_arm_semicolon.safe",
        "reason": "source_frontend_error",
        "message": "expected `;`",
    },
)

PR115_ROSETTA_READABILITY_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "arithmetic" / "factorial.safe",
        "source_fragments": (
            "var Product : Value = 1",
            "Product = Product * Value (I)",
            "return Product",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "sorting" / "binary_search.safe",
        "source_fragments": (
            "var Lo : Index = Index.First",
            "var Hi : Index = Index.Last",
            "var Mid : Index",
            "else if Arr (Mid) < Key",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "concurrency" / "producer_consumer.safe",
        "source_fragments": (
            "send Data_Ch, 41",
            "var Input : Message",
            "receive Data_Ch, Input",
        ),
    },
)


def positive_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR115_POSITIVE_CASES]


def negative_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR115_NEGATIVE_CASES]


def rosetta_readability_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR115_ROSETTA_READABILITY_CASES]


def corpus_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR115_POSITIVE_CASES]


def negative_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR115_NEGATIVE_CASES]


def rosetta_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR115_ROSETTA_READABILITY_CASES]
