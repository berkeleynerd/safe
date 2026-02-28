# 3. Single-File Packages

This section specifies Safe's single-file package model, which replaces the Ada specification/body file pair (8652:2023 §7.1, §7.2) with a single source file per package. The compiler extracts the public interface and emits the Ada `.ads`/`.adb` split mechanically. This section also specifies the `public` visibility model, opaque types, dot notation for attributes, type annotation syntax, and interleaved declarations within subprogram bodies.

All syntax, legality rules, static semantics, dynamic semantics, and implementation requirements of 8652:2023 §7 apply except as modified below.

---

## 3.1 Syntax

### 3.1.1 Compilation Units

1. A Safe compilation unit consists of a context clause followed by a package unit.

```
compilation_unit ::=
    context_clause package_unit

context_clause ::=
    { with_clause }

with_clause ::=
    'with' package_name { ',' package_name } ';'
    | 'use' 'type' subtype_mark { ',' subtype_mark } ';'

package_name ::=
    identifier { '.' identifier }
```

2. There is no `separate` compilation unit form at the compilation-unit level. The `is separate` stub form (§3.5, paragraphs 82--83) provides subprogram separation within a package.

### 3.1.2 Package Units

3. A package unit is the sole top-level construct in a Safe source file.

```
package_unit ::=
    [ 'public' ] 'package' defining_package_name 'is'
        { package_declaration }
    'end' defining_package_name ';'

defining_package_name ::=
    identifier { '.' identifier }
```

4. There is no `package body` construct. The 8652:2023 §7.2 `package_body` production is excluded. A package is a flat sequence of declarations between `is` and `end`.

5. The optional `public` keyword before `package` makes the package itself visible for `with`-ing by other compilation units. A package without the `public` keyword may still be `with`-ed if it is a child of a public package and the parent grants visibility; the `public` keyword on the package controls only whether the package name is exported in the symbol file (see §3.4).

### 3.1.3 Package Declarations

6. The body of a package is a sequence of package declarations.

```
package_declaration ::=
    basic_declaration
    | task_declaration
    | channel_declaration
    | subprogram_declaration
    | 'pragma' identifier [ '(' pragma_argument { ',' pragma_argument } ')' ] ';'
    | representation_clause
    | use_type_clause

use_type_clause ::=
    'use' 'type' subtype_mark { ',' subtype_mark } ';'
```

7. Basic declarations within a package:

```
basic_declaration ::=
    type_declaration
    | subtype_declaration
    | object_declaration
    | number_declaration
    | renaming_declaration

type_declaration ::=
    [ 'public' ] full_type_declaration
    | [ 'public' ] incomplete_type_declaration

full_type_declaration ::=
    'type' identifier [ discriminant_part ] 'is' type_definition ';'

incomplete_type_declaration ::=
    'type' identifier ';'

subtype_declaration ::=
    [ 'public' ] 'subtype' identifier 'is' subtype_indication ';'

object_declaration ::=
    [ 'public' ] defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        subtype_indication [ ':=' expression ] ';'
    | [ 'public' ] defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        array_type_definition [ ':=' expression ] ';'

defining_identifier_list ::=
    identifier { ',' identifier }

number_declaration ::=
    [ 'public' ] defining_identifier_list ':' 'constant' ':=' static_expression ';'

renaming_declaration ::=
    [ 'public' ] object_renaming_declaration
    | [ 'public' ] package_renaming_declaration
    | [ 'public' ] subprogram_renaming_declaration
```

8. Subprogram declarations include both specification and completion at the point of declaration:

```
subprogram_declaration ::=
    [ 'public' ] subprogram_specification subprogram_completion

subprogram_specification ::=
    procedure_specification
    | function_specification

procedure_specification ::=
    'procedure' identifier [ formal_part ]

function_specification ::=
    'function' identifier [ formal_part ] 'return' subtype_mark

formal_part ::=
    '(' parameter_specification { ';' parameter_specification } ')'

parameter_specification ::=
    defining_identifier_list ':' [ 'aliased' ] mode subtype_mark
        [ ':=' default_expression ]

mode ::=
    [ 'in' ]
    | 'in' 'out'
    | 'out'

subprogram_completion ::=
    'is' subprogram_body
    | 'is' expression_function_body
    | 'is' 'separate' ';'
    | 'is' 'null' ';'
    | ';'
```

9. The `subprogram_completion` alternative consisting of a bare semicolon produces a forward declaration. Forward declarations are permitted only for mutual recursion (see §3.2, paragraphs 24--26).

10. Subprogram bodies permit an optional declarative part before `begin` and interleaved declarations within the statement sequence:

```
subprogram_body ::=
    [ 'declare'
        { basic_declaration } ]
    'begin'
        sequence_of_statements
    'end' identifier ';'

expression_function_body ::=
    '(' expression ')' ';'
    | '(' expression ')' aspect_specification ';'
```

11. Within a `sequence_of_statements`, declarations may appear at any point (see Section 8, §8.7):

```
sequence_of_statements ::=
    statement { statement }

statement ::=
    [ label ] simple_statement
    | [ label ] compound_statement

simple_statement ::=
    null_statement
    | assignment_statement
    | procedure_call_statement
    | return_statement
    | exit_statement
    | goto_statement
    | delay_statement
    | send_statement
    | receive_statement
    | try_send_statement
    | try_receive_statement
    | pragma_statement
    | local_declaration

local_declaration ::=
    object_declaration
    | subtype_declaration
    | renaming_declaration
```

12. A `local_declaration` within a `sequence_of_statements` is syntactically a statement. It introduces a declaration that is visible from its point of declaration to the end of the enclosing scope. The optional `public` keyword shall not appear on a `local_declaration`; it is a legality error (see §3.2, paragraph 31).

### 3.1.4 Opaque Type Syntax

13. An opaque type declaration uses the `private record` modifier within a `type_definition`:

```
type_definition ::=
    ...
    | 'private' 'record' record_component_list 'end' 'record'
```

14. The `private record` form is valid only when the enclosing `type_declaration` bears the `public` keyword. The full production is:

```
opaque_type_declaration ::=
    'public' 'type' identifier [ discriminant_part ] 'is'
        'private' 'record' record_component_list 'end' 'record' ';'
```

This is not a separate production in the grammar; it is the combination of the `public` annotation on `type_declaration` with the `'private' 'record'` alternative of `type_definition`.

### 3.1.5 Dot Notation for Attributes

15. Ada's tick notation for attributes (8652:2023 §4.1.4) is replaced by dot notation. The attribute reference production is:

```
attribute_reference ::=
    prefix '.' attribute_designator

attribute_designator ::=
    identifier [ '(' expression { ',' expression } ')' ]
```

16. The tick character (`'`) appears in Safe source only within character literals (`'A'`, `'0'`). The 8652:2023 production for `attribute_reference` using tick (`prefix'attribute_designator`) is excluded.

### 3.1.6 Type Annotation Syntax

17. Ada's qualified expression syntax (8652:2023 §4.7, `subtype_mark'(expression)`) is replaced by type annotation syntax:

```
annotated_expression ::=
    '(' expression ':' subtype_mark ')'

qualified_aggregate ::=
    '(' aggregate ':' subtype_mark ')'
