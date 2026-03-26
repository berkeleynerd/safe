# Section 3 — Single-File Packages

**This section is normative.**

This section specifies the Safe package model. A Safe package is a single source file containing all declarations and subprogram bodies. There are no separate specification and body files. A conforming implementation shall make the public interface available to dependent compilation units for separate compilation; the mechanism is implementation-defined.

---

## 3.1 Syntax

### 3.1.1 Package Unit

1. A Safe compilation unit consists of a context clause followed by a package unit:

```
compilation_unit ::=
    context_clause package_unit

context_clause ::=
    { with_clause }

with_clause ::=
    'with' package_name { ',' package_name } ';'

package_unit ::=
    'package' defining_identifier 'is'
        { package_item }
    'end' defining_identifier ';'
```

### 3.1.2 Package Items

2. A package is a flat sequence of declarations. The following items may appear at the top level of a package:

```
package_item ::=
    basic_declaration
  | task_declaration
  | channel_declaration
  | use_type_clause
  | representation_item
  | pragma
```

3. There is no `package body` wrapper, no `begin...end` initialisation block, and no package-level executable statements.

### 3.1.3 Subprogram Bodies

4. Subprogram bodies appear at the point of declaration. A subprogram is declared and defined in one place, except for forward declarations for mutual recursion.

### 3.1.4 Interleaved Declarations in Subprogram Bodies

5. Inside subprogram bodies, declarations and statements may interleave freely after `begin`. A declaration is visible from its point of declaration to the end of the enclosing scope:

```
sequence_of_statements ::=
    statement { statement }
  | statement { interleaved_item }

interleaved_item ::=
    statement | basic_declaration
```

### 3.1.5 Visibility Annotation

6. The `public` keyword may precede any top-level declaration to make it visible to client packages. Declarations without `public` are private to the package.

### 3.1.6 Opaque Type Syntax

7. A type may be public in name but private in structure:

```
public type t is private record
    field1 : type1;
    field2 : type2;
end record;
```

Clients can declare variables of type `T` (the implementation exports size and alignment) but cannot access fields.

---

## 3.2 Legality Rules

### 3.2.1 Matching End Identifier

8. The `defining_identifier` after `end` in a package unit shall match the `defining_identifier` after `package`. A conforming implementation shall reject any package where the end identifier does not match.

### 3.2.2 Declaration-Before-Use

9. Every name used in a declaration or statement shall have been declared earlier in the same scope or in a `with`'d package. A conforming implementation shall reject any reference to a name that has not been declared at or before the point of use.

10. This rule applies within package declarations, within subprogram bodies, and to names from `with`'d packages.

### 3.2.3 Forward Declarations for Mutual Recursion

11. Forward declarations are permitted for subprograms to enable mutual recursion. A forward declaration consists of a subprogram specification followed by a semicolon, without a body.

12. The body completing a forward declaration shall appear later in the same declarative region. The subprogram specification of the body shall conform to the forward declaration.

13. A conforming implementation shall reject a forward declaration with no completing body in the same declarative region.

14. If the subprogram is public, the `public` keyword shall appear on the forward declaration. The completing body shall not repeat the `public` keyword. A conforming implementation shall reject a completing body that bears `public` when a forward declaration for the same subprogram exists.

### 3.2.4 No Package-Level Statements

15. A package shall not contain executable statements at the package level. All executable code shall appear within subprogram bodies or task bodies. A conforming implementation shall reject any executable statement appearing directly in the package item list.

16. Variable initialisation uses expressions or function calls at the point of declaration. These initialising expressions are evaluated at load time (see §3.4).

### 3.2.5 Public Keyword Visibility Rules

17. The `public` keyword may appear before the following declarations:

   (a) Type declarations (including incomplete type declarations).

   (b) Subtype declarations.

   (c) Object declarations (variables and constants).

   (d) Number declarations.

   (e) Subprogram declarations and subprogram bodies.

   (f) Expression function declarations.

   (g) Channel declarations.

   (h) Renaming declarations.

18. The `public` keyword shall not appear before:

   (a) Task declarations. Tasks are execution entities internal to the package; their effects are exposed through channels and subprograms.

   (b) Pragmas.

   (c) Representation items (except when applied to a type or object declaration).

   (d) `use type` clauses.

19. A conforming implementation shall reject any `public` annotation on a declaration kind not listed in paragraph 17.

20. A declaration without the `public` keyword is private to the declaring package and shall not be directly visible to any other compilation unit.

### 3.2.6 Opaque Types

21. A declaration of the form `public type T is private record ... end record;` declares an opaque type. The type name `T` is visible to clients; the record structure is not.

22. Client capabilities for an opaque type:

   (a) Declare objects of type `T`.

   (b) Pass objects of type `T` as parameters.

   (c) Assign objects of type `T` (unless limited).

   (d) Test equality of objects of type `T` (predefined `==` and `!=`).

