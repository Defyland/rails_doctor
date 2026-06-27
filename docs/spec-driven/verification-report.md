# Verification Report

## Summary

Framework, execution policy, opt-in readiness probes including Redis, Sidekiq,
Active Storage, GoodJob, and Solid Queue, explicit secret-redaction coverage
for built-ins, exception-derived output, contextual render-time policies,
isolated crashing checks, clean CLI failure handling, real Rails command
integration, stronger database pool versus Puma thread detection for common
Rails config shapes, required Rails credentials coverage, environment-scoped
policy file support with validation, fail-fast severity validation for custom
checks, fail-fast ID validation for custom checks, production session cookie
flag coverage, auditable suppression policy with visible `suppressed` results,
required owner and expiry metadata, proactive reminder coverage for upcoming
suppression expiry, opt-in command hooks before `server`, `db:migrate`,
`db:prepare`, and `assets:precompile`, route-set based readiness-route
detection across mounted route sets, validated policy-file examples for common
deployment topologies, dedicated suppression inventory export, GitHub Actions
annotation output and validated workflow examples, measured benchmark baseline,
tests, lint, gem build, and Rails compatibility matrix setup completed for the
current milestone.

## Commands Run

- `bundle install`: passed, installed Rails/Railties 8.1.3, Standard 1.55.0, Minitest 5.27.0.
- `bundle exec appraisal install`: passed, generated and resolved appraisals for Rails 7.1.6, 7.2.3.1, 8.0.5, and 8.1.3.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/reporter_test"; require "rails_doctor/runner_test"; require "rails_doctor/integration_command_test"'`: passed, `28 runs, 125 assertions, 0 failures, 0 errors`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/registry_test"; require "rails_doctor/reporter_test"; require "rails_doctor/runner_test"; require "rails_doctor/builtin_checks_test"; require "rails_doctor/integration_command_test"'`: passed, `82 runs, 314 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/registry_test"; require "rails_doctor/reporter_test"; require "rails_doctor/runner_test"; require "rails_doctor/integration_command_test"'`: passed, `56 runs, 233 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/builtin_checks_test"; require "rails_doctor/integration_command_test"'`: passed, `65 runs, 264 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/command_hook_runner_test"; require "rails_doctor/integration_command_test"'`: passed, `51 runs, 234 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/reporter_test"; require "rails_doctor/command_hook_runner_test"; require "rails_doctor/integration_command_test"'`: passed, `38 runs, 223 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/builtin_checks_test"; require "rails_doctor/integration_command_test"'`: passed, `56 runs, 266 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/builtin_checks_test"; require "rails_doctor/integration_command_test"'`: passed again after `secret_key_base` hardening, `60 runs, 288 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/runner_test"; require "rails_doctor/integration_command_test"'`: passed, `43 runs, 191 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/registry_test"; require "rails_doctor/integration_command_test"'`: passed, `33 runs, 146 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/check_test"; require "rails_doctor/integration_command_test"'`: passed, `26 runs, 141 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/registry_test"; require "rails_doctor/integration_command_test"'`: passed, `28 runs, 146 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/command_hook_runner_test"; require "rails_doctor/integration_command_test"'`: passed after `db:prepare` hook coverage, `57 runs, 267 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/probes_test"; require "rails_doctor/integration_probe_helpers_test"'`: passed after Sidekiq and GoodJob probe coverage, `25 runs, 85 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/probes_test"; require "rails_doctor/integration_probe_helpers_test"; require "rails_doctor/integration_command_test"'`: passed, `60 runs, 305 assertions, 0 failures, 0 errors, 0 skips`.
- `BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/integration_command_test"'`: passed after redis/Sidekiq cross-version probe fix, `35 runs, 220 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/configuration_test"; require "rails_doctor/command_hook_runner_test"; require "rails_doctor/integration_command_hook_assets_test"'`: passed after `assets:precompile` hook coverage, `26 runs, 65 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/policy_examples_test"'`: passed after policy example coverage, `1 runs, 13 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/runner_test"'`: passed after suppression inventory export coverage, `9 runs, 32 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/suppression_reporter_test"'`: passed after suppression inventory export coverage, `1 runs, 1 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/integration_command_test"'`: passed after suppression inventory export coverage, `37 runs, 238 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/ci_examples_test"; require "rails_doctor/github_actions_test"; require "rails_doctor/reporter_test"; require "rails_doctor/suppression_reporter_test"'`: passed after GitHub Actions integration coverage, `11 runs, 43 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec ruby -Itest -e 'require "test_helper"; require "rails_doctor/integration_command_test"'`: passed after GitHub Actions integration coverage, `39 runs, 250 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec standardrb`: passed.
- `asdf exec bundle exec rake test`: passed after GitHub Actions integration coverage, `156 runs, 629 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec appraisal rake test`: passed after GitHub Actions integration coverage across Rails 7.1.6, 7.2.3.1, 8.0.5, and 8.1.3, each with `156 runs, 629 assertions, 0 failures, 0 errors, 0 skips`.
- `asdf exec bundle exec rake build`: passed, built `pkg/rails_doctor-0.1.0.gem`.
- `bundle exec rake test`: passed, `126 runs, 489 assertions, 0 failures, 0 errors, 0 skips`.
- `bundle exec appraisal rake test`: passed across Rails 7.1.6, 7.2.3.1, 8.0.5, and 8.1.3.
- `bundle exec standardrb`: passed.
- `$HOME/.asdf/shims/ruby bin/benchmark`: passed, `median 2.339 ms`, `p95 3.155 ms`, `max 6.478 ms`, `22` checks, Ruby `3.4.9`.
- `ASDF_RUBY_VERSION=3.3.6 bundle install`: passed.
- `ASDF_RUBY_VERSION=3.3.6 bundle exec rake test`: passed, `126 runs, 489 assertions, 0 failures, 0 errors, 0 skips`.
- `ASDF_RUBY_VERSION=3.3.6 asdf exec bundle exec rake test`: passed after GitHub Actions integration coverage, `156 runs, 629 assertions, 0 failures, 0 errors, 0 skips`.
- `ASDF_RUBY_VERSION=3.3.6 bundle exec ruby -S standardrb`: passed.
- `ASDF_RUBY_VERSION=3.3.6 bundle exec rake build`: passed.
- `bundle exec rake build`: passed, built `pkg/rails_doctor-0.1.0.gem`.
- `bin/check`: passed, running tests and Standard Ruby.
- `bin/compat`: passed, running the full Appraisal matrix locally.
- `bundle exec ruby -Ilib -e 'require "rails_doctor"; puts RailsDoctor.registry.size'`: passed, 22 built-in checks registered.
- `bundle exec ruby -Ilib -e 'require "rails_doctor/railtie"; require "rails/command"; require "rails/commands/doctor/doctor_command"; ...'`: passed, direct Railtie and command loading works.

