# Safe Language Annotated SPARK Companion

**Frozen spec commit:** `468cf72332724b04b7c193b4d2a3b02f1584125d`
**Generated:** 2026-03-02
**Generator:** spec2spark v0.1.0

---

## 1. Overview

The Safe Language Annotated SPARK Companion is a formal verification artifact that bridges the Safe language specification and SPARK 2022. It performs three functions:

1. **Clause Extraction** -- Extracts every normative clause from the Safe specification and assigns a content-addressed clause ID (format: `SAFE@<short-SHA>:spec/<file>#<section>.p<para>:<hash>`).
2. **SPARK Proof Obligations** -- Encodes the extracted clauses as SPARK ghost models (`Safe_Model`) and proof obligation procedures (`Safe_PO`) with Pre/Post contracts.
3. **Traceability** -- Maps every clause to its generated artifact, test file(s), and assumption dependencies in a machine-readable CSV and human-readable Markdown matrix.

The companion targets the Safe specification at commit `468cf72`. Any subsequent spec changes may invalidate clause references; the companion must be regenerated when the spec is updated (see assumption D-02).

---

## 2. Quick Start

### Prerequisites

| Tool | Minimum Version |
|------|----------------|
| GNAT Pro or GNAT Community | >= 14.x (Ada 2022) |
| GNATprove (SPARK Discovery) | >= 25.x |
| Alire (optional) | >= 2.x |
| CVC5 | >= 1.0.8 |
| Z3 | >= 4.12 |
| Alt-Ergo | >= 2.5 |

### Run the Full Pipeline

```bash
# From the repository root:
python3 scripts/run_tests.py
python3 scripts/run_proofs.py
python3 scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency
scripts/diff_assumptions.sh
```

This covers the current CI gates:

1. **Test** -- `python3 scripts/run_tests.py`
2. **Prove** -- `python3 scripts/run_proofs.py` (includes the companion and emitted-proof checkpoints)
3. **Embedded smoke** -- `python3 scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency`
4. **Diff against golden** -- `scripts/diff_assumptions.sh`

### Run Companion Proof Steps Directly

```bash
# Compile the companion project
gprbuild -P companion/gen/companion.gpr

# Bronze gate only (flow analysis)
gnatprove -P companion/gen/companion.gpr --mode=flow --report=all --warnings=error

# Silver gate only (proof)
gnatprove -P companion/gen/companion.gpr --mode=prove --level=2 --prover=cvc5,z3,altergo --steps=0 --timeout=120
```

---

## 3. Repository Structure

```
safe/
├── clauses/
│   ├── clauses.yaml           # 205 extracted normative clauses (2,632 lines)
│   └── po_map.yaml            # 205 PO entries mapping clauses to artifacts (1,661 lines)
├── companion/
│   ├── assumptions.yaml       # 13 tracked assumptions (229 lines)
│   ├── gen/
│   │   ├── companion.gpr      # GNAT project file (31 lines)
│   │   └── prove_golden.txt   # Golden proof baseline (18 lines)
│   ├── release/
│   │   ├── COMPANION_README.md    # This file
│   │   └── status_report.md       # Quantitative status report
│   └── spark/
│       ├── safe_model.ads     # Ghost type/function models (366 lines)
│       ├── safe_model.adb     # Ghost expression-function bodies (116 lines)
│       ├── safe_po.ads        # 23 PO procedure specs (390 lines)
│       └── safe_po.adb        # PO procedure bodies (357 lines)
├── docs/
│   ├── gnatprove_profile.md   # GNATprove configuration & prover settings (448 lines)
│   ├── po_index.md            # PO procedure index (673 lines)
│   ├── traceability_matrix.md # Full clause-to-artifact traceability (664 lines)
│   └── traceability_matrix.csv# Machine-readable traceability (206 lines)
├── meta/
│   ├── commit.txt             # Frozen spec SHA
│   └── generator_version.txt  # Generator version (spec2spark v0.1.0)
├── scripts/
│   ├── _lib/                  # Shared harness modules and inventories (16 files, 8,343 lines)
│   ├── diff_assumptions.sh    # Assumption budget enforcement (196 lines)
│   ├── extract_assumptions.sh # GNATprove output parser (129 lines)
│   ├── generate_po_index.py   # PO index generator (272 lines)
│   ├── generate_po_map.py     # PO map generator (1,137 lines)
│   ├── run_embedded_smoke.py  # Embedded smoke runner (419 lines)
│   ├── run_proofs.py          # Proof workflow runner (710 lines)
│   ├── run_samples.py         # Sample sweep runner (333 lines)
│   ├── run_tests.py           # Test-suite orchestrator (66 lines)
│   ├── safe_cli.py            # Safe CLI driver (656 lines)
│   ├── safe_lsp.py            # Language server entrypoint (238 lines)
│   ├── safe_repl.py           # REPL entrypoint (131 lines)
│   ├── snapshot_emitted_ada.py# Emitted Ada snapshot checker (198 lines)
│   ├── spec2spark.sh          # Spec-to-SPARK generator (44 lines)
│   ├── validate_ast_output.py # AST contract validator (295 lines)
│   ├── validate_mir_output.py # MIR contract validator (55 lines)
│   └── validate_output_contracts.py # Output contract validator (770 lines)
├── spec/                      # Safe specification source (frozen at 468cf72)
└── tests/
    ├── positive/              # 31 valid Safe programs
    ├── negative/              # 35 rejection tests
    ├── golden/                # 3 golden Ada emission tests
    ├── concurrency/           # 5 concurrency scenario tests
    └── diagnostics_golden/    # 5 expected diagnostic outputs
```

