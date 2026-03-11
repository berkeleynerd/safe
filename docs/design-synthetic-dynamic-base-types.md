# Design: Synthetic Dynamic Base Types

**Status: Exploratory Draft**
**Author: Claude (design exploration)**
**Date: 2026-03-11**

---

## 1. Problem Statement

Safe excludes generics (D16), tagged types (D18), controlled types, exceptions (D14), operator overloading (D12), and the entire `Ada.Containers.*` hierarchy. The standard string libraries (`Ada.Strings.Fixed`, `.Bounded`, `.Unbounded`) are also excluded because they depend on generics or controlled types.

This leaves users of the "general application" layer — those writing business logic, data transformation, protocol handling — with only raw access types and manual `new`/ownership-transfer for any dynamically-sized data. This is the correct foundation for a systems language, but the resulting surface experience is closer to writing a linked list in C than to writing in Pascal, Modula-2, or Oberon, where the programmer declares a `STRING` or `ARRAY OF T` and the language handles storage.

**Goal:** Introduce a small set of *compiler-known, language-defined* dynamic types whose implementation details (heap arenas, growth strategies, internal pointers) are entirely hidden from the user. Users write code that looks and feels like working with value types in a Wirth-family language.

---

## 2. Design Principles

1. **No new language mechanisms.** Synthetic types are defined within the existing type system (records, access types, discriminants). They are *language-defined*, not user-definable — analogous to how `Integer` and `String` are defined in `Standard` without the user needing to understand their representation.

2. **Implementation-invisible.** The internal representation — whether backed by a pre-allocated arena, a resizable heap buffer, a region allocator, or a slab — is not observable by the user. The spec defines the *operational semantics* (what operations exist and what they mean), not the *representation*.

3. **Ownership-compatible.** Synthetic types participate fully in Safe's ownership model. A `Text` value is owned by exactly one variable. Assignment is a move (transferring the backing storage). Borrowing and observing work as with any other owned type.

4. **Silver-provable.** All operations on synthetic types are total — no operation can cause a runtime error under any input. Index-returning operations return option-style results or bounded subtypes. Length-querying operations are pure. This preserves Safe's D27 Silver guarantee without annotations.

5. **No generics required.** Each concrete element type gets its own named synthetic type. This is the cost of D16 — but it is the same cost Oberon and original Pascal paid, and it produces clear, greppable, unambiguous code.

6. **Scope-bound lifetime.** Like all owned resources in Safe, synthetic values are automatically reclaimed at scope exit. There is no garbage collector, no finaliser.

---

## 3. Proposed Synthetic Types

### 3.1 `Text` — Dynamic Character Sequence

The moral equivalent of Oberon's `Texts.Text` or Pascal's `string`. A variable-length, heap-backed character sequence with value-move semantics.

```
-- Declaration (in the user's .safe file)
Greeting : Text;
Name     : Text := To_Text("Alice");
Message  : Text := Name & To_Text(" says hello");
```

**Operations (dot notation):**

| Operation | Signature | Semantics |
|-----------|-----------|-----------|
| `To_Text(S)` | `function To_Text(S : String) return Text;` | Create from fixed string |
| `To_String(T)` | `function To_String(T : access constant Text) return String;` | Observe as fixed string |
| `T.Length` | attribute returning `Natural` | Current character count |
| `T.Capacity` | attribute returning `Natural` | Current backing capacity |
| `T.Is_Empty` | attribute returning `Boolean` | `T.Length = 0` |
| `T.Element(I)` | `function ... return Character;` | Character at index; Silver requires `I in 1..T.Length` |
| `T.Slice(Low, High)` | `function ... return Text;` | New text from sub-range |
| `Append(T, S)` | `procedure Append(T : in out Text; S : String);` | Append fixed string |
| `Append(T, U)` | `procedure Append(T : in out Text; U : access constant Text);` | Append another text (observed) |
| `T & U` | concatenation operator (predefined, not overloaded) | Returns new `Text` |
| `Clear(T)` | `procedure Clear(T : in out Text);` | Set length to zero, retain capacity |
| `T.Find(C)` | `function ... return Natural;` | 0 if not found, else first index |

