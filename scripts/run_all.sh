#!/bin/bash
# Safe Language Annotated SPARK Companion
# run_all.sh -- Master pipeline script
#
# Runs the full spec2spark verification pipeline in order:
#   Step 1: Compile (gprbuild)
#   Step 2: GNATprove flow analysis (Bronze gate)
#   Step 3: GNATprove proof analysis (Silver gate)
#   Step 4: Extract assumptions
#   Step 5: Diff assumptions against baseline
#
# Each step exits on failure with a clear error message.
# The frozen spec commit SHA is read from meta/commit.txt.
#
# Exit codes:
#   0  -- All steps passed
#   1  -- A step failed (see output for details)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="${REPO_ROOT}/companion/gen"
GPR_FILE="${WORKSPACE_DIR}/companion.gpr"
FROZEN_SHA="$(cat "${REPO_ROOT}/meta/commit.txt" | tr -d '[:space:]')"
ALR_BIN="${ALR_BIN:-alr}"

resolve_command() {
    local configured="$1"
    local label="$2"

    if [[ "${configured}" == */* ]]; then
        if [[ -x "${configured}" ]]; then
            printf '%s\n' "${configured}"
            return 0
        fi
        echo "ERROR: ${label} not executable: ${configured}" >&2
        exit 1
    fi

    local resolved
    resolved="$(command -v "${configured}" || true)"
    if [[ -z "${resolved}" ]]; then
        echo "ERROR: ${label} not found on PATH: ${configured}" >&2
        exit 1
    fi
    printf '%s\n' "${resolved}"
}

ALR_BIN="$(resolve_command "${ALR_BIN}" "alr")"

echo "================================================================"
echo "  Safe Language Annotated SPARK Companion"
echo "  Master Pipeline (run_all.sh)"
echo "  Frozen commit: ${FROZEN_SHA}"
echo "  Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "================================================================"
echo ""

# -----------------------------------------------------------------------
# Verify project file exists
# -----------------------------------------------------------------------

if [[ ! -f "${GPR_FILE}" ]]; then
    echo "ERROR: Project file not found: ${GPR_FILE}"
    echo "       Ensure companion/gen/companion.gpr exists."
    exit 1
fi

# Ensure object directory exists
mkdir -p "${WORKSPACE_DIR}/obj"

# =======================================================================
# Step 1: Compile (syntax check and type check via gprbuild)
# =======================================================================

echo "================================================================"
echo "  Step 1/5: Compile (gprbuild)"
echo "================================================================"
echo ""

if (
    cd "${WORKSPACE_DIR}"
    "${ALR_BIN}" exec -- gprbuild -P companion.gpr -q
) 2>&1; then
    echo ""
    echo "  Step 1: PASSED -- Compilation succeeded."
else
    BUILD_EXIT=$?
    echo ""
    echo "  Step 1: FAILED -- Compilation failed (exit code ${BUILD_EXIT})."
    echo "  Fix compilation errors before proceeding."
    exit 1
fi
echo ""

# =======================================================================
# Step 2: GNATprove flow analysis (Bronze gate)
# =======================================================================

echo "================================================================"
echo "  Step 2/5: GNATprove Flow Analysis (Bronze Gate)"
echo "================================================================"
echo ""

if "${REPO_ROOT}/scripts/run_gnatprove_flow.sh" 2>&1; then
    echo ""
    echo "  Step 2: PASSED -- Flow analysis succeeded."
else
    FLOW_EXIT=$?
    echo ""
    echo "  Step 2: FAILED -- Flow analysis failed (exit code ${FLOW_EXIT})."
    echo "  Fix flow analysis errors before proceeding to proof."
    exit 1
fi
echo ""

# =======================================================================
# Step 3: GNATprove proof analysis (Silver gate)
# =======================================================================

echo "================================================================"
echo "  Step 3/5: GNATprove Proof Analysis (Silver Gate)"
echo "================================================================"
echo ""

if "${REPO_ROOT}/scripts/run_gnatprove_prove.sh" 2>&1; then
    echo ""
    echo "  Step 3: PASSED -- Proof analysis succeeded."
else
    PROVE_EXIT=$?
    echo ""
    echo "  Step 3: FAILED -- Proof analysis failed (exit code ${PROVE_EXIT})."
    echo "  Review unproved VCs before proceeding."
    exit 1
fi
echo ""

# =======================================================================
# Step 4: Extract assumptions
# =======================================================================

echo "================================================================"
echo "  Step 4/5: Extract Assumptions"
echo "================================================================"
echo ""

if "${REPO_ROOT}/scripts/extract_assumptions.sh" 2>&1; then
    echo ""
    echo "  Step 4: PASSED -- Assumptions extracted."
else
    EXTRACT_EXIT=$?
    echo ""
    echo "  Step 4: FAILED -- Assumption extraction failed (exit code ${EXTRACT_EXIT})."
    exit 1
fi
echo ""

# =======================================================================
# Step 5: Diff assumptions against baseline
# =======================================================================

echo "================================================================"
echo "  Step 5/5: Diff Assumptions"
echo "================================================================"
echo ""

if "${REPO_ROOT}/scripts/diff_assumptions.sh" 2>&1; then
    echo ""
    echo "  Step 5: PASSED -- Assumptions match baseline."
else
    DIFF_EXIT=$?
    echo ""
    echo "  Step 5: FAILED -- Assumption drift detected (exit code ${DIFF_EXIT})."
    echo "  Review the diff output above and update the baseline if appropriate."
    exit 1
fi
echo ""

# =======================================================================
# Pipeline complete
# =======================================================================

echo "================================================================"
echo "  ALL STEPS PASSED"
echo ""
echo "  Pipeline Summary:"
echo "    Step 1: Compile .............. PASSED"
echo "    Step 2: Flow Analysis ........ PASSED"
echo "    Step 3: Proof Analysis ....... PASSED"
echo "    Step 4: Extract Assumptions .. PASSED"
echo "    Step 5: Diff Assumptions ..... PASSED"
echo ""
echo "  Frozen commit: ${FROZEN_SHA}"
echo "  Completed:     $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "================================================================"
exit 0
