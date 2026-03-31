# PR11.8g.4 Proof Journal

## Goal

Close `PS-034` by making the shared growable-array runtime contracts honest in
the generic case while keeping the admitted emitted proof corpus green.

## Final design

- `Safe_Array_RT` is now the weak generic base runtime:
  - `From_Array` guarantees only result-length preservation.
  - `Clone` and `Copy` guarantee only length preservation.
  - `Free` guarantees zero length after cleanup.
- Stronger element-preservation facts are now routed through a separate
  identity-preserving path:
  - `Safe_Array_Identity_Ops`
  - `Safe_Array_Identity_RT`
- The emitter selects that stronger path only for growable arrays whose
  component type does **not** contain any recursive heap value type.
- Heap-backed component types continue to use the weaker `Safe_Array_RT` path.

## Why this closes the debt

The old generic `Safe_Array_RT.From_Array` contract overclaimed elementwise
ordinary `=` without any formal requirement that `Clone_Element` preserve that
equality. The new split removes that overclaim from the shared generic base
contract and restores stronger facts only where the emitter can justify them
for the concrete instantiated component type.

The identity-preserving path stays honest by:

- requiring the emitter to select it only for non-heap component types
- emitting concrete `Clone_Element` helpers with `Post => Result = Source`
- routing those helpers through `Safe_Array_Identity_Ops` before the stronger
  array runtime instance is instantiated

## Key implementation points

- `compiler_impl/stdlib/ada/safe_array_rt.ads`
  - weakened generic base contracts
- `compiler_impl/stdlib/ada/safe_array_identity_ops.ads`
- `compiler_impl/stdlib/ada/safe_array_identity_ops.adb`
- `compiler_impl/stdlib/ada/safe_array_identity_rt.ads`
- `compiler_impl/stdlib/ada/safe_array_identity_rt.adb`
- `compiler_impl/src/safe_frontend-ada_emit.adb`
  - runtime selection based on `Has_Heap_Value_Type`
  - identity-path helper specs emitted as elaboration-safe expression functions
  - identity-path no-op free helpers emitted as null procedures

## Verification

- `cd compiler_impl && alr build`
- `python3 scripts/run_tests.py` -> `436 passed, 0 failed`
- `python3 scripts/run_samples.py` -> `18 passed, 0 failed`
- `python3 scripts/run_proofs.py` -> `120 proved, 0 failed`

## Outcome

`PS-034` is closed on this branch. The shared runtime contract boundary is now:

- generically honest in `Safe_Array_RT`
- stronger only on the identity-preserving emitted/runtime path that justifies
  those stronger facts for the actual instantiated element type
