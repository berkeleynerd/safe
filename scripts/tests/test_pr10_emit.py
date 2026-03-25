from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from _lib import pr10_emit


class Pr10EmitTests(unittest.TestCase):
    def test_selected_corpus_covers_expected_categories(self) -> None:
        observed = {item["coverage"] for item in pr10_emit.selected_emitted_corpus()}
        self.assertEqual(observed, pr10_emit.EXPECTED_COVERAGE)

    def test_parse_gnatprove_summary(self) -> None:
        summary = pr10_emit.parse_gnatprove_summary(
            """tool chatter
=========================
Summary of SPARK analysis
=========================

---------------------------------------------------------------------------------
SPARK Analysis results        Total       Flow     Provers   Justified   Unproved
---------------------------------------------------------------------------------
Data Dependencies                 1          1           .           .          .
Run-time Checks                   5          .    5 (CVC5)           .          .
Assertions                        1          .    1 (CVC5)           .          .
Termination                       1          1           .           .          .
---------------------------------------------------------------------------------
Total                             8    2 (25%)    6 (75%)           .          .
"""
        )
        self.assertEqual(summary["total"]["total"]["count"], 8)
        self.assertEqual(summary["total"]["flow"]["count"], 2)
        self.assertEqual(summary["total"]["provers"]["count"], 6)
        self.assertEqual(summary["total"]["justified"]["count"], 0)
        self.assertEqual(summary["total"]["unproved"]["count"], 0)
        self.assertEqual(
            summary["rows"]["Run-time Checks"]["provers"]["detail"],
            "CVC5",
        )

    def test_parse_gnatprove_summary_rejects_missing_total(self) -> None:
        with self.assertRaises(RuntimeError):
            pr10_emit.parse_gnatprove_summary(
                """---------------------------------------------------------------------------------
SPARK Analysis results        Total       Flow     Provers   Justified   Unproved
---------------------------------------------------------------------------------
Run-time Checks                   5          .    5 (CVC5)           .          .
---------------------------------------------------------------------------------
"""
            )

    def test_parse_gnatprove_summary_rejects_malformed_rows(self) -> None:
        with self.assertRaises(RuntimeError):
            pr10_emit.parse_gnatprove_summary(
                """---------------------------------------------------------------------------------
SPARK Analysis results        Total       Flow     Provers   Justified   Unproved
---------------------------------------------------------------------------------
Run-time Checks 5 . 5 (CVC5) . .
---------------------------------------------------------------------------------
Total                             5          .    5 (CVC5)           .          .
"""
            )

    def test_gnatprove_command_adds_gnat_adc_explicitly(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            ada_dir = Path(temp_dir)
            with mock.patch.object(pr10_emit, "find_command", return_value="/tmp/gnatprove"):
                command = pr10_emit.gnatprove_command(
                    gpr_path=ada_dir / "build.gpr",
                    ada_dir=ada_dir,
                    mode="prove",
                )
                self.assertEqual(command[:4], [pr10_emit.alr_command(), "exec", "--", "/tmp/gnatprove"])
                self.assertNotIn("-cargs", command)
                (ada_dir / "gnat.adc").write_text("pragma Profile(Jorvik);\n", encoding="utf-8")
                command = pr10_emit.gnatprove_command(
                    gpr_path=ada_dir / "build.gpr",
                    ada_dir=ada_dir,
                    mode="flow",
                )
                self.assertIn("-cargs", command)
                self.assertIn(f"-gnatec={ada_dir / 'gnat.adc'}", command)

    def test_golden_pipeline_uses_in_out_try_receive_without_failure_default(self) -> None:
        spec = (
            pr10_emit.REPO_ROOT / "tests" / "golden" / "golden_pipeline" / "pipeline.ads"
        ).read_text(encoding="utf-8")
        body = (
            pr10_emit.REPO_ROOT / "tests" / "golden" / "golden_pipeline" / "pipeline.adb"
        ).read_text(encoding="utf-8")
        self.assertIn("procedure Try_Receive (Value : in out Sample; Success : out Boolean);", spec)
        self.assertIn("procedure Try_Receive (Value : in out Sample; Success : out Boolean) is", body)
        self.assertNotIn("Value := Sample'First;", body)


if __name__ == "__main__":
    unittest.main()
