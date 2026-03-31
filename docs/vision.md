# Safe Language Vision

This document records the long-term goals for the Safe language, toolchain, and
ecosystem. It is a living document that evolves as the project matures. Nothing
here is a commitment or a scheduled milestone; it captures intent and direction
so that near-term decisions remain aligned with the broader arc.

## Core Promise

If a Safe program compiles, it is safe. The compiler is the proof engine. Users
do not run a separate verifier, attach contracts to their code, or hope that a
prover converges. The safety guarantee is a property of compilation, not an
optional add-on.

The admitted source surface is fully lowercase, with underscores as the word
separator for multiword spellings.

## Developer Experience Doctrine

### Guards are contracts

Safe's formal verification is invisible to the programmer. There are no
annotations, no contract keywords, no proof directives, and no `#[verify]`
attributes. The programmer writes normal defensive code — the same input
validation, bounds checking, null guarding, and early-error returns they would
write in Go — and the compiler extracts proof obligations from the code's own
control flow.

When a programmer writes:

```
function insert (table : store.map, k : string, v : string) returns boolean
   if k.length == 0 or k.length > max_key_len
      return false
   if store.length (table) >= max_entries
      return false
   store.insert (table, k, v)
   return true
```

The compiler sees the early returns as path constraints. After the guards pass,
it knows `k.length` is in `1..max_key_len` and `store.length(table)` is less
than `max_entries`. Those facts close the proof obligations on the `insert`
call without the programmer writing a single annotation.

This is the central developer experience insight: **the guards programmers
already write for correctness are the contracts the prover needs.** Safe does
not ask programmers to learn formal methods. It asks them to write the checks
they should write anyway, and it proves those checks are sufficient.

The practical corollary is that the repository should not treat "builds and
runs" as enough for user-facing examples. The checked-in sample sweep now
proves samples as well as building and executing them, specifically so missing
guards show up as source-level proof failures with suggested fixes in context.
That is not extra ceremony; it is the product working as intended.

That same rule now applies to newly shipped source features, not just the old
numeric/string core. When the language surface widens, the sample corpus must
widen with it and stay in the prove-build-run sweep. The current user-defined
enum sample is part of that contract rather than a docs-only example.

### Where guards alone are not enough

Guards-as-contracts cover input validation, bounds checking, capacity checking,
null/empty guarding, and error-code returns. This is the majority of what
typical programs need. For the remaining cases, the compiler must guide the
programmer toward the right solution:

**Loop invariants.** When the compiler cannot prove a loop body is safe, the
fix is usually a wider accumulator type or a tighter loop bound — not an
annotation. The compiler must explain this in terms of the program, not in
terms of proof theory.

**Ownership and borrowing.** Reference lifetimes, freeze scopes, and move
invalidation do not reduce to guard-before-use patterns. The compiler must
explain which reference is invalid and why, with enough context for the
programmer to restructure their code.

**Whole-program invariants.** Some properties (a channel never receives when
empty, an access type is never null between allocation and deallocation) span
multiple functions. The compiler must trace the property across call sites
and show the programmer where the invariant breaks.

### Diagnostic quality is a first-class requirement

The compiler's error messages are the primary teaching tool. They must not just
report what failed — they must suggest what to do about it. The target quality
level is:

```
safedb.safe:14:7: error: cannot prove store.length(table) < max_entries
  after insert on line 16
  |
  | 14 |      store.insert (table, k, v)
  |    |      ^^^^^^^^^^^^^^^^^^^^^^^^^
  |
  help: add a guard before this call:
  |
  | 13 |      if store.length (table) >= max_entries
  | 14 |         return false
  |
```

The diagnostic suggests a specific guard the programmer can add. It does not
say "medium: range check might fail" or "unproved verification condition."
Those are prover-internal concepts that should never reach the user.

Common unproved patterns should map to named fix strategies with documentation
links:

- Accumulator overflow → "use a wider type for the loop variable
  (see safe-lang.org/patterns/accumulator)"
- Null dereference after conditional → "add a null check before this access
  (see safe-lang.org/patterns/null-guard)"
- Index out of bounds → "constrain the index variable to the array range
  (see safe-lang.org/patterns/bounded-index)"

The compiler is the teacher. If the error message does not make the fix
obvious, the error message is a bug.

### Two levels of type discipline

The language supports both casual and formal typing. Casual types are for
getting started, exploring, and writing programs where the proof obligations
are simple. Formal types are for production safety-critical code where the
programmer wants the tightest possible guarantees.

