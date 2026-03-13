# Post-PR10 Scope Audit

Audit date: `2026-03-13`

This note records the cleanup applied to
[`docs/post_pr10_scope.md`](post_pr10_scope.md) so it reflects only items
deferred beyond `PR10`.

## Removed Fixed Items

- Dead `Op_Call` scaffolding in `mir_analyze`
  Source validation: `compiler_impl/src/safe_frontend-mir_analyze.adb`
- `safei` channel validation weakness
  Source validation: `scripts/validate_output_contracts.py`
- Malformed interface type-field acceptance
  Source validation: `compiler_impl/src/safe_frontend-interfaces.adb`
- `ensure_sdkroot` dropping `PATH`
  Source validation: `scripts/_lib/harness_common.py`

## Removed Pre-PR10 Tracked Items

- Imported Silver ownership through calls
  Rationale: cross-package imported-summary consumption is already tracked under
  `PR08.4`
- Emitter placeholder for "PR09/PR10 discoveries"
  Rationale: `PR09` and `PR10` are tracked milestones, not post-PR10 overflow
- Named-number follow-on work stays under `PR08.3b`
  Rationale: named numbers are the next tracked milestone, not a post-PR10 item

## Removed Spec-Excluded Items

- Protected type declarations
  Source validation: `spec/02-restrictions.md` paragraph 58
- Absolute `delay until`
  Source validation: `spec/02-restrictions.md` paragraph 60
- Access discriminants
  Source validation: `spec/02-restrictions.md` paragraph 11
- Exceptions and handlers
  Source validation: `spec/02-restrictions.md` paragraph 67
- `accept` statements
  Source validation: `spec/02-restrictions.md` paragraphs 59 and 61
- `raise` statements
  Source validation: `spec/02-restrictions.md` paragraph 67

## Moved To Language Design or Authoritative Future-Proposal Docs

- Named loop labels and named exits
  Rationale: already covered by
  [`docs/syntax_proposals.md`](syntax_proposals.md)
- Generic units / restricted generics discussion
  Rationale: future generics work belongs in
  [`docs/syntax_proposals.md`](syntax_proposals.md)
- The duplicated Syntax Proposals section from the old draft
  Rationale: `docs/syntax_proposals.md` is already authoritative

## Rewritten Retained Items

- `try_receive` pending-move item
  Old status: blocking correctness gap
  New status: analyzer precision improvement under the current conservative,
  spec-compliant behaviour
- `Raise/accept/goto statements`
  Old status: combined mixed row
  New status: rewritten as `goto statements` only
- Proof-obligation rows
  Old status: two raw counts from `docs/po_index.md`
  New status: one post-PR10 assurance item for proof discharge beyond the
  selected `PR10` GNATprove gate
- The full spec TBD register
  Old status: duplicated entire `spec/00-front-matter.md` list
  New status: trimmed to post-PR10 items that are not already tracked before
  `PR10`

## Newly Added Post-PR10 Items

- Selective interface search-dir scanning or scoped tolerance for unrelated
  malformed `.safei.json` files
  Source validation: `PR08.3` review fallout
- Ada-side Bronze regression harness independent of Python evidence
  re-derivation
  Source validation: `PR08.2` review fallout
- Constant access-object mutability semantics through `.all` writes
  Source validation: `PR08.3a` review fallout

## Priority Count Delta

| Priority | Old Count | New Count | Delta |
|----------|----------:|----------:|------:|
| `blocking-if-needed` | 21 | 14 | -7 |
| `nice-to-have` | 9 | 3 | -6 |
| `long-term` | 33 | 13 | -20 |
| **Total** | **63** | **30** | **-33** |
