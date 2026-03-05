# Proof Obligation Index

## Overview

- **Source commit**: `468cf72332724b04b7c193b4d2a3b02f1584125d`
- **Generation date**: 2026-03-02
- **Source clauses**: `clauses/clauses.yaml`
- **Total clauses**: 205
- **Total PO entries**: 205

---

## Summary Statistics

### By Target Category

| Target | Count | Percentage |
|--------|------:|------------|
| Bronze-flow | 5 | 2.4% |
| Silver-AoRTE | 30 | 14.6% |
| Memory-safety | 28 | 13.7% |
| Race-freedom | 23 | 11.2% |
| Determinism | 9 | 4.4% |
| Library-safety | 2 | 1.0% |
| Conformance | 108 | 52.7% |
| **Total** | **205** | **100.0%** |

### By Verification Mechanism

| Mechanism | Count | Percentage |
|-----------|------:|------------|
| flow_contract_check | 24 | 11.7% |
| gnatprove_proof_vc | 24 | 11.7% |
| ghost_model_invariant | 13 | 6.3% |
| runtime_wrapper_check | 26 | 12.7% |
| translation_validation | 88 | 42.9% |
| manual_review | 23 | 11.2% |
| test_assertion | 5 | 2.4% |
| assumption_tracking | 2 | 1.0% |
| **Total** | **205** | **100.0%** |

### By Status

| Status | Count | Percentage |
|--------|------:|------------|
| stubbed | 204 | 99.5% |
| deferred | 1 | 0.5% |
| **Total** | **205** | **100.0%** |

---

## PO Entries by Target Category

### Bronze-flow (5 entries)

| # | Clause ID (short) | Summary | Mechanism | Status |
|--:|-------------------|---------|-----------|--------|
| 1 | `spec/05-assurance.md#5.2.1.p3:ce5a8fe7` | Complete and correct flow information derivable without user annotations | flow_contract_check | stubbed |
| 2 | `spec/05-assurance.md#5.2.2.p5:a07e15ef` | Implementation determines Global (read/write sets) per subprogram | flow_contract_check | stubbed |
| 3 | `spec/05-assurance.md#5.2.3.p8:dfb93f2c` | Implementation determines Depends (output-to-input) per subprogram | flow_contract_check | stubbed |
| 4 | `spec/05-assurance.md#5.2.4.p11:b89bd341` | Implementation determines Initializes (elaboration-initialized variables) per pa | flow_contract_check | stubbed |
| 5 | `spec/06-conformance.md#6.1.p1f:2410637e` | Derive flow analysis information without user annotations | flow_contract_check | stubbed |

### Silver-AoRTE (30 entries)

