#!/bin/bash
# Safe Language Annotated SPARK Companion
# run_gnatprove_flow.sh -- Run GNATprove in flow analysis mode (Bronze gate)
#
# Flow analysis checks data dependencies, initialization, and Global/Depends
# contracts.  This corresponds to the Bronze assurance level defined in
# spec/05-assurance.md.
#
# Exit codes:
#   0  -- Flow analysis passed with no errors
#   1  -- Flow analysis reported errors or the tool failed to run

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="${REPO_ROOT}/companion/gen"
GPR_FILE="${WORKSPACE_DIR}/companion.gpr"
ALR_BIN="${ALR_BIN:-alr}"
GNATPROVE_BIN="${GNATPROVE_BIN:-gnatprove}"
GNATPROVE_FALLBACK="${HOME}/.alire/bin/gnatprove"

if [[ ! -f "${GPR_FILE}" ]]; then
    echo "ERROR: Project file not found: ${GPR_FILE}"
    exit 1
fi

resolve_command() {
    local configured="$1"
    local label="$2"
    local fallback="${3:-}"

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
    if [[ -z "${resolved}" && -n "${fallback}" && -x "${fallback}" ]]; then
        printf '%s\n' "${fallback}"
        return 0
    fi
    if [[ -z "${resolved}" ]]; then
        echo "ERROR: ${label} not found on PATH: ${configured}" >&2
        exit 1
    fi
    printf '%s\n' "${resolved}"
}

ALR_BIN="$(resolve_command "${ALR_BIN}" "alr")"
GNATPROVE_BIN="$(resolve_command "${GNATPROVE_BIN}" "gnatprove" "${GNATPROVE_FALLBACK}")"

echo "================================================================"
echo "  GNATprove Flow Analysis (Bronze Gate)"
echo "  Project: ${GPR_FILE}"
echo "================================================================"
echo ""

# Clean previous results to ensure a fresh analysis
(cd "${WORKSPACE_DIR}" && "${ALR_BIN}" exec -- "${GNATPROVE_BIN}" -P companion.gpr --clean) >/dev/null 2>&1 || true

echo "Running: ${ALR_BIN} exec -- ${GNATPROVE_BIN} -P companion.gpr --mode=flow --report=all --warnings=error"
echo ""

if (
    cd "${WORKSPACE_DIR}"
    "${ALR_BIN}" exec -- "${GNATPROVE_BIN}" \
        -P companion.gpr \
        --mode=flow \
        --report=all \
        --warnings=error
) 2>&1; then
    echo ""
    echo "================================================================"
    echo "  FLOW ANALYSIS: PASSED"
    echo "================================================================"
    exit 0
else
    FLOW_EXIT=$?
    echo ""
    echo "================================================================"
    echo "  FLOW ANALYSIS: FAILED (exit code ${FLOW_EXIT})"
    echo "================================================================"
    echo ""
    echo "Review the GNATprove output above for flow analysis errors."
    echo "Common issues:"
    echo "  - Missing Global contracts"
    echo "  - Uninitialized variables"
    echo "  - Incorrect Depends contracts"
    exit 1
fi