| Casual | Formal | Trade-off |
|--------|--------|-----------|
| `string` | `string_buffer (64)` | Formal gives bounded capacity proof |
| `integer` | `subtype count is integer (0 to 1024)` | Formal gives tight overflow proof |
| `(boolean, string)` | Discriminated record with variants | Formal prevents accessing fields that don't exist for this variant |
| Multiple returns | Named out parameters | Formal documents intent at the call site |

Both compile. Both are safe. The casual versions require guards to prove what
the formal versions prove by construction. The compiler should never force a
programmer into formal types — it should explain what additional guards the
casual types require and let the programmer choose.

A Go programmer starts with `string` and `integer` and guards. A safety
engineer starts with bounded types and range constraints. Both write valid Safe
programs. The language meets them where they are.

### The Go programmer's first hour

A programmer coming from Go should be able to:

1. Download one archive. Unzip. Add to PATH.
2. Write a program using `string`, `integer`, `boolean`, and tuples.
3. Run `safe build`. Get either a binary or a clear error with a suggested fix.
4. Add the suggested guard. Run `safe build` again. Get a binary.
5. Never encounter the words "verification condition," "loop invariant,"
   "precondition," or "proof obligation."

If step 3 produces an error that requires the programmer to understand formal
methods, the toolchain has failed. The error must be expressible as "your code
is missing this check" — not "the prover cannot discharge this obligation."

## Distribution Model

### Single-archive distribution

Safe ships as one download per platform. The archive contains the `safe` CLI,
the Safe compiler frontend (`safec`), the Ada backend toolchain (GNAT,
gprbuild), and the proved standard library. No package manager, no separate
compiler install, no runtime to configure. Download, unzip, add to PATH, done.

This follows the Go model: one archive, one entry point, everything works
immediately.

### The `safe` CLI

The user-facing tool is `safe`, not `safec`. It owns the Safe developer
experience end to end:

```
safe check <file.safe>       diagnostics only
safe build <file.safe>       check, emit, compile to executable
safe emit  <file.safe>       emit Ada/SPARK output for inspection or interop
safe prove [file.safe]       emitted GNATprove audit
safe run   <file.safe>       build and execute
safe fmt   <file.safe>       format (post-v1.0)
safe test  <file.safe>       test runner (post-v1.0)
```

Internally, `safe build` calls `safec emit` then `gprbuild` on the emitted Ada.
The current repo-local prototype is intentionally single-file only; roots with
leading `with` clauses still fall back to manual `safec emit` plus `gprbuild`.
`safe run` reuses that same single-file build flow, then launches the produced
binary. `safe prove` is wider here: it can already audit imported multi-file
roots because it proves emitted packages directly and does not need a runnable
`main`. The user-facing goal remains a fully integrated `safe build`
experience with Safe-oriented diagnostics.

### What ships, what does not

The core distribution includes:

- `safe` CLI (Ada binary)
- `safec` compiler frontend (Ada binary)
- GNAT compiler (GPL-3.0 + GCC Runtime Library Exception)
- gprbuild (GPL-3.0 + GCC Exception)
- Ada runtime libraries (GPL-3.0 + GCC Runtime Library Exception)
- Proved standard library (Safe source, emitted to SPARK)

GNATprove and SMT solvers are not required for daily development. Once the
emitter's proof corpus comprehensively covers the accepted language surface, the
proof is a compiler-development concern, not a user concern. Users trust the
toolchain the same way Go or Rust users trust theirs.

For regulated or certification contexts, a separate `safe prove` package
provides GNATprove plus CVC5 and Z3 for independent verification evidence.
Alt-Ergo is excluded from the distribution due to its non-commercial license
terms; CVC5 (BSD-3-Clause) and Z3 (MIT) provide sufficient prover coverage.

### No Python in the distribution

The `safe` CLI is a compiled Ada binary. Python exists in the repository as
CI/test glue but is invisible to users. This extends the existing no-Python
doctrine from `safec` to the entire user-facing toolchain.

### Alire is not shipped

Alire is a compiler-development dependency. Safe programs do not declare Ada
crate dependencies; they declare Safe package dependencies resolved by the Safe
compiler's own interface system. Users never type `alr`.

## Standard Library (Safelib)

### Written in Safe

The standard library is Safe source code. It goes through `safec check` and
`safec emit` like any user program. The emitted Ada/SPARK passes GNATprove. The
library's proof obligations are part of the compiler's proof corpus, not the
user's responsibility.

