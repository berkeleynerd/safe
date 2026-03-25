from __future__ import annotations

import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest import mock


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import run_pr0694_output_contract_stability
from migrate_pr116_whitespace import rewrite_safe_source


class Pr0694OutputContractStabilityTests(unittest.TestCase):
    def test_generate_report_keeps_inline_fixture_out_of_compiler_obj(self) -> None:
        captured_inline_source: Path | None = None
        real_temporary_directory = tempfile.TemporaryDirectory

        @contextmanager
        def fixed_temp_root(*args: object, **kwargs: object):
            del args, kwargs
            with real_temporary_directory() as temp_dir:
                yield temp_dir

        def fake_run_emit_case(
            *,
            name: str,
            source: Path,
            **_kwargs: object,
        ) -> dict[str, object]:
            nonlocal captured_inline_source
            if name == "public_interface":
                captured_inline_source = source
                self.assertEqual(
                    source.read_text(encoding="utf-8"),
                    rewrite_safe_source(
                        run_pr0694_output_contract_stability.PUBLIC_INTERFACE_SOURCE
                    ),
                )
            return {"source": str(source)}

        with mock.patch.object(
            run_pr0694_output_contract_stability.tempfile,
            "TemporaryDirectory",
            side_effect=fixed_temp_root,
        ), mock.patch.object(
            run_pr0694_output_contract_stability,
            "run_emit_case",
            side_effect=fake_run_emit_case,
        ):
            run_pr0694_output_contract_stability.generate_report(
                safec=Path("/tmp/safec"),
                python="python3",
                env={},
            )

        self.assertIsNotNone(captured_inline_source)
        assert captured_inline_source is not None
        self.assertIn("inline-sources", captured_inline_source.parts)
        self.assertNotIn("obj", captured_inline_source.parts)
        self.assertFalse(
            run_pr0694_output_contract_stability.COMPILER_ROOT / "obj" in captured_inline_source.parents
        )


if __name__ == "__main__":
    unittest.main()