**Note on `&` (concatenation):** Safe excludes *user-defined* operator overloading (D12), but `&` for `Text` is *predefined by the language*, exactly as `&` is predefined for `String` in Ada/Safe. No user-defined operator function is introduced.

**Note on naming: why not `String`?** `String` is already the Ada fixed-length character array type retained in Safe's `Standard`. `Text` avoids collision and signals dynamic semantics, following the Oberon precedent (`Texts.Text`).

### 3.2 `Byte_Buffer` — Dynamic Octet Sequence

For protocol work, binary data, and I/O buffers. The moral equivalent of a dynamically-sized `Storage_Array`.

```
Buf : Byte_Buffer := To_Buffer((16#48#, 16#65#, 16#6C#, 16#6C#, 16#6F#));
```

**Operations:** Parallel to `Text` but operating on `Storage_Element` values. Includes `T.Octet(I)`, `Append`, `Slice`, `T.Length`, etc.

### 3.3 Concrete Collection Types

Since Safe has no generics, each desired element type gets a distinct collection type. A conforming implementation shall provide at minimum the following:

#### 3.3.1 `Integer_Vector` — Dynamic Sequence of Integer

```
Scores : Integer_Vector;
Append(Scores, 42);
Append(Scores, 99);
Total : Integer := Scores.Element(1) + Scores.Element(2);
```

**Operations:**

| Operation | Semantics |
|-----------|-----------|
| `V.Length` | Current element count |
| `V.Capacity` | Current backing capacity |
| `V.Is_Empty` | `V.Length = 0` |
| `V.Element(I)` | Element at index; Silver requires `I in 1..V.Length` |
| `Append(V, E)` | Append element |
| `Replace(V, I, E)` | Replace at index; Silver requires `I in 1..V.Length` |
| `Clear(V)` | Set length to zero |
| `V.First` / `V.Last` | First/last index (1 and V.Length) |

#### 3.3.2 `Float_Vector` — Dynamic Sequence of Float

Same interface as `Integer_Vector` but for `Float` elements.

#### 3.3.3 `Boolean_Vector` — Dynamic Sequence of Boolean

Same interface, potentially with packed representation.

### 3.4 Future Concrete Types (not in initial set)

A conforming implementation may additionally provide:

- `Long_Integer_Vector`, `Long_Float_Vector`
- `Character_Vector`
- `Text_Vector` (vector of `Text` — requires nested ownership)
- `Integer_Table` / `Text_Table` (associative key-value maps)

These follow the same pattern. The specification can add concrete types in future revisions without language mechanism changes.

---

## 4. Ownership Semantics for Synthetic Types

Synthetic types are **owning types** — they own their backing storage. This means:

### 4.1 Move on Assignment

```
A : Text := To_Text("hello");
B : Text := A;              -- move: A becomes empty, B owns the buffer
-- A.Length is now 0 (A is in the moved-from state)
```