This is a stronger guarantee than SPARKlib provides. SPARKlib's formal
containers have SPARK contracts on their specifications but their implementations
are standard Ada with `SPARK_Mode => Off`. GNATprove proves correct usage but
not correct implementation. Safelib's containers are Safe source, emitted to
SPARK-subset Ada with full bodies, proved end to end.

### Proof level: Gold

Silver proves absence of runtime errors. The standard library should exceed that
baseline. Gold adds functional correctness: a sort function actually sorts, a
map lookup returns the value that was inserted, a vector's length increases by
one after append.

The practical sequence:

1. Ship Bronze/Silver containers first (monomorphic in PR11.10, generic in
   PR11.11). They compile, they do not crash, they are usable.
2. Add Gold contracts incrementally, starting with the most-used operations.
3. The contracts become part of the emitter's proof corpus. If a container's
   functional contract stops proving, the emitter is broken.

Platinum (information-flow security) is not a goal for the general-purpose
standard library. It may be relevant for a future `Safe.Crypto` package.

### Minimum viable contents

Drawing from Go's standard library and what is needed to write real programs:

- **Collections**: bounded vector, bounded map, bounded set, bounded queue
- **Text**: string buffer, string utilities, formatting, numeric-to-text
  conversion
- **I/O**: file read/write, formatted output (requires I/O seam wrappers with
  separately verified contracts)
- **Concurrency**: higher-level patterns built on the language's channel/task
  primitives
- **Math**: basic numeric utilities, bounded arithmetic helpers

### SPARKlib as transitional dependency

SPARKlib (Apache-2.0 WITH LLVM-exception) may serve as an emitter target for
container types before Safelib exists. Once Safelib ships its own containers,
SPARKlib becomes optional for Ada interop rather than foundational. SPARKlib's
lemma libraries remain useful regardless, as GNATprove uses them to close
arithmetic proof obligations in emitted code.

## Compiler Assurance

### Current state

The compiler is conventional Ada code verified by testing, not by proof.
GNATprove verifies the emitted output, not the compiler itself. The compiler is
in the trusted computing base.

### Target state

Every compiler component must reach SPARK Bronze/Silver as a minimum baseline.
Bronze (flow analysis: no uninitialized reads, no unused assignments, correct
data/flow dependencies) and Silver (all runtime checks proved: no overflow, no
range violation, no index out of bounds, no null dereference) apply uniformly
across the entire compiler. This is not aspirational; it is a requirement before
the compiler can credibly claim that its output is trustworthy.

Above that baseline, critical components have higher targets:

**Emitter (Gold target for critical transforms).** The emitter's core
transforms -- ownership lowering, integer-range checking and narrowing, postcondition
generation, cleanup ordering -- are where correctness matters most. These are
finite, well-defined transforms from MIR to Ada text. Proving that a transform
preserves semantics is tractable and high-value. Gold contracts on these
transforms mean that the emitter does not just avoid crashing -- it produces
semantically correct output.

**Analyzer (Silver baseline, Gold selectively).** The MIR analyzer enforces
ownership, range, and discriminant rules. Silver ensures it does not crash. Gold
on specific analysis judgments (e.g., proving that the borrow checker's accept/
reject decision is consistent with the ownership model) is desirable where
tractable but not required uniformly. The analyzer's correctness is also
backstopped by the emitted-output proof: if the analyzer accepts a program it
should not have, the emitted Ada will fail to prove.

**Parser, resolver, lowerer (Silver baseline).** Large mechanical passes where
bugs manifest as wrong ASTs or wrong MIR, caught by downstream gates. Silver
ensures they do not crash. Gold is not required -- the test corpus and
downstream proof provide adequate functional coverage.

### What Bronze/Silver on the compiler requires

The compiler currently uses standard Ada features that SPARK forbids: exception
handling for control flow, unbounded strings, access types for AST nodes. Reaching
Bronze/Silver will require:

- Isolating non-SPARK features behind `SPARK_Mode => Off` boundaries with
  SPARK-annotated wrapper specs, or progressively replacing them with
  SPARK-compatible alternatives
- Adding `SPARK_Mode => On` to each compiler package
- Running GNATprove flow analysis (Bronze) and runtime-check proof (Silver)
  as part of the compiler's own CI, not just on emitted output
- Treating GNATprove failures on compiler sources as CI-blocking, the same way
  emitted-output proof failures are CI-blocking today

