#!/usr/bin/env python3
"""Run the PR06.9.12 performance and scale sanity gate."""

from __future__ import annotations

import argparse
import os
import re
import statistics
import tempfile
import time
from pathlib import Path
from typing import Any

from _lib.gate_expectations import (
    PR05_POSITIVE_CASES,
    PR06_POSITIVE_CASES,
    PR07_RESULT_POSITIVE_CASES,
    PR07_RULE5_POSITIVE_CASES,
)
from _lib.harness_common import (
    display_path,
    ensure_sdkroot,
    finalize_deterministic_report,
    find_command,
    normalize_text,
    require,
    require_repo_command,
    run,
    write_report,
)
from migrate_pr114_syntax import split_segments
from validate_execution_state import check_performance_scale_sanity, performance_scale_sanity_report


REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILER_ROOT = REPO_ROOT / "compiler_impl"
DEFAULT_REPORT = REPO_ROOT / "execution" / "reports" / "pr06912-performance-scale-sanity-report.json"

CHECK_SCENARIOS = [
    REPO_ROOT / "tests" / "positive" / "rule1_accumulate.safe",
    REPO_ROOT / "tests" / "positive" / "rule2_binary_search.safe",
    REPO_ROOT / "tests" / "positive" / "ownership_borrow.safe",
]
EMIT_SCENARIOS = CHECK_SCENARIOS
ANALYZE_SCENARIOS = [
    COMPILER_ROOT / "tests" / "mir_validation" / "valid_mir_v2.json",
    COMPILER_ROOT / "tests" / "mir_analysis" / "pr06_double_move.json",
    COMPILER_ROOT / "tests" / "mir_analysis" / "pr0695_anonymous_access_reassign_parity.json",
]

CHECK_REPETITIONS = 5
EMIT_REPETITIONS = 3
ANALYZE_REPETITIONS = 5

CHECK_MEDIAN_BUDGET_MS = 500.0
EMIT_MEDIAN_BUDGET_MS = 1000.0
ANALYZE_MEDIAN_BUDGET_MS = 500.0
CHECK_SWEEP_BUDGET_MS = 15000.0
MIR_SWEEP_BUDGET_MS = 10000.0

GROWTH_RATIO_CAPS = {
    "check_rule2_vs_rule1": 8.0,
    "emit_rule2_vs_rule1": 8.0,
    "analyze_reassign_vs_valid": 8.0,
}

SIZE_RATIO_CAPS = {
    "total": 64.0,
    "ast": 32.0,
    "typed": 32.0,
    "mir": 16.0,
    "safei": 2.0,
}

DECLARATION_START_RE = re.compile(r"^\s*(?:public\s+)?function\b")
FUNCTION_DECL_RE = re.compile(r"^(\s*(?:public\s+)?)function\b")
NO_RESULT_SIGNATURE_KIND_RE = re.compile(r'"kind":"function","signature":"function(?P<sig>\s+[A-Za-z_][^"]*)"')
SIGNATURE_RETURNS_RE = re.compile(r'("signature":"function[^"]*?)\breturns\b')
MIR_VOID_KIND_RE = re.compile(
    r'"kind":"function"(?P<middle>,"entry_bb":"[^"]+","span":\{[^{}]*\},"return_type":null)'
)


