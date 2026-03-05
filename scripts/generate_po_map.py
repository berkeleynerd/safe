#!/usr/bin/env python3
"""Generate po_map.yaml from clauses.yaml for the Safe language SPARK companion."""

import yaml
import sys

def classify_clause(clause):
    """Classify a clause into target, mechanism, summary, soundness_note, status, assumptions, artifact_location."""
    cid = clause['id']
    text = clause.get('text', '')
    section = clause.get('section', '')
    section_title = clause.get('section_title', '')
    classification = clause.get('classification', '')
    tags = clause.get('tags', [])
    notes = clause.get('notes', '')
    tbd = clause.get('tbd', False)
    source_file = clause.get('source_file', '')

    # Defaults
    target = 'Conformance'
    mechanism = 'manual_review'
    status = 'stubbed'
    assumptions = []
    artifact_location = 'companion/spark/safe_conformance.ads'
    soundness_note = ''
    summary = ''

    # ============================================================
    # Section 0 - Front Matter
    # ============================================================
    if source_file == 'spec/00-front-matter.md':
        if '0.1' in section:
            if 'p1' in cid:
                summary = 'Safe is defined subtractively from Ada 2022'
                soundness_note = 'Guarantees language identity; does NOT guarantee completeness of subtractive definition'
                mechanism = 'manual_review'
                artifact_location = 'companion/spark/safe_conformance.ads'
            elif 'p2' in cid:
                summary = 'Safe source files use .safe extension'
                soundness_note = 'Guarantees file extension convention; does NOT guarantee implementation enforcement'
                mechanism = 'test_assertion'
                artifact_location = 'companion/spark/safe_conformance.ads'
        elif '0.5' in section:
            summary = 'Specification voice conventions (shall/may/should)'
            soundness_note = 'Guarantees normative language usage; does NOT guarantee interpretation correctness'
            mechanism = 'manual_review'
            artifact_location = 'companion/spark/safe_conformance.ads'
        elif '0.8' in section:
            summary = 'All TBD items shall be resolved before baselining'
            soundness_note = 'Guarantees TBD tracking; does NOT guarantee resolution timeline'
            mechanism = 'assumption_tracking'
            status = 'deferred'
            assumptions = ['All 14 TBD items (TBD-01 through TBD-14) will be resolved']
            artifact_location = 'companion/spark/safe_tbd_tracker.ads'
        return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 1 - Base Definition
    # ============================================================
    if source_file == 'spec/01-base-definition.md':
        target = 'Conformance'
        mechanism = 'translation_validation'
        artifact_location = 'companion/spark/safe_base_definition.ads'
        if 'p1' in cid:
            summary = 'Safe is Ada 2022 restricted by Section 2 and modified by Sections 3-4'
            soundness_note = 'Guarantees base language identity; does NOT guarantee complete restriction enforcement'
        elif 'p2' in cid:
            summary = 'All Ada 2022 rules apply except where explicitly excluded or modified'
            soundness_note = 'Guarantees rule inheritance; does NOT guarantee exhaustive exclusion checking'
        elif 'p3' in cid:
            summary = 'Unmentioned constructs retained with Ada 2022 semantics plus notation changes'
            soundness_note = 'Guarantees semantic preservation; does NOT guarantee notation transform completeness'
        elif 'p6' in cid:
            summary = 'Unaddressed features retained with standard semantics'
            soundness_note = 'Guarantees fallthrough behavior; does NOT guarantee no implicit conflicts'
        return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 2 - Restrictions: Excluded Language Features
    # ============================================================
    if source_file == 'spec/02-restrictions.md':
        # D27 Rules (Silver AoRTE)
        if 'D27' in tags or 'Silver' in tags or 'Rule1' in tags or 'Rule2' in tags or 'Rule3' in tags or 'Rule4' in tags or 'Rule5' in tags:
            target = 'Silver-AoRTE'
            artifact_location = 'companion/spark/safe_silver_po.ads'

            if 'Rule1' in tags or 'integer-overflow' in tags or 'range-check' in tags:
                if 'p126' in cid:
                    summary = 'Integer arithmetic evaluated in mathematical integer type (wide intermediates)'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees no intermediate overflow; does NOT guarantee implementation uses true wide arithmetic'
                    assumptions = ['Implementation provides at least 64-bit intermediate evaluation']
                elif 'p127' in cid:
                    summary = 'Range checks only at narrowing points (assignment, parameter, return, conversion, annotation)'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees narrowing point enumeration is complete; does NOT guarantee all narrowing points are identified by tooling'
                elif 'p128' in cid:
                    summary = 'Reject integer types exceeding 64-bit signed range'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees type range bounds; does NOT guarantee cross-type interaction safety'
                elif 'p129' in cid:
                    summary = 'Reject expressions with intermediate subexpressions exceeding 64-bit range'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees overflow detection; does NOT guarantee minimal rejection (may over-approximate)'
                elif 'p130' in cid:
                    summary = 'Narrowing checks discharged via sound static range analysis'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees range safety at narrowing; does NOT guarantee analysis precision'
                    assumptions = ['Static range analysis is sound']
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if 'Rule2' in tags or 'index-check' in tags:
                if 'p131' in cid:
                    summary = 'Index expression provably within array bounds at compile time'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees no out-of-bounds access; does NOT guarantee analysis handles all array patterns'
                elif 'p132' in cid:
                    summary = 'Reject unresolvable index bound relationships with diagnostic'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees rejection of unprovable indexing; does NOT guarantee diagnostic quality'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if 'Rule3' in tags or 'division-check' in tags:
                if 'p133' in cid:
                    summary = 'Right operand of /, mod, rem provably nonzero at compile time'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees no division by zero; does NOT guarantee all nonzero proof methods are implemented'
                elif 'p134' in cid:
                    summary = 'Reject division where nonzero cannot be established'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees rejection of risky division; does NOT guarantee diagnostic quality'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if 'Rule4' in tags or 'null-check' in tags:
                summary = 'Dereference requires not-null access subtype'
                mechanism = 'gnatprove_proof_vc'
                soundness_note = 'Guarantees no null dereference; does NOT guarantee flow-sensitive null tracking'
                artifact_location = 'companion/spark/safe_silver_po.ads'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if 'Rule5' in tags or 'float-overflow' in tags or 'float-div-zero' in tags or 'float-nan' in tags or 'float-range-check' in tags:
                if 'p139' in cid and 'p139b' not in cid and 'p139c' not in cid and 'p139d' not in cid:
                    summary = 'All predefined floating-point types use IEEE 754 non-trapping arithmetic'
                    mechanism = 'runtime_wrapper_check'
                    soundness_note = 'Guarantees non-trapping FP semantics; does NOT guarantee target hardware compliance'
                    assumptions = ['Target hardware supports IEEE 754 non-trapping mode']
                elif 'p139b' in cid:
                    summary = 'Sound static range analysis for floating-point narrowing points'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees finite values at narrowing; does NOT guarantee analysis precision for FP'
                elif 'p139c' in cid:
                    summary = 'Reject floating-point narrowing points that cannot be proven safe'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees rejection of risky FP narrowing; does NOT guarantee minimal false positives'
                elif 'p139d' in cid:
                    summary = 'NaN and infinity cannot survive narrowing points'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees NaN/infinity containment; does NOT guarantee all FP corner cases are covered'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            # Generic Silver tags without specific rule
            if 'accessibility-check' in tags:
                summary = 'Accessibility checks discharged at compile time'
                mechanism = 'gnatprove_proof_vc'
                if 'p113' in cid:
                    summary = 'No runtime accessibility check code shall be emitted'
                    soundness_note = 'Guarantees compile-time accessibility verification; does NOT guarantee all Ada accessibility patterns are covered'
                elif 'p109-end' in cid:
                    summary = 'No runtime accessibility check is ever required'
                    soundness_note = 'Guarantees static accessibility resolution; does NOT guarantee correctness of simplified rules'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if 'discriminant-check' in tags:
                summary = 'Discriminant check: variant access consistent with current discriminant value'
                mechanism = 'gnatprove_proof_vc'
                soundness_note = 'Guarantees variant access safety; does NOT guarantee all discriminant patterns are handled'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            # General Silver/D27 clauses from section 5
            if 'range-check' in tags:
                if 'p25' in cid:
                    summary = 'Range checks discharged via sound static range analysis'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees range safety; does NOT guarantee analysis precision'
                elif 'p26' in cid:
                    summary = 'Reject programs with undischargeable narrowing points'
                    mechanism = 'gnatprove_proof_vc'
                    soundness_note = 'Guarantees hard rejection; does NOT guarantee minimal over-rejection'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Ownership/Memory-safety clauses
        if 'ownership' in tags or 'D17' in tags:
            target = 'Memory-safety'
            artifact_location = 'companion/spark/safe_ownership_po.ads'
            mechanism = 'ghost_model_invariant'

            if section == '2.3.2':  # Move semantics
                if 'p96a' in cid:
                    summary = 'Source object becomes null after move assignment'
                    soundness_note = 'Guarantees move nullification; does NOT guarantee all move contexts are identified'
                elif 'p96c' in cid:
                    summary = 'Reject dereference of moved-from object unless reassigned or null-checked'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees use-after-move prevention; does NOT guarantee path-sensitive tracking in all cases'
                elif 'p97a' in cid and 'diag' not in cid:
                    summary = 'Move target must be provably null at point of move'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees no ownership leak on overwrite; does NOT guarantee all null-state paths are tracked'
                elif 'p97a-diag' in cid:
                    summary = 'Reject move into non-null target with ownership conflict diagnostic'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees diagnostic on ownership conflict; does NOT guarantee diagnostic message quality'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if section == '2.3.3':  # Borrowing
                if 'p99b' in cid:
                    summary = 'Lender is frozen during active borrow (no read, write, or move)'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees exclusive borrow access; does NOT guarantee all aliasing patterns detected'
                elif 'p100a' in cid:
                    summary = 'Anonymous access variables only assigned at declaration'
                    soundness_note = 'Guarantees lexical lifetime determination; does NOT guarantee completeness of assignment detection'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if section == '2.3.4a':  # Lifetime containment
                if 'p102a' in cid and 'p102a-a' not in cid:
                    summary = 'Borrower/observer scope contained within lender/observed scope'
                    soundness_note = 'Guarantees no dangling borrow; does NOT guarantee scope analysis across all control flow'
                elif 'p102a-a' in cid:
                    summary = 'Reject borrow/observe where borrower could outlive lender'
                    soundness_note = 'Guarantees lifetime containment enforcement; does NOT guarantee all lifetime patterns are analyzed'
                elif 'p102b' in cid and 'diag' not in cid:
                    summary = 'No access value shall designate a deallocated object'
                    soundness_note = 'Guarantees no dangling access; does NOT guarantee completeness of deallocation tracking'
                elif 'p102b-diag' in cid:
                    summary = 'Reject programs with potentially dangling access values'
                    soundness_note = 'Guarantees rejection of dangling access risk; does NOT guarantee all paths analyzed'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if section == '2.3.5':  # Allocators and Deallocation
                if 'p103a' in cid:
                    summary = 'Allocation failure causes program abort with diagnostic'
                    mechanism = 'runtime_wrapper_check'
                    soundness_note = 'Guarantees defined behavior on OOM; does NOT guarantee graceful degradation'
                    assumptions = ['Runtime abort handler is correctly implemented']
                elif 'p104' in cid and 'p104a' not in cid:
                    summary = 'Automatic deallocation of non-null pool-specific access at scope exit'
                    mechanism = 'runtime_wrapper_check'
                    soundness_note = 'Guarantees no memory leak from owned access; does NOT guarantee deallocation order is safe for all types'
                elif 'p104a' in cid:
                    summary = 'Named access-to-constant types auto-deallocated at scope exit'
                    mechanism = 'runtime_wrapper_check'
                    soundness_note = 'Guarantees constant access deallocation; does NOT guarantee runtime overhead is bounded'
                elif 'p105' in cid:
                    summary = 'Multiple access objects deallocated in reverse declaration order'
                    mechanism = 'runtime_wrapper_check'
                    soundness_note = 'Guarantees deterministic deallocation order; does NOT guarantee interaction with complex scopes'
                elif 'p106' in cid:
                    summary = 'General access-to-variable types cannot be deallocated'
                    soundness_note = 'Guarantees no invalid deallocation of general access; does NOT guarantee no memory leak for general access'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if section == '2.3.7':  # Ownership checking scope
                summary = 'Ownership checking is local to compilation unit'
                mechanism = 'flow_contract_check'
                soundness_note = 'Guarantees modular checking; does NOT guarantee cross-unit ownership invariants without interface info'
                assumptions = ['Dependency interface information accurately represents effects']
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

            if section == '2.3.8':  # Accessibility rules
                if 'p111' in cid and 'p111a' not in cid and 'p111b' not in cid and 'p111c' not in cid:
                    summary = 'Reject .Access on local aliased variable where result could escape scope'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees no dangling stack reference; does NOT guarantee all escape patterns detected'
                elif 'p111a' in cid:
                    summary = 'Function shall not return .Access of local aliased variable'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees no dangling return reference; does NOT guarantee non-local escape detection'
                elif 'p111b' in cid:
                    summary = '.Access of local shall not be assigned to enclosing scope variable'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees no scope escape via assignment; does NOT guarantee complex alias chains'
                elif 'p111c' in cid:
                    summary = '.Access of local aliased variable shall not be sent through channel'
                    mechanism = 'flow_contract_check'
                    soundness_note = 'Guarantees no channel escape of stack reference; does NOT guarantee transitive escapes'
                return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Lexical/syntax exclusion legality rules - Conformance checks
        if section.startswith('2.1') or section in ['2.2', '2.7', '2.9', '2.10']:
            target = 'Conformance'
            mechanism = 'translation_validation'
            artifact_location = 'companion/spark/safe_restriction_checks.ads'

            # Generate summaries based on section
            if section == '2.1.1':
                if 'p2' in cid:
                    summary = 'Reject reserved word used as identifier'
                elif 'p3' in cid:
                    summary = 'Additional reserved words (public, channel, send, receive, etc.)'
                elif 'p4' in cid:
                    summary = 'Reject tick notation for attributes/qualified expressions'
                soundness_note = 'Guarantees lexical conformance; does NOT guarantee semantic equivalence with Ada 2022'
            elif section == '2.1.2':
                if 'p5' in cid:
                    summary = 'Reject Static_Predicate and Dynamic_Predicate aspects'
                elif 'p7' in cid:
                    summary = 'Reject tagged types, type extensions, abstract types, interfaces'
                elif 'p9' in cid:
                    summary = 'Reject access-to-subprogram type declarations'
                elif 'p11' in cid:
                    summary = 'Reject access discriminants'
                elif 'p12' in cid:
                    summary = 'Reject derivation from Controlled/Limited_Controlled'
                soundness_note = 'Guarantees type system restrictions; does NOT guarantee all Ada type constructs are checked'
            elif section == '2.1.3':
                if 'p14' in cid:
                    summary = 'Reject Implicit_Dereference aspect (user-defined references)'
                elif 'p15' in cid:
                    summary = 'Reject Constant_Indexing/Variable_Indexing (user-defined indexing)'
                elif 'p16' in cid:
                    summary = 'Reject user-defined literal aspects'
                elif 'p17' in cid:
                    summary = 'Reject extension aggregates'
                elif 'p19' in cid:
                    summary = 'Reject container aggregates'
                elif 'p22' in cid:
                    summary = 'Reject quantified expressions (for all, for some)'
                elif 'p23' in cid:
                    summary = 'Reject reduction expressions'
                elif 'p25' in cid:
                    summary = 'Reject qualified expressions using tick notation'
                soundness_note = 'Guarantees expression restriction enforcement; does NOT guarantee all expression forms checked'
            elif section == '2.1.4':
                if 'p29' in cid:
                    summary = 'Reject Default_Iterator/Iterator_Element aspects'
                elif 'p31' in cid:
                    summary = 'Reject procedural iterators'
                elif 'p32' in cid:
                    summary = 'Reject parallel block statements'
                soundness_note = 'Guarantees statement restriction enforcement; does NOT guarantee all statement forms checked'
            elif section == '2.1.5':
                if 'p34' in cid:
                    summary = 'Reject Pre, Post, Pre.Class, Post.Class aspects'
                elif 'p35' in cid:
                    summary = 'Reject user-authored Global/Global.Class aspects'
                elif 'p36' in cid:
                    summary = 'Each subprogram identifier denotes exactly one subprogram'
                    mechanism = 'flow_contract_check'
                elif 'p38' in cid:
                    summary = 'Return statement shall not appear within task body'
                    target = 'Race-freedom'
                    artifact_location = 'companion/spark/safe_task_po.ads'
                elif 'p40' in cid:
                    summary = 'Reject user-defined operator functions'
                soundness_note = 'Guarantees subprogram restrictions; does NOT guarantee all subprogram forms checked'
            elif section == '2.1.6':
                summary = 'Reject standalone package body compilation unit'
                soundness_note = 'Guarantees single-file model; does NOT guarantee compilation model completeness'
            elif section == '2.1.7':
                summary = 'Reject use Package_Name clauses'
                soundness_note = 'Guarantees visibility restriction; does NOT guarantee all use-clause forms detected'
            elif section == '2.1.8':
                if 'p57' in cid:
                    summary = 'Safe tasks shall not terminate'
                    target = 'Race-freedom'
                    artifact_location = 'companion/spark/safe_task_po.ads'
                elif 'p58' in cid:
                    summary = 'Reject user-declared protected types/objects'
                elif 'p59' in cid:
                    summary = 'Reject entry declarations, accept statements, entry calls, requeue'
                elif 'p60' in cid:
                    summary = 'Reject delay until statement'
                elif 'p61' in cid:
                    summary = 'Reject Ada select model (selective accept, timed/conditional entry call, async select)'
                elif 'p62' in cid:
                    summary = 'Reject abort statement'
                soundness_note = 'Guarantees task/sync restrictions; does NOT guarantee all Ada task constructs checked'
            elif section == '2.1.9':
                if 'p65' in cid:
                    summary = 'Library units shall be packages; library-level subprograms prohibited'
                elif 'p66' in cid:
                    summary = 'Reject circular with dependencies'
                    target = 'Race-freedom'
                    artifact_location = 'companion/spark/safe_task_po.ads'
                soundness_note = 'Guarantees program structure restrictions; does NOT guarantee dependency graph analysis'
            elif section == '2.1.10':
                summary = 'Reject exceptions, handlers, raise, pragma Suppress/Unsuppress'
                soundness_note = 'Guarantees exception exclusion; does NOT guarantee all exception-related constructs are identified'
            elif section == '2.1.11':
                summary = 'Reject generic declarations, bodies, and instantiations'
                soundness_note = 'Guarantees generics exclusion; does NOT guarantee all generic-related constructs identified'
            elif section == '2.1.12':
                if 'p77' in cid:
                    summary = 'Reject machine code insertions'
                elif 'p78' in cid:
                    summary = 'Reject Ada.Unchecked_Conversion'
                elif 'p79' in cid:
                    summary = 'Reject .Unchecked_Access'
                    target = 'Memory-safety'
                    artifact_location = 'companion/spark/safe_ownership_po.ads'
                elif 'p80' in cid:
                    summary = 'Reject Storage_Pool aspects and Ada.Unchecked_Deallocation'
                    target = 'Memory-safety'
                    artifact_location = 'companion/spark/safe_ownership_po.ads'
                elif 'p82' in cid:
                    summary = 'Reject stream attribute references and stream type declarations'
                soundness_note = 'Guarantees representation restriction; does NOT guarantee all unsafe features detected'
            elif section == '2.1.13':
                if 'p84' in cid:
                    summary = 'Reject pragma Import/Export/Convention and Annex B'
                elif 'p91' in cid:
                    summary = 'Reject Annex J obsolescent features'
                soundness_note = 'Guarantees annex restrictions; does NOT guarantee all annex features identified'
            elif section == '2.2':
                summary = 'Reject 12 SPARK verification-only aspects in Safe source'
                soundness_note = 'Guarantees SPARK aspect exclusion; does NOT guarantee auto-derivation correctness'
            elif section == '2.7':
                summary = 'Reject 12 contract-related aspects'
                soundness_note = 'Guarantees contract exclusion; does NOT guarantee all contract mechanisms identified'
            elif section == '2.9':
                summary = 'Declarations and statements may interleave freely after begin'
                mechanism = 'manual_review'
                soundness_note = 'Guarantees interleaved declaration semantics; does NOT verify compilation support'
            elif section == '2.10':
                summary = 'Reject duplicate subprogram identifiers in declarative region (no overloading)'
                mechanism = 'flow_contract_check'
                soundness_note = 'Guarantees name uniqueness; does NOT guarantee all overloading forms detected'

            if not summary:
                summary = f'Restriction check for {section_title}'
                soundness_note = f'Guarantees {section_title} enforcement; does NOT guarantee complete coverage'

            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 3 - Single-File Packages
    # ============================================================
    if source_file == 'spec/03-single-file-packages.md':
        target = 'Conformance'
        mechanism = 'translation_validation'
        artifact_location = 'companion/spark/safe_package_model.ads'

        if section == '3' or section.startswith('3.p'):
            summary = 'Public interface made available for dependent compilation units'
            mechanism = 'manual_review'
            soundness_note = 'Guarantees interface availability; does NOT guarantee interface content correctness'
        elif section == '3.2.1':
            summary = 'End identifier must match package identifier'
            soundness_note = 'Guarantees name consistency; does NOT verify beyond syntactic matching'
        elif section == '3.2.2':
            summary = 'Declaration-before-use for all names'
            soundness_note = 'Guarantees forward reference prevention; does NOT guarantee complete name resolution'
        elif section == '3.2.3':
            if 'p12' in cid:
                summary = 'Forward declaration body shall appear in same region and conform'
            elif 'p13' in cid:
                summary = 'Reject forward declaration with no completing body'
            elif 'p14' in cid:
                summary = 'Public keyword on forward declaration, not on completing body'
            soundness_note = 'Guarantees forward declaration consistency; does NOT guarantee all patterns covered'
        elif section == '3.2.4':
            summary = 'No executable statements at package level'
            soundness_note = 'Guarantees code placement restriction; does NOT guarantee all statement forms detected'
        elif section == '3.2.5':
            if 'p19' in cid:
                summary = 'Reject public annotation on invalid declaration kinds'
            elif 'p20' in cid:
                summary = 'Non-public declarations are private to declaring package'
            soundness_note = 'Guarantees visibility model; does NOT guarantee all visibility edge cases'
        elif section == '3.2.6':
            if 'p23' in cid:
                summary = 'Reject external field access on opaque types'
            elif 'p24' in cid:
                summary = 'Implementation exports size/alignment for opaque types'
                mechanism = 'manual_review'
            soundness_note = 'Guarantees opaque type encapsulation; does NOT guarantee size/alignment correctness'
        elif section == '3.2.9':
            summary = 'Reject circular with dependency cycles'
            target = 'Race-freedom'
            artifact_location = 'companion/spark/safe_task_po.ads'
            soundness_note = 'Guarantees acyclic dependency graph; does NOT guarantee topological sort correctness'
        elif section == '3.2.10':
            summary = 'Library units must be packages; reject library-level subprograms'
            soundness_note = 'Guarantees library unit form; does NOT guarantee all subprogram compilation units detected'
        elif section == '3.3.1':
            if 'p33' in cid:
                summary = 'Implementation provides 9 categories of dependency interface information'
                mechanism = 'manual_review'
            elif 'p34' in cid:
                summary = 'Dependency interface mechanism is implementation-defined'
                mechanism = 'manual_review'
            elif 'p35' in cid:
                summary = 'Reject program when dependency interface info unavailable'
            soundness_note = 'Guarantees interface information availability; does NOT guarantee information completeness'
        elif section == '3.3.4':
            summary = 'Child packages have no additional visibility into parent non-public declarations'
            soundness_note = 'Guarantees child package isolation; does NOT guarantee all child-parent patterns'
        elif section == '3.4.1':
            summary = 'Package-level variable initialisers evaluated at load time in declaration order'
            target = 'Determinism'
            mechanism = 'runtime_wrapper_check'
            artifact_location = 'companion/spark/safe_determinism_po.ads'
            soundness_note = 'Guarantees initialization order; does NOT guarantee initializer side-effect ordering'
        elif section == '3.4.2':
            if 'p44' in cid:
                summary = 'Withed package initialisers complete before dependent package initialisers'
                target = 'Determinism'
                mechanism = 'runtime_wrapper_check'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
            elif 'p45' in cid:
                summary = 'Initialisation order is topological sort of dependency graph; ties implementation-defined but deterministic'
                target = 'Determinism'
                mechanism = 'runtime_wrapper_check'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
            soundness_note = 'Guarantees init ordering; does NOT guarantee deterministic behavior for unrelated packages across builds'
        elif section == '3.4.3':
            summary = 'All package initialisation completes before any task begins executing'
            target = 'Race-freedom'
            artifact_location = 'companion/spark/safe_task_po.ads'
            mechanism = 'runtime_wrapper_check'
            soundness_note = 'Guarantees init-before-task sequencing; does NOT guarantee runtime enforces this'
            assumptions = ['Runtime system implements deferred task activation']
        elif section == '3.5.1':
            if 'p47' in cid:
                summary = 'Implementation provides dependency interface mechanism'
                mechanism = 'manual_review'
            elif 'p48' in cid:
                summary = 'Interface mechanism supports legality checking, ownership checking, incremental recompilation'
                mechanism = 'manual_review'
            soundness_note = 'Guarantees interface mechanism existence; does NOT guarantee mechanism correctness'
        elif section == '3.5.2':
            summary = 'Separate compilation of packages using source and dependency interface info'
            mechanism = 'manual_review'
            soundness_note = 'Guarantees separate compilation support; does NOT guarantee cross-unit consistency'
        else:
            summary = f'Package model rule: {section_title}'
            soundness_note = f'Guarantees {section_title} enforcement; does NOT guarantee complete coverage'
        return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 4 - Tasks and Channels
    # ============================================================
    if source_file == 'spec/04-tasks-and-channels.md':
        # Task-variable ownership and race freedom
        if 'ownership' in tags and section == '4.5':
            target = 'Race-freedom'
            artifact_location = 'companion/spark/safe_task_po.ads'
            if 'p45' in cid:
                summary = 'Each package-level variable accessed by at most one task'
                mechanism = 'flow_contract_check'
                soundness_note = 'Guarantees no shared mutable state; does NOT guarantee transitive access analysis is complete'
            elif 'p47' in cid:
                summary = 'Cross-package ownership checking via effect summaries'
                mechanism = 'flow_contract_check'
                soundness_note = 'Guarantees cross-package ownership verification; does NOT guarantee effect summary completeness'
                assumptions = ['Dependency interface effect summaries are sound']
            elif 'p49' in cid:
                summary = 'Reject subprogram accessing package variable if callable from multiple tasks'
                mechanism = 'flow_contract_check'
                soundness_note = 'Guarantees multi-task subprogram restriction; does NOT guarantee all call paths analyzed'
            elif 'p50' in cid:
                summary = 'Channel operations are not variable access for ownership purposes'
                mechanism = 'manual_review'
                soundness_note = 'Guarantees channel exemption; does NOT guarantee exemption is safe for all patterns'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Channel ownership for memory safety
        if 'ownership' in tags and section == '4.3':
            target = 'Memory-safety'
            artifact_location = 'companion/spark/safe_ownership_po.ads'
            if 'p27a' in cid:
                summary = 'Ownership transfer (move) on send for owning access types'
                mechanism = 'ghost_model_invariant'
                soundness_note = 'Guarantees move semantics on channel send; does NOT guarantee atomicity of move and enqueue'
            elif 'p28a' in cid:
                summary = 'Ownership transfer on receive; null-before-move rule applies'
                mechanism = 'ghost_model_invariant'
                soundness_note = 'Guarantees receiver ownership; does NOT guarantee null-state tracking across control flow'
            elif 'p29a' in cid:
                summary = 'Move occurs only on successful try_send for owning access types'
                mechanism = 'ghost_model_invariant'
                soundness_note = 'Guarantees conditional move correctness; does NOT guarantee atomic try-send implementation'
            elif 'p29b' in cid:
                summary = 'Implementation shall not null source until enqueue confirmed'
                mechanism = 'runtime_wrapper_check'
                soundness_note = 'Guarantees deferred nulling; does NOT guarantee implementation atomicity'
            elif 'p30' in cid:
                summary = 'try_receive with ownership transfer and null-before-move rule'
                mechanism = 'ghost_model_invariant'
                soundness_note = 'Guarantees conditional receive ownership; does NOT guarantee all try_receive paths tracked'
            elif 'p31a' in cid:
                summary = 'Channel ownership invariant: each designated object owned by exactly one entity'
                mechanism = 'ghost_model_invariant'
                soundness_note = 'Guarantees single-owner invariant; does NOT guarantee invariant holds during concurrent access windows'
                assumptions = ['Channel implementation correctly serializes access']
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Task declarations
        if section == '4.1':
            target = 'Race-freedom'
            artifact_location = 'companion/spark/safe_task_po.ads'
            mechanism = 'translation_validation'
            if 'p2' in cid:
                summary = 'Task declarations only at package top level'
            elif 'p3' in cid:
                summary = 'Each task declaration creates exactly one task; no task types/arrays'
            elif 'p4' in cid:
                summary = 'Task end identifier must match task name'
            elif 'p5' in cid:
                summary = 'Priority aspect must be in System.Any_Priority range'
            elif 'p6' in cid:
                summary = 'Task declarations shall not bear public keyword'
            elif 'p7' in cid:
                summary = 'Task declarations shall not be nested'
            elif 'p9' in cid:
                summary = 'Default priority is implementation-defined and documented'
                target = 'Conformance'
                mechanism = 'manual_review'
            elif 'p10' in cid:
                summary = 'Tasks begin execution after all package-level initialisation'
                mechanism = 'runtime_wrapper_check'
            elif 'p11' in cid:
                summary = 'Preemptive priority-based scheduling; equal priority order is impl-defined'
                target = 'Determinism'
                mechanism = 'runtime_wrapper_check'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
            soundness_note = 'Guarantees task declaration constraints; does NOT guarantee runtime task behavior'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Channel declarations
        if section == '4.2':
            target = 'Race-freedom'
            artifact_location = 'companion/spark/safe_task_po.ads'
            if 'p13' in cid:
                summary = 'Channel declarations only at package top level'
                mechanism = 'translation_validation'
            elif 'p14' in cid:
                summary = 'Channel element type must be definite'
                mechanism = 'translation_validation'
            elif 'p15' in cid:
                summary = 'Channel capacity must be positive integer'
                mechanism = 'translation_validation'
            elif 'p20' in cid:
                summary = 'Channel is FIFO: elements dequeued in enqueue order'
                mechanism = 'runtime_wrapper_check'
                target = 'Determinism'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
            elif 'p21' in cid and 'p21a' not in cid:
                summary = 'Channel ceiling priority at least max of accessing task priorities'
                mechanism = 'runtime_wrapper_check'
            elif 'p21a' in cid:
                summary = 'Cross-package channel ceiling priority computation via interface summaries'
                mechanism = 'flow_contract_check'
            soundness_note = 'Guarantees channel declaration constraints; does NOT guarantee runtime channel behavior'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Channel operations (non-ownership)
        if section == '4.3':
            if 'p23' in cid:
                summary = 'Send/try_send expression type matches channel element type'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p24' in cid:
                summary = 'Receive/try_receive variable type matches channel element type'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p25' in cid:
                summary = 'try_send/try_receive success variable must be Boolean'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p26' in cid:
                summary = 'Channel operations shall not appear at package level'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p27' in cid and 'p27a' not in cid:
                summary = 'send blocks if channel full; value evaluated before enqueue'
                target = 'Race-freedom'
                mechanism = 'runtime_wrapper_check'
            elif 'p28' in cid and 'p28a' not in cid:
                summary = 'receive blocks if channel empty; dequeues front element'
                target = 'Race-freedom'
                mechanism = 'runtime_wrapper_check'
            elif 'p29' in cid and 'p29a' not in cid and 'p29b' not in cid:
                summary = 'try_send: atomic non-blocking enqueue attempt'
                target = 'Race-freedom'
                mechanism = 'runtime_wrapper_check'
            elif 'p31' in cid and 'p31a' not in cid:
                summary = 'Channel operations atomic with respect to same-channel operations'
                target = 'Race-freedom'
                mechanism = 'runtime_wrapper_check'
                assumptions = ['Channel implementation provides mutual exclusion']
            artifact_location = 'companion/spark/safe_task_po.ads'
            soundness_note = 'Guarantees channel operation semantics; does NOT guarantee implementation correctness'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Select statement
        if section == '4.4':
            artifact_location = 'companion/spark/safe_task_po.ads'
            if 'p33' in cid:
                summary = 'Select must contain at least one channel arm'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p34' in cid:
                summary = 'At most one delay arm in select statement'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p35' in cid:
                summary = 'Select arms are receive-only (no send in select)'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p36' in cid:
                summary = 'Select channel arm subtype must match channel element type'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p37' in cid:
                summary = 'Select channel arm introduces scoped variable'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p38' in cid:
                summary = 'Delay arm expression must be Duration-compatible'
                target = 'Conformance'
                mechanism = 'translation_validation'
            elif 'p39' in cid:
                summary = 'Select tests arms in declaration order; first ready arm selected'
                target = 'Determinism'
                mechanism = 'runtime_wrapper_check'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
            elif 'p40' in cid:
                summary = 'Delay arm selected if delay expires before any channel ready'
                target = 'Determinism'
                mechanism = 'runtime_wrapper_check'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
            elif 'p41' in cid:
                summary = 'Simultaneous channels: first listed arm selected (deterministic)'
                target = 'Determinism'
                mechanism = 'runtime_wrapper_check'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
            elif 'p42' in cid:
                summary = 'Select blocks if no arm ready and no delay arm present'
                target = 'Race-freedom'
                mechanism = 'runtime_wrapper_check'
            soundness_note = 'Guarantees select statement semantics; does NOT guarantee deterministic scheduling interaction'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Non-termination
        if section == '4.6':
            target = 'Race-freedom'
            mechanism = 'translation_validation'
            artifact_location = 'companion/spark/safe_task_po.ads'
            if 'p53' in cid and 'p53b' not in cid and 'p53c' not in cid:
                summary = 'Task body outermost statement must be unconditional loop'
            elif 'p53b' in cid:
                summary = 'Reject return statement within task body'
            elif 'p53c' in cid:
                summary = 'Exit statement shall not target outermost loop of task'
            soundness_note = 'Guarantees non-termination syntactic constraints; does NOT guarantee semantic non-termination (e.g., internal abort)'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        # Task startup
        if section == '4.7':
            if 'p56' in cid:
                summary = 'All package initialisation completes before any task executes'
                target = 'Race-freedom'
                mechanism = 'runtime_wrapper_check'
                artifact_location = 'companion/spark/safe_task_po.ads'
                soundness_note = 'Guarantees initialization-before-tasks; does NOT guarantee runtime implementation'
                assumptions = ['Runtime system implements deferred task activation']
            elif 'p58' in cid:
                summary = 'Task activation order is implementation-defined'
                target = 'Determinism'
                mechanism = 'manual_review'
                artifact_location = 'companion/spark/safe_determinism_po.ads'
                soundness_note = 'Guarantees documented activation order; does NOT guarantee determinism across implementations'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 5 - Assurance
    # ============================================================
    if source_file == 'spec/05-assurance.md':
        if section == '5.1':
            summary = 'Every conforming program achieves Stone, Bronze, Silver without annotations'
            target = 'Conformance'
            mechanism = 'manual_review'
            artifact_location = 'companion/spark/safe_conformance.ads'
            soundness_note = 'Guarantees assurance level claim; does NOT guarantee claim correctness without proof'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.2.1':
            summary = 'Complete and correct flow information derivable without user annotations'
            target = 'Bronze-flow'
            mechanism = 'flow_contract_check'
            artifact_location = 'companion/spark/safe_bronze_po.ads'
            soundness_note = 'Guarantees flow derivability; does NOT guarantee derived flow is maximally precise'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.2.2':
            summary = 'Implementation determines Global (read/write sets) per subprogram'
            target = 'Bronze-flow'
            mechanism = 'flow_contract_check'
            artifact_location = 'companion/spark/safe_bronze_po.ads'
            soundness_note = 'Guarantees Global derivation; does NOT guarantee minimal over-approximation'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.2.3':
            summary = 'Implementation determines Depends (output-to-input) per subprogram'
            target = 'Bronze-flow'
            mechanism = 'flow_contract_check'
            artifact_location = 'companion/spark/safe_bronze_po.ads'
            soundness_note = 'Guarantees Depends derivation; does NOT guarantee minimal over-approximation'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.2.4':
            summary = 'Implementation determines Initializes (elaboration-initialized variables) per package'
            target = 'Bronze-flow'
            mechanism = 'flow_contract_check'
            artifact_location = 'companion/spark/safe_bronze_po.ads'
            soundness_note = 'Guarantees Initializes derivation; does NOT guarantee detection of conditional initialization'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.3.1':
            if 'p12a' in cid:
                summary = 'Silver scope excludes resource exhaustion (allocation failure, stack overflow)'
                target = 'Silver-AoRTE'
                mechanism = 'assumption_tracking'
                artifact_location = 'companion/spark/safe_silver_po.ads'
                soundness_note = 'Guarantees Silver scope definition; does NOT guarantee resource exhaustion handling'
                assumptions = ['Resource exhaustion behavior is defined (abort) but not statically preventable']
            else:
                summary = 'Every conforming program is free of runtime errors (Silver guarantee)'
                target = 'Silver-AoRTE'
                mechanism = 'gnatprove_proof_vc'
                artifact_location = 'companion/spark/safe_silver_po.ads'
                soundness_note = 'Guarantees AoRTE for runtime checks in scope; does NOT guarantee resource exhaustion freedom'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.3.2':
            target = 'Silver-AoRTE'
            mechanism = 'gnatprove_proof_vc'
            artifact_location = 'companion/spark/safe_silver_po.ads'
            if 'p15' in cid:
                summary = 'Reject integer types exceeding 64-bit signed range'
            elif 'p16' in cid:
                summary = 'Reject integer expressions with unprovable 64-bit intermediate bounds'
            soundness_note = 'Guarantees wide intermediate bounds; does NOT guarantee minimal over-rejection'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.3.6':
            target = 'Silver-AoRTE'
            mechanism = 'gnatprove_proof_vc'
            artifact_location = 'companion/spark/safe_silver_po.ads'
            if 'p25' in cid:
                summary = 'Range checks discharged via sound static range analysis'
            elif 'p26' in cid:
                summary = 'Reject programs with undischargeable narrowing points'
            soundness_note = 'Guarantees range check discharge; does NOT guarantee analysis precision'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.3.7':
            summary = 'Discriminant checks: variant access consistent with discriminant value'
            target = 'Silver-AoRTE'
            mechanism = 'gnatprove_proof_vc'
            artifact_location = 'companion/spark/safe_silver_po.ads'
            soundness_note = 'Guarantees variant access safety; does NOT guarantee all discriminant patterns handled'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.3.7a':
            summary = 'All floating-point types use IEEE 754 non-trapping arithmetic'
            target = 'Silver-AoRTE'
            mechanism = 'runtime_wrapper_check'
            artifact_location = 'companion/spark/safe_silver_po.ads'
            soundness_note = 'Guarantees non-trapping FP mode; does NOT guarantee hardware compliance'
            assumptions = ['Target hardware supports IEEE 754 non-trapping mode']
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.3.9':
            target = 'Silver-AoRTE'
            artifact_location = 'companion/spark/safe_silver_po.ads'
            if 'p30' in cid:
                summary = 'Hard rejection: undischargeable runtime check means program is rejected'
                mechanism = 'gnatprove_proof_vc'
            elif 'p31' in cid:
                summary = 'Silver failure is compilation error, not warning'
                mechanism = 'manual_review'
            soundness_note = 'Guarantees hard rejection policy; does NOT guarantee specific diagnostic quality'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.4.1':
            target = 'Race-freedom'
            artifact_location = 'companion/spark/safe_task_po.ads'
            if 'p32' in cid:
                summary = 'Channel-based tasking model guarantees data race freedom'
                mechanism = 'ghost_model_invariant'
                soundness_note = 'Guarantees race freedom claim; does NOT guarantee claim holds for implementation-internal state'
            elif 'p33' in cid:
                summary = 'Data race freedom verified via task-variable ownership analysis'
                mechanism = 'flow_contract_check'
                soundness_note = 'Guarantees ownership analysis enforcement; does NOT guarantee completeness for heap objects'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.4.2':
            summary = 'Ceiling priority rules prevent priority inversion'
            target = 'Race-freedom'
            mechanism = 'runtime_wrapper_check'
            artifact_location = 'companion/spark/safe_task_po.ads'
            soundness_note = 'Guarantees priority inversion prevention; does NOT guarantee correct ceiling computation'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '5.4.4':
            summary = 'Task body effect summaries reference only owned variables and channel ops'
            target = 'Race-freedom'
            mechanism = 'flow_contract_check'
            artifact_location = 'companion/spark/safe_task_po.ads'
            soundness_note = 'Guarantees effect summary correctness; does NOT guarantee completeness of effect analysis'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 6 - Conformance
    # ============================================================
    if source_file == 'spec/06-conformance.md':
        target = 'Conformance'
        artifact_location = 'companion/spark/safe_conformance.ads'

        if section == '6.1':
            if 'p1a' in cid:
                summary = 'Conforming implementation accepts every conforming program'
                mechanism = 'test_assertion'
            elif 'p1b' in cid:
                summary = 'Conforming implementation rejects non-conforming programs with diagnostic'
                mechanism = 'test_assertion'
            elif 'p1c' in cid:
                summary = 'Correct dynamic semantics of 8652:2023 as modified'
                mechanism = 'translation_validation'
            elif 'p1d' in cid:
                summary = 'Enforce D27 Rules 1-5 legality rules'
                target = 'Silver-AoRTE'
                mechanism = 'gnatprove_proof_vc'
                artifact_location = 'companion/spark/safe_silver_po.ads'
            elif 'p1e' in cid:
                summary = 'Enforce task-variable ownership as legality rule'
                target = 'Race-freedom'
                mechanism = 'flow_contract_check'
                artifact_location = 'companion/spark/safe_task_po.ads'
            elif 'p1f' in cid:
                summary = 'Derive flow analysis information without user annotations'
                target = 'Bronze-flow'
                mechanism = 'flow_contract_check'
                artifact_location = 'companion/spark/safe_bronze_po.ads'
            elif 'p1g' in cid:
                summary = 'Provide separate compilation and linking mechanism'
                mechanism = 'manual_review'
            elif 'p2' in cid:
                summary = 'Implementation may provide additional capabilities without altering semantics'
                mechanism = 'manual_review'
            soundness_note = 'Guarantees conformance requirement; does NOT guarantee implementation completeness'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.2':
            summary = 'Programs with undischargeable runtime checks are non-conforming and rejected'
            target = 'Silver-AoRTE'
            mechanism = 'gnatprove_proof_vc'
            artifact_location = 'companion/spark/safe_silver_po.ads'
            soundness_note = 'Guarantees rejection of unsafe programs; does NOT guarantee all unsafe programs are identified'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.4':
            target = 'Silver-AoRTE'
            artifact_location = 'companion/spark/safe_silver_po.ads'
            if 'p11' in cid and 'p11b' not in cid:
                summary = 'D27 static analyses shall be sound (no under-approximation)'
                mechanism = 'manual_review'
                soundness_note = 'Guarantees soundness policy; does NOT guarantee specific analysis algorithm is sound'
                assumptions = ['Static analysis implementation is verified or validated']
            elif 'p11b' in cid:
                summary = 'Undischargeable runtime check means program is rejected'
                mechanism = 'gnatprove_proof_vc'
                soundness_note = 'Guarantees rejection on failure; does NOT guarantee analysis tries all proof methods'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.5.1':
            summary = 'Support separate compilation using source and dependency info'
            mechanism = 'manual_review'
            soundness_note = 'Guarantees compilation model; does NOT verify implementation correctness'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.5.2':
            if 'p17' in cid:
                summary = 'Dependency interface information mechanism between compiled units'
                mechanism = 'manual_review'
            elif 'p18' in cid:
                summary = 'Interface includes declarations, signatures, effects, sizes, channel summaries'
                mechanism = 'manual_review'
            soundness_note = 'Guarantees interface requirements; does NOT verify implementation completeness'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.5.3':
            summary = 'Linking mechanism to combine compiled units into executable'
            mechanism = 'manual_review'
            soundness_note = 'Guarantees linking capability; does NOT verify link-time consistency checking'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.6':
            if 'p20a' in cid:
                summary = 'Diagnostics identify source file, line, column of violation'
            elif 'p20b' in cid:
                summary = 'Diagnostics identify which rule is violated'
            mechanism = 'test_assertion'
            soundness_note = 'Guarantees diagnostic content; does NOT guarantee diagnostic clarity'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.7':
            summary = 'Implementation documents all implementation-defined behaviors'
            mechanism = 'manual_review'
            soundness_note = 'Guarantees documentation requirement; does NOT guarantee documentation completeness'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

        if section == '6.8':
            summary = 'Runtime system supports tasks, channels, delay, deallocation, abort handler'
            mechanism = 'runtime_wrapper_check'
            soundness_note = 'Guarantees runtime capability; does NOT verify runtime correctness'
            return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 7 - Annex A (Retained Library)
    # ============================================================
    if source_file == 'spec/07-annex-a-retained-library.md':
        target = 'Library-safety'
        artifact_location = 'companion/spark/safe_library_po.ads'
        mechanism = 'translation_validation'
        if 'A.1' in section:
            summary = 'Exception declarations in Standard excluded; names remain reserved'
            soundness_note = 'Guarantees Standard package restrictions; does NOT guarantee all exception references detected'
        elif 'A.4.1' in section:
            summary = 'Ada.Strings modified: exception declarations excluded, enumerations retained'
            soundness_note = 'Guarantees library modification; does NOT guarantee all exception paths removed'
        soundness_note = soundness_note or 'Guarantees library restriction; does NOT guarantee all library interactions are safe'
        return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # ============================================================
    # Section 8 - Syntax Summary
    # ============================================================
    if source_file == 'spec/08-syntax-summary.md':
        target = 'Conformance'
        artifact_location = 'companion/spark/safe_conformance.ads'
        mechanism = 'translation_validation'
        if 'p1' in cid:
            summary = 'Reject reserved word used as identifier (authoritative list)'
            soundness_note = 'Guarantees reserved word enforcement; does NOT guarantee complete list synchronization'
        elif 'p2' in cid:
            summary = 'Constructs not in Safe grammar are excluded from Safe'
            soundness_note = 'Guarantees grammar is authoritative; does NOT guarantee grammar/spec consistency'
        return target, mechanism, summary, soundness_note, status, assumptions, artifact_location

    # Fallback
    if not summary:
        summary = f'{section_title} clause'
    if not soundness_note:
        soundness_note = f'Guarantees {section_title} requirement; does NOT guarantee implementation'
    return target, mechanism, summary, soundness_note, status, assumptions, artifact_location


