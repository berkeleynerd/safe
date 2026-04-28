"""Inventory checks for the Phase 1H stdlib contract-boundary scanner."""

from __future__ import annotations

import json
import subprocess
import sys

import audit_stdlib_contracts
from _lib import baseline_audit_gate
from _lib.test_harness import REPO_ROOT, RunCounts, first_message, record_result


AUDIT_SCRIPT = REPO_ROOT / "scripts" / "audit_stdlib_contracts.py"
BASELINE_PATH = audit_stdlib_contracts.BASELINE_PATH
PHASE_LABEL = "Phase 1H stdlib contracts"
REQUIRED_FIELDS = (
    "fingerprint",
    "category",
    "pattern",
    "path",
    "line",
    "line_numbers",
    "first_line_text",
    "line_text",
    "package",
    "subprogram",
    "subprogram_kind",
    "implementation_path",
    "implementation_surface",
    "classification",
    "rationale",
    "follow_up",
)
EXPECTED_CATEGORY_COUNTS = {
    "stdlib-generic-formal-contract": 3,
    "stdlib-io-contract": 1,
    "stdlib-spark-off-runtime-contract": 29,
    "stdlib-spark-on-runtime-contract": 6,
    "stdlib-unknown-contract": 0,
}
EXPECTED_PACKAGE_COUNTS = {
    "IO": 1,
    "Safe_Array_Identity_Ops": 3,
    "Safe_Array_Identity_RT": 9,
    "Safe_Array_RT": 9,
    "Safe_Bounded_Strings.Generic_Bounded_String": 6,
    "Safe_Ownership_RT": 2,
    "Safe_String_RT": 9,
}


def validate_entries(payload: object, label: str) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_entries(
        payload,
        label,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_stdlib_contracts.CATEGORIES,
        valid_patterns=audit_stdlib_contracts.PATTERNS,
    )
    if not ok:
        return False, message
    assert isinstance(payload, dict)
    for entry in baseline_audit_gate.entries_for(payload):
        surface = entry.get("implementation_surface")
        if surface not in audit_stdlib_contracts.IMPLEMENTATION_SURFACES:
            return False, f"invalid {label} implementation_surface {surface!r}"
    return True, ""


def read_baseline_payload() -> tuple[dict[str, object] | None, str]:
    return baseline_audit_gate.read_baseline_payload(BASELINE_PATH, repo_root=REPO_ROOT)


def compare_inventory_scan_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    ok, message = validate_entries(live_payload, "live scan")
    if not ok:
        return False, message
    ok, message = validate_entries(baseline_payload, "baseline")
    if not ok:
        return False, message
    if live_payload != baseline_payload:
        live = baseline_audit_gate.fingerprint_map(live_payload)
        baseline = baseline_audit_gate.fingerprint_map(baseline_payload)
        new_fingerprints = sorted(set(live) - set(baseline))
        missing_fingerprints = sorted(set(baseline) - set(live))
        if new_fingerprints or missing_fingerprints:
            return (
                False,
                f"{PHASE_LABEL} live scan differs from inventory baseline: "
                f"{len(new_fingerprints)} new, {len(missing_fingerprints)} missing",
            )
        return False, f"{PHASE_LABEL} live scan entries differ from committed baseline"
    return True, ""


