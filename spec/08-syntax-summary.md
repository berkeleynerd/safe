# Section 8 — Syntax Summary

**This section is normative.**

This section provides the complete consolidated BNF grammar for Safe. This is the authoritative grammar; all syntactic constructs of Safe are defined here. The notation follows 8652:2023 §1.1.4: `::=` for productions, `[ ]` for optional, `{ }` for zero or more repetitions, `|` for alternation. Keywords are shown in **bold** where referenced in prose; in productions they appear as quoted literals. Nonterminals are in `snake_case`.

For the post-PR11.6.2 surface, the lexer emits structural `INDENT` / `DEDENT`
tokens from leading spaces-only indentation in fixed 3-space steps. Covered
block constructs are delimited by those structural tokens rather than explicit
closing keywords. Statement-level `declare`, `declare_expression`, source
`null`, `goto`, named `exit`, `aliased`, and legacy representation clauses are
not part of the admitted Safe source grammar.

For the post-PR11.7 surface, all Safe source spellings are lowercase-only.
Identifiers, reserved words, predefined names, attribute selectors, and
admitted aspect / pragma names use lowercase spelling. Uppercase `E` in
exponents and uppercase `A` .. `F` in based numerals remain permitted as part
of numeric literal syntax.

For the post-PR11.8c surface, fixed-width binary values are written
`binary (8)`, `binary (16)`, `binary (32)`, and `binary (64)`. Shift
operators `<<` and `>>` are admitted for binary operands only, and `>>` is a
logical zero-fill right shift.

For the post-PR11.8c.1 surface, `print (expression)` is admitted as a
statement-only built-in. It prints exactly one line of normalized text for
`integer`, `string`, `boolean`, and enum expressions.

For the post-PR11.8i surface, user-defined enumeration types with
identifier-valued enumerators are admitted. Character-literal enumerators and
enum range-constrained subtypes remain outside the admitted surface.

For the post-PR11.10a surface, built-in optional values are admitted through
`optional T`, `some(expr)`, contextual `none`, the discriminant selector
`.present`, and guarded payload access through `.value`. `optional T` remains
limited to the admitted value-type subset; inferred reference families,
channels, and tasks are outside this wedge.

For the post-PR11.13c surface, sum type declarations, variant construction,
and statement-only exhaustive `match` over sum values are admitted through
`type name is variant or variant ...`, bare zero-payload variant constructors,
positional payload-bearing variant constructors, and `match value / when
variant (...)`. Public sum types are admitted, imported constructor
expressions are package-qualified, imported `match` arms stay bare and resolve
by scrutinee type, and direct payload inspection outside `match` remains
rejected.

For the post-PR11.8c.2 surface, a compilation unit may be either an explicit
package unit or a packageless entry unit. Executable statements are admitted at
unit scope after declarations. Once the first unit-scope statement appears,
later unit-scope declarations are illegal.

For the post-PR11.8e surface, explicit `access`, `new`, `.all`, `.access`,
source `in`, `out`, and `in out` are removed. Direct self-recursive record
types are inferred as references, parameters are either ordinary borrows or
`mut` mutable borrows, and task bodies may use only their own locals and
channels.

For the post-grammar-overhaul surface, package items, declarations, and
statements use logical-line termination. A terminator may be omitted at a
logical line boundary, `DEDENT`, or end of file. A semicolon is only a
same-logical-line separator before another significant item or statement;
trailing/removable semicolons are rejected. Newlines are suppressed inside
unclosed `(`, `[`, or `{` bracket pairs. A `\` continuation is valid when the
backslash is the final non-comment token on the line; trailing horizontal
whitespace and trailing `--` comments are tolerated.

---

## 8.1 Compilation Units

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

terminator ::=
    same_line_separator
  | omitted_terminator

same_line_separator ::=
    ';'

omitted_terminator ::=
    <no token; before DEDENT, EOF, or the next significant token
     on a later logical line>

package_name ::=
    identifier { '.' identifier }

package_unit ::=
    'package' defining_identifier
        indented_unit_item_list

entry_unit ::=
    unit_item_list

indented_unit_item_list ::=
    INDENT
        unit_item_list
    DEDENT

unit_item_list ::=
    { package_item }
    { unit_statement }

unit_statement ::=
    statement
```

