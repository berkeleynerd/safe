#!/usr/bin/env bash
set -euo pipefail

# Lint .safe files for banned legacy syntax tokens.
# Runs without a Safe compiler — grep-based, suitable for CI.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

FAIL=0

echo "Linting .safe files for banned legacy syntax tokens..."

# Banned tokens in Safe source (v0.2 syntax).
# :=  was assignment (now =)
# =>  was association/arm separator (now = or then)
# /=  was inequality (now !=)
# Tick-based attributes are banned; Safe uses dot notation (spec §2.4.1).
BANNED_FIXED=(
  ":="
  "=>"
  "/="
)

BANNED_TICK=(
  "'First"
  "'Last"
  "'Length"
  "'Range"
  "'Access"
  "'Valid"
  "'Image"
  "'Size"
)

while IFS= read -r -d '' f; do
  for pat in "${BANNED_FIXED[@]}"; do
    if grep -nF -- "${pat}" "${f}" >/dev/null 2>&1; then
      echo "ERROR: ${f} contains banned token '${pat}':"
      grep -nF -- "${pat}" "${f}" | head -5
      FAIL=1
    fi
  done
  for pat in "${BANNED_TICK[@]}"; do
    if grep -nF -- "${pat}" "${f}" >/dev/null 2>&1; then
      echo "ERROR: ${f} contains tick-attribute '${pat}' (use dot notation):"
      grep -nF -- "${pat}" "${f}" | head -5
      FAIL=1
    fi
  done
  # Qualified expression ticks: T'( is banned (spec §2.2 item 25).
  # Tick is only legal for character literals ('A').
  # Match: word char followed by '( — but exclude character literals like 'A'.
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
