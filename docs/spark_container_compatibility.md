# SPARK Container Library Compatibility Analysis

This supporting reference collects the background material that informs the
container-related proposals in
[syntax_proposals.md](syntax_proposals.md).

## Purpose

This document records the compatibility between SPARK's formal container
library (`SPARK.Containers.Formal.*`) and Safe's design restrictions.

## What SPARK provides

SPARK's container library (SPARKlib, since SPARK 23) has two families:

### Formal containers (for executable code)

**Bounded (no dynamic allocation):**

| Package | Description |
|---------|-------------|
| `SPARK.Containers.Formal.Vectors` | Indexed sequence |
| `SPARK.Containers.Formal.Doubly_Linked_Lists` | Linked list |
| `SPARK.Containers.Formal.Hashed_Maps` | Hash-based key-value |
| `SPARK.Containers.Formal.Ordered_Maps` | Sorted key-value |
| `SPARK.Containers.Formal.Hashed_Sets` | Hash-based set |
| `SPARK.Containers.Formal.Ordered_Sets` | Sorted set |

**Unbounded (heap-backed):**
Each of the above has an `Unbounded_` variant that supports indefinite element
types and uses heap allocation.

### Functional containers (for specification/ghost code)

Immutable mathematical models used in contracts:
`Functional.Vectors`, `Functional.Maps`, `Functional.Sets`,
`Functional.Multisets`, `Functional.Infinite_Sequences`, `Functional.Trees`.

## How SPARK handles the "no exceptions" problem

SPARK's approach is identical to Safe's D27 model: **preconditions replace
exceptions.**

- `Element` has `Pre => Has_Element (Container, Position)` instead of raising
  `Constraint_Error`.
- `Insert` has `Pre => Length(Container) < Capacity(Container)` instead of
  raising `Capacity_Error`.
- Cursor validity is expressed through preconditions rather than runtime
  tampering checks.
- The formal containers are **not themselves verified** in SPARK. Their visible
  specs (`.ads`) are in SPARK with full contracts; their private parts and
  bodies are not in SPARK. GNATprove can prove correct *usage* of formal
  containers in client code but does not prove the container implementations.

## Compatibility Matrix

| SPARK container feature | Safe restriction | Compatible? |
|-------------------------|------------------|-------------|
| Generic packages | D16: no generics | **No** — every container is a generic instantiation |
| Tagged types (internal implementation) | D18: no tagged types | **No** |
| Iterable aspect for `for..of` | Excluded for containers (§29) | **No** — would need array-based iteration |
| Controlled types | Excluded (§12) | **No** for unbounded variants |
| Precondition-based API | Matches D27 model | **Yes** — transfers directly |
| Bounded discriminant-capacity pattern | Just a record + array | **Yes** — Safe-legal |
| Cursor-as-integer API | No tagged/access cursors | **Partially** — compatible if cursors are plain integers |
| Heap allocation (unbounded) | D17 ownership types | **Potentially** — via ownership tracking |

## Key Findings

1. **The API model is directly applicable.** SPARK's precondition-based error
   handling is exactly what Safe uses (D27 Rules 1–4). The contracts on SPARK
   containers map to Safe preconditions without modification.

2. **The implementations cannot be imported.** Every SPARK container is a
   generic package. Even if the API model transfers, the code itself cannot be
   used in Safe source.

3. **The emitter can use them.** Since D16 applies to Safe source, not emitted
   Ada, the emitter can generate SPARK generic instantiations. This is the
   basis for the emitter-based container instantiation proposal.

4. **Bounded containers avoid most exclusions.** The bounded variants don't use
   controlled types or heap allocation. Their primary incompatibilities are
   generics and tagged types — both of which are implementation details that
   disappear after instantiation.

5. **SPARK's containers are not proven internally.** If Safe wants Silver-level
   assurance for container *implementations* (not just usage), the containers
   need to be written in Safe or verified separately. The SPARK containers only
   provide verified-usage guarantees.

## Implications for Safe's Roadmap

| Phase | Strategy | SPARK dependency |
|-------|----------|-----------------|
| v0.3 monomorphic containers | Hand-written Safe packages modeled on SPARK API | None — API pattern only |
| v0.3 emitter-based constructors | Emitter generates SPARK instantiations | SPARKlib required at build time |
| v0.4 restricted generics | Safe-native generics, expanded by compiler | None — self-contained |
| v0.5+ owning containers | Containers with access-type elements | Ownership model must be defined for container operations |
