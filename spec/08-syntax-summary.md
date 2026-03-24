# Section 8 — Syntax Summary

**This section is normative.**

This section provides the complete consolidated BNF grammar for Safe. This is the authoritative grammar; all syntactic constructs of Safe are defined here. The notation follows 8652:2023 §1.1.4: `::=` for productions, `[ ]` for optional, `{ }` for zero or more repetitions, `|` for alternation. Keywords are shown in **bold** where referenced in prose; in productions they appear as quoted literals. Nonterminals are in `snake_case`.

For the PR11.6 surface, the lexer emits structural `INDENT` / `DEDENT` tokens
from leading spaces-only indentation in fixed 3-space steps. Covered block
constructs are delimited by those structural tokens rather than explicit
closing keywords. `declare` blocks and `declare_expression` remain explicit in
this release and are therefore called out separately where they still use
`begin` / `end`.

---

## 8.1 Compilation Units

```
compilation_unit ::=
    context_clause package_unit

context_clause ::=
    { with_clause }

with_clause ::=
    'with' package_name { ',' package_name } ';'

package_name ::=
    identifier { '.' identifier }

package_unit ::=
    'package' defining_identifier
        indented_package_item_list

indented_package_item_list ::=
    INDENT
        { package_item }
    DEDENT
```

## 8.2 Package Items

```
package_item ::=
    basic_declaration
  | task_declaration
  | channel_declaration
  | use_type_clause
  | representation_item
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
    [ 'public' ] 'type' defining_identifier [ known_discriminant_part ]
        'is' type_definition ';'

incomplete_type_declaration ::=
    [ 'public' ] 'type' defining_identifier ';'

subtype_declaration ::=
    [ 'public' ] 'subtype' defining_identifier 'is' subtype_indication ';'

object_declaration ::=
    [ 'public' ] defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        subtype_indication [ '=' expression ] ';'
  | [ 'public' ] defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        array_type_definition [ '=' expression ] ';'
  | [ 'public' ] defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        access_definition [ '=' expression ] ';'

number_declaration ::=
    [ 'public' ] defining_identifier_list ':' 'constant' '=' static_expression ';'

defining_identifier_list ::=
    defining_identifier { ',' defining_identifier }

subunit_stub ::=
    subprogram_specification 'is' 'separate' ';'

renaming_declaration ::=
    object_renaming_declaration
  | package_renaming_declaration
  | subprogram_renaming_declaration

object_renaming_declaration ::=
    [ 'public' ] defining_identifier ':' subtype_mark 'renames' name ';'

package_renaming_declaration ::=
    [ 'public' ] 'package' defining_identifier 'renames' package_name ';'

subprogram_renaming_declaration ::=
    [ 'public' ] subprogram_specification 'renames' name ';'
```

## 8.4 Type Definitions

```
type_definition ::=
    enumeration_type_definition
  | signed_integer_type_definition
  | modular_type_definition
  | floating_point_definition
  | ordinary_fixed_point_definition
  | decimal_fixed_point_definition
  | array_type_definition
  | record_type_definition
  | access_type_definition
  | derived_type_definition

enumeration_type_definition ::=
    '(' enumeration_literal { ',' enumeration_literal } ')'

enumeration_literal ::=
    defining_identifier | defining_character_literal

signed_integer_type_definition ::=
    'range' static_simple_expression '..' static_simple_expression

modular_type_definition ::=
    'mod' static_expression

floating_point_definition ::=
    'digits' static_expression [ real_range_constraint ]

ordinary_fixed_point_definition ::=
    'delta' static_expression real_range_constraint

decimal_fixed_point_definition ::=
    'delta' static_expression 'digits' static_expression [ real_range_constraint ]

real_range_constraint ::=
    'range' simple_expression '..' simple_expression

array_type_definition ::=
    unconstrained_array_definition
  | constrained_array_definition

unconstrained_array_definition ::=
    'array' '(' index_subtype_definition { ',' index_subtype_definition } ')'
        'of' component_definition

constrained_array_definition ::=
    'array' '(' discrete_subtype_definition { ',' discrete_subtype_definition } ')'
        'of' component_definition

index_subtype_definition ::=
    subtype_mark 'range' '<>'

discrete_subtype_definition ::=
    discrete_subtype_indication | range

component_definition ::=
    [ 'aliased' ] subtype_indication
  | [ 'aliased' ] access_definition

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
  | 'null' ';'

component_item ::=
    component_declaration
  | representation_item

component_declaration ::=
    defining_identifier_list ':' component_definition [ '=' default_expression ] ';'

known_discriminant_part ::=
    '(' discriminant_specification { ';' discriminant_specification } ')'

discriminant_specification ::=
    defining_identifier_list ':' subtype_mark [ '=' default_expression ]

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

access_type_definition ::=
    access_to_object_definition

access_to_object_definition ::=
    [ 'not' 'null' ] 'access' [ 'all' ] subtype_indication
  | [ 'not' 'null' ] 'access' [ 'constant' ] subtype_indication

access_definition ::=
    [ 'not' 'null' ] 'access' [ 'all' ] subtype_mark
  | [ 'not' 'null' ] 'access' [ 'constant' ] subtype_mark

derived_type_definition ::=
    [ 'limited' ] 'new' subtype_indication

allocator ::=
    'new' subtype_indication
  | 'new' '(' expression 'as' subtype_mark ')'
```

