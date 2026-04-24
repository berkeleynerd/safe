# Section 3 — Single-File Units

**This section is normative.**

This section specifies the Safe compilation-unit model. A Safe unit is a single
source file containing all declarations, subprogram bodies, and any admitted
unit-scope statements. There are no separate specification and body files. A
conforming implementation shall make the public interface of explicit package
units available to dependent compilation units for separate compilation; the
mechanism is implementation-defined.

---

## 3.1 Syntax

### 3.1.1 Compilation Units

1. A Safe compilation unit consists of a context clause followed by either an
explicit package unit or a packageless entry unit:

```
compilation_unit ::=
    context_clause unit

unit ::=
    package_unit
  | entry_unit

context_clause ::=
    { with_clause }

with_clause ::=
    'with' package_name { ',' package_name } terminator

package_unit ::=
    'package' defining_identifier
        INDENT
            unit_item_list
        DEDENT

entry_unit ::=
    unit_item_list

unit_item_list ::=
    { package_item }
    { unit_statement }
```

2. In an entry unit, the unit name is inferred from the source filename stem.

### 3.1.2 Unit Declarations and Statements

3. The following declarations may appear at unit scope before any unit-scope
statement:

```
package_item ::=
    basic_declaration
  | task_declaration
  | channel_declaration
  | use_type_clause
  | representation_item
  | pragma

unit_statement ::=
    statement
```

4. Safe has no separate package body file. For explicit package units, any
unit-scope statements execute in source order at package elaboration. For entry
units, unit-scope statements form the executable root of the single source
file.

### 3.1.3 Subprogram Bodies

5. Subprogram bodies appear at the point of declaration. A subprogram is
declared and defined in one place, except for forward declarations for mutual
recursion.

### 3.1.4 Interleaved Declarations in Subprogram Bodies

6. Inside subprogram bodies, declarations and statements may interleave
freely. A declaration is visible from its point of declaration to the end of
the enclosing scope:

```
sequence_of_statements ::=
    statement { statement }
  | statement { interleaved_item }

interleaved_item ::=
    statement | basic_declaration
```

### 3.1.5 Visibility Annotation

7. In an explicit package unit, the `public` keyword may precede an admitted
top-level declaration to make it visible to client packages. Declarations
without `public` are private to the package.

8. A packageless entry unit is not a library unit. It shall not contain any
`public` declaration.

### 3.1.6 Opaque Type Syntax

9. A type may be public in name but private in structure:

```
public type t is private record
    field1 : type1
    field2 : type2
```

Clients can declare variables of type `T` (the implementation exports size and alignment) but cannot access fields.

---

## 3.2 Legality Rules

### 3.2.1 Entry Unit Naming

10. The filename stem of a packageless entry unit shall be a valid lowercase
Safe identifier. A conforming implementation shall reject an entry unit whose
filename stem is not a valid defining identifier.

### 3.2.2 Declaration-Before-Use

11. Every name used in a declaration or statement shall have been declared
earlier in the same scope or in a `with`'d package. A conforming implementation
shall reject any reference to a name that has not been declared at or before
the point of use.

12. This rule applies within unit declarations, within unit-scope statements,
within subprogram bodies, and to names from `with`'d packages.

### 3.2.3 Forward Declarations for Mutual Recursion

13. Forward declarations are permitted for subprograms to enable mutual
recursion. A forward declaration is a subprogram declaration (Section 8) that
bears a logical-line terminator and has no body.

14. The body completing a forward declaration shall appear later in the same
declarative region. The subprogram specification of the body shall conform to
the forward declaration.

15. A conforming implementation shall reject a forward declaration with no
completing body in the same declarative region.

16. If the subprogram is public, the `public` keyword shall appear on the
forward declaration. The completing body shall not repeat the `public` keyword.
A conforming implementation shall reject a completing body that bears `public`
when a forward declaration for the same subprogram exists.

### 3.2.4 Unit-Scope Statements

17. Unit-scope statements are permitted after declarations in both explicit
package units and packageless entry units.

18. Once the first unit-scope statement appears, later unit-scope declarations
are illegal. A conforming implementation shall reject any declaration appearing
after a unit-scope statement.

19. Unit-scope statements use the same statement forms and name-resolution
rules as subprogram-body statements, except that statement-local declarations do
not appear at unit scope.

20. Variable initialisation uses expressions or function calls at the point of
declaration. These initialising expressions are evaluated before any later
unit-scope statements in the same compilation unit (see §3.4).

### 3.2.5 Public Keyword Visibility Rules