## Passing Criteria

- Core DSL, registry, execution filtering, reporter, runner, built-in check loading,
  real Rails command integration, and gem packaging pass local verification.
- Real command integration covers `--environment`, `--format=json`,
  `--format=github-actions`, `--fail-on`, config-driven exclusions,
  CLI-driven `--only`, and configured dependency probes including first-party
  Redis, Sidekiq, Active Storage, GoodJob, and Solid Queue reachability.
- Built-in secret checks now have explicit regression coverage proving that
  messages, hints, structured evidence, `stdout`, and `stderr` do not leak
  configured secret values.
- `rails.secrets.secret_key_base_missing` no longer trusts length alone. It now
  also rejects obvious placeholders, repeated single-character values, and
  exact repeated patterns, which closes a false-green path for insecure
  boot-time secrets such as `"x" * 64`.
- Built-in secret checks now also cover explicitly required Rails credentials
  through dot-separated paths, which closes the original gap where
  `required_env` existed but `credentials/env obrigatorios ausentes` was only
  half implemented.
- Execution policy now also supports `config/rails_doctor.yml` with `default`
  and environment sections. Unknown keys fail fast with a concise command error
  instead of silently dropping intended suppressions or requirements.
- Execution policy now also supports structured `suppressions` in both Ruby
  config and `config/rails_doctor.yml`. Each suppression requires a stable
  `check_id` and a non-empty `because`, which closes the earlier production gap
  where false positives could only be hidden through opaque `exclude_checks`
  lists.
- Suppression governance is now time-bounded and attributable. `owner` and
  `expires_on` are required metadata, malformed dates fail fast, and the new
  `rails_doctor.suppressions.expired` built-in fails once an exception ages out.
- `rails_doctor.suppressions.expiring_soon` now warns when a suppression has 14
  days or less remaining, with explicit `window_days`, `days_until_expiry`, and
  `owner` evidence so teams can review policy before it silently goes stale.
- Suppressed checks no longer disappear silently. They now return explicit
  `suppressed` results in both text and JSON output, and a run whose selected
  checks are all suppressed no longer fails as an empty selection. This keeps
  deploy gates auditable without weakening the zero-check guardrail for truly
  empty runs.
- Expired suppressions no longer hide the original problem. Once a suppression
  expires, the underlying check runs again and the governance failure is
  reported alongside it.
- Suppression governance now also has a dedicated export surface. `bin/rails
  doctor --report=suppressions` returns the full suppression inventory in text
  or JSON with `active`, `expiring_soon`, and `expired` states, days to expiry,
  and owner metadata, which closes the operational gap where teams could gate
  on policy drift but could not cleanly export the whole exception inventory.