## 8.5 Subtype Indications

```
subtype_indication ::=
    [ 'not' 'null' ] subtype_mark [ constraint ]

subtype_mark ::=
    name

constraint ::=
    scalar_constraint
  | index_constraint
  | discriminant_constraint

scalar_constraint ::=
    range_constraint
  | digits_constraint
  | delta_constraint

range_constraint ::=
    'range' range

range ::=
    simple_expression '..' simple_expression
  | name '.' 'Range' [ '(' static_expression ')' ]

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
    identifier

indexed_component ::=
    name '(' expression { ',' expression } ')'

slice ::=
    name '(' discrete_range ')'

selected_component ::=
    name '.' selector_name

selector_name ::=
    identifier

type_conversion ::=
    subtype_mark '(' expression ')'

function_call ::=
    name [ actual_parameter_part ]

actual_parameter_part ::=
    '(' parameter_association { ',' parameter_association } ')'

parameter_association ::=
    [ selector_name '=' ] expression

expression ::=
    relation { 'and' relation }
  | relation { 'and' 'then' relation }
  | relation { 'or' relation }
  | relation { 'or' 'else' relation }
  | relation { 'xor' relation }

relation ::=
    simple_expression [ relational_operator simple_expression ]
  | simple_expression [ 'not' ] 'in' membership_choice_list

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
  | 'null'
  | name
  | allocator
  | aggregate
  | '(' expression ')'
  | annotated_expression
  | conditional_expression
  | declare_expression

annotated_expression ::=
    '(' expression 'as' subtype_mark ')'

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

declare_expression ::=
    'declare' { object_declaration }
    'begin' expression

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

Within executable statement sequences, `statement_terminator` may be either an
explicit `;` or an omitted terminator when the next significant token begins on
a later source line. This omission rule applies only to executable statement
sequences. Declarative parts and package items keep explicit semicolons. Block
structure for covered statements comes from indentation rather than explicit
closing keywords.

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
    defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        subtype_indication [ '=' expression ] statement_terminator
  | defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        array_type_definition [ '=' expression ] statement_terminator
  | defining_identifier_list ':' [ 'aliased' ] [ 'constant' ]
        access_definition [ '=' expression ] statement_terminator

var_statement ::=
    'var' defining_identifier_list ':' [ 'aliased' ]
        subtype_indication [ '=' expression ] statement_terminator
  | 'var' defining_identifier_list ':' [ 'aliased' ]
        array_type_definition [ '=' expression ] statement_terminator
  | 'var' defining_identifier_list ':' [ 'aliased' ]
        access_definition [ '=' expression ] statement_terminator

statement_terminator ::=
    ';'
  | omitted_statement_terminator

omitted_statement_terminator ::=
    <no token; permitted only when the next significant token begins on a later source line>

statement ::=
    [ label ] simple_statement
  | [ label ] compound_statement

indented_statement_suite ::=
    INDENT
        sequence_of_statements
    DEDENT

label ::=
    '<<' identifier '>>'

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
  | pragma

null_statement ::=
    'null' statement_terminator

assignment_statement ::=
    name '=' expression statement_terminator

procedure_call_statement ::=
    name [ actual_parameter_part ] statement_terminator

return_statement ::=
    simple_return_statement | extended_return_statement

simple_return_statement ::=
    'return' [ expression ] statement_terminator

extended_return_statement ::=
    'return' defining_identifier ':' [ 'aliased' ] subtype_indication
        [ '=' expression ] 'do'
        handled_sequence_of_statements
    'end' 'return' ';'
  | 'return' defining_identifier ':' access_definition
        [ '=' expression ] 'do'
        handled_sequence_of_statements
    'end' 'return' ';'

exit_statement ::=
    'exit' [ loop_name ] [ 'when' condition ] statement_terminator

goto_statement ::=
    'goto' label_name statement_terminator

delay_statement ::=
    'delay' expression statement_terminator

compound_statement ::=
    if_statement
  | case_statement
  | loop_statement
  | block_statement
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
    [ loop_name ':' ] iteration_scheme
        indented_statement_suite
  | [ loop_name ':' ] 'loop'
        indented_statement_suite

iteration_scheme ::=
    'while' condition
  | 'for' defining_identifier 'in' [ 'reverse' ] discrete_subtype_definition
  | 'for' defining_identifier 'of' [ 'reverse' ] name

block_statement ::=
    [ block_name ':' ]
    'declare'
        INDENT
            { basic_declaration }
        DEDENT
    'begin'
        indented_statement_suite
    'end' statement_terminator

handled_sequence_of_statements ::=
    sequence_of_statements

loop_name ::= identifier
block_name ::= identifier
label_name ::= identifier
```

