# REVIEW.md — Claude Code Review Instructions

When reviewing pull requests in this repository, prioritize these concerns
in order:

## 1. Proof Soundness

This is a formally verified language compiler. The most critical review
axis is whether changes preserve the proof story:

- **No new `pragma Assume`** in emitted Ada without explicit justification
  and documentation in the verification matrix
- **No new `SPARK_Mode => Off`** in emitted user code (shared stdlib
  bodies are `SPARK_Mode => Off` by design; emitted user packages must not be)
- **No new `Skip_Proof`, `Skip_Flow_And_Proof`**, or blanket
  `pragma Warnings (Off)` in emitted Ada
- **No regression in proof fixture counts** — check that
  `scripts/_lib/proof_inventory.py` manifest sizes do not shrink
- **Proof exclusions must carry explicit reasons** — any fixture moved to
  `EMITTED_PROOF_EXCLUSIONS` needs `path`, `reason`, and `owner` fields

## 2. Semantic Correctness

- **Single evaluation** — send expressions, function arguments, and
  initializers must be evaluated exactly once in emitted Ada
- **Ownership invariants** — moves null the source, borrows freeze the
  lender, scope exit frees owned values
- **Channel semantics** — send is nonblocking (three-argument form only);
  receive and select block; protected bodies contain no heap operations
- **Shared record semantics** — reads return copies, writes copy into
  protected state, no live aliases escape the wrapper

## 3. Contract and Format Stability

- **No accidental version bumps** — typed/MIR/safei versions change only
  when the plan explicitly calls for it
- **Additive optional fields** do not require version bumps
- **Required field additions or semantic changes** require version bumps
- Check that `scripts/validate_output_contracts.py` is updated for any
  new contract fields

## 4. Test Coverage

- **Positive fixtures** for every new admitted surface
- **Negative fixtures** for every new rejection path, with specific
  expected diagnostic kinds in the `-- Expected: REJECT` header
- **Build/runtime fixtures** for features that affect emitted Ada
  execution behavior
- **Interface fixtures** for cross-package features
- **Emitted-shape regressions** for structural changes to emitted Ada

## 5. Code Quality

- Functions over 200 lines should be flagged for splitting
- Duplicated patterns across emission paths should be flagged
- `pragma Unreferenced` on parameters may indicate dead helper functions
- Generated Ada identifiers must be deterministic and sanitized for
  cross-unit stability

## 6. Documentation

- Spec (`spec/`) must match admitted surface
- Tutorial (`docs/tutorial.md`) should reflect new user-facing features
- Roadmap (`docs/roadmap.md`) should be updated for milestone closure
- Verification matrix should reflect any proof-surface changes

## What NOT to flag

- Ada style in emitted output (the emitter controls style, not the user)
- Python style in scripts (functional, not idiomatic Python)
- Companion template changes (these are proved separately)
- Test fixture verbosity (fixtures should be explicit, not clever)
