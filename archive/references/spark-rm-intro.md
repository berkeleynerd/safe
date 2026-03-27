# SPARK Reference Manual - Introduction Summary

## Overview

SPARK is a programming language and verification toolset designed for high-assurance software development. As described in the manual, it's "based on Ada, both subsetting the language to remove features that defy verification and also extending the system of contracts."

## Key Characteristics

**Language Foundation**: SPARK is built on Ada but removes problematic features and adds new aspects to support formal verification. The manual notes that "every valid SPARK program is also a valid Ada program."

**Verification Approach**: The language supports multiple verification methods. Rather than requiring proof alone, SPARK "facilitate[s] the use of unit proof in place of unit testing" while allowing combinations of formal analysis and traditional testing.

**Executable Contracts**: A distinctive feature is that assertion expressions in contracts have runtime semantics—they can be executed, proven, or both.

## Main Restrictions

To enable formal analysis, SPARK imposes notable limitations:
- No general aliasing of names
- No backward goto statements
- No controlled types (currently)
- Limited exception handling
- Restricted access type usage
- All expressions must be side-effect free

## Strategic Goals

The language aims to balance expressiveness with verifiability, support mixed verification approaches, enable constructive/modular development, and maintain unambiguous semantics to support sound formal analysis as defined by DO-333 certification standards.
