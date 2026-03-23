from __future__ import annotations

import io
import json
import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import safe_cli
import safe_lsp
from _lib import pr111_language_eval


class _Writer:
    def __init__(self) -> None:
        self.payloads: list[dict[str, object]] = []

    def send(self, payload: dict[str, object]) -> None:
        self.payloads.append(payload)


class Pr111LanguageEvalTests(unittest.TestCase):
    def test_safe_build_paths_use_hidden_build_root(self) -> None:
        source = Path("/tmp/demo.safe")
        paths = pr111_language_eval.safe_build_paths(source)
        self.assertEqual(paths["root"], Path("/tmp/.safe-build/demo"))
        self.assertEqual(paths["out"], Path("/tmp/.safe-build/demo/out"))
        self.assertEqual(paths["iface"], Path("/tmp/.safe-build/demo/iface"))
        self.assertEqual(paths["ada"], Path("/tmp/.safe-build/demo/ada"))
        self.assertEqual(paths["obj"], Path("/tmp/.safe-build/demo/obj"))
        self.assertEqual(paths["gpr"], Path("/tmp/.safe-build/demo/build.gpr"))
        self.assertEqual(paths["main"], Path("/tmp/.safe-build/demo/main.adb"))

    def test_safe_build_project_text_includes_exec_dir_and_optional_gnat_adc(self) -> None:
        text = pr111_language_eval.safe_build_project_text(
            has_gnat_adc=True,
            platform_name="darwin",
        )
        self.assertIn('for Source_Dirs use (".", "ada");', text)
        self.assertIn('for Object_Dir use "obj";', text)
        self.assertIn('for Exec_Dir use ".";', text)
        self.assertIn('for Main use ("main.adb");', text)
        self.assertIn('for Default_Switches ("Ada") use ("-gnatec=ada/gnat.adc");', text)
        self.assertNotIn("Sdk_Root := External", text)
        self.assertNotIn("package Linker is", text)

    def test_safe_build_main_text_withs_emitted_unit(self) -> None:
        text = pr111_language_eval.safe_build_main_text("binary_search")
        self.assertEqual(
            text,
            "with binary_search;\n\nprocedure Main is\nbegin\n   null;\nend Main;\n",
        )

    def test_safe_cli_build_dispatches_to_safe_build(self) -> None:
        with mock.patch.object(safe_cli, "safe_build", return_value=0) as safe_build:
            self.assertEqual(safe_cli.main(["build", "demo.safe"]), 0)
        safe_build.assert_called_once_with("demo.safe")

    def test_safe_cli_check_pass_through_preserves_subcommand_args(self) -> None:
        with mock.patch.object(safe_cli, "pass_through", return_value=7) as pass_through:
            self.assertEqual(
                safe_cli.main(["check", "--diag-json", "demo.safe"]),
                7,
            )
        pass_through.assert_called_once_with("check", ["--diag-json", "demo.safe"])

    def test_safe_cli_help_prints_usage_to_stdout(self) -> None:
        with mock.patch.object(sys, "stdout", new=io.StringIO()) as stdout:
            result = safe_cli.main(["--help"])
        self.assertEqual(result, 0)
        self.assertIn("safe build <file.safe>", stdout.getvalue())

    def test_file_uri_to_path_handles_file_scheme(self) -> None:
        self.assertEqual(
            safe_lsp.file_uri_to_path("file:///tmp/demo.safe"),
            Path("/tmp/demo.safe"),
        )
        self.assertEqual(
            safe_lsp.file_uri_to_path("file:///C:/work/demo.safe"),
            Path("C:/work/demo.safe"),
        )
        self.assertEqual(
            safe_lsp.file_uri_to_path("file://server/share/demo.safe"),
            Path("//server/share/demo.safe"),
        )
        self.assertIsNone(safe_lsp.file_uri_to_path("untitled:demo.safe"))

    def test_span_to_range_converts_to_zero_based_lsp_positions(self) -> None:
        converted = safe_lsp.span_to_range(
            {
                "start_line": 3,
                "start_col": 5,
                "end_line": 3,
                "end_col": 11,
            }
        )
        self.assertEqual(
            converted,
            {
                "start": {"line": 2, "character": 4},
                "end": {"line": 2, "character": 11},
            },
        )

    def test_lsp_initialize_and_close_publish_expected_messages(self) -> None:
        writer = _Writer()
        server = safe_lsp.SafeLanguageServer(writer)

        self.assertTrue(
            server.process_message({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        )
        self.assertEqual(writer.payloads[0]["id"], 1)
        self.assertIn("capabilities", writer.payloads[0]["result"])

        self.assertTrue(
            server.process_message(
                {
                    "jsonrpc": "2.0",
                    "method": "textDocument/didClose",
                    "params": {"textDocument": {"uri": "file:///tmp/demo.safe"}},
                }
            )
        )
        self.assertEqual(writer.payloads[1]["method"], "textDocument/publishDiagnostics")
        self.assertEqual(writer.payloads[1]["params"]["diagnostics"], [])

    def test_vscode_artifacts_parse_as_expected(self) -> None:
        repo_root = Path(__file__).resolve().parents[2]
        package_payload = json.loads(
            (repo_root / "editors" / "vscode" / "package.json").read_text(encoding="utf-8")
        )
        grammar_payload = json.loads(
            (
                repo_root / "editors" / "vscode" / "syntaxes" / "safe.tmLanguage.json"
            ).read_text(encoding="utf-8")
        )
        config_payload = json.loads(
            (repo_root / "editors" / "vscode" / "language-configuration.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertEqual(package_payload["main"], "./extension.js")
        self.assertEqual(package_payload["contributes"]["languages"][0]["id"], "safe")
        self.assertEqual(grammar_payload["scopeName"], "source.safe")
        keyword_matchers = grammar_payload["repository"]["keywords"]["patterns"]
        type_matchers = grammar_payload["repository"]["types"]["patterns"]
        builtin_matchers = grammar_payload["repository"]["builtins"]["patterns"]
        tuple_selector_matchers = grammar_payload["repository"]["tuple_selectors"]["patterns"]
        character_matchers = grammar_payload["repository"]["characters"]["patterns"]
        self.assertIn("case", keyword_matchers[0]["match"])
        self.assertIn("others", keyword_matchers[0]["match"])
        self.assertIn("returns", keyword_matchers[0]["match"])
        self.assertIn("to", keyword_matchers[0]["match"])
        self.assertNotIn("procedure", keyword_matchers[0]["match"])
        self.assertNotIn("elsif", keyword_matchers[0]["match"])
        self.assertIn("Character", type_matchers[0]["match"])
        self.assertIn("String", type_matchers[0]["match"])
        self.assertIn("result", type_matchers[0]["match"])
        self.assertIn("ok", builtin_matchers[0]["match"])
        self.assertIn("fail", builtin_matchers[0]["match"])
        self.assertIn("(?<!\\d)\\.\\d+\\b", tuple_selector_matchers[0]["match"])
        self.assertEqual(character_matchers[0]["name"], "constant.character.safe")
        self.assertEqual(config_payload["comments"]["lineComment"], "--")


if __name__ == "__main__":
    unittest.main()