This is substantial work. It will proceed incrementally, package by package,
starting with the emitter (highest payoff) and working inward toward the parser
(largest volume, lowest risk).

### The compounding effect

Each layer's proof level multiplies confidence:

```
Safe source
  compiler (Silver; Gold on critical emitter transforms)
    emitted Ada/SPARK (Silver by construction)
      Safelib (Gold -- functionally correct contracts)
        GNATprove (proves the whole thing)
```

A Silver compiler producing Silver code that calls Gold-proved library functions
gives stronger end-to-end assurance than any single layer at Platinum. The
chain is the product.

### When

Compiler self-verification is not a prerequisite for v1.0. The test
infrastructure provides adequate confidence for the current language surface.
Post-v1.0, progressive SPARK annotation of the compiler is a high-value
initiative that would make Safe's assurance story genuinely unique: a formally
verified compiler producing formally verified output calling a formally verified
standard library.

## Proof Coverage Strategy

### The emitter proves everything

The long-term model is that every accepted Safe program emits Ada/SPARK that
proves under GNATprove as part of compiler development. If the proof is
comprehensive, `safe prove` at user time is redundant for correctness -- the
proof was done when the emitter was validated.

This is fundamentally different from SPARK's model, where the programmer writes
contracts and hopes the prover converges. In Safe, the proof is an emitter
invariant: if the frontend accepted the program and the emitter is correct, the
emitted Ada must prove. If it does not, that is an emitter bug, not a user error.

### Incremental proof expansion

Proof coverage expands at natural stability points in the language roadmap rather
than being deferred to one massive catch-up:

- **PR10.6**: closes the remaining ~27 sequential fixtures
- **After PR11.3 (discriminants)**: first proof checkpoint for string, case,
  and discriminated-record fixtures
- **After PR11.8 (numeric model)**: second proof checkpoint; re-validate that
  Rules 1-5 still hold under the new numeric semantics
- **Concurrency proof**: parallel track closing the ~9 unproved concurrency
  fixtures, landing before PR11.9

### What remains outside proof

Some obligations are inherently outside GNATprove's reach and require different
verification approaches (testing, runtime analysis, or separate formal methods):

- Broader runtime-model guarantees beyond the admitted STM32F4/Jorvik subset (`PS-036`)
- Broader select fairness and latency semantics beyond the admitted polling contract (`PS-035`)
- I/O seam wrapper contracts (PS-019)

These are post-v1.0 concerns that do not block the core safety guarantee for
pure computation and channel-based concurrency.

## `safe prove` as Audit Tool

Once the emitter's proof corpus is comprehensive, `safe prove` exists for
transparency, not necessity. It lets users verify the toolchain's claim
independently on their specific program on their machine. The output is a proof
certificate for regulatory or certification contexts, not a pass/fail
diagnostic for daily development.

In the near term (before proof coverage is complete), `safe prove` tells users
whether their specific program falls inside or outside the proved corpus. Once
coverage is comprehensive, it becomes an assurance artifact generator.

The current repo-local prototype already implements that emitted-proof audit
path. It runs `safec check`, `safec emit`, compiles the emitted Ada, then runs
GNATprove `flow` and `prove` using the repo's current emitted-proof policy. Its
verdict is intentionally limited to emitted Ada proof; it does not subsume
separate runtime evidence such as the embedded/Jorvik concurrency lane.

The repository sample sweep now uses that same emitted-proof path. This keeps
the checked-in examples honest: a sample that still builds and runs but no
longer proves is treated as a regression, because that is exactly the case
where the compiler should be teaching the user which guard or control-flow fact
is missing.

This also means the core `safe` distribution can ship without GNATprove. The
prove capability is an optional package for users who need independent
verification evidence.

## Licensing Constraints

The distribution bundles GPL-licensed tools (GNAT, gprbuild, GNATprove) under
"mere aggregation." Source code for GPL components must be provided. The GCC
Runtime Library Exception ensures that executables produced by `safe build` can
be distributed under any license.

CVC5 (BSD-3-Clause) and Z3 (MIT) are fully permissive. Alt-Ergo's
non-commercial license makes it unsuitable for bundled distribution; CVC5 and Z3
together provide sufficient prover coverage.

Safelib will be under a permissive license so that Safe programs using the
standard library can be distributed under any license, matching the GCC Runtime
Library Exception's guarantee for the Ada runtime.

## Timeline Sketch

**Current (PR10.x series)**: proof-corpus expansion, emitter hardening, parser
and evidence hardening. No user-facing tooling changes.

