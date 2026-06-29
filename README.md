# RailsDoctor

RailsDoctor is an extensible diagnostic framework for Rails applications. It adds
a `bin/rails doctor` command that runs actionable checks against a booted Rails
application and returns human-readable or JSON output.

## Problem It Solves

Rails ships `/up`, which is useful as a boot check but too narrow for deployment
readiness. It does not prove that secrets, SSL, job backends, database pool,
session cookie flags, storage, mailer URLs, logging filters, assets, or
dependency readiness are configured correctly.

RailsDoctor gives Rails projects a central system-check surface similar in intent
to Django's system check framework: Rails itself and third-party gems can register
checks, give evidence, and return concrete fix hints.

## Why I Built It

Production Rails readiness is usually spread across runbooks, deploy scripts,
one-off smoke tests, and tribal knowledge. That makes misconfiguration easy to
miss and hard for gems to participate in. RailsDoctor turns those checks into a
small, executable contract: stable check IDs, structured evidence, explicit
severity, auditable suppressions, and a Rails-native command that CI can run
before deploy.

The engineering case study is documented in
[docs/engineering-case-study.md](docs/engineering-case-study.md).

## Target Users

- Rails application teams preparing production deployments.
- Gem authors that want to expose diagnostics for their integration.
- Platform teams that need a scriptable readiness signal before deploys.

## Main Features

- `bin/rails doctor`
- `bin/rails doctor --environment=production`
- `bin/rails doctor --fail-on warning`
- `bin/rails doctor --format=json`
- `bin/rails doctor --format=github-actions`
- `bin/rails doctor --report=suppressions --format=json`
- `bin/rails doctor --report=suppressions --format=github-actions`
- `bin/rails doctor --only=check.one,check.two`
- `bin/rails doctor --exclude=check.three`
- `bundle exec appraisal rake test`
- DSL for custom checks registered by applications or gems.
- Unexpected exceptions inside checks are converted into structured failed
  results instead of aborting the whole command.
- Built-in checks for secrets, production config, session cookie strength,
  jobs, database pool, migrations, assets, storage, mailer host, log
  filtering, readiness routes including mounted route sets, and configured
  dependency probes.
- The secret check for `secret_key_base` now rejects missing, too-short,
  placeholder, repeated-character, and exact repeated-pattern values instead of
  trusting length alone.

## DSL

```ruby
RailsDoctor.register "database.pool.too_small" do |check|
  check.severity = :high

  check.run do |context|
    db_pool = context.database_pool_size
    puma_threads = context.puma_max_threads
    next if db_pool.nil? || puma_threads.nil?

    if db_pool < puma_threads
      check.fail!(
        "Database pool is smaller than Puma thread count",
        hint: "Set pool >= RAILS_MAX_THREADS for each web process.",
        evidence: {
          database_pool: db_pool,
          database_pool_source: context.database_pool_source,
          puma_threads: puma_threads,
          puma_threads_source: context.puma_max_threads_source
        }
      )
    end
  end
end
```

Supported severities are `low`, `warning`, `medium`, `high`, and `critical`.
Unsupported severities fail fast during check registration instead of breaking a
later doctor run.
Check IDs must use lowercase dot-separated segments with optional underscores,
such as `database.pool.too_small` or `solid_queue.database_role_missing`.

The built-in `database.pool.too_small` check resolves the live Active Record
pool first, then `config/database.yml` (`pool`, `primary.pool`, or the single
defined role), then `RAILS_MAX_DB_POOL` / `DB_POOL`. Puma threads come from
`RAILS_MAX_THREADS` first and then the common Rails `config/puma.rb` template
defaults when the env var is absent.

Third-party gems can expose explicit installers:

```ruby
module SolidLens
  def self.install_rails_doctor_checks
    RailsDoctor.register "solid_lens.configuration.missing" do |check|
      check.severity = :high
      check.run do |context|
        # inspect context.application, context.config, files, env, or loaded gems
      end
    end
  end
end
```

Applications can configure execution policy directly:

```ruby
config.x.rails_doctor.required_env = %w[DATABASE_URL REDIS_URL STRIPE_SECRET_KEY]
config.x.rails_doctor.required_credentials = %w[
  aws.access_key_id
  aws.secret_access_key
]
config.x.rails_doctor.suppress(
  "health.readiness_route_missing",
  because: "Readiness is exposed by another engine in this deployment",
  owner: "platform@example.com",
  expires_on: "2026-12-31"
)
config.x.rails_doctor.before_command(
  "server",
  fail_on: :warning,
  only: %w[
    rails.production.force_ssl_disabled
    rails.secrets.required_environment_missing
  ]
)
config.x.rails_doctor.before_command(
  "db:migrate",
  fail_on: :high,
  exclude: %w[database.pool.too_small]
)
config.x.rails_doctor.before_command(
  "db:prepare",
  fail_on: :high,
  only: %w[
    rails.secrets.required_environment_missing
    rails.secrets.required_credentials_missing
  ]
)
config.x.rails_doctor.before_command(
  "assets:precompile",
  fail_on: :medium,
  only: %w[
    assets.production_build_missing
    rails.secrets.required_credentials_missing
  ]
)
config.x.rails_doctor.only_checks = %w[
  rails.production.force_ssl_disabled
  rails.secrets.required_environment_missing
]
config.x.rails_doctor.redacted_patterns = [
  /acct-live-\d+/,
  "tenant-secret-value"
]
```

`required_env` checks plain environment variables. `required_credentials` checks
dot-separated Rails credentials paths such as `aws.access_key_id`. `only_checks`
narrows execution. `suppress` records an intentional exception with a reason and
keeps that check visible in output as `suppressed` instead of silently hiding
it. Suppressions must also include `owner` and `expires_on`, and expired
suppressions stop suppressing the underlying check while the built-in
`rails_doctor.suppressions.expired` check fails the run. Suppressions that will
expire within 14 days are surfaced by the built-in
`rails_doctor.suppressions.expiring_soon` warning so teams can renew or remove
them before they become stale. `exclude_checks` still exists as a blunt escape
hatch, but `suppressions` are preferred for production policy because they stay
auditable in versioned config and in command output. Teams can also export a
dedicated suppression inventory with
`bin/rails doctor --report=suppressions --format=json`, which returns every
configured suppression with its `active`, `expiring_soon`, or `expired` state.
`before_command` enables opt-in command hooks for `server`, `db:migrate`,
`db:prepare`, `db:schema:load`, `db:structure:load`, and
`assets:precompile`, using the same check registry, runner, and redaction
pipeline as the explicit `bin/rails doctor` command. Each hook can set its own
`fail_on`, `only`, and `exclude` policy. If `fail_on` is omitted it defaults
to `high`. Hooks for `db:migrate`, `db:prepare`, `db:schema:load`, and
`db:structure:load` automatically exclude `database.migrations.pending`,
because pending migrations are expected before a legitimate database bootstrap
or migration run. Hooks for `assets:precompile` automatically exclude
`assets.production_build_missing`, because a missing manifest is expected
immediately before a legitimate asset build run.
CLI `--only` intersects with configured
`only_checks`; CLI `--exclude` is added to configured exclusions.
`redacted_patterns` applies a final output redaction pass for adapter or
vendor-specific strings that are not covered by the built-in heuristics.

Applications can also keep these execution-policy settings in
`config/rails_doctor.yml`:

```yaml
default:
  exclude_checks:
    - mailer.default_url_options_missing
  required_env:
    - DATABASE_URL

production:
  required_credentials:
    - aws.access_key_id
    - aws.secret_access_key
  command_hooks:
    - command: server
      fail_on: warning
      only_checks:
        - rails.production.force_ssl_disabled
        - rails.secrets.required_environment_missing
    - command: db:migrate
      fail_on: high
      exclude_checks:
        - database.pool.too_small
    - command: db:prepare
      fail_on: high
      only_checks:
        - rails.secrets.required_environment_missing
        - rails.secrets.required_credentials_missing
    - command: assets:precompile
      fail_on: medium
      only_checks:
        - assets.production_build_missing
        - rails.secrets.required_credentials_missing
  suppressions:
    - check_id: health.readiness_route_missing
      because: Readiness is exposed by another engine in this deployment
      owner: platform@example.com
      expires_on: 2026-12-31
  only_checks:
    - rails.production.force_ssl_disabled
    - rails.secrets.required_credentials_missing
```

