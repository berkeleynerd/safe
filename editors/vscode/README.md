# Safe VSCode Extension

This is the minimal PR11.1 editor surface for Safe.

- Static syntax highlighting comes from [`syntaxes/safe.tmLanguage.json`](syntaxes/safe.tmLanguage.json).
- Diagnostics come from the disposable Python shim at [`../../scripts/safe_lsp.py`](../../scripts/safe_lsp.py).
- The extension intentionally does not provide completion, hover, rename, go-to-definition, or formatting.

Important boundary:

- The grammar statically highlights the current PR11.2 string/character/case surface, but it is still editor-only tokenization rather than semantic analysis.
- This extension is intentionally disposable and may be replaced by a real post-v1.0 language server.

## Local Development Install

From the repo root:

```bash
editors/vscode/install-local.sh
```

Then reload VS Code (`Cmd+Shift+P` -> `Reload Window`).