## 8.8 Subprograms

```
subprogram_declaration ::=
    [ 'public' ] function_specification ';'

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
    'function' defining_identifier [ formal_part ] [ 'returns' subtype_mark ]
  | 'function' defining_identifier [ formal_part ] [ 'returns' access_definition ]

formal_part ::=
    '(' parameter_specification { ';' parameter_specification } ')'

parameter_specification ::=
    defining_identifier_list ':' [ 'aliased' ] mode subtype_mark
        [ '=' default_expression ]
  | defining_identifier_list ':' access_definition
        [ '=' default_expression ]

mode ::=
    [ 'in' ] | 'in' 'out' | 'out'

declarative_part ::=
    { basic_declaration }

expression_function_declaration ::=
    [ 'public' ] function_specification '(' expression ')' ';'

designator ::=
    identifier

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
    'use' 'type' subtype_mark { ',' subtype_mark } ';'
```

## 8.11 Representation Items

```
representation_item ::=
    attribute_definition_clause
  | enumeration_representation_clause
  | record_representation_clause
  | aspect_specification

attribute_definition_clause ::=
    'for' name 'use' expression ';'

enumeration_representation_clause ::=
    'for' subtype_mark 'use' aggregate ';'

record_representation_clause ::=
    'for' subtype_mark 'use'
        'record' [ 'at' 'mod' static_expression ';' ]
            { component_clause }
        'end' 'record' ';'

component_clause ::=
    component_name 'at' static_expression 'range'
        static_simple_expression '..' static_simple_expression ';'

aspect_specification ::=
    'with' aspect_mark '=' expression

aspect_mark ::=
    identifier
```

## 8.12 Tasks and Channels

```
task_declaration ::=
    'task' defining_identifier
        [ 'with' 'Priority' '=' static_expression ]
        indented_task_body

indented_task_body ::=
    INDENT
        { basic_declaration }
        { statement_item }
    DEDENT

channel_declaration ::=
    [ 'public' ] 'channel' defining_identifier ':' subtype_mark
        'capacity' static_expression ';'

send_statement ::=
    'send' channel_name ',' expression statement_terminator

receive_statement ::=
    'receive' channel_name ',' name statement_terminator

try_send_statement ::=
    'try_send' channel_name ',' expression ',' name statement_terminator

try_receive_statement ::=
    'try_receive' channel_name ',' name ',' name statement_terminator

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
        { ',' pragma_argument_association } ')' ] ';'

pragma_argument_association ::=
    [ identifier '=' ] expression
  | [ identifier '=' ] name
```

## 8.14 Lexical Elements

```
identifier ::=
    identifier_start { identifier_extend }

identifier_start ::=
    letter

identifier_extend ::=
    letter | digit | '_'

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

letter ::=
    'A' .. 'Z' | 'a' .. 'z'

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
try_send    try_receive capacity    from
```

## 8.16 Grammar Summary

This grammar defines approximately 148 productions. All Safe syntactic constructs are defined by the productions in §8.1–§8.14. Any construct that appears in 8652:2023 but does not appear in this grammar is excluded from Safe.
