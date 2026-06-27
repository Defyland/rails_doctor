# CI Integration

RailsDoctor supports GitHub Actions annotations directly through
`--format=github-actions`.

Use the normal check surface for deploy gates:

```bash
bin/rails doctor --environment=production --fail-on warning --format=github-actions
```

Use the suppression inventory surface for scheduled review and artifact export:

```bash
bin/rails doctor --environment=production --report=suppressions --format=github-actions
bin/rails doctor --environment=production --report=suppressions --format=json
```

Recommended workflow shape:

- Gate pull requests or deploy branches with `--fail-on warning`.
- Export the suppression inventory as JSON so the current policy can be
  archived as a workflow artifact.
- Run a scheduled suppression audit that emits GitHub Actions annotations for
  `expired` and `expiring_soon` suppressions, while the JSON artifact keeps the
  full inventory.

Validated examples:

- [Deploy gate workflow](../examples/github-actions/deploy-gate.yml)
- [Scheduled suppression audit workflow](../examples/github-actions/suppression-audit.yml)
