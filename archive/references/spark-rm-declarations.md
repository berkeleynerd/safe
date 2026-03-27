# SPARK Reference Manual: Declarations and Types Summary

This section covers declarations and types in SPARK programming language version 27.0w.

## Key Concepts

**Full Default Initialization**: A type defines this property if it's a scalar with Default_Value, an access type, an array-of-scalar with Default_Component_Value, or similar structures where all components have initialization mechanisms.

**Subtype Constraints**: Dynamic constraints must use constant values rather than variable expressions, except in loop parameter specifications. This restriction ensures "an explicit constant which can be referenced in analysis and proof."

**Subtype Predicates**: Both static and dynamic predicates are permitted, though dynamic predicates cannot depend on variable inputs. The system generates verification conditions to ensure composite objects satisfy their predicates after component modifications.

## Access Types and Ownership

SPARK implements a strict **single-ownership model** for allocated objects through its ownership policy. Key principles include:

- At any program point, each allocated object has exactly one "owner"
- Paths can be marked as Persistent, Observed, Borrowed, or Moved
- Multiple references to one object are prevented, eliminating storage leaks and cyclic structures

**Traversal Functions**: Functions returning anonymous access types enable safe access patterns while maintaining ownership constraints.

## Notable Restrictions

- Derived tagged types cannot have named access-to-variable components
- Anonymous access types cannot convert to named access types
- Allocators and certain conversions only occur at library level
- Fixed point types where specified bounds exceed base range are excluded
