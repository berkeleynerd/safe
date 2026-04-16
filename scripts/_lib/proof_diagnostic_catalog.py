"""Safe-native classification catalog for GNATprove diagnostics."""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Pattern


@dataclass(frozen=True)
class ProofDiagnosticPattern:
    gnatprove_re: Pattern[str]
    safe_message: str
    fix_guidance: str

    @classmethod
    def from_regex(cls, pattern: str, safe_message: str, fix_guidance: str) -> "ProofDiagnosticPattern":
        return cls(
            gnatprove_re=re.compile(pattern, re.IGNORECASE),
            safe_message=safe_message,
            fix_guidance=fix_guidance,
        )


DEFAULT_CATALOG: list[ProofDiagnosticPattern] = [
    ProofDiagnosticPattern.from_regex(
        r"range check might fail",
        "value may exceed type range at conversion",
        "Use a wider type, add a guard (`if value >= lo and then value <= hi`), or use `for` instead of `while`.",
    ),
    ProofDiagnosticPattern.from_regex(
        r"overflow check might fail",
        "arithmetic may overflow",
        "Use a wider accumulator type or restructure to avoid bounded-type accumulation in loops.",
    ),
    ProofDiagnosticPattern.from_regex(
        r"assertion might fail",
        "generated proof assertion could not be verified",
        "Check that all variables used in the expression are initialized and in range at this point.",
    ),
    ProofDiagnosticPattern.from_regex(
        r"loop should mention .* in a loop invariant",
        "prover cannot establish loop body safety without additional facts",
        "Restructure the loop to use bounded iteration (`for item of`) or a wider accumulator type.",
    ),
    ProofDiagnosticPattern.from_regex(
        r"call to a volatile function in interfering context",
        "shared reads in compound conditions must be snapshot first",
        "Read the shared value into a local variable before using it in `and then` / `or else`.",
    ),
    ProofDiagnosticPattern.from_regex(
        r"cannot write .* during elaboration",
        "imported state cannot be modified at unit scope",
        "Move the operation into a task body or subprogram.",
    ),
    ProofDiagnosticPattern.from_regex(
        r"uninitialized",
        "variable may be uninitialized on this path",
        "Ensure the variable is assigned before use on all code paths.",
    ),
    ProofDiagnosticPattern.from_regex(
        r"precondition might fail",
        "precondition of called function may not hold",
        "Add a guard ensuring the precondition before the call.",
    ),
]


__all__ = ["DEFAULT_CATALOG", "ProofDiagnosticPattern"]