For an entry unit, the unit name is inferred from the source filename stem.

## 8.2 Package Items

```
package_item ::=
    basic_declaration
  | task_declaration
  | channel_declaration
  | use_type_clause
  | pragma

basic_declaration ::=
    type_declaration
  | subtype_declaration
  | object_declaration
  | number_declaration
  | subprogram_declaration
  | subprogram_body
  | expression_function_declaration
  | renaming_declaration
  | subunit_stub
  | incomplete_type_declaration
```

## 8.3 Declarations

```
type_declaration ::=
    [ 'public' ] 'type' defining_identifier
        [ generic_formal_part ] [ known_discriminant_part ]
        'is' type_definition terminator
  | [ 'public' ] 'type' defining_identifier [ generic_formal_part ]
        'is' 'interface'
        indented_interface_member_list

incomplete_type_declaration ::=
    [ 'public' ] 'type' defining_identifier terminator

subtype_declaration ::=
    [ 'public' ] 'subtype' defining_identifier 'is' subtype_indication terminator

object_declaration ::=
    [ 'public' ] defining_identifier_list ':' [ 'constant' ]
        subtype_indication [ '=' expression ] terminator
  | [ 'public' ] defining_identifier_list ':' [ 'constant' ]
        array_type_definition [ '=' expression ] terminator

number_declaration ::=
    [ 'public' ] defining_identifier_list ':' 'constant' '=' static_expression terminator

defining_identifier_list ::=
    defining_identifier { ',' defining_identifier }

subunit_stub ::=
    subprogram_specification 'is' 'separate' terminator

renaming_declaration ::=
    object_renaming_declaration
  | package_renaming_declaration
  | subprogram_renaming_declaration

object_renaming_declaration ::=
    [ 'public' ] defining_identifier ':' subtype_mark 'renames' name terminator

package_renaming_declaration ::=
    [ 'public' ] 'package' defining_identifier 'renames' package_name terminator

subprogram_renaming_declaration ::=
    [ 'public' ] subprogram_specification 'renames' name terminator
```

## 8.4 Type Definitions

