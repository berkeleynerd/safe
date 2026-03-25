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
            "type packet (active : boolean = true, kind : character = 'A', count : integer = 0) is",
            "named : packet (active = true, kind = default_kind, count = default_count) = (value = 3);",
        ],
        "spec_fragments": [
            "type packet (active : boolean := True; kind : character := 'A'; count : integer := 0) is record",
            "subtype Safe_constraint_packet_active_true_kind_A_count_1 is packet (True, 'A', 1);",
            "subtype Safe_constraint_packet_active_true_kind_A_count_2 is packet (active => True, kind => 'A', count => 2);",
            "function take(item : Safe_constraint_packet_active_true_kind_A_count_2) return Safe_constraint_packet_active_true_kind_A_count_2 with Global => null,",
            "Depends => (take'Result => item);",
        ],
    },
    {
        "fixture": "tests/positive/pr113_tuple_destructure.safe",
        "family": "pr113",
        "coverage_note": "Tuple returns, destructuring, and positional field access stay visible in emitted tuple records and destructure lowering.",
        "source_fragments": [
            "function lookup (flag : in Boolean) returns (Boolean, Integer) is",
            "(Found, Value) : (Boolean, Integer) = lookup (True);",
            "return direct.2;",
        ],
        "spec_fragments": [
            "type Safe_tuple_boolean_integer is record",
            "function lookup(flag : boolean) return Safe_tuple_boolean_integer with Global => null,",
        ],
        "body_fragments": [
            "Safe_Destructure_1 : Safe_tuple_boolean_integer := lookup (True);",
            "Found : boolean := Safe_Destructure_1.F1;",
            "return direct.F2;",
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
            "type Safe_tuple_result_integer is record",
            "function reject(msg : string) return result with Global => null,",
        ],
        "body_fragments": [
            "return (Ok => False, Message => Ada.Strings.Unbounded.To_Unbounded_String (Msg));",
            "F1 => (Ok => True, Message => Ada.Strings.Unbounded.Null_Unbounded_String)",
            "return Safe_tuple_result_integer'(F1 => reject (\"negative\"), F2 => 0);",
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
            "if (P.kind = 'A') then",
            "case P.kind is",
            "return P.alpha;",
        ],
    },
    {
        "fixture": "tests/positive/constant_discriminant_default.safe",
        "family": "revalidation",
        "coverage_note": "Previously proved discriminant defaults remain explicit and continue to prove after the generalized PR11.3 discriminant work.",
        "source_fragments": [
            "default_active : constant boolean = true;",
            "type default_result (active : boolean = default_active) is record",
        ],
        "spec_fragments": [
            "type default_result (active : boolean := True) is record",
            "default_active : constant boolean := True;",
        ],
    },
    {
        "fixture": "tests/positive/result_equality_check.safe",
        "family": "revalidation",
        "coverage_note": "Existing equality/inequality lowering remains proof-clean after tuple/result parser and emitter expansion.",
        "source_fragments": [
            "function is_ok (S : status) returns boolean is",
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
            "type parse_result (ok : boolean = false) is record",
            "if R.ok then",
            "return R.value;",
        ],
        "spec_fragments": [
            "type parse_result (ok : boolean := False) is record",
            "case ok is",
            "when True =>",
            "when False =>",
        ],
        "body_fragments": [
            "return parse_result'(ok => True, value => Input);",
            "return parse_result'(ok => False, error => 1);",
            "if R.ok then",
            "return R.value;",
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