21. In an explicit package unit, the `public` keyword may appear before the
following declarations:

   (a) Type declarations (including incomplete type declarations).

   (b) Subtype declarations.

   (c) Object declarations (variables and constants).

   (d) Number declarations.

   (e) Subprogram declarations and subprogram bodies.

   (f) Expression function declarations.

   (g) Channel declarations.

   (h) Renaming declarations.

22. The `public` keyword shall not appear before:

   (a) Task declarations. Tasks are execution entities internal to the
       enclosing compilation unit; their effects are exposed through channels
       and subprograms.

   (b) Pragmas.

   (c) Representation items (except when applied to a type or object declaration).

   (d) `use type` clauses.

23. A conforming implementation shall reject any `public` annotation on a
declaration kind not listed in paragraph 21, and shall reject all `public`
annotations in a packageless entry unit.

24. A declaration without the `public` keyword is private to the declaring
explicit package unit and shall not be directly visible to any other
compilation unit.

### 3.2.6 Opaque Types

25. A declaration of the form `public type T is private record ...`
declares an opaque type. The type name `T` is visible to clients; the record
structure is not.

26. Client capabilities for an opaque type:

   (a) Declare objects of type `T`.

   (b) Pass objects of type `T` as parameters.

   (c) Assign objects of type `T` (unless limited).

   (d) Test equality of objects of type `T` (predefined `==` and `!=`).

27. Clients shall not access individual fields of an opaque type. A conforming
implementation shall reject any selected component on an opaque type that names
a record field, when the reference occurs outside the declaring package.

28. The implementation shall export sufficient information for clients to
allocate objects of the opaque type (size and alignment).

### 3.2.7 Dot Notation for Attributes

29. All attribute references in Safe use dot notation (`x.first`) instead of
tick notation (`X'First`). See Section 2, §2.4.1 for the complete resolution
rule.

30. When `X.Name` appears in source, the implementation resolves it as follows:

   (a) If `X` denotes a record object, `Name` is resolved as a record component.

   (b) If `X` denotes a type or subtype mark, `Name` is resolved as an attribute.

   (c) If `X` denotes a package name, `Name` is resolved as a declaration in that package.

   (d) If `X` denotes an access value, `Name` is resolved as implicit dereference followed by component selection.

31. This resolution is unambiguous because Safe has no overloading and no
tagged types. The type or kind of `X` is always known at the point of use due
to declaration-before-use.

### 3.2.8 Type Annotation Syntax

32. Ada's qualified expression syntax `T'(Expr)` is replaced by type
annotation syntax `(Expr as T)`.

33. Parentheses are always required around type annotation expressions. The
keyword `as` binds looser than any operator.

34. Examples:

   (a) Aggregate disambiguation: `((others = 0) as Buffer_Type)`

   (b) Allocators: `new (Expr as T)` instead of `new T'(Expr)`

   (c) In argument position: `Foo ((X as T))`

### 3.2.9 Circular Dependencies Prohibited

35. Circular `with` dependencies among compilation units are prohibited. A
conforming implementation shall reject any set of compilation units forming a
cycle in the `with` dependency graph.

### 3.2.10 Library Units

36. An explicit package unit is an importable library unit. A packageless entry
unit is an executable root, not a library unit. A conforming implementation
shall reject any attempt to import an entry unit, and shall reject any
library-level subprogram declaration or body as a compilation unit.

---

## 3.3 Static Semantics

### 3.3.1 Dependency Interface Information

37. A conforming implementation shall make the following information available
for each separately compiled unit, to support cross-unit legality checking. For
explicit package units, this information supports separate compilation. For
entry units, the information may be emitted for regularity, but entry-unit
interfaces are not importable:

   (a) **Visibility:** Which declarations bear the `public` keyword.

   (b) **Types:** For each public type, the type kind, constraints, and component information. For opaque types, size and alignment but not field layout.

   (c) **Subprogram signatures:** Parameter profiles (names, types, modes, default values) for all public subprograms.

   (d) **Effect summaries:** For each public subprogram, a conservative
       interprocedural summary (including transitive callees) of the unit-level
       variables read and written. This information is needed for callers to
       compute their own flow information and for task-variable ownership
       checking across packages. The summary may be conservatively
       over-approximate; precision may improve over time without affecting
       conformance.

   (e) **Constants and named numbers:** Values of public constants and named numbers, to the extent needed for static expression evaluation.

   (f) **Channel declarations:** Type, capacity, and visibility of public channels.

   (g) **Package dependencies:** The `with` dependency list.

   (h) **Incomplete type declarations:** Public incomplete type declarations for forward references.

   (i) **Channel-access summaries:** For each public subprogram, a conservative interprocedural summary (including transitive callees) of the channels accessed by `send`, `receive`, or `try_receive` — directly or transitively. This information is needed for ceiling priority computation across packages (Section 4, §4.2, paragraph 21a). The summary may be conservatively over-approximate; an over-approximate summary may raise ceiling priorities above the necessary minimum but does not compromise correctness.