23. Clients shall not access individual fields of an opaque type. A conforming implementation shall reject any selected component on an opaque type that names a record field, when the reference occurs outside the declaring package.

24. The implementation shall export sufficient information for clients to allocate objects of the opaque type (size and alignment).

### 3.2.7 Dot Notation for Attributes

25. All attribute references in Safe use dot notation (`x.first`) instead of tick notation (`X'First`). See Section 2, §2.4.1 for the complete resolution rule.

26. When `X.Name` appears in source, the implementation resolves it as follows:

   (a) If `X` denotes a record object, `Name` is resolved as a record component.

   (b) If `X` denotes a type or subtype mark, `Name` is resolved as an attribute.

   (c) If `X` denotes a package name, `Name` is resolved as a declaration in that package.

   (d) If `X` denotes an access value, `Name` is resolved as implicit dereference followed by component selection.

27. This resolution is unambiguous because Safe has no overloading and no tagged types. The type or kind of `X` is always known at the point of use due to declaration-before-use.

### 3.2.8 Type Annotation Syntax

28. Ada's qualified expression syntax `T'(Expr)` is replaced by type annotation syntax `(Expr as T)`.

29. Parentheses are always required around type annotation expressions. The keyword `as` binds looser than any operator.

30. Examples:

   (a) Aggregate disambiguation: `((others = 0) as Buffer_Type)`

   (b) Allocators: `new (Expr as T)` instead of `new T'(Expr)`

   (c) In argument position: `Foo ((X as T))`

### 3.2.9 Circular Dependencies Prohibited

31. Circular `with` dependencies among compilation units are prohibited. A conforming implementation shall reject any set of compilation units forming a cycle in the `with` dependency graph.

### 3.2.10 Library Units

32. A library unit shall be a package. Library-level subprograms are not permitted as compilation units. A conforming implementation shall reject any library-level subprogram declaration or body.

---

## 3.3 Static Semantics

### 3.3.1 Dependency Interface Information

33. A conforming implementation shall make the following information available for each package, to support separate compilation and cross-unit legality checking:

   (a) **Visibility:** Which declarations bear the `public` keyword.

   (b) **Types:** For each public type, the type kind, constraints, and component information. For opaque types, size and alignment but not field layout.

   (c) **Subprogram signatures:** Parameter profiles (names, types, modes, default values) for all public subprograms.

   (d) **Effect summaries:** For each public subprogram, a conservative interprocedural summary (including transitive callees) of the package-level variables read and written. This information is needed for callers to compute their own flow information and for task-variable ownership checking across packages. The summary may be conservatively over-approximate; precision may improve over time without affecting conformance.

   (e) **Constants and named numbers:** Values of public constants and named numbers, to the extent needed for static expression evaluation.

   (f) **Channel declarations:** Type, capacity, and visibility of public channels.

   (g) **Package dependencies:** The `with` dependency list.

   (h) **Incomplete type declarations:** Public incomplete type declarations for forward references.

   (i) **Channel-access summaries:** For each public subprogram, a conservative interprocedural summary (including transitive callees) of the channels accessed by `send`, `receive`, `try_send`, or `try_receive` — directly or transitively. This information is needed for ceiling priority computation across packages (Section 4, §4.2, paragraph 21a). The summary may be conservatively over-approximate; an over-approximate summary may raise ceiling priorities above the necessary minimum but does not compromise correctness.

34. The mechanism for conveying this information (e.g., symbol files, compiler databases) is implementation-defined.

35. If required dependency interface information is unavailable for a `with`'d package, the program shall be rejected.

### 3.3.2 Client Visibility

36. A client package that `with`s a provider package has visibility of all public declarations of the provider. Non-public declarations of the provider are not visible to the client.

37. Qualified naming is required: `Provider.Name`. General `use` clauses are excluded (Section 2, §2.1.7). `use type` clauses are retained.

### 3.3.3 Opaque Type Visibility

38. For a public opaque type `T` declared as `public type T is private record ... end record;`:

   (a) Within the declaring package: the full record structure is visible; fields may be accessed.

   (b) In client packages: only the type name, size, and alignment are visible; fields shall not be accessed.

### 3.3.4 Child Packages

39. Child packages and hierarchical package names are retained. A child package `Parent.Child` has visibility into the public declarations of its parent.

40. A child package does not have additional visibility into the non-public declarations of its parent beyond what `with Parent;` provides. This is a consequence of Safe's single-file model: there is no separate "private part" that child packages could see.

### 3.3.5 Name Resolution

