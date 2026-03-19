This document is the canonical running ledger of proposed Safe syntax changes.
It records future-facing design directions only; inclusion here does not
imply an implementation commitment or rollout schedule.

# Whitespace-Significant Blocks

## Motivation

The current Safe syntax uses Ada-style `begin`/`end`, `loop`/`end loop`, and
`record`/`end record` block delimiters. These are explicit and
self-documenting, but they add ceremony that every line of code pays for.

Key observations from the design discussion:

- **`begin`/`end` says nothing the indentation doesn't already say.** Every
  developer already indents to show structure. Making indentation meaningful
  eliminates the redundant delimiter without losing information.
- **`loop` as a block delimiter adds no meaning** — in `for I in Index`, the
  `for` already tells you it's a loop. The only case where `loop` is
  genuinely meaningful is the bare infinite loop, where it *is* the construct.
- **`end Foo` closing labels are valuable** for safety-critical review. They
  are preserved under `pragma Strict` for teams that need them. They are not
  needed in the default mode.
- **Precedent**: Python is the most widely used programming language partly
  because of its clean, indentation-based syntax. Nim and Haskell also use
  significant whitespace successfully. The "invisible character" concern is
  addressed by compiler-enforced indentation rules (spaces only, fixed width,
  no mixing).

## Proposed Change

In the default mode, indentation defines block structure. No `begin`/`end`,
no braces, no `end loop`, no `end record`. Keywords that introduce blocks
(`function`, `procedure`, `if`, `else if`, `else`, `for`, `while`, `loop`,
`task`, `package`, `record`) increase the indentation level on the following
line. A decrease in indentation level closes the block.

The compiler enforces:
- spaces only (no tabs)
- fixed indentation width (3 spaces)
- consistent indentation throughout the compilation unit
- a wrong indentation level is a compile error, not a silent structural change

Under `pragma Strict`, the full Ada-style keyword-delimited syntax with
closing labels is used instead. See the `pragma Strict` proposal.

## Block-Opening Rules

A new indentation level is opened after any line ending with one of:

| Line ending | Opens block for |
|-------------|-----------------|
| Function/procedure signature | Subprogram body |
| `package <name>` | Package body |
| `if <condition>` | If branch |
| `else if <condition>` | Else-if branch |
| `else` | Else branch |
| `for <var> in <range>` | For loop body |
| `while <condition>` | While loop body |
| `loop` | Bare infinite loop body |
| `task <name> ...` | Task body |
| `record` | Record field list |

A decrease in indentation closes the innermost open block.

## Examples

### Accumulator — for loop

```
package accumulator

   type small_int is range 0 .. 100
   type index is range 1 .. 20
   type values is array (index) of small_int
   type total_range is range 0 .. 2000

   function accumulate (data : values) returns total_range
      sum : total_range = 0

      for i in index
         sum = sum + total_range (data (i))
      return sum
```

### Binary Search — while loop, if/else if/else

```
package binary_search

   type index is range 1 .. 256
   type element is range 0 .. 10_000
   type sorted_array is array (index) of element
   type search_result is record
      found    : boolean
      found_at : index

   function search (arr : sorted_array;
                    key : element) returns search_result
      lo  : index = index.first
      hi  : index = index.last
      mid : index

      while lo <= hi
         mid = lo + (hi - lo) / 2
         if arr (mid) == key
            return ((found = true, found_at = mid) as search_result)
         else if arr (mid) < key
            if mid == index.last
               return ((found = false, found_at = index.first) as search_result)
            lo = mid + 1
         else
            if mid == index.first
               return ((found = false, found_at = index.first) as search_result)
            hi = mid - 1
      return ((found = false, found_at = index.first) as search_result)
```

### Linked List — record types, null guard

```
package safe_linked_list

   type node
   type node_ref is access node

   type node is record
      value : integer
      Next  : access node

   function sum_values (Head : node_ref) returns integer
      total : integer = 0

      if Head != null
         total = total + Head.value
         if Head.Next != null
            total = total + Head.Next.value
      return total
```

### Channel Pipeline — tasks, bare loops, channels

```
package pipeline

   type sample is range 0 .. 10_000

   channel raw_ch      : sample capacity 4
   channel filtered_ch : sample capacity 4

   task producer with priority = 10
      counter : sample = 0

      loop
         send raw_ch, counter
         if counter < 10_000
            counter = counter + 1
         else
            counter = 0

   task filter with priority = 10
      input  : sample
      output : sample

      loop
         receive raw_ch, input
         output = input / 2
         send filtered_ch, output

   task consumer with priority = 10
      data : sample
      sum  : integer = 0

      loop
         receive filtered_ch, data
         sum = sum + integer (data)
         if sum > 1_000_000
            sum = 0
```

### Ownership Move — record, access types, procedure

```
package ownership_demo

   type payload is record
      value : integer

   type payload_ref is access payload

   procedure transfer
      Source : payload_ref = new ((value = 42) as payload)
      Target : payload_ref = null

      Target = move Source
      Target.value = 100
```

## Tradeoffs

| Gain | Loss |
|------|------|
| Minimal ceremony — the code IS the structure | Invisible characters carry semantic weight |
| ~30-40% reduction in line count vs Ada-style | Copy-paste across contexts can lose indentation |
| No delimiter vocabulary to learn | Mixed-editor teams must agree on spaces/width |
| Python-familiar to the largest developer community | No machine-verifiable closing labels (use `pragma Strict` for that) |
| Indentation is always correct (compiler enforces it) | Cannot place multiple blocks on one line |

## Alternatives Considered

1. **Brace-delimited blocks (`{ }`)** — the original proposal in this
   document. Braces are a middle ground: less ceremony than `begin`/`end`,
   more ceremony than whitespace. **Rejected** because braces satisfy
   neither the "maximum clarity" camp (no closing labels like `end loop`)
   nor the "minimum ceremony" camp (still need `{`, `}` on their own lines).
   Whitespace-significant default plus `pragma Strict` for begin/end covers
   both extremes. Braces are a compromise that serves no audience fully.

2. **Three modes (whitespace + braces + begin/end)** — too many options. Two
   modes (whitespace default + strict) are sufficient. Every additional mode
   fragments the ecosystem and complicates tooling.

3. **Whitespace only (no strict mode)** — removes the safety-critical team's
   option for explicit closing labels. `pragma Strict` is essential for
   DO-178C review contexts where `end loop;` and `end function_name;` are
   required by coding standards.

---

# Record Field Encapsulation

## Motivation

Given the snippet:

```
package Buffers is
   public type Buffer_Size is range 1 .. 4096;
   public subtype Buffer_Index is Buffer_Size;
   public type Buffer is private record
      Data   : array (Buffer_Index) of Character = (others = ' ');
      Length : Buffer_Size = 1;
   end record;
end Buffers;
```

The declaration `public type Buffer is private record` reads as contradictory.
`public` and `private` modify different things (type visibility vs. field
visibility), but in plain English they clash directly. This is confusing and
should be eliminated.

## Proposed Rule

**Record fields are always package-scoped.** No `private` keyword is needed on
the type declaration. Fields are directly accessible within the declaring
package and inaccessible outside it. External access is provided through
explicitly declared public functions and procedures.

This is a single rule with no exceptions:

| Context | Field access |
|---------|-------------|
| Inside declaring package | Direct (`Buf.Data`, `Buf.Length`) |
| Outside declaring package | Only through public functions/procedures |

## Example

```
package Buffers {

   public type Buffer_Size is range 1 .. 4096;
   public subtype Buffer_Index is Buffer_Size;

   public type Buffer is record {
      Data   : array (Buffer_Index) of Character = (others = ' ');
      Length : Buffer_Size = 1;
   }

   -- Read access
   public function Get_Char (Buf : Buffer; Pos : Buffer_Index) return Character {
      return Buf.Data (Pos);
   }

   public function Get_Length (Buf : Buffer) return Buffer_Size {
      return Buf.Length;
   }

   -- Write access
   public procedure Put_Char (Buf : in out Buffer; Pos : Buffer_Index; Ch : Character) {
      Buf.Data (Pos) = Ch;
      if Pos > Buf.Length {
         Buf.Length = Pos;
      }
   }

   public procedure Clear (Buf : in out Buffer) {
      Buf.Data = (others = ' ');
      Buf.Length = 1;
   }

}
```

## Design Rationale

- **No contradictory phrasing** — `public type Buffer is record` reads cleanly.
  The type is public; its fields are automatically package-scoped.
- **Invariants are enforceable** — `Put_Char` keeps `Length` consistent with
  `Data`. No outside code can set `Length` to a stale value.
- **One rule, no annotation burden** — developers never decide per-field
  visibility. Fields are internal; the public API is functions and procedures.
- **Precedent** — Go (unexported fields + exported methods), Erlang/Elixir
  (opaque types with accessor functions), and ML (abstract types in signatures)
  all use this model successfully.
- **`private` keyword freed up** — with fields always package-scoped, `private`
  can mean its natural thing: "not exported from this package at all" (for
  helper types, internal functions, etc.).

## Alternatives Considered

1. **`opaque record`** — `public type Buffer is opaque record { ... }`.
   Reads well but introduces a new keyword for something that could simply be
   the default behavior.

2. **Field-level `public` annotations** — allow `public Value : Integer` on
   individual fields. More flexible but adds decision burden and risks exposing
   fields that break invariants.

Both were rejected in favor of the simpler "fields are always package-scoped"
rule.

---

# `returns` Keyword

Status: implemented in PR11.4 as a cutover. `returns` is the only accepted
signature-result spelling; legacy signature `return` is rejected.

## Motivation

In the current syntax, function signatures use `return` for both the
declaration and the statement:

```
public function Get_Char (Buf : Buffer; Pos : Buffer_Index) return Character {
   return Buf.Data (Pos);
}
```

The signature reads as an imperative command — "go return Character" — when the
intent is declarative: "this function returns a Character." It's a grammatical
mismatch inherited from Ada.

## Proposed Change

Use **`returns`** in function signatures. The `return` statement inside function
bodies is unchanged.

```
public function Get_Char (Buf : Buffer; Pos : Buffer_Index) returns Character {
   return Buf.Data (Pos);
}
```

- **`returns`** — declarative, in the signature: "Get_Char returns Character"
- **`return`** — imperative, in the body: "return this value"

## Examples

### Accumulator

```
function Accumulate (Data : Values) returns Total_Range {
   Sum : Total_Range = 0;

   for I in Index {
      Sum = Sum + Total_Range (Data (I));
   }
   return Sum;
}
```

### Binary Search

```
function Search (Arr : Sorted_Array;
                 Key : Element;
                 Found_At : out Index) returns Boolean {
   Lo  : Index = Index.First;
   Hi  : Index = Index.Last;
   Mid : Index;

   Found_At = Index.First;
   while Lo <= Hi {
      Mid = Lo + (Hi - Lo) / 2;
      if Arr (Mid) == Key {
         Found_At = Mid;
         return True;
      } elsif Arr (Mid) < Key {
         if Mid == Index.Last {
            return False;
         }
         Lo = Mid + 1;
      } else {
         if Mid == Index.First {
            return False;
         }
         Hi = Mid - 1;
      }
   }
   return False;
}
```

### Linked List

```
function Length (Head : Node_Ptr) returns Natural {
   Count   : Natural = 0;
   Current : Node_Ptr = Head;

   while Current != null {
      Count = Count + 1;
      Current = Current.all.Next;
   }
   return Count;
}
```

## Design Rationale

- **Reads as English** — "function Accumulate returns Total_Range" is a
  grammatically correct sentence. Consistent with Safe's preference for words
  over symbols.
- **No ambiguity** — `returns` (signature) and `return` (statement) are
  visually distinct. One declares, the other executes.
- **Minimal change** — one letter added to a keyword. No new concepts, no
  syntax restructuring.
- **Procedures unaffected** — procedures have no return type, so the keyword
  never appears in their signatures.

## Alternatives Considered

1. **`->` arrow** — `function Get_Char (...) -> Character { }`. Concise, used
   by Rust/Swift/Kotlin. Trades readability for symbol density; inconsistent
   with Safe's "words over symbols" philosophy (`in out` not `&mut`, `access`
   not `*`).

2. **`: Type` after signature** — `function Get_Char (...) : Character { }`.
   Pascal/TypeScript style. Ambiguous since Safe already uses `:` for parameter
   type annotations within the same signature.

Both were rejected. `returns` is the smallest change that fixes the grammar
while staying consistent with the rest of the language.

---

# `pragma Strict`

## Motivation

The whitespace-significant syntax proposed earlier optimizes for conciseness
and readability. But the Ada-style `begin`/`end`, `end loop`, and
`end Package_Name` delimiters have a real advantage: **self-documenting block
closers** that are valuable in safety-critical code, long-lived codebases,
and formal review contexts (e.g., DO-178C).

Rather than forcing a single style, Safe supports both through a compiler-
enforced pragma. Teams that value explicit block labels opt in; everyone else
gets whitespace-significant blocks by default.

## Proposed Change

Introduce **`pragma Strict;`** which, when active, requires the full keyword-
delimited block syntax throughout the compilation unit or project.

### What `pragma Strict` restores

| Construct | Default (whitespace) | Under `pragma Strict` |
|-----------|---------------------|-----------------------|
| Function/procedure body | Indented block after signature | `begin ... end Function_Name;` |
| Package body | Indented block after `package name` | `is ... end Package_Name;` |
| For/while loop body | Indented block after `for`/`while` | `loop ... end loop;` |
| Bare infinite loop | Indented block after `loop` | `loop ... end loop;` |
| Record definition | Indented block after `record` | `record ... end record;` |
| If/else if/else blocks | Indented block after condition | `then ... end if;` |
| Case arms | `when <choice>` + indented block | `when <choice> then ... end when;` |
| Case statement | `case <expr>` + indented arms | `case <expr> is ... end case;` |
| Variant part | `case <disc>` + indented arms | `case <disc> is ... end case;` |
| Return type keyword | `returns` | `return` |
| Semicolons | Optional (auto-inserted) | Required |
| Range delimiter | `to` | `..` |

Under `pragma Strict`, whitespace-significant blocks are rejected by the
compiler. The two styles are mutually exclusive within a compilation unit —
no mixing.

### Current implementation status (PR11.2)

PR11.2 lands only the strict/Ada-like **statement** form of `case`:

```
case expr is
   when choice then
      ...
   end when;
   when others then
      ...
   end when;
end case;
```

The current compiler additionally requires a final `when others then` arm on
every admitted `case`. The default-mode/whitespace `case` syntax and
variant-part `case` remain future work; they are still proposal text here, not
accepted PR11.2 compiler surface.

### Case-arm syntax: `then` replaces `=>`

In default mode, case arms need no delimiter — indentation defines the block:

```
case op
   when get
      var r = Lookup (DB, k)
      return (true, r)
   when put
      Insert (DB, k, v)
      return (true, "")
```

In strict mode, `then` replaces Ada's `=>` as the arm delimiter. The `=>`
symbol is a convention that means "then" — Safe says what it means:

```
case op is
   when get then
      var r = Lookup (DB, k);
      return (true, r);
   end when;
   when put then
      Insert (DB, k, v);
      return (true, "");
   end when;
end case;
```

The same applies to variant parts in record declarations:

```
-- Default mode
type response (op : operation = get) is record
   success : boolean
   case op
      when get
         data : string
      when put
         null

-- Strict mode
type Response (Op : Operation = Get) is record
   Success : Boolean;
   case Op is
      when Get then
         Data : String;
      end when;
      when Put then
         null;
      end when;
   end case;
end record;
```

The `then` keyword reads naturally after `when`: "when get, then do this."
It is consistent with `if ... then` under strict mode and eliminates the
`=>` symbol, which is not self-documenting to non-Ada readers.

### Granularity

- **Per-unit** — place `pragma Strict;` at the top of a source file, before
  the package declaration. Applies to the entire compilation unit.

  ```
  pragma Strict;

  package Flight_Controller is

     type Altitude is range 0 .. 50_000;

     function Current_Altitude return Altitude is
        Raw : Altitude = 0;
     begin
        -- read from sensor
        return Raw;
     end Current_Altitude;

  end Flight_Controller;
  ```

- **Project-wide** — set in the build manifest (e.g., `safe.toml`):

  ```toml
  [build]
  strict = true
  ```

  Individual units can override with `pragma Default;` to use braces in a
  project that defaults to strict.

## Examples

### Accumulator — strict style

```
pragma Strict;

package Accumulator is

   type Small_Int is range 0 .. 100;
   type Index is range 1 .. 20;
   type Values is array (Index) of Small_Int;
   type Total_Range is range 0 .. 2000;

   function Accumulate (Data : Values) return Total_Range is
      Sum : Total_Range = 0;
   begin
      for I in Index loop
         Sum = Sum + Total_Range (Data (I));
      end loop;
      return Sum;
   end Accumulate;

end Accumulator;
```

