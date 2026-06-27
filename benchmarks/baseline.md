# Benchmark Baseline

Measured on 2026-06-13 with `RUNS=100 bin/benchmark` against the dummy Rails app
after boot:

- Ruby: `3.4.9`
- Registered checks: `22`
- Median: `2.339 ms`
- P95: `3.155 ms`
- Max: `6.478 ms`

Scope note: this benchmark measures `RailsDoctor::Runner#call` after the Rails
environment is already loaded. It does not include process startup or command
boot time.
