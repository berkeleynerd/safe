# Verified Emission Templates Prompt and Maintenance Plan (SPARK 2022 rev26)

Status: Archived (templates implemented and CI-verified)
Updated: 2026-03-03

This document is a historical prompt artifact for the “Verified Emission Templates” effort.
Because the emission templates are complete, this document belongs in archive/.

If you are doing active work:
- For the authoritative templates design and layout, read: docs/template_plan.md
- For the authoritative templates proof totals and status, read: docs/template_inventory.md
- For the verification pipeline and trust boundary, read: release/COMPANION_README.md
- For GNATprove configuration policy and expected behavior, read: docs/gnatprove_profile.md


Purpose

Verified Emission Templates are standalone Ada/SPARK units that encode the intended Safe→Ada/SPARK emission shapes and prove them under GNATprove. They bridge between:

- Companion contracts (Safe_Model and Safe_PO), and
- A future compiler emitter that assembles/instantiates templates instead of generating ad-hoc SPARK.

This repository already contains a completed templates suite under companion/templates/ and a dedicated CI job that builds and proves them.


Where the templates live

Templates reside in:
- companion/templates/

They are built and proved using:
- companion/templates/alire.toml
- companion/templates/templates.gpr
- the “templates-verify” job in .github/workflows/ci.yml

The templates rely on:
- companion/spark/safe_model.ads(.adb) (ghost models)
- companion/spark/safe_po.ads(.adb) (proof-obligation hooks)


What “Silver verified” means in this repo

A template (and its supporting units) is acceptable only if:

- It is SPARK-legal (SPARK_Mode On where intended).
- GNATprove flow analysis succeeds (Bronze gate).
- GNATprove proof mode succeeds (Silver gate) with:
  - 0 unproved verification conditions (VCs)
  - 0 unexpected warnings
- Assumption governance gates do not regress:
  - assumption extraction succeeds
  - diff/budget checks pass against the committed golden baseline


How to reproduce the template verification locally

From the repository root:

1) Run the repository pipeline (companion + templates):
   scripts/run_all.sh

2) Or run the templates subset directly:
   cd companion/templates
   alr build
   alr exec -- gnatprove -P templates.gpr --mode=flow  --report=all --warnings=on
   alr exec -- gnatprove -P templates.gpr --mode=prove --level=2 --prover=cvc5,z3,altergo \
     --steps=0 --timeout=120 --report=all --warnings=on --checks-as-errors=on

3) Assumption governance checks (drift/budget):
   (these are run in CI; see scripts and workflow for exact env settings)
   scripts/extract_assumptions.sh
   scripts/diff_assumptions.sh


Canonical Claude Code kick-off prompt (for future extensions)

Use this prompt if you want an LLM agent (Claude Code) to extend templates
because translation rules or coverage requirements changed.

START PROMPT (copy/paste):

You are Claude Code operating inside the repository berkeleynerd/safe.

Goal
Audit and, if needed, extend the Verified Emission Templates for Safe→Ada/SPARK
under SPARK 2022 rev26, without weakening the existing verification posture.

Non-negotiable constraints
- Do not implement the compiler emitter.
- Do not weaken CI verification gates.
- Do not add assumptions silently.
- Do not accept any unproved VCs.

Required reading (must do first)
- release/COMPANION_README.md
- docs/gnatprove_profile.md
- docs/template_plan.md
- docs/template_inventory.md
- .github/workflows/ci.yml
- companion/spark/safe_model.ads(.adb)
- companion/spark/safe_po.ads(.adb)
- compiler/translation_rules.md
- docs/traceability_matrix.md

Milestone 0: Baseline audit packet (STOP after this)
1) Inventory the existing templates in companion/templates/:
   - list each template file (.ads/.adb)
   - describe what emission pattern it encodes
   - list which Safe_PO hooks it calls
   - identify the translation_rules sections it corresponds to
2) Re-run template verification locally (commands documented above).
3) Verify CI parity:
   - confirm the templates-verify job runs compile → flow → prove → extract → diff
   - confirm the golden proof baseline used by templates is stable
4) Produce a single “Audit Packet” markdown file with:
   - file inventory
   - commands run
   - proof/VC summary (0 unproved required)
   - assumption diff/budget status
   - any gaps vs translation_rules.md

STOP after Milestone 0 and wait for an auditor decision.

Only after approval: extend templates
- If translation_rules.md contains an emission pattern not covered by templates:
  1) add a new standalone template package in companion/templates/
  2) call Safe_PO hooks at the required proof points
  3) ensure SPARK legality and GNATprove flow/prove succeed
  4) update docs/template_inventory.md to include the new template and its proof summary
  5) update the templates proof golden baseline only when the change is legitimate and reviewed
  6) ensure CI passes (templates-verify job)

Definition of done
- All templates (existing + new) pass flow and prove in CI with 0 unproved VCs.
- Assumption governance gates pass and remain within budget.
- docs/template_inventory.md remains accurate and up to date.

END PROMPT


Archive policy note

This document is in archive/ because the templates implementation is complete.
If a new major iteration of templates planning is created, store it in archive/ when done,
and keep active operational docs under docs/ (or referenced from README.md).
