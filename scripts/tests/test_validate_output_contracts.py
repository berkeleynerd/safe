from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from validate_output_contracts import (
    require_positive_int,
    validate_mir_graphs,
    validate_optional_mir_channels,
    validate_safei_payload,
    validate_optional_typed_channels,
    validate_optional_typed_tasks,
    validate_span,
)


def valid_span() -> dict[str, int]:
    return {
        "start_line": 1,
        "start_col": 1,
        "end_line": 1,
        "end_col": 1,
    }


def valid_type() -> dict[str, object]:
    return {"name": "Integer", "kind": "integer", "low": 0, "high": 10}


def valid_safei() -> dict[str, object]:
    return {
        "format": "safei-v1",
        "package_name": "Sample",
        "dependencies": ["Provider"],
        "executables": [],
        "public_declarations": [],
        "types": [valid_type()],
        "subtypes": [],
        "channels": [],
        "objects": [
            {
                "name": "Max_Count",
                "type": valid_type(),
                "is_constant": True,
                "static_value_kind": "integer",
                "static_value": 4,
                "span": valid_span(),
            }
        ],
        "subprograms": [
            {
                "name": "Next",
                "kind": "function",
                "signature": "function Next (Value: Integer) return Integer",
                "params": [
                    {
                        "name": "Value",
                        "mode": "in",
                        "type": valid_type(),
                        "span": valid_span(),
                    }
                ],
                "has_return_type": True,
                "return_type": valid_type(),
                "return_is_access_def": False,
                "span": valid_span(),
            }
        ],
        "effect_summaries": [
            {
                "name": "Next",
                "signature": "function Next (Value: Integer) return Integer",
                "reads": [],
                "writes": [],
                "inputs": ["param:Value"],
                "outputs": ["return"],
                "depends": [{"output_name": "return", "inputs": ["param:Value"]}],
            }
        ],
        "channel_access_summaries": [
            {
                "name": "Next",
                "signature": "function Next (Value: Integer) return Integer",
                "channels": [],
            }
        ],
    }


class ValidateOutputContractsTests(unittest.TestCase):
    def test_require_positive_int_rejects_boolean(self) -> None:
        with self.assertRaises(ValueError):
            require_positive_int(True, "payload.capacity")

    def test_validate_span_rejects_boolean_coordinates(self) -> None:
        with self.assertRaises(ValueError):
            validate_span(
                {
                    "start_line": True,
                    "start_col": 1,
                    "end_line": 1,
                    "end_col": 1,
                },
                "payload.span",
            )

    def test_validate_optional_typed_tasks_rejects_boolean_priority(self) -> None:
        with self.assertRaises(ValueError):
            validate_optional_typed_tasks(
                [
                    {
                        "name": "Worker",
                        "priority": False,
                        "has_explicit_priority": True,
                        "span": valid_span(),
                    }
                ],
                "typed.tasks",
            )

    def test_validate_optional_typed_channels_rejects_boolean_capacity(self) -> None:
        with self.assertRaises(ValueError):
            validate_optional_typed_channels(
                [
                    {
                        "name": "Data_Ch",
                        "is_public": False,
                        "element_type": {"name": "Integer", "kind": "integer"},
                        "capacity": True,
                        "span": valid_span(),
                    }
                ],
                "typed.channels",
            )

    def test_validate_optional_mir_channels_rejects_boolean_capacity(self) -> None:
        with self.assertRaises(ValueError):
            validate_optional_mir_channels(
                [
                    {
                        "name": "Data_Ch",
                        "element_type": {"name": "Integer", "kind": "integer"},
                        "capacity": True,
                        "span": valid_span(),
                    }
                ],
                "mir.channels",
            )

    def test_validate_mir_graphs_rejects_boolean_task_priority(self) -> None:
        with self.assertRaises(ValueError):
            validate_mir_graphs(
                [
                    {
                        "name": "Worker",
                        "kind": "task",
                        "entry_bb": "bb0",
                        "priority": True,
                        "has_explicit_priority": False,
                        "span": valid_span(),
                        "blocks": [],
                    }
                ],
                "mir.graphs",
            )

    def test_validate_mir_graphs_rejects_non_boolean_explicit_priority_flag(self) -> None:
        with self.assertRaises(ValueError):
            validate_mir_graphs(
                [
                    {
                        "name": "Worker",
                        "kind": "task",
                        "entry_bb": "bb0",
                        "priority": 1,
                        "has_explicit_priority": 1,
                        "span": valid_span(),
                        "blocks": [],
                    }
                ],
                "mir.graphs",
            )

    def test_validate_mir_graphs_rejects_task_return_type(self) -> None:
        with self.assertRaises(ValueError):
            validate_mir_graphs(
                [
                    {
                        "name": "Worker",
                        "kind": "task",
                        "entry_bb": "bb0",
                        "priority": 1,
                        "has_explicit_priority": False,
                        "return_type": {"name": "Integer", "kind": "integer"},
                        "span": valid_span(),
                        "blocks": [],
                    }
                ],
                "mir.graphs",
            )

    def test_validate_safei_payload_accepts_safei_v1(self) -> None:
        payload = validate_safei_payload(valid_safei(), path="sample.safei.json")
        self.assertEqual(payload["format"], "safei-v1")

    def test_validate_safei_payload_rejects_wrong_format(self) -> None:
        payload = valid_safei()
        payload["format"] = "safei-v0"
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_rejects_null_channels(self) -> None:
        payload = valid_safei()
        payload["channels"] = None
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_rejects_malformed_params(self) -> None:
        payload = valid_safei()
        payload["subprograms"][0]["params"] = [{"name": "Value", "mode": "in", "span": valid_span()}]
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_rejects_malformed_effect_summary(self) -> None:
        payload = valid_safei()
        payload["effect_summaries"][0]["depends"] = [{"output_name": "return", "inputs": True}]
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_rejects_unknown_summary_target(self) -> None:
        payload = valid_safei()
        payload["effect_summaries"][0]["name"] = "Missing"
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_accepts_boolean_constant_payload(self) -> None:
        payload = valid_safei()
        payload["objects"] = [
            {
                "name": "Default_Active",
                "type": {"name": "Boolean", "kind": "integer", "low": 0, "high": 1},
                "is_constant": True,
                "static_value_kind": "boolean",
                "static_value": True,
                "span": valid_span(),
            }
        ]
        validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_rejects_static_kind_without_constant(self) -> None:
        payload = valid_safei()
        payload["objects"] = [
            {
                "name": "Max_Count",
                "type": valid_type(),
                "static_value_kind": "integer",
                "static_value": 4,
                "span": valid_span(),
            }
        ]
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_rejects_kind_value_mismatch(self) -> None:
        payload = valid_safei()
        payload["objects"][0]["static_value"] = True
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")

    def test_validate_safei_payload_rejects_value_without_kind(self) -> None:
        payload = valid_safei()
        del payload["objects"][0]["static_value_kind"]
        with self.assertRaises(ValueError):
            validate_safei_payload(payload, path="sample.safei.json")


if __name__ == "__main__":
    unittest.main()