```
type_definition ::=
    enumeration_type_definition
  | sum_type_definition
  | signed_integer_type_definition
  | binary_type_definition
  | floating_point_definition
  | ordinary_fixed_point_definition
  | decimal_fixed_point_definition
  | array_type_definition
  | record_type_definition
  | derived_type_definition

enumeration_type_definition ::=
    '(' enumeration_literal { ',' enumeration_literal } ')'

sum_type_definition ::=
    sum_variant_specification { 'or' sum_variant_specification }

sum_variant_specification ::=
    defining_identifier
  | defining_identifier '(' sum_payload_field_declaration
        { ';' sum_payload_field_declaration } ')'

sum_payload_field_declaration ::=
    defining_identifier ':' subtype_indication

Sum payload field lists retain structural semicolons as field separators.
These semicolons are not terminators and are not removable.

enumeration_literal ::=
    defining_identifier

signed_integer_type_definition ::=
    'range' static_simple_expression 'to' static_simple_expression

binary_type_definition ::=
    'binary' '(' static_expression ')'

floating_point_definition ::=
    'digits' static_expression [ real_range_constraint ]

ordinary_fixed_point_definition ::=
    'delta' static_expression real_range_constraint

decimal_fixed_point_definition ::=
    'delta' static_expression 'digits' static_expression [ real_range_constraint ]

real_range_constraint ::=
    'range' simple_expression 'to' simple_expression

array_type_definition ::=
    unconstrained_array_definition
  | constrained_array_definition
  | growable_array_definition

unconstrained_array_definition ::=
    'array' '(' index_subtype_definition { ',' index_subtype_definition } ')'
        'of' component_definition

constrained_array_definition ::=
    'array' '(' discrete_subtype_definition { ',' discrete_subtype_definition } ')'
        'of' component_definition

growable_array_definition ::=
    'array' 'of' component_definition

index_subtype_definition ::=
    subtype_mark 'range' '<>'

discrete_subtype_definition ::=
    discrete_subtype_indication | range

component_definition ::=
    subtype_indication
  | growable_array_type_spec

growable_array_type_spec ::=
    'array' 'of' component_definition

record_type_definition ::=
    [ 'limited' ] record_definition
  | 'private' record_definition

record_definition ::=
    'record'
        indented_component_list
  | 'null' 'record'

indented_component_list ::=
    INDENT
        component_list
    DEDENT

component_list ::=
    component_item { component_item }
  | { component_item } variant_part
  | 'null' terminator

component_item ::=
    component_declaration

component_declaration ::=
    defining_identifier_list ':' component_definition [ '=' default_expression ] terminator

known_discriminant_part ::=
    '(' discriminant_specification { ',' discriminant_specification } ')'

discriminant_specification ::=
    defining_identifier_list ':' subtype_mark [ '=' default_expression ]

Known discriminant parts use comma-separated discriminant specifications.
This differs from Ada's semicolon-separated discriminant syntax; discriminant
separators are not among the structural semicolon cases retained by Safe.

variant_part ::=
    'case' discriminant_direct_name
        indented_variant_list

indented_variant_list ::=
    INDENT
        variant { variant }
    DEDENT

variant ::=
    'when' discrete_choice_list
        indented_component_list

discrete_choice_list ::=
    discrete_choice { '|' discrete_choice }

discrete_choice ::=
    choice_expression | discrete_subtype_indication | range | 'others'

derived_type_definition ::=
    [ 'limited' ] 'new' subtype_indication

indented_interface_member_list ::=
    INDENT
        interface_member_specification { interface_member_specification }
    DEDENT

interface_member_specification ::=
    function_specification terminator

generic_formal_part ::=
    'of' generic_formal_list [ generic_constraint_part ]

generic_formal_list ::=
    defining_identifier
  | '(' defining_identifier { ',' defining_identifier } ')'

generic_constraint_part ::=
    'with' generic_constraint_association
        { ',' generic_constraint_association }

generic_constraint_association ::=
    defining_identifier ':' subtype_mark
```

## 8.5 Subtype Indications

```
subtype_indication ::=
    [ 'not' 'null' ] subtype_mark [ constraint | inline_range_constraint ]
  | binary_type_definition
  | list_type_spec
  | map_type_spec
  | optional_type_spec

subtype_mark ::=
    name

type_target ::=
    subtype_mark
  | binary_type_definition
  | list_type_spec
  | map_type_spec
  | optional_type_spec

list_type_spec ::=
    'list' 'of' subtype_indication

map_type_spec ::=
    'map' 'of' '(' subtype_indication ',' subtype_indication ')'

optional_type_spec ::=
    'optional' subtype_indication

constraint ::=
    scalar_constraint
  | index_constraint
  | discriminant_constraint

scalar_constraint ::=
    range_constraint
  | digits_constraint
  | delta_constraint

inline_range_constraint ::=
    '(' simple_expression 'to' simple_expression ')'

range_constraint ::=
    'range' range

range ::=
    simple_expression 'to' simple_expression
  | name '.' 'range' [ '(' static_expression ')' ]

index_constraint ::=
    '(' discrete_range { ',' discrete_range } ')'

discrete_range ::=
    discrete_subtype_indication | range

discrete_subtype_indication ::=
    subtype_mark [ range_constraint ]

discriminant_constraint ::=
    '(' discriminant_association { ',' discriminant_association } ')'

discriminant_association ::=
    [ selector_name { '|' selector_name } '=' ] expression

digits_constraint ::=
    'digits' static_expression [ range_constraint ]

delta_constraint ::=
    'delta' static_expression [ range_constraint ]
```