38. The mechanism for conveying this information (e.g., symbol files, compiler
databases) is implementation-defined.

39. If required dependency interface information is unavailable for a `with`'d
package, the program shall be rejected.

### 3.3.2 Client Visibility

40. A client package that `with`s a provider package has visibility of all
public declarations of the provider. Non-public declarations of the provider
are not visible to the client.

41. Qualified naming is required: `Provider.Name`. General `use` clauses are
excluded (Section 2, §2.1.7). `use type` clauses are retained.

### 3.3.3 Opaque Type Visibility

42. For a public opaque type `T` declared as `public type T is private record
...`:

   (a) Within the declaring package: the full record structure is visible; fields may be accessed.

   (b) In client packages: only the type name, size, and alignment are visible; fields shall not be accessed.

### 3.3.4 Child Packages

43. Child packages and hierarchical package names are retained. A child package
`Parent.Child` has visibility into the public declarations of its parent.

44. A child package does not have additional visibility into the non-public
declarations of its parent beyond what `with Parent;` provides. This is a
consequence of Safe's single-file model: there is no separate "private part"
that child packages could see.

### 3.3.5 Name Resolution

45. Name resolution in Safe is unambiguous. When a name `X` appears in source:

   (a) The implementation searches the current declarative region for a declaration of `X`.

   (b) If not found, the implementation searches enclosing declarative regions (for nested scopes within a subprogram body).

   (c) If `X` is qualified (`P.X`), the implementation looks up `P` as a package name and resolves `X` within that package's public declarations.

   (d) If `X` is a selected component (`R.F`), resolution follows §3.2.7.

   (e) At most one declaration matches any given name at any program point (no overloading).

---

## 3.4 Dynamic Semantics

### 3.4.1 Package Initialisation

46. Unit-level variable initialisers are evaluated at load time in declaration
order (top to bottom), as in Ada. An initialiser may reference previously
declared variables and call previously declared functions within the same
compilation unit.

47. After all unit-level declarations have been elaborated, any unit-scope
statements execute in source order.

48. Referencing a not-yet-declared entity in an initialiser or unit-scope
statement is a legality error (declaration-before-use, paragraph 11).

### 3.4.2 Cross-Package Initialisation Order

49. If package A `with`s package B, then B's initialisers and unit-scope
statements complete before A's initialisers begin. This matches Ada's
elaboration semantics but is trivially satisfiable because Safe compilation
units have no circular `with` dependencies (paragraph 35).

50. The initialisation order across all compilation units is a topological sort
of the `with` dependency graph. The order among units with no direct or
transitive dependency is implementation-defined but deterministic for a given
program.

### 3.4.3 Task Startup Sequencing

51. All unit-level initialisation and unit-scope statements across all
compilation units complete before any task begins executing. See Section 4 for
task startup semantics.

---

## 3.5 Implementation Requirements

### 3.5.1 Dependency Interface Mechanism

52. A conforming implementation shall provide a mechanism for conveying
dependency interface information (paragraph 37) between separately compiled
units. The mechanism is implementation-defined.

53. The mechanism shall be sufficient to support:

   (a) Legality checking of client code against provider interfaces.

   (b) Task-variable ownership checking using effect summaries from transitive dependencies.

   (c) Incremental recompilation when a provider's interface changes.

### 3.5.2 Separate Compilation

54. A conforming implementation shall support separate compilation of explicit
package units. Each explicit package unit shall be compilable independently,
given only its source and the dependency interface information of its `with`'d
packages.

55. A conforming implementation shall support separate checking and emission of
packageless entry units. Entry units are executable roots, not importable
libraries.

---

## 3.6 Examples

### 3.6.1 Example: Simple Package

**Conforming Example.**

