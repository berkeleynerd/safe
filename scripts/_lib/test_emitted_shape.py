"""Emitted Ada, SafeI, and source-shape checks for ``scripts/run_tests.py``."""

from __future__ import annotations

import re
from pathlib import Path

from _lib.proof_inventory import EMITTED_PROOF_FIXTURES
from _lib.test_harness import (
    EMITTED_ASSUME_RE,
    EMITTED_GNATPROVE_WARNING_RE,
    REPO_ROOT,
    RunCounts,
    emit_case_ada_text,
    record_result,
    repo_rel,
)

EMITTED_PRAGMA_ALLOWLIST = {
    'pragma Assume (Safe_String_RT.Length (Safe_Channel_Staged_1) = Safe_Channel_Length_1);',
    'pragma Assume (Safe_String_RT.Length (Safe_Channel_Staged_3) = Safe_Channel_Length_3);',
    'pragma Assume (values_RT.Length (Safe_Channel_Staged_3) = Safe_Channel_Length_3);',
    'pragma Warnings (GNATprove, Off, "implicit aspect Always_Terminates", Reason => "shared runtime cleanup termination is accepted");',
    'pragma Warnings (GNATprove, Off, "initialization of", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "initialization of", Reason => "generated local initialization is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "channel results are consumed on the success path only");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "for-of loop item cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "heap-backed channel staging is intentional");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "generated timer cancel result is intentionally ignored");',
    'pragma Warnings (GNATprove, Off, "is set by", Reason => "generated dispatcher wake result is intentionally ignored on no-delay select paths");',
    'pragma Warnings (GNATprove, Off, "has no effect", Reason => "generated package elaboration helper is intentional");',
    'pragma Warnings (GNATprove, Off, "implicit aspect Always_Terminates", Reason => "generated package elaboration helper termination is accepted");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "for-of loop item cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "task-local branching is intentionally isolated");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "task-local state updates are intentionally isolated");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "static for-of string unrolling exposes constant conditions");',
    'pragma Warnings (GNATprove, Off, "statement has no effect", Reason => "generated pop_last trim branch is guarded by static length facts");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "generated pop_last trim branch is guarded by static length facts");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "deferred heap-backed package initialization is intentional");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "static for-of unrolling preserves intermediate source assignments");',
    'pragma Warnings (GNATprove, Off, "unused assignment", Reason => "task-local state updates are intentionally isolated");',
    'pragma Warnings (GNATprove, Off, "unused initial value of", Reason => "generated local cleanup is intentional");',
    'pragma Warnings (GNATprove, On, "has no effect");',
    'pragma Warnings (GNATprove, On, "implicit aspect Always_Terminates");',
    'pragma Warnings (GNATprove, On, "initialization of");',
    'pragma Warnings (GNATprove, On, "is set by");',
    'pragma Warnings (GNATprove, On, "statement has no effect");',
    'pragma Warnings (GNATprove, On, "unused assignment");',
    'pragma Warnings (GNATprove, On, "unused initial value of");',
}

