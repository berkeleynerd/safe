"""Baseline-gated checks for the Phase 1H stdlib contract-boundary scanner."""

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
ACCEPTED = baseline_audit_gate.ACCEPTED
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


def validate_closed_baseline(payload: dict[str, object]) -> tuple[bool, str]:
    ok, message = baseline_audit_gate.validate_closed_baseline(
        payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_stdlib_contracts.CATEGORIES,
        valid_patterns=audit_stdlib_contracts.PATTERNS,
    )
    if not ok:
        return False, message
    for entry in baseline_audit_gate.entries_for(payload):
        surface = entry.get("implementation_surface")
        if surface not in audit_stdlib_contracts.IMPLEMENTATION_SURFACES:
            return False, f"invalid baseline implementation_surface {surface!r}"
        if surface in {"missing", "unknown"}:
            return (
                False,
                f"closed {PHASE_LABEL} baseline cannot accept "
                f"implementation_surface {surface!r} at {baseline_audit_gate.describe_entry(entry)}",
            )
    return True, ""


def compare_live_scan_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    return baseline_audit_gate.compare_live_scan_to_baseline(
        live_payload,
        baseline_payload,
        phase_label=PHASE_LABEL,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_stdlib_contracts.CATEGORIES,
        valid_patterns=audit_stdlib_contracts.PATTERNS,
    )


def compare_implementation_surface_to_baseline(
    live_payload: dict[str, object],
    baseline_payload: dict[str, object],
) -> tuple[bool, str]:
    """Validate cross-file implementation metadata separately from the fingerprint."""

    live = baseline_audit_gate.fingerprint_map(live_payload)
    baseline = baseline_audit_gate.fingerprint_map(baseline_payload)
    for fingerprint in sorted(set(live) & set(baseline)):
        live_surface = live[fingerprint].get("implementation_surface")
        baseline_surface = baseline[fingerprint].get("implementation_surface")
        if live_surface != baseline_surface:
            package = live[fingerprint].get("package")
            subprogram = live[fingerprint].get("subprogram")
            return (
                False,
                f"{PHASE_LABEL} implementation_surface drift for "
                f"{package}.{subprogram}: {baseline_surface!r} -> {live_surface!r} at "
                f"{baseline_audit_gate.describe_entry(live[fingerprint])}",
            )
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
    ok, message = validate_closed_baseline(baseline)
    if not ok:
        return False, message
    ok, message = compare_live_scan_to_baseline(payload, baseline)
    if not ok:
        return False, message
    if message:
        print(message)
    ok, message = compare_implementation_surface_to_baseline(payload, baseline)
    if not ok:
        return False, message
    return True, ""


def run_baseline_case() -> tuple[bool, str]:
    payload, message = read_baseline_payload()
    if payload is None:
        return False, message
    return validate_closed_baseline(payload)


def synthetic_entry(
    fingerprint: str,
    *,
    classification: str = ACCEPTED,
    rationale: str = "Accepted: synthetic Phase 1H stdlib contract entry.",
    implementation_surface: str = "spark-off-body",
) -> dict[str, object]:
    return {
        "fingerprint": fingerprint,
        "category": "stdlib-spark-off-runtime-contract",
        "pattern": "stdlib-contract-subprogram",
        "path": "compiler_impl/stdlib/ada/synthetic.ads",
        "line": 1,
        "line_numbers": [1],
        "first_line_text": "function Clone (Source : Item) return Item",
        "line_text": "function Clone (Source : Item) return Item with Global => null;",
        "package": "Safe_Array_RT",
        "subprogram": "Clone",
        "subprogram_kind": "function",
        "implementation_path": "compiler_impl/stdlib/ada/synthetic.adb",
        "implementation_surface": implementation_surface,
        "classification": classification,
        "rationale": rationale,
        "follow_up": "",
    }


def run_gate_self_check_case() -> tuple[bool, str]:
    return baseline_audit_gate.run_gate_self_check(
        phase_label=PHASE_LABEL,
        synthetic_entry=synthetic_entry,
        required_fields=REQUIRED_FIELDS,
        valid_categories=audit_stdlib_contracts.CATEGORIES,
        valid_patterns=audit_stdlib_contracts.PATTERNS,
    )


