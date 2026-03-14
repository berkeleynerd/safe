# Frontend Architecture Baseline

This document is the canonical prose baseline for the Safe compiler frontend after PR08.

## Live Ada-Native Commands

The live user-facing compiler commands are:

- `safec lex`
- `safec ast`
- `safec validate-mir`
- `safec analyze-mir`
- `safec check`
- `safec emit`

All of those commands are Ada-native runtime surfaces for the current implemented subset.

PR09 adds deterministic Ada/SPARK emission on top of that PR08 frontend baseline through `safec emit --ada-out-dir`, without widening the accepted frontend-analysis subset.

PR10 adds selected emitted-output GNATprove `flow` / `prove` verification on top
of that emitted surface without claiming universal proof coverage for every
currently emitted Safe program. [`emitted_output_verification_matrix.md`](emitted_output_verification_matrix.md)
is the canonical statement of what emitted output is compile-validated,
GNATprove-validated, exception-backed, or deferred.

## Current Supported Subset

The current frontend supports the exact current Rule 5 fixture corpus, sequential ownership, and the current boolean result-record discriminant pattern.

PR08.2 adds the accepted local-only concurrency checking slice for single-package tasks, channels, channel operations, select, and relative delay.

PR08.3 adds explicit dependency-interface lookup plus `safei-v1` publication/consumption for imported public types, subtypes, channels, objects, and subprogram signatures.

PR08.3a adds ordinary object constants on the live Ada-native path plus imported integer/boolean constant values in the currently supported static-expression sites.

PR08.4 adds imported-summary consumption for cross-package task ownership, channel-access, and channel ceiling analysis through imported `safei-v1` summaries, plus imported-call ownership semantics at the call boundary.

That means the current frontend baseline covers:

- the frozen Rule 5 floating-point corpus
- sequential ownership checking
- the current boolean result-record discriminant pattern
- local-only concurrency checking for accepted single-package task/channel/select/delay sources
- imported package-qualified resolution through explicit `--interface-search-dir` inputs and `safei-v1`
- ordinary object constants plus imported integer/boolean constant values in the current static-expression sites
- cross-package task ownership, channel-access, and channel ceiling analysis through imported `safei-v1` summaries
- imported-call ownership semantics at the call boundary
- AST, `typed-v2`, `mir-v2`, and `safei-v1` emission for that same subset
- MIR validation and MIR analysis for the same subset

The following surfaces remain explicitly out of scope for the current frontend baseline:

- fixed-point Rule 5 work
- general discriminants
- discriminant constraints
- access discriminants
- named numbers and richer constant folding beyond the PR08.3a constant slice
- emitted-output GNATprove coverage beyond the selected PR10 corpus

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

## PR08 Baseline

PR08 extends the live path rather than reviving deleted legacy packages, and the current supported frontend baseline is now PR08 rather than PR07.

The current PR07 scope and scale limits are summarized in [frontend_scale_limits.md](frontend_scale_limits.md).
