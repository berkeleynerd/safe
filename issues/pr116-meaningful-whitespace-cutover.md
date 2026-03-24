# PR11.6 Meaningful Whitespace Cutover

## Decision
- PR11.6 ships meaningful whitespace as the pre-1.0 block-structuring surface.
- `pragma Strict` is deferred to post-1.0 and removed from PR11.6 tracked scope.

## Covered Syntax
- package bodies
- subprogram bodies
- task bodies
- `if` / `else if` / `else`
- `for`, `while`, and bare `loop`
- `case` statements and record variant arms
- `select` statements
- record field lists

## Explicitly Deferred
- `declare` blocks and `declare_expression` stay explicit in PR11.6
- scoped-binding `receive` and channel direction constraints stay in later concurrency work
- long-term dual-mode compatibility is out of scope; any temporary dual parsing is migration-only

## Parser/Lexer Rules
- lexer emits structural `indent` / `dedent` tokens
- indentation is spaces-only, fixed at 3 spaces per level
- tabs in indentation are lexical errors
- blank and comment-only lines do not change indentation structure
- EOF flushes pending dedents
- same-line multiple statements still require `;`
- newline-separated statements may omit `;`

## Landing Shape
- add a dedicated PR11.6 gate/report
- migrate the tracked `.safe` corpus to whitespace form
- update tracker/dashboard/README/spec/proposal docs to state that whitespace is being shipped
- move `pragma Strict` into a post-1.0 deferred section in proposal docs
- ratchet and verify using canonical CI-authority flow only

## Acceptance
1. Covered constructs parse only in the shipped whitespace form.
2. The compiler enforces deterministic indentation structure with no accidental mixed-syntax acceptance.
3. A mechanical migrator and deterministic corpus evidence exist, and `ratchet --authority ci` / `verify --authority ci` stay green.
