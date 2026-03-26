# PR11.x Rosetta Corpus

This directory holds the Rosetta-style sample corpus that the stripped-down
development workflow checks with `scripts/run_samples.py`.

All samples use the current lowercase Safe surface and stay in the
compile-only lane:

- `safec check`

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
- `text/opcode_dispatch.safe`

PR11.3 structured-return additions:

- `data_structures/parse_result.safe`
- `text/lookup_pair.safe`
- `text/lookup_result.safe`

## Running the Corpus

Use:

```bash
python3 scripts/run_samples.py
```

That runner builds the compiler once and runs `safec check` on every
`samples/rosetta/**/*.safe` file in stable order.
