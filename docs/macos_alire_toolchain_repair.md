# macOS Alire Toolchain Repair

This note is a developer recovery procedure, not a compiler runtime dependency.
The current frontend supports Ubuntu/Linux CI and local macOS development, and
the macOS host assumption is that an SDK is discoverable through
`xcrun --show-sdk-path` or `SDKROOT`.

## Symptom

`cd compiler_impl && $HOME/bin/alr build` can fail on macOS while rebuilding
dependency C sources with errors such as:

- `fatal error: stdlib.h: No such file or directory`
- `fatal error: unistd.h: No such file or directory`

The failure usually appears only after cached dependency objects are invalidated.

## Root Cause

Some local Alire GNAT toolchains bake in a version-specific sysroot such as
`MacOSX14.sdk`. On hosts where only the generic
`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` path exists, fresh C
rebuilds in dependencies can lose access to standard SDK headers.

## Recovery Procedure

1. Check the current SDK path:

```sh
xcrun --show-sdk-path
```

2. If the failing GNAT GCC driver is hardwired to a missing version-specific
   SDK, install a wrapper that:
   - calls `xcrun --show-sdk-path`
   - prepends `<sdk>/usr/include` to `CPATH`
   - execs the preserved real compiler binary

3. Re-run:

```sh
cd "$REPO_ROOT/compiler_impl"
$HOME/bin/alr build
```

## Notes

- This repair is host-local and reversible.
- It is not part of the Safe compiler runtime contract.
- The preferred long-term fix is to repair or reinstall the Alire/GNAT toolchain
  so its GCC driver resolves the current Command Line Tools SDK layout without a
  wrapper.