def run_live_scan_case() -> tuple[bool, str]:
    completed = subprocess.run(
        [sys.executable, str(AUDIT_SCRIPT), "--json"],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return False, first_message(completed)
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        return False, f"invalid scanner JSON: {exc}"
    ok, message = validate_entries(payload, "scanner JSON")
    if not ok:
        return False, message
    audit_stdlib_contracts.print_summary(
        payload,
        baseline_entries=audit_stdlib_contracts.existing_classifications(),
    )
    baseline, message = read_baseline_payload()
    if baseline is None:
        return False, message
    return compare_inventory_scan_to_baseline(payload, baseline)


def run_baseline_case() -> tuple[bool, str]:
    payload, message = read_baseline_payload()
    if payload is None:
        return False, message
    return validate_entries(payload, "baseline")


def run_multiline_declaration_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    decls = audit_stdlib_contracts.collect_contract_declarations(
        path,
        """
package Synthetic is
   procedure Copy
     (Target : in out Item;
      Source : Item)
      with Global => null,
           Always_Terminates,
           Depends => (Target => (Target, Source));
end Synthetic;
""",
    )
    if len(decls) != 1:
        return False, f"expected one multiline declaration, found {len(decls)}"
    decl = decls[0]
    if decl.subprogram != "Copy" or decl.end_line != 8:
        return False, f"unexpected multiline declaration {decl!r}"
    return True, ""


def run_parameter_semicolon_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    decls = audit_stdlib_contracts.collect_contract_declarations(
        path,
        """
package Synthetic is
   procedure Copy (Target : in out Item; Source : Item)
      with Global => null,
           Depends => (Target => Source);
end Synthetic;
""",
    )
    if len(decls) != 1:
        return False, f"expected semicolon-in-parameters declaration, found {len(decls)}"
    if "Depends" not in decls[0].line_text:
        return False, "declaration terminated at parameter-list semicolon"
    return True, ""


def run_double_quote_character_literal_case() -> tuple[bool, str]:
    line = """   Quote : constant Character := '"'; -- comment"""
    stripped = audit_stdlib_contracts.strip_comment(line)
    if "-- comment" in stripped:
        return False, "comment after double-quote character literal was not stripped"
    lines = [
        "   function Quote return Character",
        """      with Post => Quote'Result = '"';""",
        "   procedure Next;",
    ]
    end = audit_stdlib_contracts.statement_end(lines, 0)
    if end != 1:
        return False, f"statement_end crossed double-quote character literal; got {end}"
    return True, ""


def run_private_and_rename_skip_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    decls = audit_stdlib_contracts.collect_contract_declarations(
        path,
        """
package Synthetic is
   procedure Free (Value : in out Item)
      with Global => null;
   procedure Dispose (Value : in out Item) renames Free;
private
   function Private_Length (Value : Item) return Natural
      with Global => null;
end Synthetic;
""",
    )
    names = [decl.subprogram for decl in decls]
    if names != ["Free"]:
        return False, f"rename/private declarations should be skipped, got {names!r}"
    return True, ""


def run_sibling_package_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    decls = audit_stdlib_contracts.collect_contract_declarations(
        path,
        """
package Outer is
   package First is
      procedure A
        with Global => null;
   private
      procedure Hidden
        with Global => null;
   end First;

   package Second is
      procedure B
        with Global => null;
   end Second;
end Outer;
""",
    )
    packages = [(decl.package, decl.subprogram) for decl in decls]
    expected = [("Outer.First", "A"), ("Outer.Second", "B")]
    if packages != expected:
        return False, f"sibling package stack mismatch: expected {expected!r}, got {packages!r}"
    return True, ""


def run_package_body_keyword_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    decls = audit_stdlib_contracts.collect_contract_declarations(
        path,
        """
package body Not_A_Spec is
end Not_A_Spec;

package Visible is
   procedure A
     with Global => null;
end Visible;
""",
    )
    packages = [(decl.package, decl.subprogram) for decl in decls]
    if packages != [("Visible", "A")]:
        return False, f"package body keyword should not be captured, got {packages!r}"
    return True, ""


def run_dotted_child_unit_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    decls = audit_stdlib_contracts.collect_contract_declarations(
        path,
        """
package Outer.Inner is
   procedure A
     with Global => null;
end Outer.Inner;

package Sibling is
   procedure B
     with Global => null;
end Sibling;
""",
    )
    packages = [(decl.package, decl.subprogram) for decl in decls]
    expected = [("Outer.Inner", "A"), ("Sibling", "B")]
    if packages != expected:
        return False, f"dotted child-unit package mismatch: expected {expected!r}, got {packages!r}"
    return True, ""


def run_expression_function_case() -> tuple[bool, str]:
    names = audit_stdlib_contracts.collect_expression_functions(
        """
package Synthetic is
   function Length (Value : Item) return Natural
      with Global => null;
private
   function Length (Value : Item) return Natural is
     (Value.Length);
   function Normal_Body (Value : Item) return Natural;
end Synthetic;
""",
    )
    if names != {"Length"}:
        return False, f"unexpected private expression completions {sorted(names)!r}"
    return True, ""


def run_expected_inventory_case() -> tuple[bool, str]:
    payload = audit_stdlib_contracts.scan()
    category_counts = audit_stdlib_contracts.counts_by_category(payload)
    for category, expected in EXPECTED_CATEGORY_COUNTS.items():
        actual = category_counts.get(category)
        if actual != expected:
            return False, f"{category} expected {expected}, got {actual}"
    package_counts = audit_stdlib_contracts.counts_by_package(payload)
    if package_counts != EXPECTED_PACKAGE_COUNTS:
        return False, f"unexpected package counts {package_counts!r}"
    surface_counts = audit_stdlib_contracts.counts_by_surface(payload)
    for stop_surface in ("missing", "unknown"):
        if surface_counts.get(stop_surface, 0) != 0:
            return False, f"unexpected implementation_surface {stop_surface}"
    return True, ""


def run_stdlib_contract_audit_checks() -> RunCounts:
    passed = 0
    failures = []
    passed += record_result(failures, "phase1h-stdlib-contract-audit:scan", run_live_scan_case())
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:baseline",
        run_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:multiline-declaration",
        run_multiline_declaration_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:parameter-semicolon",
        run_parameter_semicolon_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:double-quote-character-literal",
        run_double_quote_character_literal_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:private-and-rename-skip",
        run_private_and_rename_skip_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:sibling-package",
        run_sibling_package_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:package-body-keyword",
        run_package_body_keyword_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:dotted-child-unit",
        run_dotted_child_unit_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:expression-function",
        run_expression_function_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:expected-inventory",
        run_expected_inventory_case(),
    )
    return passed, 0, failures
