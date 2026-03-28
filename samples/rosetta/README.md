# PR11.x Rosetta Corpus

This directory holds the Rosetta-style sample corpus that the stripped-down
development workflow checks with `scripts/run_samples.py`.

All samples use the current lowercase Safe surface. The checked-in sample
runner now exercises the corpus end to end:

- `safec check`
- `safec emit`
- emitted Ada build through `gprbuild`
- execution of the produced binary

PR11.1, PR11.2, and PR11.3 do not treat this corpus as a proof-bearing
milestone. Proof coverage re-enters later through `PR11.3a`, `PR11.8a`, and
`PR11.8b`.

## Status of Current Candidates

Starter corpus:

- `arithmetic/fibonacci.safe`
- `arithmetic/gcd.safe`
- `arithmetic/factorial.safe`
- `arithmetic/collatz_bounded.safe`
- `sorting/bubble_sort.safe`
- `sorting/binary_search.safe`
- `data_structures/bounded_stack.safe`
- `concurrency/producer_consumer.safe`

Candidate expansion:

- `linked_list_reverse.safe`
- `prime_sieve_pipeline.safe`

Deferred:

- `trapezoidal_rule.safe`
- `newton_sqrt_bounded.safe`

PR11.2 text/control-flow additions:

- `text/grade_message.safe`
- `text/hello_print.safe` (built-in `print` sample with exact stdout checks)
- `text/opcode_dispatch.safe` (`binary (8)` opcode dispatch)

PR11.3 structured-return additions:

- `data_structures/parse_result.safe`
- `text/lookup_pair.safe`
- `text/lookup_result.safe`

PR11.8d text/array additions:

- `text/bounded_prefix.safe`
- `data_structures/growable_sum.safe`
- `data_structures/fixed_to_growable.safe`
- `data_structures/growable_to_fixed.safe`

The current PR11.8d Rosetta coverage demonstrates:

- bounded strings through `string (N)`
- growable arrays through `array of T` and bracket literals
- array-only `for item of values`
- fixed -> growable widening
- static-only growable -> fixed narrowing

Still deferred beyond the current corpus:

- string iteration
- proof-based growable -> fixed narrowing
- string/growable channel elements
- string `case`
- string discriminants

## Running the Corpus

Use:

```bash
python3 scripts/run_samples.py
```

That runner builds the compiler once and, for every
`samples/rosetta/**/*.safe` file in stable order:

- runs `safec check`
- emits Ada and interface artifacts
- builds either the emitted `main.adb` for packageless entry samples or a tiny
  Ada driver for explicit-package samples
- runs the produced executable under a short timeout

`concurrency/producer_consumer.safe` uses a custom driver that waits briefly
for channel traffic, checks `producer_consumer.result = 42`, and then exits
explicitly so the sweep does not hang on the package's library-level tasks.

`text/hello_print.safe` is a packageless entry sample. The runner builds and
executes its emitted `main.adb` directly and asserts exact stdout:

```text
hello
```

## Embedded Smoke Lane

The Renode-based embedded smoke lane does **not** reuse this Rosetta corpus as
its pass/fail source. Bare-metal verdicts currently come from the dedicated
`tests/embedded/` fixtures instead, because those cases expose package-visible
integer results that can be checked through an exported status word without
depending on `print`, UART routing, or semihosting.

See [`../../docs/embedded_simulation.md`](../../docs/embedded_simulation.md)
for the current embedded setup and prerequisites.