### Buffers — strict style with encapsulation

```
pragma Strict;

package Buffers is

   public type Buffer_Size is range 1 .. 4096;
   public subtype Buffer_Index is Buffer_Size;

   public type Buffer is record
      Data   : array (Buffer_Index) of Character = (others = ' ');
      Length : Buffer_Size = 1;
   end record;

   public function Get_Char (Buf : Buffer; Pos : Buffer_Index) return Character is
   begin
      return Buf.Data (Pos);
   end Get_Char;

   public procedure Put_Char (Buf : in out Buffer;
                              Pos : Buffer_Index;
                              Ch  : Character) is
   begin
      Buf.Data (Pos) = Ch;
      if Pos > Buf.Length then
         Buf.Length = Pos;
      end if;
   end Put_Char;

end Buffers;
```

### Channel Pipeline — strict style

```
pragma Strict;

package Pipeline is

   type Sample is range 0 .. 10_000;

   channel Raw_Ch      : Sample capacity 4;
   channel Filtered_Ch : Sample capacity 4;

   task Producer is
      Counter : Sample = 0;
   begin
      loop
         send Raw_Ch, Counter;
         if Counter < 10_000 then
            Counter = Counter + 1;
         else
            Counter = 0;
         end if;
      end loop;
   end Producer;

   task Filter is
      Input  : Sample;
      Output : Sample;
   begin
      loop
         receive Raw_Ch, Input;
         Output = Input / 2;
         send Filtered_Ch, Output;
      end loop;
   end Filter;

end Pipeline;
```

## Design Rationale

- **No style wars in a single file** — the pragma is all-or-nothing per
  compilation unit. You never see whitespace blocks and `end loop` in the
  same file.
- **Compiler-enforced** — not a linter suggestion. If `pragma Strict` is
  active, whitespace-significant blocks are a compile error. If it's absent,
  `begin`/`end` delimiters are a compile error. Both styles parse to
  identical ASTs.
- **Safety-critical teams get what they need** — closing labels like
  `end Accumulate` and `end loop` are required by some coding standards
  (e.g., DO-178C reviews). `pragma Strict` gives them first-class support.
- **Tooling can round-trip** — since the two styles have identical semantics,
  a `safe fmt --strict` or `safe fmt --default` command can mechanically
  convert between them.
- **Extensible** — `pragma Strict` can grow to enforce additional discipline
  in future versions (e.g., requiring explicit type annotations, disallowing
  certain shorthand forms) without changing its meaning for existing code.
- **Naming** — "Strict" conveys "more rigorous requirements" without implying
  the default style is incorrect. It leaves room for the pragma to enforce
  additional rules beyond block delimiters as the language evolves.

## Alternatives Considered

1. **`pragma Verbose`** — accurate but pejorative. Implies the style is
   unnecessarily wordy rather than deliberately explicit.

2. **`pragma Classic`** — nods to Ada heritage but suggests the whitespace
   style is the "modern" replacement, which may not age well.

3. **`pragma Explicit_Blocks`** — too narrow. If the pragma grows to enforce
   other rules, the name won't fit.

4. **Compiler flag only (no pragma)** — forces the entire project into one
   style. Per-unit control is valuable when a project mixes application code
   (whitespace) with safety-critical modules (strict).

5. **Brace-delimited default instead of whitespace** — braces are a middle
   ground between whitespace and begin/end. Rejected because braces satisfy
   neither extreme: they lack closing labels for safety-critical review, and
   they still add delimiter noise that whitespace eliminates. Two clean modes
   (whitespace + strict) serve both audiences better than a compromise that
   serves neither fully.

---

# Statement Labels, Loop Labels, and `var` Declarations

## Status

This is a proposal for future syntax work only. It does not change the current
frontend, parser, or accepted surface language.

## Motivation

Statement labels have little practical value in Safe's core language.

- `goto` is not part of the core language.
- Named exits are not part of the core language.
- Structured control flow is preferred throughout the language design.

At the same time, Safe's current statement-local declaration form overlaps with
classic label syntax:

```safe
L: Count = 1;
```

This can be read in two incompatible ways:

- as a labeled assignment where `L` is a label and `Count` is a variable
- as a declaration where `L` is a newly declared object of type `Count`

Banning statement labels alone does not remove that ambiguity if colon-led
statement-local declarations remain legal. The long-term syntax needs to
remove both sides of the overlap.

## Proposed Change

For a future language revision:

- ban statement labels of the form `Label: Statement`
- ban named loop labels and named exits
- keep closing end names such as `end Worker;` and `end loop;` as a separate
  readability feature tied to the strict-style surface syntax
- introduce `var` as the intended syntax for statement-local declarations

The intended future statement-local declaration forms are:

```safe
var Item : Payload_Ptr;
var Count : Natural = 0;
```

The future-invalid statement forms are:

```safe
Label: Statement;
Outer: loop
   ...
end loop Outer;
exit Outer;
```

## Rationale

### Why ban statement labels

Statement labels are primarily useful for:

- `goto` targets
- targeted exits from named loops or blocks
- low-level generated control-flow patterns

Those use cases are either unsupported already or are a poor fit for Safe's
structured, reviewable control-flow model.

### Why keep closing end names

Closing end names solve a different problem. They improve readability at the
end of long declarations or blocks and fit naturally with the existing
`pragma Strict` direction:

```safe
end Worker;
end loop;
```

They should not be treated as part of the same feature surface as statement
labels.

### Why `var`

`var` removes the statement-position colon ambiguity directly:

```safe
var Count : Natural = 0;
Count = Count + 1;
```

With this direction, `L: Count = 1;` no longer needs semantic
disambiguation in the long term because ordinary statements no longer begin
with a declaration-style `Name : Type` form.

## Scope Boundary

This proposal is limited to statement syntax.

- It does not redesign package-level declarations.
- It does not redesign declarative parts inside packages, tasks, or
  subprograms.
- It does not redesign explicit `declare` blocks.

## Migration

Migration policy is intentionally deferred. This proposal records the intended
destination syntax only. A later implementation proposal can decide whether the
transition should be immediate, warning-backed, or staged.

---

# Bounded String Buffer

## Motivation

Ada's string handling is spread across four library packages — `Ada.Strings.Fixed`,
`Ada.Strings.Bounded`, `Ada.Strings.Unbounded`, and `Ada.Strings.Text_Buffers` —
all of which are excluded from Safe because they require generics (D16), controlled
types, or exceptions. The built-in `String` type (`array (Positive range <>) of
Character`) is retained, but it is fixed-length: you cannot append to it, truncate
it, or build one incrementally.

Every non-trivial program needs mutable strings. Without a library solution, Safe
developers would hand-roll the same record-with-array-and-length pattern repeatedly.
This should be a standard type.

## Proposed Type

**`Safe.String_Buffer`** — a bounded, mutable character buffer with a fixed
maximum capacity set at declaration time.

```
type String_Buffer (Capacity : Buffer_Size) is record {
   Data   : array (1 .. Capacity) of Character = (others = ' ');
   Length : Natural = 0;
}
```

The capacity is a discriminant — no heap allocation, no controlled types, no
generics. The buffer lives on the stack or in a record field, with its maximum
size known at compile time.

## API

All operations use preconditions instead of exceptions. A failed precondition
is a compile-time proof obligation (D27) or a runtime abort — never a catchable
exception.

### Core operations

```
package Safe.String_Buffers {

   public type Buffer_Size is range 1 .. 4096;

   public type String_Buffer (Capacity : Buffer_Size) is record {
      Data   : array (1 .. Capacity) of Character = (others = ' ');
      Length : Natural = 0;
   }

   -- Query
   public function Get_Length (Buf : String_Buffer) returns Natural {
      return Buf.Length;
   }

   public function Get_Char (Buf : String_Buffer; Pos : Positive) returns Character
      pre Pos <= Buf.Length
   {
      return Buf.Data (Pos);
   }

   public function Slice (Buf : String_Buffer;
                          Low : Positive;
                          High : Natural) returns String
      pre Low <= High + 1 and High <= Buf.Length
   {
      return Buf.Data (Low .. High);
   }

   -- Mutation
   public procedure Append (Buf : in out String_Buffer; Ch : Character)
      pre Buf.Length < Buf.Capacity
   {
      Buf.Length = Buf.Length + 1;
      Buf.Data (Buf.Length) = Ch;
   }

   public procedure Append_String (Buf : in out String_Buffer; S : String)
      pre Buf.Length + S'Length <= Buf.Capacity
   {
      Buf.Data (Buf.Length + 1 .. Buf.Length + S'Length) = S;
      Buf.Length = Buf.Length + S'Length;
   }

   public procedure Clear (Buf : in out String_Buffer) {
      Buf.Length = 0;
   }

   public procedure Put_Char (Buf : in out String_Buffer;
                              Pos : Positive;
                              Ch  : Character)
      pre Pos <= Buf.Length
   {
      Buf.Data (Pos) = Ch;
   }

   -- Comparison
   public function Equal (A, B : String_Buffer) returns Boolean {
      return A.Length == B.Length
         and A.Data (1 .. A.Length) == B.Data (1 .. B.Length);
   }

   -- Conversion
   public function To_String (Buf : String_Buffer) returns String {
      return Buf.Data (1 .. Buf.Length);
   }

   public function From_String (S : String; Capacity : Buffer_Size) returns String_Buffer
      pre S'Length <= Capacity
   {
      Result : String_Buffer (Capacity);
      Result.Data (1 .. S'Length) = S;
      Result.Length = S'Length;
      return Result;
   }
}
```

### Usage

```
package Logger {

   Msg : Safe.String_Buffers.String_Buffer (256);

   procedure Build_Message (Code : Integer; Tag : String)
      pre Tag'Length <= 200
   {
      Safe.String_Buffers.Clear (Msg);
      Safe.String_Buffers.Append_String (Msg, "[");
      Safe.String_Buffers.Append_String (Msg, Tag);
      Safe.String_Buffers.Append_String (Msg, "] ");
      -- remaining capacity is provably sufficient
   }
}
```

## Design Rationale

- **No generics** — `String_Buffer` is a concrete type with a discriminant for
  capacity. It is what you'd get after instantiating `Ada.Strings.Bounded` with
  a specific bound, minus the generic machinery.
- **No exceptions** — every operation that could fail has a precondition. The
  compiler proves the precondition holds (D27) or the runtime aborts.
- **No controlled types** — no finalization, no hidden `Adjust`/`Finalize` calls.
  The buffer is a plain record.
- **Copy semantics** — assigning one `String_Buffer` to another copies the data.
  No aliasing, no ownership complications. Consistent with Safe's value semantics
  for non-access types.
- **Discriminant capacity** — the Ada pattern for bounded data structures without
  heap allocation. The size is part of the type's constraint, enabling stack
  allocation and static analysis.

## Alternatives Considered

1. **Heap-allocated resizable string** — like `Ada.Strings.Unbounded`. Requires
   controlled types for automatic deallocation or access-type ownership tracking
   for a string, which is over-engineered for most use cases. Bounded buffers
   cover the common case.

2. **`String` with slice operations only** — the built-in `String` is immutable
   in length. Useful for passing around, but you can't build one incrementally.
   `String_Buffer` fills the gap between "I have a string" and "I'm constructing
   a string."

---

# Bounded Container Types

## Motivation

Ada's container library (`Ada.Containers.*`) is entirely excluded from Safe:
it requires generics (D16), tagged types (D18), controlled types (§12), and
exceptions (D14). SPARK provides a parallel library (`SPARK.Containers.Formal.*`)
with precondition-based APIs, but these are also generic packages.

Without containers, Safe developers must hand-roll every array-with-length,
every search, every sorted collection. This is tedious, error-prone, and the
number one barrier to adoption from any language community.

## Proposed Approach

Provide a small set of **monomorphic bounded container packages** in the Safe
retained library. Each package is what you'd get after instantiating a SPARK
formal container with a specific element type — but written as concrete Safe
code with no generics.

This is explicitly a **v0.3 bridge**. The long-term solution is restricted
generics (proposed for v0.4), which would allow user-defined container
instantiations. The monomorphic containers ship now to unblock real programs.

## Container Types

### Bounded Vector

A contiguous, indexed, variable-length sequence with fixed maximum capacity.

```
package Safe.Integer_Vectors {

   public type Capacity_Range is range 1 .. 10_000;
   public type Index is range 1 .. 10_000;
   public type Count is range 0 .. 10_000;

   public type Vector (Capacity : Capacity_Range) is record {
      Data   : array (1 .. Capacity) of Integer = (others = 0);
      Length : Count = 0;
   }

   public function Get_Length (V : Vector) returns Count {
      return V.Length;
   }

   public function Element (V : Vector; I : Index) returns Integer
      pre I <= V.Length
   {
      return V.Data (I);
   }

   public procedure Append (V : in out Vector; Value : Integer)
      pre V.Length < V.Capacity
   {
      V.Length = V.Length + 1;
      V.Data (V.Length) = Value;
   }

   public procedure Replace_Element (V : in out Vector;
                                     I : Index;
                                     Value : Integer)
      pre I <= V.Length
   {
      V.Data (I) = Value;
   }

   public function Contains (V : Vector; Value : Integer) returns Boolean {
      for I in 1 .. V.Length {
         if V.Data (I) == Value {
            return True;
         }
      }
      return False;
   }

   public procedure Clear (V : in out Vector) {
      V.Length = 0;
   }
}
```

### Bounded Ordered Map

A sorted key-value store with fixed maximum capacity. Keys are unique and
maintained in sorted order for deterministic iteration.

```
package Safe.Integer_Maps {

   public type Capacity_Range is range 1 .. 10_000;
   public type Count is range 0 .. 10_000;

   public type Entry is record {
      Key   : Integer;
      Value : Integer;
   }

   public type Map (Capacity : Capacity_Range) is record {
      Data   : array (1 .. Capacity) of Entry = (others = (Key = 0, Value = 0));
      Length : Count = 0;
   }

   public function Get_Length (M : Map) returns Count {
      return M.Length;
   }

   public function Contains_Key (M : Map; Key : Integer) returns Boolean {
      -- binary search on sorted keys
      Lo  : Integer = 1;
      Hi  : Integer = M.Length;
      Mid : Integer;
      while Lo <= Hi {
         Mid = Lo + (Hi - Lo) / 2;
         if M.Data (Mid).Key == Key {
            return True;
         } elsif M.Data (Mid).Key < Key {
            Lo = Mid + 1;
         } else {
            Hi = Mid - 1;
         }
      }
      return False;
   }

   public function Get (M : Map; Key : Integer) returns Integer
      pre Contains_Key (M, Key)
   {
      -- binary search; precondition guarantees hit
      Lo  : Integer = 1;
      Hi  : Integer = M.Length;
      Mid : Integer;
      while Lo <= Hi {
         Mid = Lo + (Hi - Lo) / 2;
         if M.Data (Mid).Key == Key {
            return M.Data (Mid).Value;
         } elsif M.Data (Mid).Key < Key {
            Lo = Mid + 1;
         } else {
            Hi = Mid - 1;
         }
      }
      return 0;  -- unreachable; precondition ensures key exists
   }

   public procedure Insert (M : in out Map; Key : Integer; Value : Integer)
      pre M.Length < M.Capacity and not Contains_Key (M, Key)
   {
      -- insert in sorted position
      Pos : Integer = M.Length + 1;
      for I in 1 .. M.Length {
         if Key < M.Data (I).Key {
            Pos = I;
            -- shift elements right
            for J in reverse Pos .. M.Length {
               M.Data (J + 1) = M.Data (J);
            }
            -- exit outer loop handled by setting Pos
         }
      }
      M.Data (Pos) = (Key = Key, Value = Value);
      M.Length = M.Length + 1;
   }
}
```

### Initial Library Surface

The v0.3 retained library adds these concrete packages:

| Package | Element Type | Description |
|---------|-------------|-------------|
| `Safe.Integer_Vectors` | `Integer` | Bounded vector |
| `Safe.Natural_Vectors` | `Natural` | Bounded vector |
| `Safe.Integer_Maps` | `Integer` -> `Integer` | Bounded ordered map |
| `Safe.Integer_Sets` | `Integer` | Bounded ordered set |
| `Safe.String_Buffers` | `Character` | Bounded mutable string (see prior section) |

Each follows the same pattern: discriminant capacity, precondition-guarded API,
no generics, no exceptions, no controlled types.

## Design Rationale

- **Ships now** — monomorphic containers are Safe-legal today. No language
  changes required. They're just packages.
