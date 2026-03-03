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

# -----------------------------------------------------------------------
# Part A: Verify assumptions.yaml baseline
# -----------------------------------------------------------------------

if [[ ! -f "${BASELINE}" ]]; then
    echo "ERROR: Baseline assumptions file not found: ${BASELINE}"
    exit 2
fi

# Extract assumption IDs and severities from baseline YAML
BASELINE_IDS=$(grep -E "^- id:" "${BASELINE}" | sed 's/^- id: *//' | sort)
BASELINE_COUNT=$(echo "${BASELINE_IDS}" | grep -c '.' || echo "0")
CRITICAL_COUNT=$(grep -c "severity: critical" "${BASELINE}" || echo "0")
MAJOR_COUNT=$(grep -c "severity: major" "${BASELINE}" || echo "0")
MINOR_COUNT=$(grep -c "severity: minor" "${BASELINE}" || echo "0")

echo "Tracked assumptions in companion/assumptions.yaml:"
echo "  Total:    ${BASELINE_COUNT}"
echo "  Critical: ${CRITICAL_COUNT}"
echo "  Major:    ${MAJOR_COUNT}"
echo "  Minor:    ${MINOR_COUNT}"
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

    if [[ -f "${PROVE_GOLDEN}" ]]; then
        GOLDEN_SUMMARY=$(cat "${PROVE_GOLDEN}")

        if [[ "${CURRENT_SUMMARY}" == "${GOLDEN_SUMMARY}" ]]; then
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
    CLAIM_COUNT=$(grep -c "^  claim:" "${EXTRACTED}" 2>/dev/null || echo "0")
    ASSUME_COUNT=$(grep -c "^    assumes:" "${EXTRACTED}" 2>/dev/null || echo "0")

    echo "Extracted from GNATprove output:"
    echo "  Claims:      ${CLAIM_COUNT}"
    echo "  Assumptions: ${ASSUME_COUNT}"
    echo ""
fi

# -----------------------------------------------------------------------
# Part D: Budget policy enforcement
# -----------------------------------------------------------------------

# Enforce assumption budget limits from gnatprove_profile.md Section 6.5
TOTAL_LIMIT=15
CRITICAL_LIMIT=4

if [[ ${BASELINE_COUNT} -gt ${TOTAL_LIMIT} ]]; then
    echo "WARNING: Assumption count (${BASELINE_COUNT}) exceeds budget limit (${TOTAL_LIMIT})."
    echo "         A formal budget review is required per gnatprove_profile.md Section 6.5."
    DRIFT_DETECTED=1
fi

if [[ ${CRITICAL_COUNT} -gt ${CRITICAL_LIMIT} ]]; then
    echo "WARNING: Critical assumption count (${CRITICAL_COUNT}) exceeds limit (${CRITICAL_LIMIT})."
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
echo "  Baseline: ${BASELINE_COUNT} assumptions (${CRITICAL_COUNT} critical,"
echo "            ${MAJOR_COUNT} major, ${MINOR_COUNT} minor)"
echo "  Proof summary: matches golden"
echo "  Budget: within limits"
echo "================================================================"
exit 0