The policy file is environment-scoped, supports `default` plus environment
sections such as `production`, and currently accepts only
`command_hooks`, `exclude_checks`, `only_checks`, `required_env`,
`required_credentials`, `redacted_patterns`, and `suppressions`. Each
suppression must include a stable `check_id`, a non-empty `because`, an
`owner`, and an `expires_on` date in `YYYY-MM-DD` format. Command hooks
currently support `server`, `db:migrate`, `db:prepare`, `db:schema:load`,
`db:structure:load`, and `assets:precompile`, plus `fail_on`, `only_checks`,
and `exclude_checks` per hook. Hook `fail_on` defaults to `high`. Unknown keys
fail the command with a concise error
instead of being ignored. If configured `only_checks` and CLI `--only` resolve
to an empty intersection, the command also fails instead of silently
broadening or emptying the run. Suppressed-only selections now return explicit
`suppressed` results, expired suppressions no longer hide the original check,
near-expiry suppressions emit a built-in warning before the exception goes
stale, `--report=suppressions` exports the full suppression inventory without
running regular checks, migration-style and database-load hooks automatically
exclude `database.migrations.pending`, and `assets:precompile` hooks
automatically exclude `assets.production_build_missing`.
Validated example policies for common deployment shapes live in
[docs/product/policy-examples.md](docs/product/policy-examples.md).
GitHub Actions integration guidance and validated workflow examples live in
[docs/product/ci-integration.md](docs/product/ci-integration.md).

Applications can also register dependency readiness probes that feed the
built-in `readiness.configured_probes_failing` check:

```ruby
config.x.rails_doctor.register_probe(:database, RailsDoctor::Probes.active_record)
config.x.rails_doctor.register_probe(:cache, RailsDoctor::Probes.cache)
config.x.rails_doctor.register_probe(:redis, RailsDoctor::Probes.redis(existing_redis_pool))
config.x.rails_doctor.register_probe(:sidekiq, RailsDoctor::Probes.sidekiq)
config.x.rails_doctor.register_probe(:storage, RailsDoctor::Probes.active_storage)
config.x.rails_doctor.register_probe(:good_job, RailsDoctor::Probes.good_job)
config.x.rails_doctor.register_probe(:queue, RailsDoctor::Probes.solid_queue)
```

Each configured probe runs inside the Rails process and should either return
truthy or raise `RailsDoctor::ProbeFailure` with a concrete `hint` and
structured `evidence`. The built-in Redis probe accepts a client or pool that
responds to `#ping`, `#call("PING")`, or `#with`. The built-in Sidekiq probe
uses `Sidekiq.redis_pool` or `Sidekiq.redis` when available, or an explicit
Sidekiq-compatible target, and verifies Redis round-trip reachability through
the configured Sidekiq connection path. The built-in Active Storage probe uses
the configured `ActiveStorage::Blob.service` when available, or an explicit
service object that responds to `#upload`, `#download`, and `#delete`. The
built-in GoodJob probe uses `GoodJob::BaseRecord.connection_pool` or
`GoodJob::Job.connection_pool` when available, or an explicit connection /
connection pool, and verifies the `good_jobs` table exists before deploy. The
built-in Solid Queue probe uses `SolidQueue::Record.connection_pool` when
available, or an explicit connection / connection pool, and verifies the core
queue tables exist.

## Output

```text
HIGH rails.production.force_ssl_disabled - force_ssl is disabled in production
Hint: Set config.force_ssl = true or document the upstream TLS enforcement check.
Evidence: {:environment=>"production", :force_ssl=>false}

MEDIUM active_job.adapter.async_in_production - Active Job is using a non-durable adapter in production
Hint: Configure Solid Queue, Sidekiq, GoodJob, Delayed Job, or another durable backend.
Evidence: {:queue_adapter=>":async"}
```

JSON output contains one object per result:

```json
[
  {
    "check_id": "database.pool.too_small",
    "severity": "high",
    "status": "failed",
    "message": "Database pool is smaller than Puma thread count",
    "hint": "Set pool >= RAILS_MAX_THREADS for each web process.",
    "evidence": {
      "database_pool": 2,
      "database_pool_source": "ENV[DB_POOL]",
      "puma_threads": 5,
      "puma_threads_source": "ENV[RAILS_MAX_THREADS]"
    }
  },
  {
    "check_id": "rails.production.force_ssl_disabled",
    "severity": "high",
    "status": "suppressed",
    "message": "check suppressed by policy",
    "hint": "HTTPS is enforced by the ingress tier before Rails",
    "evidence": {
      "because": "HTTPS is enforced by the ingress tier before Rails",
      "owner": "platform@example.com",
      "expires_on": "2026-12-31"
    }
  }
]
```

