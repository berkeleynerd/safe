from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from render_execution_status import render_dashboard


TRACKER_FIXTURE = {
    "schema_version": 1,
    "frozen_spec_sha": "abc1234",
    "active_task_id": None,
    "next_task_id": "PRX",
    "updated_at": "2026-03-09T00:00:00Z",
    "repo_facts": {
        "tests": {
            "positive": 1,
            "negative": 2,
            "golden": 3,
            "concurrency": 4,
            "diagnostics_golden": 5,
            "total": 15,
        }
    },
    "tasks": [
        {
            "id": "PRX",
            "title": "Example",
            "status": "planned",
            "depends_on": [],
            "acceptance": ["one", "two"],
            "evidence": ["execution/reports/example.json"],
            "blockers": [],
            "unblock_condition": "",
        }
    ],
}


class RenderExecutionStatusTests(unittest.TestCase):
    def test_render_dashboard_is_deterministic(self) -> None:
        rendered = render_dashboard(TRACKER_FIXTURE)
        self.assertEqual(rendered, render_dashboard(TRACKER_FIXTURE))
        self.assertTrue(rendered.endswith("\n"))

    def test_render_dashboard_contains_task_row_and_evidence(self) -> None:
        rendered = render_dashboard(TRACKER_FIXTURE)
        self.assertIn("| PRX | planned | -- | 1 |", rendered)
        self.assertIn("- **Evidence:**", rendered)
        self.assertIn("`execution/reports/example.json`", rendered)


if __name__ == "__main__":
    unittest.main()