EMITTED_SHAPE_CASES = [
    (
        "linked-list-sum-no-skip-proof",
        REPO_ROOT / "tests" / "positive" / "rule4_linked_list_sum.safe",
        ["Skip_Proof"],
    ),
    (
        "select-delay-no-blanket-warning-suppression",
        REPO_ROOT / "tests" / "concurrency" / "select_delay_local_scope.safe",
        ["pragma Warnings (Off);", "pragma Warnings (On);"],
    ),
    (
        "string-case-no-ada-case",
        REPO_ROOT / "tests" / "build" / "pr118d1_string_case_build.safe",
        ["case word is", "case mark is"],
    ),
    (
        "print-no-local-io-suppressions",
        REPO_ROOT / "tests" / "positive" / "pr118c1_print.safe",
        ["SPARK_Mode => Off", "Skip_Flow_And_Proof", "_safe_io"],
    ),
    (
        "value-channel-no-local-suppressions",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        ["SPARK_Mode => Off", "Skip_Flow_And_Proof", "_safe_io"],
    ),
    (
        "string-channel-direct-scalar-no-protected-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        ["protected type text_ch_Channel is", "_Model_Has_Value", "pragma Assume ("],
    ),
    (
        "growable-channel-direct-scalar-no-protected-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        ["protected type data_ch_Channel is", "_Model_Has_Value", "pragma Assume ("],
    ),
    (
        "try-string-channel-direct-scalar-no-protected-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        ["protected type text_ch_Channel is", "_Model_Has_Value", "pragma Assume ("],
    ),
    (
        "heap-send-length-no-source-rerender",
        REPO_ROOT / "tests" / "build" / "pr119d_send_single_eval_build.safe",
        ["Safe_String_RT.Length (next_text)"],
    ),
    (
        "select-delay-no-polling-lowering",
        REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
        [
            "Select_Polls",
            "Select_Iter",
            "if Select_Iter > 0 then",
            "if Select_Start >= Select_Deadline then",
        ],
    ),
    (
        "select-no-delay-no-polling-lowering",
        REPO_ROOT / "tests" / "embedded" / "select_single_ready_result.safe",
        ["Select_Polls", "Select_Iter", "delay 0.001;"],
    ),
    (
        "shared-root-no-raw-package-object",
        REPO_ROOT / "tests" / "positive" / "pr1112a_shared_field_access.safe",
        ["cfg : settings;", "cfg : settings :="],
    ),
    (
        "shared-root-nested-write-no-whole-record-snapshot-temp",
        REPO_ROOT / "tests" / "build" / "pr1112b_shared_update_build.safe",
        ["Safe_Shared_Snapshot_", "Safe_Shared_cfg.Set_All (Safe_Shared_Snapshot_"],
    ),
    (
        "shadowed-loop-item-no-accumulator-invariant",
        REPO_ROOT / "tests" / "emitted" / "pr1123e_shadowed_loop_item.safe",
        ["pragma Loop_Invariant (Safe_Runtime.Wide_Integer (sum)"],
    ),
    (
        "observe-only-length-reads-stay-constant",
        REPO_ROOT / "tests" / "emitted" / "pr1123j_observe_only_preserves_length.safe",
        ["Safe_growable_array_factor_RT.Length (ys)"],
    ),
]

EMITTED_REQUIRED_SHAPE_CASES = [
    (
        "string-channel-direct-scalar-record-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
        [
            "type text_ch_Channel is record",
            "Full : Boolean := False;",
            "Stored_Length_Value : Natural := 0;",
            "Pre => text_ch_Well_Formed and then not text_ch.Full",
            "Pre => text_ch_Well_Formed and then text_ch.Full",
        ],
    ),
    (
        "growable-channel-direct-scalar-record-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_growable_channel_build.safe",
        [
            "type data_ch_Channel is record",
            "Full : Boolean := False;",
            "Stored_Length_Value : Natural := 0;",
            "Pre => data_ch_Well_Formed and then not data_ch.Full",
            "Pre => data_ch_Well_Formed and then data_ch.Full",
        ],
    ),
    (
        "try-string-channel-direct-scalar-record-lowering",
        REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
        [
            "type text_ch_Channel is record",
            "Full : Boolean := False;",
            "Stored_Length_Value : Natural := 0;",
            "Pre => text_ch_Well_Formed and then not text_ch.Full",
            "Pre => text_ch_Well_Formed and then text_ch.Full",
        ],
    ),
    (
        "heap-send-stages-before-length-model",
        REPO_ROOT / "tests" / "build" / "pr119d_send_single_eval_build.safe",
        [
            "Safe_Channel_Staged_1 := Safe_String_RT.Clone (next_text);",
            "Safe_Channel_Length_1 := Safe_String_RT.Length (Safe_Channel_Staged_1);",
        ],
    ),
    (
        "select-delay-dispatcher-lowering",
        REPO_ROOT / "tests" / "concurrency" / "select_with_delay.safe",
        [
            "protected type Safe_Select_Dispatcher_",
            "procedure Reset;",
            "procedure Signal;",
            "procedure Signal_Delay (Event : in out Ada.Real_Time.Timing_Events.Timing_Event);",
            "entry Await (Timed_Out : out Boolean);",
            ".Signal;",
            ".Await (Select_Timed_Out);",
            "Ada.Real_Time.Timing_Events.Set_Handler",
            ".Signal_Delay'Access",
            "Select_Delay_Span : constant Ada.Real_Time.Time_Span :=",
            "_Compute_Deadline (Start : in Ada.Real_Time.Time; Delay_Span : in Ada.Real_Time.Time_Span)",
            "Select_Timeout_Observed : Boolean;",
            "Select_Timeout_Observed := Select_Start >= Select_Deadline;",
            "if not Select_Timeout_Observed then",
            "if Select_Timeout_Observed then",
        ],
    ),
    (
        "select-zero-delay-ready-precheck-before-timeout",
        REPO_ROOT / "tests" / "interfaces" / "pr119a_select_zero_delay_ready.safe",
        [
            "if not Select_Done then",
            "msg_ch.Try_Receive (item, Arm_Success);",
            "delay 0.0;",
            "result := Long_Long_Integer (9);",
        ],
    ),
    (
        "imported-numeric-elaboration-precondition",
        REPO_ROOT / "tests" / "build" / "pr232_imported_numeric_elab_build.safe",
        [
            "channel_score = tally (0)",
            "score = pr232_provider_numeric.user_id (0)",
        ],
    ),
    (
        "known-mutating-call-invalidates-length",
        REPO_ROOT / "tests" / "build" / "pr1123j_known_mutating_call_length_build.safe",
        [
            "IO.Put_Line (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Long_Long_Integer (Long_Long_Integer (Safe_growable_array_factor_RT.Length (ys)))), Ada.Strings.Both));",
        ],
    ),
    (
        "unknown-call-invalidates-length",
        REPO_ROOT / "tests" / "emitted" / "pr1123j_unknown_call_invalidates_length.safe",
        [
            "IO.Put_Line (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Long_Long_Integer (Long_Long_Integer (Safe_growable_array_factor_RT.Length (ys)))), Ada.Strings.Both));",
        ],
    ),
    (
        "overloaded-mutating-call-invalidates-length",
        REPO_ROOT / "tests" / "emitted" / "pr1123j_overloaded_mutating_call_invalidates_length.safe",
        [
            "IO.Put_Line (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Long_Long_Integer (Long_Long_Integer (Safe_growable_array_factor_RT.Length (ys)))), Ada.Strings.Both));",
        ],
    ),
    (
        "mutating-call-expr-invalidates-length",
        REPO_ROOT / "tests" / "emitted" / "pr1123j_mutating_call_expr_invalidates_length.safe",
        [
            "return Long_Long_Integer (Safe_growable_array_factor_RT.Length (ys));",
        ],
    ),
    (
        "select-no-delay-dispatcher-await",
        REPO_ROOT / "tests" / "embedded" / "select_single_ready_result.safe",
        [
            "protected type Safe_Select_Dispatcher_",
            "_Next_Arm : Positive range 1 .. 2 := 1",
            "for Select_Offset in 0 .. 1 loop",
            "Select_Probe_Ordinal : constant Positive range 1 .. 2 :=",
            "case Select_Probe_Ordinal is",
            "_Next_Arm := 2;",
            "_Next_Arm := 1;",
            ".Signal;",
            ".Await (Select_Timed_Out);",
        ],
    ),
    (
        "shared-root-protected-wrapper-lowering",
        REPO_ROOT / "tests" / "positive" / "pr1112a_shared_field_access.safe",
        [
            "protected type Safe_Shared_cfg_Wrapper with Priority => System.Any_Priority'Last is",
            "function Get_All return settings;",
            "procedure Set_All (Value : in settings);",
            "function Get_count return",
            "procedure Set_count (Value : in",
            "function Get_nested return",
            "procedure Initialize (Value : in settings);",
            "Safe_Shared_cfg : Safe_Shared_cfg_Wrapper;",
        ],
    ),
    (
        "shared-root-snapshot-update-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112b_shared_update_build.safe",
        [
            "Safe_Shared_cfg.Set_All (next);",
            "procedure Set_Path_nested_depth (Value : in counter);",
            "Safe_Shared_cfg.Set_Path_nested_depth (7);",
        ],
    ),
    (
        "shared-root-heap-wrapper-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_string_build.safe",
        [
            "function Get_All return settings is",
            "function Get_text return Safe_String_RT.Safe_String is",
            "Safe_String_RT.Clone (State_Value.text)",
            "Safe_String_RT.Free (State_Value.text);",
            "procedure Set_Path_nested_label (Value : in Safe_String_RT.Safe_String);",
            "Safe_String_RT.Free (State_Value.nested.label);",
        ],
    ),
    (
        "shared-root-container-wrapper-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_container_fields_build.safe",
        [
            "function Get_items return Safe_growable_array_integer is",
            "Result := Safe_growable_array_integer_RT.Clone (State_Value.items);",
            "Safe_growable_array_integer_RT.Free (State_Value.items);",
            "State_Value.items := Safe_growable_array_integer_RT.Clone (Value);",
            "Safe_Shared_cfg_settings_Copy (Result, State_Value);",
            "Safe_Shared_cfg_settings_Free (State_Value);",
            "Safe_Shared_cfg_settings_Copy (State_Value, Value);",
        ],
    ),
    (
        "shared-list-root-wrapper-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_list_root_build.safe",
        [
            "protected type Safe_Shared_values_Wrapper with Priority => System.Any_Priority'Last is",
            "function Get_All return Safe_growable_array_integer;",
            "procedure Set_All (Value : in Safe_growable_array_integer);",
            "function Get_Length return Long_Long_Integer;",
            "procedure Append (Value : in Long_Long_Integer);",
            "procedure Pop_Last (Result : out",
            "Safe_Shared_values.Append (3);",
            "Safe_Shared_values.Append (4);",
            "Safe_Shared_values.Pop_Last",
        ],
    ),
    (
        "shared-map-root-wrapper-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_map_root_build.safe",
        [
            "protected type Safe_Shared_cache_Wrapper with Priority => System.Any_Priority'Last is",
            "function Get_All return Safe_growable_array_tuple_string_integer;",
            "procedure Set_All (Value : in Safe_growable_array_tuple_string_integer);",
            "function Get_Length return Long_Long_Integer;",
            "function Contains (Key : in",
            "function Get (Key : in",
            "procedure Set (Key : in",
            "procedure Remove (Key : in",
            "Safe_Shared_cache.Set (Safe_String_RT.From_Literal (\"two\"), 2);",
            "Safe_Shared_cache.Get (Safe_String_RT.From_Literal (\"two\"))",
            "Safe_Shared_cache.Contains (Safe_String_RT.From_Literal (\"one\"))",
            "Safe_Shared_cache.Remove (Safe_String_RT.From_Literal (\"one\"), removed);",
        ],
    ),
    (
        "shared-growable-root-wrapper-lowering",
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_growable_root_build.safe",
        [
            "protected type Safe_Shared_data_Wrapper with Priority => System.Any_Priority'Last is",
            "function Get_All return Safe_growable_array_integer;",
            "procedure Set_All (Value : in Safe_growable_array_integer);",
            "function Get_Length return Long_Long_Integer;",
            "procedure Append (Value : in Long_Long_Integer);",
            "procedure Pop_Last (Result : out",
            "Safe_Shared_data.Append (6);",
            "Safe_Shared_data.Append (7);",
            "Safe_Shared_data.Pop_Last",
        ],
    ),
    (
        "shared-private-record-exact-ceiling",
        REPO_ROOT / "tests" / "build" / "pr1112f_shared_record_ceiling_build.safe",
        [
            "protected type Safe_Shared_cfg_Wrapper with Priority => 20 is",
        ],
    ),
    (
        "shared-private-container-exact-ceiling",
        REPO_ROOT / "tests" / "build" / "pr1112f_shared_container_ceiling_build.safe",
        [
            "protected type Safe_Shared_values_Wrapper with Priority => 14 is",
        ],
    ),
    (
        "shared-public-provider-fallback-ceiling",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_ceiling.safe",
        [
            "protected type Safe_Shared_cfg_Wrapper with Priority => System.Any_Priority'Last is",
        ],
    ),
    (
        "shared-no-analysis-fallback-ceiling",
        REPO_ROOT / "tests" / "positive" / "pr1112a_shared_field_access.safe",
        [
            "protected type Safe_Shared_cfg_Wrapper with Priority => System.Any_Priority'Last is",
        ],
    ),
    (
        "shared-mixed-channel-ceiling",
        REPO_ROOT / "tests" / "build" / "pr1112f_mixed_channel_shared_build.safe",
        [
            "protected type Safe_Shared_cfg_Wrapper with Priority => 18 is",
            "protected type data_ch_Channel with Priority => 18 is",
        ],
    ),
    (
        "mutual-global-aspect-recursion",
        REPO_ROOT / "tests" / "interfaces" / "pr1122e3_mutual_global_aspect.safe",
        [
            "function first(remaining : in Long_Long_Integer) return Long_Long_Integer with Global => (Input => counter);",
            "function second(remaining : in Long_Long_Integer) return Long_Long_Integer with Global => (Input => counter);",
        ],
    ),
]

SAFEI_REQUIRED_SHAPE_CASES = [
    (
        "shared-helper-prefix-prefers-longest-root",
        REPO_ROOT / "tests" / "interfaces" / "provider_shared_helper_prefix.safe",
        [
            "\"provider_shared_helper_prefix.cfg_more\"",
        ],
    ),
]

EMITTED_PROTECTED_BODY_SHAPE_CASES = [
    (
        "tuple-channel-protected-body-no-heap-runtime",
        REPO_ROOT / "tests" / "build" / "pr118g_tuple_string_channel_build.safe",
        "pair_ch_Channel",
        [
            "pair_ch_Copy_Value",
            "pair_ch_Free_Value",
            "Safe_String_RT.Clone",
            "Safe_String_RT.Copy",
            "Safe_String_RT.Free",
        ],
    ),
    (
        "record-channel-protected-body-no-heap-runtime",
        REPO_ROOT / "tests" / "build" / "pr118g_record_string_channel_build.safe",
        "data_ch_Channel",
        [
            "data_ch_Copy_Value",
            "data_ch_Free_Value",
            "Safe_String_RT.Clone",
            "Safe_String_RT.Copy",
            "Safe_String_RT.Free",
        ],
    ),
    (
        "shared-root-heap-protected-body-no-raw-state-assignments",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_string_build.safe",
        "Safe_Shared_cfg_Wrapper",
        [
            "return State_Value;",
            "State_Value := Value;",
            "return State_Value.text;",
            "State_Value.text := Value;",
            "return State_Value.nested;",
            "State_Value.nested := Value;",
            "State_Value.nested.label := Value;",
        ],
    ),
    (
        "shared-root-container-protected-body-no-raw-state-assignments",
        REPO_ROOT / "tests" / "build" / "pr1112c_shared_container_fields_build.safe",
        "Safe_Shared_cfg_Wrapper",
        [
            "return State_Value;",
            "return State_Value.items;",
            "State_Value.items := Value;",
            "return State_Value.names;",
            "State_Value.names := Value;",
            "return State_Value.data;",
            "State_Value.data := Value;",
        ],
    ),
    (
        "shared-list-root-protected-body-no-raw-state-assignments",
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_list_root_build.safe",
        "Safe_Shared_values_Wrapper",
        [
            "return State_Value;",
            "State_Value := Value;",
        ],
    ),
    (
        "shared-map-root-protected-body-no-raw-state-assignments",
        REPO_ROOT / "tests" / "build" / "pr1112d_shared_map_root_build.safe",
        "Safe_Shared_cache_Wrapper",
        [
            "return State_Value;",
            "State_Value := Value;",
        ],
    ),
]

SOURCE_SHAPE_CASES = [
    (
        "ada-emit-no-skip-proof-fallback",
        REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-ada_emit.adb",
        ["Skip_Proof"],
    ),
    (
        "ada-emit-no-channel-proof-suppression",
        REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-ada_emit.adb",
        ["Skip_Flow_And_Proof"],
    ),
    (
        "ada-emit-no-select-polling-lowering",
        REPO_ROOT / "compiler_impl" / "src" / "safe_frontend-ada_emit.adb",
        ["Select_Poll_Quantum_Seconds", "Select_Polls : constant Positive :=", "for Select_Iter in 0 .. Select_Polls loop"],
    ),
    (
        "run-proofs-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "run_proofs.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "pr09-emit-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "_lib" / "pr09_emit.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "pr111-eval-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "_lib" / "pr111_language_eval.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "embedded-eval-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "_lib" / "embedded_eval.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
    (
        "run-samples-no-stdlib-project-import",
        REPO_ROOT / "scripts" / "run_samples.py",
        ['SAFE_STDLIB_OBJECT_DIR', 'with "{STDLIB_GPR}";'],
    ),
]

def run_emitted_shape_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    forbidden_snippets: list[str],
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        _, emitted_text = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    for snippet in forbidden_snippets:
        if snippet in emitted_text:
            return False, f"found forbidden emitted snippet {snippet!r}"
    return True, ""

def normalize_snippet_whitespace(text: str) -> str:
    return " ".join(text.split())


def emitted_allowlisted_pragmas(ada_dir: Path) -> dict[str, set[str]]:
    occurrences: dict[str, set[str]] = {}

    for path in sorted(ada_dir.iterdir()):
        if path.suffix not in {".adb", ".ads"}:
            continue
        emitted_text = path.read_text(encoding="utf-8")
        for match in EMITTED_GNATPROVE_WARNING_RE.findall(emitted_text):
            snippet = normalize_snippet_whitespace(match)
            occurrences.setdefault(snippet, set()).add(path.name)
        for match in EMITTED_ASSUME_RE.findall(emitted_text):
            snippet = normalize_snippet_whitespace(match)
            occurrences.setdefault(snippet, set()).add(path.name)

    return occurrences


def run_emitted_pragma_allowlist_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        ada_dir, _ = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    occurrences = emitted_allowlisted_pragmas(ada_dir)
    unexpected = sorted(set(occurrences) - EMITTED_PRAGMA_ALLOWLIST)
    if not unexpected:
        return True, ""

    details = []
    for snippet in unexpected:
        files = ", ".join(sorted(occurrences[snippet]))
        details.append(f"{snippet!r} in {files}")
    return False, "unexpected emitted pragma(s): " + "; ".join(details)


def run_emitted_required_shape_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    required_snippets: list[str],
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        _, emitted_text = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    for snippet in required_snippets:
        if snippet not in emitted_text:
            return False, f"missing required emitted snippet {snippet!r}"
    return True, ""


def run_safei_required_shape_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    required_snippets: list[str],
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        ada_dir, _ = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    iface_dir = ada_dir.parent / "iface"
    safei_path = iface_dir / f"{source.stem.lower()}.safei.json"
    if not safei_path.exists():
        return False, f"emit produced no safei contract {safei_path.name}"

    safei_text = safei_path.read_text(encoding="utf-8")
    for snippet in required_snippets:
        if snippet not in safei_text:
            return False, f"missing required safei snippet {snippet!r}"
    return True, ""


def run_emitted_protected_body_shape_case(
    safec: Path,
    *,
    label: str,
    source: Path,
    protected_name: str,
    forbidden_snippets: list[str],
    temp_root: Path,
) -> tuple[bool, str]:
    try:
        ada_dir, _ = emit_case_ada_text(
            safec,
            label=label,
            source=source,
            temp_root=temp_root,
        )
    except RuntimeError as exc:
        return False, str(exc)

    body_pattern = re.compile(
        rf"protected body {re.escape(protected_name)} is(.*?)end {re.escape(protected_name)};",
        re.DOTALL,
    )

    for path in sorted(ada_dir.iterdir()):
        if path.suffix != ".adb":
            continue
        emitted_text = path.read_text(encoding="utf-8")
        match = body_pattern.search(emitted_text)
        if not match:
            continue
        protected_body = match.group(1)
        for snippet in forbidden_snippets:
            if snippet in protected_body:
                return (
                    False,
                    f"found forbidden protected-body snippet {snippet!r} in {path.name}",
                )
        return True, ""

    return False, f"missing protected body {protected_name!r} in emitted Ada sources"


def run_source_shape_case(
    *,
    source: Path,
    forbidden_snippets: list[str],
) -> tuple[bool, str]:
    source_text = source.read_text(encoding="utf-8")
    for snippet in forbidden_snippets:
        if snippet in source_text:
            return False, f"found forbidden source snippet {snippet!r}"
    return True, ""



def run_emitted_shape_checks(safec: Path, *, temp_root: Path) -> RunCounts:
    passed = 0
    failures: list[tuple[str, str]] = []

    for label, source, forbidden_snippets in EMITTED_SHAPE_CASES:
        passed += record_result(
            failures,
            f"emitted-shape:{label}:{repo_rel(source)}",
            run_emitted_shape_case(
                safec,
                label=label,
                source=source,
                forbidden_snippets=forbidden_snippets,
                temp_root=temp_root,
            ),
        )

    for fixture in EMITTED_PROOF_FIXTURES:
        source = REPO_ROOT / fixture
        passed += record_result(
            failures,
            f"emitted-pragma-allowlist:{repo_rel(source)}",
            run_emitted_pragma_allowlist_case(
                safec,
                label="pragma-allowlist",
                source=source,
                temp_root=temp_root,
            ),
        )

    for label, source, required_snippets in EMITTED_REQUIRED_SHAPE_CASES:
        passed += record_result(
            failures,
            f"emitted-required-shape:{label}:{repo_rel(source)}",
            run_emitted_required_shape_case(
                safec,
                label=label,
                source=source,
                required_snippets=required_snippets,
                temp_root=temp_root,
            ),
        )

    for label, source, required_snippets in SAFEI_REQUIRED_SHAPE_CASES:
        passed += record_result(
            failures,
            f"safei-required-shape:{label}:{repo_rel(source)}",
            run_safei_required_shape_case(
                safec,
                label=label,
                source=source,
                required_snippets=required_snippets,
                temp_root=temp_root,
            ),
        )

    for label, source, protected_name, forbidden_snippets in EMITTED_PROTECTED_BODY_SHAPE_CASES:
        passed += record_result(
            failures,
            f"emitted-protected-shape:{label}:{repo_rel(source)}",
            run_emitted_protected_body_shape_case(
                safec,
                label=label,
                source=source,
                protected_name=protected_name,
                forbidden_snippets=forbidden_snippets,
                temp_root=temp_root,
            ),
        )

    for label, source, forbidden_snippets in SOURCE_SHAPE_CASES:
        passed += record_result(
            failures,
            f"source-shape:{label}:{repo_rel(source)}",
            run_source_shape_case(source=source, forbidden_snippets=forbidden_snippets),
        )

    return passed, 0, failures