def run_gate_implementation_surface_drift_case() -> tuple[bool, str]:
    baseline = {"entries": [synthetic_entry("same", implementation_surface="spark-off-body")]}
    for drift_surface in ("spark-on-body", "expression-function", "missing", "unknown"):
        live = {"entries": [synthetic_entry("same", implementation_surface=drift_surface)]}
        ok, message = compare_implementation_surface_to_baseline(live, baseline)
        if ok or "spark-off-body" not in message or drift_surface not in message:
            return (
                False,
                "implementation_surface drift should fail with both surfaces for "
                f"drift_surface={drift_surface!r}, got: {message}",
            )
    return True, ""


def run_gate_stop_surface_closed_baseline_case() -> tuple[bool, str]:
    for stop_surface in ("missing", "unknown"):
        ok, message = validate_closed_baseline(
            {"entries": [synthetic_entry("known", implementation_surface=stop_surface)]}
        )
        if ok or stop_surface not in message:
            return (
                False,
                "closed baseline should reject stop-signal implementation_surface "
                f"{stop_surface!r}, got: {message}",
            )
    return True, ""


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


def run_case_insensitive_aspect_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    decls = audit_stdlib_contracts.collect_contract_declarations(
        path,
        """
package Synthetic is
   procedure Lowercase
     with global => null,
          post => True;
end Synthetic;
""",
    )
    if [(decl.package, decl.subprogram) for decl in decls] != [("Synthetic", "Lowercase")]:
        return False, "lowercase Ada aspect names were not detected"
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


def run_parenthesis_character_literal_case() -> tuple[bool, str]:
    lines = [
        "   function Open_Paren return Character",
        "      with Post => Open_Paren'Result = '(';",
        "   procedure Next;",
    ]
    end = audit_stdlib_contracts.statement_end(lines, 0)
    if end != 1:
        return False, f"statement_end crossed parenthesis character literal; got {end}"
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


def run_nested_package_private_scope_case() -> tuple[bool, str]:
    path = REPO_ROOT / "compiler_impl" / "stdlib" / "ada" / "synthetic.ads"
    text = """
package Outer is
   function Length (Value : Item) return Natural
      with Global => null;
private
   package Inner is
      procedure Hidden_Inner
        with Global => null;
   end Inner;

   function Length (Value : Item) return Natural is
     (Value.Length);
   procedure Hidden_After_Inner
     with Global => null;
end Outer;
"""
    decls = audit_stdlib_contracts.collect_contract_declarations(path, text)
    packages = [(decl.package, decl.subprogram) for decl in decls]
    if packages != [("Outer", "Length")]:
        return False, f"private declarations leaked after nested package close: {packages!r}"
    names = audit_stdlib_contracts.collect_expression_functions(text)
    if names != {("Outer", "Length")}:
        return False, f"private expression function missed after nested package close: {names!r}"
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
    expected = {("Synthetic", "Length")}
    if names != expected:
        return False, f"unexpected private expression completions {sorted(names)!r}"
    return True, ""


def run_expression_function_private_scope_case() -> tuple[bool, str]:
    names = audit_stdlib_contracts.collect_expression_functions(
        """
package First is
private
   function Hidden (Value : Item) return Natural is
     (Value.Length);
end First;

package Second is
   function Visible (Value : Item) return Natural is
     (Value.Length);
end Second;
""",
    )
    expected = {("First", "Hidden")}
    if names != expected:
        return False, f"private expression scope leaked across packages: {sorted(names)!r}"
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
        "phase1h-stdlib-contract-audit:gate-self-check",
        run_gate_self_check_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:gate-implementation-surface-drift",
        run_gate_implementation_surface_drift_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:gate-stop-surface-baseline",
        run_gate_stop_surface_closed_baseline_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:multiline-declaration",
        run_multiline_declaration_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:case-insensitive-aspect",
        run_case_insensitive_aspect_case(),
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
        "phase1h-stdlib-contract-audit:parenthesis-character-literal",
        run_parenthesis_character_literal_case(),
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
        "phase1h-stdlib-contract-audit:nested-package-private-scope",
        run_nested_package_private_scope_case(),
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
        "phase1h-stdlib-contract-audit:expression-function-private-scope",
        run_expression_function_private_scope_case(),
    )
    passed += record_result(
        failures,
        "phase1h-stdlib-contract-audit:expected-inventory",
        run_expected_inventory_case(),
    )
    return passed, 0, failures
