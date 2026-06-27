# Senior Readiness Spec

## Product Bar

RailsDoctor must behave like a Rails diagnostic platform with a real command,
custom-check DSL, actionable built-in checks, and scriptable output.

## Domain Bar

The domain is diagnostic evidence: check registration, execution context, result
severity, failure hints, and machine-readable evidence.

## Architecture Bar

The architecture must keep extension registration separate from Rails inspection
and output rendering.

## API Bar

The public API is Ruby DSL plus `bin/rails doctor`. There is no HTTP API.

## Data and Consistency Bar

No persisted data. Checks must avoid mutating the inspected application.

## Security Bar

Checks must not print raw secrets. Secret checks may report presence, length, and
configuration source, not values.

## Observability Bar

JSON output must expose structured evidence for CI and deployment automation.

## Performance Bar

Checks are synchronous and should run in deploy/CI timescales. Runtime benchmarks
are deferred until benchmark runs are recorded against the integration app.

## Scalability Bar

The registry must allow third-party gem registration without central file edits.

## Operational Cost Bar

The command should fail loudly on unknown format/severity and produce clear fix
hints to reduce deploy debugging cost.

## Maintainability Bar

Built-in checks must be grouped by domain and tested through `Context` fakes plus
real Rails command integration.

## Readability Bar

Check IDs must be stable, namespaced, and specific.

## Test and CI Bar

The project must pass unit tests, real Rails command integration tests, Standard
Ruby, gem build validation, CI, and a Rails compatibility matrix.

## Evidence Matrix