| # | Clause ID (short) | Summary | Mechanism | Status |
|--:|-------------------|---------|-----------|--------|
| 1 | `spec/02-restrictions.md#2.3.8.p113:75fcd707` | No runtime accessibility check code shall be emitted | gnatprove_proof_vc | stubbed |
| 2 | `spec/02-restrictions.md#2.3.8.p109-end:5d18703e` | No runtime accessibility check is ever required | gnatprove_proof_vc | stubbed |
| 3 | `spec/02-restrictions.md#2.8.1.p126:812b54a8` | Integer arithmetic evaluated in mathematical integer type (wide intermediates) | gnatprove_proof_vc | stubbed |
| 4 | `spec/02-restrictions.md#2.8.1.p127:d5d93439` | Range checks only at narrowing points (assignment, parameter, return, conversion | gnatprove_proof_vc | stubbed |
| 5 | `spec/02-restrictions.md#2.8.1.p128:d2e83ca8` | Reject integer types exceeding 64-bit signed range | flow_contract_check | stubbed |
| 6 | `spec/02-restrictions.md#2.8.1.p129:9f3b1394` | Reject expressions with intermediate subexpressions exceeding 64-bit range | gnatprove_proof_vc | stubbed |
| 7 | `spec/02-restrictions.md#2.8.1.p130:2289e5b2` | Narrowing checks discharged via sound static range analysis | gnatprove_proof_vc | stubbed |
| 8 | `spec/02-restrictions.md#2.8.2.p131:30aba5f5` | Index expression provably within array bounds at compile time | gnatprove_proof_vc | stubbed |
| 9 | `spec/02-restrictions.md#2.8.2.p132:8613ecf4` | Reject unresolvable index bound relationships with diagnostic | gnatprove_proof_vc | stubbed |
| 10 | `spec/02-restrictions.md#2.8.3.p133:0610d951` | Right operand of /, mod, rem provably nonzero at compile time | gnatprove_proof_vc | stubbed |
| 11 | `spec/02-restrictions.md#2.8.3.p134:90a17a3b` | Reject division where nonzero cannot be established | gnatprove_proof_vc | stubbed |
| 12 | `spec/02-restrictions.md#2.8.4.p136:fa5e94b7` | Dereference requires not-null access subtype | gnatprove_proof_vc | stubbed |
| 13 | `spec/02-restrictions.md#2.8.5.p139:d50bc714` | All predefined floating-point types use IEEE 754 non-trapping arithmetic | runtime_wrapper_check | stubbed |
| 14 | `spec/02-restrictions.md#2.8.5.p139b:5e20032b` | Sound static range analysis for floating-point narrowing points | gnatprove_proof_vc | stubbed |
| 15 | `spec/02-restrictions.md#2.8.5.p139c:7fad4f7d` | Reject floating-point narrowing points that cannot be proven safe | gnatprove_proof_vc | stubbed |
| 16 | `spec/02-restrictions.md#2.8.5.p139d:56f1f36b` | NaN and infinity cannot survive narrowing points | gnatprove_proof_vc | stubbed |
| 17 | `spec/05-assurance.md#5.3.1.p12:99a94209` | Every conforming program is free of runtime errors (Silver guarantee) | gnatprove_proof_vc | stubbed |
| 18 | `spec/05-assurance.md#5.3.1.p12a:047a8410` | Silver scope excludes resource exhaustion (allocation failure, stack overflow) | assumption_tracking | stubbed |
| 19 | `spec/05-assurance.md#5.3.2.p15:1ab3314c` | Reject integer types exceeding 64-bit signed range | gnatprove_proof_vc | stubbed |
| 20 | `spec/05-assurance.md#5.3.2.p16:2e323902` | Reject integer expressions with unprovable 64-bit intermediate bounds | gnatprove_proof_vc | stubbed |
| 21 | `spec/05-assurance.md#5.3.6.p25:e8253bd7` | Range checks discharged via sound static range analysis | gnatprove_proof_vc | stubbed |
| 22 | `spec/05-assurance.md#5.3.6.p26:9ca2c786` | Reject programs with undischargeable narrowing points | gnatprove_proof_vc | stubbed |
| 23 | `spec/05-assurance.md#5.3.7.p27:e63b291b` | Discriminant checks: variant access consistent with discriminant value | gnatprove_proof_vc | stubbed |
| 24 | `spec/05-assurance.md#5.3.7a.p28a:5936dbea` | All floating-point types use IEEE 754 non-trapping arithmetic | runtime_wrapper_check | stubbed |
| 25 | `spec/05-assurance.md#5.3.9.p30:c7a2cbdb` | Hard rejection: undischargeable runtime check means program is rejected | gnatprove_proof_vc | stubbed |
| 26 | `spec/05-assurance.md#5.3.9.p31:f6ea7939` | Silver failure is compilation error, not warning | manual_review | stubbed |
| 27 | `spec/06-conformance.md#6.1.p1d:19219997` | Enforce D27 Rules 1-5 legality rules | gnatprove_proof_vc | stubbed |
| 28 | `spec/06-conformance.md#6.2.p4:3e238301` | Programs with undischargeable runtime checks are non-conforming and rejected | gnatprove_proof_vc | stubbed |
| 29 | `spec/06-conformance.md#6.4.p11:f35e2134` | D27 static analyses shall be sound (no under-approximation) | manual_review | stubbed |
| 30 | `spec/06-conformance.md#6.4.p11b:6e973d1d` | Undischargeable runtime check means program is rejected | gnatprove_proof_vc | stubbed |

### Memory-safety (28 entries)

| # | Clause ID (short) | Summary | Mechanism | Status |
|--:|-------------------|---------|-----------|--------|
| 1 | `spec/02-restrictions.md#2.1.12.p79:90727967` | Reject .Unchecked_Access | translation_validation | stubbed |
| 2 | `spec/02-restrictions.md#2.1.12.p80:15d3c6f7` | Reject Storage_Pool aspects and Ada.Unchecked_Deallocation | translation_validation | stubbed |
| 3 | `spec/02-restrictions.md#2.3.2.p96a:0eaf48aa` | Source object becomes null after move assignment | ghost_model_invariant | stubbed |
| 4 | `spec/02-restrictions.md#2.3.2.p96c:0b45de01` | Reject dereference of moved-from object unless reassigned or null-checked | flow_contract_check | stubbed |
| 5 | `spec/02-restrictions.md#2.3.2.p97a:8d0214d5` | Move target must be provably null at point of move | flow_contract_check | stubbed |
| 6 | `spec/02-restrictions.md#2.3.2.p97a-diag:dc259149` | Reject move into non-null target with ownership conflict diagnostic | flow_contract_check | stubbed |
| 7 | `spec/02-restrictions.md#2.3.3.p99b:47108b45` | Lender is frozen during active borrow (no read, write, or move) | flow_contract_check | stubbed |
| 8 | `spec/02-restrictions.md#2.3.3.p100a:ba849e66` | Anonymous access variables only assigned at declaration | ghost_model_invariant | stubbed |
| 9 | `spec/02-restrictions.md#2.3.4a.p102a:5bc5ab8b` | Borrower/observer scope contained within lender/observed scope | ghost_model_invariant | stubbed |
| 10 | `spec/02-restrictions.md#2.3.4a.p102a-a:ae729065` | Reject borrow/observe where borrower could outlive lender | ghost_model_invariant | stubbed |
| 11 | `spec/02-restrictions.md#2.3.4a.p102b:2ed757bd` | No access value shall designate a deallocated object | ghost_model_invariant | stubbed |
| 12 | `spec/02-restrictions.md#2.3.4a.p102b-diag:ddab22c8` | Reject programs with potentially dangling access values | ghost_model_invariant | stubbed |
| 13 | `spec/02-restrictions.md#2.3.5.p103a:520dc0d4` | Allocation failure causes program abort with diagnostic | runtime_wrapper_check | stubbed |
| 14 | `spec/02-restrictions.md#2.3.5.p104:d9f9b8d9` | Automatic deallocation of non-null pool-specific access at scope exit | runtime_wrapper_check | stubbed |
| 15 | `spec/02-restrictions.md#2.3.5.p104a:b70c1d15` | Named access-to-constant types auto-deallocated at scope exit | runtime_wrapper_check | stubbed |
| 16 | `spec/02-restrictions.md#2.3.5.p105:d4a9cdb4` | Multiple access objects deallocated in reverse declaration order | runtime_wrapper_check | stubbed |
| 17 | `spec/02-restrictions.md#2.3.5.p106:bae12394` | General access-to-variable types cannot be deallocated | ghost_model_invariant | stubbed |
| 18 | `spec/02-restrictions.md#2.3.7.p108:083e15a2` | Ownership checking is local to compilation unit | flow_contract_check | stubbed |
| 19 | `spec/02-restrictions.md#2.3.8.p111:42819528` | Reject .Access on local aliased variable where result could escape scope | flow_contract_check | stubbed |
| 20 | `spec/02-restrictions.md#2.3.8.p111a:a858bdfc` | Function shall not return .Access of local aliased variable | flow_contract_check | stubbed |
| 21 | `spec/02-restrictions.md#2.3.8.p111b:2921e9d2` | .Access of local shall not be assigned to enclosing scope variable | flow_contract_check | stubbed |
| 22 | `spec/02-restrictions.md#2.3.8.p111c:819cc398` | .Access of local aliased variable shall not be sent through channel | flow_contract_check | stubbed |
| 23 | `spec/04-tasks-and-channels.md#4.3.p27a:8ed3c1d4` | Ownership transfer (move) on send for owning access types | ghost_model_invariant | stubbed |
| 24 | `spec/04-tasks-and-channels.md#4.3.p28a:4cb19779` | Ownership transfer on receive; null-before-move rule applies | ghost_model_invariant | stubbed |
| 25 | `spec/04-tasks-and-channels.md#4.3.p29a:8d3f2225` | Move occurs only on successful try_send for owning access types | ghost_model_invariant | stubbed |
| 26 | `spec/04-tasks-and-channels.md#4.3.p29b:7121ccd7` | Implementation shall not null source until enqueue confirmed | runtime_wrapper_check | stubbed |
| 27 | `spec/04-tasks-and-channels.md#4.3.p30:62619161` | try_receive with ownership transfer and null-before-move rule | ghost_model_invariant | stubbed |
| 28 | `spec/04-tasks-and-channels.md#4.3.p31a:a621d08c` | Channel ownership invariant: each designated object owned by exactly one entity | ghost_model_invariant | stubbed |

### Race-freedom (23 entries)

| # | Clause ID (short) | Summary | Mechanism | Status |
|--:|-------------------|---------|-----------|--------|
| 1 | `spec/02-restrictions.md#2.1.8.p57:6fc7a14c` | Safe tasks shall not terminate | translation_validation | stubbed |
| 2 | `spec/03-single-file-packages.md#3.4.3.p46:b5f92bd9` | All package initialisation completes before any task begins executing | runtime_wrapper_check | stubbed |
| 3 | `spec/04-tasks-and-channels.md#4.1.p2:78f022f7` | Task declarations only at package top level | translation_validation | stubbed |
| 4 | `spec/04-tasks-and-channels.md#4.1.p3:542e0dee` | Each task declaration creates exactly one task; no task types/arrays | translation_validation | stubbed |
| 5 | `spec/04-tasks-and-channels.md#4.1.p5:4e4afebc` | Priority aspect must be in System.Any_Priority range | translation_validation | stubbed |
| 6 | `spec/04-tasks-and-channels.md#4.1.p10:92a67777` | Tasks begin execution after all package-level initialisation | runtime_wrapper_check | stubbed |
| 7 | `spec/04-tasks-and-channels.md#4.2.p21:c6a92460` | Channel ceiling priority at least max of accessing task priorities | runtime_wrapper_check | stubbed |
| 8 | `spec/04-tasks-and-channels.md#4.2.p21a:16ec46cb` | Cross-package channel ceiling priority computation via interface summaries | flow_contract_check | stubbed |
| 9 | `spec/04-tasks-and-channels.md#4.3.p27:ef0ce6bd` | send blocks if channel full; value evaluated before enqueue | runtime_wrapper_check | stubbed |
| 10 | `spec/04-tasks-and-channels.md#4.3.p28:ea6bd13c` | receive blocks if channel empty; dequeues front element | runtime_wrapper_check | stubbed |
| 11 | `spec/04-tasks-and-channels.md#4.3.p29:f792d704` | try_send: atomic non-blocking enqueue attempt | runtime_wrapper_check | stubbed |
| 12 | `spec/04-tasks-and-channels.md#4.3.p31:a7297e97` | Channel operations atomic with respect to same-channel operations | runtime_wrapper_check | stubbed |
| 13 | `spec/04-tasks-and-channels.md#4.4.p42:dce8ac38` | Select blocks if no arm ready and no delay arm present | runtime_wrapper_check | stubbed |
| 14 | `spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99` | Each package-level variable accessed by at most one task | flow_contract_check | stubbed |
| 15 | `spec/04-tasks-and-channels.md#4.5.p47:bc08fb3b` | Cross-package ownership checking via effect summaries | flow_contract_check | stubbed |
| 16 | `spec/04-tasks-and-channels.md#4.5.p49:d2001725` | Reject subprogram accessing package variable if callable from multiple tasks | flow_contract_check | stubbed |
| 17 | `spec/04-tasks-and-channels.md#4.6.p53:897d5577` | Task body outermost statement must be unconditional loop | translation_validation | stubbed |
| 18 | `spec/04-tasks-and-channels.md#4.7.p56:55e4230e` | All package initialisation completes before any task executes | runtime_wrapper_check | stubbed |
| 19 | `spec/05-assurance.md#5.4.1.p32:90d4f527` | Channel-based tasking model guarantees data race freedom | ghost_model_invariant | stubbed |
| 20 | `spec/05-assurance.md#5.4.1.p33:0fc25399` | Data race freedom verified via task-variable ownership analysis | flow_contract_check | stubbed |
| 21 | `spec/05-assurance.md#5.4.2.p34:198b1ddf` | Ceiling priority rules prevent priority inversion | runtime_wrapper_check | stubbed |
| 22 | `spec/05-assurance.md#5.4.4.p40:36087a2c` | Task body effect summaries reference only owned variables and channel ops | flow_contract_check | stubbed |
| 23 | `spec/06-conformance.md#6.1.p1e:d0e6c93b` | Enforce task-variable ownership as legality rule | flow_contract_check | stubbed |

### Determinism (9 entries)

| # | Clause ID (short) | Summary | Mechanism | Status |
|--:|-------------------|---------|-----------|--------|
| 1 | `spec/03-single-file-packages.md#3.4.1.p42:b88e8ad4` | Package-level variable initialisers evaluated at load time in declaration order | runtime_wrapper_check | stubbed |
| 2 | `spec/03-single-file-packages.md#3.4.2.p44:a655dde4` | Withed package initialisers complete before dependent package initialisers | runtime_wrapper_check | stubbed |
| 3 | `spec/03-single-file-packages.md#3.4.2.p45:80712e1a` | Initialisation order is topological sort of dependency graph; ties implementatio | runtime_wrapper_check | stubbed |
| 4 | `spec/04-tasks-and-channels.md#4.1.p11:2460c5cb` | Preemptive priority-based scheduling; equal priority order is impl-defined | runtime_wrapper_check | stubbed |
| 5 | `spec/04-tasks-and-channels.md#4.2.p20:8aa1a21e` | Channel is FIFO: elements dequeued in enqueue order | runtime_wrapper_check | stubbed |
| 6 | `spec/04-tasks-and-channels.md#4.4.p39:1012f4db` | Select tests arms in declaration order; first ready arm selected | runtime_wrapper_check | stubbed |
| 7 | `spec/04-tasks-and-channels.md#4.4.p40:4cfdeffe` | Delay arm selected if delay expires before any channel ready | runtime_wrapper_check | stubbed |
| 8 | `spec/04-tasks-and-channels.md#4.4.p41:cdf6a558` | Simultaneous channels: first listed arm selected (deterministic) | runtime_wrapper_check | stubbed |
| 9 | `spec/04-tasks-and-channels.md#4.7.p58:d10f9cd1` | Task activation order is implementation-defined | manual_review | stubbed |

### Library-safety (2 entries)

| # | Clause ID (short) | Summary | Mechanism | Status |
|--:|-------------------|---------|-----------|--------|
| 1 | `spec/07-annex-a-retained-library.md#A.1.p3:70deff00` | Exception declarations in Standard excluded; names remain reserved | translation_validation | stubbed |
| 2 | `spec/07-annex-a-retained-library.md#A.4.1.p19:891ffa81` | Ada.Strings modified: exception declarations excluded, enumerations retained | translation_validation | stubbed |

### Conformance (108 entries)

| # | Clause ID (short) | Summary | Mechanism | Status |
|--:|-------------------|---------|-----------|--------|
| 1 | `spec/00-front-matter.md#0.1.p1:40d0d4cf` | Safe is defined subtractively from Ada 2022 | manual_review | stubbed |
| 2 | `spec/00-front-matter.md#0.1.p2:9e5cd9ab` | Safe source files use .safe extension | test_assertion | stubbed |
| 3 | `spec/00-front-matter.md#0.5.p21:5eb1de72` | Specification voice conventions (shall/may/should) | manual_review | stubbed |
| 4 | `spec/00-front-matter.md#0.8.p27:5000a79a` | All TBD items shall be resolved before baselining | assumption_tracking | deferred |
| 5 | `spec/01-base-definition.md#1.p1:e7bf1014` | Safe is Ada 2022 restricted by Section 2 and modified by Sections 3-4 | translation_validation | stubbed |
| 6 | `spec/01-base-definition.md#1.p2:b610468e` | All Ada 2022 rules apply except where explicitly excluded or modified | translation_validation | stubbed |
| 7 | `spec/01-base-definition.md#1.p3:a2ff4ad4` | Unmentioned constructs retained with Ada 2022 semantics plus notation changes | translation_validation | stubbed |
| 8 | `spec/01-base-definition.md#1.p6:b83ece40` | Unaddressed features retained with standard semantics | translation_validation | stubbed |
| 9 | `spec/02-restrictions.md#2.1.1.p2:75c5cfea` | Reject reserved word used as identifier | translation_validation | stubbed |
| 10 | `spec/02-restrictions.md#2.1.1.p3:f8550668` | Additional reserved words (public, channel, send, receive, etc.) | translation_validation | stubbed |
| 11 | `spec/02-restrictions.md#2.1.1.p4:b8e73758` | Reject tick notation for attributes/qualified expressions | translation_validation | stubbed |
| 12 | `spec/02-restrictions.md#2.1.2.p5:c8832ac8` | Reject Static_Predicate and Dynamic_Predicate aspects | translation_validation | stubbed |
| 13 | `spec/02-restrictions.md#2.1.2.p7:2de62408` | Reject tagged types, type extensions, abstract types, interfaces | translation_validation | stubbed |
| 14 | `spec/02-restrictions.md#2.1.2.p9:faae18b9` | Reject access-to-subprogram type declarations | translation_validation | stubbed |
| 15 | `spec/02-restrictions.md#2.1.2.p11:3fd55933` | Reject access discriminants | translation_validation | stubbed |
| 16 | `spec/02-restrictions.md#2.1.2.p12:8da68138` | Reject derivation from Controlled/Limited_Controlled | translation_validation | stubbed |
| 17 | `spec/02-restrictions.md#2.1.3.p14:4ab42f23` | Reject Implicit_Dereference aspect (user-defined references) | translation_validation | stubbed |
| 18 | `spec/02-restrictions.md#2.1.3.p15:9092af85` | Reject Constant_Indexing/Variable_Indexing (user-defined indexing) | translation_validation | stubbed |
| 19 | `spec/02-restrictions.md#2.1.3.p16:6436f829` | Reject user-defined literal aspects | translation_validation | stubbed |
| 20 | `spec/02-restrictions.md#2.1.3.p17:be123e5f` | Reject extension aggregates | translation_validation | stubbed |
| 21 | `spec/02-restrictions.md#2.1.3.p19:29c43768` | Reject container aggregates | translation_validation | stubbed |
| 22 | `spec/02-restrictions.md#2.1.3.p22:58a7c04c` | Reject quantified expressions (for all, for some) | translation_validation | stubbed |
| 23 | `spec/02-restrictions.md#2.1.3.p23:e51d510c` | Reject reduction expressions | translation_validation | stubbed |
| 24 | `spec/02-restrictions.md#2.1.3.p25:f55ddbee` | Reject qualified expressions using tick notation | translation_validation | stubbed |
| 25 | `spec/02-restrictions.md#2.1.4.p29:f27b01a7` | Reject Default_Iterator/Iterator_Element aspects | translation_validation | stubbed |
| 26 | `spec/02-restrictions.md#2.1.4.p31:3aff42cb` | Reject procedural iterators | translation_validation | stubbed |
| 27 | `spec/02-restrictions.md#2.1.4.p32:d090f2f1` | Reject parallel block statements | translation_validation | stubbed |
| 28 | `spec/02-restrictions.md#2.1.5.p34:70346a23` | Reject Pre, Post, Pre.Class, Post.Class aspects | translation_validation | stubbed |
| 29 | `spec/02-restrictions.md#2.1.5.p35:9db565e8` | Reject user-authored Global/Global.Class aspects | translation_validation | stubbed |
| 30 | `spec/02-restrictions.md#2.1.5.p36:ba7835b4` | Each subprogram identifier denotes exactly one subprogram | flow_contract_check | stubbed |
| 31 | `spec/02-restrictions.md#2.1.5.p40:cc41753d` | Reject user-defined operator functions | translation_validation | stubbed |
| 32 | `spec/02-restrictions.md#2.1.6.p44:a5524a86` | Reject standalone package body compilation unit | translation_validation | stubbed |
| 33 | `spec/02-restrictions.md#2.1.7.p51:3bd0226a` | Reject use Package_Name clauses | translation_validation | stubbed |
| 34 | `spec/02-restrictions.md#2.1.8.p58:9bf4999c` | Reject user-declared protected types/objects | translation_validation | stubbed |
| 35 | `spec/02-restrictions.md#2.1.8.p59:95c073d3` | Reject entry declarations, accept statements, entry calls, requeue | translation_validation | stubbed |
| 36 | `spec/02-restrictions.md#2.1.8.p60:75dc85e6` | Reject delay until statement | translation_validation | stubbed |
| 37 | `spec/02-restrictions.md#2.1.8.p61:f91fb172` | Reject Ada select model (selective accept, timed/conditional entry call, async s | translation_validation | stubbed |
| 38 | `spec/02-restrictions.md#2.1.8.p62:9053b623` | Reject abort statement | translation_validation | stubbed |
| 39 | `spec/02-restrictions.md#2.1.9.p65:a6f8ab1c` | Library units shall be packages; library-level subprograms prohibited | translation_validation | stubbed |
| 40 | `spec/02-restrictions.md#2.1.10.p67:50d815f0` | Reject exceptions, handlers, raise, pragma Suppress/Unsuppress | translation_validation | stubbed |
| 41 | `spec/02-restrictions.md#2.1.11.p69:4ced1c77` | Reject generic declarations, bodies, and instantiations | translation_validation | stubbed |
| 42 | `spec/02-restrictions.md#2.1.12.p77:8b158e82` | Reject machine code insertions | translation_validation | stubbed |
| 43 | `spec/02-restrictions.md#2.1.12.p78:803e4add` | Reject Ada.Unchecked_Conversion | translation_validation | stubbed |
| 44 | `spec/02-restrictions.md#2.1.12.p82:453192f0` | Reject stream attribute references and stream type declarations | translation_validation | stubbed |
| 45 | `spec/02-restrictions.md#2.1.13.p84:84829058` | Reject pragma Import/Export/Convention and Annex B | translation_validation | stubbed |
| 46 | `spec/02-restrictions.md#2.1.13.p91:4a433f78` | Reject Annex J obsolescent features | translation_validation | stubbed |
| 47 | `spec/02-restrictions.md#2.2.p93:301d16b8` | Reject 12 SPARK verification-only aspects in Safe source | translation_validation | stubbed |
| 48 | `spec/02-restrictions.md#2.7.p124:ef993f07` | Reject 12 contract-related aspects | translation_validation | stubbed |
| 49 | `spec/02-restrictions.md#2.9.p140:7eeb1bb6` | Declarations and statements may interleave freely after begin | manual_review | stubbed |
| 50 | `spec/02-restrictions.md#2.10.p141:9e5dc3fe` | Reject duplicate subprogram identifiers in declarative region (no overloading) | flow_contract_check | stubbed |
| 51 | `spec/03-single-file-packages.md#3.p0:dcd1bc13` | Public interface made available for dependent compilation units | manual_review | stubbed |
| 52 | `spec/03-single-file-packages.md#3.2.1.p8:cb47c342` | End identifier must match package identifier | translation_validation | stubbed |
| 53 | `spec/03-single-file-packages.md#3.2.2.p9:d7d76101` | Declaration-before-use for all names | translation_validation | stubbed |
| 54 | `spec/03-single-file-packages.md#3.2.3.p12:b76eb7bf` | Forward declaration body shall appear in same region and conform | translation_validation | stubbed |
| 55 | `spec/03-single-file-packages.md#3.2.3.p13:8bf74e20` | Reject forward declaration with no completing body | translation_validation | stubbed |
| 56 | `spec/03-single-file-packages.md#3.2.3.p14:c205a40a` | Public keyword on forward declaration, not on completing body | translation_validation | stubbed |
| 57 | `spec/03-single-file-packages.md#3.2.4.p15:e090edc2` | No executable statements at package level | translation_validation | stubbed |
| 58 | `spec/03-single-file-packages.md#3.2.5.p19:05cb629b` | Reject public annotation on invalid declaration kinds | translation_validation | stubbed |
| 59 | `spec/03-single-file-packages.md#3.2.5.p20:d2c1d841` | Non-public declarations are private to declaring package | translation_validation | stubbed |
| 60 | `spec/03-single-file-packages.md#3.2.6.p23:26dc2217` | Reject external field access on opaque types | translation_validation | stubbed |
| 61 | `spec/03-single-file-packages.md#3.2.6.p24:12e57227` | Implementation exports size/alignment for opaque types | manual_review | stubbed |
| 62 | `spec/03-single-file-packages.md#3.2.10.p32:be83c6b5` | Library units must be packages; reject library-level subprograms | translation_validation | stubbed |
| 63 | `spec/03-single-file-packages.md#3.3.1.p33:b08ead48` | Implementation provides 9 categories of dependency interface information | manual_review | stubbed |
| 64 | `spec/03-single-file-packages.md#3.3.1.p34:2a0b2728` | Dependency interface mechanism is implementation-defined | manual_review | stubbed |
| 65 | `spec/03-single-file-packages.md#3.3.1.p35:0bbb4bb7` | Reject program when dependency interface info unavailable | translation_validation | stubbed |
| 66 | `spec/03-single-file-packages.md#3.3.4.p40:cdfbcb6b` | Child packages have no additional visibility into parent non-public declarations | translation_validation | stubbed |
| 67 | `spec/03-single-file-packages.md#3.5.1.p47:b7e93197` | Implementation provides dependency interface mechanism | manual_review | stubbed |
| 68 | `spec/03-single-file-packages.md#3.5.1.p48:616dd05d` | Interface mechanism supports legality checking, ownership checking, incremental  | manual_review | stubbed |
| 69 | `spec/03-single-file-packages.md#3.5.2.p49:02b25de0` | Separate compilation of packages using source and dependency interface info | manual_review | stubbed |
| 70 | `spec/04-tasks-and-channels.md#4.1.p9:b4640bda` | Default priority is implementation-defined and documented | manual_review | stubbed |
| 71 | `spec/04-tasks-and-channels.md#4.3.p23:197d9a49` | Send/try_send expression type matches channel element type | translation_validation | stubbed |
| 72 | `spec/04-tasks-and-channels.md#4.3.p24:9e47ed4c` | Receive/try_receive variable type matches channel element type | translation_validation | stubbed |
| 73 | `spec/04-tasks-and-channels.md#4.3.p25:961abe5a` | try_send/try_receive success variable must be Boolean | translation_validation | stubbed |
| 74 | `spec/04-tasks-and-channels.md#4.3.p26:3a9449c1` | Channel operations shall not appear at package level | translation_validation | stubbed |
| 75 | `spec/04-tasks-and-channels.md#4.4.p33:7a94ab51` | Select must contain at least one channel arm | translation_validation | stubbed |
| 76 | `spec/04-tasks-and-channels.md#4.4.p34:f0f83b83` | At most one delay arm in select statement | translation_validation | stubbed |
| 77 | `spec/04-tasks-and-channels.md#4.4.p35:2ad6e64f` | Select arms are receive-only (no send in select) | translation_validation | stubbed |
| 78 | `spec/04-tasks-and-channels.md#4.4.p36:0bffbd47` | Select channel arm subtype must match channel element type | translation_validation | stubbed |
| 79 | `spec/04-tasks-and-channels.md#4.4.p37:6ced8129` | Select channel arm introduces scoped variable | translation_validation | stubbed |
| 80 | `spec/04-tasks-and-channels.md#4.4.p38:35ed84d9` | Delay arm expression must be Duration-compatible | translation_validation | stubbed |
| 81 | `spec/04-tasks-and-channels.md#4.5.p50:2882310a` | Task-Variable Ownership clause | manual_review | stubbed |
| 82 | `spec/05-assurance.md#5.1.p2:14a5a600` | Every conforming program achieves Stone, Bronze, Silver without annotations | manual_review | stubbed |
| 83 | `spec/06-conformance.md#6.1.p1a:ba2c1d31` | Conforming implementation accepts every conforming program | test_assertion | stubbed |
| 84 | `spec/06-conformance.md#6.1.p1b:3890c549` | Conforming implementation rejects non-conforming programs with diagnostic | test_assertion | stubbed |
| 85 | `spec/06-conformance.md#6.1.p1c:1f8fe478` | Correct dynamic semantics of 8652:2023 as modified | translation_validation | stubbed |
| 86 | `spec/06-conformance.md#6.1.p1g:80745a1e` | Provide separate compilation and linking mechanism | manual_review | stubbed |
| 87 | `spec/06-conformance.md#6.1.p2:983b5f84` | Implementation may provide additional capabilities without altering semantics | manual_review | stubbed |
| 88 | `spec/06-conformance.md#6.5.1.p16:b89b7765` | Support separate compilation using source and dependency info | manual_review | stubbed |
| 89 | `spec/06-conformance.md#6.5.2.p17:70300f7a` | Dependency interface information mechanism between compiled units | manual_review | stubbed |
| 90 | `spec/06-conformance.md#6.5.2.p18:ae5640ac` | Interface includes declarations, signatures, effects, sizes, channel summaries | manual_review | stubbed |
| 91 | `spec/06-conformance.md#6.5.3.p19:5d4dfb69` | Linking mechanism to combine compiled units into executable | manual_review | stubbed |
| 92 | `spec/06-conformance.md#6.6.p20a:d74e6ca7` | Diagnostics identify source file, line, column of violation | test_assertion | stubbed |
| 93 | `spec/06-conformance.md#6.6.p20b:74ad00a2` | Diagnostics identify which rule is violated | test_assertion | stubbed |
| 94 | `spec/06-conformance.md#6.7.p22:03afd0a4` | Implementation documents all implementation-defined behaviors | manual_review | stubbed |
| 95 | `spec/06-conformance.md#6.8.p23:3419a843` | Runtime system supports tasks, channels, delay, deallocation, abort handler | runtime_wrapper_check | stubbed |
| 96 | `spec/08-syntax-summary.md#8.15.p1:75c5cfea` | Reject reserved word used as identifier (authoritative list) | translation_validation | stubbed |
| 97 | `spec/08-syntax-summary.md#8.16.p2:ccb1533b` | Constructs not in Safe grammar are excluded from Safe | translation_validation | stubbed |
| 98 | `spec/02-restrictions.md#2.1.5.p38:872f4ec6` | Return statement shall not appear within task body | translation_validation | stubbed |
| 99 | `spec/02-restrictions.md#2.1.9.p66:3d98f9e9` | Reject circular with dependencies | translation_validation | stubbed |
| 100 | `spec/03-single-file-packages.md#3.2.9.p31:c2a3dc04` | Reject circular with dependency cycles | translation_validation | stubbed |
| 101 | `spec/04-tasks-and-channels.md#4.1.p4:016e5737` | Task end identifier must match task name | translation_validation | stubbed |
| 102 | `spec/04-tasks-and-channels.md#4.1.p6:be85291b` | Task declarations shall not bear public keyword | translation_validation | stubbed |
| 103 | `spec/04-tasks-and-channels.md#4.1.p7:393c53c2` | Task declarations shall not be nested | translation_validation | stubbed |
| 104 | `spec/04-tasks-and-channels.md#4.2.p13:4f888b03` | Channel declarations only at package top level | translation_validation | stubbed |
| 105 | `spec/04-tasks-and-channels.md#4.2.p14:a35bd0fa` | Channel element type must be definite | translation_validation | stubbed |
| 106 | `spec/04-tasks-and-channels.md#4.2.p15:b5b29b0e` | Channel capacity must be positive integer | translation_validation | stubbed |
| 107 | `spec/04-tasks-and-channels.md#4.6.p53b:19b7c4ae` | Reject return statement within task body | translation_validation | stubbed |
| 108 | `spec/04-tasks-and-channels.md#4.6.p53c:77a5f52c` | Exit statement shall not target outermost loop of task | translation_validation | stubbed |

---

## D-Rule Cross-Reference

This table maps specification design decisions (D-rules) to their corresponding PO entries.

### D1 (4 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/01-base-definition.md#1.p1:e7bf1014` | Safe is Ada 2022 restricted by Section 2 and modified by Sections 3-4 | Conformance |
| `spec/01-base-definition.md#1.p2:b610468e` | All Ada 2022 rules apply except where explicitly excluded or modified | Conformance |
| `spec/01-base-definition.md#1.p3:a2ff4ad4` | Unmentioned constructs retained with Ada 2022 semantics plus notation  | Conformance |
| `spec/01-base-definition.md#1.p6:b83ece40` | Unaddressed features retained with standard semantics | Conformance |

### D6 (14 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.6.p44:a5524a86` | Reject standalone package body compilation unit | Conformance |
| `spec/02-restrictions.md#2.1.9.p65:a6f8ab1c` | Library units shall be packages; library-level subprograms prohibited | Conformance |
| `spec/03-single-file-packages.md#3.p0:dcd1bc13` | Public interface made available for dependent compilation units | Conformance |
| `spec/03-single-file-packages.md#3.2.1.p8:cb47c342` | End identifier must match package identifier | Conformance |
| `spec/03-single-file-packages.md#3.2.2.p9:d7d76101` | Declaration-before-use for all names | Conformance |
| `spec/03-single-file-packages.md#3.2.4.p15:e090edc2` | No executable statements at package level | Conformance |
| `spec/03-single-file-packages.md#3.2.10.p32:be83c6b5` | Library units must be packages; reject library-level subprograms | Conformance |
| `spec/03-single-file-packages.md#3.3.1.p33:b08ead48` | Implementation provides 9 categories of dependency interface informati | Conformance |
| `spec/03-single-file-packages.md#3.3.1.p34:2a0b2728` | Dependency interface mechanism is implementation-defined | Conformance |
| `spec/03-single-file-packages.md#3.3.1.p35:0bbb4bb7` | Reject program when dependency interface info unavailable | Conformance |
| `spec/03-single-file-packages.md#3.3.4.p40:cdfbcb6b` | Child packages have no additional visibility into parent non-public de | Conformance |
| `spec/03-single-file-packages.md#3.5.1.p47:b7e93197` | Implementation provides dependency interface mechanism | Conformance |
| `spec/03-single-file-packages.md#3.5.1.p48:616dd05d` | Interface mechanism supports legality checking, ownership checking, in | Conformance |
| `spec/03-single-file-packages.md#3.5.2.p49:02b25de0` | Separate compilation of packages using source and dependency interface | Conformance |

### D7 (3 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.9.p66:3d98f9e9` | Reject circular with dependencies | Conformance |
| `spec/03-single-file-packages.md#3.2.4.p15:e090edc2` | No executable statements at package level | Conformance |
| `spec/03-single-file-packages.md#3.2.9.p31:c2a3dc04` | Reject circular with dependency cycles | Conformance |

### D8 (3 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/03-single-file-packages.md#3.2.3.p14:c205a40a` | Public keyword on forward declaration, not on completing body | Conformance |
| `spec/03-single-file-packages.md#3.2.5.p19:05cb629b` | Reject public annotation on invalid declaration kinds | Conformance |
| `spec/03-single-file-packages.md#3.2.5.p20:d2c1d841` | Non-public declarations are private to declaring package | Conformance |

### D9 (2 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/03-single-file-packages.md#3.2.6.p23:26dc2217` | Reject external field access on opaque types | Conformance |
| `spec/03-single-file-packages.md#3.2.6.p24:12e57227` | Implementation exports size/alignment for opaque types | Conformance |

### D11 (1 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.9.p140:7eeb1bb6` | Declarations and statements may interleave freely after begin | Conformance |

### D12 (3 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.5.p36:ba7835b4` | Each subprogram identifier denotes exactly one subprogram | Conformance |
| `spec/02-restrictions.md#2.1.5.p40:cc41753d` | Reject user-defined operator functions | Conformance |
| `spec/02-restrictions.md#2.10.p141:9e5dc3fe` | Reject duplicate subprogram identifiers in declarative region (no over | Conformance |

### D13 (1 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.7.p51:3bd0226a` | Reject use Package_Name clauses | Conformance |

### D14 (2 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.10.p67:50d815f0` | Reject exceptions, handlers, raise, pragma Suppress/Unsuppress | Conformance |
| `spec/07-annex-a-retained-library.md#A.1.p3:70deff00` | Exception declarations in Standard excluded; names remain reserved | Library-safety |

### D16 (1 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.11.p69:4ced1c77` | Reject generic declarations, bodies, and instantiations | Conformance |

### D17 (11 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.3.2.p96a:0eaf48aa` | Source object becomes null after move assignment | Memory-safety |
| `spec/02-restrictions.md#2.3.2.p96c:0b45de01` | Reject dereference of moved-from object unless reassigned or null-chec | Memory-safety |
| `spec/02-restrictions.md#2.3.2.p97a:8d0214d5` | Move target must be provably null at point of move | Memory-safety |
| `spec/02-restrictions.md#2.3.2.p97a-diag:dc259149` | Reject move into non-null target with ownership conflict diagnostic | Memory-safety |
| `spec/02-restrictions.md#2.3.3.p99b:47108b45` | Lender is frozen during active borrow (no read, write, or move) | Memory-safety |
| `spec/02-restrictions.md#2.3.3.p100a:ba849e66` | Anonymous access variables only assigned at declaration | Memory-safety |
| `spec/02-restrictions.md#2.3.4a.p102a:5bc5ab8b` | Borrower/observer scope contained within lender/observed scope | Memory-safety |
| `spec/02-restrictions.md#2.3.4a.p102a-a:ae729065` | Reject borrow/observe where borrower could outlive lender | Memory-safety |
| `spec/02-restrictions.md#2.3.4a.p102b:2ed757bd` | No access value shall designate a deallocated object | Memory-safety |
| `spec/02-restrictions.md#2.3.4a.p102b-diag:ddab22c8` | Reject programs with potentially dangling access values | Memory-safety |
| `spec/02-restrictions.md#2.3.5.p104:d9f9b8d9` | Automatic deallocation of non-null pool-specific access at scope exit | Memory-safety |

### D18 (2 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.2.p7:2de62408` | Reject tagged types, type extensions, abstract types, interfaces | Conformance |
| `spec/02-restrictions.md#2.1.2.p9:faae18b9` | Reject access-to-subprogram type declarations | Conformance |

### D19 (3 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.3.p22:58a7c04c` | Reject quantified expressions (for all, for some) | Conformance |
| `spec/02-restrictions.md#2.1.5.p34:70346a23` | Reject Pre, Post, Pre.Class, Post.Class aspects | Conformance |
| `spec/02-restrictions.md#2.7.p124:ef993f07` | Reject 12 contract-related aspects | Conformance |

### D20 (2 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.1.p4:b8e73758` | Reject tick notation for attributes/qualified expressions | Conformance |
| `spec/02-restrictions.md#2.1.3.p25:f55ddbee` | Reject qualified expressions using tick notation | Conformance |

### D21 (1 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.3.p25:f55ddbee` | Reject qualified expressions using tick notation | Conformance |

### D22 (2 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.5.p35:9db565e8` | Reject user-authored Global/Global.Class aspects | Conformance |
| `spec/02-restrictions.md#2.2.p93:301d16b8` | Reject 12 SPARK verification-only aspects in Safe source | Conformance |

### D24 (2 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.12.p77:8b158e82` | Reject machine code insertions | Conformance |
| `spec/02-restrictions.md#2.1.13.p84:84829058` | Reject pragma Import/Export/Convention and Annex B | Conformance |

### D26 (6 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/05-assurance.md#5.1.p2:14a5a600` | Every conforming program achieves Stone, Bronze, Silver without annota | Conformance |
| `spec/05-assurance.md#5.2.1.p3:ce5a8fe7` | Complete and correct flow information derivable without user annotatio | Bronze-flow |
| `spec/05-assurance.md#5.2.2.p5:a07e15ef` | Implementation determines Global (read/write sets) per subprogram | Bronze-flow |
| `spec/05-assurance.md#5.2.3.p8:dfb93f2c` | Implementation determines Depends (output-to-input) per subprogram | Bronze-flow |
| `spec/05-assurance.md#5.2.4.p11:b89bd341` | Implementation determines Initializes (elaboration-initialized variabl | Bronze-flow |
| `spec/06-conformance.md#6.1.p1f:2410637e` | Derive flow analysis information without user annotations | Bronze-flow |

### D27 (23 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.8.1.p126:812b54a8` | Integer arithmetic evaluated in mathematical integer type (wide interm | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.1.p127:d5d93439` | Range checks only at narrowing points (assignment, parameter, return,  | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.1.p128:d2e83ca8` | Reject integer types exceeding 64-bit signed range | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.1.p129:9f3b1394` | Reject expressions with intermediate subexpressions exceeding 64-bit r | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.1.p130:2289e5b2` | Narrowing checks discharged via sound static range analysis | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.2.p131:30aba5f5` | Index expression provably within array bounds at compile time | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.2.p132:8613ecf4` | Reject unresolvable index bound relationships with diagnostic | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.3.p133:0610d951` | Right operand of /, mod, rem provably nonzero at compile time | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.3.p134:90a17a3b` | Reject division where nonzero cannot be established | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.4.p136:fa5e94b7` | Dereference requires not-null access subtype | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.5.p139:d50bc714` | All predefined floating-point types use IEEE 754 non-trapping arithmet | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.5.p139b:5e20032b` | Sound static range analysis for floating-point narrowing points | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.5.p139c:7fad4f7d` | Reject floating-point narrowing points that cannot be proven safe | Silver-AoRTE |
| `spec/02-restrictions.md#2.8.5.p139d:56f1f36b` | NaN and infinity cannot survive narrowing points | Silver-AoRTE |
| `spec/05-assurance.md#5.3.1.p12:99a94209` | Every conforming program is free of runtime errors (Silver guarantee) | Silver-AoRTE |
| `spec/05-assurance.md#5.3.2.p15:1ab3314c` | Reject integer types exceeding 64-bit signed range | Silver-AoRTE |
| `spec/05-assurance.md#5.3.2.p16:2e323902` | Reject integer expressions with unprovable 64-bit intermediate bounds | Silver-AoRTE |
| `spec/05-assurance.md#5.3.6.p25:e8253bd7` | Range checks discharged via sound static range analysis | Silver-AoRTE |
| `spec/05-assurance.md#5.3.6.p26:9ca2c786` | Reject programs with undischargeable narrowing points | Silver-AoRTE |
| `spec/05-assurance.md#5.3.7a.p28a:5936dbea` | All floating-point types use IEEE 754 non-trapping arithmetic | Silver-AoRTE |
| `spec/06-conformance.md#6.1.p1d:19219997` | Enforce D27 Rules 1-5 legality rules | Silver-AoRTE |
| `spec/06-conformance.md#6.4.p11:f35e2134` | D27 static analyses shall be sound (no under-approximation) | Silver-AoRTE |
| `spec/06-conformance.md#6.4.p11b:6e973d1d` | Undischargeable runtime check means program is rejected | Silver-AoRTE |

### D28 (60 POs)

| Clause ID (short) | Summary | Target |
|-------------------|---------|--------|
| `spec/02-restrictions.md#2.1.4.p32:d090f2f1` | Reject parallel block statements | Conformance |
| `spec/02-restrictions.md#2.1.5.p38:872f4ec6` | Return statement shall not appear within task body | Conformance |
| `spec/02-restrictions.md#2.1.8.p57:6fc7a14c` | Safe tasks shall not terminate | Race-freedom |
| `spec/02-restrictions.md#2.1.8.p58:9bf4999c` | Reject user-declared protected types/objects | Conformance |
| `spec/02-restrictions.md#2.1.8.p59:95c073d3` | Reject entry declarations, accept statements, entry calls, requeue | Conformance |
| `spec/02-restrictions.md#2.1.8.p61:f91fb172` | Reject Ada select model (selective accept, timed/conditional entry cal | Conformance |
| `spec/03-single-file-packages.md#3.4.3.p46:b5f92bd9` | All package initialisation completes before any task begins executing | Race-freedom |
| `spec/04-tasks-and-channels.md#4.1.p2:78f022f7` | Task declarations only at package top level | Race-freedom |
| `spec/04-tasks-and-channels.md#4.1.p3:542e0dee` | Each task declaration creates exactly one task; no task types/arrays | Race-freedom |
| `spec/04-tasks-and-channels.md#4.1.p4:016e5737` | Task end identifier must match task name | Conformance |
| `spec/04-tasks-and-channels.md#4.1.p5:4e4afebc` | Priority aspect must be in System.Any_Priority range | Race-freedom |
| `spec/04-tasks-and-channels.md#4.1.p6:be85291b` | Task declarations shall not bear public keyword | Conformance |
| `spec/04-tasks-and-channels.md#4.1.p7:393c53c2` | Task declarations shall not be nested | Conformance |
| `spec/04-tasks-and-channels.md#4.1.p9:b4640bda` | Default priority is implementation-defined and documented | Conformance |
| `spec/04-tasks-and-channels.md#4.1.p10:92a67777` | Tasks begin execution after all package-level initialisation | Race-freedom |
| `spec/04-tasks-and-channels.md#4.1.p11:2460c5cb` | Preemptive priority-based scheduling; equal priority order is impl-def | Determinism |
| `spec/04-tasks-and-channels.md#4.2.p13:4f888b03` | Channel declarations only at package top level | Conformance |
| `spec/04-tasks-and-channels.md#4.2.p14:a35bd0fa` | Channel element type must be definite | Conformance |
| `spec/04-tasks-and-channels.md#4.2.p15:b5b29b0e` | Channel capacity must be positive integer | Conformance |
| `spec/04-tasks-and-channels.md#4.2.p20:8aa1a21e` | Channel is FIFO: elements dequeued in enqueue order | Determinism |
| `spec/04-tasks-and-channels.md#4.2.p21:c6a92460` | Channel ceiling priority at least max of accessing task priorities | Race-freedom |
| `spec/04-tasks-and-channels.md#4.2.p21a:16ec46cb` | Cross-package channel ceiling priority computation via interface summa | Race-freedom |
| `spec/04-tasks-and-channels.md#4.3.p23:197d9a49` | Send/try_send expression type matches channel element type | Conformance |
| `spec/04-tasks-and-channels.md#4.3.p24:9e47ed4c` | Receive/try_receive variable type matches channel element type | Conformance |
| `spec/04-tasks-and-channels.md#4.3.p25:961abe5a` | try_send/try_receive success variable must be Boolean | Conformance |
| `spec/04-tasks-and-channels.md#4.3.p26:3a9449c1` | Channel operations shall not appear at package level | Conformance |
| `spec/04-tasks-and-channels.md#4.3.p27:ef0ce6bd` | send blocks if channel full; value evaluated before enqueue | Race-freedom  |
| `spec/04-tasks-and-channels.md#4.3.p27a:8ed3c1d4` | Ownership transfer (move) on send for owning access types | Memory-safety |
| `spec/04-tasks-and-channels.md#4.3.p28:ea6bd13c` | receive blocks if channel empty; dequeues front element | Race-freedom  |
| `spec/04-tasks-and-channels.md#4.3.p28a:4cb19779` | Ownership transfer on receive; null-before-move rule applies | Memory-safety |
| `spec/04-tasks-and-channels.md#4.3.p29:f792d704` | try_send: atomic non-blocking enqueue attempt | Race-freedom |
| `spec/04-tasks-and-channels.md#4.3.p29a:8d3f2225` | Move occurs only on successful try_send for owning access types | Memory-safety |
| `spec/04-tasks-and-channels.md#4.3.p29b:7121ccd7` | Implementation shall not null source until enqueue confirmed | Memory-safety |
| `spec/04-tasks-and-channels.md#4.3.p30:62619161` | try_receive with ownership transfer and null-before-move rule | Memory-safety |
| `spec/04-tasks-and-channels.md#4.3.p31:a7297e97` | Channel operations atomic with respect to same-channel operations | Race-freedom |
| `spec/04-tasks-and-channels.md#4.3.p31a:a621d08c` | Channel ownership invariant: each designated object owned by exactly o | Memory-safety |
| `spec/04-tasks-and-channels.md#4.4.p33:7a94ab51` | Select must contain at least one channel arm | Conformance |
| `spec/04-tasks-and-channels.md#4.4.p34:f0f83b83` | At most one delay arm in select statement | Conformance |
| `spec/04-tasks-and-channels.md#4.4.p35:2ad6e64f` | Select arms are receive-only (no send in select) | Conformance |
| `spec/04-tasks-and-channels.md#4.4.p36:0bffbd47` | Select channel arm subtype must match channel element type | Conformance |
| `spec/04-tasks-and-channels.md#4.4.p37:6ced8129` | Select channel arm introduces scoped variable | Conformance |
| `spec/04-tasks-and-channels.md#4.4.p38:35ed84d9` | Delay arm expression must be Duration-compatible | Conformance |
| `spec/04-tasks-and-channels.md#4.4.p39:1012f4db` | Select tests arms in declaration order; first ready arm selected | Determinism |
| `spec/04-tasks-and-channels.md#4.4.p40:4cfdeffe` | Delay arm selected if delay expires before any channel ready | Determinism |
| `spec/04-tasks-and-channels.md#4.4.p41:cdf6a558` | Simultaneous channels: first listed arm selected (deterministic) | Determinism |
| `spec/04-tasks-and-channels.md#4.4.p42:dce8ac38` | Select blocks if no arm ready and no delay arm present | Race-freedom |
| `spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99` | Each package-level variable accessed by at most one task | Race-freedom |
| `spec/04-tasks-and-channels.md#4.5.p47:bc08fb3b` | Cross-package ownership checking via effect summaries | Race-freedom |
| `spec/04-tasks-and-channels.md#4.5.p49:d2001725` | Reject subprogram accessing package variable if callable from multiple | Race-freedom |
| `spec/04-tasks-and-channels.md#4.5.p50:2882310a` | Task-Variable Ownership clause | Conformance |
| `spec/04-tasks-and-channels.md#4.6.p53:897d5577` | Task body outermost statement must be unconditional loop | Race-freedom |
| `spec/04-tasks-and-channels.md#4.6.p53b:19b7c4ae` | Reject return statement within task body | Conformance |
| `spec/04-tasks-and-channels.md#4.6.p53c:77a5f52c` | Exit statement shall not target outermost loop of task | Conformance |
| `spec/04-tasks-and-channels.md#4.7.p56:55e4230e` | All package initialisation completes before any task executes | Race-freedom |
| `spec/04-tasks-and-channels.md#4.7.p58:d10f9cd1` | Task activation order is implementation-defined | Determinism |
| `spec/05-assurance.md#5.4.1.p32:90d4f527` | Channel-based tasking model guarantees data race freedom | Race-freedom |
| `spec/05-assurance.md#5.4.1.p33:0fc25399` | Data race freedom verified via task-variable ownership analysis | Race-freedom |
| `spec/05-assurance.md#5.4.2.p34:198b1ddf` | Ceiling priority rules prevent priority inversion | Race-freedom |
| `spec/05-assurance.md#5.4.4.p40:36087a2c` | Task body effect summaries reference only owned variables and channel  | Race-freedom |
| `spec/06-conformance.md#6.1.p1e:d0e6c93b` | Enforce task-variable ownership as legality rule | Race-freedom |

---

## Assumptions Registry

The following assumptions are made across PO entries. Each must be validated or justified.

1. **All 14 TBD items (TBD-01 through TBD-14) will be resolved**
   - Used by: 1 PO(s)
     - `spec/00-front-matter.md#0.8.p27:5000a79a`

2. **Channel implementation correctly serializes access**
   - Used by: 1 PO(s)
     - `spec/04-tasks-and-channels.md#4.3.p31a:a621d08c`

3. **Channel implementation provides mutual exclusion**
   - Used by: 1 PO(s)
     - `spec/04-tasks-and-channels.md#4.3.p31:a7297e97`

4. **Dependency interface effect summaries are sound**
   - Used by: 1 PO(s)
     - `spec/04-tasks-and-channels.md#4.5.p47:bc08fb3b`

5. **Dependency interface information accurately represents effects**
   - Used by: 1 PO(s)
     - `spec/02-restrictions.md#2.3.7.p108:083e15a2`

6. **Implementation provides at least 64-bit intermediate evaluation**
   - Used by: 1 PO(s)
     - `spec/02-restrictions.md#2.8.1.p126:812b54a8`

7. **Resource exhaustion behavior is defined (abort) but not statically preventable**
   - Used by: 1 PO(s)
     - `spec/05-assurance.md#5.3.1.p12a:047a8410`

8. **Runtime abort handler is correctly implemented**
   - Used by: 1 PO(s)
     - `spec/02-restrictions.md#2.3.5.p103a:520dc0d4`

9. **Runtime system implements deferred task activation**
   - Used by: 2 PO(s)
     - `spec/03-single-file-packages.md#3.4.3.p46:b5f92bd9`
     - `spec/04-tasks-and-channels.md#4.7.p56:55e4230e`

10. **Static analysis implementation is verified or validated**
   - Used by: 1 PO(s)
     - `spec/06-conformance.md#6.4.p11:f35e2134`

11. **Static range analysis is sound**
   - Used by: 1 PO(s)
     - `spec/02-restrictions.md#2.8.1.p130:2289e5b2`

12. **Target hardware supports IEEE 754 non-trapping mode**
   - Used by: 2 PO(s)
     - `spec/02-restrictions.md#2.8.5.p139:d50bc714`
     - `spec/05-assurance.md#5.3.7a.p28a:5936dbea`

13. **Select polling deadline check is faithful to wall-clock elapsed time**
   - Used by: template_select_polling (`spec/04-tasks-and-channels.md#4.4`)

---

## Risk Assessment

### Highest Priority POs for Proof

The following PO categories represent the highest risk areas that require
priority attention in the SPARK companion proof effort.

#### Priority 1: Silver AoRTE (D27 Rules 1-5)

These POs directly back the Silver guarantee -- the central value proposition
of the Safe language. Failure to prove any of these would undermine the
fundamental claim that every conforming Safe program is free of runtime errors.

- **Rule 1 (Wide Intermediate Arithmetic)**: 5 POs covering overflow and range checks.
  Risk: sound static range analysis correctness. Interval arithmetic must be proven sound.
- **Rule 2 (Provable Index Safety)**: 2 POs covering array bounds checks.
  Risk: type containment and range analysis interaction with dynamic bounds.
- **Rule 3 (Division by Provably Nonzero Divisor)**: 2 POs covering division-by-zero.
  Risk: nonzero proof methods must be exhaustively enumerated.
- **Rule 4 (Not-Null Dereference)**: 1 PO covering null dereference.
  Risk: flow-sensitive null tracking must integrate with ownership model.
- **Rule 5 (Floating-Point Non-Trapping)**: 4 POs covering IEEE 754 compliance.
  Risk: hardware compliance assumption; FP range analysis precision.

#### Priority 2: Memory Safety (Ownership Model)

These POs back the ownership, borrowing, and lifetime containment guarantees.
The ownership model is novel relative to standard SPARK and requires ghost
model invariants that have no direct precedent.

- **28 POs** covering move semantics, borrow freezing,
  lifetime containment, automatic deallocation, and channel ownership transfer.
- Key risk: channel ownership transfer atomicity during concurrent operations.
- Key risk: null-before-move flow analysis completeness.

#### Priority 3: Race Freedom (Task-Variable Ownership)

These POs back the data race freedom guarantee -- a critical safety property.

- **34 POs** covering task-variable ownership,
  channel atomicity, non-termination, and elaboration ordering.
- Key risk: cross-package transitivity of effect summaries.
- Key risk: channel ceiling priority computation correctness.

#### Priority 4: Bronze Flow Analysis

- **5 POs** covering Global, Depends, Initializes derivation.
- Lower risk: well-understood problem with existing GNATprove tooling.
- Key risk: automatic derivation correctness proof (no user annotations).

#### Priority 5: Determinism

- **9 POs** covering select ordering, initialization ordering,
  scheduling, and FIFO channel semantics.
- Key risk: implementation-defined behavior documentation completeness.

#### Priority 6: Conformance and Library Safety

- **97 Conformance POs**: mostly syntactic restriction
  checks that are straightforward translation validations.
- **2 Library-safety POs**: retained library modifications.
- Low risk: primarily implementable as compiler front-end checks.

### Deferred POs

1 PO(s) are deferred, requiring future tooling or spec resolution:

- `spec/00-front-matter.md#0.8.p27:5000a79a`: All TBD items shall be resolved before baselining

### Stubbed POs

204 PO(s) are stubbed -- they have identified verification mechanisms
but the SPARK companion stubs are not yet implemented. These will be
addressed in subsequent implementation tasks.