Unexpected exceptions raised by a check are reported as a failed result with the
same `check_id` and severity, plus safe crash evidence such as `error_class`.
Suppressed checks also remain visible in both text and JSON output so deploy
gates and dashboards can distinguish "ignored by policy" from "never selected".
The suppression lifecycle itself is modeled as ordinary built-in checks instead
of a second policy engine, which keeps governance visible in the same reporter
and `--fail-on` contract as the rest of the framework.
Invalid usage such as unknown check IDs, unsupported formats, or unsupported
`--fail-on` severities exits with status `1` and a concise stderr message rather
than a framework backtrace.
Secret-like substrings inside external exception messages and structured
evidence, such as URL credentials, `token=...`, `password=...`, or
`Authorization: Bearer ...`, are redacted before they reach stdout, stderr, or
JSON output. Rails `config.filter_parameters` is also reused as contextual key
redaction for structured evidence at render time.

## Contract And Versioning

RailsDoctor's public contract is larger than one Ruby API. Reviewers and
automation should expect these surfaces to stay intentional:

- stable check IDs such as `database.pool.too_small`;
- the severity and status vocabulary rendered by text, JSON, and GitHub Actions
  output;
- the `bin/rails doctor` and `bin/rails doctor --report=suppressions` command
  surfaces;
- the documented configuration keys under `config.x.rails_doctor` and
  `config/rails_doctor.yml`.

The concrete release policy for those surfaces lives in
[docs/contract-versioning.md](docs/contract-versioning.md). The verification
suite now builds the gem artifact, validates the packaged public docs, and boots
a disposable Rails app that executes `bin/rails doctor` from the built gem so
release readiness is proven from the package, not only from the checkout.

## Architecture Overview

RailsDoctor is intentionally small:

- `RailsDoctor::Registry` owns check registration and duplicate protection.
- `RailsDoctor::Check` owns the DSL and produces `Result` objects.
- `RailsDoctor::Context` exposes application, configuration, files, and env.
- `RailsDoctor::Context` also carries the output redaction policy derived from
  Rails config and RailsDoctor config.
- `RailsDoctor::Probes` provides reusable readiness helpers for first-party or app code.
- `RailsDoctor::ProbeFailure` carries actionable readiness failure details.
- `RailsDoctor::Reporter` renders text or JSON.
- `RailsDoctor::Runner` wires context, registry, reporter, and exit code.
- `rails/commands/doctor/doctor_command.rb` integrates with Rails command lookup.

Built-in checks live under `lib/rails_doctor/checks/` and are grouped by domain
instead of collected in a single checklist file.

## Tech Stack

- Ruby 3.4.9 for local development.
- Runtime dependency: `railties >= 7.1, < 9.0`.
- Declared Ruby support: `>= 3.2`, with CI coverage across Ruby `3.2`, `3.3`, and `3.4`.
- Minitest for fast unit coverage.
- Standard Ruby for formatting and lint.

## Domain Model

The core domain is diagnostic evidence:

- A check has an ID, severity, description, and run block.
- A result is passed or failed.
- A failed result must include a message and hint.
- Evidence is structured data, not prose, so CI and deployment tooling can parse it.

## API Documentation

RailsDoctor has no HTTP API. Its public API is the Ruby registration DSL and the
Rails command interface.

## Async Or Event Architecture

No async runtime is required. Checks run synchronously in the Rails process to
make the command deterministic and easy to use in CI.

## Database Design

RailsDoctor has no database. Database-related checks inspect application config,
environment, and Active Record state when Active Record is loaded.

## Testing Strategy

Unit tests cover the DSL, registry, reporter, runner exit code behavior, and the
highest-risk built-in checks. Rails command integration is covered by a dummy app
that executes the real `bin/rails doctor` command in tests.

Run:

```bash
bundle exec rake verify
bundle exec appraisal install
bundle exec appraisal rake test
```

The generated `gemfiles/*.gemfile` and their lockfiles are part of the
compatibility evidence for the supported Rails matrix.

## How To Evaluate This Repo

```bash
bundle install
bundle exec rake test
bundle exec standardrb
bundle exec appraisal rake test
bundle exec rake build
ruby -e 'require "rubygems/package"; puts Gem::Package.new("pkg/rails_doctor-0.1.0.gem").spec.files'
RUNS=10 ruby bin/benchmark
```

Expected evidence:

- The unit and integration suite passes on the active Ruby.
- Standard Ruby reports no lint offenses.
- Appraisal passes against Rails 7.1, 7.2, 8.0, and 8.1.
- `pkg/rails_doctor-0.1.0.gem` includes `README.md`, `LICENSE.txt`, all runtime
  Ruby files, and `lib/rails/commands/doctor/doctor_command.rb`; it excludes
  tests, lockfiles, generated packages, and CI-only files.
- The benchmark reports warm-run timings for the runner after Rails has booted.

## Performance Benchmarks