## 8.6 Names and Expressions

```
name ::=
    direct_name
  | indexed_component
  | slice
  | selected_component
  | type_conversion
  | function_call

direct_name ::=
    identifier [ generic_actual_part ]

indexed_component ::=
    name '(' expression { ',' expression } ')'

slice ::=
    name '(' discrete_range ')'

selected_component ::=
    name '.' selector_name [ generic_actual_part ]

selector_name ::=
    identifier

generic_actual_part ::=
    'of' generic_actual_list

generic_actual_list ::=
    generic_actual_type
  | '(' generic_actual_type { ',' generic_actual_type } ')'

generic_actual_type ::=
    subtype_mark
  | binary_type_definition
  | list_type_spec
  | map_type_spec
  | optional_type_spec
  | growable_array_type_spec

Generic actuals in PR11.11c use these explicit type constructors at
name/call sites, but do not admit trailing subtype constraints there.

type_conversion ::=
    type_target '(' expression ')'

function_call ::=
    name [ actual_parameter_part ]

actual_parameter_part ::=
    '(' [ positional_parameter_association_list | named_parameter_association_list ] ')'

Empty parentheses are valid for zero-argument calls. A bare name uses the
`function_call` alternative without an `actual_parameter_part`; name resolution
decides whether it denotes a zero-argument call rather than an object or other
named entity.

positional_parameter_association_list ::=
    expression { ',' expression }

named_parameter_association_list ::=
    named_parameter_association { ',' named_parameter_association }

named_parameter_association ::=
    selector_name '=' expression

Named value arguments are admitted for declared, imported, and generic
function calls and for sum constructors. Positional and named value arguments
cannot be mixed in one function call or sum constructor. This mixing rule does
not apply to pragma argument associations in §8.13. Compiler built-ins and
generic type actuals remain positional-only. Sum constructor payload field names
are part of the public source contract once named constructor calls exist.

expression ::=
    relation { logical_operator relation }

logical_operator ::=
    'and'
  | 'and' 'then'
  | 'or'
  | 'or' 'else'
  | 'xor'

Mixed logical operators at the same nesting level require parentheses.

relation ::=
    shift_expression [ relational_operator shift_expression ]
  | shift_expression [ 'not' ] 'in' membership_choice_list

shift_expression ::=
    simple_expression { shift_operator simple_expression }

shift_operator ::=
    '<<' | '>>'

membership_choice_list ::=
    membership_choice { '|' membership_choice }

membership_choice ::=
    choice_expression | range | subtype_mark

simple_expression ::=
    [ unary_adding_operator ] term { binary_adding_operator term }

term ::=
    factor { multiplying_operator factor }

factor ::=
    primary [ '**' primary ]
  | 'abs' primary
  | 'not' primary

primary ::=
    numeric_literal
  | string_literal
  | character_literal
  | bracket_aggregate
  | 'null'
  | name
  | allocator
  | aggregate
  | some_expression
  | none_literal
  | '(' expression ')'
  | annotated_expression
  | conditional_expression

some_expression ::=
    'some' '(' expression ')'

none_literal ::=
    'none'

annotated_expression ::=
    '(' expression 'as' type_target ')'

bracket_aggregate ::=
    '[' [ expression { ',' expression } ] ']'

conditional_expression ::=
    if_expression
  | case_expression

if_expression ::=
    'if' condition 'then' expression
    { 'elsif' condition 'then' expression }
    'else' expression

case_expression ::=
    'case' expression 'is'
        case_expression_alternative { ',' case_expression_alternative }

case_expression_alternative ::=
    'when' discrete_choice_list 'then' expression

choice_expression ::=
    simple_expression

condition ::=
    expression

relational_operator ::=
    '==' | '!=' | '<' | '<=' | '>' | '>='

binary_adding_operator ::=
    '+' | '-' | '&'

unary_adding_operator ::=
    '+' | '-'

multiplying_operator ::=
    '*' | '/' | 'mod' | 'rem'

aggregate ::=
    record_aggregate
  | array_aggregate
  | delta_aggregate

record_aggregate ::=
    '(' record_component_association_list ')'

record_component_association_list ::=
    record_component_association { ',' record_component_association }
  | 'null' 'record'

record_component_association ::=
    [ component_choice_list '=' ] expression
  | component_choice_list '=' '<>'

component_choice_list ::=
    selector_name { '|' selector_name }
  | 'others'

array_aggregate ::=
    positional_array_aggregate
  | named_array_aggregate

positional_array_aggregate ::=
    '(' expression ',' expression { ',' expression } ')'
  | '(' expression { ',' expression } ',' 'others' '=' expression ')'
  | '(' expression { ',' expression } ',' 'others' '=' '<>' ')'

named_array_aggregate ::=
    '(' array_component_association { ',' array_component_association } ')'

array_component_association ::=
    discrete_choice_list '=' expression
  | discrete_choice_list '=' '<>'

delta_aggregate ::=
    '(' expression 'with' 'delta' record_component_association_list ')'
  | '(' expression 'with' 'delta' array_component_association { ',' array_component_association } ')'
```