- **Preconditions, not exceptions** — `Append` requires `V.Length < V.Capacity`.
  The compiler proves this at call sites (D27). No `Constraint_Error`, no
  hidden control flow.
- **Bounded by default** — fixed capacity via discriminant. No heap allocation
  for the container itself. This matches the safety-critical profile where
  dynamic allocation is restricted or prohibited.
- **Deterministic** — ordered maps and sets use sorted arrays with binary
  search. Iteration order is defined. No hash tables (non-deterministic
  iteration, DoS-vulnerable hash functions).
- **Identical pattern to SPARK formal containers** — the API mirrors
  `SPARK.Containers.Formal.Vectors` and `SPARK.Containers.Formal.Ordered_Maps`,
  minus the generic wrapper. When restricted generics arrive in v0.4, these
  packages become instantiations of a generic rather than hand-written copies.

## Limitations

- **Only covers built-in element types** — a vector of a user-defined record
  requires writing a new package by hand or waiting for v0.4 generics.
- **No linked structures** — bounded containers use contiguous arrays. A bounded
  linked list or tree would require internal cursors (integer indices into a
  node array), which is more complex. Deferred to v0.4.
- **Verbose** — five packages that differ only in element type is the exact
  problem generics solve. This is an acknowledged stopgap.

## Migration Path to Restricted Generics

When restricted generics (v0.4) are available, the monomorphic packages become
thin wrappers or are replaced entirely:

```
-- v0.4: user writes this
type My_Readings is new Safe.Vectors (Element_Type = Sample,
                                       Capacity     = 256);
```

The v0.3 monomorphic API is designed to be a strict subset of what the v0.4
generic API will provide, so migration is mechanical.

---

# Default Capacity Policy

## Motivation

Go programmers write:

```go
name := "hello"
names := []string{}
names = append(names, name)
```

No capacity declaration. No bounds. The runtime handles growth. This is what
makes Go feel effortless for microservice and application development.

Safe's bounded containers and string buffers require explicit capacity:

```
var name : string_buffer (256) = "hello"
var names : integer_vector (64)
append (names, 42)
```

The capacity parameter is valuable for safety-critical and embedded work
where every byte of RAM is accounted for. But for the Go developer writing
a microservice, choosing 256 vs 512 for every string declaration is friction
that delivers no value on a machine with gigabytes of RAM.

The predefined immutable `string` type (PR11.2) already removes this friction
for ordinary text parameters, returns, constants, and literals by letting the
programmer write `string` directly without choosing a buffer capacity. This
proposal extends the same "casual syntax, explicit bounded containers when
needed" pattern to the rest of the bounded container family.

## Proposed Change

Every bounded container type and `string_buffer` has a **default capacity**
that the programmer can omit. The defaults are generous — sized for the
microservice developer, not the embedded developer:

```
-- Go-like: no capacity, defaults apply
const greeting : string = "hello"
var scores : vector (integer)
var cache : map (string, string)

-- Explicit: programmer overrides when they care
var name_buffer : string_buffer (64) = "hello"
var scores : vector (integer, 128)
var cache : map (string, string, 512)
```

Both forms compile. Both are safe. The default-capacity container form uses
generous limits; the explicit form uses exactly what the programmer specifies.

## Default Values

Targeting the Go microservice developer profile — generous, not minimal:

| Type | Default capacity | Memory per instance | Rationale |
|------|-----------------|--------------------|-|
| `string_buffer` | 256 bytes | 256 B | Covers most keys, names, short messages |
| `vector (T)` | 64 elements | 64 * sizeof(T) | Covers most in-memory collections |
| `map (K, V)` | 128 entries | 128 * (sizeof(K) + sizeof(V)) | Covers most lookup tables |
| `set (T)` | 128 elements | 128 * sizeof(T) | Matches map default |

For a program with 100 strings, 20 vectors of integers, and 5 maps of
string-to-string: ~25KB for strings, ~10KB for vectors, ~130KB for maps.
Total: ~165KB. A Go program with equivalent data structures uses ~50KB
of actual data plus 5-10MB of GC runtime. Safe is smaller by two orders
of magnitude even with "wasteful" defaults.

## Compiler-Configurable Defaults

The defaults are compile-time constants, not language constants. The build
configuration can override them:

```toml
# safe.toml (build configuration)
[defaults]
string_capacity = 256
vector_capacity = 64
map_capacity = 128
set_capacity = 128
```

A project targeting embedded hardware overrides with smaller values:

```toml
[defaults]
string_capacity = 32
vector_capacity = 8
map_capacity = 16
set_capacity = 16
```

The granularity question (per-project? per-package? per-type?) is left
open for now. Per-project via build configuration is the minimum viable
design. Finer granularity can be added later if real programs need it.

## Interaction with `pragma Strict`

Under `pragma Strict`, default capacity could optionally be **disabled** —
every container declaration must specify capacity explicitly. This serves
safety-critical teams where certification requires that every buffer size
is a deliberate engineering decision, not a default.

```
pragma Strict;

var name : string                 -- REJECTED: explicit capacity required
var name : string_buffer (64)     -- OK
var scores : vector (integer)     -- REJECTED
var scores : vector (integer, 32) -- OK
```

Whether `pragma Strict` enforces this is a design decision for the PR11.6
evaluation. The option is noted here so the interaction is considered.

## How Guards Work with Default Capacity

When a program might exceed the default capacity, the compiler requires
a guard — the same guards-as-contracts pattern used for all Safe proof
obligations:

```
function collect_names () returns vector (string)
   var names : vector (string)    -- default capacity 64
   for i in 1 to input_count
      if names.length >= 64
         return names              -- guard: capacity reached
      append (names, next_name ())
   return names
```

The compiler proves `append` is safe because the guard ensures
`names.length < 64` on the path that reaches `append`. The programmer
writes a natural bounds check; the compiler uses it as proof context.

If the programmer writes no guard and the compiler cannot prove the
capacity is sufficient, the diagnostic suggests one:

```
collect.safe:5:7: error: cannot prove names.length < capacity
  after append on line 6
  |
  | 5 |      append (names, next_name ())
  |   |      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  |
  help: add a capacity guard before this call:
  |
  | 4 |      if names.length >= 64
  | 5 |         return names
  |
```

## Memory Budget Comparison

For a typical microservice program (100 string variables, 20 vectors of
integer, 5 maps of string-to-string, most partially filled):

| | Go | Safe (default capacity) | Safe (explicit, tight) |
|--|---|------------------------|----------------------|
| String storage | ~10KB data + headers | ~25KB (256B * 100) | ~6KB (64B * 100) |
| Vector storage | ~5KB data + headers | ~10KB (64 * 8B * 20) | ~2KB (8 * 8B * 20) |
| Map storage | ~20KB data + headers | ~130KB (128 * 512B * 5) | ~13KB (16 * 512B * 5) |
| Runtime overhead | 5-10MB (GC, stacks, metadata) | 0 | 0 |
| **Total** | **~5-10MB** | **~165KB** | **~21KB** |

Default-capacity Safe uses 50-60x less memory than Go. Tight-capacity Safe
uses 250-500x less. Both have zero runtime overhead.

## What This Closes

The synthetic dynamic base types proposal (`docs/design-synthetic-dynamic-
base-types.md`) proposed compiler-known magic types with hidden arena
allocation to achieve the Go-like "just works" experience. This default
capacity policy achieves the same developer experience without hidden
allocation: the types are ordinary bounded containers, the capacity is
just pre-chosen. The synthetic types proposal is superseded.

## Design Rationale

- **Go-first onboarding.** A Go programmer writes `var names : vector
  (string)` and it works. No capacity decision on day one.
- **Provably bounded.** Every default-capacity container has a fixed
  maximum size known at compile time. The compiler can prove bounds,
  the linker can compute exact stack usage, and certification reviewers
  can verify memory budgets.
- **No hidden allocation.** Unlike Go's slices or the synthetic types
  proposal, there is no heap growth, no arena, no GC. The container is
  a fixed-size record. What you declare is what you get.
- **Configurable, not magic.** The defaults are build-configuration
  constants, not language magic. Teams override them in `safe.toml`.
  The value is always knowable and auditable.
- **Graceful upgrade path.** When a programmer hits the default limit,
  they either add a guard (immediate fix) or specify a larger capacity
  (deliberate choice). Both are one-line changes. Neither requires
  redesigning the program.

---

# Emitter-Based Container Instantiation

## Motivation

The bounded container types proposal (above) provides monomorphic containers
for built-in element types (`Integer`, `Natural`). The v0.4 restricted generics
proposal (below) adds the `generic` keyword to Safe's grammar. Between these
two points sits a gap: developers who define their own record types (e.g.,
`Sensor_Reading`, `Waypoint`) cannot use bounded containers for those types
until v0.4.

This proposal fills that gap by letting the Safe emitter generate SPARK generic
instantiations in the output, without adding generics to Safe's source language.

## Proposed Change

Introduce **built-in container type constructors** as Safe-level syntax sugar.
The Safe programmer writes a monomorphic type declaration; the emitter lowers
it to a SPARK formal container instantiation.

### Syntax

```
container_type_definition ::=
    'bounded_vector' 'of' element_subtype_mark 'capacity' static_expression
  | 'bounded_map' 'of' key_subtype_mark 'to' value_subtype_mark 'capacity' static_expression
  | 'bounded_set' 'of' element_subtype_mark 'capacity' static_expression
```

### Example

```
package Telemetry {

   type Sample is record {
      Timestamp : Integer;
      Value     : Float;
   }

   type Sample_Buffer is bounded_vector of Sample capacity 256;

   type Config_Map is bounded_map of Integer to Sample capacity 64;
}
```

### What the emitter produces

For `type Sample_Buffer is bounded_vector of Sample capacity 256;`, the emitter
generates:

```ada
-- emitted Ada
with SPARK.Containers.Formal.Vectors;
package Sample_Buffer_Pkg is new SPARK.Containers.Formal.Vectors
   (Index_Type   => Positive,
    Element_Type => Telemetry.Sample);
subtype Sample_Buffer is Sample_Buffer_Pkg.Vector (256);
```

The generated code is a standard SPARK generic instantiation. GNATprove
verifies client usage against the SPARK formal container contracts — the same
contracts that the monomorphic v0.3 containers are modeled after.

### Operations

Container operations are accessed through the generated package name, matching
the monomorphic container API:

```
procedure Collect (Buf : in out Sample_Buffer; S : Sample)
   pre Get_Length (Buf) < 256
{
   Append (Buf, S);
}
```

The compiler maps `Append`, `Element`, `Get_Length`, `Contains`, `Clear`, etc.
to the corresponding operations in the instantiated SPARK package.

## Design Rationale

- **No `generic` keyword in Safe source.** D16 is preserved in the source
  language. Generics exist only in emitted Ada — the same principle used for
  `Ada.Unchecked_Deallocation` in the ownership system.
- **Works for user-defined element types.** Unlike the monomorphic containers,
  `bounded_vector of My_Record` works for any Safe-legal record type.
- **Closed vocabulary.** Only the built-in container kinds (`bounded_vector`,
  `bounded_map`, `bounded_set`) are supported. Users cannot define new generic
  containers — that requires v0.4 restricted generics.
- **Mechanical migration to v0.4.** When restricted generics arrive, the
  built-in constructors become syntax sugar over user-visible generic
  instantiation:

  ```
  -- v0.3 (emitter-based)
  type Sample_Buffer is bounded_vector of Sample capacity 256;

  -- v0.4 (explicit generic instantiation)
  package Sample_Vectors is new Safe.Bounded_Vectors (Element_Type = Sample);
  subtype Sample_Buffer is Sample_Vectors.Vector (256);
  ```

  Both forms can coexist. The built-in constructors can be retained as
  convenient shorthand even after generics are available.

## Interaction with Other Proposals

- **Bounded container types (this document):** The monomorphic containers
  (`Safe.Integer_Vectors`, etc.) remain for built-in element types. The
  emitter-based constructors extend coverage to user-defined types.
- **v0.4 restricted generics:** The constructors are a stepping stone. They
  prove the emitter can handle SPARK generic instantiations before Safe's
  grammar gains the `generic` keyword.
- **D27 proof obligations:** Preconditions on container operations flow through
  the SPARK instantiation. `Append` requires `Length < Capacity` — the same
  proof obligation as the monomorphic version.
- **Ownership (D17):** For v0.3, element types must have copy semantics (no
  access-type components). This matches the v0.4 generics restriction.

## Limitations

- **Depends on SPARKlib.** The emitted Ada imports
  `SPARK.Containers.Formal.*`. The SPARK library must be available in the
  build environment.
- **Closed set of containers.** Only vector, map, and set are provided.
  A ring buffer, priority queue, or other structure requires either a
  monomorphic hand-written package or v0.4 generics.
- **No customization.** Hash functions, comparison operators, and equivalence
  relations are inferred from the element type. User-supplied comparators
  require formal subprogram parameters, which are excluded until v0.4 or later.

## Alternatives Considered

1. **Skip directly to v0.4 generics.** Faster path to full generality but
   leaves v0.3 with containers only for built-in types. The emitter-based
   approach buys time while the `generic` keyword design is finalized.

2. **Hand-write monomorphic containers for every user type.** The compiler
   could auto-generate a `My_Record_Vectors` package for each type that
   appears in a container declaration. This avoids depending on SPARKlib
   but requires the Safe compiler to contain a container implementation
   template — effectively a code generator for data structures.

## Supporting Reference

Background on SPARK formal-container compatibility now lives in
[SPARK Container Library Compatibility Analysis](spark_container_compatibility.md).

---

# Three-Tier Integer Model

## Motivation

Ada's predefined integer types have implementation-defined ranges. `Integer`
might be 16-bit on one target and 32-bit on another. `Long_Integer` may or
may not exist. `Short_Integer` is optional. This forces Ada developers into
one of two bad patterns:

1. **Use `Integer` everywhere** and hope the target gives you enough range
   (fragile, non-portable).
2. **Declare range types for everything** even when you don't care about
   bounds (verbose, ceremony).

Safe already has a decisive advantage: D27 Rule 1 mandates wide intermediate
arithmetic bounded at 64-bit signed. Every Safe program lives in a world
where intermediate math can't overflow within -(2^63) .. (2^63 - 1). That
means Safe can make a much bolder choice than Ada did.

## Proposed Change

Replace Ada's implementation-defined integer hierarchy with a fixed,
portable, three-tier model.

### Tier 1: One default integer type, always 64-bit signed

```
type Integer is range -(2**63) .. (2**63 - 1);  -- always, on every target
```

No `Long_Integer`. No `Short_Integer`. No `Long_Long_Integer`. No
implementation-defined ranges. One type, one range, portable everywhere.
This directly matches D27's 64-bit bound — the widest integer you can
compute with is the default integer.

`Natural` and `Positive` remain as subtypes:

```
subtype Natural  is Integer range 0 .. Integer'Last;
subtype Positive is Integer range 1 .. Integer'Last;
```

**Rationale:** D27 already caps everything at 64-bit. Making `Integer`
narrower than the intermediate arithmetic range creates a pointless gap
where expressions succeed but assignments fail for no domain reason. Go
made `int` 64-bit. Zig made `i64` the common choice. Safe should too.

### Tier 2: Fixed-width types for storage and hardware interfaces

Provided as predefined types in `Standard` (not in a library package, not
generic):

```
type Integer_8   is range -(2**7)  .. (2**7  - 1);
type Integer_16  is range -(2**15) .. (2**15 - 1);
type Integer_32  is range -(2**31) .. (2**31 - 1);
type Integer_64  is range -(2**63) .. (2**63 - 1);  -- same range as Integer

type Unsigned_8  is mod 2**8;
type Unsigned_16 is mod 2**16;
type Unsigned_32 is mod 2**32;
type Unsigned_64 is mod 2**64;
```

These exist for **storage efficiency and hardware register mapping**, not
for arithmetic precision. When you're packing a struct for a network
protocol or a memory-mapped register, you need exactly 16 bits, not
"whatever the compiler thinks is efficient."

In Ada, you'd get these from `Interfaces` (as `Interfaces.Integer_8`, etc.)
or declare your own range types and hope `'Size` works out. Safe provides
them directly.

**Key property:** Arithmetic between these types and `Integer` uses D27
wide intermediates. The range check happens at the narrowing point
(assignment back to an `Integer_16` variable). No surprise truncation, no
silent overflow.

### Tier 3: Domain range types (unchanged from current spec)

```
type Sensor_Reading is range 0 .. 4095;
type Temperature_C  is range -40 .. 125;
type Channel_Id     is range 0 .. 7;
```

This is where Safe's static analysis shines. The range is the contract.
`(A + B) / 2` where both are `Sensor_Reading` provably fits back in
0 .. 4095 without any annotation. This mechanism already works well —
keep it exactly as-is.

