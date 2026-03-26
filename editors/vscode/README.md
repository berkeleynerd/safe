# Safe VSCode Extension

This is the minimal editor surface for Safe, with static grammar updates
through the current PR11.6.2 compiler subset.

- Static syntax highlighting comes from [`syntaxes/safe.tmLanguage.json`](syntaxes/safe.tmLanguage.json).
- Diagnostics come from the disposable Python shim at [`../../scripts/safe_lsp.py`](../../scripts/safe_lsp.py).
- The extension intentionally does not provide completion, hover, rename, go-to-definition, or formatting.

Important boundary:

- The grammar statically highlights the current PR11.6.2 surface, including
  the PR11.4 keyword cutovers, PR11.5 optional semicolons and statement-local
  `var`, PR11.6 indentation-structured blocks, and PR11.6.2 deprecated legacy
  block keywords. It is still editor-only tokenization rather than semantic
  analysis.
- Tuple selectors like `.1` and `.2` are highlighted syntactically only; the
  extension does not validate tuple arity or selector legality.
- This extension is intentionally disposable and may be replaced by a real post-v1.0 language server.

## Local Development Install

From the repo root:

```bash
editors/vscode/install-local.sh
```

Then reload VS Code (`Cmd+Shift+P` -> `Reload Window`).