After a move, the source is in a valid but empty state (not null — synthetic types are not access types from the user's perspective). This is a key design choice: **moved-from synthetic values are empty, not undefined**. This preserves Silver because there is no uninitialised read — the moved-from variable holds a well-defined empty value.

**Rationale:** Unlike raw access types where the moved-from variable becomes null (and dereferencing null is a runtime error), synthetic types guarantee a safe moved-from state. This is more ergonomic and eliminates an entire class of null-check obligations.

### 4.2 Borrowing

```
A : Text := To_Text("hello");
B : access Text := A;       -- borrow: A frozen while B in scope
Append(B, " world");        -- mutate through borrow
-- B goes out of scope: A is unfrozen, now contains "hello world"
```

### 4.3 Observing

```
A : Text := To_Text("hello");
B : access constant Text := A.Access;  -- observe: A frozen for writes
Len : Natural := B.Length;              -- read through observer
-- B goes out of scope: A is unfrozen
```

### 4.4 Channel Transfer

```
channel Messages : Text capacity 10;

task Producer is
   Msg : Text := To_Text("ping");
   send Messages, Msg;    -- Msg moved into channel; Msg is now empty
end Producer;

task Consumer is
   Received : Text;
   receive Messages, Received;  -- Received now owns the buffer
end Consumer;
```

### 4.5 Scope-Exit Deallocation

```
procedure Process is
   Buf : Text := To_Text("temporary");
   -- ... use Buf ...
end Process;  -- Buf's backing storage is automatically reclaimed
```

---

## 5. Implementation Strategies (Informative)

This section is informative — it describes *how* a conforming implementation might realise synthetic types. The user never sees any of this.

### 5.1 Arena-per-Scope

Each lexical scope that contains synthetic type declarations allocates from a per-scope arena. When the scope exits, the entire arena is freed in one operation.

**Advantages:**
- Extremely fast deallocation (one `free` per scope, not per object)
- Cache-friendly allocation (sequential bumps within the arena)
- No fragmentation within a scope's lifetime
- Natural fit for Safe's scope-exit deallocation model

**Disadvantages:**
- Memory is not reclaimed until scope exit (even if individual values are moved away)
- Requires sizing heuristics or growth

**Mitigation for long-lived scopes (e.g., task main loops):** The arena for a loop body is reset at each iteration boundary, matching Safe's existing pattern where variables declared inside a loop are destroyed at each iteration end (spec §2.3.5, paragraph 104).

### 5.2 Per-Task Arena Pool

Each static task gets a private arena pool. Since Safe's tasks do not share mutable state (D28), per-task arenas require no synchronisation.

```
Task A: [Arena Pool A] ──> arena for scope 1, arena for scope 2, ...
Task B: [Arena Pool B] ──> arena for scope 1, arena for scope 2, ...
```

Arenas within a pool can be recycled using a free-list, reducing system allocator pressure.

### 5.3 Small-Buffer Optimisation (SBO)

For `Text` and small vectors, embed a small inline buffer (e.g., 64 or 128 bytes) directly in the stack-allocated record. Only spill to the heap arena when the content exceeds the inline capacity.

```
-- Conceptual internal layout (never visible to users):
type Text_Rep is record
   Inline  : String(1..64);     -- small-buffer optimisation
   Heap    : access String;     -- used when Length > 64
   Length  : Natural := 0;
   In_Heap : Boolean := False;
end record;
```

This means that typical short strings (`"hello"`, error codes, identifiers) never touch the heap at all.

### 5.4 Pre-Allocated Capacity Pools

For embedded or real-time targets, an implementation may pre-allocate fixed-capacity pools at elaboration time:

```
-- Implementation-internal configuration (not visible to Safe source):
-- Text arena:       64 KiB per task, 256-byte chunks
-- Integer_Vector:   32 KiB per task, 4-byte elements, 1024-element chunks
```

This gives deterministic allocation with no runtime `malloc`, suitable for systems where heap allocation is forbidden after initialisation.

### 5.5 Hybrid: Arena + SBO + Growth

The recommended default strategy:

1. Values start with SBO (inline buffer, zero heap allocation)
2. On first spill, allocate from the current scope's arena
3. On growth beyond arena chunk, double the allocation (amortised O(1) append)
4. On scope exit, reset the arena (O(1) deallocation of all spilled values)
5. On move, transfer the backing pointer (O(1) move, no copy)

---

## 6. Silver Integration

### 6.1 Index Safety (D27 Rule 2)

Indexing operations (`T.Element(I)`, `V.Element(I)`, `Replace(V, I, E)`) require the index to be in range `1..T.Length` (or `1..V.Length`). The Silver-by-construction rules apply exactly as for arrays:

```
-- ACCEPTED: index is provably in range
for I in 1 .. Scores.Length loop
   Total := Total + Scores.Element(I);
end loop;

-- REJECTED: I has type Integer, not provably in 1..Scores.Length
Total := Scores.Element(I);  -- diagnostic: index not provably in range
```

The `.Length` attribute returns a value of type `Natural`, so `1 .. T.Length` is a valid range and `I` within a `for` loop over that range is statically known to be in bounds.

### 6.2 No Division or Null Hazards

All synthetic type operations are total:
- No operation returns an access type that could be null
- No operation involves division
- `Find` returns `Natural` (0 for not-found) rather than raising an exception
- Allocation failure aborts (consistent with paragraph 103a)

### 6.3 Moved-From Safety

A moved-from synthetic value is empty (length 0), not undefined. Any subsequent use of a moved-from variable reads a valid empty container. This is stronger than the raw access type model (where moved-from becomes null and dereferencing is a runtime error).

**Alternative considered:** Making moved-from synthetic values *frozen* (unusable until reassigned), matching raw access semantics. Rejected because it adds annotation burden and the empty-state model is strictly safer.

### 6.4 Iteration Safety

The `for E of V` array iteration syntax (retained in Safe, spec §2.1.4 paragraph 30) extends naturally to synthetic vectors:

```
for Score of Scores loop
   Total := Total + Score;
end loop;
```

This requires no index variable and is safe by construction — the iteration is bounded by `V.Length` and each `Score` is a valid element.

---

## 7. Translation to Ada/SPARK

Following the existing translation rules (`compiler/translation_rules.md`), synthetic types map to Ada private types with SPARK-compatible bodies:

### 7.1 `Text` Emission

```ada
-- In the emitted .ads (visible part):
type Text is private;

function To_Text (S : String) return Text;
function Length (T : Text) return Natural;
function Element (T : Text; I : Positive) return Character
  with Pre => I <= Length (T);
procedure Append (T : in out Text; S : String);
procedure Clear (T : in out Text);

-- In the emitted .ads (private part) / .adb:
type Text is record
   Data   : access String;   -- heap-allocated backing
   Len    : Natural := 0;
   Cap    : Natural := 0;
end record;
```

The `Pre` contract on `Element` is emitted by the Safe compiler to satisfy GNATprove, even though the user never writes it — this is the "Silver without annotations" guarantee. The Safe compiler has already verified statically that all call sites satisfy `I <= Length(T)` via D27 Rule 2.

### 7.2 Arena Emission

If the implementation uses arena allocation, the emitted Ada code includes a hidden arena package:

```ada
-- Emitted as part of the runtime support:
package Safe_Runtime.Arenas is
   type Arena is limited private;
   function Allocate (A : in out Arena; Size : Positive) return System.Address;
   procedure Reset (A : in out Arena);
   -- ...
private
   -- implementation-defined
end Safe_Runtime.Arenas;
```

This package is part of the Safe runtime, not visible to user code.

---

## 8. Interaction with Existing Safe Features

### 8.1 Records Containing Synthetic Types

```
type Person is record
   Name : Text;
   Age  : Natural;
end record;

-- Assignment of Person moves the Name field:
P1 : Person := (Name => To_Text("Alice"), Age => 30);
P2 : Person := P1;  -- move: P1.Name is now empty, P1.Age is 0 (default)
```

Records containing synthetic fields become move-only types (they already are, since any record containing an owning access type is move-only under Safe's ownership rules).

### 8.2 Channels Carrying Synthetic Types

Synthetic types can be sent through channels. The backing storage is transferred to the receiving task:

```
channel Names : Text capacity 5;
send Names, To_Text("Alice");
```

### 8.3 Discriminated Records

Synthetic types can appear in non-discriminant record fields:

```
type Tagged_Message is record
   Kind    : Message_Kind;
   Payload : Text;
end record;
```

They cannot be discriminants themselves (discriminants must be discrete types in Ada/Safe).

---

## 9. What Users See vs. What the Compiler Does

### User's View (Pascal/Oberon-like)

```
package Greet is
   public procedure Run is
      Name    : Text := To_Text("World");
      Message : Text := To_Text("Hello, ");
      Append(Message, Name);

      Scores : Integer_Vector;
      Append(Scores, 100);
      Append(Scores, 95);
      Append(Scores, 87);

      Sum : Integer := 0;
      for I in 1 .. Scores.Length loop
         Sum := Sum + Scores.Element(I);
      end loop;

      pragma Assert(Sum = 282);
      pragma Assert(Message.Length = 12);
   end Run;
end Greet;
```

No `new`, no `access`, no null checks, no ownership annotations. The code reads like Oberon or Modula-2.

### Compiler's View (Hidden)

1. `Name` and `Message` are backed by a scope arena or SBO
2. `Append` may grow the backing buffer (arena allocation or realloc)
3. `Scores` is backed by a contiguous array in the arena
4. At `end Run`, the scope arena is reset, reclaiming all backing storage
5. The emitted Ada/SPARK code includes `Pre` contracts on `Element` calls
6. GNATprove verifies that `I in 1..Scores.Length` satisfies `Element`'s precondition

---

## 10. Specification Changes Required

To add synthetic dynamic base types, the following spec sections would need amendments:

| Section | Change |
|---------|--------|
| §00 Front Matter (D-table) | Add decision D30: "Predefined dynamic types" |
| §01 Base Definition | Note that `Standard` is extended with synthetic types |
| §02 Restrictions (§2.3) | Add §2.3.9: "Synthetic owning types" with move/borrow/observe rules |
| Annex A | Add §A.19: "Predefined Dynamic Types" listing `Text`, `Byte_Buffer`, `Integer_Vector`, `Float_Vector`, `Boolean_Vector` |
| §05 Assurance | Add D27 Rule 2 extension for synthetic type indexing |
| §08 Syntax Summary | No grammar changes needed — synthetic types use existing declaration syntax |
| Translation Rules | Add §15: "Synthetic type emission" |

### 10.1 No Grammar Changes

This is a critical property. Synthetic types require *zero* new syntax. They are used through existing Safe constructs:
- Type declarations: existing
- Variable declarations: existing
- Procedure calls: existing
- Dot-notation attributes: existing
- `for` loops: existing
- `&` concatenation: already predefined for string-like types

The entire feature is additive at the library/type-system level, not at the grammar level.

---

## 11. Open Questions

| ID | Question | Options |
|----|----------|---------|
| SYN-01 | Should moved-from synthetic values be *empty* or *frozen*? | Empty (proposed) vs. Frozen (matching raw access) |
| SYN-02 | Should `Text` support Unicode (`Wide_Character`) variants? | `Text` = `Character` only; add `Wide_Text` later vs. `Text` = UTF-8 from the start |
| SYN-03 | Minimum set of concrete vector types? | `{Integer, Float, Boolean}_Vector` (proposed) vs. larger set |
| SYN-04 | Should implementations be *required* to use arenas, or free to choose? | Informative (proposed) — the spec defines semantics, not strategy |
| SYN-05 | Should `Text` have a configurable maximum capacity for embedded targets? | `Text(Max => 256)` discriminant vs. implementation-defined global limit |
| SYN-06 | Should synthetic types be in `Standard` or in a `Safe.Collections` package? | `Standard` (most Oberon-like) vs. separate package (more modular) |
| SYN-07 | Should the `for E of V` syntax work for synthetic vectors? | Yes (proposed) — requires compiler support for `Element`/`Length` protocol |

---

## 12. Comparison with Wirth-Family Languages

| Feature | Pascal | Modula-2 | Oberon | **Safe (proposed)** |
|---------|--------|----------|--------|---------------------|
| Dynamic strings | `string` (Turbo Pascal) | `ARRAY OF CHAR` | `Texts.Text` | `Text` |
| Dynamic arrays | not standard | `OPEN ARRAY` | `POINTER TO ARRAY` | `Integer_Vector`, etc. |
| Memory management | hidden | `NEW`/`DISPOSE` | GC | Ownership + arena (hidden) |
| Generics | no | yes (Modula-3) | no | no |
| User sees heap? | no | yes | no (GC) | **no** |
| Runtime errors | yes | yes | yes | **no (Silver)** |

The proposed design gives Safe the ergonomics of Oberon (user never sees the heap) with the safety guarantees that none of the Wirth-family languages provide (Silver — no runtime errors by construction).

---

## 13. Summary

Synthetic dynamic base types solve the "missing middle" in Safe: between raw scalar types and raw access-with-ownership, there is currently no way to express variable-length data without exposing heap mechanics. The proposed design:

1. Adds a small, fixed set of compiler-known dynamic types (`Text`, `Byte_Buffer`, `*_Vector`)
2. Hides all allocation strategy behind the implementation (arenas, SBO, pools)
3. Integrates with ownership (move, borrow, observe) and Silver (total operations, bounded indexing)
4. Requires zero grammar changes
5. Preserves the "subtractive from Ada" philosophy — these types are *additions* to `Standard`, not new language mechanisms
6. Delivers a Pascal/Modula-2/Oberon programming experience for general application code
