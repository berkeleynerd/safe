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
            "function Exit_Early",
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
            "function Adjust (Input : Count) returns Count",
            "if Current > 5",
            "else if Current < 5",
            "for I in 1 to 2",
        ),
        "forbidden_source_fragments": (
            "then",
            "end if",
            "end loop",
            "begin",
        ),
        "typed_snippets": ('"name":"Adjust"',),
        "safei_snippets": ("function Adjust",),
        "ada_snippets": (
            "elsif (Current < 5) then",
            "for I in 1 .. 2 loop",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
        "coverage_note": "Whitespace `while` blocks stay compatible with the existing PR10.2 and PR10.3 proof/evaluation surface.",
        "source_fragments": (
            "while Lo <= Hi",
            "else if Arr (Mid) < Key",
        ),
        "forbidden_source_fragments": (
            "then",
            "end loop",
        ),
        "typed_snippets": ('"name":"Search"',),
        "safei_snippets": ("function Search",),
        "ada_snippets": (
            "while (Lo <= Hi) loop",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr112_character_case.safe",
        "coverage_note": "Whitespace `case` statements use indented `when` suites with no `is`, `then`, or closing delimiters.",
        "source_fragments": (
            "case Grade",
            "when 'A'",
            "when others",
        ),
        "forbidden_source_fragments": (
            "then",
            "end case",
            "end when",
        ),
        "typed_snippets": ('"name":"Grade_Message"',),
        "safei_snippets": ("function Grade_Message",),
        "ada_snippets": (
            "case Grade is",
            "when others =>",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "positive" / "pr113_variant_guard.safe",
        "coverage_note": "Record field lists and variant arms are indentation-structured with no `end record` / `end case` closers.",
        "source_fragments": (
            "type Packet (Kind : Character = 'A') is",
            "record",
            "case Kind",
            "when others",
        ),
        "forbidden_source_fragments": (
            "end record",
            "end case",
        ),
        "typed_snippets": ('"name":"Read_Alpha"',),
        "safei_snippets": ("function Read_Alpha",),
        "ada_snippets": (
            "type Packet",
            "case Kind is",
        ),
    },
    {
        "source": REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
        "coverage_note": "Task and `select` bodies use indentation-defined suites while preserving the admitted concurrency surface.",
        "source_fragments": (
            "task Poller with Priority = 10",
            "select",
            "when Item : Message from Msg_Ch",
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
            "var Current : Working_Value = Working_Value (Seed)",
            "for Step in Iteration",
            "if Current == 1",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "data_structures" / "bounded_stack.safe",
        "source_fragments": (
            "type Stack is record",
            "case S.Size",
            "when others",
        ),
    },
    {
        "source": REPO_ROOT / "samples" / "rosetta" / "concurrency" / "producer_consumer.safe",
        "source_fragments": (
            "task Producer with Priority = 10",
            "loop",
            "receive Data_Ch, Input",
        ),
    },
)

PR116_MIGRATION_EXAMPLES: tuple[dict[str, Any], ...] = (
    {
        "name": "control_flow_cutover",
        "legacy_source": """package Demo is

   type Count is range 0 to 10;

   function Adjust (Input : Count) returns Count is
   begin
      if Input > 0 then
         return Input;
      else
         return 0;
      end if;
   end Adjust;
end Demo;
""",
        "migrated_fragments": (
            "package Demo",
            "function Adjust (Input : Count) returns Count",
            "if Input > 0",
            "else",
        ),
        "forbidden_fragments": (
            "function Adjust (Input : Count) returns Count is",
            "begin",
            "end if",
            "end Adjust",
            "end Demo",
        ),
    },
    {
        "name": "case_and_select_cutover",
        "legacy_source": """package Demo is

   type Flag is range 0 to 1;
   channel Msg_Ch : Flag capacity 1;

   function Decide (Input : Flag) returns Flag is
   begin
      case Input is
         when 0 then
            return 0;
         when others then
            return 1;
      end case;
   end Decide;
end Demo;
""",
        "migrated_fragments": (
            "case Input",
            "when 0",
            "when others",
        ),
        "forbidden_fragments": (
            "case Input is",
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