---

## 4. Key Statistics

| Metric | Value |
|--------|-------|
| Normative clauses extracted | 205 |
| PO entries mapped | 205 |
| SPARK source lines | 1,229 (safe_model + safe_po, .ads + .adb) |
| PO procedures | 23 |
| Ghost models/functions | ordered FIFO channel model included |
| Proof checks (total) | 132 |
| -- Flow checks | 32 (24%) |
| -- Proved (CVC5) | 99 (75%) |
| -- Justified | 1 (1%) -- FP_Safe_Div, assumption A-05 |
| -- Unproved | 0 |
| Tracked assumptions | 13 tracked (12 open, 1 resolved) |
| Test files | 79 |
| Documentation files | 4 |
| Repository scripts/modules | 32 tracked files (13,992 lines) |

---

## 5. PO Category Breakdown

| Category | Clause Count | Description |
|----------|-------------|-------------|
| Bronze-flow | 5 | Data-flow, initialization, termination |
| Silver-AoRTE | 30 | Absence of runtime errors (overflow, range, division, index, null) |
| Memory-safety | 28 | Ownership, borrowing, observing, lifetime |
| Race-freedom | 23 | Channel safety, task-variable exclusivity |
| Determinism | 9 | FIFO ordering, select semantics, elaboration order |
| Library-safety | 2 | Retained library restrictions |
| Conformance | 108 | Legality rules, static semantics, implementation requirements |
| **Total** | **205** | |

---

## 6. D27 Rule Coverage

| D27 Rule | Spec Section | Clauses | Procedures | Test Files |
|----------|-------------|---------|------------|------------|
| Rule 1: Wide Intermediate Arithmetic | 2.8.1 | 7 | 8 (`Safe_Div`, `Narrow_Assignment`, `Narrow_Parameter`, `Narrow_Return`, `Narrow_Indexing`, `Narrow_Conversion`, + `Range64` model) | 15 |
| Rule 2: Provable Index Safety | 2.8.2 | 2 | 2 (`Narrow_Indexing`, `Safe_Index`) | 12 |
| Rule 3: Division by Nonzero | 2.8.3 | 2 | 5 (`Safe_Div`, `Nonzero`, `Safe_Mod`, `Safe_Rem`, + `Excludes_Zero` model) | 12 |
| Rule 4: Not-Null Dereference | 2.8.4 | 1 | 4 (`Not_Null_Ptr`, `Safe_Deref`, + `Is_Dereferenceable`, `Is_Accessible` models) | 10 |
| Rule 5: FP Non-Trapping | 2.8.5 | 5 | 3 (`FP_Safe_Div`, `FP_Not_NaN`, `FP_Not_Infinity`) | 10 |

---

## 7. Assumption Registry

The companion tracks 13 assumptions -- dependencies that the SPARK model relies on but cannot verify within SPARK itself. One of those (`B-02`, FIFO ordering) is retained as a resolved audit entry; the remaining 12 stay open. Full details are in `companion/assumptions.yaml`.

| Severity | Count | IDs |
|----------|-------|-----|
| Critical | 5 | A-01 (64-bit intermediates), A-02 (IEEE 754 non-trapping), A-03 (range analysis soundness), A-04 (channel serialization), A-06 (heap runtime contracts) |
| Major | 4 tracked (3 open, 1 resolved) | A-05 (FP division overflow guard), B-01 (ownership state completeness), B-02 (FIFO ordering, resolved), B-03 (task-var map coverage) |
| Minor | 4 | B-04 (Boolean null model), C-01 (flow analysis sufficiency), C-02 (Ghost erasure), D-02 (frozen spec commit) |

