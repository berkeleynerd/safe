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
            "var local : counter = input",
            "local = input return local",
        ),
        "typed_snippets": ('"name":"bump"',),
        "mir_snippets": ('"name":"bump"',),
        "safei_snippets": ("function bump",),
        "ada_snippets": (
            "local : counter := input;",
            "local := input;",
            "return local;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_compound_terminators.safe",
        "coverage_note": "Compound statement terminators may omit semicolons on later lines without changing the lowered control-flow structure.",
        "source_fragments": (
            "else if current < 5",
            "for i in 1 to 2",
            "return current",
        ),
        "typed_snippets": ('"name":"adjust"',),
        "mir_snippets": ('"name":"adjust"',),
        "safei_snippets": ("function adjust",),
        "ada_snippets": (
            "elsif (current < 5) then",
            "for i in 1 .. 2 loop",
            "current := 5;",
            "end loop;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_case_terminator.safe",
        "coverage_note": "The final `end case` statement terminator may be omitted while `end when;` arm separators remain explicit.",
        "source_fragments": (
            "when others result = true; return result",
        ),
        "typed_snippets": ('"name":"normalize"',),
        "mir_snippets": ('"name":"normalize"',),
        "safei_snippets": ("function normalize",),
        "ada_snippets": (
            "case input is",
            "when 0 =>",
            "end case;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_legacy_local_decl.safe",
        "coverage_note": "Legacy statement-local `Name : Type` declarations remain admitted in PR11.5; `var` is additive rather than a cutover.",
        "source_fragments": (
            "current : counter = 0 current = 1",
        ),
        "typed_snippets": ('"name":"build"',),
        "mir_snippets": ('"name":"build"',),
        "safei_snippets": ("function build",),
        "ada_snippets": (
            "current : counter := 0;",
            "current := 1;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_declare_terminator.safe",
        "coverage_note": "Statement-local declarations may omit their trailing terminator while still lowering to the same local-object surface.",
        "source_fragments": (
            "var temp : counter = 1 return temp",
        ),
        "typed_snippets": ('"name":"compute"',),
        "mir_snippets": ('"name":"compute"',),
        "safei_snippets": ("function compute",),
        "ada_snippets": (
            "temp : counter := 1;",
            "return temp;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_multiline_return.safe",
        "coverage_note": "Value-returning functions still admit multiline `return` expressions; optional terminators do not turn them into bare returns.",
        "source_fragments": (
            "input;",
        ),
        "typed_snippets": ('"name":"identity"',),
        "mir_snippets": ('"name":"identity"',),
        "safei_snippets": ("function identity",),
        "ada_snippets": (
            "return input;",
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
            "var product : value = 1",
            "product = product * value (i)",
            "return product",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "sorting" / "binary_search.safe",
        "source_fragments": (
            "var lo : index = index.first",
            "var hi : index = index.last",
            "var mid : index",
            "else if arr (mid) < key",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "concurrency" / "producer_consumer.safe",
        "source_fragments": (
            "send data_ch, 41",
            "var input : message",
            "receive data_ch, input",
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
