#!/usr/bin/env python3
"""Generate docs/po_index.md from clauses/po_map.yaml."""

import yaml
from collections import Counter, defaultdict

def main():
    with open('clauses/po_map.yaml') as f:
        data = yaml.safe_load(f)

    with open('clauses/clauses.yaml') as f:
        clauses_data = yaml.safe_load(f)

    clause_lookup = {c['id']: c for c in clauses_data['clauses']}
    entries = data['po_entries']

    target_counts = Counter(e['target'] for e in entries)
    mechanism_counts = Counter(e['mechanism'] for e in entries)
    status_counts = Counter(e['status'] for e in entries)

    by_target = defaultdict(list)
    for e in entries:
        by_target[e['target']].append(e)

    # D-rule cross-reference
    d27_by_rule = defaultdict(list)
    for e in entries:
        clause = clause_lookup.get(e['clause_id'], {})
        tags = clause.get('tags', [])
        for tag in tags:
            if tag.startswith('D') and len(tag) > 1 and tag[1:].isdigit():
                d27_by_rule[tag].append((e['clause_id'], e['summary'], e['target']))

    # All assumptions
    all_assumptions = set()
    for e in entries:
        for a in e.get('assumptions', []):
            all_assumptions.add(a)

    def shorten(cid):
        return cid.replace('SAFE@468cf72:', '')

    lines = []
    lines.append('# Proof Obligation Index')
    lines.append('')
    lines.append('## Overview')
    lines.append('')
    lines.append('- **Source commit**: `468cf72332724b04b7c193b4d2a3b02f1584125d`')
    lines.append('- **Generation date**: 2026-03-05')
    lines.append('- **Source clauses**: `clauses/clauses.yaml`')
    lines.append('- **Total clauses**: 205')
    lines.append('- **Total PO entries**: ' + str(len(entries)))
    lines.append('')
    lines.append('---')
    lines.append('')

    # Summary statistics
    lines.append('## Summary Statistics')
    lines.append('')
    lines.append('### By Target Category')
    lines.append('')
    lines.append('| Target | Count | Percentage |')
    lines.append('|--------|------:|------------|')
    target_order = ['Bronze-flow', 'Silver-AoRTE', 'Memory-safety', 'Race-freedom', 'Determinism', 'Library-safety', 'Conformance']
    for t in target_order:
        c = target_counts.get(t, 0)
        pct = '{:.1f}%'.format(100*c/len(entries))
        lines.append('| ' + t + ' | ' + str(c) + ' | ' + pct + ' |')
    lines.append('| **Total** | **' + str(len(entries)) + '** | **100.0%** |')
    lines.append('')

    lines.append('### By Verification Mechanism')
    lines.append('')
    lines.append('| Mechanism | Count | Percentage |')
    lines.append('|-----------|------:|------------|')
    mech_order = ['flow_contract_check', 'gnatprove_proof_vc', 'ghost_model_invariant', 'runtime_wrapper_check', 'translation_validation', 'k_semantics_proof', 'coq_lemma', 'manual_review', 'test_assertion', 'assumption_tracking']
    for m in mech_order:
        c = mechanism_counts.get(m, 0)
        if c > 0:
            pct = '{:.1f}%'.format(100*c/len(entries))
            lines.append('| ' + m + ' | ' + str(c) + ' | ' + pct + ' |')
    lines.append('| **Total** | **' + str(len(entries)) + '** | **100.0%** |')
    lines.append('')

    lines.append('### By Status')
    lines.append('')
    lines.append('| Status | Count | Percentage |')
    lines.append('|--------|------:|------------|')
    for s in ['implemented', 'stubbed', 'deferred']:
        c = status_counts.get(s, 0)
        if c > 0:
            pct = '{:.1f}%'.format(100*c/len(entries))
            lines.append('| ' + s + ' | ' + str(c) + ' | ' + pct + ' |')
    lines.append('| **Total** | **' + str(len(entries)) + '** | **100.0%** |')
    lines.append('')
    lines.append('---')
    lines.append('')

    # Full table by target
    lines.append('## PO Entries by Target Category')
    lines.append('')

    for t in target_order:
        group = by_target.get(t, [])
        if not group:
            continue
        lines.append('### ' + t + ' (' + str(len(group)) + ' entries)')
        lines.append('')
        lines.append('| # | Clause ID (short) | Summary | Mechanism | Status |')
        lines.append('|--:|-------------------|---------|-----------|--------|')
        for i, e in enumerate(group, 1):
            cid_short = shorten(e['clause_id'])
            summary_short = e['summary'][:80]
            lines.append('| ' + str(i) + ' | `' + cid_short + '` | ' + summary_short + ' | ' + e['mechanism'] + ' | ' + e['status'] + ' |')
        lines.append('')

    lines.append('---')
    lines.append('')

    # D-rule cross-reference
    lines.append('## D-Rule Cross-Reference')
    lines.append('')
    lines.append('This table maps specification design decisions (D-rules) to their corresponding PO entries.')
    lines.append('')

    for d_rule in sorted(d27_by_rule.keys(), key=lambda x: int(x[1:])):
        entries_for_rule = d27_by_rule[d_rule]
        lines.append('### ' + d_rule + ' (' + str(len(entries_for_rule)) + ' POs)')
        lines.append('')
        lines.append('| Clause ID (short) | Summary | Target |')
        lines.append('|-------------------|---------|--------|')
        for cid, summary, target in entries_for_rule:
            cid_short = shorten(cid)
            lines.append('| `' + cid_short + '` | ' + summary[:70] + ' | ' + target + ' |')
        lines.append('')

    lines.append('---')
    lines.append('')

    # Assumptions
    lines.append('## Assumptions Registry')
    lines.append('')
    lines.append('The following assumptions are made across PO entries. Each must be validated or justified.')
    lines.append('')
    for i, a in enumerate(sorted(all_assumptions), 1):
        using = [shorten(e['clause_id']) for e in data['po_entries'] if a in e.get('assumptions', [])]
        lines.append(str(i) + '. **' + a + '**')
        lines.append('   - Used by: ' + str(len(using)) + ' PO(s)')
        if len(using) <= 5:
            for u in using:
                lines.append('     - `' + u + '`')
        else:
            for u in using[:3]:
                lines.append('     - `' + u + '`')
            lines.append('     - ...and ' + str(len(using)-3) + ' more')
        lines.append('')

    lines.append('---')
    lines.append('')

    # Risk assessment
    lines.append('## Risk Assessment')
    lines.append('')
    lines.append('### Highest Priority POs for Proof')
    lines.append('')
    lines.append('The following PO categories represent the highest risk areas that require')
    lines.append('priority attention in the SPARK companion proof effort.')
    lines.append('')

    lines.append('#### Priority 1: Silver AoRTE (D27 Rules 1-5)')
    lines.append('')
    lines.append('These POs directly back the Silver guarantee -- the central value proposition')
    lines.append('of the Safe language. Failure to prove any of these would undermine the')
    lines.append('fundamental claim that every conforming Safe program is free of runtime errors.')
    lines.append('')
    lines.append('- **Rule 1 (Wide Intermediate Arithmetic)**: 5 POs covering overflow and range checks.')
    lines.append('  Risk: sound static range analysis correctness. Interval arithmetic must be proven sound.')
    lines.append('- **Rule 2 (Provable Index Safety)**: 2 POs covering array bounds checks.')
    lines.append('  Risk: type containment and range analysis interaction with dynamic bounds.')
    lines.append('- **Rule 3 (Division by Provably Nonzero Divisor)**: 2 POs covering division-by-zero.')
    lines.append('  Risk: nonzero proof methods must be exhaustively enumerated.')
    lines.append('- **Rule 4 (Not-Null Dereference)**: 1 PO covering null dereference.')
    lines.append('  Risk: flow-sensitive null tracking must integrate with ownership model.')
    lines.append('- **Rule 5 (Floating-Point Non-Trapping)**: 4 POs covering IEEE 754 compliance.')
    lines.append('  Risk: hardware compliance assumption; FP range analysis precision.')
    lines.append('')

    lines.append('#### Priority 2: Memory Safety (Ownership Model)')
    lines.append('')
    lines.append('These POs back the ownership, borrowing, and lifetime containment guarantees.')
    lines.append('The ownership model is novel relative to standard SPARK and requires ghost')
    lines.append('model invariants that have no direct precedent.')
    lines.append('')
    mem_count = len(by_target.get('Memory-safety', []))
    lines.append('- **' + str(mem_count) + ' POs** covering move semantics, borrow freezing,')
    lines.append('  lifetime containment, automatic deallocation, and channel ownership transfer.')
    lines.append('- Key risk: channel ownership transfer atomicity during concurrent operations.')
    lines.append('- Key risk: null-before-move flow analysis completeness.')
    lines.append('')

    lines.append('#### Priority 3: Race Freedom (Task-Variable Ownership)')
    lines.append('')
    lines.append('These POs back the data race freedom guarantee -- a critical safety property.')
    lines.append('')
    race_count = len(by_target.get('Race-freedom', []))
    lines.append('- **' + str(race_count) + ' POs** covering task-variable ownership,')
    lines.append('  channel atomicity, non-termination, and elaboration ordering.')
    lines.append('- Key risk: cross-package transitivity of effect summaries.')
    lines.append('- Key risk: channel ceiling priority computation correctness.')
    lines.append('')

    lines.append('#### Priority 4: Bronze Flow Analysis')
    lines.append('')
    bronze_count = len(by_target.get('Bronze-flow', []))
    lines.append('- **' + str(bronze_count) + ' POs** covering Global, Depends, Initializes derivation.')
    lines.append('- Lower risk: well-understood problem with existing GNATprove tooling.')
    lines.append('- Key risk: automatic derivation correctness proof (no user annotations).')
    lines.append('')

    lines.append('#### Priority 5: Determinism')
    lines.append('')
    det_count = len(by_target.get('Determinism', []))
    lines.append('- **' + str(det_count) + ' POs** covering select ordering, initialization ordering,')
    lines.append('  scheduling, and FIFO channel semantics.')
    lines.append('- Key risk: implementation-defined behavior documentation completeness.')
    lines.append('')

    lines.append('#### Priority 6: Conformance and Library Safety')
    lines.append('')
    conf_count = len(by_target.get('Conformance', []))
    lib_count = len(by_target.get('Library-safety', []))
    lines.append('- **' + str(conf_count) + ' Conformance POs**: mostly syntactic restriction')
    lines.append('  checks that are straightforward translation validations.')
    lines.append('- **' + str(lib_count) + ' Library-safety POs**: retained library modifications.')
    lines.append('- Low risk: primarily implementable as compiler front-end checks.')
    lines.append('')

    lines.append('### Deferred POs')
    lines.append('')
    deferred = [e for e in data['po_entries'] if e['status'] == 'deferred']
    if deferred:
        lines.append(str(len(deferred)) + ' PO(s) are deferred, requiring future tooling or spec resolution:')
        lines.append('')
        for e in deferred:
            cid_short = shorten(e['clause_id'])
            lines.append('- `' + cid_short + '`: ' + e['summary'])
        lines.append('')
    else:
        lines.append('No POs are currently deferred.')
        lines.append('')

    lines.append('### Stubbed POs')
    lines.append('')
    stubbed = [e for e in data['po_entries'] if e['status'] == 'stubbed']
    lines.append(str(len(stubbed)) + ' PO(s) are stubbed -- they have identified verification mechanisms')
    lines.append('but the SPARK companion stubs are not yet implemented. These will be')
    lines.append('addressed in subsequent implementation tasks.')
    lines.append('')

    output = '\n'.join(lines)
    with open('docs/po_index.md', 'w') as f:
        f.write(output)

    print('Generated docs/po_index.md (' + str(len(lines)) + ' lines)')

if __name__ == '__main__':
    main()
