#!/bin/bash
# Safe Language Annotated SPARK Companion
# run_gnatprove_prove.sh -- Run GNATprove in prove mode (Silver gate)
#
# Proof mode verifies functional contracts (Pre/Post), absence of runtime
# errors (AoRTE), and all verification conditions.  This corresponds to the
# Silver assurance level defined in spec/05-assurance.md.
#
# Exit codes:
#   0  -- All proofs discharged successfully
#   1  -- One or more VCs remain unproved, or the tool failed

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
echo "  GNATprove Proof Analysis (Silver Gate)"
echo "  Project: ${GPR_FILE}"
echo "  Level: 2"
echo "================================================================"
echo ""

# Clean previous results to ensure a fresh analysis
(cd "${WORKSPACE_DIR}" && "${ALR_BIN}" exec -- "${GNATPROVE_BIN}" -P companion.gpr --clean) >/dev/null 2>&1 || true

echo "Running: ${ALR_BIN} exec -- ${GNATPROVE_BIN} -P companion.gpr --mode=prove --level=2 --prover=cvc5,z3,altergo --steps=0 --timeout=120 --report=all --warnings=error --checks-as-errors=on"
echo ""

if (
    cd "${WORKSPACE_DIR}"
    "${ALR_BIN}" exec -- "${GNATPROVE_BIN}" \
        -P companion.gpr \
        --mode=prove \
        --level=2 \
        --prover=cvc5,z3,altergo \
        --steps=0 \
        --timeout=120 \
        --report=all \
        --warnings=error \
        --checks-as-errors=on
) 2>&1; then
    echo ""
    echo "================================================================"
    echo "  PROOF ANALYSIS: PASSED"
    echo "  All verification conditions discharged at level 2."
    echo "================================================================"
    exit 0
else
    PROVE_EXIT=$?
    echo ""
    echo "================================================================"
    echo "  PROOF ANALYSIS: FAILED (exit code ${PROVE_EXIT})"
    echo "================================================================"
    echo ""
    echo "Review the GNATprove output above for unproved VCs."
    echo "Common issues:"
    echo "  - Insufficient preconditions"
    echo "  - Postconditions that cannot be established"
    echo "  - Arithmetic overflow in intermediate expressions"
    echo "  - Prover timeout (try increasing --level or --timeout)"
    echo ""

    # Attempt to print a summary from the gnatprove output directory
    PROVE_OUT="${REPO_ROOT}/companion/gen/obj/gnatprove"
    if [[ -d "${PROVE_OUT}" ]]; then
        echo "GNATprove output directory: ${PROVE_OUT}"
        # Count unproved checks if the summary file exists
        SUMMARY_FILE="${PROVE_OUT}/gnatprove.out"
        if [[ -f "${SUMMARY_FILE}" ]]; then
            echo ""
            echo "--- Proof Summary ---"
            cat "${SUMMARY_FILE}"
        fi
    fi

    exit 1
fi
