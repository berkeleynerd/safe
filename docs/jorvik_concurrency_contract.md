# Jorvik-Backed Concurrency Contract

This note is the current assurance boundary for Safe's admitted concurrency
surface after `PR11.8g.3`.

It covers the shipped subset only:

- static unit-scope tasks
- bounded FIFO channels
- blocking `send` / `receive`
- non-blocking `try_send` / `try_receive`
- `select` with one or more channel arms and at most one delay arm
- the admitted value-only channel element surface, including the named
  heap-backed string / growable-channel fixtures already carried by the proof
  matrix

## Admitted Semantics

- Tasks execute under the emitted `pragma Profile (Jorvik)` profile and rely on
  the shipped Jorvik/Ravenscar runtime contract for fixed-priority tasking.
- Equal-priority task ordering remains implementation-defined.
- Channels are bounded FIFO queues, and channel operations are atomic with
  respect to other operations on the same channel.
- Blocking is confined to the calling task.
- The emitted channel lowering still computes task-based ceilings, but it also
  raises the ceiling conservatively to `System.Any_Priority'Last` for channels
  touched from package-level code or exposed as public channels, so the
  environment task and direct external callers do not violate the emitted
  protected-object boundary on the admitted STM32F4/Jorvik runtime.
- The admitted `select` subset in `PR11.9a` is intentionally narrower than the
  full source surface: select arms must target same-unit non-public channels,
  and emitted select statements are admitted only from direct task bodies and
  unit-scope statements.
- `select` channel arms are checked in source order, and the first ready arm
  wins.
- If no channel arm is ready and a delay arm is present, the current
  implementation establishes one absolute deadline at select entry, then blocks
  on a package-scope dispatcher that is signaled by same-unit channel sends or
  by a package-scope timing event when the deadline expires. After each wake,
  the same source-order readiness precheck runs again.
- No stronger fairness, wakeup immediacy, or cycle-accurate timing guarantee is
  part of the admitted surface.

## Assurance Basis

The admitted concurrency contract is justified by two required mechanisms:

- emitted-package GNATprove closure from `scripts/run_proofs.py`
- the blocking embedded evidence lane:

```bash
python3 scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency
```

That embedded lane must stay green for:

- the generated Jorvik startup probe
- `producer_consumer_result.safe`
- `scoped_receive_result.safe`
- `delay_scope_result.safe`
- `select_priority_result.safe`
- `string_channel_result.safe`

## Still Out Of Scope

These claims are not part of the admitted surface:

- fairness guarantees beyond source-order select priority
- stronger latency or round-robin fairness guarantees beyond the admitted
  blocking dispatcher contract plus ordinary runtime scheduling jitter
- cycle-accurate or peripheral-level timing claims
- targets or runtimes beyond the documented STM32F4 / `light-tasking-stm32f4`
  evidence lane
- elimination of the documented receive-side equality `pragma Assume` used by
  the direct sequential single-slot string / growable channel proof path from
  `PR11.8g.2`
