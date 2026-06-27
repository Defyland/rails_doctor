# frozen_string_literal: true

require "test_helper"

class RailsDoctorConfigurationTest < Minitest::Test
  def test_filters_intersect_only_and_union_exclude
    configuration = RailsDoctor::Configuration.new
    configuration.only_checks = "a,b"
    configuration.exclude_checks = "c"

    filters = configuration.filters(only: "b,d", exclude: "e,c")

    assert_equal ["b"], filters[:only]
    assert_equal %w[c e], filters[:exclude]
  end

  def test_filters_preserve_empty_only_intersection
    configuration = RailsDoctor::Configuration.new
    configuration.only_checks = "a"

    filters = configuration.filters(only: "b")

    assert_equal [], filters[:only]
  end

  def test_filters_preserve_auditable_suppressions_as_structured_policy
    configuration = RailsDoctor::Configuration.new
    configuration.suppress(
      "a",
      because: "handled by upstream TLS",
      owner: "platform@example.com",
      expires_on: "2099-12-31"
    )

    filters = configuration.filters(exclude: "b")

    assert_equal %w[b], filters[:exclude]
    assert_equal(
      [
        RailsDoctor::Suppression.new(
          check_id: "a",
          because: "handled by upstream TLS",
          owner: "platform@example.com",
          expires_on: "2099-12-31"
        )
      ],
      filters[:suppressions]
    )
  end

  def test_before_command_registers_structured_command_hook
    configuration = RailsDoctor::Configuration.new

    configuration.before_command(
      "db:migrate",
      fail_on: :warning,
      only: %w[rails.secrets.required_environment_missing],
      exclude: %w[database.pool.too_small]
    )

    assert_equal(
      [
        RailsDoctor::CommandHook.new(
          command: "db:migrate",
          fail_on: "warning",
          only_checks: %w[rails.secrets.required_environment_missing],
          exclude_checks: %w[database.pool.too_small]
        )
      ],
      configuration.command_hooks
    )
  end

  def test_before_command_registers_structured_db_prepare_command_hook
    configuration = RailsDoctor::Configuration.new

    configuration.before_command(
      "db:prepare",
      fail_on: :high,
      only: %w[rails.production.force_ssl_disabled],
      exclude: %w[database.pool.too_small]
    )

    assert_equal(
      [
        RailsDoctor::CommandHook.new(
          command: "db:prepare",
          fail_on: "high",
          only_checks: %w[rails.production.force_ssl_disabled],
          exclude_checks: %w[database.pool.too_small]
        )
      ],
      configuration.command_hooks
    )
  end

  def test_before_command_registers_structured_assets_precompile_command_hook
    configuration = RailsDoctor::Configuration.new

    configuration.before_command(
      "assets:precompile",
      fail_on: :medium,
      only: %w[rails.production.force_ssl_disabled],
      exclude: %w[database.pool.too_small]
    )

    assert_equal(
      [
        RailsDoctor::CommandHook.new(
          command: "assets:precompile",
          fail_on: "medium",
          only_checks: %w[rails.production.force_ssl_disabled],
          exclude_checks: %w[database.pool.too_small]
        )
      ],
      configuration.command_hooks
    )
  end

  def test_before_command_registers_structured_db_schema_load_command_hook
    configuration = RailsDoctor::Configuration.new

    configuration.before_command(
      "db:schema:load",
      fail_on: :high,
      only: %w[rails.production.force_ssl_disabled],
      exclude: %w[database.pool.too_small]
    )

    assert_equal(
      [
        RailsDoctor::CommandHook.new(
          command: "db:schema:load",
          fail_on: "high",
          only_checks: %w[rails.production.force_ssl_disabled],
          exclude_checks: %w[database.pool.too_small]
        )
      ],
      configuration.command_hooks
    )
  end

  def test_before_command_registers_structured_db_structure_load_command_hook
    configuration = RailsDoctor::Configuration.new

    configuration.before_command(
      "db:structure:load",
      fail_on: :high,
      only: %w[rails.production.force_ssl_disabled],
      exclude: %w[database.pool.too_small]
    )

    assert_equal(
      [
        RailsDoctor::CommandHook.new(
          command: "db:structure:load",
          fail_on: "high",
          only_checks: %w[rails.production.force_ssl_disabled],
          exclude_checks: %w[database.pool.too_small]
        )
      ],
      configuration.command_hooks
    )
  end

  def test_required_env_normalizes_strings_and_arrays
    configuration = RailsDoctor::Configuration.new
    configuration.required_env = ["API_TOKEN, OTHER_KEY", "THIRD_KEY"]

    assert_equal %w[API_TOKEN OTHER_KEY THIRD_KEY], configuration.required_env
  end

  def test_required_credentials_normalizes_strings_and_arrays
    configuration = RailsDoctor::Configuration.new
    configuration.required_credentials = ["aws.access_key_id, aws.secret_access_key", "redis.url"]

    assert_equal %w[aws.access_key_id aws.secret_access_key redis.url], configuration.required_credentials
  end

  def test_merge_unions_lists_and_intersects_only_checks
    left = RailsDoctor::Configuration.from_hash(
      {
        "command_hooks" => [
          {
            "command" => "server",
            "fail_on" => "high"
          }
        ],
        "exclude_checks" => %w[a b],
        "only_checks" => %w[x y],
        "redacted_patterns" => ["acct-live-123"],
        "required_credentials" => %w[aws.access_key_id],
        "required_env" => %w[DATABASE_URL],
        "suppressions" => [
          {
            "check_id" => "rails.production.force_ssl_disabled",
            "because" => "ALB terminates TLS",
            "owner" => "platform@example.com",
            "expires_on" => "2099-12-31"
          }
        ]
      }
    )
    right = RailsDoctor::Configuration.from_hash(
      {
        "command_hooks" => [
          {
            "command" => "server",
            "fail_on" => "warning",
            "only_checks" => ["rails.production.force_ssl_disabled"]
          },
          {
            "command" => "db:migrate",
            "fail_on" => "high",
            "exclude_checks" => ["database.pool.too_small"]
          }
        ],
        "exclude_checks" => %w[b c],
        "only_checks" => %w[y z],
        "redacted_patterns" => ["tenant-secret-value"],
        "required_credentials" => %w[aws.secret_access_key],
        "required_env" => %w[REDIS_URL],
        "suppressions" => [
          {
            "check_id" => "rails.production.force_ssl_disabled",
            "because" => "Ingress enforces HTTPS",
            "owner" => "platform@example.com",
            "expires_on" => "2100-01-31"
          },
          {
            "check_id" => "health.readiness_route_missing",
            "because" => "Health endpoints live in another engine",
            "owner" => "app-team@example.com",
            "expires_on" => "2099-11-30"
          }
        ]
      }
    )

    merged = left.merge(right)

    assert_equal %w[a b c], merged.exclude_checks
    assert_equal %w[y], merged.only_checks
    assert_equal(
      [
        RailsDoctor::CommandHook.new(
          command: "server",
          fail_on: "warning",
          only_checks: ["rails.production.force_ssl_disabled"],
          exclude_checks: []
        ),
        RailsDoctor::CommandHook.new(
          command: "db:migrate",
          fail_on: "high",
          only_checks: [],
          exclude_checks: ["database.pool.too_small"]
        )
      ],
      merged.command_hooks
    )
    assert_equal ["acct-live-123", "tenant-secret-value"], merged.redacted_patterns
    assert_equal %w[aws.access_key_id aws.secret_access_key], merged.required_credentials
    assert_equal %w[DATABASE_URL REDIS_URL], merged.required_env
    assert_equal(
      [
        RailsDoctor::Suppression.new(
          check_id: "rails.production.force_ssl_disabled",
          because: "Ingress enforces HTTPS",
          owner: "platform@example.com",
          expires_on: "2100-01-31"
        ),
        RailsDoctor::Suppression.new(
          check_id: "health.readiness_route_missing",
          because: "Health endpoints live in another engine",
          owner: "app-team@example.com",
          expires_on: "2099-11-30"
        )
      ],
      merged.suppressions
    )
  end

  def test_from_hash_rejects_unknown_keys
    error = assert_raises(RailsDoctor::Error) do
      RailsDoctor::Configuration.from_hash({"unsupported_key" => ["value"]}, source_label: "config/rails_doctor.yml:production")
    end

    assert_equal "config/rails_doctor.yml:production has unknown keys: unsupported_key", error.message
  end

  def test_from_hash_normalizes_command_hooks
    configuration = RailsDoctor::Configuration.from_hash(
      {
        "command_hooks" => [
          {
            "command" => "server",
            "fail_on" => "warning",
            "only_checks" => ["rails.production.force_ssl_disabled, rails.secrets.required_environment_missing"],
            "exclude_checks" => ["database.pool.too_small"]
          },
          {
            "command" => "db:prepare",
            "fail_on" => "high",
            "only_checks" => ["health.readiness_route_missing"]
          },
          {
            "command" => "db:schema:load",
            "fail_on" => "high",
            "exclude_checks" => ["database.pool.too_small"]
          },
          {
            "command" => "assets:precompile",
            "fail_on" => "medium",
            "exclude_checks" => ["database.pool.too_small"]
          }
        ]
      }
    )

    assert_equal(
      [
        RailsDoctor::CommandHook.new(
          command: "server",
          fail_on: "warning",
          only_checks: %w[rails.production.force_ssl_disabled rails.secrets.required_environment_missing],
          exclude_checks: %w[database.pool.too_small]
        ),
        RailsDoctor::CommandHook.new(
          command: "db:prepare",
          fail_on: "high",
          only_checks: %w[health.readiness_route_missing],
          exclude_checks: []
        ),
        RailsDoctor::CommandHook.new(
          command: "db:schema:load",
          fail_on: "high",
          only_checks: [],
          exclude_checks: ["database.pool.too_small"]
        ),
        RailsDoctor::CommandHook.new(
          command: "assets:precompile",
          fail_on: "medium",
          only_checks: [],
          exclude_checks: ["database.pool.too_small"]
        )
      ],
      configuration.command_hooks
    )
  end

  def test_from_hash_rejects_suppressions_without_reason
    error = assert_raises(RailsDoctor::Error) do
      RailsDoctor::Configuration.from_hash(
        {
          "suppressions" => [
            {"check_id" => "rails.production.force_ssl_disabled"}
          ]
        },
        source_label: "config/rails_doctor.yml:production"
      )
    end

    assert_equal "config/rails_doctor.yml:production.suppressions[0] must include because", error.message
  end

  def test_from_hash_rejects_suppressions_without_owner
    error = assert_raises(RailsDoctor::Error) do
      RailsDoctor::Configuration.from_hash(
        {
          "suppressions" => [
            {
              "check_id" => "rails.production.force_ssl_disabled",
              "because" => "Ingress enforces HTTPS",
              "expires_on" => "2099-12-31"
            }
          ]
        },
        source_label: "config/rails_doctor.yml:production"
      )
    end

    assert_equal "config/rails_doctor.yml:production.suppressions[0] must include owner", error.message
  end

  def test_from_hash_rejects_suppressions_with_invalid_expiration
    error = assert_raises(RailsDoctor::Error) do
      RailsDoctor::Configuration.from_hash(
        {
          "suppressions" => [
            {
              "check_id" => "rails.production.force_ssl_disabled",
              "because" => "Ingress enforces HTTPS",
              "owner" => "platform@example.com",
              "expires_on" => "31-12-2099"
            }
          ]
        },
        source_label: "config/rails_doctor.yml:production"
      )
    end

    assert_equal "config/rails_doctor.yml:production.suppressions[0] expires_on must use YYYY-MM-DD", error.message
  end

  def test_from_hash_rejects_command_hooks_with_unsupported_command
    error = assert_raises(RailsDoctor::Error) do
      RailsDoctor::Configuration.from_hash(
        {
          "command_hooks" => [
            {
              "command" => "console",
              "fail_on" => "warning"
            }
          ]
        },
        source_label: "config/rails_doctor.yml:production"
      )
    end

    assert_equal 'config/rails_doctor.yml:production.command_hooks[0] command "console" is unsupported; use server, db:migrate, db:prepare, db:schema:load, db:structure:load, assets:precompile', error.message
  end

  def test_from_hash_rejects_command_hooks_with_unsupported_fail_on
    error = assert_raises(RailsDoctor::Error) do
      RailsDoctor::Configuration.from_hash(
        {
          "command_hooks" => [
            {
              "command" => "server",
              "fail_on" => "fatal"
            }
          ]
        },
        source_label: "config/rails_doctor.yml:production"
      )
    end

    assert_equal 'config/rails_doctor.yml:production.command_hooks[0] fail_on "fatal" is unsupported; use low, warning, medium, high, critical', error.message
  end

  def test_register_probe_normalizes_names
    configuration = RailsDoctor::Configuration.new
    probe = ->(_context) { true }

    configuration.register_probe(:cache, probe)

    assert_equal({"cache" => probe}, configuration.dependency_probes)
  end

  def test_redacted_patterns_preserve_regex_and_trim_strings
    configuration = RailsDoctor::Configuration.new
    configuration.redacted_patterns = [" acct-live-123 ", /secret-\d+/]

    assert_equal ["acct-live-123", /secret-\d+/], configuration.redacted_patterns
  end

  def test_suppress_dsl_registers_structured_suppression
    configuration = RailsDoctor::Configuration.new

    configuration.suppress(
      "rails.production.force_ssl_disabled",
      because: "TLS is enforced before Rails",
      owner: "platform@example.com",
      expires_on: "2099-12-31"
    )

    assert_equal(
      [
        RailsDoctor::Suppression.new(
          check_id: "rails.production.force_ssl_disabled",
          because: "TLS is enforced before Rails",
          owner: "platform@example.com",
          expires_on: "2099-12-31"
        )
      ],
      configuration.suppressions
    )
  end

  def test_suppression_helper_reports_days_until_expiry
    suppression = RailsDoctor::Suppression.new(
      check_id: "rails.production.force_ssl_disabled",
      because: "TLS is enforced before Rails",
      owner: "platform@example.com",
      expires_on: "2099-12-31"
    )

    assert_equal 5, suppression.days_until_expiry(today: Date.iso8601("2099-12-26"))
    assert suppression.expiring_within?(7, today: Date.iso8601("2099-12-26"))
    refute suppression.expiring_within?(3, today: Date.iso8601("2099-12-26"))
  end
end
