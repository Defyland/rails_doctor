# Benchmark Methodology

The current benchmark target is warm-boot `RailsDoctor::Runner#call` execution
against a dummy Rails app:

- boot the dummy Rails app once before measurement;
- execute 100 runner calls by default;
- report median, p95, and max;
- include Ruby version and number of registered checks.

`bin/benchmark` is the canonical entrypoint and accepts `RUNS=<n>` overrides.
Re-run the baseline whenever the number of built-in checks changes, because the
published figures are expected to match the current registry surface.