| Criterion | Evidence | Status | Notes |
| --- | --- | --- | --- |
| Rails command exists | `lib/rails/commands/doctor/doctor_command.rb` | Done | Covered by integration test harness. |
| Custom check DSL exists | `lib/rails_doctor/check.rb`, `lib/rails_doctor/registry.rb`, `test/rails_doctor/check_test.rb`, `test/rails_doctor/registry_test.rb`, `test/rails_doctor/integration_command_test.rb` | Done | Supports block DSL and failures with hints. Check severity is validated against the supported set, and check IDs are validated against the documented lowercase dotted format, so malformed extensions fail fast with concise errors. |
| Third-party registration exists | `RailsDoctor.register`, `Registry` duplicate checks | Done | Duplicate IDs fail fast. |
| Text, JSON, and GitHub Actions output exist | `lib/rails_doctor/reporter.rb`, `lib/rails_doctor/suppression_reporter.rb`, reporter tests | Done | JSON includes structured evidence and visible `suppressed` results with owner/expiry metadata for auditable policy exceptions. GitHub Actions output emits annotations for failed checks, suppressed checks, and actionable suppression inventory states. |
| Fail-on policy exists | `lib/rails_doctor/runner.rb`, runner tests | Done | `warning` maps to low severity threshold. |
| Execution policy exists | `lib/rails_doctor/configuration.rb`, `lib/rails_doctor/context.rb`, `lib/rails_doctor/registry.rb`, runner/integration tests | Done | Supports required env, required credentials, only, exclude, and structured suppressions from Ruby config, plus environment-scoped `config/rails_doctor.yml` policy files with fail-fast validation for unknown keys and malformed suppression entries. Suppressions now require owner and expiry metadata, suppressed-only selections return auditable `suppressed` results instead of ambiguous empty-run errors, and expired suppressions stop hiding the original check. Empty `only` intersections and true zero-check selections still fail. |
| Suppression governance exists | `lib/rails_doctor/suppression.rb`, `lib/rails_doctor/checks/policy.rb`, configuration/runner/integration tests | Done | Suppressions require `owner` and `expires_on`, suppressions nearing expiry trigger a built-in warning before they go stale, expired suppressions trigger a built-in failed result, and the original check runs again once the exception has expired. |
| Suppression inventory export exists | `lib/rails_doctor/suppression_report.rb`, `lib/rails_doctor/suppression_reporter.rb`, `lib/rails_doctor/runner.rb`, `test/rails_doctor/suppression_reporter_test.rb`, `test/rails_doctor/runner_test.rb`, `test/rails_doctor/integration_command_test.rb` | Done | `bin/rails doctor --report=suppressions` exports the full suppression inventory with `active`, `expiring_soon`, and `expired` states without running normal checks, and rejects `--fail-on`, `--only`, and `--exclude` to keep the surface unambiguous. |
| GitHub Actions workflow examples exist | `docs/product/ci-integration.md`, `docs/examples/github-actions/*.yml`, `test/rails_doctor/ci_examples_test.rb` | Done | The repo now ships validated examples for deploy gating and scheduled suppression audits using `--format=github-actions` plus JSON artifact export. |
| CLI errors fail clearly | `lib/rails/commands/doctor/doctor_command.rb`, `test/rails_doctor/integration_command_test.rb` | Done | Unknown check IDs and other framework usage errors exit with concise stderr instead of raw backtraces. |
| MVP checks exist | `lib/rails_doctor/checks/`, `lib/rails_doctor/probes.rb`, `test/rails_doctor/builtin_checks_test.rb`, `test/rails_doctor/integration_command_test.rb`, `test/rails_doctor/probes_test.rb` | Done | Config, session cookie strength, installer validation, readiness routes, and first-party probes now cover Active Record, cache, Redis, Sidekiq, Active Storage, GoodJob, and Solid Queue. Secret checks cover both required env vars and dot-path Rails credentials. The database pool check also resolves common `database.yml` role shapes and Rails Puma template defaults with explicit evidence sources. Readiness-route detection now prefers the real route set and follows mounted route sets before falling back to `config/routes.rb` text inspection. |
| Third-party check crashes are isolated | `lib/rails_doctor/check.rb`, `test/rails_doctor/check_test.rb`, `test/rails_doctor/integration_command_test.rb` | Done | Unexpected check exceptions become structured failures without aborting the entire run. |
| Contextual redaction policy exists | `lib/rails_doctor/context.rb`, `lib/rails_doctor/reporter.rb`, `test/rails_doctor/runner_test.rb`, `test/rails_doctor/integration_command_test.rb` | Done | Rails `filter_parameters` and explicit RailsDoctor redaction patterns are applied at render time without changing the check DSL. |
| Security avoids secret leakage | `lib/rails_doctor/checks/secrets.rb`, `lib/rails_doctor/redaction.rb`, `test/rails_doctor/builtin_checks_test.rb`, `test/rails_doctor/redaction_test.rb`, `test/rails_doctor/integration_command_test.rb` | Done | Built-in checks and exception-derived output now assert that secret values never appear in messages, hints, JSON output, or stderr. The `secret_key_base` check also rejects placeholder and repeated-pattern values instead of trusting length alone. |
| CI exists | `.github/workflows/ci.yml` | Done | Runs quality checks and compatibility matrix. |
| Rails compatibility matrix exists | `Appraisals`, `gemfiles/*.gemfile*`, `rake compat` | Done | Rails 7.1.6, 7.2.3.1, 8.0.5, and 8.1.3 verified locally. |
| Ruby support is enforced in CI | `.github/workflows/ci.yml`, `rails_doctor.gemspec` | Done | Quality runs on Ruby 3.2, 3.3, and 3.4; Rails matrix runs on the minimum supported Ruby, and Ruby 3.3.6 was verified locally. |
| Optional command hooks exist | `lib/rails_doctor/command_hook.rb`, `lib/rails_doctor/command_hook_runner.rb`, `lib/rails_doctor/railtie.rb`, configuration/runner/integration tests | Done | Applications can opt into RailsDoctor before `server`, `db:migrate`, `db:prepare`, `db:schema:load`, `db:structure:load`, or `assets:precompile` with hook-specific fail thresholds and filters. The implementation reuses the same runner and reporter as `bin/rails doctor`; migration-style and database-load hooks exclude `database.migrations.pending` by default, and the asset-build hook excludes `assets.production_build_missing`, so legitimate setup runs are not self-blocking. |
| Policy-file examples exist | `docs/product/policy-examples.md`, `docs/examples/policies/*.yml`, `test/rails_doctor/policy_examples_test.rb` | Done | Common deployment examples are versioned, use reasoned suppressions, and are validated through the real policy-file loading path so docs do not drift away from the executable contract. |
| HTTP API status is explicit | `openapi.yaml`, `docs/api/` | Done | No HTTP endpoints in this gem. |
| Benchmark baseline is explicit | `benchmarks/baseline.md`, `docs/benchmarks/methodology.md`, `bin/benchmark` | Done | Warm-boot runner baseline recorded locally with reproducible command. |
| Dummy app integration | `test/rails_doctor/integration_command_test.rb` | Done | Runs the real command in a temporary Rails app. |

## Out of Scope

- Automatic background IO against every dependency without explicit probe opt-in.
- Broad rule-expression policy above stable check IDs and explicit reasons.
- Publishing to RubyGems.
