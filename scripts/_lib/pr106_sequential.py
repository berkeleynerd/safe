"""Shared corpus and structural expectations for PR10.6 sequential proof expansion."""

from __future__ import annotations

from typing import Any

from .harness_common import normalize_source_text, normalized_source_fragments


PR106_EXCLUDED_POSITIVE_CONCURRENCY_CASES = [
    "tests/positive/channel_pingpong.safe",
    "tests/positive/channel_pipeline.safe",
    "tests/positive/channel_pipeline_compute.safe",
]


PR106_SEQUENTIAL_PROOF_CORPUS: list[dict[str, Any]] = [
    {
        "fixture": "tests/positive/constant_access_deref_write.safe",
        "family": "constants",
        "coverage_note": "Access-typed constant initialization still lowers to explicit dereference writes plus explicit cleanup support.",
        "source_fragments": [
            "package Constant_Access_Deref_Write is",
            "function Mutate_Through_Constant_Access",
        ],
        "spec_fragments": [
            "type Payload_Ptr is access Payload;",
        ],
        "body_fragments": [
            "Ada.Unchecked_Deallocation",
            "Ptr.all.Value := 2;",
        ],
    },
    {
        "fixture": "tests/positive/constant_channel_capacity.safe",
        "family": "constants",
        "coverage_note": "Constant-derived channel capacity remains visible in the emitted protected buffer shape and entry guards.",
        "source_fragments": [
            "package Constant_Channel_Capacity is",
            "channel Data_Ch : Message capacity Capacity_Value;",
        ],
        "spec_fragments": [
            "Capacity_Value : constant Integer := 3;",
            "subtype Data_Ch_Index is Positive range 1 .. 3;",
            "protected type Data_Ch_Channel",
        ],
        "body_fragments": [
            "when Count < 3 is",
            "when Count > 0 is",
        ],
    },
    {
        "fixture": "tests/positive/constant_discriminant_default.safe",
        "family": "constants",
        "coverage_note": "Defaulted discriminants in the current boolean-only subset emit as explicit discriminated Ada records.",
        "source_fragments": [
            "package Constant_Discriminant_Default is",
            "Default_Active",
        ],
        "spec_fragments": [
            "type Result (Active : Boolean := True) is record",
            "Default_Active : constant Boolean := True;",
        ],
    },
    {
        "fixture": "tests/positive/constant_range_bound.safe",
        "family": "constants",
        "coverage_note": "Constant-derived scalar range bounds remain explicit in emitted subtype and constant declarations.",
        "source_fragments": [
            "package Constant_Range_Bound is",
            "Max_Count",
        ],
        "spec_fragments": [
            "type Index is range 0 .. 4;",
            "Max_Count : constant Integer := 4;",
        ],
    },
    {
        "fixture": "tests/positive/constant_shadow_mutable.safe",
        "family": "constants",
        "coverage_note": "Shadowed mutable locals stay distinct from outer constants in the emitted Ada body.",
        "source_fragments": [
            "package Constant_Shadow_Mutable is",
            "function Update_Local",
        ],
        "spec_fragments": [
            "Value : constant Integer := 1;",
        ],
        "body_fragments": [
            "Value : Integer := 0;",
            "Value := 2;",
        ],
        "body_order": [
            "Value : Integer := 0;",
            "Value := 2;",
        ],
    },
    {
        "fixture": "tests/positive/constant_task_priority.safe",
        "family": "constants",
        "coverage_note": "Task priorities derived from constants remain explicit in the emitted task declaration without dragging unrelated task-body proof noise into the corpus.",
        "source_fragments": [
            "package Constant_Task_Priority is",
            "task Worker",
        ],
        "spec_fragments": [
            "Worker_Priority : constant Integer := 5;",
            "task Worker with Priority => 5;",
        ],
        "body_fragments": [
            "loop",
            "null;",
        ],
    },
    {
        "fixture": "tests/positive/emitter_surface_proc.safe",
        "family": "emitter_surface",
        "coverage_note": "Procedure-only emission stays support-file-light and preserves explicit dependency contracts.",
        "source_fragments": [
            "package Emitter_Surface_Proc is",
            "function Copy",
        ],
        "spec_fragments": [
            "Depends => (Output => Input);",
        ],
        "body_fragments": [
            "Local : Small := Input;",
            "Output := Local;",
        ],
        "absent_ada_files": [
            "safe_runtime.ads",
            "gnat.adc",
        ],
    },
    {
        "fixture": "tests/positive/emitter_surface_record.safe",
        "family": "emitter_surface",
        "coverage_note": "Record-only emission stays support-file-light and preserves the intended minimal package skeleton.",
        "source_fragments": [
            "package Emitter_Surface_Record is",
            "type Pair is record",
        ],
        "spec_fragments": [
            "type Pair is record",
            "Seed : Counter := 3;",
        ],
        "body_fragments": [
            "Value : Counter := Seed;",
            "return Value;",
        ],
        "absent_ada_files": [
            "safe_runtime.ads",
            "gnat.adc",
        ],
    },
    {
        "fixture": "tests/positive/result_equality_check.safe",
        "family": "results",
        "coverage_note": "Result equality and inequality lowering remain explicit and compile/prove cleanly in emitted Ada.",
        "source_fragments": [
            "package Result_Equality_Check is",
            "function Is_Error",
        ],
        "body_fragments": [
            "return (S = 0);",
            "return (S /= 0);",
        ],
    },
    {
        "fixture": "tests/positive/result_guarded_access.safe",
        "family": "results",
        "coverage_note": "Guarded result access now proves on top of explicit boolean-discriminant variant record emission.",
        "source_fragments": [
            "package Result_Guarded_Access is",
            "function Get_Or_Default",
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
    {
        "fixture": "tests/positive/rule1_accumulate.safe",
        "family": "rule1",
        "coverage_note": "Loop-carried wide arithmetic and narrowing remain explicit in the emitted accumulation path.",
        "source_fragments": [
            "function Accumulate",
            "type Total_Range",
        ],
        "body_fragments": [
            "Sum : Safe_Runtime.Wide_Integer := Safe_Runtime.Wide_Integer (0);",
            "Sum := (Safe_Runtime.Wide_Integer (Sum) + Safe_Runtime.Wide_Integer (Data (I)));",
            "return Total_Range (Safe_Runtime.Wide_Integer (Sum));",
        ],
    },
    {
        "fixture": "tests/positive/rule1_conversion.safe",
        "family": "rule1",
        "coverage_note": "Wide-to-narrow conversion and sign-sensitive narrowing remain explicit and asserted before return.",
        "source_fragments": [
            "function Clamp_And_Convert",
            "function Absolute_To_Positive",
        ],
        "body_fragments": [
            "Clamped : Wide_Value;",
            "return Narrow_Value (Clamped);",
            "return Positive_Value ((-Safe_Runtime.Wide_Integer (V)));",
        ],
    },
    {
        "fixture": "tests/positive/rule1_return.safe",
        "family": "rule1",
        "coverage_note": "Return-path arithmetic stays widened and narrowed explicitly, including negative constant returns.",
        "source_fragments": [
            "function Signum",
            "function Bounded_Add",
        ],
        "body_fragments": [
            "return Small ((-Safe_Runtime.Wide_Integer (1)));",
            "return Bounded ((Safe_Runtime.Wide_Integer (A) + Safe_Runtime.Wide_Integer (B)));",
        ],
    },
    {
        "fixture": "tests/positive/rule2_binary_search.safe",
        "family": "rule2",
        "coverage_note": "Index-safe midpoint search remains explicit through loop variants, midpoint asserts, and bounded index conversions.",
        "source_fragments": [
            "function Search",
            "type Sorted_Array",
        ],
        "body_fragments": [
            "pragma Loop_Variant (Increases => Lo, Decreases => Hi);",
            "Mid := Index ((Safe_Runtime.Wide_Integer (Lo) + ((Safe_Runtime.Wide_Integer (Hi) - Safe_Runtime.Wide_Integer (Lo)) / Safe_Runtime.Wide_Integer (2))));",
            "Lo := Index ((Safe_Runtime.Wide_Integer (Mid) + Safe_Runtime.Wide_Integer (1)));",
            "Hi := Index ((Safe_Runtime.Wide_Integer (Mid) - Safe_Runtime.Wide_Integer (1)));",
        ],
    },
    {
        "fixture": "tests/positive/rule2_iteration.safe",
        "family": "rule2",
        "coverage_note": "Whole-range iteration over bounded indices remains direct and safe in the emitted loops.",
        "source_fragments": [
            "function Find_Max",
            "function Zero_All",
        ],
        "body_fragments": [
            "for I in Slot loop",
            "Max_Val := Bank (I);",
            "Bank (I) := 0;",
        ],
    },
    {
        "fixture": "tests/positive/rule2_lookup.safe",
        "family": "rule2",
        "coverage_note": "Lookup lowering keeps explicit raw-id range guards before index narrowing and table access.",
        "source_fragments": [
            "function Lookup",
            "function Lookup_With_Default",
        ],
        "body_fragments": [
            "return Table (Id);",
            "if ((Raw_Id >= 1) and then (Raw_Id <= 8)) then",
            "return Table (Sensor_Id (Raw_Id));",
        ],
    },
    {
        "fixture": "tests/positive/rule2_matrix.safe",
        "family": "rule2",
        "coverage_note": "Matrix trace and transpose keep bounded multidimensional indexing and explicit transposition assignments.",
        "source_fragments": [
            "function Trace",
            "function Transpose",
        ],
        "body_fragments": [
            "Sum := (Safe_Runtime.Wide_Integer (Sum) + Safe_Runtime.Wide_Integer (M (I, Col_Index (I))));",
            "for J in Col_Index loop",
            "M (I, J) := M (Row_Index (J), Col_Index (I));",
            "M (Row_Index (J), Col_Index (I)) := Temp;",
        ],
    },
    {
        "fixture": "tests/positive/rule2_slice.safe",
        "family": "rule2",
        "coverage_note": "Subrange iteration remains explicit through guarded bounds and direct in-range element access across the selected slice.",
        "source_fragments": [
            "function Last_In_Subrange",
            "type Buffer",
        ],
        "body_fragments": [
            "if (First <= Last) then",
            "for I in First .. Last loop",
            "Current := Buf (I);",
            "return Current;",
        ],
    },
    {
        "fixture": "tests/positive/rule3_average.safe",
        "family": "rule3",
        "coverage_note": "Division-by-constant lowering remains explicit and range-asserted before narrowing the result.",
        "source_fragments": [
            "function Compute_Average",
            "type Measurement",
        ],
        "body_fragments": [
            "Safe_Runtime.Wide_Integer (Total) / Safe_Runtime.Wide_Integer (2)",
            "return Measurement ((Safe_Runtime.Wide_Integer (Total) / Safe_Runtime.Wide_Integer (2)));",
        ],
    },
    {
        "fixture": "tests/positive/rule3_modulo.safe",
        "family": "rule3",
        "coverage_note": "Modulo lowering stays explicit for both fixed divisor and size-parameterized ring indexing.",
        "source_fragments": [
            "function Normalize_Angle",
            "function Ring_Index",
        ],
        "body_fragments": [
            "mod Safe_Runtime.Wide_Integer (360)",
            "mod Safe_Runtime.Wide_Integer (Size)",
        ],
    },
    {
        "fixture": "tests/positive/rule3_percent.safe",
        "family": "rule3",
        "coverage_note": "Percentage computation keeps the total-nonzero guard and explicit widened multiply/divide shape.",
        "source_fragments": [
            "function Compute_Percentage",
            "type Percentage",
        ],
        "body_fragments": [
            "if ((Total > 0) and then (Part <= Total)) then",
            "Safe_Runtime.Wide_Integer (Part) * Safe_Runtime.Wide_Integer (100)",
            "return Percentage (((Safe_Runtime.Wide_Integer (Part) * Safe_Runtime.Wide_Integer (100)) / Safe_Runtime.Wide_Integer (Total)));",
        ],
    },
    {
        "fixture": "tests/positive/rule3_remainder.safe",
        "family": "rule3",
        "coverage_note": "Remainder lowering and parity testing remain explicit, bounded, and prove-clean.",
        "source_fragments": [
            "function Compute_Remainder",
            "function Is_Even",
        ],
        "body_fragments": [
            "rem Safe_Runtime.Wide_Integer (M)",
            "return ((V rem 2) = 0);",
        ],
    },
    {
        "fixture": "tests/positive/rule4_conditional.safe",
        "family": "rule4",
        "coverage_note": "Conditional access dereference stays guarded by explicit null checks on both pointers.",
        "source_fragments": [
            "function Max_Of_Two",
            "type Config_Ptr is access Config_Value;",
        ],
        "body_fragments": [
            "if ((A /= null) and then (B /= null)) then",
            "return A.all;",
            "return B.all;",
        ],
    },
    {
        "fixture": "tests/positive/rule4_deref.safe",
        "family": "rule4",
        "coverage_note": "Not-null access parameters still lower to direct dereference reads and writes without extra null-guard noise.",
        "source_fragments": [
            "type Data_Ptr is not null access Data;",
            "function Write_Value",
        ],
        "spec_fragments": [
            "type Data_Ptr is not null access Data;",
        ],
        "body_fragments": [
            "return P.all;",
            "P.all := V;",
        ],
    },
    {
        "fixture": "tests/positive/rule4_factory.safe",
        "family": "rule4",
        "coverage_note": "Allocator-based factory returns and later field dereference remain explicit in the emitted body.",
        "source_fragments": [
            "function Create_Sensor",
            "function Read_Sensor",
        ],
        "body_fragments": [
            "return new Sensor_Data'(Id => Id, Value => Initial_Value);",
            "return S.all.Value;",
        ],
    },
    {
        "fixture": "tests/positive/rule4_linked_list.safe",
        "family": "rule4",
        "coverage_note": "Linked-list traversal keeps structural loop variants and observer-style pointer progression in emitted Ada.",
        "source_fragments": [
            "function Last_Value",
            "function Has_Tail",
        ],
        "body_fragments": [
            "Current : access constant Node := Head;",
            "pragma Loop_Variant (Structural => Current);",
            "Current := Current.all.Next;",
        ],
    },
    {
        "fixture": "tests/positive/rule4_optional.safe",
        "family": "rule4",
        "coverage_note": "Optional access values stay guarded through explicit null tests on read and presence-check paths.",
        "source_fragments": [
            "function Get_Or_Default",
            "function Has_Value",
        ],
        "body_fragments": [
            "if (P /= null) then",
            "return P.all;",
            "return (P /= null);",
        ],
    },
]


def sequential_proof_corpus() -> list[dict[str, Any]]:
    return [dict(item) for item in PR106_SEQUENTIAL_PROOF_CORPUS]


def corpus_paths() -> list[str]:
    return [item["fixture"] for item in PR106_SEQUENTIAL_PROOF_CORPUS]


def excluded_positive_concurrency_paths() -> list[str]:
    return list(PR106_EXCLUDED_POSITIVE_CONCURRENCY_CASES)
