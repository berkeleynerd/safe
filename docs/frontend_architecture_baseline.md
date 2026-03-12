# Frontend Architecture Baseline

This document is the canonical prose baseline for the Safe compiler frontend after PR07.

## Live Ada-Native Commands

The live user-facing compiler commands are:

- `safec lex`
- `safec ast`
- `safec validate-mir`
- `safec analyze-mir`
- `safec check`
- `safec emit`

All of those commands are Ada-native runtime surfaces for the current implemented subset.

## Current Supported Subset

The current frontend supports the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern.

PR08.2 adds the accepted local-only concurrency checking slice for single-package tasks, channels, channel operations, select, and relative delay.

That means the current frontend baseline covers:

- the frozen Rule 5 floating-point corpus
- sequential ownership checking
- the current boolean result-record discriminant pattern
- local-only concurrency checking for accepted single-package task/channel/select/delay sources
- AST, `typed-v2`, `mir-v2`, and `safei-v0` emission for that same subset
- MIR validation and MIR analysis for the same subset

The following surfaces remain explicitly out of scope for the current frontend baseline:

- fixed-point Rule 5 work
- general discriminants
- discriminant constraints
- access discriminants
- cross-package tasks/channels/concurrency analysis beyond the local PR08.2 slice
- broader Ada/SPARK emission work

## No-Python Doctrine

Python is glue/orchestration only.

No user-facing `safec` command depends on Python at runtime.

Python remains allowed in-repo only for harnesses, validators, CI/report orchestration, and other non-runtime glue around the Ada-native compiler.

## Live and Deleted Package Ownership

The live frontend implementation is owned by:

- `Check_*`
- `Mir_*`
- `Lexer`
- `Source`
- `Types`
- `Diagnostics`
- `Json`

The old shallow `Ast` / `Parser` / `Semantics` / `Mir` chain was deleted in PR06.9.8.

The current frontend baseline therefore lives only on the Ada-native `Check_*` plus `Mir_*` pipeline, with `Lexer`, `Source`, `Types`, `Diagnostics`, and `Json` supporting that path.

## PR08 Starting Point

PR08 must extend the live path rather than revive deleted legacy packages.

The current PR07 scope and scale limits are summarized in [frontend_scale_limits.md](frontend_scale_limits.md).
