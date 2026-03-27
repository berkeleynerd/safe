# SPARK Reference Manual - Section 6: Subprograms

This section covers subprogram declarations, bodies, and calls in the SPARK language. Here are the key concepts:

## Subprogram Declarations

A subprogram's **declaration view** differs from its **implementation view**. The declaration introduces the interface, while the implementation provides the body. Key rules include:

- Functions without side effects cannot have `out` or `in out` parameters and must return normally
- A subprogram with side effects can be a procedure, protected entry, or function with the Side_Effects aspect

## Contract Specifications

SPARK supports several aspects for formal specification:

- **Preconditions/Postconditions**: Standard Pre and Post contracts
- **Contract_Cases**: Partitions behavior into mutually exclusive cases with specific postconditions
- **Global**: Lists which global items a subprogram reads or writes
- **Depends**: Specifies information flow relationships between inputs and outputs

As the manual notes: "An _output_ of a subprogram is a global item or parameter whose final value...may be updated by a successful call to the subprogram."

## Global and Depends Aspects

These aspects enable information flow analysis. The Global aspect uses mode selectors (Input, Output, In_Out, Proof_In), while Depends specifies how outputs depend on inputs using arrow notation (e.g., `X => Y`).

## Additional Aspects

- **Exceptional_Cases**: Associates raised exceptions with postconditions
- **Program_Exit**: Indicates subprogram may exit the program
- **Always_Terminates**: Provides conditions ensuring the subprogram completes
- **Extensions_Visible**: Controls whether extension components are accessible
- **Subprogram_Variant**: Ensures recursive calls make progress toward termination

## Anti-Aliasing Rules

SPARK prevents problematic aliasing in subprogram calls by restricting how actual parameters can overlap with each other or global variables referenced by the called subprogram.
