"""Shared corpus and structural expectations for PR10.3 ownership proof expansion."""

from __future__ import annotations

from typing import Any

from .harness_common import normalize_source_text, normalized_source_fragments


PR103_OWNERSHIP_CORPUS: list[dict[str, Any]] = [
    {
        "fixture": "tests/positive/ownership_borrow.safe",
        "coverage_note": "Anonymous mutable borrow with owner reuse after the borrow call and owner cleanup at scope exit.",
        "source_fragments": [
            "function modify_via_borrow (Ref : access data)",
            "modify_via_borrow (Owner);",
            "Owner.x = Owner.x + 5;",
        ],
        "spec_fragments": [
            "procedure use_borrow with Global => null;",
        ],
        "spec_regexes": [
            r"procedure modify_via_borrow\(Ref : (?:not null )?access data\) with Global => null",
        ],
        "body_fragments": [
            "modify_via_borrow (Owner);",
            "Owner.all.x := integer",
            "Free_data_ptr (Owner);",
        ],
        "body_regexes": [
            r"procedure modify_via_borrow\(Ref : (?:not null )?access data\) is",
        ],
        "body_order": [
            "modify_via_borrow (Owner);",
            "Owner.all.x := integer",
            "Free_data_ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_observe.safe",
        "coverage_note": "Two distinct access-constant observers over the same owner, with owner-only cleanup after the observations.",
        "source_fragments": [
            "function read_rate (Ref : access constant config) returns natural",
            "function read_limit (Ref : access constant config) returns natural",
            "r = read_rate (Owner);",
            "l = read_limit (Owner);",
        ],
        "spec_fragments": [
            "Depends => (read_rate'Result => Ref);",
            "Depends => (read_limit'Result => Ref);",
            "procedure use_observe with Global => null;",
        ],
        "spec_regexes": [
            r"function read_rate\(Ref : (?:not null )?access constant config\) return natural with Global => null,",
            r"function read_limit\(Ref : (?:not null )?access constant config\) return natural with Global => null,",
        ],
        "body_fragments": [
            "r := read_rate (Owner);",
            "l := read_limit (Owner);",
            "Free_config_ptr (Owner);",
        ],
        "body_regexes": [
            r"function read_rate\(Ref : (?:not null )?access constant config\) return natural is",
            r"function read_limit\(Ref : (?:not null )?access constant config\) return natural is",
        ],
        "body_order": [
            "r := read_rate (Owner);",
            "l := read_limit (Owner);",
            "Free_config_ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_observe_access.safe",
        "coverage_note": "Local access-constant observer alias derived from the owner, scoped before owner cleanup.",
        "source_fragments": [
            "Observer : access constant config = Owner.access;",
            "rate = Observer.rate;",
        ],
        "spec_fragments": [
            "procedure read_with_local_observer with Global => null;",
        ],
        "body_fragments": [
            "declare",
            "rate := Observer.all.rate;",
            "Free_config_ptr (Owner);",
        ],
        "body_regexes": [
            r"Observer : (?:not null )?access constant config := Owner;",
        ],
        "body_order": [
            "rate := Observer.all.rate;",
            "end;",
            "Free_config_ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_return.safe",
        "coverage_note": "Return move captures the returned owner, nulls the source, preserves cleanup ordering, and frees only the final owner state at the caller.",
        "source_fragments": [
            "function build returns payload_ptr",
            "return Source;",
            "Target = build ();",
        ],
        "spec_fragments": [
            "Depends => (build'Result => null);",
            "procedure use_return with Global => null;",
        ],
        "body_fragments": [
            "Return_Value : constant payload_ptr := Source;",
            "Source := null;",
            "Free_payload_ptr (Source);",
            "return Return_Value;",
            "Target := build;",
            "Free_payload_ptr (Target);",
        ],
        "body_order": [
            "Return_Value : constant payload_ptr := Source;",
            "Source := null;",
            "Free_payload_ptr (Source);",
            "return Return_Value;",
        ],
    },
    {
        "fixture": "tests/positive/ownership_inout.safe",
        "coverage_note": "Owner passed by in out, consumed through the callee formal, and cleaned up only through the caller's post-call owner state.",
        "source_fragments": [
            "function consume (Ref : in out payload_ptr)",
            "consume (Owner);",
        ],
        "spec_fragments": [
            "procedure consume(Ref : in out payload_ptr) with Global => null;",
            "procedure use_inout with Global => null;",
        ],
        "body_fragments": [
            "consume (Owner);",
            "Free_payload_ptr (Owner);",
        ],
        "body_regexes": [
            r"procedure consume\(Ref : in out payload_ptr\) is",
        ],
        "body_order": [
            "consume (Owner);",
            "Free_payload_ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_early_return.safe",
        "coverage_note": "Nested-scope early return still captures the return value before freeing inner then outer owners.",
        "source_fragments": [
            "function read_and_exit returns integer",
            "return Outer.value;",
        ],
        "spec_fragments": [
            "function read_and_exit return integer with Global => null",
            "Depends => (read_and_exit'Result => null);",
        ],
        "body_fragments": [
            "Return_Value : constant integer := Outer.all.value;",
            "Free_payload_ptr (Inner);",
            "Free_payload_ptr (Outer);",
            "return Return_Value;",
        ],
        "body_order": [
            "Return_Value : constant integer := Outer.all.value;",
            "Free_payload_ptr (Inner);",
            "Free_payload_ptr (Outer);",
            "return Return_Value;",
        ],
    },
]


def ownership_proof_corpus() -> list[dict[str, Any]]:
    return [dict(item) for item in PR103_OWNERSHIP_CORPUS]


def corpus_paths() -> list[str]:
    return [item["fixture"] for item in PR103_OWNERSHIP_CORPUS]
