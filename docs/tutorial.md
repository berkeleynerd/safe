# Safe Tutorial (Working Draft)

This is a succinct, opinionated tour of the Safe language as currently specified in `spec/`.
It is written for readers who want to evaluate the project as it evolves, including both virtues and warts.

Safe is defined subtractively from Ada 2022 (ISO/IEC 8652:2023). If you already know Ada, read this as "the delta plus the new bits".
If you do not know Ada, you can still follow along, but the full language reference is the Ada RM plus the Safe spec delta.

This repo now includes an Ada-native `safec` frontend plus emitted-output proof
gates. The spec and curated tests remain the authoritative reference for
language intent and assurance boundaries. For a concrete walkthrough of the
current toolchain, see
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
| Attributes | dot notation: `T.First` not `T'First` | uniform "selected" syntax | breaks muscle memory; `'` reserved for character literals |
| Qualified exprs | no `T'(Expr)`; use type annotation `(Expr as T)` | makes narrowing points explicit | extra parentheses; more "ceremony" in aggregates and allocators |
| Exceptions | none (no handlers, no `raise`) | control-flow stays explicit; proof story is cleaner | error handling becomes explicit and sometimes verbose |
| Tasking | static tasks + typed channels | analyzable concurrency | less expressive than full Ada tasking/protected objects |

## 3. Program Shape: Single-File Packages + `public`

In Safe, a package is a single `.safe` file containing declarations and bodies. There is no separate spec and body file.

```safe
-- demo.safe
package Demo

   public type Index is range 0 to 15;
   public type Buf is array (Index) of Integer;

   Hidden : Integer = 0;  -- not public, not visible to clients

   public function Sum (B : Buf) returns Integer
      var Total : Integer = 0
      for I in Index.First to Index.Last
         Total = Total + B(I)
      return Total
```

Virtue: you can read a package top-to-bottom without jumping between spec/body, and public API is visually obvious.

Wart: large packages can get large fast; Safe intentionally leans on tooling and structure rather than the spec/body split.

See: `spec/03-single-file-packages.md`.

### 3.1 Opaque Types With `private record`