```

The parentheses are mandatory and are part of the syntactic form. The colon token `:` within an `annotated_expression` binds at the lowest precedence within the parenthesized group, so `(X + Y : Integer)` is parsed as `((X + Y) : Integer)`.

---

## 3.2 Legality Rules

### Matching End Identifier

18. The identifier following `end` in a `package_unit` shall be the same as the `defining_package_name` following `package`. A conforming implementation shall reject any `package_unit` where these identifiers do not match. This corresponds to 8652:2023 §7.1(3).

19. The identifier following `end` in a `subprogram_body` shall be the same as the identifier in the `subprogram_specification` of the enclosing `subprogram_declaration`. A conforming implementation shall reject any `subprogram_body` where these identifiers do not match.

### Declaration-Before-Use

20. Every identifier shall be declared before it is used. Within a package, each declaration is visible from the point immediately following its completion to the end of the package. Within a subprogram body (both the `declare` region and the `begin`...`end` region), each declaration is visible from the point immediately following its declaration to the end of the enclosing `subprogram_body` or `block_statement`. A conforming implementation shall reject any reference to an identifier that has not yet been declared at the point of reference.

21. This rule is stricter than 8652:2023 §3.1(7), which permits certain forward references within a single declarative region. In Safe, the only permitted forward reference is an incomplete type declaration (paragraph 22) or a forward subprogram declaration (paragraph 24).

### Incomplete Type Declarations

22. An incomplete type declaration (`type T;`) is permitted to enable recursive access type structures. It shall be completed by a `full_type_declaration` for the same identifier later in the same declarative region. A conforming implementation shall reject any incomplete type declaration that is not completed within the same declarative region. This corresponds to 8652:2023 §3.10.1(3).

23. Between the incomplete type declaration and its completion, the identifier may appear only as the designated type in an access type definition. A conforming implementation shall reject any other use of an incompletely declared type.

### Forward Declarations for Mutual Recursion

24. A subprogram declaration with a bare semicolon as its `subprogram_completion` constitutes a forward declaration. A forward declaration shall be completed by a subsequent `subprogram_declaration` in the same declarative region with an identical `subprogram_specification` (same identifier, same parameter names and types, same modes, same return type if a function).

25. Forward declarations are permitted only when two or more subprograms are mutually recursive. A conforming implementation shall reject a forward declaration unless the completing body, or a body that it calls, contains a call to a subprogram that is declared after the forward declaration and that directly or indirectly calls the forward-declared subprogram.

26. A conforming implementation may, as a simpler alternative to paragraph 25, accept all forward declarations provided each is completed by a matching body later in the same declarative region. This relaxation does not affect program semantics.

### No Package-Level Statements

27. A `package_unit` shall not contain statements outside of subprogram bodies and task bodies. The `package_declaration` production does not include `statement`. There is no `begin`...`end` initialization block at the package level (contrast 8652:2023 §7.2(6)). A conforming implementation shall reject any statement that appears directly in the declaration sequence of a `package_unit`.

28. Package-level variable initialization is accomplished through initializer expressions in `object_declaration` productions. These expressions may reference previously declared constants, variables, and functions within the same package or imported packages (see §3.4, paragraph 63).

### Mandatory Package-Level Initialization

28a. An `object_declaration` that is not a `constant` declaration and that appears directly in the declarative region of a `package_unit` shall include an initialization expression (`:= expression`). A conforming implementation shall reject a package-level variable declaration that omits the initialization expression. [Rationale: Safe packages have no `begin...end` elaboration block (paragraph 27), so the only mechanism for package-level initialization is the declaration-time expression.]

28b. This rule does not apply to variable declarations within subprogram bodies or task bodies. Local variables may omit initializers; SPARK flow analysis enforces write-before-read for locals.

### Public Keyword Visibility Rules

29. All declarations within a package are private by default. A declaration bearing the `public` keyword is visible to client packages that `with` the enclosing package. A declaration without the `public` keyword is visible only within the enclosing package.

30. The `public` keyword may appear on the following declaration forms:

- `type_declaration` (including `full_type_declaration` and `incomplete_type_declaration`)
- `subtype_declaration`
- `object_declaration`
- `number_declaration`
- `renaming_declaration`
- `subprogram_declaration`
- `channel_declaration`
- `package_unit` (on the `package` keyword itself)

31. The `public` keyword shall not appear on `local_declaration` forms within a `subprogram_body` or `block_statement`. A conforming implementation shall reject any `local_declaration` bearing the `public` keyword.

32. The `public` keyword shall not appear on `task_declaration`. Tasks are package-internal constructs; they communicate with clients through public channels and public subprograms.

33. A `public` subprogram declaration exports both its specification (parameter names, types, modes, return type) and its calling convention, but not its body. Clients see the specification; the body is private to the package.

34. If a `public` declaration references a type that is not itself `public`, the program is ill-formed. A conforming implementation shall reject any `public` declaration whose profile or type references a non-public type, except for opaque types (paragraph 35) and private types used only in `out` mode parameters where the type's name is public but structure is hidden.

### Opaque Types

35. A type declared as `public type T is private record ... end record;` is an opaque type. The type name `T` is public. Client packages may declare variables of type `T`, pass values of type `T` as parameters, assign values of type `T`, and test values of type `T` for equality. Client packages shall not access the components (fields) of the record. A conforming implementation shall reject any selected component access on a value of an opaque type outside the declaring package.

36. The `private record` modifier shall appear only on a `type_declaration` that bears the `public` keyword. A conforming implementation shall reject `private record` on a type that is not `public`. The rationale is that `private record` is a visibility restriction for clients; if the type is already package-private, the modifier is meaningless.

37. An opaque type may have discriminants. If discriminants are present, they are visible to clients (they must be, since discriminant constraints are needed to declare objects of discriminated types). The record components remain hidden.

38. An opaque type may include default component values. These defaults are part of the private structure and are not visible to clients, but they take effect when clients declare default-initialized objects of the type.

### Dot Notation Resolution

39. When `X.Name` appears in source, resolution is determined by the declaration of `X`:

- (a) If `X` denotes a record object or a component of a record object, then `Name` shall be a component (field) of the record type. This is a selected component as defined in 8652:2023 §4.1.3.
- (b) If `X` denotes a type or subtype mark, then `Name` shall be an attribute of that type. This replaces the tick notation of 8652:2023 §4.1.4. For example, `Integer.First` replaces `Integer'First`; `T.Size` replaces `T'Size`; `T.Image(42)` replaces `T'Image(42)`.
- (c) If `X` denotes a package name (introduced by a `with_clause` or a `package_renaming_declaration`), then `Name` shall be a public declaration within that package.

