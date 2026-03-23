"""Shared corpus and structural expectations for the PR11.3a proof checkpoint."""

from __future__ import annotations

from typing import Any

from .gate_expectations import (
    PR113A_EXCLUDED_POSITIVE_CONCURRENCY_CASES,
    PR113A_SEQUENTIAL_PROOF_CASES,
)
from .harness_common import normalize_source_text, normalized_source_fragments


PR113A_SEQUENTIAL_PROOF_CORPUS: list[dict[str, Any]] = [
    {
        "fixture": "tests/positive/pr112_character_case.safe",
        "family": "pr112",
        "coverage_note": "Character/string literals and strict case statements stay emitted as direct Ada Character/String and Ada case syntax.",
        "source_fragments": [
            "function Grade_Message (Grade : in Character) returns String is",
            "when 'A' then",
            "return Fallback;",
        ],
        "spec_fragments": [
            "function Grade_Message(Grade : Character) return String with Global => null,",
            "Depends => (Grade_Message'Result => Grade);",
        ],
        "body_fragments": [
            "case Grade is",
            "when 'A' =>",
            'return "excellent";',
            "when others =>",
            "return Fallback;",
        ],
    },
    {
        "fixture": "tests/positive/pr112_discrete_case.safe",
        "family": "pr112",
        "coverage_note": "Boolean and integer case statements remain direct emitted-Ada case constructs with string returns.",
        "source_fragments": [
            "function Flag_Value (Flag : in Boolean) returns Integer is",
            "function Opcode_Name (Opcode : in Integer) returns String is",
            "when -1 then",
        ],
        "body_fragments": [
            "case Flag is",
            "case Opcode is",
            "when (-1) =>",
            'return "unknown";',
        ],
    },
    {
        "fixture": "tests/positive/pr112_string_param.safe",
        "family": "pr112",
        "coverage_note": "The admitted in-mode String parameter path stays accepted through emitted Ada and proof.",
        "source_fragments": [
            "function Echo (Name : in String) returns String is",
            "return Echo (\"hello\");",
        ],
        "spec_fragments": [
            "function Echo(Name : String) return String with Global => null,",
            "function Greeting return String with Global => null,",
        ],
        "body_fragments": [
            "return Name;",
            'return Echo ("hello");',
        ],
    },
    {
        "fixture": "tests/positive/pr112_case_scrutinee_once.safe",
        "family": "pr112",
        "coverage_note": "The emitted case path for a call-valued scrutinee remains proof-valid after the MIR single-evaluation fix.",
        "source_fragments": [
            "function Read_Opcode returns Integer is",
            "case Read_Opcode () is",
        ],
        "body_fragments": [
            "case Read_Opcode is",
            'return "two";',
            'return "other";',
        ],
    },
    {
        "fixture": "tests/positive/pr113_discriminant_constraints.safe",
        "family": "pr113",
        "coverage_note": "Multiple scalar discriminants and explicit positional/named constraints remain explicit in emitted Ada subtypes and profiles.",
        "source_fragments": [
            "type Packet (Active : Boolean = True, Kind : Character = 'A', Count : Integer = 0) is",
            "Named : Packet (Active = True, Kind = Default_Kind, Count = Default_Count) = (Value = 3);",
        ],
        "spec_fragments": [
            "type Packet (Active : Boolean := True; Kind : Character := 'A'; Count : Integer := 0) is record",
            "subtype Safe_constraint_Packet_Active_true_Kind_A_Count_1 is Packet (True, 'A', 1);",
            "subtype Safe_constraint_Packet_Active_true_Kind_A_Count_2 is Packet (Active => True, Kind => 'A', Count => 2);",
            "function Take(Item : Safe_constraint_Packet_Active_true_Kind_A_Count_2) return Safe_constraint_Packet_Active_true_Kind_A_Count_2 with Global => null,",
            "Depends => (Take'Result => Item);",
        ],
    },
    {
        "fixture": "tests/positive/pr113_tuple_destructure.safe",
        "family": "pr113",
        "coverage_note": "Tuple returns, destructuring, and positional field access stay visible in emitted tuple records and destructure lowering.",
        "source_fragments": [
            "function Lookup (Flag : in Boolean) returns (Boolean, Integer) is",
            "(Found, Value) : (Boolean, Integer) = Lookup (True);",
            "return Direct.2;",
        ],
        "spec_fragments": [
            "type Safe_tuple_Boolean_Integer is record",
            "function Lookup(Flag : Boolean) return Safe_tuple_Boolean_Integer with Global => null,",
        ],
        "body_fragments": [
            "Safe_Destructure_1 : Safe_tuple_Boolean_Integer := Lookup (True);",
            "Found : Boolean := Safe_Destructure_1.F1;",
            "return Direct.F2;",
        ],
    },
    {
        "fixture": "tests/positive/pr113_structured_result.safe",
        "family": "pr113",
        "coverage_note": "Builtin result plus tuple structured returns remain explicit in emitted Ada while keeping fail(String) unbounded through Ada.Strings.Unbounded storage.",
        "source_fragments": [
            "function Reject (Msg : in String) returns result is",
            "return fail (Msg);",
            "function Parse (Input : in Integer) returns (result, Integer) is",
            "return (ok (), Input);",
            "return (Reject (\"negative\"), 0);",
        ],
        "spec_fragments": [
            "with Ada.Strings.Unbounded;",
            "type result is record",
            "Message : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.Null_Unbounded_String;",
            "type Safe_tuple_result_Integer is record",
            "function Reject(Msg : String) return result with Global => null,",
        ],
        "body_fragments": [
            "return (Ok => False, Message => Ada.Strings.Unbounded.To_Unbounded_String (Msg));",
            "F1 => (Ok => True, Message => Ada.Strings.Unbounded.Null_Unbounded_String)",
            "return Safe_tuple_result_Integer'(F1 => Reject (\"negative\"), F2 => 0);",
        ],
    },
    {
        "fixture": "tests/positive/pr113_variant_guard.safe",
        "family": "pr113",
        "coverage_note": "Variant-part emission and guarded field access stay explicit through both if- and case-based discriminant establishment.",
        "source_fragments": [
            "type Packet (Kind : Character = 'A') is",
            "case Kind is",
            "return P.Alpha;",
        ],
        "spec_fragments": [
            "type Packet (Kind : Character := 'A') is record",
            "case Kind is",
            "when 'A' =>",
            "when others =>",
        ],
        "body_fragments": [
            "if (P.Kind = 'A') then",
            "case P.Kind is",
            "return P.Alpha;",
        ],
    },
    {
        "fixture": "tests/positive/constant_discriminant_default.safe",
        "family": "revalidation",
        "coverage_note": "Previously proved discriminant defaults remain explicit and continue to prove after the generalized PR11.3 discriminant work.",
        "source_fragments": [
            "Default_Active : constant Boolean = True;",
            "type Result (Active : Boolean = Default_Active) is record",
        ],
        "spec_fragments": [
            "type Result (Active : Boolean := True) is record",
            "Default_Active : constant Boolean := True;",
        ],
    },
    {
        "fixture": "tests/positive/result_equality_check.safe",
        "family": "revalidation",
        "coverage_note": "Existing equality/inequality lowering remains proof-clean after tuple/result parser and emitter expansion.",
        "source_fragments": [
            "function Is_OK (S : Status) returns Boolean is",
            "return S == 0;",
            "return S != 0;",
        ],
        "body_fragments": [
            "return (S = 0);",
            "return (S /= 0);",
        ],
    },
    {
        "fixture": "tests/positive/result_guarded_access.safe",
        "family": "revalidation",
        "coverage_note": "The earlier boolean result-record guarded-access proof remains valid after the PR11.2/PR11.3 expansion.",
        "source_fragments": [
            "type Parse_Result (OK : Boolean = False) is record",
            "if R.OK then",
            "return R.Value;",
        ],
        "spec_fragments": [
            "type Parse_Result (OK : Boolean := False) is record",
            "case OK is",
            "when True =>",
            "when False =>",
        ],
        "body_fragments": [
            "return Parse_Result'(OK => True, Value => Input);",
            "return Parse_Result'(OK => False, Error => 1);",
            "if R.OK then",
            "return R.Value;",
        ],
    },
]


def sequential_proof_corpus() -> list[dict[str, Any]]:
    return [dict(item) for item in PR113A_SEQUENTIAL_PROOF_CORPUS]


def corpus_paths() -> list[str]:
    return [item["fixture"] for item in PR113A_SEQUENTIAL_PROOF_CORPUS]


def excluded_positive_concurrency_paths() -> list[str]:
    return list(PR113A_EXCLUDED_POSITIVE_CONCURRENCY_CASES)

def verify_expected_lists() -> None:
    fixtures = corpus_paths()
    if fixtures != list(PR113A_SEQUENTIAL_PROOF_CASES):
        raise RuntimeError("PR11.3a helper corpus paths drifted from the canonical checkpoint list")
    excluded = excluded_positive_concurrency_paths()
    if excluded != list(PR113A_EXCLUDED_POSITIVE_CONCURRENCY_CASES):
        raise RuntimeError("PR11.3a excluded concurrency paths drifted from the canonical checkpoint list")