The command is designed for deploy/CI use, not per-request execution. Warm-boot
runner timing is recorded in `benchmarks/baseline.md`, and the measurement
method is documented in `docs/benchmarks/methodology.md`.

## Observability

JSON output is the first integration point for CI, deploy systems, and log
aggregation. The framework intentionally returns structured evidence for each
failed check.

## Security Considerations

RailsDoctor checks high-impact deployment misconfigurations but does not replace
Brakeman, dependency scanning, secret scanning, or threat modeling. It should not
print raw secret values; built-in checks report lengths, names, and configuration
states instead, and exception-derived output is sanitized before rendering.

## Trade-Offs And Decisions

- Rails command integration is included immediately because `bin/rails doctor` is
  the product surface.
- Built-in checks are direct Ruby code instead of a rules engine. A rules engine
  would add indirection before the domain needs it.
- Dependency readiness is opt-in through probes so the framework can verify real
  backends without surprising applications with extra IO by default.
- Readiness-route detection now prefers the real Rails route set, including
  mounted route sets, and falls back to `config/routes.rb` text inspection only
  when route objects are unavailable.
- The first Redis probe supports direct clients and pools because that is the
  cleanest explicit reachability check that does not force adapter-specific job
  mutations into the framework yet.
- The first Active Storage probe round-trips a short object and cleans it up
  explicitly, which keeps the contract honest without forcing `activestorage` as
  a runtime dependency of the gem itself.
- The first Solid Queue probe checks the real queue database non-destructively by
  verifying the core queue tables through the queue connection, instead of
  enqueueing synthetic jobs that would mutate operational state.
- Installer-level checks now validate the Solid Queue database role, queue schema
  artifacts, and the configured Active Storage service definition before runtime
  probes even start.
- Unexpected third-party check exceptions are isolated into structured failures
  so one unstable extension does not abort the entire diagnostic run or leak raw
  exception text by default.
- External exception messages and structured evidence now pass through a central
  redaction step before rendering, which reduces accidental leakage from adapter
  or client error strings.
- RailsDoctor also supports explicit `redacted_patterns` so applications can
  scrub vendor-specific strings without patching built-in checks or probes.
- Automatic command hooks are opt-in and reuse the same runner, output, and
  policy model as the explicit command instead of creating a second execution
  engine for `server`, `db:migrate`, `db:prepare`, `db:schema:load`,
  `db:structure:load`, or `assets:precompile`.
- The `db:migrate`, `db:prepare`, `db:schema:load`, and `db:structure:load`
  hooks intentionally exclude
  `database.migrations.pending` by default, because otherwise legitimate
  database setup flows would block on the very condition they are supposed to
  clear.
- The `assets:precompile` hook intentionally excludes
  `assets.production_build_missing` by default, because otherwise a legitimate
  asset build would block on the missing manifest it is supposed to create.
- The MVP favors actionable evidence and hints over exhaustive Rails coverage.
- Suppression is intentionally explicit and narrow: stable check ID, required
  reason, required owner, required expiry, and visible `suppressed` output.
  There is still no broad policy DSL because that would add a second rules
  layer too early.

## How To Run Locally

```bash
bundle install
bundle exec appraisal install
bundle exec rake test
bin/benchmark
bin/compat
```

Inside a Rails application that depends on the gem:

```bash
bin/rails doctor
bin/rails doctor --environment=production --fail-on warning
bin/rails doctor --format=json
bin/rails doctor --format=github-actions
bin/rails doctor --report=suppressions --format=json
bin/rails doctor --report=suppressions --format=github-actions
bin/rails doctor --only=rails.secrets.required_environment_missing
```

## Failure Scenarios

- A check can be too shallow and create false confidence. Mitigation: every
  failure includes evidence and a concrete hint.
- A check can produce false positives for intentionally unusual deployments.
  Mitigation: checks expose stable IDs and can now be suppressed with explicit
  reasons in versioned policy files or Ruby config.
- A third-party gem can register duplicate IDs. Mitigation: registry rejects
  duplicate check IDs.

## Roadmap

- Add extra Ruby-version coverage on top of the Rails matrix.
- Add chat, webhook, or non-GitHub downstream integrations on top of
  suppression reports and upcoming expiry.
- Broaden automatic hook coverage beyond `server`, `db:migrate`, and
  `db:prepare`, and `assets:precompile` only where the signal stays actionable
  and low-noise.
- Extend third-party readiness coverage beyond the current Sidekiq and GoodJob
  helpers only where the adapter contract stays testable and explicit.
- First-party installers for Solid Queue and Active Storage deep checks.