def repo_arg(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def legacy_surface_normalize(text: str) -> str:
    lines = text.splitlines(keepends=True)
    rewritten: list[str] = []
    inside_signature = False
    paren_depth = 0

    for line in lines:
        segments = split_segments(line)
        visible_code = "".join(segment for kind, segment in segments if kind == "code")
        if DECLARATION_START_RE.match(visible_code):
            inside_signature = True
            paren_depth = 0

        has_returns = "returns" in visible_code
        replaced_returns = False
        first_code = True
        updated_segments: list[str] = []

        for kind, segment in segments:
            if kind != "code":
                updated_segments.append(segment)
                continue

            updated = segment
            if first_code and inside_signature and not has_returns:
                updated = FUNCTION_DECL_RE.sub(r"\1procedure", updated, count=1)
                first_code = False
            elif first_code:
                first_code = False

            if inside_signature and has_returns and not replaced_returns and re.search(r"\breturns\b", updated):
                updated = re.sub(r"\breturns\b", "return", updated, count=1)
                replaced_returns = True

            updated = re.sub(r"\belse\s+if\b", "elsif", updated)
            updated_segments.append(updated)

        rewritten_line = "".join(updated_segments)
        rewritten.append(rewritten_line)

        visible_rewritten = "".join(
            segment for kind, segment in split_segments(rewritten_line) if kind == "code"
        )
        if inside_signature:
            paren_depth += visible_rewritten.count("(") - visible_rewritten.count(")")
            if paren_depth <= 0 and (
                re.search(r"\bis\b", visible_rewritten) or visible_rewritten.rstrip().endswith(";")
            ):
                inside_signature = False
                paren_depth = 0

    return "".join(rewritten)


def stable_source_size(path: Path, *, text: str) -> int:
    if path.suffix == ".safe":
        return len(legacy_surface_normalize(text).encode("utf-8"))
    return path.stat().st_size


def stable_typed_or_safei_text(text: str) -> str:
    def replace_signature(match: re.Match[str]) -> str:
        sig = match.group("sig")
        full_sig = "function" + sig
        if " return " in full_sig or " returns " in full_sig:
            return match.group(0)
        return f'"kind":"procedure","signature":"procedure{sig}"'

    updated = NO_RESULT_SIGNATURE_KIND_RE.sub(replace_signature, text)
    return SIGNATURE_RETURNS_RE.sub(r"\1return", updated)


def stable_mir_text(text: str) -> str:
    return MIR_VOID_KIND_RE.sub(r'"kind":"procedure"\g<middle>', text)


def stable_emitted_artifact_size(path: Path, *, temp_root: Path | None = None) -> int:
    text = normalize_text(path.read_text(encoding="utf-8"), temp_root=temp_root, repo_root=REPO_ROOT)
    if path.name.endswith(".typed.json") or path.name.endswith(".safei.json"):
        return len(stable_typed_or_safei_text(text).encode("utf-8"))
    if path.name.endswith(".mir.json"):
        return len(stable_mir_text(text).encode("utf-8"))
    return path.stat().st_size


def sample_metadata(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    return {
        "path": display_path(path, repo_root=REPO_ROOT),
        "bytes": stable_source_size(path, text=text),
        "lines": len(text.splitlines()),
    }


def median_ms(values: list[float]) -> float:
    return statistics.median(values)


def measure_run(*, argv: list[str], cwd: Path, env: dict[str, str]) -> tuple[dict[str, Any], float]:
    start = time.perf_counter()
    result = run(argv, cwd=cwd, env=env)
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    return result, elapsed_ms


def emitted_paths(root: Path, sample: Path) -> dict[str, Path]:
    stem = sample.stem.lower()
    return {
        "ast": root / "out" / f"{stem}.ast.json",
        "typed": root / "out" / f"{stem}.typed.json",
        "mir": root / "out" / f"{stem}.mir.json",
        "safei": root / "iface" / f"{stem}.safei.json",
    }


def measure_check_scenarios(*, safec: Path, env: dict[str, str]) -> tuple[list[dict[str, Any]], dict[str, float]]:
    summaries: list[dict[str, Any]] = []
    medians: dict[str, float] = {}
    for sample in CHECK_SCENARIOS:
        times_ms: list[float] = []
        for _ in range(CHECK_REPETITIONS):
            _, elapsed_ms = measure_run(
                argv=[str(safec), "check", repo_arg(sample)],
                cwd=REPO_ROOT,
                env=env,
            )
            times_ms.append(elapsed_ms)
        median = median_ms(times_ms)
        medians[sample.name] = median
        require(
            median <= CHECK_MEDIAN_BUDGET_MS,
            f"check median exceeded budget for {sample.name}: {median:.2f} ms > {CHECK_MEDIAN_BUDGET_MS:.2f} ms",
        )
        print(f"pr06912 check {sample.name}: median={median:.2f} ms over {CHECK_REPETITIONS} runs")
        summaries.append(
            {
                "sample": sample_metadata(sample),
                "repetitions": CHECK_REPETITIONS,
                "median_budget_ms": CHECK_MEDIAN_BUDGET_MS,
                "budget_pass": True,
            }
        )
    return summaries, medians


def measure_emit_scenarios(*, safec: Path, env: dict[str, str]) -> tuple[list[dict[str, Any]], dict[str, float]]:
    summaries: list[dict[str, Any]] = []
    medians: dict[str, float] = {}
    for sample in EMIT_SCENARIOS:
        source_text = sample.read_text(encoding="utf-8")
        source_bytes = stable_source_size(sample, text=source_text)
        times_ms: list[float] = []
        artifact_sizes: dict[str, int] = {}
        with tempfile.TemporaryDirectory(prefix=f"pr06912-emit-{sample.stem.lower()}-") as temp_root_str:
            temp_root = Path(temp_root_str)
            for repetition in range(EMIT_REPETITIONS):
                root = temp_root / f"rep-{repetition + 1}"
                (root / "out").mkdir(parents=True, exist_ok=True)
                (root / "iface").mkdir(parents=True, exist_ok=True)
                _, elapsed_ms = measure_run(
                    argv=[
                        str(safec),
                        "emit",
                        repo_arg(sample),
                        "--out-dir",
                        str(root / "out"),
                        "--interface-dir",
                        str(root / "iface"),
                    ],
                    cwd=REPO_ROOT,
                    env=env,
                )
                times_ms.append(elapsed_ms)
                paths = emitted_paths(root, sample)
                observed_files = {
                    str(path.relative_to(root))
                    for path in root.rglob("*")
                    if path.is_file()
                }
                expected_files = {
                    str(paths["ast"].relative_to(root)),
                    str(paths["typed"].relative_to(root)),
                    str(paths["mir"].relative_to(root)),
                    str(paths["safei"].relative_to(root)),
                }
                require(
                    observed_files == expected_files,
                    f"emit file set drift for {sample.name}: expected {sorted(expected_files)}, got {sorted(observed_files)}",
                )
                current_sizes = {
                    "ast": stable_emitted_artifact_size(paths["ast"], temp_root=temp_root),
                    "typed": stable_emitted_artifact_size(paths["typed"], temp_root=temp_root),
                    "mir": stable_emitted_artifact_size(paths["mir"], temp_root=temp_root),
                    "safei": stable_emitted_artifact_size(paths["safei"], temp_root=temp_root),
                }
                if not artifact_sizes:
                    artifact_sizes = current_sizes
                else:
                    require(
                        current_sizes == artifact_sizes,
                        f"emit artifact sizes drifted across repetitions for {sample.name}",
                    )

        median = median_ms(times_ms)
        medians[sample.name] = median
        require(
            median <= EMIT_MEDIAN_BUDGET_MS,
            f"emit median exceeded budget for {sample.name}: {median:.2f} ms > {EMIT_MEDIAN_BUDGET_MS:.2f} ms",
        )
        total_bytes = sum(artifact_sizes.values())
        ratios = {
            "total": total_bytes / source_bytes,
            "ast": artifact_sizes["ast"] / source_bytes,
            "typed": artifact_sizes["typed"] / source_bytes,
            "mir": artifact_sizes["mir"] / source_bytes,
            "safei": artifact_sizes["safei"] / source_bytes,
        }
        for key, cap in SIZE_RATIO_CAPS.items():
            require(
                ratios[key] <= cap,
                f"{sample.name} {key} size ratio exceeded cap: {ratios[key]:.2f} > {cap:.2f}",
            )
        print(f"pr06912 emit {sample.name}: median={median:.2f} ms over {EMIT_REPETITIONS} runs")
        summaries.append(
            {
                "sample": sample_metadata(sample),
                "repetitions": EMIT_REPETITIONS,
                "median_budget_ms": EMIT_MEDIAN_BUDGET_MS,
                "budget_pass": True,
                "artifact_bytes": {
                    "ast": artifact_sizes["ast"],
                    "typed": artifact_sizes["typed"],
                    "mir": artifact_sizes["mir"],
                    "safei": artifact_sizes["safei"],
                    "total": total_bytes,
                },
                "artifact_ratio_caps": SIZE_RATIO_CAPS,
                "artifact_ratio_pass": True,
            }
        )
    return summaries, medians


def analyze_expected_returncode(path: Path) -> int:
    return 0 if path.name in {"valid_mir_v2.json", "valid_mir_v2_concurrency.json"} else 1


def measure_analyze_scenarios(*, safec: Path, env: dict[str, str]) -> tuple[list[dict[str, Any]], dict[str, float]]:
    summaries: list[dict[str, Any]] = []
    medians: dict[str, float] = {}
    for sample in ANALYZE_SCENARIOS:
        times_ms: list[float] = []
        for _ in range(ANALYZE_REPETITIONS):
            start = time.perf_counter()
            run(
                [str(safec), "analyze-mir", "--diag-json", str(sample)],
                cwd=REPO_ROOT,
                env=env,
                expected_returncode=analyze_expected_returncode(sample),
            )
            times_ms.append((time.perf_counter() - start) * 1000.0)
        median = median_ms(times_ms)
        medians[sample.name] = median
        require(
            median <= ANALYZE_MEDIAN_BUDGET_MS,
            f"analyze-mir median exceeded budget for {sample.name}: {median:.2f} ms > {ANALYZE_MEDIAN_BUDGET_MS:.2f} ms",
        )
        print(f"pr06912 analyze {sample.name}: median={median:.2f} ms over {ANALYZE_REPETITIONS} runs")
        summaries.append(
            {
                "sample": sample_metadata(sample),
                "repetitions": ANALYZE_REPETITIONS,
                "median_budget_ms": ANALYZE_MEDIAN_BUDGET_MS,
                "budget_pass": True,
            }
        )
    return summaries, medians


def enforce_growth_caps(
    *,
    check_medians: dict[str, float],
    emit_medians: dict[str, float],
    analyze_medians: dict[str, float],
) -> list[dict[str, Any]]:
    ratios = [
        (
            "check_rule2_vs_rule1",
            check_medians["rule2_binary_search.safe"] / check_medians["rule1_accumulate.safe"],
        ),
        (
            "emit_rule2_vs_rule1",
            emit_medians["rule2_binary_search.safe"] / emit_medians["rule1_accumulate.safe"],
        ),
        (
            "analyze_reassign_vs_valid",
            analyze_medians["pr0695_anonymous_access_reassign_parity.json"]
            / analyze_medians["valid_mir_v2.json"],
        ),
    ]
    results: list[dict[str, Any]] = []
    for name, value in ratios:
        cap = GROWTH_RATIO_CAPS[name]
        require(value <= cap, f"{name} ratio exceeded cap: {value:.2f} > {cap:.2f}")
        print(f"pr06912 ratio {name}: {value:.2f} (cap {cap:.2f})")
        results.append({"name": name, "cap": cap, "pass": True})
    return results


def run_supported_positive_check_sweep(*, safec: Path, env: dict[str, str]) -> dict[str, Any]:
    cases = [
        REPO_ROOT / path
        for path in [
            *PR05_POSITIVE_CASES,
            *PR06_POSITIVE_CASES,
            *PR07_RULE5_POSITIVE_CASES,
            *PR07_RESULT_POSITIVE_CASES,
        ]
    ]
    total_ms = 0.0
    for sample in cases:
        start = time.perf_counter()
        run([str(safec), "check", repo_arg(sample)], cwd=REPO_ROOT, env=env)
        total_ms += (time.perf_counter() - start) * 1000.0
    require(
        total_ms <= CHECK_SWEEP_BUDGET_MS,
        f"supported-positive check sweep exceeded budget: {total_ms:.2f} ms > {CHECK_SWEEP_BUDGET_MS:.2f} ms",
    )
    largest = max(
        cases,
        key=lambda path: (
            stable_source_size(path, text=path.read_text(encoding="utf-8")),
            str(path),
        ),
    )
    print(f"pr06912 full check sweep: total={total_ms:.2f} ms over {len(cases)} cases")
    return {
        "count": len(cases),
        "budget_ms": CHECK_SWEEP_BUDGET_MS,
        "budget_pass": True,
        "largest_sample": sample_metadata(largest),
    }


def run_full_mir_sweep(*, safec: Path, env: dict[str, str]) -> dict[str, Any]:
    cases = sorted((COMPILER_ROOT / "tests" / "mir_analysis").glob("*.json")) + sorted(
        (COMPILER_ROOT / "tests" / "mir_validation").glob("*.json")
    )
    total_ms = 0.0
    for sample in cases:
        start = time.perf_counter()
        run(
            [str(safec), "analyze-mir", "--diag-json", str(sample)],
            cwd=REPO_ROOT,
            env=env,
            expected_returncode=analyze_expected_returncode(sample),
        )
        total_ms += (time.perf_counter() - start) * 1000.0
    require(
        total_ms <= MIR_SWEEP_BUDGET_MS,
        f"full MIR sweep exceeded budget: {total_ms:.2f} ms > {MIR_SWEEP_BUDGET_MS:.2f} ms",
    )
    largest = max(cases, key=lambda path: (path.stat().st_size, str(path)))
    print(f"pr06912 full MIR sweep: total={total_ms:.2f} ms over {len(cases)} cases")
    return {
        "count": len(cases),
        "budget_ms": MIR_SWEEP_BUDGET_MS,
        "budget_pass": True,
        "largest_sample": sample_metadata(largest),
    }


def collect_measurements(*, safec: Path, env: dict[str, str]) -> dict[str, Any]:
    check_performance_scale_sanity()
    check_runs, check_medians = measure_check_scenarios(safec=safec, env=env)
    emit_runs, emit_medians = measure_emit_scenarios(safec=safec, env=env)
    analyze_runs, analyze_medians = measure_analyze_scenarios(safec=safec, env=env)
    ratio_results = enforce_growth_caps(
        check_medians=check_medians,
        emit_medians=emit_medians,
        analyze_medians=analyze_medians,
    )
    check_sweep = run_supported_positive_check_sweep(safec=safec, env=env)
    mir_sweep = run_full_mir_sweep(safec=safec, env=env)
    return {
        "check_runs": check_runs,
        "emit_runs": emit_runs,
        "analyze_runs": analyze_runs,
        "ratio_results": ratio_results,
        "check_sweep": check_sweep,
        "mir_sweep": mir_sweep,
    }


def build_report(measurements: dict[str, Any]) -> dict[str, Any]:
    return {
        "task": "PR06.9.12",
        "status": "ok",
        "performance_scale_policy": performance_scale_sanity_report(),
        "budgets_ms": {
            "check_median": CHECK_MEDIAN_BUDGET_MS,
            "emit_median": EMIT_MEDIAN_BUDGET_MS,
            "analyze_median": ANALYZE_MEDIAN_BUDGET_MS,
            "supported_positive_check_sweep": CHECK_SWEEP_BUDGET_MS,
            "full_mir_sweep": MIR_SWEEP_BUDGET_MS,
        },
        "growth_ratio_caps": GROWTH_RATIO_CAPS,
        "artifact_size_ratio_caps": SIZE_RATIO_CAPS,
        "repetitions": {
            "check": CHECK_REPETITIONS,
            "emit": EMIT_REPETITIONS,
            "analyze_mir": ANALYZE_REPETITIONS,
        },
        "repeated_scenarios": {
            "check": measurements["check_runs"],
            "emit": measurements["emit_runs"],
            "analyze_mir": measurements["analyze_runs"],
        },
        "growth_ratio_results": measurements["ratio_results"],
        "aggregate_sweeps": {
            "supported_positive_check": measurements["check_sweep"],
            "full_mir": measurements["mir_sweep"],
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    find_command("python3")
    find_command("git")
    find_command("alr", Path.home() / "bin" / "alr")
    env = ensure_sdkroot(os.environ.copy())
    safec = require_repo_command(COMPILER_ROOT / "bin" / "safec", "safec")

    measurements = collect_measurements(safec=safec, env=env)
    report = finalize_deterministic_report(
        lambda: build_report(measurements),
        label="PR06.9.12 performance and scale sanity",
    )
    write_report(args.report, report)
    print(f"pr06912 performance and scale sanity: OK ({display_path(args.report, repo_root=REPO_ROOT)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
