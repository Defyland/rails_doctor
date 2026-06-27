# Implementation Plan

## Scope

Graduate `rails_doctor` from a command-level MVP into a production-ready deploy
gate with stable extension points, auditable execution policy, opt-in
dependency readiness probes, real Rails integration tests, and a Rails
compatibility matrix.

## Files to Create or Update

- `rails_doctor.gemspec`
- `Gemfile`
- `Appraisals`
- `Rakefile`
- `gemfiles/*.gemfile`
- `lib/rails_doctor/**/*.rb`
- `lib/rails/commands/doctor/doctor_command.rb`
- `test/rails_doctor/**/*_test.rb`
- `test/support/**/*.rb`
- `README.md`
- `docs/spec-driven/*.md`
- `docs/adr/*.md`
- `docs/learning-journal.md`
- `.github/workflows/ci.yml`

## Acceptance Criteria Mapping

| Acceptance criterion | Implementation |
| --- | --- |
| `bin/rails doctor` command surface | Rails command file under `lib/rails/commands/doctor/` |
| Extensible checks | `RailsDoctor.register`, `Registry`, `Check` |
| Built-in MVP diagnostics | Domain files under `lib/rails_doctor/checks/` |
| Actionable failures | `Result` requires message, hint, evidence |
| JSON output | `Reporter` JSON renderer |
| Severity exit policy | `Runner#call` with `fail_on` |
| Operational execution policy | `Configuration`, `Suppression`, registry filtering, CLI `--only` and `--exclude` |
| Extensible readiness reachability | `ProbeFailure`, `Probes`, readiness check, config probe registration |
| Real command integration | Temporary Rails app harness in integration tests |
| GitHub Actions integration | `GitHubActions`, `Reporter`, `SuppressionReporter`, workflow examples, real Rails command integration tests |
| Optional command hooks | `CommandHook`, `CommandHookRunner`, Railtie `server` hook, Railtie `db:migrate`, `db:prepare`, `db:schema:load`, `db:structure:load`, and `assets:precompile` rake prerequisites, real command integration tests |
| Suppression inventory export | `SuppressionReport`, `SuppressionReporter`, `Runner#call(report: "suppressions")`, real Rails command integration tests |
| Rails compatibility matrix | `Appraisals`, Appraisal-generated gemfiles, CI matrix |
| Journal and decisions | `docs/learning-journal.md`, ADR files |
| CI baseline | `.github/workflows/ci.yml` |
| Auditable false-positive handling | Structured `suppressions` in Ruby config and `config/rails_doctor.yml`, visible as `suppressed` results in output with owner and expiry metadata, plus built-in expired and expiring-soon governance checks |

## Verification Commands

```bash
bundle install
bundle exec appraisal install
bundle exec rake test
bundle exec appraisal rake test
bundle exec standardrb
bundle exec rake build
```

## Risks

- Some built-in checks inspect conventions and may need suppression/configuration
  before use in complex production deployments.
- Intentional exceptions must stay reviewable and time-bounded; blind excludes
  are tolerated as an escape hatch but should not become the primary
  suppression policy.
- Active Record migration checks are intentionally skipped when Active Record is
  not loaded.
- Dependency probes are opt-in because real IO checks should be explicit at the
  app boundary.

## Deferred Work

- Extra Ruby-version coverage on top of the Rails matrix.
- Deeper Solid Queue and Active Storage installer-level checks as gaps are proven in the field.
- Broader automatic hook coverage beyond `server`, `db:migrate`, `db:prepare`, `db:schema:load`, `db:structure:load`, and `assets:precompile`, but only where the signal stays actionable.
- Chat, webhook, and non-GitHub downstream integrations on top of the suppression report export.
