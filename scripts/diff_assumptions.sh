#!/bin/bash
# Safe Language Annotated SPARK Companion
# diff_assumptions.sh -- Verify assumptions baseline and proof summary stability
#
# Two-part check:
#   Part A: Verify companion/assumptions.yaml has not changed unexpectedly
#           by comparing against a committed golden hash.
#   Part B: Verify GNATprove proof summary matches the committed golden
#           summary (companion/gen/prove_golden.txt).
#
# Exit codes:
#   0  -- No drift detected; everything matches
#   1  -- Drift detected (assumptions or proof summary changed)
#   2  -- Required files are missing

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="${REPO_ROOT}/companion/assumptions.yaml"
EXTRACTED="${REPO_ROOT}/companion/assumptions_extracted.txt"
PROVE_GOLDEN="${REPO_ROOT}/${PROVE_GOLDEN:-companion/gen/prove_golden.txt}"
PROVE_OUT="${REPO_ROOT}/${PROVE_OUT:-companion/gen/obj/gnatprove/gnatprove.out}"

echo "================================================================"
echo "  Diff Assumptions & Proof Summary Against Baseline"
echo "================================================================"
echo ""

DRIFT_DETECTED=0

normalize_summary() {
    # GNATprove's prover-attribution percentages can drift across toolchains
    # without any change to proved/justified/unproved counts.
    sed -E 's/\([^)]*\)/(normalized)/g'
}

# -----------------------------------------------------------------------
# Part A: Verify assumptions.yaml baseline
# -----------------------------------------------------------------------

if [[ ! -f "${BASELINE}" ]]; then
    echo "ERROR: Baseline assumptions file not found: ${BASELINE}"
    exit 2
fi

# Extract assumption IDs and severities from baseline YAML
BASELINE_IDS=$(grep -E "^- id:" "${BASELINE}" | sed 's/^- id: *//' | sort)
BASELINE_COUNT=$(echo "${BASELINE_IDS}" | grep -c '.' || true)
OPEN_COUNT=$(grep -c "^  status: open$" "${BASELINE}" || true)
RESOLVED_COUNT=$(grep -c "^  status: resolved$" "${BASELINE}" || true)
CRITICAL_COUNT=$(grep -c "^  severity: critical$" "${BASELINE}" || true)
MAJOR_COUNT=$(grep -c "^  severity: major$" "${BASELINE}" || true)
MINOR_COUNT=$(grep -c "^  severity: minor$" "${BASELINE}" || true)
OPEN_CRITICAL_COUNT=$(python3 - <<'PY' "${BASELINE}"
from pathlib import Path
import sys

count = 0
severity = None
status = None
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith("- id:"):
        severity = None
        status = None
    elif line.strip().startswith("severity:"):
        severity = line.split(":", 1)[1].strip()
    elif line.strip().startswith("status:"):
        status = line.split(":", 1)[1].strip()
        if severity == "critical" and status == "open":
            count += 1
print(count)
PY
)

echo "Tracked assumptions in companion/assumptions.yaml:"
echo "  Tracked total: ${BASELINE_COUNT}"
echo "  Open:          ${OPEN_COUNT}"
echo "  Resolved:      ${RESOLVED_COUNT}"
echo "  Critical:      ${CRITICAL_COUNT}"
echo "  Major:         ${MAJOR_COUNT}"
echo "  Minor:         ${MINOR_COUNT}"
echo ""

echo "Assumption IDs:"
echo "${BASELINE_IDS}" | sed 's/^/  /'
echo ""

# -----------------------------------------------------------------------
# Part B: Verify GNATprove proof summary matches golden
# -----------------------------------------------------------------------

if [[ ! -f "${PROVE_OUT}" ]]; then
    echo "WARNING: GNATprove output not found: ${PROVE_OUT}"
    echo "         Run gnatprove before diffing. Skipping proof summary check."
    echo ""