```ada
-- temperatures.safe

package Temperatures is

    public type Kelvin is digits 6 range 0.0 .. 1.0E6;

    public subtype Room_Temperature is Kelvin range 273.15 .. 323.15;

    Absolute_Zero : constant Kelvin = 0.0;

    public function To_Celsius (T : Kelvin) return Float is
    begin
        return Float(T) - 273.15;
        -- D27 proof: Float range sufficient; no narrowing issue
    end To_Celsius;

    public function To_Kelvin (C : Float) return Kelvin is
    begin
        return Kelvin(C + 273.15);
        -- D27 proof: range check at return to Kelvin
    end To_Kelvin;

end Temperatures;
```

### 3.6.2 Example: Opaque Types

**Conforming Example.**

```safe
-- buffers.safe

package buffers

    public subtype buffer_size is integer (1 to 4096)
    public subtype buffer_index is buffer_size

    public type buffer is private record
        data   : string (4096) = ""
        length : buffer_size = 1

    public function create (size : buffer_size) returns buffer
        return (data = "", length = size)
        -- D27 proof: aggregate values in range

    public function get (b : buffer; i : buffer_index) returns string
        return b.data(i)
        -- D27 proof: i is buffer_index, same as array index type (Rule 2)

    public function length (b : buffer) returns buffer_size
        return b.length
    -- D27 proof: b.length is buffer_size by declaration

```

### 3.6.3 Example: Inter-Package Dependency

**Conforming Example — Provider package.**

```ada
-- units.safe

package Units is

    public type Metres is digits 8 range 0.0 .. 1.0E12;
    public type Seconds is digits 8 range 0.001 .. 1.0E9;
    public type Metres_Per_Second is digits 8 range 0.0 .. 3.0E8;

    public function Speed (D : Metres; T : Seconds) return Metres_Per_Second is
    begin
        return Metres_Per_Second(Float(D) / Float(T));
        -- D27 proof: Seconds excludes zero (range starts at 0.001)
    end Speed;

end Units;
```

**Conforming Example — Client package.**

```safe
-- navigation.safe

with units

package navigation

    public subtype heading is integer (0 to 359)

    current_speed : units.metres_per_second = 0.0
    current_heading : heading = 0

    public procedure update (d : units.metres; t : units.seconds;
                             h : heading)
        current_speed = units.speed(d, t)
        current_heading = h

    public function get_speed returns units.metres_per_second
        return current_speed
    -- D27 proof: return type matches declaration type

```

### 3.6.4 Example: Interleaved Declarations, Dot Notation, Type Annotation

**Conforming Example.**

```safe
-- sensors.safe

package sensors

    public subtype reading is integer (0 to 4095)
    public subtype channel_id is integer (0 to 7)
    public subtype channel_count is integer (1 to 8)

    type calibration is private record
        scale  : float = 1.0
        bias   : integer = 0

    cal_table : array (channel_id) of calibration =
        (others = (scale = 1.0, bias = 0))

    initialized : boolean = false

    public function is_initialized returns boolean

        return initialized

    public procedure initialize
        default_cal : constant calibration = (scale = 1.0, bias = 0)
        -- Interleaved declaration near the top of the body
        for i in channel_id.first .. channel_id.last loop
            -- Dot notation for attributes: channel_id.first, channel_id.last
            cal_table (i) = default_cal
        initialized = true

    public function average (a, b : reading) returns reading

        return (a + b) / 2
        -- D27 Rule 1: max (4095+4095)/2 = 4095
        -- D27 Rule 3(b): literal 2 is a static nonzero expression
        -- D27 proof: result in 0..4095

    public function scale (r : reading; divisor : channel_count) returns integer

        return integer (r) / divisor
        -- D27 Rule 3(a): Channel_Count range 1..8 excludes zero
        -- D27 proof: division is safe

    function read_adc (channel : channel_id) returns reading is separate

```


---

## 3.7 Relationship to 8652:2023

50. The following table summarises how Safe's package model relates to 8652:2023:

| 8652:2023 Feature | Safe Status |
|-------------------|-------------|
| Package specifications (§7.1) | Modified — single-file model, `public` visibility |
| Package bodies (§7.2) | Excluded — no separate body |
| Private types (§7.3) | Replaced by `private record` in single-file model |
| Private extensions (§7.3) | Excluded — no tagged types |
| Deferred constants (§7.4) | Excluded — no separate body for completion |
| Limited types (§7.5) | Retained |
| Controlled types (§7.6) | Excluded — ownership-based deallocation instead |
| With clauses (§10.1.2) | Retained |
| Subunits (§10.1.3) | Retained (`is separate`) |
| Child packages (§10.1.1) | Retained |
| Elaboration control (§10.2.1) | Simplified — topological sort, no circular deps |
