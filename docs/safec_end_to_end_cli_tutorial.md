# SafeC End-to-End CLI Tutorial

This is a small host-local walkthrough for testing the current `safec`
compiler end to end after it has already been built.

It is intentionally practical rather than portable:

- it assumes you are running from this repository checkout
- it assumes the Ada toolchain is available through Alire on this host
- it follows the same Linux-oriented build assumptions as `compiler_impl/safec.gpr`

The walkthrough below uses a small typed-channel package so the emitted Ada
includes `gnat.adc` and actually exercises the local Jorvik link path.

Safe now has a built-in statement-only `print (expr)` surface for `integer`,
`string`, and `boolean`, plus unit-scope statements and packageless entry
files. For single-file roots with no leading `with` clauses, the repo-local
wrapper can now build or run directly:

```bash
python3 scripts/safe_cli.py build samples/rosetta/text/hello_print.safe
python3 scripts/safe_cli.py run samples/rosetta/text/hello_print.safe
```

The same wrapper now also has a proof-audit path:

```bash
python3 scripts/safe_cli.py prove samples/rosetta/text/hello_print.safe
```

`safe build` and `safe run` now use the same cached root-proof path by default
for the current repo-local wrapper flow. `safe prove` remains the explicit
proof-audit command and keeps the fuller default proof depth.
All three commands accept `--target-bits 32|64` and partition their shared
`.safe-build/` cache by target width.
`safe build` and `safe run` also accept `--no-prove`; `safe build` adds
`--clean-proofs`; and both `safe build` / `safe run` plus `safe prove` accept
`--level 1|2` (`safe build` and `safe run` default to level 1; `safe prove`
defaults to level 2).
`safe build`, `safe run`, and `safe prove` now all accept local imported roots
with leading `with` clauses when the sibling dependency sources are present.
They share a per-directory `.safe-build/` cache, but the model is still
`safe <command> <root.safe>`, not workspace-mode discovery. The emitted
machine-interface contract is now frozen at `typed-v6`, `mir-v4`, and
`safei-v5`; see [artifact_contract.md](./artifact_contract.md).

This tutorial still uses the raw `safec emit` path and a handwritten Ada driver
because it is focused on emitted artifacts and on a tasking example that needs
an explicit host-side exit.

Instead of asking you to type every command by hand, it writes a small
host-local build script that does the full flow:

1. writes a Safe package with a typed channel plus two tasks
2. runs `safec check`
3. emits JSON plus Ada/SPARK with `safec emit --ada-out-dir`
4. validates and analyzes the emitted MIR
5. writes a tiny Ada driver plus a matching `build.gpr`
6. builds and runs the resulting native binary

## 1. Start From the Repo Root

```bash
cd /path/to/safe
export REPO_ROOT="$(pwd)"
```

The compiler binary should already exist at:

```bash
compiler_impl/bin/safec
```

If you need to rebuild it first:

```bash
cd compiler_impl
alr build
cd ..
```

## 2. Create a Temporary Work Area

```bash
BASE_TMP="${TMPDIR%/}"
[ -d "$BASE_TMP" ] || BASE_TMP=/tmp
WORK="$(mktemp -d "$BASE_TMP"/safec-e2e.XXXXXX)"
mkdir -p "$WORK/out" "$WORK/iface" "$WORK/ada"
```

## 3. The Safe Sample the Script Will Build

The script below writes this package:

```safe
package typed_channel_demo

   subtype message is integer (0 to 1000);

   channel data_ch : message capacity 1;
   result : message = 0;

   task producer with priority = 10, sends data_ch
      loop
         send data_ch, 41
         delay 0.05

   task consumer with priority = 10, receives data_ch
      loop
         receive data_ch, input : message
         result = input + 1
```

Why this is useful:

- `data_ch` is a real typed channel carrying `message`
- the emitted Ada includes `gnat.adc`, so the build uses `pragma Profile(Jorvik);`
- the package exposes `result`, so a tiny Ada driver can print the observed
  channel output

## 4. Write the Automation Script

Save this as `"$WORK/run_typed_channel_demo.sh"`:

```bash
cat > "$WORK/run_typed_channel_demo.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:?set REPO_ROOT to your safe checkout root before running this script}"
SAFEC="$REPO_ROOT/compiler_impl/bin/safec"
ALR_BIN="${ALR_BIN:-alr}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

OUT_DIR="$SCRIPT_DIR/out"
IFACE_DIR="$SCRIPT_DIR/iface"
ADA_DIR="$SCRIPT_DIR/ada"
SOURCE="$SCRIPT_DIR/typed_channel_demo.safe"

mkdir -p "$OUT_DIR" "$IFACE_DIR" "$ADA_DIR"

cat > "$SOURCE" <<'SAFE'
package typed_channel_demo

   subtype message is integer (0 to 1000);

   channel data_ch : message capacity 1;

   result : message = 0;

   task producer with priority = 10, sends data_ch
      loop
         send data_ch, 41
         delay 0.05

   task consumer with priority = 10, receives data_ch
      loop
         receive data_ch, input : message
         result = input + 1
SAFE

"$SAFEC" check "$SOURCE"

"$SAFEC" emit \
  "$SOURCE" \
  --out-dir "$OUT_DIR" \
  --interface-dir "$IFACE_DIR" \
  --ada-out-dir "$ADA_DIR"

"$SAFEC" validate-mir "$OUT_DIR/typed_channel_demo.mir.json"
"$SAFEC" analyze-mir "$OUT_DIR/typed_channel_demo.mir.json"

test -f "$ADA_DIR/gnat.adc"

cat > "$ADA_DIR/main.adb" <<'ADA'
with Ada.Text_IO; use Ada.Text_IO;
with GNAT.OS_Lib;
with Typed_Channel_Demo;

procedure Main is
begin
   delay 0.2;
   Put_Line
     ("Typed channel result ="
      & Long_Long_Integer'Image (Long_Long_Integer (Typed_Channel_Demo.Result)));
   GNAT.OS_Lib.OS_Exit (0);
end Main;
ADA

cat > "$ADA_DIR/build.gpr" <<'GPR'
project Build is
   for Source_Dirs use (".");
   for Object_Dir use "obj";

   package Compiler is
      for Default_Switches ("Ada") use ("-gnatec=gnat.adc");
   end Compiler;
end Build;
GPR

(
   cd "$REPO_ROOT/compiler_impl"
   "$ALR_BIN" exec -- gprbuild -P "$ADA_DIR/build.gpr" main.adb
)

"$ADA_DIR/obj/main"
EOF

chmod +x "$WORK/run_typed_channel_demo.sh"
```

## 5. Run the Script

```bash
"$WORK/run_typed_channel_demo.sh"
```

Expected output:

```text
Typed channel result = 42
```

You should also now have:

```text
$WORK/out/typed_channel_demo.ast.json
$WORK/out/typed_channel_demo.typed.json
$WORK/out/typed_channel_demo.mir.json
$WORK/iface/typed_channel_demo.safei.json
$WORK/ada/typed_channel_demo.ads
$WORK/ada/typed_channel_demo.adb
$WORK/ada/gnat.adc
$WORK/ada/main.adb
$WORK/ada/build.gpr
```

## 6. Why the Driver Calls `OS_Exit`

The current Safe task subset requires each task body to keep its single outer
loop. That is why the sample tasks do not terminate on their own.

For this host-local tutorial, the handwritten Ada driver waits briefly for the
channel traffic to settle, prints the observed package-global result, and then
calls `GNAT.OS_Lib.OS_Exit (0)` so the process terminates cleanly instead of
waiting forever on the library-level tasks.

That exit pattern is just for the tutorial driver. The emitted Safe package
itself still follows the current task/channel model.

## 7. What This Proves

If all of the steps above pass, you have exercised the current compiler stack
end to end on this host:

- Safe source parsing and semantic checking
- MIR emission and validation
- `safei-v1` interface emission
- Ada/SPARK emission
- emitted `gnat.adc` generation for a real typed-channel package
- host-local Ada compilation of the emitted package plus handwritten driver
- execution of a native binary linked through the local Jorvik configuration

## Notes

- This is a host-local smoke path, not a replacement for
  `scripts/run_tests.py`, `scripts/run_samples.py`, or `scripts/run_proofs.py`.
- CI now runs the checked-in Rosetta sample sweep in `scripts/run_samples.py`,
  which checks, emits, proves, builds, and executes the sample corpus. This
  tutorial is still useful when you want to inspect the emitted artifacts and
  native driver steps manually on a local host.
- That "prove as well as run" policy is intentional: when a sample drifts out
  of the proved subset, we want the failure to appear as a source-level proof
  gap with a suggested guard or more explicit control-flow shape, not as a
  latent discrepancy hidden behind a passing runtime smoke test.
- For a checked-in single-file runnable print example, see
  `samples/rosetta/text/hello_print.safe`, which the sample sweep now emits,
  builds, runs, and checks for exact stdout through the emitted `main.adb`.
- For a checked-in enum example on the shipped PR11.8i surface, see
  `samples/rosetta/text/enum_dispatch.safe`, which the same sweep now proves,
  builds, and runs.
- For a checked-in binary-surface example, see
  `samples/rosetta/text/opcode_dispatch.safe`.
- `safe build` and `safe run` now support local imported roots and reuse the
  same per-directory `.safe-build/` cache as `safe prove`. They also run the
  cached root proof step by default in the current repo-local wrapper flow, but
  they are still root-file commands rather than workspace mode.
- `safe prove` is intentionally narrower than the full assurance story. It is
  the emitted-Ada GNATprove audit command only; it does not run the separate
  embedded/Jorvik evidence lane used for admitted concurrency runtime claims.
- This tutorial assumes a supported Linux host with the local Alire GNAT
  toolchain available on `PATH`.
- If you want a minimal emission-only sample instead, use
  `tests/positive/emitter_surface_proc.safe`.