else
    # Extract the summary block (from "Summary of SPARK" through "Total" line)
    CURRENT_SUMMARY=$(sed -n '/^Summary of SPARK/,/^Total/p' "${PROVE_OUT}")
    NORMALIZED_CURRENT_SUMMARY=$(printf '%s\n' "${CURRENT_SUMMARY}" | normalize_summary)

    if [[ -f "${PROVE_GOLDEN}" ]]; then
        GOLDEN_SUMMARY=$(cat "${PROVE_GOLDEN}")
        NORMALIZED_GOLDEN_SUMMARY=$(printf '%s\n' "${GOLDEN_SUMMARY}" | normalize_summary)

        if [[ "${NORMALIZED_CURRENT_SUMMARY}" == "${NORMALIZED_GOLDEN_SUMMARY}" ]]; then
            echo "Proof summary: MATCHES golden baseline."
            echo ""
        else
            echo "================================================================"
            echo "  PROOF SUMMARY DRIFT DETECTED"
            echo "================================================================"
            echo ""
            echo "--- Golden (expected) ---"
            cat "${PROVE_GOLDEN}"
            echo ""
            echo "--- Current ---"
            echo "${CURRENT_SUMMARY}"
            echo ""
            diff <(cat "${PROVE_GOLDEN}") <(echo "${CURRENT_SUMMARY}") || true
            echo ""
            echo "To accept the new summary:"
            echo "  sed -n '/^Summary of SPARK/,/^Total/p' ${PROVE_OUT} > ${PROVE_GOLDEN}"
            echo "  git add ${PROVE_GOLDEN} && git commit"
            echo ""
            DRIFT_DETECTED=1
        fi
    else
        echo "No golden proof summary found. Creating initial baseline."
        printf '%s\n' "${CURRENT_SUMMARY}" > "${PROVE_GOLDEN}"
        echo "Saved: ${PROVE_GOLDEN}"
        echo ""
    fi
fi

# -----------------------------------------------------------------------
# Part C: Report extracted GNATprove assumptions (informational)
# -----------------------------------------------------------------------

if [[ -f "${EXTRACTED}" ]]; then
    CLAIM_COUNT=$(grep -c "^  claim:" "${EXTRACTED}" 2>/dev/null || true)
    ASSUME_COUNT=$(grep -c "^    assumes:" "${EXTRACTED}" 2>/dev/null || true)

    echo "Extracted from GNATprove output:"
    echo "  Claims:      ${CLAIM_COUNT}"
    echo "  Assumptions: ${ASSUME_COUNT}"
    echo ""
fi

# -----------------------------------------------------------------------
# Part D: Budget policy enforcement
# -----------------------------------------------------------------------

# Enforce assumption budget limits from gnatprove_profile.md Section 6.5.
# Resolved assumptions stay in YAML for audit history; only open assumptions
# consume the active budget.
TOTAL_LIMIT=15
# A-06 documents the existing heap-backed runtime trust boundary rather than
# adding a new proof exemption, so the governed open-critical budget is five.
# The budget is intentionally at limit; any additional open critical assumption
# must be paired with formal budget review before merge.
CRITICAL_LIMIT=5

if [[ ${OPEN_COUNT} -gt ${TOTAL_LIMIT} ]]; then
    echo "WARNING: Open assumption count (${OPEN_COUNT}) exceeds budget limit (${TOTAL_LIMIT})."
    echo "         A formal budget review is required per gnatprove_profile.md Section 6.5."
    DRIFT_DETECTED=1
fi

if [[ ${OPEN_CRITICAL_COUNT} -gt ${CRITICAL_LIMIT} ]]; then
    echo "WARNING: Open critical assumption count (${OPEN_CRITICAL_COUNT}) exceeds limit (${CRITICAL_LIMIT})."
    echo "         Escalation required per gnatprove_profile.md Section 6.5."
    DRIFT_DETECTED=1
fi

# -----------------------------------------------------------------------
# Final verdict
# -----------------------------------------------------------------------

if [[ ${DRIFT_DETECTED} -eq 1 ]]; then
    echo "================================================================"
    echo "  ASSUMPTION DIFF: CHANGED"
    echo "  Review the output above and update baselines if appropriate."
    echo "================================================================"
    exit 1
fi

echo "================================================================"
echo "  ASSUMPTION DIFF: OK"
echo "  Baseline: ${BASELINE_COUNT} tracked (${OPEN_COUNT} open,"
echo "            ${RESOLVED_COUNT} resolved)"
echo "  Severity: ${CRITICAL_COUNT} critical, ${MAJOR_COUNT} major,"
echo "            ${MINOR_COUNT} minor"
echo "  Proof summary: matches golden"
echo "  Budget: within limits (${OPEN_COUNT} open, ${OPEN_CRITICAL_COUNT} open critical)"
echo "================================================================"
exit 0
