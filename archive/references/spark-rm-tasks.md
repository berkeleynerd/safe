# Summary of SPARK Tasks and Synchronization (Section 9)

## Overview
This section of the SPARK Reference Manual covers task and protected types used for concurrent programming, subject to the Ravenscar or Jorvik profile restrictions.

## Key Concepts

**Synchronized Objects**: The specification defines types that "yield synchronized objects," including task types, protected types, synchronized interfaces, and certain composite types. An object is synchronized if it's of such a type, is atomic with `Async_Writers` true, is "constant after elaboration," or is a non-access constant.

**Communication**: Tasks may interact through synchronized objects like protected types, suspension objects, and atomic objects. Direct access to unsynchronized objects by multiple tasks is prohibited to eliminate data races.

**Part_Of Aspect**: Variables or state abstractions declared after a task or protected unit can use the Part_Of aspect to indicate they belong to that unit rather than their enclosing package.

## Key Rules

The specification requires that:
- Protected types must define full default initialization
- No mixing of synchronized and unsynchronized component types in a single type
- Global references in task/protected operations must denote synchronized objects
- The environment task cannot reference objects belonging to other tasks
- Task bodies must be unreachable at their end (enforcing no termination)

The document also defines how language-defined functions (like `Ada.Real_Time.Clock`) interact with state abstractions for purposes of flow analysis.