**PR11.1**: language evaluation harness. `safe build` prototype (Python),
VSCode syntax highlighting, diagnostics LSP shim, Rosetta sample corpus.
First real-program feedback loop.

**PR11.2-PR11.7**: language surface expansion and syntax stabilization. Strings,
case statements, discriminated records, syntax proposals, block syntax, and the
lowercase-source cutover. First proof checkpoint after PR11.3.

**PR11.8-PR11.8g**: numeric and value-type model reset. Unified integer type
(superseding the earlier three-tier model), simplified predefined type names,
binary arithmetic, value-type strings, copy-by-default value/reference
semantics, a value-model proof checkpoint, and value-only channel elements.

**PR11.9**: artifact contract stabilization. Machine interfaces freeze for
ecosystem consumers after the recovered PR11.8 proof and channel milestones.

**PR11.10**: monomorphic standard library (bounded containers, string buffer).
First Safelib code, Bronze/Silver.

**PR11.11**: restricted generics. Generic containers replace monomorphic ones.
Safelib becomes parameterized.

**Post-PR11.11**: spec v1.0 baseline. Resolve remaining TBDs. Freeze grammar,
type system, emission rules.

**Post-v1.0 horizons**:

- Compiled `safe` CLI replacing Python prototype
- Single-archive distribution per platform
- Full LSP server (diagnostics, go-to-definition, hover, completion)
- `safe fmt`, `safe test`, `safe get` (package management)
- `safe repl` interactive exploration loop
- Progressive SPARK annotation of the compiler
- Gold contracts on Safelib
- Crypto/security library at Platinum level

## Interactive REPL

Now that `print` (PR11.8c.1) and package-level statements (PR11.8c.2) have
landed, Safe has the minimal surface needed for a compile-and-run REPL. The
REPL is a tool (`scripts/safe_repl.py` or later `safe repl`), not a language
feature.

The current prototype accumulates declarations and statements into a growing
single-file buffer. Each time the user presses enter, the tool rebuilds that
buffer as a packageless entry file, runs `safec check` + `safec emit` +
`gprbuild`, and executes the result.

The proof story carries into the REPL: if the accumulated program can't
be proven safe, the REPL shows the compiler diagnostic instead of running.
The programmer sees range violations, overflow, and type errors
interactively rather than at a later build step.

Tasks are not supported in REPL mode because they run indefinitely and
can't be incrementally extended. The REPL is for computational
exploration: defining types, writing functions, calling them, and
printing results.

## Compiler Optimization Targets

These are implementation-quality improvements that do not change language
semantics. They can land at any point without milestone coordination.

- **Return value optimization:** construct return values directly in the
  caller's frame when GNAT's RVO applies to the emitted Ada. This eliminates
  the copy on `var result = f(args)` for composite types in the common case.
- **Last-use move:** when a variable is dead after an assignment or channel
  send, silently move instead of copy. Requires liveness analysis in the
  emitter. Covers `var b = a` where `a` is never read again, and
  `send ch, value` where `value` is never read again.
- **Copy diagnostics:** optional `safec emit --show-copies` flag that reports
  where actual copies occur in emitted Ada, so programmers can identify
  unnecessary copies without reading the emitted code.

## I/O Architecture

The initial `print` built-in uses a thin `SPARK_Mode (Off)` wrapper around
`Ada.Text_IO`. This is sufficient for development and testing but has
limitations: output from concurrent tasks may interleave, and the I/O
call is synchronous (the calling task blocks until the write completes).

The long-term I/O architecture replaces direct I/O calls with dedicated
persistent service tasks:

- **stdout task:** receives string messages through an internal channel and
  writes them to standard output in order. Output from concurrent tasks is
  serialized through the channel — no interleaving.
- **stderr task:** same architecture for diagnostic/error output.
- **stdin task:** reads lines from standard input and sends them through an
  internal channel. Consumer tasks receive input without blocking on I/O
  directly.

Under this model, `print ("hello")` lowers to `send stdout_ch, "hello"` —
a normal channel operation that is non-blocking from the caller's
perspective. The `SPARK_Mode (Off)` boundary is isolated to the three
runtime I/O tasks, which the programmer never sees or declares. All user
code remains fully provable.

This architecture requires the value-type string (PR11.8d), the built-in
container layer (PR11.10), and runtime startup/shutdown coordination for
the persistent I/O tasks. It belongs in the library/runtime layer rather
than in a language milestone.
