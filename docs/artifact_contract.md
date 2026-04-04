# Artifact Contract

This document is the normative machine-interface contract for the current Safe
compiler outputs.

## Scope

Frozen machine-facing artifacts:

- `typed.json` with `format: "typed-v5"`
- `mir.json` with `format: "mir-v4"`
- `safei.json` with `format: "safei-v4"`
- `diagnostics-v0` remains the current stable diagnostics shape

Not part of the frozen machine-interface contract:

- AST JSON emitted by `safec ast` and nested under `typed.json["ast"]`
- emitted Ada/SPARK source layout
- repo-local cache directory layout

## Required Top-Level Fields

`typed-v5`, `mir-v4`, and `safei-v4` must all carry:

- `format`
- `target_bits`

`target_bits` must be either `32` or `64`.

The contract validator requires the same `target_bits` value across the typed,
MIR, and interface payloads from one emit run.

`typed-v5` and `safei-v4` may additionally carry `interface_members` on public
type descriptors for Safe structural interface declarations. This is part of
the frozen contract surface from `PR11.11b` onward.

## CLI Surface

The compiler accepts `--target-bits 32|64` on:

- `safec ast`
- `safec check`
- `safec emit`
- `safe build`
- `safe run`
- `safe prove`

Default target width is `64`.

## Target Semantics

`--target-bits` parameterizes the builtin Safe `integer` base range:

- `32`: `-(2**31) .. 2**31 - 1`
- `64`: `-(2**63) .. 2**63 - 1`

The Safe source language stays target-agnostic. There is no source-level
`integer_32` / `integer_64` split.

In this milestone, emitted arithmetic still uses the existing
`Safe_Runtime.Wide_Integer` model. `target_bits` affects builtin integer bounds
and the emitted narrowing/range-check surface, not the intermediate arithmetic
runtime model.

## Compatibility Rules

No version bump is required for:

- additive optional fields
- additive enum values that do not change existing value semantics
- documentation-only clarifications

A version bump is required for:

- required field additions
- field removals
- field renames
- field type changes
- semantic changes to existing enum values or required fields
- target-semantics changes that alter the meaning of existing payloads

`diagnostics-v0` stays on its current version until one of the breaking rules
above is triggered for diagnostics specifically.
