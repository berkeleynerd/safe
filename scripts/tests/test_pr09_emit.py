from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from _lib import pr09_emit


class Pr09EmitTests(unittest.TestCase):
    def test_project_text_includes_compiler_without_platform_linker_stanza(self) -> None:
        text = pr09_emit.emitted_ada_project_text(has_gnat_adc=True, platform_name="darwin")
        self.assertIn("package Compiler is", text)
        self.assertIn('for Default_Switches ("Ada") use ("-gnatec=gnat.adc");', text)
        self.assertNotIn("Sdk_Root := External", text)
        self.assertNotIn("package Linker is", text)

    def test_project_text_omits_linker_when_gnat_adc_is_absent(self) -> None:
        text = pr09_emit.emitted_ada_project_text(has_gnat_adc=False, platform_name="darwin")
        self.assertNotIn("package Compiler is", text)
        self.assertNotIn("Sdk_Root := External", text)
        self.assertNotIn("package Linker is", text)

    def test_project_text_is_platform_independent(self) -> None:
        text = pr09_emit.emitted_ada_project_text(has_gnat_adc=True, platform_name="linux")
        self.assertNotIn("Sdk_Root := External", text)
        self.assertIn("package Compiler is", text)
        self.assertNotIn("package Linker is", text)

    def test_write_project_reflects_gnat_adc_presence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            ada_dir = Path(temp_dir)
            (ada_dir / "gnat.adc").write_text("pragma Profile(Jorvik);\n", encoding="utf-8")
            gpr_path = pr09_emit.write_emitted_ada_project(ada_dir, platform_name="darwin")
            text = gpr_path.read_text(encoding="utf-8")
            self.assertIn("package Compiler is", text)
            self.assertNotIn("package Linker is", text)

    def test_compile_command_adds_gnat_adc_explicitly(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            ada_dir = Path(temp_dir)
            (ada_dir / "sample.adb").write_text("procedure Sample is begin null; end Sample;\n", encoding="utf-8")
            gpr_path = ada_dir / "build.gpr"
            gpr_path.write_text("project Build is end Build;\n", encoding="utf-8")

            command = pr09_emit.compile_emitted_ada_command(ada_dir=ada_dir, gpr_path=gpr_path)
            self.assertNotIn("-cargs", command)

            (ada_dir / "gnat.adc").write_text("pragma Profile(Jorvik);\n", encoding="utf-8")
            command = pr09_emit.compile_emitted_ada_command(ada_dir=ada_dir, gpr_path=gpr_path)
            self.assertIn("-cargs", command)
            self.assertIn(f"-gnatec={ada_dir / 'gnat.adc'}", command)


if __name__ == "__main__":
    unittest.main()
