# Frontend Scale Limits

PR06.9.12 is a cliff-detection gate, not a benchmark commitment.

See [frontend_architecture_baseline.md](frontend_architecture_baseline.md) for the current live command set, supported subset boundary, and no-Python runtime doctrine.

The current proven scale envelope is the PR05/PR06 supported subset only:
- sequential Rule 1-4 checking
- sequential ownership checking
- committed `mir-v2` validation and analysis fixtures for that same subset

Rule 5, result safety, channels/tasks/concurrency, and other unsupported surfaces are out of scope for performance claims.

This policy is intentionally conservative:
- the PR06.9.12 gate uses generous budgets and wide ratio caps to catch obvious regression cliffs
- the gate does not claim a user-facing latency SLA or throughput guarantee
- raw timings are intentionally kept out of committed evidence so report JSON stays reproducible across environments

Exact corpus counts and the largest currently measured source/MIR fixtures are recorded in the committed PR06.9.12 evidence report:
- `execution/reports/pr06912-performance-scale-sanity-report.json`

The gate covers:
- repeated representative `check` runs
- repeated representative `emit` runs
- repeated representative `analyze-mir` runs
- one full supported-positive `check` sweep across the current PR05/PR06 subset
- one full MIR sweep across the committed MIR fixture corpus

The report records only deterministic pass/fail metadata, configured budgets, ratio caps, corpus counts, and largest-sample metadata.
