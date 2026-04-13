#!/usr/bin/env python3
"""Snapshot or verify emitted Ada across the proved fixture corpus."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from _lib.harness_common import REPO_ROOT, sha256_file
from _lib.pr09_emit import file_hashes
from _lib.pr111_language_eval import safec_path
from _lib.project_cache import resolve_project_sources
from _lib.proof_inventory import EMITTED_PROOF_FIXTURES

SNAPSHOT_PATH = REPO_ROOT / "tests" / "emitted_ada_snapshot.json"
SNAPSHOT_VERSION = 1
SNAPSHOT_EXTRA_FIXTURES = [
    "tests/build/pr228_shared_loop_exit_condition_build.safe",
]


def repo_arg(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def emit_fixture(*, safec: Path, source: Path) -> dict[str, str]:
    with tempfile.TemporaryDirectory(prefix="safe-emitted-ada-") as tmp:
        root = Path(tmp)
        out_dir = root / "out"
        iface_dir = root / "iface"
        ada_dir = root / "ada"
        out_dir.mkdir()
        iface_dir.mkdir()
        ada_dir.mkdir()

        sources = resolve_project_sources(source)
        for unit in sources:
            argv = [
                str(safec),
                "emit",
                repo_arg(unit),
                "--out-dir",
                str(out_dir),
                "--interface-dir",
                str(iface_dir),
                "--ada-out-dir",
                str(ada_dir),
                "--interface-search-dir",
                str(iface_dir),
            ]
            completed = subprocess.run(
                argv,
                cwd=REPO_ROOT,
                env=os.environ.copy(),
                text=True,
                capture_output=True,
                check=False,
            )
            if completed.returncode != 0:
                detail = next(
                    (
                        line.strip()
                        for line in (completed.stderr + "\n" + completed.stdout).splitlines()
                        if line.strip()
                    ),
                    f"exit code {completed.returncode}",
                )
                raise RuntimeError(f"{repo_arg(source)}: emit failed for {unit.name}: {detail}")

        return {
            name: digest
            for name, digest in sorted(file_hashes(ada_dir).items())
            if name.endswith((".adb", ".ads"))
        }


def snapshot_fixture_paths() -> list[str]:
    return sorted(set(EMITTED_PROOF_FIXTURES) | set(SNAPSHOT_EXTRA_FIXTURES))


def build_manifest(*, safec: Path) -> dict[str, object]:
    fixtures: dict[str, dict[str, str]] = {}
    for fixture_rel in snapshot_fixture_paths():
        print(f"[snapshot_emitted_ada] {fixture_rel}", flush=True)
        fixtures[fixture_rel] = emit_fixture(safec=safec, source=REPO_ROOT / fixture_rel)
    return {
        "version": SNAPSHOT_VERSION,
        "compiler_hash": sha256_file(safec),
        "fixtures": fixtures,
    }


def write_snapshot(payload: dict[str, object]) -> None:
    SNAPSHOT_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_snapshot() -> dict[str, object]:
    if not SNAPSHOT_PATH.exists():
        raise RuntimeError(f"snapshot not found: {SNAPSHOT_PATH}")
    return json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))


def compare_snapshot(*, snapshot: dict[str, object], current_hash: str, safec: Path) -> int:
    snapshot_version = snapshot.get("version")
    if snapshot_version != SNAPSHOT_VERSION:
        raise RuntimeError(
            "snapshot version mismatch: "
            f"expected {SNAPSHOT_VERSION}, got {snapshot_version!r}"
        )

    snapshot_hash = snapshot.get("compiler_hash")
    if snapshot_hash != current_hash:
        print(
            "snapshot_emitted_ada: warning: compiler hash mismatch; "
            f"snapshot={snapshot_hash}, current={current_hash}; skipping check",
            file=sys.stderr,
        )
        return 0

    manifest_fixtures = snapshot.get("fixtures")
    if not isinstance(manifest_fixtures, dict):
        raise RuntimeError("snapshot fixtures payload must be a mapping")

    failures: list[str] = []
    expected_fixture_keys = sorted(str(item) for item in manifest_fixtures.keys())
    current_fixture_keys = snapshot_fixture_paths()
    if expected_fixture_keys != current_fixture_keys:
        missing = sorted(set(current_fixture_keys) - set(expected_fixture_keys))
        extra = sorted(set(expected_fixture_keys) - set(current_fixture_keys))
        if missing:
            failures.append("snapshot missing fixtures: " + ", ".join(missing))
        if extra:
            failures.append("snapshot has extra fixtures: " + ", ".join(extra))

    for fixture_rel in current_fixture_keys:
        print(f"[snapshot_emitted_ada] {fixture_rel}", flush=True)
        actual = emit_fixture(safec=safec, source=REPO_ROOT / fixture_rel)
        expected = manifest_fixtures.get(fixture_rel)
        if expected is None:
            failures.append(f"MISMATCH: {fixture_rel}\n  fixture missing from snapshot")
            continue
        if not isinstance(expected, dict):
            failures.append(f"MISMATCH: {fixture_rel}\n  snapshot entry is not a file-hash mapping")
            continue

        expected_files = {str(name): str(digest) for name, digest in expected.items()}
        missing_files = sorted(set(expected_files) - set(actual))
        extra_files = sorted(set(actual) - set(expected_files))
        changed_files = sorted(
            name for name in set(expected_files) & set(actual) if expected_files[name] != actual[name]
        )
        if not (missing_files or extra_files or changed_files):
            continue

        lines = [f"MISMATCH: {fixture_rel}"]
        for name in missing_files:
            lines.append(f"  missing {name}: expected {expected_files[name]}")
        for name in extra_files:
            lines.append(f"  extra {name}: got {actual[name]}")
        for name in changed_files:
            lines.append(f"  {name}: expected {expected_files[name]} got {actual[name]}")
        failures.append("\n".join(lines))

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify emitted Ada against the committed snapshot")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    safec = safec_path()
    if args.check:
        snapshot = load_snapshot()
        return compare_snapshot(snapshot=snapshot, current_hash=sha256_file(safec), safec=safec)

    payload = build_manifest(safec=safec)
    write_snapshot(payload)
    print(f"wrote {repo_arg(SNAPSHOT_PATH)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
