"""Shared corpus and migration expectations for the PR11.6.2 legacy-syntax gate."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .pr09_emit import REPO_ROOT


PR1162_POSITIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "positive" / "constant_shadow_mutable.safe",
        "coverage_note": "Former statement-level `declare` shadowing now uses suite-local `var` without reintroducing Ada block syntax.",
        "source_fragments": (
            "var value : integer = 0;",
            "value = 2;",
        ),
        "forbidden_source_fragments": (
            "declare",
        ),
        "safei_snippets": ("function update_local",),
        "ada_snippets": (
            "value : integer := 0;",
            "value := 2;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "ownership_inout.safe",
        "coverage_note": "No-result helper callables migrate former source `null` statements to explicit bare `return;` without reintroducing removed Ada syntax.",
        "source_fragments": (
            "function consume (Ref : in out payload_ptr)",
            "return;",
        ),
        "forbidden_source_fragments": (
            "null;",
        ),
        "safei_snippets": ("function consume",),
        "ada_snippets": (
            "procedure consume",
            "return;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "constant_task_priority.safe",
        "coverage_note": "Empty nested suites replace source `null` placeholders while emitted Ada may still synthesize `null;` where Ada requires a statement.",
        "source_fragments": (
            "task worker with Priority = worker_priority",
            "loop",
        ),
        "forbidden_source_fragments": (
            "null;",
        ),
        "ada_snippets": (
            "task body worker is",
            "null;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "ownership_early_return.safe",
        "coverage_note": "Early return cleanup remains covered after removing explicit inner `declare` blocks from the admitted source surface.",
        "source_fragments": (
            "Outer : payload_ptr = new ((value = 7) as payload);",
            "Inner : payload_ptr = new ((value = 9) as payload);",
            "return Outer.value;",
        ),
        "forbidden_source_fragments": (
            "declare",
        ),
        "safei_snippets": ("function read_and_exit",),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule4_linked_list.safe",
        "coverage_note": "Borrow/observe traversal cases now use statement-local `var` instead of explicit `declare` blocks.",
        "source_fragments": (
            "var Current : access constant node = Head.access;",
            "while Current != null",
        ),
        "forbidden_source_fragments": (
            "declare",
        ),
        "safei_snippets": ("function last_value", "function has_tail"),
    },
    {
        "source": REPO_ROOT / "tests" / "interfaces" / "provider_transitive_channel.safe",
        "coverage_note": "Concurrency helpers migrate former `declare`-scoped receive temporaries to suite-local `var` declarations.",
        "source_fragments": (
            "var item : message = 0;",
            "receive data_ch, item;",
        ),
        "forbidden_source_fragments": (
            "declare",
        ),
        "safei_snippets": ("function push",),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr1162_empty_subprogram_body_followed_by_sibling.safe",
        "coverage_note": "Empty subprogram bodies remain legal after source `null` removal and must not consume later sibling package items.",
        "source_fragments": (
            "function skip",
            "function value returns integer",
        ),
        "forbidden_source_fragments": (
            "null;",
        ),
        "safei_snippets": ("function skip", "function value"),
        "ada_snippets": (
            "procedure skip",
            "function value return integer",
            "null;",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr1162_empty_select_delay_arm.safe",
        "coverage_note": "Empty select delay arms are emitted as Ada `null;` suites instead of producing invalid empty Ada blocks.",
        "source_fragments": (
            "select",
            "delay 0.05",
        ),
        "forbidden_source_fragments": (
            "null;",
        ),
        "safei_snippets": ("task poller",),
        "ada_snippets": (
            "if not Select_Done then",
            "null;",
        ),
    },
)

PR1162_NEGATIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr1162_removed_declare.safe",
        "reason": "source_frontend_error",
        "message": "removed source construct `declare block` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr1162_removed_declare_expression.safe",
        "reason": "source_frontend_error",
        "message": "removed source construct `declare_expression` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr1162_removed_null_statement.safe",
        "reason": "source_frontend_error",
        "message": "removed source construct `null statement` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr1162_removed_named_exit.safe",
        "reason": "source_frontend_error",
        "message": "removed source construct `named exit` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr1162_removed_goto.safe",
        "reason": "source_frontend_error",
        "message": "removed source construct `goto` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr1162_removed_aliased.safe",
        "reason": "source_frontend_error",
        "message": "removed source spelling `aliased` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr1162_removed_representation_clause.safe",
        "reason": "source_frontend_error",
        "message": "removed source construct `representation clause` is not allowed",
    },
)

PR1162_MIGRATION_EXAMPLES: tuple[dict[str, Any], ...] = (
    {
        "name": "declare_tail_hoist",
        "legacy_source": """package demo

   function build returns integer

      declare
         temp : integer = 1;
      begin
         return temp;
      end;
""",
        "migrated_fragments": (
            "var temp : integer = 1;",
            "return temp;",
        ),
        "forbidden_fragments": (
            "declare",
            "begin",
            "end;",
        ),
    },
    {
        "name": "null_statement_removal",
        "legacy_source": """package demo

   function consume

      null;
""",
        "migrated_fragments": (
            "function consume",
        ),
        "forbidden_fragments": (
            "null;",
        ),
    },
)


def positive_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR1162_POSITIVE_CASES]


def negative_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR1162_NEGATIVE_CASES]


def migration_examples() -> list[dict[str, Any]]:
    return [dict(item) for item in PR1162_MIGRATION_EXAMPLES]


def corpus_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR1162_POSITIVE_CASES]


def negative_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR1162_NEGATIVE_CASES]