## Examples

### Mixed-width arithmetic

```
package Sensor_Protocol {

   type Header is record {
      Version  : Unsigned_8;
      Msg_Type : Unsigned_8;
      Length   : Unsigned_16;
      Sequence : Unsigned_32;
   }

   function Checksum (H : Header) returns Unsigned_8 {
      -- Arithmetic in 64-bit intermediate, narrowed at assignment
      Sum : Integer = Integer (H.Version)
                    + Integer (H.Msg_Type)
                    + Integer (H.Length)
                    + Integer (H.Sequence);
      return Unsigned_8 (Sum mod 256);
   }
}
```

### Array indexing with default Integer

```
package Data_Processing {

   type Reading is range 0 .. 65535;
   type Buffer is array (1 .. 1024) of Reading;

   function Average (B : Buffer) returns Reading {
      Sum   : Integer = 0;  -- 64-bit, no overflow risk for 1024 * 65535
      Count : Integer = B'Length;

      for I in B'Range {
         Sum = Sum + Integer (B (I));
      }
      return Reading (Sum / Count);
   }
}
```

### Hardware register mapping

```
package GPIO_Controller {

   type Register is record {
      Direction : Unsigned_32;
      Output    : Unsigned_32;
      Input     : Unsigned_32;
      Interrupt : Unsigned_32;
   }

   procedure Set_Pin (Reg : in out Register; Pin : Integer_8)
      pre Pin >= 0 and Pin <= 31
   {
      Reg.Output = Reg.Output or Unsigned_32 (2 ** Natural (Pin));
   }
}
```

## What This Eliminates

| Ada pain point | Safe solution |
|----------------|--------------|
| "What's the range of `Integer` on my target?" | Always 64-bit signed. No guessing. |
| `Long_Integer` / `Short_Integer` / `Long_Long_Integer` | Gone. Use `Integer` or a fixed-width type. |
| `Interfaces.Integer_16` requires `with Interfaces;` | `Integer_16` is in `Standard`, always visible. |
| Declaring `type My_Int is range 0 .. 255;` then fighting with `'Size` for storage | Use `Unsigned_8` when you want 8-bit storage. Use a range type when you want range analysis. Intent is clear. |
| Mixing `Natural` and `Positive` in arithmetic requires understanding subtype rules | Still subtypes, but the base type is always 64-bit, so the intermediate arithmetic is always fine. |

## What This Resolves

- **TBD-10 (Numeric Model for Predefined Integer Types):** Resolved. `Integer`
  is always 64-bit. No minimum range question to answer.

- **TBD-12 (Modular Arithmetic Wrapping):** Partially addressed. The
  `Unsigned_*` types are modular (wrapping). Whether non-wrapping should be
  the default for user-declared `mod` types is a separate question — but the
  predefined `Unsigned_8`/`16`/`32`/`64` should wrap, because their purpose is
  hardware-level bit manipulation where wrapping is expected.

- **D27 Rule 1 (64-bit bound):** The proposal is designed around this rule.
  `Integer` fills the entire proof-engine range. Fixed-width types are strict
  subsets. Domain range types are strict subsets. Everything narrows from
  `Integer`, never widens beyond it.

## Storage Representation

Safe needs a way to say "this record field occupies exactly 16 bits." The
fixed-width types give that directly via their type, without needing
representation clauses in simple cases. For record layout, `Integer_16` has
a natural size of 16 bits — the compiler should use it without requiring
`for X'Size use 16`.

For cases where explicit layout control is needed (hardware registers,
protocol headers), representation clauses remain available per §2.1.12 of
the spec.

## Design Rationale

- **Portable by default** — a Safe program using `Integer` produces identical
  results on every target. No `#ifdef` equivalents, no target-specific range
  workarounds.
- **Reads as expected** — `x : Integer = 42;` works. `buf : array (1..4) of
  Unsigned_8;` works. `id : Integer_32 = 0;` works. No imports, no range
  declarations, no target documentation.
- **D27-aligned** — `Integer` fills the proof engine's range exactly. No gap
  between "what I can compute" and "what I can store in the default type."
- **Minimal** — three tiers, each with a clear purpose. Default arithmetic
  (`Integer`), storage/hardware (`Integer_N`/`Unsigned_N`), domain contracts
  (range types). No fourth category needed.

## Alternatives Considered

1. **Keep Ada's implementation-defined model** — portable Safe programs would
   need to declare `type My_Integer is range -(2**63) .. (2**63 - 1);`
   explicitly. This is what the spec currently implies. It works but pushes
   portability onto every developer.

2. **Provide only `Integer` (no fixed-width types)** — rely on `'Size`
   representation clauses for storage control. This is Ada-idiomatic but
   requires developers to know the representation clause mechanism for
   basic hardware interfacing.

3. **Rust-style naming (`i8`, `i16`, `u32`, etc.)** — concise but inconsistent
   with Safe's Ada heritage and word-based naming philosophy (`in out` not
   `&mut`, `access` not `*`).

## Required Companion: Wide-Intermediate Overflow Checking

**This section describes work that MUST ship with the Three-Tier Integer
Model. Implementing one without the other creates a soundness hole in
Silver.**

### The problem

The Safe spec defines intermediate arithmetic as operating on "mathematical
integers" — unbounded, no overflow. The implementation approximates this
with 64-bit `Wide_Integer`. Today, `Integer` is narrower than `Wide_Integer`
(typically 32-bit), so the 64-bit intermediate has headroom and overflow is
unlikely.

The Three-Tier Model makes `integer` 64-bit — the same width as
`Wide_Integer`. At that point there is zero headroom. Any arithmetic that
could exceed 64-bit range overflows the implementation's intermediate, but
the compiler's Silver analysis only checks overflow at **narrowing points**
(wide → narrow conversion). When both operands and the result are `integer`,
there is no narrowing point, and the overflow is undetected.

### Example

```
function sum_range (lo, hi : integer) returns integer {
   total : integer = 0
   for i in lo .. hi {
      total = total + i
   }
   return total
}
```

Silver does not reject this today. But if `hi` is `integer'last`, the
running `total` overflows 64-bit signed range. The "can't crash" guarantee
has a silent exception.

### The fix

Extend the Silver analyzer's existing interval tracking to check every
arithmetic expression against the `Wide_Integer` range, not just at explicit
narrowing points. The machinery already exists — the analyzer computes
intervals for every expression. The change is one additional check: if the
computed interval of any arithmetic result exceeds -(2^63) .. (2^63 - 1),
emit a diagnostic.

For accumulating loops, the analyzer's interval for `total` grows without
bound across iterations. The check rejects the program unless the developer
bounds the loop range or uses a narrower accumulator:

```
type counter is range 0 .. 1_000_000

function sum_range (lo, hi : counter) returns integer {
   total : integer = 0
   for i in lo .. hi {
      total = total + integer (i)
   }
   return total
}
```

Now the compiler knows: at most 1,000,000 iterations, each adding at most
1,000,000. Maximum `total` is 10^12, which fits in 64-bit. Silver proves it.

### Why they are coupled

| Scenario | Without Three-Tier | With Three-Tier, without this fix |
|---|---|---|
| `integer + integer` | Lifted to 64-bit `Wide_Integer`; 32-bit operands can't overflow 64-bit | Both operands are already 64-bit; sum can overflow with no check |
| Silver guarantee | Sound (headroom protects) | **Unsound** (no headroom, no check) |

The Three-Tier Model must not ship without wide-intermediate overflow
checking. They are a single atomic change to the language's soundness model.

### Relationship to TBD-10

TBD-10 in `spec/00-front-matter.md` §0.8 asks: "Numeric model: required
ranges for predefined integer types." The Three-Tier Model resolves TBD-10
by fixing `Integer` at 64-bit. This companion fix ensures the resolution
does not weaken Silver.

---

# Discriminant-Constrained Dispatch

## Motivation

Developers coming from Go, Rust, Java, or C# expect some form of interface
or trait mechanism for polymorphic code. D18 excludes tagged types, dynamic
dispatch, vtables, and runtime type identification — but the desire for
cleaner polymorphic patterns remains.

Safe already has discriminated record types, which serve as closed variant
types (sum types). The concept is sound, but the ergonomics are painful:
every function that operates on a variant type needs a full `case` statement
even for trivial per-variant logic. This proposal addresses the ergonomic
problem directly, without introducing new type system concepts.

## Alternatives Evaluated

Three approaches were considered before arriving at the recommended design.

### Option A: Discriminated dispatch (status quo)

This is what Safe already has. You enumerate variants in a discriminant and
case-match:

```
type Shape_Kind is (Circle, Rectangle);
type Shape (Kind : Shape_Kind) is record {
   case Kind is
      when Circle    => Radius : Float;
      when Rectangle => Width, Height : Float;
   end case;
}

function Area (S : Shape) returns Float {
   case S.Kind is
      when Circle    => return 3.14159 * S.Radius ** 2;
      when Rectangle => return S.Width * S.Height;
   end case;
}
```

This is **closed** — adding a new variant means modifying the type and every
`case`. But it's fully static, provable, and requires no new language
machinery. The only problem is ergonomics.

### Option B: Named interface types with explicit conformance

```
interface Measurable is
   function Area (Self : Measurable) returns Float;
   function Perimeter (Self : Measurable) returns Float;
end interface;

type Circle is record conforms Measurable {
   Radius : Float;
}

function Area (Self : Circle) returns Float {
   return 3.14159 * Self.Radius ** 2;
}
```

**Why this is tractable:** no vtable (conformance checked at compile time),
no dynamic dispatch, compatible with dot notation, compatible with ownership.

**Why it's not worth it:** the value of interfaces is polymorphic code —
writing one function that works on any `Measurable`. Without dynamic dispatch
or generics, you can't write:

```
function Total_Area (Shapes : array of Measurable) returns Float;
```

because `array of Measurable` requires either a heterogeneous container
(needs tagged types) or monomorphisation (needs generics). Interfaces that
only check conformance but don't enable polymorphic call sites are just
documentation — useful, but not what Go/Java/C# developers mean by
"interfaces."

### Option C: Discriminant-constrained function overloading (recommended)

This is the recommended approach. See the full design below.

## Proposed Change

Add **discriminant-constrained parameter syntax** to function declarations,
enabling pattern-matched function overloading on discriminant values.

### Grammar Extension

```
parameter_declaration ::=
    defining_identifier ':' [mode] subtype_mark
  | defining_identifier ':' [mode] subtype_mark 'when' discriminant_value
```

The `when` clause constrains the parameter to a specific discriminant value.
The compiler treats the set of overloaded functions as a single dispatch
point.

### Example

```
type Shape_Kind is (Circle, Rectangle);
type Shape (Kind : Shape_Kind) is record {
   case Kind is
      when Circle    => Radius : Float;
      when Rectangle => Width, Height : Float;
   end case;
}

function Area (S : Shape when Circle) returns Float {
   return 3.14159 * S.Radius ** 2;
}

function Area (S : Shape when Rectangle) returns Float {
   return S.Width * S.Height;
}
```

The caller writes `Area(My_Shape)` and the compiler generates a case
dispatch. No vtable, no tags, no runtime cost — it's a syntactic
transformation to the existing `case` semantics.

### Compiler Responsibilities

1. **Exhaustiveness checking** — every discriminant value must have a
   matching clause. If a new variant is added to `Shape_Kind`, every
   discriminant-constrained function set must be extended or the program
   is rejected. This is the same guarantee Rust provides for `match` on
   enums.

2. **Static resolution** — the generated dispatch is equivalent to an
   inline `case` statement. There is no indirect call, no function pointer,
   no runtime type lookup.

3. **Signature consistency** — all overloads in a set must have identical
   return types and identical non-constrained parameters. The only
   difference is the `when` clause and the variant-specific fields
   accessible on the constrained parameter.

4. **Field visibility** — within a `when Circle` overload, `S.Radius` is
   directly accessible without a `case` statement. The discriminant
   constraint narrows the type, just as a `when` arm does in a `case`.

## Examples

### Multi-function dispatch

```
type Message_Kind is (Text, Image, Video);
type Message (Kind : Message_Kind) is record {
   Sender    : User_Id;
   Timestamp : Time;
   case Kind is
      when Text  => Content : Bounded_String (256);
      when Image => Width, Height : Positive; Data : Image_Buffer;
      when Video => Duration : Duration; Stream : Stream_Handle;
   end case;
}

function Render (M : Message when Text) returns Display_Element {
   return Text_Box (M.Content, M.Sender, M.Timestamp);
}

function Render (M : Message when Image) returns Display_Element {
   return Image_Frame (M.Data, M.Width, M.Height);
}

function Render (M : Message when Video) returns Display_Element {
   return Video_Player (M.Stream, M.Duration);
}

function Size_Bytes (M : Message when Text) returns Integer {
   return M.Content'Length;
}

function Size_Bytes (M : Message when Image) returns Integer {
   return M.Width * M.Height * 4;  -- RGBA
}

function Size_Bytes (M : Message when Video) returns Integer {
   return Integer (M.Duration * 1_000_000);  -- estimate
}
```

### Mixed constrained and unconstrained

```
-- This function works on any Shape — no constraint
function Describe (S : Shape) returns Bounded_String (64) {
   return "Shape with kind " & Shape_Kind'Image (S.Kind);
}

-- These are constrained
function Area (S : Shape when Circle) returns Float { ... }
function Area (S : Shape when Rectangle) returns Float { ... }
```

Both patterns coexist. Unconstrained functions handle the general case;
constrained overloads handle per-variant logic.

## Why This Design

- **Uses existing machinery.** Discriminated types already work. This is
  sugar over `case`, not a new type system concept.

- **Closedness is a feature.** In safety-critical code, you want the
  compiler to force you to handle every variant. Open extension (adding a
  new shape without modifying existing code) is a liability when you need
  exhaustive analysis.

- **Familiar.** Rust developers recognise this as `match` on enums with
  associated data. Haskell developers recognise it as pattern matching on
  sum types. Go developers will see it as a type switch without the
  interface indirection.

- **Exhaustiveness checking is provable.** The compiler guarantees at
  compile time that every discriminant value is handled — no `default` arm
  that silently drops new variants.

- **Doesn't break D18.** No tagged types, no dynamic dispatch, no vtables,
  no runtime type identification. Dot notation stays unambiguous.

## Implementation Cost

One new grammar production (discriminant-constrained parameter) and
exhaustiveness checking logic in the compiler. Both are tractable for the
frontend team given the existing discriminant infrastructure.

The desugaring is mechanical: a set of constrained overloads for function
`F` with discriminant type `K` having values `V1, V2, ..., Vn` is
equivalent to:

```
function F (Param : Type) returns R {
   case Param.Kind is
      when V1 => -- body of F (Param : Type when V1)
      when V2 => -- body of F (Param : Type when V2)
      ...
      when Vn => -- body of F (Param : Type when Vn)
   end case;
}
```

## What This Does Not Solve

This proposal does not address **open extension** — the ability to add new
variants without modifying the original type or existing functions. In a
safety-critical language, that's arguably the right tradeoff: closed variant
types with exhaustive matching are the safer primitive.

If open extension is needed later, it can be layered on top — perhaps via
TBD-13's cross-package type views — without committing to full OOP now.

## Interaction with Other Proposals

- **D18 (No tagged types):** Fully compatible. This proposal adds no
  runtime type information and no dynamic dispatch.

- **TBD-13 (Limited/private type views):** A future cross-package extension
  mechanism could allow packages to add variants to a discriminated type,
  with the compiler enforcing exhaustiveness across package boundaries. This
  is a natural evolution path that doesn't require interfaces.

- **Brace syntax (this document):** The examples above use the proposed
  brace syntax. The discriminant-constrained parameter syntax is orthogonal
  to block delimiters.

- **Restricted generics:** When generics arrive, constrained parameters compose
  naturally — a generic function can accept any type that has a discriminant,
  and the constrained overloads work within the generic instantiation.

---

## Open Questions

1. **Should `record` use braces too?** The examples above show `record { ... }`
   which reads cleanly, but `type Node is record { ... }` is a longer line.
   Alternative: `type Node is { ... }` (drop `record` keyword entirely).

2. **Bare `loop` in a safety-focused language** — if Safe requires provable
   termination for most code, bare `loop` may only appear in task bodies.
   Should it be restricted to that context?

3. **Semicolons after closing braces** — the examples above omit them (C-style).
   Should `};` be required for consistency with other declarations?