- CI and downstream GitHub consumption no longer need custom parsing glue.
  `--format=github-actions` now emits first-party annotations for failed checks,
  suppressed checks, and actionable suppression inventory states, and the repo
  includes validated workflow examples for deploy gates and scheduled
  suppression audits.
- Optional command hooks now let applications run RailsDoctor before `server`,
  `db:migrate`, `db:prepare`, or `assets:precompile` without creating a second
  execution engine. Hook-specific `fail_on`, `only_checks`, and
  `exclude_checks` are supported in both Ruby config and
  `config/rails_doctor.yml`; migration-style hooks exclude
  `database.migrations.pending` by default, and the asset-build hook excludes
  `assets.production_build_missing`, so valid setup runs do not self-block.
- The repo now includes validated policy-file examples for ingress TLS
  termination, external asset pipelines, and API-only gateway deployments.
  These examples are loaded through the real `config/rails_doctor.yml` path in
  test coverage so the published guidance stays aligned with the executable
  contract.
- The probe helper surface now includes adapter-aware first-party helpers for
  Sidekiq and GoodJob. Sidekiq can reuse `Sidekiq.redis_pool` or
  `Sidekiq.redis`; GoodJob can reuse `GoodJob::BaseRecord.connection_pool` or
  `GoodJob::Job.connection_pool`. Both helpers were verified through the real
  command path, not only through isolated doubles.
- `health.readiness_route_missing` now prefers the real Rails route set over a
  raw `config/routes.rb` grep and follows mounted route sets, which removes a
  production false-positive path for readiness endpoints exposed through
  engines.
- Execution filtering now rejects runs that would select zero checks. This
  closes a subtle false-green path where disjoint `only_checks` policies could
  otherwise produce ambiguous execution.
- Third-party checks now fail fast on unsupported severities during
  registration, which prevents malformed extensions from surfacing later as
  broken `--fail-on` behavior or unstable output contracts.
- Third-party checks now also fail fast on malformed IDs. This protects the
  filtering contract, JSON output, and policy-file references from IDs that do
  not match the documented lowercase dotted form.
- Exception-derived output now has explicit regression coverage proving that
  adapter/client messages and evidence with likely credentials are redacted
  before rendering.
- Contextual render-time redaction now has explicit regression coverage proving
  that Rails `filter_parameters` and app-defined RailsDoctor patterns scrub
  structured evidence and vendor-specific strings without changing check code.
- Unexpected check implementation crashes now become structured failed results,
  which keeps the diagnostic run alive even when a third-party extension is
  buggy.
- Command-level usage and configuration errors now exit with concise stderr
  messages instead of surfacing framework backtraces.
- Installer-level checks now cover Solid Queue database roles, Solid Queue schema
  artifacts, and Active Storage service definitions.
- `rails.session.cookie_flags_weak` now closes the original "cookies/session
  config fraca" gap with explicit evidence for `secure`, `httponly`, `force_ssl`,
  and the exact issues detected. The real-command integration suite proves the
  contract against a temporary Rails app using a weak `config.session_store`
  definition. The built-in now also skips `api_only` apps to avoid flagging
  APIs that do not rely on browser session cookies.
- `database.pool.too_small` now covers the common Rails shapes that matter in
  production: top-level `config/database.yml` pools, nested `primary.pool`,
  single-role multi-database configs, and default Puma thread counts derived
  from the standard `config/puma.rb` template when `RAILS_MAX_THREADS` is not
  set. Failure evidence now reports both values and their sources.
- CI now proves the declared Ruby support more honestly: Ruby `3.2`, `3.3`, and
  `3.4` for the core quality job, plus the Rails matrix on the minimum supported
  Ruby. Local verification now also exists for Ruby `3.3.6`.
- Rails compatibility matrix is no longer declarative only; every supported
  appraisal in the current matrix passed locally.

## Partial Criteria

- Ruby `3.2` is still CI-only evidence from this machine's perspective.

## Failed or Blocked Criteria

No local command failures remain after fixes. CI has been added but not run on GitHub.

## Remaining Risk

The project now proves the real Rails command path and test suite across the
declared Rails matrix, with local evidence on Ruby `3.4.9` and `3.3.6`. The
main remaining risks are deeper field validation against real third-party
adapter/config shapes beyond the current Sidekiq and GoodJob helpers,
especially around richer credentials structures, custom session middleware
conventions beyond `config.session_store`, chat/webhook or non-GitHub
downstream integrations on top of the suppression report export, balancing
false positives versus misses in custom redaction patterns supplied by
applications, the fact that automatic hooks still stop at `server`,
`db:migrate`, `db:prepare`, and `assets:precompile`, and the absence of local
Ruby `3.2` proof on this host.