40. Resolution is unambiguous because no overloading is permitted (Section 2, D12), no tagged types exist (Section 2, D18), and the kind of every identifier is known at the point of use in a single-pass compiler. A conforming implementation shall determine which case applies from the declaration of `X` and shall reject any `X.Name` where `Name` is not a valid component, attribute, or package member as appropriate.

41. The complete list of retained attributes using dot notation is specified in Section 2 (§2.5). All attributes listed there are accessed via dot notation. An attribute not listed there is not available in Safe.

### Type Annotation Syntax

42. The type annotation syntax `(Expr : T)` replaces Ada's qualified expression syntax `T'(Expr)` (8652:2023 §4.7). The parentheses are required; bare `Expr : T` without enclosing parentheses is not a valid expression.

43. The colon in a type annotation binds at the lowest precedence within the parenthesized group. Specifically, `(A + B : T)` is equivalent to `(T'(A + B))` in Ada. No additional parentheses are needed around the expression within the annotation.

44. In an argument list, an annotated expression requires its own parentheses to avoid ambiguity with the colon in named parameter association. Thus: `Foo((others => 0) : Buffer_Type)` passes an annotated aggregate; `Foo(X => 42)` is a named association.

45. A `qualified_aggregate` of the form `(aggregate : subtype_mark)` serves the same purpose as Ada's qualified aggregate `subtype_mark'(aggregate)` for disambiguating aggregate types. This is the primary use of type annotations in Safe, since overloading (the other common reason for qualified expressions in Ada) is excluded.

---

## 3.3 Static Semantics

### Visibility and Name Resolution

46. The declarative region of a `package_unit` extends from the first `package_declaration` to the closing `end`. Within this region, 8652:2023 §8.2 visibility rules apply, modified by the declaration-before-use rule of paragraph 20.

47. A `with_clause` makes the public declarations of the named package visible via qualified notation (`Package_Name.Declaration_Name`). General `use` clauses (8652:2023 §8.4) are excluded (Section 2, D13). `use type` clauses are retained and make the primitive operators of the named type directly visible within the enclosing scope.

48. Child packages are supported. A child package `Parent.Child` has visibility into the public declarations of `Parent` without an explicit `with_clause`, as in 8652:2023 §10.1.1. A child package also has visibility into the private declarations of its parent; this is the one exception to the `public` visibility rule.

### Symbol File Contents

49. The compiler shall produce a symbol file for each compiled package. The symbol file is the unit of interface information used for incremental compilation. It replaces the Ada `.ads` file as the mechanism by which client packages learn the interface of a dependency.

50. The symbol file for a package `P` shall contain, at minimum:

- (a) The package name.
- (b) For each `public` type declaration: the type name, its kind (integer, modular, floating-point, fixed-point, enumeration, array, record, access, derived), its constraints (range bounds, index types, discriminants), and its size and alignment. For opaque types, the size and alignment are included but the component list is omitted.
- (c) For each `public` subtype declaration: the subtype name, the parent type, and the constraint.
- (d) For each `public` object declaration: the object name, its type, and whether it is `constant` or `aliased`.
- (e) For each `public` number declaration: the name and the static value.
- (f) For each `public` subprogram declaration: the subprogram name, its kind (procedure or function), the full parameter profile (names, types, modes, default expressions if any), and the return type (for functions).
- (g) For each `public` channel declaration: the channel name, the element type, and the capacity.
- (h) For each `public` renaming declaration: the new name and what it renames.
- (i) The names and symbol file hashes of all packages named in `with_clause`s.

51. The symbol file format is implementation-defined. It may be binary, textual, or any format that supports efficient lookup. The format shall be versioned so that incompatible changes to the symbol file format are detected at compile time.

### What Clients See

52. A client package that names `P` in a `with_clause` sees exactly the information in `P`'s symbol file. Specifically:

- (a) Public type names, with full structural information for non-opaque types and size/alignment only for opaque types.
- (b) Public subtype names with their constraints.
- (c) Public object names with their types.
- (d) Public number names with their values.
- (e) Public subprogram specifications (not bodies).
- (f) Public channel names with element types and capacities.
- (g) Public renaming names.

53. Private declarations (those without the `public` keyword) are not visible to clients. They do not appear in the symbol file. A client that attempts to reference a private declaration of an imported package shall be rejected at compile time.

### Opaque Type Semantics

54. For an opaque type `public type T is private record ... end record;`, the symbol file exports:

- (a) The type name `T`.
- (b) The size and alignment of `T`, sufficient for a client to allocate storage.
- (c) The discriminant part, if any (discriminant names, types, and defaults).
- (d) No component (field) information.

55. Within the declaring package, `T` is treated as an ordinary record type with full component access.

56. In a client package, the following operations are permitted on a value `V` of opaque type `T`:

- (a) Declaration: `V : T;` or `V : T := ...;`
- (b) Assignment: `V := W;` where `W` is of type `T`.
- (c) Equality test: `V = W` and `V /= W`.
- (d) Passing as a parameter to a subprogram that accepts type `T`.
- (e) Returning from a function that returns type `T`.

57. In a client package, the following operations are not permitted on a value of opaque type `T`:

- (a) Selected component access: `V.Field` is rejected.
- (b) Record aggregate construction: `(Field1 => ..., Field2 => ...)` for type `T` is rejected, since the component names are not visible.
- (c) Membership test against a component value.

58. A client may initialize an opaque-type object by calling a public function of the declaring package that returns the opaque type, or by assigning from another object of the same type. Default initialization (using the record's default component values) is also permitted.

### Interleaved Declaration Visibility

59. A `local_declaration` within a `sequence_of_statements` introduces a new declaration at the point where it appears. The declared entity is visible from the point immediately following the declaration to the end of the enclosing `subprogram_body` or `block_statement`.

60. A `local_declaration` shall not shadow a declaration from the same declarative region. Specifically, a `local_declaration` shall not have the same identifier as a parameter of the enclosing subprogram, a declaration in the `declare` region of the same subprogram body, or a preceding `local_declaration` in the same scope. A conforming implementation shall reject such shadowing. This is stricter than 8652:2023 §8.3(16), which permits homographs in certain cases.

61. A `local_declaration` in a nested `block_statement` may shadow a declaration from an enclosing scope, following 8652:2023 §8.3 hiding rules. The inner declaration hides the outer declaration within the block.

---

## 3.4 Dynamic Semantics

### Package Initialization

62. Package-level variable initializers are evaluated at load time in the order in which they appear in the source file (top to bottom, left to right within a `defining_identifier_list`). This corresponds to 8652:2023 §3.3.1(19) for object declarations with explicit initialization expressions.

63. An initializer expression may reference:

- (a) Previously declared constants and variables within the same package.
- (b) Previously declared functions within the same package (including expression functions).
- (c) Public declarations of imported packages (whose initialization has already completed; see paragraph 65).

64. An initializer expression shall not reference a declaration that follows it in the source text. This is enforced by the declaration-before-use legality rule (paragraph 20).

65. If package `A` names package `B` in a `with_clause`, all initializers in `B` shall complete before any initializer in `A` begins evaluation. This matches 8652:2023 §10.2(7) elaboration semantics. Circular `with` dependencies are not permitted; a conforming implementation shall reject any set of packages whose `with`-graphs form a cycle.

66. There is no elaboration-time executable code other than variable initializer expressions and the function calls they may invoke. There is no `begin`...`end` initialization block at the package level (see paragraph 27). The emitted Ada uses `pragma Preelaborate` or `pragma Pure` where the package-level declarations satisfy the requirements of 8652:2023 §10.2.1 or §10.2.1(1); otherwise, the emitted Ada relies on GNAT's static elaboration model.

### Task Startup Ordering

67. All package-level initialization across all compilation units in the partition shall complete before any task declared in any package begins executing. This is specified further in Section 4 (Tasks and Channels).

### Subprogram Execution

68. Subprogram bodies execute as defined in 8652:2023 §6.4. Within a subprogram body, the `declare` region (if present) is elaborated first, then the `sequence_of_statements` is executed. Local declarations within the statement sequence are elaborated (their initializer expressions evaluated) when control reaches them.

69. If control flow bypasses a `local_declaration` (for example, via a `goto`, `exit`, or `return` before the declaration), that declaration is not elaborated and the declared entity does not exist. A reference to such an entity is prevented by the declaration-before-use rule, which operates on the textual ordering within the source, combined with the flow-based reachability: a declaration is usable only if it is both textually preceding and in the same or enclosing scope.

---

## 3.5 Implementation Requirements

### Emitted Ada Structure

70. For each Safe source file containing a `package_unit` for a package `P`, the compiler shall emit two Ada source files:

- (a) `p.ads` — the Ada package specification.
- (b) `p.adb` — the Ada package body.

The file naming convention shall follow GNAT's default file naming rules (8652:2023 §10.1 Implementation Advice): lowercase, dots replaced by hyphens for child packages (e.g., `parent-child.ads`).

71. The emitted `.ads` file shall contain:

- (a) `pragma SPARK_Mode;` at the top.
- (b) The `package P` declaration with an `Initializes` aspect listing all package-level variables that have initializer expressions.
- (c) All `public` type declarations with full structure for non-opaque types.
- (d) For opaque types: the type name in the visible part, with the full record definition in the `private` section of the `.ads`. This preserves Ada's information-hiding semantics for the emitted code.
- (e) All `public` subtype declarations.
- (f) All `public` object declarations.
- (g) All `public` number declarations.
- (h) All `public` subprogram specifications, each with compiler-generated `Global` and `Depends` aspects (see Section 5, SPARK Assurance).
- (i) All `public` channel declarations, emitted as protected object specifications with `Send`, `Receive`, `Try_Send`, and `Try_Receive` entries/procedures.
- (j) All private type, subtype, object, and number declarations, placed in the `private` section of the `.ads`.

72. The emitted `.adb` file shall contain:

- (a) `pragma SPARK_Mode;` at the top.
- (b) The `package body P` with all subprogram bodies.
- (c) All private subprogram bodies.
- (d) Task bodies, emitted as Ada task objects with Jorvik-profile-compatible bodies.
- (e) Channel-backing protected object bodies.
- (f) If any package-level variables have non-static initializers that prevent `pragma Preelaborate`, a `begin`...`end` elaboration block in the package body performing the initializations in declaration order.

73. The emitted Ada shall be valid ISO/IEC 8652:2023. It shall be compilable by GNAT and verifiable by GNATprove at Bronze and Silver levels without any manual annotation (see Section 5).

### Dot Notation Emission

74. All attribute references using Safe's dot notation (`X.First`, `T.Size`, `T.Image(42)`) shall be emitted as Ada tick notation (`X'First`, `T'Size`, `T'Image(42)`). The mapping is purely syntactic; the semantic identity of each attribute is preserved.

### Type Annotation Emission

75. All type annotations (`(Expr : T)`) shall be emitted as Ada qualified expressions (`T'(Expr)`). The semantic identity is preserved; the transformation is purely syntactic.

### Symbol File Emission

76. The compiler shall emit a symbol file for each successfully compiled package. The symbol file shall contain the information specified in paragraph 50.

77. The symbol file shall include a cryptographic hash or checksum of its contents, sufficient to detect changes between compilations.

78. The symbol file shall be emitted atomically: either the complete, consistent file is written, or no file is written. This prevents partial symbol files from corrupting subsequent compilations.

### Incremental Recompilation Rules

79. A package `P` shall be recompiled if any of the following conditions hold:

- (a) The Safe source file for `P` has been modified since the last compilation.
- (b) The symbol file of any package named in `P`'s `with_clause`s has changed (detected by comparing the stored hash in `P`'s symbol file against the current hash of the dependency's symbol file).

80. If the recompilation of a dependency `Q` produces a symbol file with the same hash as the previous symbol file, packages that depend on `Q` need not be recompiled. This enables minimal recompilation when internal changes to `Q` (private declarations, subprogram body changes) do not alter `Q`'s public interface.

81. The compiler shall track dependency information (the `with`-graph) in the symbol files (paragraph 50(i)) to enable a build system to determine the correct compilation order and minimal recompilation set.

### Separate Subprogram Bodies

82. A subprogram declared with `is separate` in a package `P` indicates that the subprogram body is provided in a separate Safe source file. The file shall be named following GNAT conventions (e.g., `p-subprogram_name.safe`). The compiler shall compile the separate body in the context of `P`'s declarative region, with access to all declarations visible at the point of the `is separate` stub.

83. The emitted Ada for a separate body shall use Ada's `separate (P)` mechanism (8652:2023 §10.1.3).

---

## 3.6 Examples

### Example 1: Simple Package with Public Types and Functions

84. This example demonstrates a basic package with public type declarations, public and private objects, and public subprograms with bodies at point of declaration.

```
-- counters.safe

package Counters is

    public type Count is range 0 .. 1_000_000;

    public subtype Positive_Count is Count range 1 .. Count.Last;

    Max_Value : constant Count := Count.Last;

    Current : Count := 0;

    public function Value return Count
    is (Current);

    public procedure Increment is
    begin
        if Current < Max_Value then
            Current := Current + 1;
        end if;
    end Increment;

    public procedure Reset is
    begin
        Current := 0;
    end Reset;

    public function Average (Total : Count; Num_Items : Positive_Count) return Count is
    begin
        -- Num_Items is Positive_Count (1..1_000_000), excludes zero:
        -- division is legal per D27 Rule 3
        return Total / Num_Items;
    end Average;

end Counters;
```

85. In this example, `Count`, `Positive_Count`, `Value`, `Increment`, `Reset`, and `Average` are public. `Max_Value` and `Current` are private. Clients may call `Value` to read the counter but cannot access `Current` directly.

### Example 2: Package with Opaque Types

86. This example demonstrates an opaque type whose fields are hidden from clients.

```
-- tokens.safe

package Tokens is

    public type Token_Kind is (Identifier, Number, Symbol, End_Of_File);

    public type Token is private record
        Kind   : Token_Kind := End_Of_File;
        Start  : Positive := 1;
        Length : Natural := 0;
    end record;

    public function Make (K : Token_Kind; S : Positive; L : Natural) return Token is
    begin
        return (Kind => K, Start => S, Length => L);
    end Make;

    public function Kind_Of (T : Token) return Token_Kind is
    begin
        return T.Kind;
    end Kind_Of;

    public function Start_Of (T : Token) return Positive is
    begin
        return T.Start;
    end Start_Of;

    public function Length_Of (T : Token) return Natural is
    begin
        return T.Length;
    end Length_Of;

end Tokens;
```

87. Clients can declare `Token` variables, pass them to functions, and test them for equality. Clients cannot write `T.Kind` or `(Kind => Identifier, Start => 1, Length => 5)` because the record components are not visible outside the package. Accessor functions (`Kind_Of`, `Start_Of`, `Length_Of`) and a constructor function (`Make`) provide the public interface.

88. The emitted Ada `.ads` places `Token`'s full record definition in the `private` section:

```ada
-- tokens.ads (generated)
pragma SPARK_Mode;

package Tokens
    with Initializes => null
is
    type Token_Kind is (Identifier, Number, Symbol, End_Of_File);

    type Token is private;

    function Make (K : Token_Kind; S : Positive; L : Natural) return Token
        with Global => null;

    function Kind_Of (T : Token) return Token_Kind
        with Global => null;

    function Start_Of (T : Token) return Positive
        with Global => null;

    function Length_Of (T : Token) return Natural
        with Global => null;

private
    type Token is record
        Kind   : Token_Kind := End_Of_File;
        Start  : Positive := 1;
        Length : Natural := 0;
    end record;
end Tokens;
```

### Example 3: Two Packages with Dependency

89. This example demonstrates two packages where one depends on the other via a `with`-clause.

```
-- units.safe

public package Units is

    public type Meters is range 0 .. 100_000;

    public type Seconds is range 1 .. 3_600;
    -- Seconds excludes zero: valid divisor type (D27 Rule 3)

    public subtype Meters_Index is Meters range 0 .. 99;

    public function To_Meters (Value : Natural) return Meters is
    begin
        if Value > Natural (Meters.Last) then
            return Meters.Last;
        else
            return Meters (Value);
        end if;
    end To_Meters;

end Units;
```

```
-- physics.safe

with Units;

public package Physics is

    public type Velocity is range 0 .. 100_000;

    public function Speed (Distance : Units.Meters;
                           Time     : Units.Seconds) return Velocity is
    begin
        -- Time is Units.Seconds (1..3600), excludes zero: division is legal
        return Velocity (Distance / Time);
    end Speed;

    Table : array (Units.Meters_Index) of Velocity :=
        (others => 0);

    public function Lookup (Index : Units.Meters_Index) return Velocity is
    begin
        -- Index type matches array index type: indexing is provably safe
        return Table (Index);
    end Lookup;

end Physics;
```

90. Package `Physics` names `Units` in its `with_clause`. All initializers in `Units` complete before any initializer in `Physics` begins. `Physics` references `Units.Meters`, `Units.Seconds`, and `Units.Meters_Index` using qualified notation. The type `Seconds` excludes zero, so division by `Time` is accepted per D27 Rule 3. Array `Table` is indexed by `Units.Meters_Index`, and `Lookup` accepts the same type as its parameter, satisfying D27 Rule 2.

### Example 4: Interleaved Declarations, Dot Notation, and Type Annotations

91. This example demonstrates interleaved declarations and statements in subprogram bodies, dot notation for attribute access, and type annotation syntax.

```
-- analysis.safe

with Units;

public package Analysis is

    public type Sample_Index is range 1 .. 256;

    public type Sample_Array is array (Sample_Index) of Units.Meters;

    public type Result is private record
        Min   : Units.Meters := Units.Meters.Last;
        Max   : Units.Meters := Units.Meters.First;
        Total : Natural := 0;
        Count : Sample_Index := 1;
    end record;

    public function Make_Result (Lo, Hi : Units.Meters;
                                 Sum    : Natural;
                                 N      : Sample_Index) return Result is
    begin
        return (Min => Lo, Max => Hi, Total => Sum, Count => N);
    end Make_Result;

    public function Min_Of (R : Result) return Units.Meters is (R.Min);
    public function Max_Of (R : Result) return Units.Meters is (R.Max);

    -- Forward declarations for mutual recursion
    procedure Process_Even (Data : Sample_Array; Idx : Sample_Index;
                            Acc : in out Result);
    procedure Process_Odd  (Data : Sample_Array; Idx : Sample_Index;
                            Acc : in out Result);

    procedure Process_Even (Data : Sample_Array; Idx : Sample_Index;
                            Acc : in out Result) is
    begin
        -- Dot notation for attributes: Sample_Index.Last replaces Sample_Index'Last
        Val : Units.Meters := Data (Idx);

        if Val < Acc.Min then
            Acc.Min := Val;
        end if;
        if Val > Acc.Max then
            Acc.Max := Val;
        end if;

        -- Type annotation: (Integer(Val) : Natural) replaces Natural'(Integer(Val))
        Contribution : Natural := (Integer (Val) : Natural);
        Acc.Total := Acc.Total + Contribution;

        Next : Sample_Index := Idx + 1;
        if Next <= Sample_Index.Last then
            -- Mutual recursion: even calls odd
            Process_Odd (Data, Next, Acc);
        end if;
    end Process_Even;

    procedure Process_Odd (Data : Sample_Array; Idx : Sample_Index;
                           Acc : in out Result) is
    begin
        Val : Units.Meters := Data (Idx);

        if Val < Acc.Min then
            Acc.Min := Val;
        end if;
        if Val > Acc.Max then
            Acc.Max := Val;
        end if;

        Contribution : Natural := (Integer (Val) : Natural);
        Acc.Total := Acc.Total + Contribution;

        Next : Sample_Index := Idx + 1;
        if Next <= Sample_Index.Last then
            -- Mutual recursion: odd calls even
            Process_Even (Data, Next, Acc);
        end if;
    end Process_Odd;

    public function Analyze (Data : Sample_Array) return Result is
    begin
        -- Interleaved declaration: R declared at point of use
        R : Result := (Min   => Units.Meters.Last,
                        Max   => Units.Meters.First,
                        Total => 0,
                        Count => 1);

        -- Dot notation for attribute: Sample_Index.First
        Process_Even (Data, Sample_Index.First, R);

        -- Another interleaved declaration
        N : Sample_Index := Sample_Index (Data.Length);
        R.Count := N;

        return R;
    end Analyze;

end Analysis;
```

92. This example illustrates several features working together:

- **Interleaved declarations:** `Val`, `Contribution`, `Next`, `R`, and `N` are declared within the `begin`...`end` region of their respective subprogram bodies, at the point of first use. Each is visible from its point of declaration to the end of the enclosing subprogram body.

- **Dot notation for attributes:** `Sample_Index.Last` replaces Ada's `Sample_Index'Last`. `Units.Meters.Last` and `Units.Meters.First` replace `Units.Meters'Last` and `Units.Meters'First`. `Data.Length` replaces `Data'Length`. The compiler resolves each by determining that `Sample_Index` is a type (case (b) of paragraph 39), `Units.Meters` is a type in an imported package (case (c) then case (b)), and `Data` is an array object (case (b)).

- **Type annotation syntax:** `(Integer(Val) : Natural)` asserts that the conversion result has type `Natural`. This replaces Ada's `Natural'(Integer(Val))`. The parentheses are mandatory.

- **Forward declarations for mutual recursion:** `Process_Even` and `Process_Odd` are forward-declared before their bodies. This is required because `Process_Even` calls `Process_Odd`, which is not yet declared at the point of call, and vice versa.

- **Opaque type:** `Result` is `public type Result is private record`. Within the package, full component access is available (`R.Min`, `R.Max`, etc.). Clients of `Analysis` cannot access these fields; they use `Min_Of`, `Max_Of`, and `Make_Result`.

---

## 3.7 Notes

93. The single-file package model eliminates the signature duplication inherent in Ada's separate specification and body files. In Ada, every subprogram declared in a package specification must have its full signature repeated in the package body. In Safe, each subprogram is written once. The compiler extracts public signatures for the symbol file and reconstructs the `.ads`/`.adb` split mechanically.

94. The `public` keyword model is simpler than Ada's `private` section model. In Ada, a package specification has a visible part and a private part, separated by the `private` keyword. Declarations in the visible part are public; declarations in the private part are visible to the compiler (for type completion) but not logically to clients, except that child packages can see them. In Safe, each declaration is independently annotated. There is no section boundary, and the structural distinction between "visible to clients" and "visible only to the compiler" is handled by the symbol file (paragraph 50).

95. The `private record` mechanism for opaque types is the Safe equivalent of Ada's partial and full type views (8652:2023 §7.3). In Ada, the partial view (`type T is private;`) appears in the visible part of the specification, and the full view (`type T is record ... end record;`) appears in the private part. In Safe, both views are collapsed into a single declaration: `public type T is private record ... end record;`. The word `public` exports the name; the words `private record` hide the structure.