41. Name resolution in Safe is unambiguous. When a name `X` appears in source:

   (a) The implementation searches the current declarative region for a declaration of `X`.

   (b) If not found, the implementation searches enclosing declarative regions (for nested scopes within a subprogram body).

   (c) If `X` is qualified (`P.X`), the implementation looks up `P` as a package name and resolves `X` within that package's public declarations.

   (d) If `X` is a selected component (`R.F`), resolution follows §3.2.7.

   (e) At most one declaration matches any given name at any program point (no overloading).

---

## 3.4 Dynamic Semantics

### 3.4.1 Package Initialisation

42. Package-level variable initialisers are evaluated at load time in declaration order (top to bottom), as in Ada. An initialiser may reference previously declared variables and call previously declared functions within the same package.

43. Referencing a not-yet-declared entity in an initialiser is a legality error (declaration-before-use, paragraph 9).

### 3.4.2 Cross-Package Initialisation Order

44. If package A `with`s package B, then B's initialisers complete before A's initialisers begin. This matches Ada's elaboration semantics but is trivially satisfiable because Safe packages have no circular `with` dependencies (paragraph 31).

45. The initialisation order across all compilation units is a topological sort of the `with` dependency graph. The order among packages with no direct or transitive dependency is implementation-defined but deterministic for a given program.

### 3.4.3 Task Startup Sequencing

46. All package-level initialisation across all compilation units completes before any task begins executing. See Section 4 for task startup semantics.

---

## 3.5 Implementation Requirements

### 3.5.1 Dependency Interface Mechanism

47. A conforming implementation shall provide a mechanism for conveying dependency interface information (paragraph 33) between separately compiled units. The mechanism is implementation-defined.

48. The mechanism shall be sufficient to support:

   (a) Legality checking of client code against provider interfaces.

   (b) Task-variable ownership checking using effect summaries from transitive dependencies.

   (c) Incremental recompilation when a provider's interface changes.

### 3.5.2 Separate Compilation

49. A conforming implementation shall support separate compilation of packages. Each package shall be compilable independently, given only its source and the dependency interface information of its `with`'d packages.

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

```ada
-- buffers.safe

package Buffers is

    public type Buffer_Size is range 1 .. 4096;
    public subtype Buffer_Index is Buffer_Size;

    public type Buffer is private record
        Data   : array (Buffer_Index) of Character = (others = ' ');
        Length : Buffer_Size = 1;
    end record;

    public function Create (Size : Buffer_Size) return Buffer is
    begin
        return (Data = (others = ' '), Length = Size);
        -- D27 proof: aggregate values in range
    end Create;

    public function Get (B : Buffer; I : Buffer_Index) return Character is
    begin
        return B.Data(I);
        -- D27 proof: I is Buffer_Index, same as array index type (Rule 2)
    end Get;

    public function Length (B : Buffer) return Buffer_Size
    is (B.Length);
    -- D27 proof: B.Length is Buffer_Size by declaration

end Buffers;
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

```ada
-- navigation.safe

with Units;

package Navigation is

    public type Heading is range 0 .. 359;

    Current_Speed : Units.Metres_Per_Second = 0.0;
    Current_Heading : Heading = 0;

    public procedure Update (D : Units.Metres; T : Units.Seconds;
                             H : Heading) is
    begin
        Current_Speed = Units.Speed(D, T);
        Current_Heading = H;
    end Update;

    public function Get_Speed return Units.Metres_Per_Second
    is (Current_Speed);
    -- D27 proof: return type matches declaration type

end Navigation;
```

### 3.6.4 Example: Interleaved Declarations, Dot Notation, Type Annotation

**Conforming Example.**

```safe
-- sensors.safe

package sensors

    public type reading is range 0 to 4095;
    public type channel_id is range 0 to 7;
    public subtype channel_count is integer range 1 to 8;

    type calibration is private record
        scale  : float = 1.0;
        bias   : integer = 0;

    cal_table : array (channel_id) of calibration =
        (others = (scale = 1.0, bias = 0));

    initialized : boolean = false;

    public function is_initialized returns boolean

        return initialized;

    public procedure initialize
        default_cal : constant calibration = (scale = 1.0, bias = 0);
        -- Interleaved declaration near the top of the body
        for i in channel_id.first .. channel_id.last loop
            -- Dot notation for attributes: channel_id.first, channel_id.last
            cal_table (i) = default_cal;
        initialized = true;

    public function average (a, b : reading) returns reading

        return (a + b) / 2;
        -- D27 Rule 1: wide intermediate, max (4095+4095)/2 = 4095
        -- D27 Rule 3(b): literal 2 is a static nonzero expression
        -- D27 proof: result in 0..4095

    public function scale (r : reading; divisor : channel_count) returns integer

        return integer (r) / divisor;
        -- D27 Rule 3(a): Channel_Count range 1..8 excludes zero
        -- D27 proof: division is safe

    function read_adc (channel : channel_id) returns reading is separate;

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
