# Safe Tutorial (Working Draft)

This is a succinct, opinionated tour of the Safe language as currently specified in `spec/`.
It is written for readers who want to evaluate the project as it evolves, including both virtues and warts.

Safe is a language in its own right, not a subtractive Ada profile. If you
already know Ada, many constructs will feel familiar, but the normative
reference is the Safe spec rather than "Ada plus a delta".

This repo now includes an Ada-native `safec` frontend plus a minimal
test/sample/proof workflow. The spec and curated tests remain the authoritative
reference for language intent and assurance boundaries. For a concrete
walkthrough of the current toolchain, see
[`docs/safec_end_to_end_cli_tutorial.md`](safec_end_to_end_cli_tutorial.md).

## 0. Where To Start (If You Read Only 3 Things)

1. Language entry point: `spec/00-front-matter.md`
2. The guarantee story (Bronze/Silver, D27 rules): `spec/05-assurance.md`
3. The authoritative grammar: `spec/08-syntax-summary.md`

For concrete programs, browse `tests/positive/` (acceptance-style examples) and `spec/03-*.md` / `spec/04-*.md` (worked examples).

## 1. What Safe Is Trying To Be

Safe is a systems programming language designed so that:

- Bronze: programs are provably free of data races and uninitialized reads.
- Silver: programs are provably free of runtime errors (overflow, division by zero, bounds errors, null dereference, double ownership) without developer proof annotations.

Virtue: the safety story is a language property, not a lint or a "run tests and hope" property.

Wart: this is achieved by restrictions. Some idioms that are common in Ada (and most languages) are disallowed, and Safe code tends to be more explicit about ranges, narrowing, ownership, and fallible operations.

## 2. The Biggest Differences From Ada (Surface Syntax)

Safe keeps most Ada surface syntax, but changes a few high-impact parts:

| Area | Safe choice | What it buys | What it costs |
|------|-------------|--------------|---------------|
| Visibility | `public` keyword, default-private | simple interface model, simpler separate compilation | surprising if you expect Ada's spec/body + private part model |
| Attributes | dot notation: `t.first` not `t'First` | uniform "selected" syntax | breaks muscle memory; `'` reserved for character literals |
| Qualified exprs | no `t'(expr)`; use type annotation `(expr as t)` | makes narrowing points explicit | extra parentheses; more "ceremony" in aggregates and narrowed initializers |
| Exceptions | none (no handlers, no `raise`) | control-flow stays explicit; proof story is cleaner | error handling becomes explicit and sometimes verbose |
| Tasking | static tasks + typed channels | analyzable concurrency | less expressive than full Ada tasking/protected objects |

## 3. Program Shape: Single-File Units + `public`

In Safe, an explicit package is a single `.safe` file containing declarations,
bodies, and any admitted unit-scope statements. There is no separate spec and
body file.

```safe
-- demo.safe
package demo

   public subtype index is integer (0 to 15);
   public type buf is array (index) of integer;

   hidden : integer = 0;  -- not public, not visible to clients

   public function sum (b : buf) returns integer
      var total : integer = 0
      for i in index.first to index.last
         total = total + b(i)
      return total
```

Virtue: you can read a package top-to-bottom without jumping between spec/body, and public API is visually obvious.

Wart: large packages can get large fast; Safe intentionally leans on tooling and structure rather than the spec/body split.

See: `spec/03-single-file-packages.md`.

### 3.1 Packageless Entry Files and Top-Level Statements

Safe also admits executable statements at unit scope after declarations, and a
single-file executable root may omit `package` entirely:

```safe
value : integer = 41;

print (value + 1)
```

That is a packageless entry file. The unit name comes from the filename stem,
and its unit-scope statements execute in source order before any tasks declared
in the same file start.

The current `safe build` / `safe run` prototype is intentionally narrower than
the language:

- single-file explicit-package roots work
- single-file packageless entry roots work
- roots with leading `with` clauses still use `safec emit` plus manual
  `gprbuild` for now

### 3.1 Opaque Types With `private record`