## 8.7 Statements

Statements use the shared `terminator` production from §8.1. Block structure
for covered statements comes from indentation rather than explicit closing
keywords.

```
sequence_of_statements ::=
    statement_item { statement_item }

statement_item ::=
    statement
  | statement_local_declaration

statement_local_declaration ::=
    local_object_declaration
  | var_statement

local_object_declaration ::=
    defining_identifier_list ':' [ 'constant' ]
        subtype_indication [ '=' expression ] terminator
  | defining_identifier_list ':' [ 'constant' ]
        array_type_definition [ '=' expression ] terminator

var_statement ::=
    'var' defining_identifier_list ':'
        subtype_indication [ '=' expression ] terminator
  | 'var' defining_identifier_list ':'
        array_type_definition [ '=' expression ] terminator

statement ::=
    simple_statement
  | compound_statement

indented_statement_suite ::=
    INDENT
        sequence_of_statements
    DEDENT

simple_statement ::=
    assignment_statement
  | procedure_call_statement
  | print_statement
  | return_statement
  | exit_statement
  | delay_statement
  | send_statement
  | receive_statement
  | try_receive_statement
  | pragma

assignment_statement ::=
    name '=' expression terminator

procedure_call_statement ::=
    name [ actual_parameter_part ] terminator

The contextual builtins `append(items, value)`, `pop_last(items)`,
`contains(m, key)`, `get(m, key)`, `set(m, key, value)`, and
`remove(m, key)` use ordinary call syntax. Under PR11.11a the same
operations may also be written with selector-call sugar:
`items.append(value)`, `items.pop_last()`, `m.contains(key)`,
`m.get(key)`, `m.set(key, value)`, and `m.remove(key)`.
Named value arguments are rejected for these compiler built-ins; their
arguments remain positional-only in both free-call and selector-call form.

- `append` is admitted only as a procedure-call statement on a writable
  `list of T` name.
- `pop_last` is admitted only as an expression and returns `optional T`.
- `contains` and `get` are expression-only map builtins.
- `set` is statement-only and requires a writable `map of (K, V)` first
  argument.
- `remove` is expression-only, mutates a writable `map of (K, V)`, and
  returns `optional V`.

print_statement ::=
    'print' '(' expression ')' terminator

return_statement ::=
    simple_return_statement | extended_return_statement

simple_return_statement ::=
    'return' [ expression ] terminator

extended_return_statement ::=
    'return' defining_identifier ':' subtype_indication
        [ '=' expression ] 'do'
        handled_sequence_of_statements
    'end' 'return' terminator

exit_statement ::=
    'exit' [ 'when' condition ] terminator

delay_statement ::=
    'delay' expression terminator

compound_statement ::=
    if_statement
  | case_statement
  | loop_statement
  | select_statement

if_statement ::=
    'if' condition
        indented_statement_suite
    { 'else' 'if' condition
        indented_statement_suite }
    [ 'else'
        indented_statement_suite ]

case_statement ::=
    'case' expression
        indented_case_statement_alternatives

indented_case_statement_alternatives ::=
    INDENT
        case_statement_alternative { case_statement_alternative }
    DEDENT

case_statement_alternative ::=
    'when' discrete_choice_list
        indented_statement_suite

loop_statement ::=
    iteration_scheme
        indented_statement_suite
  | 'loop'
        indented_statement_suite

iteration_scheme ::=
    'while' condition
  | 'for' defining_identifier 'in' discrete_subtype_definition
  | 'for' defining_identifier 'of' name

handled_sequence_of_statements ::=
    sequence_of_statements
```

