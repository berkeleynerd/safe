#!/usr/bin/env bash
set -euo pipefail

# Lint .safe files for banned legacy syntax tokens.
# Runs without a Safe compiler — grep-based, suitable for CI.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

FAIL=0

# Some negative fixtures intentionally preserve removed legacy syntax so the
# parser can prove deterministic rejection. Keep the allowlist explicit.
declare -A LINT_EXEMPT_TICK_ATTRIBUTE=(
  ["tests/negative/neg_pr1162_removed_representation_clause.safe"]=1
)

echo "Linting .safe files for banned legacy syntax tokens..."

# Banned tokens in Safe source (v0.2 syntax).
# :=  was assignment (now =)
# =>  was association/arm separator (now = or then)
# /=  was inequality (now !=)
# Tick-based attributes and qualified expressions are banned (spec §2.2 item 4,
# §4.7 item 25). Safe uses dot notation for attributes and (Expr as T) for
# qualified expressions. Tick is only legal for character literals ('A').
BANNED_FIXED=(
  ":="
  "=>"
  "/="
)

while IFS= read -r -d '' f; do
  for pat in "${BANNED_FIXED[@]}"; do
    if grep -nF -- "${pat}" "${f}" >/dev/null 2>&1; then
      echo "ERROR: ${f} contains banned token '${pat}':"
      grep -nF -- "${pat}" "${f}" | head -5
      FAIL=1
    fi
  done
  # Tick-attribute check: catches T'First, T'Succ, T'Image, etc.
  # Regex: word char + tick + uppercase + lowercase (avoids char literals 'A').
  if [[ -z "${LINT_EXEMPT_TICK_ATTRIBUTE["${f}"]+x}" ]] && grep -nE "[A-Za-z_0-9]'[A-Z][a-z]" "${f}" >/dev/null 2>&1; then
    echo "ERROR: ${f} contains tick-attribute (use dot notation, spec §2.2 item 4):"
    grep -nE "[A-Za-z_0-9]'[A-Z][a-z]" "${f}" | head -5
    FAIL=1
  fi
  # Qualified expression ticks: T'( is banned (spec §4.7 item 25).
  if grep -nE "[A-Za-z_0-9]'\(" "${f}" >/dev/null 2>&1; then
    echo "ERROR: ${f} contains qualified expression tick T'(...) (use (Expr as T)):"
    grep -nE "[A-Za-z_0-9]'\(" "${f}" | head -5
    FAIL=1
  fi
done < <(find tests -type f -name "*.safe" -print0)

if [[ "${FAIL}" -ne 0 ]]; then
  echo
  echo "Safe syntax lint FAILED. Replace legacy tokens with v0.2 syntax:"
  echo "  :=  ->  ="
  echo "  /=  ->  !="
  echo "  =>  ->  then (arms) or = (associations)"
  echo "  X'First  ->  X.First  (and other tick attributes)"
  echo "  T'(Expr) ->  (Expr as T)"
  exit 1
fi

echo "Safe syntax lint passed."