def main():
    with open('clauses/clauses.yaml') as f:
        data = yaml.safe_load(f)

    po_entries = []
    for clause in data['clauses']:
        target, mechanism, summary, soundness_note, status, assumptions, artifact_location = classify_clause(clause)
        po_entries.append({
            'clause_id': clause['id'],
            'summary': summary,
            'target': target,
            'mechanism': mechanism,
            'soundness_note': soundness_note,
            'status': status,
            'assumptions': assumptions,
            'artifact_location': artifact_location,
        })

    output = {
        'meta': {
            'source_commit': '468cf72332724b04b7c193b4d2a3b02f1584125d',
            'generation_date': '2026-03-05',
            'source_clauses': 'clauses/clauses.yaml',
            'total_clauses': 205,
        },
        'po_entries': po_entries,
    }

    # Use explicit YAML dumping with proper quoting
    with open('clauses/po_map.yaml', 'w') as f:
        f.write('---\n')
        f.write('meta:\n')
        f.write(f'  source_commit: "{output["meta"]["source_commit"]}"\n')
        f.write(f'  generation_date: "{output["meta"]["generation_date"]}"\n')
        f.write(f'  source_clauses: "{output["meta"]["source_clauses"]}"\n')
        f.write(f'  total_clauses: {output["meta"]["total_clauses"]}\n\n')
        f.write('po_entries:\n')
        for entry in po_entries:
            f.write(f'  - clause_id: "{entry["clause_id"]}"\n')
            f.write(f'    summary: "{entry["summary"]}"\n')
            f.write(f'    target: "{entry["target"]}"\n')
            f.write(f'    mechanism: "{entry["mechanism"]}"\n')
            # Handle multiline soundness notes
            sn = entry["soundness_note"].replace('"', '\\"')
            f.write(f'    soundness_note: "{sn}"\n')
            f.write(f'    status: "{entry["status"]}"\n')
            if entry["assumptions"]:
                f.write('    assumptions:\n')
                for a in entry["assumptions"]:
                    f.write(f'      - "{a}"\n')
            else:
                f.write('    assumptions: []\n')
            f.write(f'    artifact_location: "{entry["artifact_location"]}"\n')

    print(f"Generated {len(po_entries)} PO entries")

    # Statistics
    from collections import Counter
    target_counts = Counter(e['target'] for e in po_entries)
    mechanism_counts = Counter(e['mechanism'] for e in po_entries)
    status_counts = Counter(e['status'] for e in po_entries)
    print("\nTarget counts:")
    for k, v in sorted(target_counts.items()):
        print(f"  {k}: {v}")
    print("\nMechanism counts:")
    for k, v in sorted(mechanism_counts.items()):
        print(f"  {k}: {v}")
    print("\nStatus counts:")
    for k, v in sorted(status_counts.items()):
        print(f"  {k}: {v}")

if __name__ == '__main__':
    main()
