from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import migrate_pr114_syntax


class MigratePr114SyntaxTests(unittest.TestCase):
    def test_rewrite_safe_source_converts_full_quartet(self) -> None:
        original = (
            "procedure Search (Arr : Data;\n"
            "                  Key : Integer) is\n"
            "begin\n"
            "   if Key > 0 then\n"
            "      return;\n"
            "   elsif Key < 0 then\n"
            "      return;\n"
            "   end if;\n"
            "   for I in 1 .. 3 loop\n"
            "      null;\n"
            "   end loop;\n"
            "end Search;\n"
        )
        rewritten = migrate_pr114_syntax.rewrite_safe_source(original)
        self.assertIn("function Search", rewritten)
        self.assertIn("else if Key < 0 then", rewritten)
        self.assertIn("for I in 1 to 3 loop", rewritten)
        self.assertNotIn("elsif", rewritten)
        self.assertNotIn("..", rewritten)
        self.assertIn("return;", rewritten)

    def test_rewrite_safe_source_updates_signature_return_only(self) -> None:
        original = (
            "function Lookup (Key : Integer)\n"
            "                 return Integer is\n"
            "begin\n"
            "   return Key;\n"
            "end Lookup;\n"
        )
        rewritten = migrate_pr114_syntax.rewrite_safe_source(original)
        self.assertIn("returns Integer is", rewritten)
        self.assertEqual(rewritten.count("returns"), 1)
        self.assertIn("return Key;", rewritten)

    def test_rewrite_safe_source_handles_public_declarations(self) -> None:
        original = (
            "public procedure Bump (Ref : access Payload) is\n"
            "begin\n"
            "   null;\n"
            "end Bump;\n"
            "\n"
            "public function Read_Value (Ref : access constant Payload) return Integer is\n"
            "begin\n"
            "   return 0;\n"
            "end Read_Value;\n"
        )
        rewritten = migrate_pr114_syntax.rewrite_safe_source(original)
        self.assertIn("public function Bump", rewritten)
        self.assertIn("public function Read_Value", rewritten)
        self.assertIn("returns Integer is", rewritten)

    def test_rewrite_safe_source_preserves_literals_and_comments(self) -> None:
        original = (
            "function Describe returns String is\n"
            "begin\n"
            "   -- elsif and 1 .. 3 are documentation only\n"
            "   return \"elsif ..\";\n"
            "end Describe;\n"
        )
        rewritten = migrate_pr114_syntax.rewrite_safe_source(original)
        self.assertIn('-- elsif and 1 .. 3 are documentation only', rewritten)
        self.assertIn('return "elsif ..";', rewritten)
        self.assertIn("function Describe returns String is", rewritten)


if __name__ == "__main__":
    unittest.main()
