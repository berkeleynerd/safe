#!/bin/bash
# Safe Language Annotated SPARK Companion
# extract_assumptions.sh -- Extract GNATprove assumptions from proof output
#
# This script reads the GNATprove output directory and extracts the
# assumption summary to companion/assumptions_extracted.txt.
# If no assumptions file exists yet, it creates an initial baseline.
#
# Exit codes:
#   0  -- Assumptions extracted successfully
#   1  -- Error during extraction

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GPR_FILE="${REPO_ROOT}/${GPR_FILE:-companion/gen/companion.gpr}"
PROVE_OUT="${REPO_ROOT}/${PROVE_OUT:-companion/gen/obj/gnatprove}"
EXTRACTED="${REPO_ROOT}/companion/assumptions_extracted.txt"

echo "================================================================"
echo "  Extract GNATprove Assumptions"
echo "================================================================"
echo ""

# -----------------------------------------------------------------------
# Step 1: Locate the GNATprove output directory
# -----------------------------------------------------------------------

if [[ ! -d "${PROVE_OUT}" ]]; then
    echo "WARNING: GNATprove output directory not found: ${PROVE_OUT}"
    echo "         This may mean GNATprove has not been run yet."
    echo "         Creating empty baseline assumptions file."
    {
        echo "# Safe Companion -- Extracted Assumptions"
        echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "# Source: (no GNATprove output available)"
        echo "#"
        echo "# This file is empty because GNATprove has not been run."
        echo "# Run scripts/run_gnatprove_prove.sh first, then re-extract."
    } > "${EXTRACTED}"
    echo "Created empty baseline: ${EXTRACTED}"
    exit 0
fi

echo "GNATprove output directory: ${PROVE_OUT}"
echo ""

# -----------------------------------------------------------------------
# Step 2: Extract assumptions from GNATprove output files
# -----------------------------------------------------------------------

{
    echo "# Safe Companion -- Extracted Assumptions"
    echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "# Source: ${PROVE_OUT#"${REPO_ROOT}"/}"
    echo "#"
    echo "# This file lists all assumptions extracted from GNATprove output."
    echo "# Compare against companion/assumptions.yaml to detect drift."
    echo ""

    # Extract from .spark files (JSON proof results) if present
    SPARK_FILES_FOUND=0
    for spark_file in "${PROVE_OUT}"/*.spark; do
        if [[ -f "${spark_file}" ]]; then
            SPARK_FILES_FOUND=1
            basename_file="$(basename "${spark_file}")"
            echo "## File: ${basename_file}"
            # Extract assumption entries from JSON proof results
            if command -v python3 &>/dev/null; then
                python3 -c "
import json, sys
try:
    with open('${spark_file}') as f:
        data = json.load(f)
    if 'assumptions' in data:
        for a in data['assumptions']:
            claim = a.get('claim', {})
            assumptions = a.get('assumptions', [])
            file_name = claim.get('file', 'unknown')
            sloc_line = claim.get('sloc', {}).get('line', '?')
            rule = claim.get('rule', 'unknown')
            print(f'  claim: {file_name}:{sloc_line} [{rule}]')
            for dep in assumptions:
                dep_file = dep.get('file', 'unknown')
                dep_line = dep.get('sloc', {}).get('line', '?')
                dep_rule = dep.get('rule', 'unknown')
                print(f'    assumes: {dep_file}:{dep_line} [{dep_rule}]')
    else:
        print('  (no assumptions section found)')
except Exception as e:
    print(f'  (parse error: {e})')
" 2>/dev/null || echo "  (could not parse ${basename_file})"
            else
                echo "  (python3 not available for JSON parsing)"
            fi
            echo ""
        fi
    done

    if [[ ${SPARK_FILES_FOUND} -eq 0 ]]; then
        echo "# No .spark proof result files found in ${PROVE_OUT}"
        echo "# This may indicate GNATprove was run in flow mode only,"
        echo "# or proof results were cleaned."
    fi

    # Also extract any warnings about unproved assumptions from log files
    for log_file in "${PROVE_OUT}"/*.out; do
        if [[ -f "${log_file}" ]]; then
            echo ""
            echo "## Log: $(basename "${log_file}")"
            grep -i "assumption\|axiom\|trust\|unproved" "${log_file}" 2>/dev/null || echo "  (no assumption-related entries)"
        fi
    done

} > "${EXTRACTED}"

echo "Assumptions extracted to: ${EXTRACTED}"
echo ""

# Count extracted entries
CLAIM_COUNT=$(grep -c "^  claim:" "${EXTRACTED}" 2>/dev/null || echo "0")
ASSUME_COUNT=$(grep -c "^    assumes:" "${EXTRACTED}" 2>/dev/null || echo "0")
echo "Summary:"
echo "  Claims:      ${CLAIM_COUNT}"
echo "  Assumptions: ${ASSUME_COUNT}"
echo ""
echo "extract_assumptions: OK"
exit 0
