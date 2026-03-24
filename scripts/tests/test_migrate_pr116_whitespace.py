from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import migrate_pr116_whitespace


class MigratePr116WhitespaceTests(unittest.TestCase):
    def test_rewrite_safe_source_rewrites_function_and_if_blocks(self) -> None:
        original = (
            "package Demo is\n"
            "   function Build returns integer is\n"
            "   begin\n"
            "      if True then\n"
            "         return 1;\n"
            "      end if;\n"
            "   end Build;\n"
            "end Demo;\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertIn("package Demo\n", rewritten)
        self.assertIn("   function Build returns integer\n", rewritten)
        self.assertIn("      if True\n", rewritten)
        self.assertNotIn("then\n", rewritten)
        self.assertNotIn("end if;\n", rewritten)
        self.assertNotIn("end Demo;\n", rewritten)

    def test_rewrite_safe_source_preserves_declare_block(self) -> None:
        original = (
            "package Demo is\n"
            "   function Build returns integer is\n"
            "   begin\n"
            "      declare\n"
            "         Temp : integer = 1;\n"
            "      begin\n"
            "         if Temp == 1 then\n"
            "            return Temp;\n"
            "         end if;\n"
            "      end;\n"
            "   end Build;\n"
            "end Demo;\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertIn("      declare\n", rewritten)
        self.assertIn("      begin\n", rewritten)
        self.assertIn("      end;\n", rewritten)
        self.assertIn("         if Temp == 1\n", rewritten)
        self.assertNotIn("         end if;\n", rewritten)

    def test_rewrite_safe_source_rewrites_case_record_and_select(self) -> None:
        original = (
            "package Demo is\n"
            "   type Flag is range 0 to 1;\n"
            "   type Item is record\n"
            "      case Flag is\n"
            "         when 0 then\n"
            "            Value : integer;\n"
            "         end when;\n"
            "         when others then\n"
            "            Other : integer;\n"
            "         end when;\n"
            "      end case;\n"
            "   end record;\n"
            "   function Pick returns integer is\n"
            "   begin\n"
            "      select\n"
            "         delay 1.0 then\n"
            "            return 1;\n"
            "      or\n"
            "         when Msg : integer from Ch then\n"
            "            return Msg;\n"
            "      end select;\n"
            "   end Pick;\n"
            "end Demo;\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertIn("      case Flag\n", rewritten)
        self.assertIn("         when 0\n", rewritten)
        self.assertIn("      select\n", rewritten)
        self.assertIn("         delay 1.0\n", rewritten)
        self.assertIn("         when Msg : integer from Ch\n", rewritten)
        self.assertNotIn("end case;\n", rewritten)
        self.assertNotIn("end record;\n", rewritten)
        self.assertNotIn("end select;\n", rewritten)

    def test_rewrite_safe_source_splits_inline_when_body(self) -> None:
        original = (
            "package Demo is\n"
            "   type Result (OK : Boolean = False) is record\n"
            "      case OK is\n"
            "         when True then Value : integer;\n"
            "         when False then Error : integer;\n"
            "      end case;\n"
            "   end record;\n"
            "end Demo;\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertIn("         when True\n", rewritten)
        self.assertIn("            Value : integer;\n", rewritten)
        self.assertIn("         when False\n", rewritten)
        self.assertIn("            Error : integer;\n", rewritten)
        self.assertNotIn("when True then", rewritten)

    def test_rewrite_safe_source_preserves_comments(self) -> None:
        original = (
            "package Demo is -- package header\n"
            "   function Build returns integer is -- signature\n"
            "   begin\n"
            "      if True then -- branch\n"
            "         return 1;\n"
            "      end if;\n"
            "   end Build;\n"
            "end Demo;\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertIn("package Demo -- package header\n", rewritten)
        self.assertIn("   function Build returns integer -- signature\n", rewritten)
        self.assertIn("      if True -- branch\n", rewritten)

    def test_rewrite_safe_source_strips_semicolonless_end_lines(self) -> None:
        original = (
            "package Demo is\n"
            "   function Build returns integer is\n"
            "   begin\n"
            "      if True\n"
            "         return 1\n"
            "      end if\n"
            "   end Build\n"
            "end Demo\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertNotIn("end if\n", rewritten)
        self.assertNotIn("end Build\n", rewritten)
        self.assertNotIn("end Demo\n", rewritten)

    def test_rewrite_safe_source_collapses_else_followed_by_if(self) -> None:
        original = (
            "package Demo is\n"
            "   function Pick (A : Integer) returns Integer is\n"
            "   begin\n"
            "      if A > 10 then\n"
            "         return 10;\n"
            "      else\n"
            "      if A > 0 then\n"
            "         return A;\n"
            "      else\n"
            "         return 0;\n"
            "      end if;\n"
            "      end if;\n"
            "   end Pick;\n"
            "end Demo;\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertIn("      else if A > 0\n", rewritten)
        self.assertNotIn("      else\n      if A > 0", rewritten)

    def test_rewrite_safe_source_is_idempotent_for_already_migrated_signature(self) -> None:
        original = (
            "package Demo\n"
            "   function Build returns Integer\n"
            "      return 1;\n"
            "   type Count is range 0 to 10;\n"
        )
        rewritten = migrate_pr116_whitespace.rewrite_safe_source(original)
        self.assertEqual(rewritten, original)
        self.assertIn("   type Count is range 0 to 10;\n", rewritten)


if __name__ == "__main__":
    unittest.main()
