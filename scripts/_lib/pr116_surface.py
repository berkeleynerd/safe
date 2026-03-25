"""Shared corpus and migration expectations for the PR11.6 whitespace gate."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .pr09_emit import REPO_ROOT


PR116_POSITIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr116_bare_return.safe",
        "coverage_note": "No-return subprograms may begin their indented suite with a bare `return;` without being mistaken for a multiline return-type continuation.",
        "source_fragments": (
            "function exit_early",
            "return;",
        ),
        "forbidden_source_fragments": (
            "returns",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr115_compound_terminators.safe",
        "coverage_note": "Executable control-flow blocks use indentation rather than `then` / `end if` / `end loop` while preserving the lowered control-flow shape.",
        "source_fragments": (
            "function adjust (input : count) returns count",
            "if current > 5",
            "else if current < 5",
            "for i in 1 to 2",
        ),
        "forbidden_source_fragments": (
            "then",
            "end if",
            "end loop",
            "begin",
        ),
        "typed_snippets": ('"name":"adjust"',),
        "safei_snippets": ("function adjust",),
        "ada_snippets": (
            "elsif (current < 5) then",
            "for i in 1 .. 2 loop",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
        "coverage_note": "Whitespace `while` blocks stay compatible with the existing PR10.2 and PR10.3 proof/evaluation surface.",
        "source_fragments": (
            "while lo <= hi",
            "else if arr (mid) < key",
        ),
        "forbidden_source_fragments": (
            "then",
            "end loop",
        ),
        "typed_snippets": ('"name":"search"',),
        "safei_snippets": ("function search",),
        "ada_snippets": (
            "while (lo <= hi) loop",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_character_case.safe",
        "coverage_note": "Whitespace `case` statements use indented `when` suites with no `is`, `then`, or closing delimiters.",
        "source_fragments": (
            "case grade",
            "when 'A'",
            "when others",
        ),
        "forbidden_source_fragments": (
            "then",
            "end case",
            "end when",
        ),
        "typed_snippets": ('"name":"grade_message"',),
        "safei_snippets": ("function grade_message",),
        "ada_snippets": (
            "case grade is",
            "when others =>",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_variant_guard.safe",
        "coverage_note": "Record field lists and variant arms are indentation-structured with no `end record` / `end case` closers.",
        "source_fragments": (
            "type packet (kind : character = 'A') is",
            "record",
            "case kind",
            "when others",
        ),
        "forbidden_source_fragments": (
            "end record",
            "end case",
        ),
        "typed_snippets": ('"name":"read_alpha"',),
        "safei_snippets": ("function read_alpha",),
        "ada_snippets": (
            "type packet",
            "case kind is",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
        "coverage_note": "Task and `select` bodies use indentation-defined suites while preserving the admitted concurrency surface.",
        "source_fragments": (
            "task poller with Priority = 10",
            "select",
            "when item : message from msg_ch",
            "or",
            "delay 0.05",
        ),
        "forbidden_source_fragments": (
            "then",
            "end select",
        ),
    },
)

PR116_NEGATIVE_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr116_tab_indent.safe",
        "reason": "source_frontend_error",
        "message": "tabs are not allowed in indentation",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr116_bad_indent_step.safe",
        "reason": "source_frontend_error",
        "message": "indentation must use 3-space steps",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr116_legacy_end_if.safe",
        "reason": "source_frontend_error",
        "message": "legacy block delimiter `end` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr116_legacy_begin.safe",
        "reason": "source_frontend_error",
        "message": "legacy block delimiter `begin` is not allowed",
    },
    {
        "source": REPO_ROOT / "tests" / "negative" / "neg_pr116_mixed_named_end.safe",
        "reason": "source_frontend_error",
        "message": "legacy block delimiter `end` is not allowed in package items",
    },
)

PR116_ROSETTA_READABILITY_CASES: tuple[dict[str, Any], ...] = (
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "arithmetic" / "collatz_bounded.safe",
        "source_fragments": (
            "var current : working_value = working_value (seed)",
            "for step in iteration",
            "if current == 1",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "data_structures" / "bounded_stack.safe",
        "source_fragments": (
            "type stack is record",
            "case s.size",
            "when others",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "concurrency" / "producer_consumer.safe",
        "source_fragments": (
            "task producer with Priority = 10",
            "loop",
            "receive data_ch, input",
        ),
    },
)

PR116_MIGRATION_EXAMPLES: tuple[dict[str, Any], ...] = (
    {
        "name": "control_flow_cutover",
        "legacy_source": """package demo is

   type count is range 0 to 10;

   function adjust (input : count) returns count is
   begin
      if input > 0 then
         return input;
      else
         return 0;
      end if;
   end adjust;
end demo;
""",
        "migrated_fragments": (
            "package demo",
            "function adjust (input : count) returns count",
            "if input > 0",
            "else",
        ),
        "forbidden_fragments": (
            "function adjust (input : count) returns count is",
            "begin",
            "end if",
            "end adjust",
            "end demo",
        ),
    },
    {
        "name": "case_and_select_cutover",
        "legacy_source": """package demo is

   type flag is range 0 to 1;
   channel msg_ch : flag capacity 1;

   function decide (input : flag) returns flag is
   begin
      case input is
         when 0 then
            return 0;
         when others then
            return 1;
      end case;
   end decide;
end demo;
""",
        "migrated_fragments": (
            "case input",
            "when 0",
            "when others",
        ),
        "forbidden_fragments": (
            "case input is",
            "when 0 then",
            "when others then",
            "end case",
        ),
    },
)


def positive_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR116_POSITIVE_CASES]


def negative_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR116_NEGATIVE_CASES]


def rosetta_readability_cases() -> list[dict[str, Any]]:
    return [dict(item) for item in PR116_ROSETTA_READABILITY_CASES]


def migration_examples() -> list[dict[str, Any]]:
    return [dict(item) for item in PR116_MIGRATION_EXAMPLES]


def corpus_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR116_POSITIVE_CASES]


def negative_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR116_NEGATIVE_CASES]


def rosetta_paths() -> list[str]:
    return [str(item["source"].relative_to(REPO_ROOT)) for item in PR116_ROSETTA_READABILITY_CASES]