4. **Scoped binding on `receive`** — the `select` arm grammar already declares
   and scopes a variable in one construct (`when Msg : T from Ch then`), but
   `receive` does not. This asymmetry is the root cause of the §97a
   null-before-move trap in loops: developers declare the target outside the
   loop, and the second `receive` overwrites a non-null variable — a
   compile-time rejection that is not obvious from the syntax. (The existing
   test `tests/concurrency/try_send_ownership.safe` contained exactly this
   bug in its `Receiver` task.)

   A one-line grammar extension would make §97a compliance structural:

   ```
   receive_statement ::=
       'receive' channel_name ',' name ';'
     | 'receive' channel_name ',' defining_identifier ':' subtype_mark ';'
   ```

   The second form declares the variable at the `receive` point, scoped to
   the enclosing block. Combined with the brace syntax, the idiomatic loop
   becomes:

   ```
   loop {
       receive Data_Ch, Item : Payload_Ptr;
       if Item != null {
           Item.all.Value = 0;
       }
   }   -- Item goes out of scope; auto-deallocation
   ```

   This eliminates the nonconforming pattern by construction — there is no
   way to write a `receive` into a pre-existing non-null variable when using
   the binding form. The non-binding form (`receive Ch, Var;`) is retained
   for cases where the variable must survive across iterations (non-owning
   types where §97a does not apply).

   The same extension applies to `try_receive`:

   ```
   try_receive_statement ::=
       'try_receive' channel_name ',' name ',' name ';'
     | 'try_receive' channel_name ',' defining_identifier ':' subtype_mark ',' name ';'
   ```

   For `try_receive`, the declared variable is null when `Success` is `False`
   (no move occurred) and non-null when `Success` is `True`, consistent with
   the existing §30 semantics.

   **Tradeoff:** this adds a second grammar production to two statements.
   The benefit is that the most common ownership-safe pattern (receive in a
   loop) becomes a single statement instead of a declaration-then-receive
   pair, and the compiler can enforce §97a structurally rather than relying
   solely on flow analysis.

---

# `to` Range Keyword

Status: implemented in PR11.4 as a cutover. `to` is the only accepted
source-level inclusive-range spelling; legacy `..` is rejected in Safe source.

## Motivation

Safe's current range syntax uses `..` from Ada:

```
for Step in 2 .. N loop
```

The `..` operator is a convention inherited from Ada, Pascal, and Rust. Every
programmer has to learn that `..` means "through." It is not self-documenting
to a reader encountering the syntax for the first time — a safety auditor,
domain expert, or regulator reviewing code.

Safe optimizes for reading, not writing. The language already uses full English
words (`function`, `returns`, `boolean`, `integer`, `constant`, `access`)
rather than abbreviations or symbols. A range delimiter should follow the same
principle.

## Proposed Change

Replace `..` with the keyword `to` in range expressions:

```
for step in 2 to n
```

The `to` keyword is recognized by the lexer in range position (after `in
<expr>` in a `for` header, and in type range declarations). It replaces `..`
as the inclusive-range delimiter throughout the language.

### In `for` loops

```
-- Current
for Step in 2 .. N loop

-- Proposed
for step in 2 to n
```

### In type declarations

```
-- Current
type Count is range 1 .. 12;

-- Proposed
type count is range 1 to 12
```

### In array index types

```
-- Current
type Index is range 0 .. 255;
type Buffer is array (Index) of Element;

-- Proposed
type index is range 0 to 255
type buffer is array (index) of element
```

## Parser Impact

Minimal. The lexer adds `to` as a keyword token. The parser replaces the `..`
token expectation with `to` in range productions. The AST representation is
unchanged — a range is still (lower_bound, upper_bound, inclusive).

`to` is not a useful identifier name in Safe programs. It does not conflict
with any existing keyword, operator, or standard library name.

## Emitter Mapping

The emitter produces Ada `..` from the range AST node regardless of whether
the source used `to`. The Safe-to-Ada mapping is trivial: `2 to n` emits as
`2 .. N`. No downstream tooling change is needed.

## Readability Comparison

```
-- Current Safe
type Cell is range -1_000_000 .. 1_000_000;
for I in Row_Index loop

-- Proposed Safe
type cell is range -1_000_000 to 1_000_000
for i in row_index

-- Ada (what the emitter produces regardless)
type Cell is range -1_000_000 .. 1_000_000;
for I in Row_Index loop
```

The Safe source reads as English. The emitted Ada uses Ada conventions. The
emitter bridges the gap.

## Design Rationale

- **Reads as a sentence.** `for step in 2 to n` is five English words with
  unambiguous meaning. `for step in 2 .. n` requires knowing the `..`
  convention.
- **Consistent with the language's word-over-symbol philosophy.** Safe uses
  `and then` not `&&`, `or else` not `||`, `not` not `!`, `access` not `*`.
  Using `to` instead of `..` follows the same pattern.
- **Zero ambiguity cost.** The parser knows it's in a range position. `to`
  cannot be confused with anything else in that context.
- **Trivial migration.** Mechanical find-and-replace of `..` with `to` in
  range contexts. No semantic analysis needed for the migration tool.

## Alternatives Considered

1. **Keep `..`** — status quo. Familiar to Ada/Rust/Pascal programmers but
   opaque to non-programmers reading the code.

2. **`through`** — more explicit than `to` but longer. `1 through 12` reads
   well; `1 to 12` reads equally well and is shorter.

3. **`..=` (Rust inclusive) vs `..` (Rust exclusive)** — Safe only has
   inclusive ranges. There is no exclusive-range ambiguity to resolve, so the
   Rust distinction is unnecessary.

---

# Optional Semicolons

## Motivation

Safe already uses braces for block delimiters, `=` for assignment, and `returns`
for function signatures — each reducing ceremony inherited from Ada. Semicolons
are the next candidate. In a brace-delimited language, the semicolon's
block-structuring role is redundant; its only remaining job is separating
consecutive statements on the same line or across lines.

Go demonstrates that semicolons can be eliminated from source without
ambiguity by having the lexer insert them automatically based on line-ending
tokens.

## Proposed Change

Make semicolons **optional** in Safe source by adopting Go-style automatic
semicolon insertion in the lexer.

### Insertion rule

After lexing a line, if the final token is one of the following, the lexer
inserts a semicolon:

- an identifier (including type names and keywords used as values: `True`,
  `False`, `null`)
- a numeric or string literal
- `)`, `]`, or `}`
- the keywords `return`, `end`

All other line-ending tokens (operators, `,`, `(`, `{`, `is`, `then`, `else`,
`elsif`, `loop`) do **not** trigger insertion, allowing statements to be
broken across lines after those tokens.

### What this enables

```
-- Semicolons omitted
package Safe_Return {

   type Bounded is range -500 .. 500
   type Small is range -10 .. 10

   function Signum (V : Bounded) returns Small {
      if V > 0 {
         return 1
      } elsif V < 0 {
         return -1
      } else {
         return 0
      }
   }

   function Bounded_Add (A, B : Small) returns Bounded {
      return Bounded (A) + Bounded (B)
   }

}
```

Explicit semicolons remain legal everywhere — existing code does not break.

### Multi-line expressions

The insertion rule means a line can only be continued **after** an operator or
opening delimiter. This is the same constraint Go enforces:

```
-- Valid: break after operator
Total = Base_Amount
   + Tax
   + Shipping

-- Invalid: break before operator (lexer inserts semicolon after Base_Amount)
Total = Base_Amount
   + Tax
```

This constrains formatting style but eliminates parsing ambiguity without
requiring an explicit line-continuation character.

## Design Rationale

- **Backward compatible** — semicolons are still accepted. No existing code
  breaks. Teams that prefer explicit semicolons can continue using them.
- **Proven model** — Go has used automatic semicolon insertion since 2009 with
  no reported ambiguity issues. The rule is simple enough for developers to
  internalise quickly.
- **Reduces visual noise** — in brace-delimited code, semicolons after `}`
  and before `}` are pure ceremony. Removing them produces cleaner code.
- **Mechanical formatting** — `safe fmt` can strip or restore semicolons
  deterministically, just as `gofmt` does.
- **No grammar ambiguity** — the insertion rule is purely lexical. The parser
  sees the same token stream regardless of whether the developer wrote the
  semicolons or the lexer inserted them.

## Interaction with `pragma Strict`

Under `pragma Strict`, the language uses Ada-style `begin`/`end` delimiters
where semicolons are syntactically required in more positions (e.g.,
`end loop;`, `end Package_Name;`). Two options:

1. **Semicolons remain required under `pragma Strict`** — strict mode is
   explicitly about more rigorous syntax, so requiring semicolons fits.
2. **Auto-insertion applies under both modes** — the insertion rule handles
   `end` as a triggering token, so `end loop` at end-of-line would get an
   auto-inserted semicolon.

Option 1 is recommended: `pragma Strict` keeps semicolons mandatory,
reinforcing the "explicit everything" philosophy of strict mode.

## Alternatives Considered

1. **Newline-as-terminator (Python/Ruby)** — makes semicolons an error rather
   than optional. Too aggressive; breaks backward compatibility and prevents
   multiple statements per line.