Safe uses `private record` (not Ada's package `private` part) to express an opaque type:

```safe
package buffers
   public subtype buffer_size is integer (1 to 4096);
   public subtype buffer_index is buffer_size;

   public type buffer is private record
      data   : string (4096) = "";
      length : buffer_size = 1;
```

Virtue: clients can name and pass the type, but cannot depend on its representation.

Wart: the syntax is novel if you are used to Ada's spec/body + `private` section model.

## 4. Attributes Use Dot Notation

Safe forbids tick-based attribute references. Use dot notation instead:

- `t.first`, `t.last`
- `t.range` (and `t.range(n)` where Ada permits it)
- `x.image` and `t.image(x)` (image attributes are retained)

Virtue: removes an irregular syntax form from the core language and makes attribute access look like other selection.

Wart: you cannot "accidentally" paste Ada code that uses `X'First` and have it work.

See: `spec/02-restrictions.md` (tick restriction) and `spec/03-single-file-packages.md` (resolution rules).

## 5. Type Annotation Replaces Qualified Expressions

Ada uses `T'(Expr)` to qualify an expression (often an aggregate). Safe replaces this with:

```safe
(expr as t)
```

This matters in aggregates and other target-typed initializers. In Safe, you would write:

```safe
type payload is record
   value : integer;

p : payload = ((value = 42) as payload);
```

Virtue: qualification becomes a consistent surface form, and (more importantly) narrowing points become easier to identify and reason about.

Wart: you will write more parentheses than in Ada.

See: `spec/02-restrictions.md` (qualified expressions) and `spec/08-syntax-summary.md`.

## 5.1 Text and Arrays (PR11.8d Surface)

Safe now has a real value-type text and array surface rather than the older
provisional PR11.2 text model.

Bounded text uses `string (N)`:

```safe
name : string (5) = "hello";
prefix : string (5) = name (1 to 2);
initial : string (1) = 'h';
```

This is the stack-backed text form. It supports `.length`, indexing, slicing,
equality, and ordinary assignment.

Growable arrays use `array of T` and bracket literals:

```safe
type int_list is array of integer;

values : int_list = [10, 20, 30];
total : integer = 0;

for item of values
   total = total + item;
```

The shipped PR11.8d conversion boundary is:

- fixed -> growable works through normal target typing
- growable -> fixed works only when the RHS length is syntactically exact at
  the narrowing site, such as a bracket literal or a static name-based slice

Example:

```safe
subtype slot is integer (3 to 4);
subtype item is integer (0 to 10);
type pair is array (slot) of item;

selected : pair = [7, 9];
```

Still deferred beyond the current PR11.8d surface:

- string iteration
- proof-based exact-length growable -> fixed narrowing
- string `case`
- string discriminants
- string and growable-array channel elements

## 6. "Silver By Construction": D27 In One Page

Safe's Silver level is built around a simple premise:

- `integer` is a signed 64-bit type, and every integer arithmetic result must
  be statically provable within that range,
- and any narrowing back into a constrained type must be statically provable safe,
- and other runtime-check sources (division by zero, bounds, null deref) are similarly eliminated by type/range discipline.

Practically, this pushes you toward:

- defining range types for indices and counts,
- using those types pervasively (especially for array indices and divisors),
- making narrowing explicit (conversions, type annotations, target-typed initializers).

Virtue: you can get very strong safety properties without writing contracts.

Wart: you end up designing your numeric types up front. "Just use integer everywhere" fights the language.

Safe also now has a small fixed-width binary surface for protocol and bitwise
work:

- `binary (8)`, `binary (16)`, `binary (32)`, `binary (64)` for machine-word
  values,
- explicit conversion at the `integer` / `binary` boundary,
- `and`, `or`, `xor`, `not` for `boolean` and `binary`,
- `<<` and `>>` for `binary`, with `>>` defined as logical zero-fill.

That keeps ordinary signed arithmetic and proof obligations centered on
`integer` while still admitting the common "I need a byte / hash word /
protocol field" cases without pretending they are signed numbers.

See: `spec/05-assurance.md`.

## 7. Inferred References, Moves, and Borrows

Safe no longer exposes `access`, `new`, `.all`, or source-level `in` / `out`
/ `in out`. Instead:

- recursive record families are inferred as reference roots,
- assignment of inferred references moves ownership,
- ordinary parameters are immutable borrows,
- `mut` parameters are mutable borrows,
- `null` and `not null` are admitted only for inferred reference-typed
  bindings.

Example sketch (move):

```safe
type node is record
   v : integer;
   next : node;

function set_value (target : mut not null node; value : integer)
   target.v = value

function demo_move
   var a : node = (v = 1, next = null)
   var b : node = null
   b = a      -- move A into B; A becomes null
   set_value (b, 2)
```

Virtue: ownership and borrowing still prevent the usual aliasing and lifetime
mistakes, but the source surface stays simpler because the programmer writes
ordinary record types and ordinary field selection.

Wart: you still need to think about ownership, moves, and mutable-borrow
aliasing. PR11.8e.1 extends the model to mutually recursive record families,
but the alias rule is still conservative: same-root `mut` actuals remain
rejected until a later follow-up.

See: `spec/02-restrictions.md` (Section 2.3).

## 8. Concurrency: Static Tasks + Typed Channels

Safe replaces most of Ada's tasking surface features with:

- static task declarations (typically at package level),
- optional task `sends` / `receives` clauses for channel-direction legality,
- typed bounded FIFO channels,
- `send`, `receive`, and non-blocking `try_send` / `try_receive`,
- scoped-binding `receive` / `try_receive` forms such as
  `receive raw, msg : measurement`,
- a `select` statement for multiplexing receives (with optional delay arms).

Example sketch:

```safe
package pipeline
   public subtype measurement is integer (0 to 65535);

   channel raw : measurement capacity 16;
   channel out : measurement capacity 8;

   task producer with priority = 10, sends raw
      loop
         var m : measurement = read_sensor
         send raw, m
         delay 0.01

   task consumer with priority = 5, receives raw, sends out
      loop
         receive raw, m : measurement
         send out, process(m)
```

Example sketch (`select`):

```safe
task control with priority = 10
   loop
      select
         when cmd : command from commands
            handle(cmd)
      or
         delay 1.0
            tick
```

Virtue: concurrency is structured around explicit communication points, which is easier to analyze and makes "what can race" more tractable.

Wart: you do not get the full expressive power of Ada tasking (entries, accept, requeue, etc.), and tasks are intentionally constrained (including a non-termination rule).

Post-PR11.8e, task bodies may use only their own locals and channels. Package-
scope result slots and counters no longer count as legal task communication.

See: `spec/04-tasks-and-channels.md`.

## 9. Error Handling Without Exceptions (Current Gap + Candidate Idiom)

Safe explicitly excludes exceptions, handlers, and `raise`. That removes the traditional Ada error-handling escape hatch.

Virtue: control flow stays explicit, which helps both human reasoning and tool reasoning (and avoids "hidden" paths that complicate proofs).

Wart: the spec currently does not bless a standard replacement idiom, and without an idiom, every codebase will invent its own.

One strong candidate idiom (from upstream GitHub Discussions
[#11](https://github.com/berkeleynerd/safe/discussions/11) and
[#12](https://github.com/berkeleynerd/safe/discussions/12)) is a discriminated "result" record:

```safe
type error_code is (invalid_input, overflow, not_found);

type result (ok : boolean = false) is record
   case ok
      when true
         value : integer;
      when false
         error : error_code;
```

Why this is attractive in a SPARK/Safe world:

- The discriminant makes it illegal to access `.value` when `ok == false` (a property SPARK can prove).
- It nudges you toward exhaustive handling and away from "ignore the error and keep going" bugs.

Tradeoff: without generics, you will likely define many small `result_*`
types, one per value/error pairing, until the language or standard library
provides a better abstraction.

Also note: Safe draws a sharp line between recoverable and non-recoverable failures. At least today, a failed `pragma Assert` or an allocation failure is defined to abort the program via a runtime abort handler, not to be handled in-user-code like an exception.

## 10. Known Friction Points (Read Before You Commit)

- No user-extensible I/O standard library. The current output surface is only
  statement-only `print (expr)` for `integer`, `string`, and `boolean`.
- No multi-file `safe build` yet. The current wrapper is intentionally
  single-file; roots with `with` clauses still use `safec emit` plus manual
  `gprbuild`.
- No generics, no tagged types, no overloading: abstraction techniques are intentionally limited.
- The "Silver by construction" story means you will spend effort on numeric subtype design.
- Some Ada habits are invalid in Safe (`'` attributes and qualified expressions, exceptions).
- Tooling is incomplete today: the repo has a working compiler frontend and
  proof workflow, but the supported language and proof surface is still
  narrower than the full spec ambition.

## 11. Where To Go Next

- Spec entry: `spec/00-front-matter.md`
- The restrictions list (what's removed): `spec/02-restrictions.md`
- Packages and `public`: `spec/03-single-file-packages.md`
- Tasks/channels/select: `spec/04-tasks-and-channels.md`
- Assurance model and D27: `spec/05-assurance.md`
- Grammar: `spec/08-syntax-summary.md`
- Examples: `tests/positive/`
