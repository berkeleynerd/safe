# Safe VSCode Extension

This is the minimal editor surface for Safe, with static grammar updates
through the current PR11.8c.1 compiler surface.

- Static syntax highlighting comes from [`syntaxes/safe.tmLanguage.json`](syntaxes/safe.tmLanguage.json).
- Diagnostics come from the disposable Python shim at [`../../scripts/safe_lsp.py`](../../scripts/safe_lsp.py).
- The extension intentionally does not provide completion, hover, rename, go-to-definition, or formatting.

Important boundary:

- The grammar statically highlights the current PR11.8c.1 lowercase surface,
  including the PR11.4 keyword cutovers, PR11.5 optional semicolons and
  statement-local `var`, PR11.6 indentation-structured blocks, PR11.6.2
  deprecated legacy block keywords, the PR11.7 lowercase-only source
  convention, the PR11.8 single-`integer` builtin set, the PR11.8b.1
  `sends` / `receives` task clauses, and the PR11.8c `binary (8|16|32|64)`
  surface with `<<` / `>>` shifts and plain `and` / `or` / `xor`, plus the
  PR11.8c.1 statement-only `print` builtin. Mixed-case Safe spellings are
  highlighted as invalid.
- Tuple selectors like `.1` and `.2` are highlighted syntactically only; the
  extension does not validate tuple arity or selector legality.
- This extension is intentionally disposable and may be replaced by a real post-v1.0 language server.

## Local Development Install

From the repo root:

```bash
editors/vscode/install-local.sh
```

Then reload VS Code (`Cmd+Shift+P` -> `Reload Window`).