2. **Explicit line continuation (`\` or `_`)** — adds a new token for
   multi-line statements instead of relying on lexer rules. More ceremony,
   not less.

3. **Status quo (always required)** — safe and simple, but leaves Safe with
   more ceremony than any C-family language for no parsing benefit in
   brace-delimited mode.

---

# `else if` Keyword

Status: implemented in PR11.4 as a cutover. `else if` is the only accepted
conditional-chain spelling; legacy `elsif` is rejected.

## Motivation

Safe inherits `elsif` from Ada. In a brace-delimited language, `elsif` is an
outlier — every C-family language uses `else if` as two separate tokens.
With braces, `} else if cond {` reads naturally and requires no special
compound keyword.

## Proposed Change

Replace `elsif` with `else if` throughout the grammar.

### Brace syntax (default)

```
if v > 0 {
   return 1
} else if v < 0 {
   return -1
} else {
   return 0
}
```

### Under `pragma Strict`

```
if V > 0 then
   return 1;
else if V < 0 then
   return -1;
else
   return 0;
end if;
```

Under strict mode, `else if ... then` replaces `elsif ... then`. The closing
`end if;` applies once to the entire chain, not per branch — the same
semantics as the current `elsif` chain.

## Design Rationale

- **Familiar** — `else if` is universal across C, Go, Rust, Swift, Python,
  JavaScript, and every mainstream language except Ada and its descendants.
- **No ambiguity** — in both brace and strict modes, the parser treats
  `else if` as an else-clause containing a nested if. The semantics are
  identical to `elsif`.
- **One fewer keyword** — `elsif` is removed from the reserved word list.
  `else` and `if` are already reserved.
- **Mechanical migration** — `elsif` → `else if` is a global find-replace
  with no semantic change.

## Alternatives Considered

1. **Keep `elsif`** — preserves Ada compatibility. But Safe has already
   departed from Ada syntax in multiple ways (braces, `=` for assignment,
   `returns`, `==` for equality). `elsif` is not carrying its weight.

2. **Support both `elsif` and `else if`** — avoid a breaking change. But
   permitting two spellings of the same construct invites style inconsistency
   and complicates the grammar for no benefit.

---

# Simplified Predefined Type Names

## Motivation

The Three-Tier Integer Model (proposed earlier in this document) introduces
fixed-width types named `Integer_8`, `Integer_16`, `Integer_32`, `Integer_64`
and `Unsigned_8`, `Unsigned_16`, `Unsigned_32`, `Unsigned_64`. These names are
precise but verbose, and they read as Ada library types rather than language
primitives.

Every mainstream language provides short, familiar names for its built-in
integer types:

| Language | 8-bit unsigned | 16-bit signed | 32-bit signed | 64-bit signed |
|----------|---------------|---------------|---------------|---------------|
| Go       | `byte`        | `int16`       | `int32`       | `int64`       |
| Java/C#  | `byte`        | `short`       | `int`         | `long`        |
| Rust     | `u8`          | `i16`         | `i32`         | `i64`         |

Safe's "words over symbols" philosophy (`in out` not `&mut`, `access` not `*`)
favours the Java/C# style over the Rust style. But Safe's integer model
differs from Java's in one important way: the default `integer` is always
64-bit (matching the D27 wide intermediate range), not 32-bit.

## Proposed Change

Add short predefined names as built-in aliases for the fixed-width types.
The full `Integer_N`/`Unsigned_N` names remain available.

### Signed types

| Short name | Alias for | Range |
|------------|-----------|-------|
| `integer`  | `Integer` (Tier 1) | -(2^63) .. (2^63 - 1) |
| `short`    | `Integer_16` | -(2^15) .. (2^15 - 1) |

### Unsigned types

| Short name | Alias for | Range |
|------------|-----------|-------|
| `byte`     | `Unsigned_8` | 0 .. 255 |

### What is NOT aliased

| Full name | Reason |
|-----------|--------|
| `Integer_8` | Signed 8-bit is rare; `byte` covers the unsigned case |
| `Integer_32` | Use `integer` (64-bit) for general arithmetic, range types for domain bounds |
| `Integer_64` | Same range as `integer`; the alias would be redundant |
| `Unsigned_16/32/64` | These are hardware/storage types used explicitly; short names add little |

The set of short names is intentionally small. Developers who need a specific
width spell it out: `Integer_32`, `Unsigned_16`. The short names cover the
three most common cases: default arithmetic (`integer`), compact signed
storage (`short`), and byte-level operations (`byte`).

### Subtypes

`natural` and `positive` remain as subtypes of `integer`:

```
subtype natural  is integer range 0 .. integer'last
subtype positive is integer range 1 .. integer'last
```

### Example

```
package sensor_protocol {

   type header is record {
      version  : byte
      msg_type : byte
      length   : short
      sequence : integer
   }

   function checksum (h : header) returns byte {
      sum : integer = integer (h.version)
                    + integer (h.msg_type)
                    + integer (h.length)
                    + integer (h.sequence)
      return byte (sum mod 256)
   }
}
```

## Design Rationale

- **Reads as English** — `version : byte` and `length : short` are
  immediately clear to any programmer.
- **Three names, not eight** — the short-name set covers the common cases
  without creating a zoo of aliases.
- **Consistent with Safe's philosophy** — words over symbols, familiarity
  over Ada heritage.
- **No ambiguity with range types** — `short` is a predefined type, not a
  keyword. A developer can still write `type sensor_reading is range 0 .. 4095`
  for domain-specific bounds. The two mechanisms serve different purposes.

## Alternatives Considered

1. **Go-style numeric names (`int8`, `int16`, `uint32`)** — concise but
   reads as abbreviated jargon rather than English. Inconsistent with Safe's
   word-based naming philosophy.

2. **Rust-style (`i8`, `i16`, `u32`)** — maximally terse but even more
   symbol-like. Poor fit for a language that uses `in out` and `access`.

3. **Keep only the `Integer_N`/`Unsigned_N` names** — precise and
   self-documenting, but verbose for everyday use. `h.version : Unsigned_8`
   is noisier than `h.version : byte` for no informational gain.

---

# Task Channel Direction Constraints

## Motivation

Safe's current concurrency model allows any task to `send` or `receive` on any
visible channel within the same package. The Bronze analysis internally tracks
which channels each task reads from and writes to, but there is no
declaration-site constraint that the programmer can use to express intent or
that the compiler can enforce as a legality rule.

Go solved this at the type level: `chan<- int` is send-only, `<-chan int` is
receive-only. The direction constraint prevents a goroutine from accidentally
performing the wrong operation on a channel it was given. The compiler enforces
it.

Safe's concurrency model is different from Go's — channels are package-level
declarations accessed by name, not values passed as function arguments. Tasks
are declared entities, not spawned function calls. The direction constraint
therefore belongs on the **task declaration** rather than on a parameter type.

## Proposed Change

Task declarations gain optional `sends` and `receives` clauses that name the
channels the task is permitted to use in each direction. The compiler rejects
a `send` statement on a channel not listed in `sends`, and a `receive`
statement on a channel not listed in `receives`.

```
channel data_ch : sample capacity 4
channel control_ch : command capacity 2

task producer with priority = 10, sends data_ch, receives control_ch
   loop
      var cmd : command
      select
         when cmd : command from control_ch
            if cmd == stop
               return
      or delay 0.0
      send data_ch, compute_sample ()

task consumer with priority = 10, receives data_ch
   loop
      var s : sample
      receive data_ch, s
      process (s)
```

If `producer` attempts `receive data_ch`, the compiler rejects it. If
`consumer` attempts `send data_ch`, the compiler rejects it.

## Syntax

The `sends` and `receives` clauses appear after the `priority` attribute in
the task declaration, separated by commas. Multiple channels are listed with
commas:

```
task relay with priority = 10, receives input_ch, sends output_ch, sends log_ch
```

## Omission Semantics

If neither `sends` nor `receives` is specified, the task has unrestricted
channel access within its package — the current behavior. This preserves
backward compatibility. Adding direction constraints is opt-in but
compiler-enforced when present.

If only `sends` is specified, the task may send to the listed channels but
may also receive from any visible channel (and vice versa). To fully constrain
a task, specify both:

```
task worker with priority = 10, sends output_ch, receives input_ch
```

A task that should neither send nor receive on any channel (pure computation)
can be expressed by omitting both clauses — the absence of channel operations
in the body is already enforced by the analyzer.

## Relationship to Bronze Analysis

The Bronze summary already computes per-task channel-access sets. The direction
constraints make this internal analysis fact **user-visible and
user-constrainable**. When direction clauses are present, the analyzer checks
them against the actual channel operations in the task body and reports a
diagnostic if they disagree.

This is analogous to how SPARK's `Global` and `Depends` aspects make the
data-flow analysis user-visible: the programmer declares intent, the prover
verifies it.

## Emitter Mapping

The direction constraint is a source-level legality rule. It does not affect
emitted Ada — the emitted task body uses the same channel-operation lowering
regardless of whether direction constraints are present. The constraint is
checked during `safec check` and does not propagate to GNATprove.

## Examples

### Pipeline with direction constraints

```
package pipeline

   type sample is range 0 .. 10_000

   channel raw_ch      : sample capacity 4
   channel filtered_ch : sample capacity 4

   task producer with priority = 10, sends raw_ch
      var counter : sample = 0
      loop
         send raw_ch, counter
         if counter < 10_000
            counter = counter + 1
         else
            counter = 0

   task filter with priority = 10, receives raw_ch, sends filtered_ch
      loop
         var s : sample
         receive raw_ch, s
         if s > 0
            send filtered_ch, s

   task consumer with priority = 10, receives filtered_ch
      loop
         var s : sample
         receive filtered_ch, s
```

Each task's channel contract is visible in its declaration. A reviewer can
verify the pipeline topology without reading the task bodies.

### Select with direction constraints

```
task listener with priority = 10, receives msg_ch, receives control_ch, sends ack_ch
   loop
      select
         when m : message from msg_ch
            process (m)
            send ack_ch, ((status = ok) as ack)
         when c : command from control_ch
            if c == shutdown
               return
      or delay 1.0
```

The `select` arms reference `msg_ch` and `control_ch` (both in `receives`)
and the body sends to `ack_ch` (in `sends`). If someone adds a `send msg_ch`
inside the body, the compiler rejects it.

## What This Replaces

No existing syntax is replaced. This is an additive feature. Existing task
declarations without `sends`/`receives` remain valid and unrestricted.

## Alternatives Considered

1. **Channel direction on the channel declaration** — `channel data_ch : sample
   capacity 4 direction send`. This restricts all tasks uniformly, which is too
   coarse. Different tasks need different access to the same channel.

2. **Direction on function parameters (Go model)** — `function relay (In :
   receive channel, Out : send channel)`. Safe doesn't pass channels as
   arguments; they're declared at package level. This model doesn't fit.

3. **Direction inferred from usage** — the analyzer already does this. The
   proposal makes it declarative rather than inferred, which is more useful for
   review, documentation, and catching mistakes early.

---

# Capitalisation as Reference Signal

## Motivation

In Safe's current syntax, access-typed variables look identical to value-typed
variables at every use site:

```
ptr.all.value = 42;    -- dereference happening
other.value = 42;      -- direct field access
```

The reader cannot tell whether an identifier is a pointer or a value without
checking its type declaration. In a safety-critical language where pointer
operations (move, deallocation, null risk) are the primary source of bugs,
this is a significant readability gap.

Go demonstrated that compiler-enforced capitalisation rules work at scale:
exported identifiers must start with an uppercase letter, unexported with
lowercase. Every Go developer internalises this in the first week.

Safe can use the same mechanism for a different purpose: **uppercase initial
letter means the identifier binds to a reference (access-typed storage),
lowercase means it binds to a value.** The compiler enforces this as a
legality rule, not a style convention.

## Proposed Rule

Safe becomes case-sensitive. Identifiers that bind to access-typed storage
must start with an uppercase letter. All other identifiers must start with a
lowercase letter. The compiler rejects violations.

| Identifier kind | Case rule | Examples |
|-----------------|-----------|----------|
| Variable binding to access type | Uppercase initial | `Source`, `Target`, `Head` |
| Variable binding to value type | Lowercase initial | `count`, `total`, `index` |
| Parameter binding to access type | Uppercase initial | `Data`, `Node` |
| Parameter binding to value type | Lowercase initial | `data`, `value` |
| Record field of access type | Uppercase initial | `Next`, `Parent` |
| Record field of value type | Lowercase initial | `value`, `length` |
| Type name | Lowercase initial | `payload`, `node_ref`, `integer` |
| Package name | Lowercase initial | `provider`, `safe_runtime` |
| Function/procedure name | Lowercase initial | `find`, `process`, `consume` |
| Constant binding to access type | Uppercase initial | `Default_Node` |
| Constant binding to value type | Lowercase initial | `max_size` |

## The `move` Keyword

Capitalisation answers "is this a pointer?" The `move` keyword answers "is
this assignment destructive?"

Reference-to-reference assignment requires the `move` keyword. A bare `=` on
a reference variable is a compile error:

```
Target = move Source;     -- ok: Source becomes null, Target takes ownership
Target = Source;          -- ERROR: reference assignment requires 'move'
Target = null;            -- ok: null assignment, no move needed
```

For value-typed variables, `move` is not used. Plain `=` copies the value:

```
total = count + 1;        -- value copy, both lowercase
```

No `copy` keyword is needed. The absence of `move` on a lowercase variable
is the copy signal.

## Implicit Dereference

With capitalisation marking every reference, the `.all` explicit dereference
is redundant and dropped:

```
-- Current
Total = Total + total_value (Current.all.value);
Current = Current.all.Next;

-- Proposed
total = total + total_value (Current.value);
Current = move Current.Next;
```

The compiler knows `Current` is a reference (uppercase). Field access through
a reference is an implicit dereference. The reader knows too, because the
variable is capitalised.

## Examples

### Ownership move

```
package ownership_demo {

   type payload is record {
      value : integer
   }

   type payload_ref is access payload

   procedure transfer {
      Source : payload_ref = new ((value = 42) as payload)
      Target : payload_ref = null

      Target = move Source
      Target.value = 100
   }

}
```

Every occurrence of `Source` and `Target` is visually distinct from `value`.
The `move` on the assignment makes the destructive transfer explicit.

### Linked list traversal

```
type node is record {
   value : integer
   Next  : access node
}

function sum_values (Head : node_ref) returns integer {
   total : integer = 0

   if Head != null {
      total = total + Head.value
      if Head.Next != null {
         total = total + Head.Next.value
      }
   }
   return total
}
```

`Head` and `Next` are uppercase — the reader knows dereferences are happening.
`total` and `value` are lowercase — plain value operations.

### Function parameters

```
function consume (Data : payload_ref) ...        -- takes ownership (uppercase)
function modify  (Data : in out payload_ref) ...  -- borrows mutably (uppercase)
function inspect (Data : in payload_ref) ...      -- observes read-only (uppercase)
function process (data : payload) ...             -- copies value (lowercase)
```

The call site:

```
consume (move My_Ptr)     -- uppercase argument, explicit move
inspect (My_Ptr)          -- uppercase argument, observe (not moved)
process (my_value)        -- lowercase argument, value copy
```

### Record field enforcement

The compiler enforces field capitalisation at the type declaration:

```
type node is record {
   value : integer         -- lowercase: value field (ok)
   Next  : access node     -- uppercase: reference field (required)
   next  : access node     -- ERROR: access-typed field must be uppercase
   Value : integer         -- ERROR: value-typed field must be lowercase
}
```

## What This Replaces

This proposal supersedes the earlier Case Insensitivity confirmation. Safe
becomes case-sensitive. This is a one-way departure from Ada's
case-insensitive model (8652:2023 §2.3).

It also eliminates the need for a `ref` keyword. Capitalisation carries the
reference signal without a type-level keyword.

## Edge Cases

**Array elements.** `items(3).value` — the array `items` is lowercase (it's a
value), but `items(3)` produces a reference if the element type is an access
type. The capitalisation signal doesn't carry through indexing. This is the
same gap Go and Rust accept for indexed access.

**Parameter names shadowing type names.** `(Payload : payload)` is rejected
by the compiler. An identifier that differs from a visible type name only by
initial capitalisation is a legality error. The developer must choose a
distinct name: `(Data : payload)`, not `(Payload : payload)`.

**Refactoring type changes.** Changing a variable from value type to access
type requires renaming it from lowercase to uppercase (and vice versa). This
is a feature: the change is visible at every use site rather than hidden in a
type definition.

## Design Rationale

- **Always-on signal** — every occurrence of every variable in the entire
  codebase tells you whether it is a pointer. No keyword, no sigil, no type
  lookup needed.
- **Compiler-enforced** — not a convention. The compiler rejects a lowercase
  name for an access-typed binding and an uppercase name for a value-typed
  binding.
- **Low cognitive load** — one rule: uppercase means pointer. No symbol
  vocabulary to learn.
- **Grep-friendly** — `[A-Z]` in an expression means a reference is involved.
  Code review becomes faster.
- **Proven model** — Go has used case-as-semantics since 2009 with no
  reported usability issues. The rule is simple enough for developers to
  internalise in the first day.
- **Complements `move`** — capitalisation answers "is this a pointer?" and
  `move` answers "is this destructive?" Together they make both the nature
  and the operation visible at every site.

## Alternatives Considered

1. **`ref` keyword on types and declarations** — `ptr : ref payload`. Marks
   the declaration site but not every use site. Field access `ptr.value`
   still looks identical to a value access without checking the declaration.

2. **`*` / `&` sigils** — Rust/Go-style. Visually distinct but inconsistent
   with Safe's "words over symbols" philosophy.

3. **Keep case-insensitive + add `move` only** — `move` marks destructive
   assignment but doesn't tell you which variables are pointers at a glance.

4. **Keep case-insensitive entirely** — status quo. Reader must check type
   declarations to know whether a variable is a pointer. The gap that
   motivated this proposal remains.

## Interaction with `pragma Strict`

Capitalisation rules apply identically under both default and strict modes.
`pragma Strict` controls block delimiters and closing labels, not identifier
casing. Both modes enforce the same uppercase-means-reference rule.

---

# Capitalisation as Export Signal

## Motivation

The Capitalisation as Reference Signal proposal uses uppercase initials on
variable/field/parameter names to indicate reference (access-typed) bindings.
Function and type names are all lowercase under that proposal. This leaves
export/visibility signaling to a separate mechanism (currently implicit: all
package-level declarations are public).

Go uses capitalisation for a single purpose: exported vs unexported. Safe can
use it for **two** purposes without ambiguity because function names and
variable names occupy disjoint syntactic positions. A name followed by `(` is
a function call or declaration. A name followed by `:` or appearing as an
expression argument is a variable. The parser already distinguishes these —
capitalisation adds a visual signal that the grammar enforces.

## Proposed Rule

Function names follow the same uppercase/lowercase split as variable names,
but with a different semantic:

| Name | Followed by | Meaning |
|------|-------------|---------|
| `Lookup(` | `(` | Exported (public) function |
| `lookup(` | `(` | Private (package-internal) function |
| `Table` | `:` or expression position | Reference variable/parameter |
| `table` | `:` or expression position | Value variable/parameter |

The compiler enforces:

- An uppercase-initial function name is visible to importing packages.
- A lowercase-initial function name is private to the declaring package.
- No `public`/`private` keyword or section is needed.
- The rule is orthogonal to the reference-signal rule: they apply to different
  syntactic categories and never conflict.

## Combined Rule Set

```
Uppercase name followed by (   =  exported function
Lowercase name followed by (   =  private function
Uppercase name followed by :   =  reference (access-typed) binding
Lowercase name followed by :   =  value binding
Uppercase name as expression   =  reference being used
Lowercase name as expression   =  value being used
Type names                     =  always lowercase
Package names                  =  always lowercase
```

## Examples

### Package with mixed visibility

```
package key_value_store

   type entry is record
      key   : string_buffer (64)
      value : string_buffer (256)

   -- Exported: other packages can call Get and Put
   function Get (Table : constant store.Map, k : key) returns lookup_result
      ...
   end Get

   function Put (Table : store.Map, k : key, v : value, success : out boolean)
      ...
   end Put

   -- Private: only used within this package
   function validate_key (k : key) returns boolean
      ...
   end validate_key

   function compact_storage (Table : store.Map)
      ...
   end compact_storage
```

At every call site, the reader sees:

```
key_value_store.Get (DB, my_key)           -- uppercase: public API
key_value_store.Put (DB, my_key, my_val, ok)  -- uppercase: public API
validate_key (k)                           -- lowercase: internal, only callable here
```

### Interaction with reference signal

The two uses of capitalisation never conflict:

```
function Process (Table : store.Map, req : request) returns response
--       ^^^^^^^  ^^^^^              ^^^
--       exported  reference          value
--       (function) (parameter)       (parameter)
```

`Process` is uppercase because it's exported. `Table` is uppercase because
it's a reference. `req` is lowercase because it's a value. Each uppercase
initial has exactly one meaning determined by its syntactic position.

## What This Replaces

The `public` / `private` keywords or sections that would otherwise be needed
for visibility control. The export decision is visible at every mention of the
function name throughout the codebase, not hidden at the declaration site.

## Interaction with `pragma Strict`

Export rules apply identically under both default and strict modes. `pragma
Strict` controls block delimiters and closing labels, not identifier casing or
visibility signaling.

---

# Unified Function Type

Status: implemented in PR11.4 as a cutover. All Safe callables now use
`function`; legacy `procedure` is rejected.

## Motivation

Safe currently has both `function` (returns a value) and `procedure` (performs
an action, no return). This distinction is inherited from Ada. In practice,
the two are identical except that a function has a return type and a procedure
does not. The same keyword, parameter syntax, body structure, calling
convention, and ownership rules apply to both.

Every modern language has converged on a single function concept: Go's `func`,
Rust's `fn`, Python's `def`, JavaScript's `function`. The split adds a keyword
to learn, a decision to make ("should this be a function or procedure?"), and
an asymmetry where converting a procedure to return a status value requires
changing the keyword.

## Proposed Change

The `procedure` keyword is removed. All callable declarations use `function`.
A function with no `returns` clause is what was previously called a procedure.

```
-- Returns a value
function lookup (Table : constant store.Map, k : key) returns lookup_result
   ...

-- Returns nothing (was "procedure")
function insert (Table : store.Map, k : key, v : value, success : out boolean)
   ...
```

The absence of `returns` is the signal that the function produces no value.
This is strictly less syntax to learn: one keyword instead of two, one rule
instead of two.

## Emitter Mapping

The emitter produces Ada `function` or `procedure` based on whether a
`returns` clause is present. The Safe source uses `function` uniformly; the
emitted Ada uses the appropriate keyword. This is a surface-level mapping with
no semantic complexity.

## Interaction with Ownership

Ownership rules for parameters (`in`, `out`, `in out`, access-typed borrows,
`move`) are identical for functions and procedures today. Merging the keyword
changes nothing about parameter passing, borrow semantics, or cleanup
ordering.

## Interaction with Capitalisation

Under the Capitalisation as Export Signal proposal, function names follow the
uppercase-exported / lowercase-private convention regardless of whether they
return a value:

```
function Process (req : request) returns response   -- exported, returns value
function insert (Table : store.Map, k : key, ...)   -- private, returns nothing
```

## Examples

### Before (current syntax)

```
procedure insert (Table : access Store.Map;
                  K : Key;
                  V : Value;
                  Success : out Boolean) is
begin
   ...
end insert;

function lookup (Table : access constant Store.Map;
                 K : Key) return Lookup_Result is
begin
   ...
end lookup;
```

### After (unified)

```
function insert (Table : store.Map, k : key, v : value, success : out boolean)
   ...
end insert

function lookup (Table : constant store.Map, k : key) returns lookup_result
   ...
end lookup
```

## What This Replaces

The `procedure` keyword. No other language construct is affected.

## Alternatives Considered

1. **Keep both keywords.** Status quo. Two keywords for one concept. Every
   developer must choose between them for every callable declaration.

2. **Use `def` instead of `function`.** Shorter, but loses the self-documenting
   quality of `function` and departs further from Ada heritage than necessary.

3. **Use `proc` and `func` abbreviations.** Still two keywords. Does not solve
   the problem.

---

# Predefined Immutable `string` Type

## Motivation

The Go-programmer onboarding story depends on being able to write `string`
without specifying a capacity. Go's `string` is a built-in type that just
works. If Safe requires `string_buffer (64)` for every text parameter or return
value, the first-hour experience fails before the programmer has written their
first useful function.

## Proposed Change

Introduce `string` as a predefined immutable text type in PR11.2. It lowers
directly to Ada `String` for the admitted PR11.2 use sites and does not depend
on the later `string_buffer` library surface.

```
-- Casual style: built-in immutable text
function lookup (k : string) returns string

-- Later bounded mutable text (PR11.10)
function lookup_buffered (k : string_buffer (64)) returns string_buffer (256)
```

The PR11.2 `string` surface is intentionally narrow: it exists so text literals,
text-returning helpers, and ordinary `in` parameters feel natural, without
pulling mutable bounded storage forward.

## What `string` Is

- A predefined immutable text type
- Lowered to Ada `String` in emitted code
- Admitted in PR11.2 only for `in` parameters, return types, constant objects,
  and literal expressions
- Suitable for code like `function grade_message (letter : character) returns string`

## What `string` Is Not

- Not a type alias to `string_buffer`
- Not a mutable object type in PR11.2
- Not admitted in record fields, channel element types, array component types,
  discriminants, or `out` / `in out` parameters
- Not a dynamic heap string (no allocation, no GC)
- Not the future bounded mutable text library surface

## PR11.2 Boundary

PR11.2 does not try to solve the full string story. It intentionally excludes:

- mutable `string` objects
- string comparison or concatenation
- string indexing and attributes such as `.Length`
- `case` on `string`
- bounded mutable storage concerns such as default capacities

## When Dynamic Strings Are Needed

Dynamic/unbounded strings are a post-PR11.11 concern. They require heap
allocation and ownership semantics that interact with generics. Separately,
bounded mutable text storage belongs to the later `string_buffer` library work
in PR11.10. PR11.2 keeps `string` immutable and narrow so the early parser and
emitter milestone stays small.

## Emitter Mapping

`string` emits as Ada `String`. `character` emits as Ada `Character`. The later
`string_buffer` work in PR11.10 remains a distinct bounded mutable-text surface
rather than being hidden behind the PR11.2 `string` spelling.

---

# Tuple Types and Multiple Returns

## Motivation

Go programmers write:

```go
func lookup(key string) (bool, string) {
    ...
    return true, value
}

found, data := lookup("host")
```

This pattern — returning multiple values without defining a custom struct —
is fundamental to Go's ergonomics. Every Go function that can fail returns
`(result, error)` or `(result, bool)`.

Safe's current equivalent requires a custom discriminated record:

```
type lookup_result (found : boolean = false) is record
   case found is
      when true =>
         data : value
      when false =>
         null
```

This is more precise (the compiler proves you never access `data` when
`found` is false) but it requires defining a named type before writing the
function. For many programs, especially during exploration and prototyping,
the ceremony is not worth the precision.

## Proposed Change

Introduce anonymous tuple types and multiple-return syntax:

```
function Lookup (Table : constant store.Map, k : string) returns (boolean, string)
   if store.contains (Table, k)
      return (true, store.element (Table, k))
   return (false, "")
```

### Tuple type syntax

`(T1, T2, ...)` in type position creates an anonymous product type.

### Tuple expression syntax

`(expr1, expr2, ...)` in expression position creates a tuple value.

### Destructuring bind

```
var (found, data) : (boolean, string) = Lookup (DB, "host")
```

### Tuple field access

Positional: `result.1`, `result.2` (1-indexed).

### Current implementation status (PR11.3)

PR11.3 lands the narrow value-type tuple subset:

- Anonymous tuple types and tuple expressions with arity >= 2
- Function returns of tuple type
- Local destructuring bind
- Positional selectors like `.1`, `.2`
- Tuple-typed channel elements

PR11.3 does **not** admit nested tuples, access-typed tuple elements, or other
ownership-bearing tuple shapes. Those remain deferred.

## Emitter Mapping

The emitter lowers tuples to Ada records with positional field names:

```ada
type Safe_tuple_Boolean_Integer is record
   F1 : Boolean;
   F2 : Integer;
end record;
```

The Ada type is generated and invisible to the Safe programmer. Tuple elements
of type `string` are emitted with compiler-generated length discriminants in
the helper Ada record; PR11.3 does not route tuples through `string_buffer`.

## Interaction with Discriminated Records

Tuples and discriminated records solve overlapping problems. The design
principle is:

- **Tuples** for lightweight, unnamed, positional return values and
  intermediate groupings. No variant parts. No field names. Copy semantics.
- **Discriminated records** for named, structured data with variant fields
  and field-access legality enforced by discriminant values.

Both can be used as function return types. The programmer chooses based on
whether they need named fields and variant-part enforcement.

## Interaction with Ownership

The landed PR11.3 subset avoids ownership-heavy tuple shapes. Access-typed
elements, nested tuples, and other ownership-bearing elements are rejected.
For the admitted value-type cases like `(boolean, string)` or
`(integer, integer)`, tuples behave like ordinary copyable records.

## Interaction with Channels

Tuples can be channel element types:

```
channel response_ch : (boolean, string) capacity 16
send response_ch, (true, "hello")
```

This enables lightweight message protocols without named record types.

---

# Scoped-Binding `receive`

## Motivation

The §97a null-before-move rule requires that the target of a `receive` into
an owning access variable must be provably null at the point of the receive.
In a loop, this means the variable must be declared inside the loop body so
that each iteration creates a fresh null binding:

```
-- Conforming (§97c): declaration inside loop
loop
   var msg : message_ref
   receive ch, msg
   process (msg)
-- msg deallocated at scope exit each iteration

-- Nonconforming: declaration outside loop
var msg : message_ref
loop
   receive ch, msg    -- second iteration: msg is non-null, rejected
   process (msg)
```

The conforming pattern requires the programmer to know that declaration
placement controls deallocation timing — a concept that does not exist in
Go, Java, C#, or Python. The nonconforming pattern is what every developer
from those languages will write first.

The `select` statement already solves this. Its `when` arm declares and
scopes the variable in one construct (§4.4, paragraph 37):

```
select
   when msg : message from ch
      process (msg)
```

`msg` is born at the `when`, scoped to the arm, and deallocated at arm
exit. The programmer cannot write the nonconforming pattern because there
is no separate declaration to misplace. `receive` has no equivalent.

## Proposed Change

Extend the `receive` statement grammar with an inline declaration form:

```
receive_statement ::=
    'receive' channel_name ',' name
  | 'receive' channel_name ',' defining_identifier ':' subtype_mark
```

The second form declares the variable at the receive point, scoped to the
enclosing block. It is syntactic sugar for a declaration followed by a
receive:

```
-- Sugar
receive ch, msg : message_ref

-- Desugars to
var msg : message_ref
receive ch, msg
```

The same extension applies to `try_receive`:

```
try_receive_statement ::=
    'try_receive' channel_name ',' name ',' name
  | 'try_receive' channel_name ',' defining_identifier ':' subtype_mark ',' name
```

## Owning access types require the scoped form

If the target variable has an owning access type, the compiler **requires**
the scoped-binding form. The bare form is a compile error:

```
-- Owning access type: scoped form required
receive ch, Item : payload_ref     -- OK
receive ch, Item                   -- REJECTED if Item is owning access

-- Value type: both forms legal
receive ch, count : integer        -- OK
receive ch, count                  -- OK (no ownership concern)
```

This makes §97a compliance automatic for owning types. The programmer never
encounters a null-before-move diagnostic for `receive` — the syntax does
not allow the mistake. The bare form remains available for value types
where scoping has no safety consequence.

The same rule applies to `try_receive`:

```
-- Owning access type: scoped form required
try_receive ch, Item : payload_ref, got_item    -- OK
try_receive ch, Item, got_item                  -- REJECTED if Item is owning access
```

## Examples

### Basic loop with scoped receive

```
task consumer with priority = 10, receives data_ch
   loop
      receive data_ch, item : payload_ref
      process (item)
   -- item deallocated at end of loop body each iteration
```

The programmer cannot declare `item` outside the loop and accidentally
create a §97a violation. The declaration is fused to the receive.

### Try-receive with scoped binding

```
task poller with priority = 5, receives data_ch, sends status_ch
   loop
      try_receive data_ch, item : payload_ref, got_item
      if got_item
         process (item)
      else
         send status_ch, (false, "idle")
      delay 0.1
```

`item` is declared at the `try_receive` point. If `got_item` is false,
`item` is null (no ownership transferred). If true, `item` is non-null
and scoped to the enclosing block.

### Value types: both forms work

For value types, the scoped binding is a convenience, not a requirement:

```
-- Both are fine for value types
receive ch, count : integer
-- or
var count : integer
receive ch, count
```

The scoped form is preferred for consistency but the bare form is not
rejected for non-owning types.

## Interaction with `select`

The `select` arm already has scoped binding:

```
select
   when msg : message from ch
      ...
```

The `receive` scoped binding mirrors this:

```
receive ch, msg : message
```

The two constructs use different syntax (`when msg : T from ch` vs
`receive ch, msg : T`) because they serve different roles — `select`
multiplexes across channels while `receive` blocks on one. But the
scoping semantics are identical: the variable is born at the statement
and dies at the enclosing block's exit.

## What This Does Not Change

- The non-binding `receive ch, name` form is retained for value types.
  Existing code using value-typed channels is unaffected.
- The semantics of receive are unchanged — only the declaration point of
  the target variable moves.
- No new ownership rules. §97a still applies; the scoped binding makes
  compliance structural for owning types and leaves it optional for
  value types.

## Design Rationale

- **Structural safety over diagnostic recovery.** The best error message
  for a §97a violation is never seeing one. If the syntax makes the
  violation unrepresentable for owning types, the compiler never needs
  to explain it.
- **Mandatory for owning types, optional for value types.** This is the
  strongest design: the trap is eliminated where it matters (ownership)
  and the lightweight syntax is preserved where it doesn't (values).
  Convention-based approaches ("prefer the scoped form") leave the trap
  available. Safe should make it impossible.
- **Mirrors `select` arm syntax.** The precedent already exists in the
  language. Extending it to `receive` is consistent.
- **Minimal grammar change.** One production added to `receive_statement`
  and one to `try_receive_statement`. No new keywords, no new concepts.
- **Go-familiar.** Go's `for msg := range ch` declares and receives in
  one construct. Safe's `receive ch, msg : T` is the same idea adapted
  to Safe's channel syntax.

## Alternatives Considered

1. **Keep both forms for all types (convention only).** Weaker — the §97a
   trap remains representable. Diagnostics catch it, but the syntax could
   prevent it. Safe should prefer prevention over detection.

2. **Require scoped form for all types.** Too restrictive. Value types
   have no ownership concern. Forcing `receive ch, count : integer` when
   `receive ch, count` is safe wastes the programmer's time without
   improving safety.

3. **Add a `with` block for receive.** A dedicated scoping construct like
   `with msg : T from ch do ... end`. Heavier than necessary when the
   inline declaration suffices.

4. **Rely on diagnostics alone.** The compiler can explain §97a violations
   clearly. But "add a diagnostic for a mistake the syntax could prevent"
   is weaker than "make the mistake unrepresentable." Diagnostics are the
   fallback for the bare form on value types; the scoped form eliminates
   the need for owning types.

---

# Error Handling Convention

## Motivation

Safe has no exception mechanism (D14), no `try`/`catch`, and no stack
unwinding. When a function detects a problem, it must communicate the failure
through its return value. When a task detects a problem, it must communicate
the failure through a channel. The language provides no guidance on how to
structure either.

Go programmers expect `(T, error)` return pairs. Rust programmers expect
`Result<T, E>`. Safe currently has nothing — developers invent ad hoc
patterns using booleans, discriminated records, or untyped status values.

This matters especially for channels. Tasks loop forever and cannot return
values. Errors generated inside a task must travel through channels, and the
channel element type must accommodate both success and failure without
ownership complications.

## Phase 1: Tuples as error pairs (PR11.3)

This is the Go-like phase. When tuples land in PR11.3, the standard error
convention is `(boolean, T)` — the same structure as Go's `(T, error)` with
the status in the first position.

### Functions

```
function Lookup (k : string) returns (boolean, string)
   if not store.contains (DB, k)
      return (false, "")
   return (true, store.element (DB, k))
```

### Callers

```
var (found, data) : (boolean, string) = Lookup (DB, key)
if not found
   return (false, "")
process (data)
```

This is the pattern a Go programmer already knows. `found` is the `err !=
nil` check. The compiler proves `found` is checked before `data` is used,
via the guards-as-contracts model.

### Channels

```
channel results : (boolean, string) capacity 16

task worker with priority = 10, receives jobs, sends results
   loop
      var job : string
      receive jobs, job
      var (ok, data) : (boolean, string) = process_job (job)
      send results, (ok, data)

task collector with priority = 5, receives results
   loop
      var payload : (boolean, string)
      receive results, payload
      if not payload.1
         log_error ("job failed")
      else
         store_result (payload.2)
```

### Limitation

The caller knows the operation failed but not why. `false` carries no
context. For many programs this is sufficient — Go's `(T, bool)` pattern
(like `map[key]` returning `(value, ok)`) works the same way.

## Phase 2: Predefined `result` type (PR11.3, after tuples)

For cases where an error message is needed, introduce a predefined `result`
type:

```
result
ok
fail ("key not found")
```

### Current implementation status (PR11.3)

`result` is a compiler-known builtin type, not a user-declared alias or
ordinary source-level record declaration. Semantically it exposes:

```
ok      : boolean
message : string
```

with builtin constructors:

```
ok                          -- result where ok = true, message = ""
fail ("key not found")      -- result where ok = false, message = "key not found"
```

PR11.3 keeps the general PR11.2 restriction on user-declared `String` record
fields. `result` is the only carveout, and the emitter lowers it to a
compiler-generated Ada discriminated record with hidden message-length storage
rather than to an ordinary user-visible record with an unconstrained `String`
component.

This is the upgrade path from `(boolean, T)` when bare true/false is not
enough context. Functions return `(result, T)`:

```
function Lookup (k : string) returns (result, string)
   if not store.contains (DB, k)
      return (fail ("key not found"), "")
   return (ok, store.element (DB, k))
```

Channels carry `(result, T)`:

```
channel results : (result, string) capacity 16
send results, (fail ("timeout"), "")
send results, (ok, "localhost")
```

The `result` type is value-typed, copyable, and contains no access types.
It serializes cleanly through bounded channels without ownership transfer
concerns.

A Go programmer learns `(boolean, T)` first — that is what they already
know. When they need error messages, they upgrade to `(result, T)`. The
compiler diagnostics and tutorials should teach both, in that order.

## Phase 3: Generic `result (T, E)` type (PR11.11)

After generics land, parameterize the result type:

```
type result (T, E) is record
   case ok : boolean
      when true
         value : T
      when false
         error : E
```

Destructuring bind works:

```
var r : result (string, error_code) = Lookup (DB, key)
if not r.ok
   handle_error (r.error)
   return
use_value (r.value)
```

Channel element types use the generic form:

```
channel results : result (string, error_code) capacity 16
```

The Phase 2 monomorphic `result` is retained as a lightweight alternative
for cases where only a status message is needed.

## Error Propagation

No propagation operator is proposed. The reasons:

**Guards handle it naturally.** The `if not found` / `return` pattern is
the same guard-based idiom Safe uses for all proof obligations. The compiler
proves the error is checked. The programmer decides where the error goes.

**Channel errors are directional.** In Go, `return err` propagates up the
call stack. In Safe, errors often cross task boundaries via channels. A `?`
operator that propagates to the caller does not help when the error needs
to go to a different channel or a supervisor task. The programmer must
choose the destination.

**Community patterns first.** Let developers use manual error checking and
develop idioms for retry, fallback, and supervisor notification. If a
dominant pattern emerges, add propagation syntax later with evidence from
real programs.

## Channel Error Patterns

### Supervisor

```
channel error_ch : result capacity 8

task worker with priority = 10, receives jobs, sends results, sends error_ch
   loop
      var job : string
      receive jobs, job
      var (status, data) : (result, string) = process (job)
      if not status.ok
         send error_ch, status
      else
         send results, (ok, data)

task supervisor with priority = 15, receives error_ch
   loop
      var err : result
      receive error_ch, err
      log ("worker error: " ++ err.message)
```

### Retry

```
function fetch_with_retry (k : string, max_attempts : integer) returns (result, string)
   var attempt : integer = 0
   while attempt < max_attempts
      var (status, data) : (result, string) = Lookup (DB, k)
      if status.ok
         return (ok, data)
      attempt = attempt + 1
   return (fail ("max retries exceeded"), "")
```

## Design Rationale

- **Value-typed errors.** The `result` type contains no access types. It is
  always copyable. This is essential for channels — errors must serialize
  through bounded channels without ownership transfer.
- **Boolean discriminant.** Two states cover the majority of error handling.
  Richer taxonomies use the `message` field or (post-generics) a
  parameterized error type.
- **No `error` interface.** Go's `error` works because Go has interfaces.
  Safe does not (D18). A concrete `result` type is simpler and sufficient.
- **Compatible with guards-as-contracts.** `if not status.ok` is a proof
  obligation the compiler discharges. After the guard, the compiler knows
  the result is ok and can prove downstream code is safe.
- **Go-first learning path.** `(boolean, T)` is what Go programmers already
  know. `(result, T)` is the upgrade when they need error messages. Neither
  requires learning new concepts — just new types.

## Interaction with Other Proposals

| Proposal | Interaction |
|----------|------------|
| Tuples (PR11.3) | `(boolean, T)` and `(result, T)` are the standard error return types |
| Predefined immutable `string` type (PR11.2) | `result.message` uses the builtin immutable `string` type |
| Channel direction constraints (PR11.5) | Error channels appear in `sends` clauses |
| Restricted generics (PR11.11) | `result (T, E)` replaces the monomorphic `result` |
| Capitalisation (PR11.7) | `result` is lowercase — value type, not a reference |

## Alternatives Considered

1. **Exceptions (D14 reversed).** Rejected. Stack unwinding is incompatible
   with static analysis and channel-based concurrency where errors must
   cross task boundaries explicitly.

2. **Monadic chaining (`.and_then`, `.map_err`).** Requires higher-order
   functions or method syntax. Deferred to post-generics.

3. **Panic / abort.** Non-recoverable termination for impossible states.
   Not proposed here but could complement `result`. Needs interaction
   design with the task model.

4. **Propagation operator (`?`).** Deferred. Manual checking with guards
   integrates with the proof model. If verbosity becomes a demonstrated
   problem in the Rosetta corpus, revisit with evidence.

---

# Restricted Generics

## Supporting Reference

Background on SPARK formal-container compatibility is collected in
[SPARK Container Library Compatibility Analysis](spark_container_compatibility.md).

## Motivation

Design decision D16 excludes Ada's generic units (8652:2023 §12) in their
entirety. The stated rationale is compiler complexity:

> "Generics require instantiation, which adds significant compiler complexity."
> — §2.1.11, ¶69

This decision was correct for v0.1–v0.2, where the priority was a minimal,
provably correct compiler. But the cost is now clear:

1. **No standard containers.** Ada's `Ada.Containers.*` and SPARK's
   `SPARK.Containers.Formal.*` are both generic libraries. Without generics,
   Safe cannot use either. The v0.3 monomorphic containers (`Safe.Integer_Vectors`,
   etc.) are a stopgap that covers built-in element types but cannot serve
   user-defined types.

2. **No user-defined reusable data structures.** A developer who defines a
   `Sensor_Reading` record and needs a bounded vector of them must hand-write
   a one-off package. This is the exact boilerplate generics eliminate.

3. **No access to SPARK's formally verified libraries.** SPARK's formal
   containers have precondition-based APIs that align perfectly with Safe's
   D27 proof model. The only barrier is the `generic` keyword.

4. **Adoption barrier.** Every mainstream language — including Ada itself —
   provides parameterized types. Shipping a language in 2026 without them
   will deter adoption from every community, not just those familiar with
   generics.

The question is not whether Safe needs generics, but what restricted subset
is sufficient and what the implementation cost is.

## Proposed Change

Retain a **restricted subset of Ada §12** that supports monomorphic
specialization of generic packages. Every instantiation produces a distinct,
fully concrete compilation unit. No runtime polymorphism, no code sharing
between instantiations, no dynamic dispatch.

### What is retained

| §12 Feature | Status | Rationale |
|-------------|--------|-----------|
| Generic package declarations | **Retained** | Required for container libraries |
| Generic package bodies | **Retained** | Implementation of generic packages |
| Generic instantiation (`package X is new G (T)`) | **Retained** | The mechanism that produces concrete types |
| Formal type parameters (`type T is private`) | **Retained** | Parameterize over element types |
| Formal type parameters (`type T is (<>)`) | **Retained** | Discrete types for keys, indices |
| Formal type parameters (`type T is range <>`) | **Retained** | Numeric types for arithmetic containers |
| Default values for formal parameters | **Retained** | Convenience; no semantic complexity |

### What remains excluded

| §12 Feature | Status | Rationale |
|-------------|--------|-----------|
| Generic subprograms | **Excluded** | Packages are sufficient; subprogram generics add complexity without enabling new patterns |
| Formal subprogram parameters (`with function`) | **Excluded** | Requires higher-order parameterization; deferred to v1.0 |
| Formal package parameters (`with package`) | **Excluded** | Parameterizing over packages-of-packages; too complex for v0.4 |
| Generic child packages | **Excluded** | Safe has no child packages (flat package model) |
| Formal access type parameters | **Excluded** | Interaction with ownership model is unresolved |
| Formal tagged type parameters | **Excluded** | Tagged types remain excluded (D18) |
| Shared generic bodies | **Excluded** | Every instantiation is fully expanded; no sharing |

### Syntax

Generic declarations use Ada's existing syntax, restricted to the retained
subset:

```
generic
   type Element_Type is private;
   type Index_Type is range <>;
package Safe.Bounded_Vectors {

   public type Capacity_Range is range 1 .. 10_000;
   public type Count is range 0 .. 10_000;

   public type Vector (Capacity : Capacity_Range) is record {
      Data   : array (1 .. Capacity) of Element_Type = (others = Element_Type'Default);
      Length : Count = 0;
   }

   public function Get_Length (V : Vector) returns Count {
      return V.Length;
   }

   public function Element (V : Vector; I : Index_Type) returns Element_Type
      pre I <= V.Length
   {
      return V.Data (I);
   }

   public procedure Append (V : in out Vector; Value : Element_Type)
      pre V.Length < V.Capacity
   {
      V.Length = V.Length + 1;
      V.Data (V.Length) = Value;
   }

   public procedure Clear (V : in out Vector) {
      V.Length = 0;
   }

   public function Contains (V : Vector; Value : Element_Type) returns Boolean {
      for I in 1 .. V.Length {
         if V.Data (I) == Value {
            return True;
         }
      }
      return False;
   }
}
```

Instantiation:

```
package Sample_Vectors is new Safe.Bounded_Vectors
   (Element_Type = Sample,
    Index_Type   = Sample_Index);
```

This produces a fully concrete package `Sample_Vectors` with no generic
parameters — identical to what a developer would write by hand.

### Strict mode

Under `pragma Strict`, the syntax uses Ada-style delimiters:

```
pragma Strict;

generic
   type Element_Type is private;
   type Index_Type is range <>;
package Safe.Bounded_Vectors is

   public type Vector (Capacity : Capacity_Range) is record
      Data   : array (1 .. Capacity) of Element_Type;
      Length : Count = 0;
   end record;

   public function Element (V : Vector; I : Index_Type) return Element_Type is
   begin
      return V.Data (I);
   end Element;

end Safe.Bounded_Vectors;
```

## Compilation Model

### Monomorphic specialization

Every generic instantiation is expanded at compile time into a concrete
package. The compiler:

1. Parses and validates the generic declaration (type-checks the body with
   formal types as placeholders).
2. At each instantiation site, substitutes actual types for formal parameters.
3. Emits a fully concrete Ada package — no `generic` keyword in the output.
4. The instantiated package is an independent compilation unit for GNATprove.

This is the same model GNAT uses when inlining generic bodies. The expansion
happens in the Safe compiler; the emitted Ada contains only concrete packages.

### What the emitter produces

For the instantiation:

```
package Sample_Vectors is new Safe.Bounded_Vectors
   (Element_Type = Sample,
    Index_Type   = Sample_Index);
```

The emitter generates:

```ada
-- sample_vectors.ads (emitted Ada)
package Sample_Vectors is
   type Capacity_Range is range 1 .. 10_000;
   type Count is range 0 .. 10_000;

   type Vector (Capacity : Capacity_Range) is record
      Data   : array (1 .. Capacity) of Sample;
      Length : Count := 0;
   end record;

   function Element (V : Vector; I : Sample_Index) return Sample
      with Pre => I <= V.Length;

   procedure Append (V : in out Vector; Value : Sample)
      with Pre => V.Length < V.Capacity;

   -- ... remaining operations
end Sample_Vectors;
```

GNATprove verifies this as a standard SPARK package. No special handling.

### Alternative: emit SPARK generic instantiations

Instead of expanding generics in the Safe compiler, the emitter could produce
SPARK-level generic instantiations:

```ada
-- emitted Ada
with SPARK.Containers.Formal.Vectors;
package Sample_Vectors is new SPARK.Containers.Formal.Vectors
   (Element_Type => Sample, Index_Type => Sample_Index);
```

This delegates expansion to GNAT and leverages SPARK's already-verified
container implementations. The tradeoff: Safe's emitter becomes dependent on
the SPARK formal library being available, and the emitted Ada is less
self-contained.

**Recommendation:** Start with Safe-side expansion (the emitter produces
concrete packages). This keeps the emitted Ada independent of SPARK library
availability and makes the emitted code easier to audit. SPARK library
delegation can be added later as an optimization.

## Interaction with Existing Design Decisions

### D17 — Ownership

The critical design question. When a container holds access types, ownership
semantics must be defined for every operation:

| Operation | Ownership Effect |
|-----------|-----------------|
| `Append (V, Ptr)` | **Move**: `Ptr` becomes null; the container owns the referent |
| `Element (V, I)` | **Observe**: returns a read-only view; container retains ownership |
| `Remove (V, I)` | **Move out**: returns the owned value; container releases ownership |
| `Replace_Element (V, I, Ptr)` | **Swap**: old element is moved out (deallocated or returned); `Ptr` is moved in |
| `Clear (V)` | **Deallocate all**: every owned element is freed |
| Container scope exit | **Deallocate all**: same as `Clear` |

For non-access element types (integers, records without access components),
assignment is a copy and ownership is not involved. The complexity only arises
when `Element_Type` is or contains an access type.

**Proposed restriction for v0.4:** Generic containers may only be instantiated
with element types that have **copy semantics** — no access types, no records
with access-type components. This eliminates the ownership-through-containers
problem entirely for the initial release.

Owning containers (where `Element_Type` is an access type) are deferred to
v0.5, which requires:
- A `with Ownership` formal type class that opts into move semantics
- Compiler-generated deallocation in `Clear` and scope-exit paths
- Proof obligations that the container's internal array doesn't alias

### D27 — Runtime checks and proof obligations

Preconditions on generic operations produce proof obligations at each call
site, just as they do for non-generic operations. The instantiated concrete
package has concrete preconditions with concrete types — GNATprove handles
this without special support.

### K Semantics

"No template instantiation or monomorphization is needed. Every construct in
a Safe program is concrete." — this property is preserved. After generic
expansion, the K semantics sees only concrete packages. The expansion happens
in the compiler frontend, before the semantic representation that K formalizes.

The K semantics does not need to model generics. It models the output of
generic expansion, which is ordinary Safe code.

### Channels

Generic container types can be sent through channels if the element type is
a channel-legal type (no access components in v0.4, per the ownership
restriction above). The container is moved through the channel like any
other value type.

### D12 — No overloading

Generic instantiation does not introduce overloading. Each instantiation
creates a distinctly named package. `Sample_Vectors.Append` and
`Reading_Vectors.Append` are different subprograms in different packages —
no overload resolution required.

## Implementation Effort

### Compiler changes

| Component | Work | Estimate |
|-----------|------|----------|
| Parser | Accept `generic` declaration + instantiation syntax | Small — syntax is regular |
| Name resolution | Resolve formal type parameters as placeholder types | Medium |
| Type checking | Validate generic body with formal types; re-validate at instantiation with actuals | Medium — the core new work |
| Expansion | Substitute actuals for formals, produce concrete package AST | Medium |
| Emitter | Emit concrete package (no change to emission strategy) | Small |
| Error messages | Report errors in terms of both generic body and instantiation site | Medium |

### Spec changes

- **§2.1.11 (¶69):** Replace "excluded in its entirety" with "restricted subset
  retained" and enumerate the retained/excluded features.
- **Annex A (retained library):** Add generic container packages to the retained
  library surface.
- **New section:** Generic units — syntax, restrictions, expansion model,
  ownership restrictions.

### Test suite

- Positive tests: instantiation with discrete, range, and private types;
  nested records as element types; multiple instantiations of same generic;
  precondition proofs through instantiated operations.
- Negative tests: generic subprograms rejected; formal subprogram parameters
  rejected; access-type element instantiation rejected (v0.4 restriction);
  formal package parameters rejected.
- GNATprove integration: emitted concrete packages pass Silver-level
  verification.

## Standard Library Additions

With restricted generics, the retained library grows to include Safe-native
generic containers:

| Package | Description |
|---------|-------------|
| `Safe.Bounded_Vectors` | Generic bounded vector (array + length) |
| `Safe.Bounded_Ordered_Maps` | Generic bounded sorted map (sorted array of key-value pairs) |
| `Safe.Bounded_Ordered_Sets` | Generic bounded sorted set (sorted array, unique elements) |
| `Safe.Bounded_Ring_Buffers` | Generic bounded circular buffer (useful for channel-like patterns) |

The v0.3 monomorphic packages (`Safe.Integer_Vectors`, etc.) become
instantiations of the generic versions:

```
package Safe.Integer_Vectors is new Safe.Bounded_Vectors
   (Element_Type = Integer,
    Index_Type   = Positive);
```

They remain in the library for backward compatibility but are no longer
hand-written — they're generated from the generic.

## Migration from v0.3

v0.3 monomorphic containers are designed as a strict API subset of v0.4
generics. Migration is mechanical:

| v0.3 code | v0.4 equivalent |
|-----------|----------------|
| `V : Safe.Integer_Vectors.Vector (100)` | `V : My_Vectors.Vector (100)` where `My_Vectors` is an instantiation |
| `Safe.Integer_Vectors.Append (V, 42)` | `My_Vectors.Append (V, 42)` |

The operations, preconditions, and types are identical. Only the package name
changes.

## Alternatives Considered

1. **Type-level syntax sugar only** — `type Readings is vector of Sample capacity 256`
   that lowers to emitted SPARK generic instantiations, with no `generic`
   keyword in Safe source. Simpler for the user but creates a closed set of
   container kinds (only the built-in vector/map/set). Users cannot define
   their own generic packages.

2. **Full Ada §12 generics** — retain everything including formal subprogram
   parameters, formal packages, and generic child packages. More expressive
   but significantly more complex. The formal subprogram parameter (`with
   function "<" (A, B : T) return Boolean`) is the single most powerful — and
   most complex — feature. Deferring it to v1.0 is the right trade.

3. **Zig-style comptime** — replace generics with compile-time evaluation
   that produces concrete types. Powerful but a radical departure from Ada
   semantics and would require a fundamentally different compiler architecture.

4. **Status quo (no generics)** — continue with monomorphic containers
   indefinitely. Not viable for adoption. The boilerplate cost grows linearly
   with the number of user-defined types.

## Open Questions

1. **Should `with function` be included in v0.4?** Formal subprogram
   parameters (specifically comparison functions) are needed for sorted
   containers over user-defined types. Without `with function "<"`, an
   `Ordered_Map` generic can only be instantiated with types that have a
   built-in ordering. Including a restricted form (only `"<"` and `"="`)
   would cover the sorted-container use case without opening the full
   formal-subprogram complexity.

2. **Instantiation location.** Should instantiations be allowed only at
   package level, or also inside subprogram bodies? Package-level-only is
   simpler (each instantiation is a compilation unit) but less flexible.

3. **Emitter strategy.** Safe-side expansion (recommended) vs. SPARK library
   delegation. The latter reuses proven implementations but creates a
   dependency on SPARK library availability.

4. **Naming convention for instantiations.** Should the compiler enforce a
   naming pattern (e.g., `Element_Vectors` for a vector of `Element`)? Or
   is the name entirely user-chosen?

5. **Default values for formal private types.** The `Element_Type'Default`
   used in array initialization requires that the actual type has a default
   value. Should this be a constraint on the formal parameter, or should the
   generic body avoid relying on default initialization?

## Timeline

| Milestone | Target |
|-----------|--------|
| Proposal finalized | v0.3 (this document) |
| Spec amendment drafted | v0.4-alpha |
| Parser + name resolution | v0.4-alpha |
| Type checking + expansion | v0.4-beta |
| Standard generic containers | v0.4-beta |
| GNATprove integration verified | v0.4-rc |
| Ownership-through-containers (access types) | v0.5 |
| Formal subprogram parameters | v1.0 |
