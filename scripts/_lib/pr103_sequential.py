"""Shared corpus and structural expectations for PR10.3 ownership proof expansion."""

from __future__ import annotations

from typing import Any

from .harness_common import normalize_source_text, normalized_source_fragments


PR103_OWNERSHIP_CORPUS: list[dict[str, Any]] = [
    {
        "fixture": "tests/positive/ownership_borrow.safe",
        "coverage_note": "Anonymous mutable borrow with owner reuse after the borrow call and owner cleanup at scope exit.",
        "source_fragments": [
            "function Modify_Via_Borrow (Ref : access Data) is",
            "Modify_Via_Borrow (Owner);",
            "Owner.all.X = Owner.all.X + 5;",
        ],
        "spec_fragments": [
            "procedure Use_Borrow with Global => null;",
        ],
        "spec_regexes": [
            r"procedure Modify_Via_Borrow\(Ref : (?:not null )?access Data\) with Global => null",
        ],
        "body_fragments": [
            "Modify_Via_Borrow (Owner);",
            "Owner.all.X := Integer",
            "Free_Data_Ptr (Owner);",
        ],
        "body_regexes": [
            r"procedure Modify_Via_Borrow\(Ref : (?:not null )?access Data\) is",
        ],
        "body_order": [
            "Modify_Via_Borrow (Owner);",
            "Owner.all.X := Integer",
            "Free_Data_Ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_observe.safe",
        "coverage_note": "Two distinct access-constant observers over the same owner, with owner-only cleanup after the observations.",
        "source_fragments": [
            "function Read_Rate (Ref : access constant Config) returns Natural is",
            "function Read_Limit (Ref : access constant Config) returns Natural is",
            "R = Read_Rate (Owner);",
            "L = Read_Limit (Owner);",
        ],
        "spec_fragments": [
            "Depends => (Read_Rate'Result => Ref);",
            "Depends => (Read_Limit'Result => Ref);",
            "procedure Use_Observe with Global => null;",
        ],
        "spec_regexes": [
            r"function Read_Rate\(Ref : (?:not null )?access constant Config\) return Natural with Global => null,",
            r"function Read_Limit\(Ref : (?:not null )?access constant Config\) return Natural with Global => null,",
        ],
        "body_fragments": [
            "R := Read_Rate (Owner);",
            "L := Read_Limit (Owner);",
            "Free_Config_Ptr (Owner);",
        ],
        "body_regexes": [
            r"function Read_Rate\(Ref : (?:not null )?access constant Config\) return Natural is",
            r"function Read_Limit\(Ref : (?:not null )?access constant Config\) return Natural is",
        ],
        "body_order": [
            "R := Read_Rate (Owner);",
            "L := Read_Limit (Owner);",
            "Free_Config_Ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_observe_access.safe",
        "coverage_note": "Local access-constant observer alias derived from the owner, scoped before owner cleanup.",
        "source_fragments": [
            "Observer : access constant Config = Owner.Access;",
            "Rate = Observer.all.Rate;",
        ],
        "spec_fragments": [
            "procedure Read_With_Local_Observer with Global => null;",
        ],
        "body_fragments": [
            "declare",
            "Rate := Observer.all.Rate;",
            "Free_Config_Ptr (Owner);",
        ],
        "body_regexes": [
            r"Observer : (?:not null )?access constant Config := Owner;",
        ],
        "body_order": [
            "Rate := Observer.all.Rate;",
            "end;",
            "Free_Config_Ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_return.safe",
        "coverage_note": "Return move captures the returned owner, nulls the source, preserves cleanup ordering, and frees only the final owner state at the caller.",
        "source_fragments": [
            "function Build returns Payload_Ptr is",
            "return Source;",
            "Target = Build ();",
        ],
        "spec_fragments": [
            "Depends => (Build'Result => null);",
            "procedure Use_Return with Global => null;",
        ],
        "body_fragments": [
            "Return_Value : constant Payload_Ptr := Source;",
            "Source := null;",
            "Free_Payload_Ptr (Source);",
            "return Return_Value;",
            "Target := Build;",
            "Free_Payload_Ptr (Target);",
        ],
        "body_order": [
            "Return_Value : constant Payload_Ptr := Source;",
            "Source := null;",
            "Free_Payload_Ptr (Source);",
            "return Return_Value;",
        ],
    },
    {
        "fixture": "tests/positive/ownership_inout.safe",
        "coverage_note": "Owner passed by in out, consumed through the callee formal, and cleaned up only through the caller's post-call owner state.",
        "source_fragments": [
            "function Consume (Ref : in out Payload_Ptr) is",
            "Consume (Owner);",
        ],
        "spec_fragments": [
            "procedure Consume(Ref : in out Payload_Ptr) with Global => null;",
            "procedure Use_Inout with Global => null;",
        ],
        "body_fragments": [
            "Consume (Owner);",
            "Free_Payload_Ptr (Owner);",
        ],
        "body_regexes": [
            r"procedure Consume\(Ref : in out Payload_Ptr\) is",
        ],
        "body_order": [
            "Consume (Owner);",
            "Free_Payload_Ptr (Owner);",
        ],
    },
    {
        "fixture": "tests/positive/ownership_early_return.safe",
        "coverage_note": "Nested-scope early return still captures the return value before freeing inner then outer owners.",
        "source_fragments": [
            "function Read_And_Exit returns Integer is",
            "return Outer.all.Value;",
        ],
        "spec_fragments": [
            "function Read_And_Exit return Integer with Global => null",
            "Depends => (Read_And_Exit'Result => null);",
        ],
        "body_fragments": [
            "Return_Value : constant Integer := Outer.all.Value;",
            "Free_Payload_Ptr (Inner);",
            "Free_Payload_Ptr (Outer);",
            "return Return_Value;",
        ],
        "body_order": [
            "Return_Value : constant Integer := Outer.all.Value;",
            "Free_Payload_Ptr (Inner);",
            "Free_Payload_Ptr (Outer);",
            "return Return_Value;",
        ],
    },
]


def ownership_proof_corpus() -> list[dict[str, Any]]:
    return [dict(item) for item in PR103_OWNERSHIP_CORPUS]


def corpus_paths() -> list[str]:
    return [item["fixture"] for item in PR103_OWNERSHIP_CORPUS]