**Budget limits:** max 15 open (current: 12), max 5 open critical (current: 5). Open count within limits; open-critical AT LIMIT.

---

## 8. CI Pipeline

The 5-step verification pipeline runs on every push and PR:

```
Step 1: Compile
  gprbuild -P companion/gen/companion.gpr
  Gate: compilation success
        │
        ▼
Step 2: Flow Analysis (Bronze)
  gnatprove --mode=flow --report=all --warnings=error
  Gate: 32/32 flow checks, 0 errors
        │
        ▼
Step 3: Prove (Silver)
  gnatprove --mode=prove --level=2 --prover=cvc5,z3,altergo
  Gate: 132 checks, 99 proved, 1 justified, 0 unproved
        │
        ▼
Step 4: Extract Assumptions
  scripts/extract_assumptions.sh
  Gate: extraction success
        │
        ▼
Step 5: Diff Against Golden
  scripts/diff_assumptions.sh
  Gate: zero diff against prove_golden.txt, budget within limits
```

---

## 9. Verification Strategy

The companion relies exclusively on GNATprove for formal verification at two assurance gates:

- **Bronze gate** -- flow analysis (data-flow, initialization, termination): 32/32 checks proved
- **Silver gate** -- absence of runtime errors via formal proof: 99 checks proved by CVC5, 1 justified

GNATprove uses Why3 internally as its intermediate VC language and dispatches to CVC5, Z3, and Alt-Ergo solvers. No additional verification tools are required. See `docs/gnatprove_profile.md` for configuration details.

### Deferred Scoping Documents

The `archive/docs/` directory also contains three supplementary scoping documents that analyze potential future verification approaches. These are **reference material only** -- not active deliverables and not included in the artifact inventory counts:

| Document | Scope | Status |
|----------|-------|--------|
| `archive/docs/why3_alignment.md` | Why3 intermediate VC alignment analysis | Deferred -- GNATprove uses Why3 internally |
| `archive/docs/mechanized_scope.md` | Coq/Isabelle mechanized proof scoping | Deferred -- requires compiler to verify |
| `archive/docs/k_semantics_scope.md` | K-Framework executable semantics scoping | Deferred -- requires compiler output to cross-check |

---

## 10. Traceability

Full clause-to-artifact traceability is maintained in two formats:

- **`docs/traceability_matrix.md`** -- Human-readable Markdown with per-spec-file tables, PO category summary, D27 rule coverage, assumption cross-reference, test coverage summary, and pipeline diagrams.
- **`docs/traceability_matrix.csv`** -- Machine-readable CSV (206 lines: 1 header + 205 data rows) with columns: `clause_id`, `spec_file`, `section`, `paragraph`, `category`, `target`, `artifact_file`, `artifact_element`, `test_files`, `status`, `assumptions`.

**Clause ID format:** `SAFE@468cf72:spec/<file>#<section>.p<paragraph>:<content-hash>`

The short SHA prefix (`468cf72`) anchors every clause to the frozen spec commit.

---

## 11. Deferred & Known Issues

### Stubbed POs

204 of 205 PO entries are in "stubbed" status. This means the PO mapping and SPARK contract exist in the companion, but full proof discharge against the implementation has not yet been completed. The stubbed POs define the proof interface that a conforming Safe compiler must satisfy.

### Deferred PO

1 PO is deferred: clause `0.8.p27:5000a79a` (14 TBD items in the spec front matter). These will be resolved when the spec TBD register is finalized.

### Justified VC

1 verification condition is justified rather than proved: the float overflow check in `FP_Safe_Div`. GNATprove cannot discharge this at level 2 because dividing a finite X by a very small finite Y can produce infinity. The compiler's narrowing-point analysis provides the runtime guarantee (see assumption A-05, M3-AUD-002).

### Closed M3 Minors

| Finding | Description | Status |
|---------|-------------|--------|
| M3-AUD-006 | Pin Alire toolchain versions in CI | Closed |
| M3-AUD-007 | Pin GitHub Actions to commit SHAs | Closed |
| M3-AUD-008 | Cache/clean interaction in CI | Closed |

---

## 12. Normative References

- **Safe specification:** Frozen at commit `468cf72332724b04b7c193b4d2a3b02f1584125d`
- **Spec files parsed:** `spec/00-front-matter.md` through `spec/08-syntax-summary.md` (10 files)
- **Ada 2022:** ISO/IEC 8652:2023
- **SPARK 2022:** SPARK Reference Manual (AdaCore)
- **GNATprove:** SPARK User's Guide (AdaCore)

---

*End of COMPANION_README.md*