Safe uses `private record` (not Ada's package `private` part) to express an opaque type:

```safe
package Buffers
   public type Buffer_Size is range 1 to 4096;
   public subtype Buffer_Index is Buffer_Size;

   public type Buffer is private record
      Data   : array (Buffer_Index) of Character = (others = ' ');
      Length : Buffer_Size = 1;
```

Virtue: clients can name and pass the type, but cannot depend on its representation.

Wart: the syntax is novel if you are used to Ada's spec/body + `private` section model.

## 4. Attributes Use Dot Notation

Safe forbids tick-based attribute references. Use dot notation instead:

- `T.First`, `T.Last`
- `T.Range` (and `T.Range(N)` where Ada permits it)
- `X.Image` and `T.Image(X)` (image attributes are retained)

Virtue: removes an irregular syntax form from the core language and makes attribute access look like other selection.

Wart: you cannot "accidentally" paste Ada code that uses `X'First` and have it work.

See: `spec/02-restrictions.md` (tick restriction) and `spec/03-single-file-packages.md` (resolution rules).

## 5. Type Annotation Replaces Qualified Expressions

Ada uses `T'(Expr)` to qualify an expression (often an aggregate). Safe replaces this with:

```safe
(Expr as T)
```

This matters in allocators and aggregates. In Safe, you would write:

```safe
type Payload is record
   Value : Integer;

type Payload_Ptr is access Payload;

P : Payload_Ptr = new ((Value = 42) as Payload);
```

Virtue: qualification becomes a consistent surface form, and (more importantly) narrowing points become easier to identify and reason about.

Wart: you will write more parentheses than in Ada.

See: `spec/02-restrictions.md` (qualified expressions and allocators) and `spec/08-syntax-summary.md` (allocator grammar).

## 6. "Silver By Construction": D27 In One Page

Safe's Silver level is built around a simple premise:

- intermediate integer arithmetic is evaluated "wide" (no overflow),
- and any narrowing back into a constrained type must be statically provable safe,
- and other runtime-check sources (division by zero, bounds, null deref) are similarly eliminated by type/range discipline.

Practically, this pushes you toward:

- defining range types for indices and counts,
- using those types pervasively (especially for array indices and divisors),
- making narrowing explicit (conversions, type annotations, allocator initializers).

Virtue: you can get very strong safety properties without writing contracts.

Wart: you end up designing your numeric types up front. "Just use Integer everywhere" fights the language.

See: `spec/05-assurance.md`.

## 7. Access Types With Ownership, Move, Borrow, Observe

Safe retains access-to-object types, but adopts SPARK's ownership model:

- assignments of owning access values are moves (source becomes null),
- mutable access parameters act like borrows (lender is frozen),
- `access constant` parameters act like read-only observations.

Example sketch (move):

```safe
type Node is record
   V : Integer;
type Node_Ptr is access Node;

function Demo_Move
   var A : Node_Ptr = new ((V = 1) as Node)
   var B : Node_Ptr = null
   B = A        -- move A into B; A becomes null
   B.all.V = 2  -- safe dereference through the new owner
```

Virtue: eliminates an entire class of aliasing and lifetime bugs, while staying in an Ada-like surface syntax.

Wart: you must think about who owns what, and you cannot freely copy pointers around to "share" data.

See: `spec/02-restrictions.md` (Section 2.3).

## 8. Concurrency: Static Tasks + Typed Channels

Safe replaces most of Ada's tasking surface features with:

- static task declarations (typically at package level),
- typed bounded FIFO channels,
- `send`, `receive`, and non-blocking `try_send` / `try_receive`,
- a `select` statement for multiplexing receives (with optional delay arms).

Example sketch:

```safe
package Pipeline
   public type Measurement is range 0 to 65535;

   channel Raw : Measurement capacity 16;
   channel Out : Measurement capacity 8;

   task Producer with Priority = 10
      loop
         var M : Measurement = Read_Sensor
         send Raw, M
         delay 0.01

   task Consumer with Priority = 5
      loop
         var M : Measurement
         receive Raw, M
         send Out, Process(M)
```

Example sketch (`select`):

```safe
task Control with Priority = 10
   loop
      select
         when Cmd : Command from Commands
            Handle(Cmd)
      or
         delay 1.0
            Tick
```

Virtue: concurrency is structured around explicit communication points, which is easier to analyze and makes "what can race" more tractable.

Wart: you do not get the full expressive power of Ada tasking (entries, accept, requeue, etc.), and tasks are intentionally constrained (including a non-termination rule).

See: `spec/04-tasks-and-channels.md`.

## 9. Error Handling Without Exceptions (Current Gap + Candidate Idiom)

Safe explicitly excludes exceptions, handlers, and `raise`. That removes the traditional Ada error-handling escape hatch.

Virtue: control flow stays explicit, which helps both human reasoning and tool reasoning (and avoids "hidden" paths that complicate proofs).

Wart: the spec currently does not bless a standard replacement idiom, and without an idiom, every codebase will invent its own.

One strong candidate idiom (from upstream GitHub Discussions
[#11](https://github.com/berkeleynerd/safe/discussions/11) and
[#12](https://github.com/berkeleynerd/safe/discussions/12)) is a discriminated "result" record:

```safe
type Error_Code is (Invalid_Input, Overflow, Not_Found);

type Result (OK : Boolean = False) is record
   case OK
      when True
         Value : Integer;
      when False
         Error : Error_Code;
```

Why this is attractive in a SPARK/Safe world:

- The discriminant makes it illegal to access `.Value` when `OK == False` (a property SPARK can prove).
- It nudges you toward exhaustive handling and away from "ignore the error and keep going" bugs.

Tradeoff: without generics, you will likely define many small `Result_*` types, one per value/error pairing, until the language or standard library provides a better abstraction.

Also note: Safe draws a sharp line between recoverable and non-recoverable failures. At least today, a failed `pragma Assert` or an allocation failure is defined to abort the program via a runtime abort handler, not to be handled in-user-code like an exception.

## 10. Known Friction Points (Read Before You Commit)

- No I/O standard library (by design). A future "system sublanguage" may address this.
- No generics, no tagged types, no overloading: abstraction techniques are intentionally limited.
- The "Silver by construction" story means you will spend effort on numeric subtype design.
- Some Ada habits are invalid in Safe (`'` attributes and qualified expressions, exceptions).
- Tooling is incomplete today: the repo has a working compiler frontend and
  proof pipeline, but the supported language and proof surface is still
  narrower than the full spec ambition.

## 11. Where To Go Next

- Spec entry: `spec/00-front-matter.md`
- The restrictions list (what's removed): `spec/02-restrictions.md`
- Packages and `public`: `spec/03-single-file-packages.md`
- Tasks/channels/select: `spec/04-tasks-and-channels.md`
- Assurance model and D27: `spec/05-assurance.md`
- Grammar: `spec/08-syntax-summary.md`
- Examples: `tests/positive/`