## 8.8 Subprograms

```
subprogram_declaration ::=
    [ 'public' ] function_specification terminator

subprogram_body ::=
    [ 'public' ] subprogram_specification
        indented_subprogram_body

indented_subprogram_body ::=
    INDENT
        { basic_declaration }
        { statement_item }
    DEDENT

subprogram_specification ::=
    function_specification

function_specification ::=
    'function' [ receiver_parameter_clause ] defining_identifier
        [ generic_formal_part ]
        [ formal_part ] [ 'returns' subtype_indication ]

receiver_parameter_clause ::=
    '(' defining_identifier ':' [ 'mut' ] subtype_indication ')'

formal_part ::=
    '(' parameter_specification { ';' parameter_specification } ')'

parameter_specification ::=
    defining_identifier_list ':' [ 'mut' ] subtype_indication
        [ '=' default_expression ]

Formal parameter lists retain structural semicolons as parameter separators.
These semicolons are not terminators and are not removable.

declarative_part ::=
    { basic_declaration }

expression_function_declaration ::=
    [ 'public' ] function_specification '(' expression ')' terminator

designator ::=
    identifier

Method-call sugar is source-level desugaring over the existing first-parameter
function model:

- `value.method(args)` rewrites to `method(value, args)` when exactly one
  visible compatible first-parameter function or builtin exists.
- Imported public functions may be called the same way:
  `value.method()` may resolve to `pkg.method(value)`.
- The receiver stays positional as the implicit first argument; named
  arguments apply only to the explicit parameter list.
- Bare selectors such as `.length`, `.present`, `.value`, and ordinary field
  access keep their existing meaning unless immediately followed by `(...)`.

For the post-PR11.11b surface, structural interfaces are also admitted with a
strict subset:

- interface declarations are `type name is interface` plus an indented suite
  of signature-only members,
- every interface member must use receiver syntax and the receiver type must be
  the enclosing interface name,
- interface types are admitted only in subprogram parameter positions in this
  milestone,
- public interface-constrained subprogram bodies remain deferred to a later
  milestone.

For the post-PR11.11c surface, Safe-native generics are also admitted with a
strict subset:

- generic declarations use Safe-native `of ...` syntax rather than Ada
  `generic` units,
- generic type declarations are package-level record or discriminated-record
  declarations only in this milestone,
- generic function calls require explicit type arguments, such as
  `identity of integer (value)`,
- generic value arguments may be named, but generic type actuals after `of`
  are positional-only,
- multi-parameter and constrained forms use a trailing named constraint map,
  such as `function max of T with T: orderable ...`,
- public generic declarations may cross package boundaries, but all
  concrete specializations lower away before MIR and emitted Ada.

default_expression ::=
    expression
```

## 8.9 Renaming and Subunits

```
subunit ::=
    'separate' '(' parent_unit_name ')'
    subprogram_body

parent_unit_name ::=
    package_name
```

## 8.10 Use Type Clause

```
use_type_clause ::=
    'use' 'type' subtype_mark { ',' subtype_mark } terminator
```

## 8.11 Representation Clauses

Legacy Ada representation clauses such as `for T use (...)` and `for T use
record ... end record;` are not part of Safe source after PR11.6.2. A
conforming implementation shall reject them.

## 8.12 Tasks and Channels

