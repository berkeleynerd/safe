# Archived macOS Alire Toolchain Repair

This note is archived historical guidance for an unsupported host. It is not a
compiler runtime dependency, and the current supported build environments are
Ubuntu/Linux CI and local Linux only.

## Symptom

`cd compiler_impl && alr build` can fail on macOS while rebuilding
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
alr build
```

## Notes

- This repair is host-local and reversible.
- It documents an unsupported platform and should not be treated as active repo policy.
- It is not part of the Safe compiler runtime contract.
- The preferred long-term fix is to repair or reinstall the Alire/GNAT toolchain
  so its GCC driver resolves the current Command Line Tools SDK layout without a
  wrapper.