```
task_declaration ::=
    'task' defining_identifier
        [ 'with' 'priority' '=' static_expression ]
        [ [ ',' ] task_channel_clause { [ ',' ] task_channel_clause } ]
        indented_task_body

task_channel_clause ::=
    'sends' channel_name { ',' channel_name }
  | 'receives' channel_name { ',' channel_name }

indented_task_body ::=
    INDENT
        { basic_declaration }
        { statement_item }
    DEDENT

channel_declaration ::=
    [ 'public' ] 'channel' defining_identifier ':' subtype_mark
        'capacity' static_expression terminator

send_statement ::=
    'send' channel_name ',' expression ',' name terminator

receive_statement ::=
    'receive' channel_name ',' receive_target terminator

receive_target ::=
    name | defining_identifier ':' subtype_indication

try_receive_statement ::=
    'try_receive' channel_name ',' receive_target ',' name terminator

select_statement ::=
    'select'
        indented_select_arm
    { 'or'
        indented_select_arm }

indented_select_arm ::=
    INDENT
        select_arm
    DEDENT

select_arm ::=
    channel_arm | delay_arm

channel_arm ::=
    'when' defining_identifier ':' subtype_mark 'from' channel_name
        indented_statement_suite

delay_arm ::=
    'delay' expression
        indented_statement_suite

channel_name ::= name
```

## 8.13 Pragmas

```
pragma ::=
    'pragma' identifier [ '(' pragma_argument_association
        { ',' pragma_argument_association } ')' ] terminator

pragma_argument_association ::=
    [ identifier '=' ] expression
  | [ identifier '=' ] name
```

## 8.14 Lexical Elements

```
identifier ::=
    identifier_start { identifier_extend }

identifier_start ::=
    lowercase_letter

identifier_extend ::=
    lowercase_letter | digit | '_'

numeric_literal ::=
    decimal_literal | based_literal

decimal_literal ::=
    numeral [ '.' numeral ] [ exponent ]

based_literal ::=
    base '#' based_numeral [ '.' based_numeral ] '#' [ exponent ]

numeral ::=
    digit { [ '_' ] digit }

base ::=
    numeral

based_numeral ::=
    extended_digit { [ '_' ] extended_digit }

extended_digit ::=
    digit | 'A' | 'B' | 'C' | 'D' | 'E' | 'F'
          | 'a' | 'b' | 'c' | 'd' | 'e' | 'f'

exponent ::=
    'E' [ '+' ] numeral | 'E' '-' numeral

character_literal ::=
    ''' graphic_character '''

string_literal ::=
    '"' { string_element } '"'

string_element ::=
    graphic_character | '""'

comment ::=
    '--' { character }

lowercase_letter ::=
    'a' .. 'z'

digit ::=
    '0' .. '9'

static_expression ::= expression
static_simple_expression ::= simple_expression
```

## 8.15 Reserved Words

The following words are reserved in Safe. A conforming implementation shall reject any program that uses a reserved word as an identifier.

### Ada 2022 Reserved Words (8652:2023 §2.9)

All Ada 2022 reserved words are reserved in Safe regardless of whether the corresponding feature is retained:

```
abort       abs         abstract    accept      access
aliased     all         and         array       at
begin       body        case        constant    declare
delay       delta       digits      do          else
elsif       end         entry       exception   exit
for         function    generic     goto        if
in          interface   is          limited     loop
mod         new         not         null        of
or          others      out         overriding  package
parallel    pragma      private     procedure   protected
raise       range       record      rem         renames
requeue     return      reverse     select      separate
some        subtype     synchronized tagged     task
terminate   then        type        until       use
when        while       with        xor
```

### Safe Additional Reserved Words

```
public      channel     send        receive
try_send    try_receive sends       receives
capacity    from        binary      print
```

## 8.16 Grammar Summary

This grammar defines approximately 151 productions. All Safe syntactic
constructs are defined by the productions in §8.1–§8.14. Any construct that
appears in 8652:2023 but does not appear in this grammar is excluded from
Safe.
