# frozen_string_literal: true

require "test_helper"

class RailsDoctorIntegrationCommandTest < Minitest::Test
  include TestSupport

  def test_real_rails_command_runs_and_respects_configured_exclusions
    with_integration_app do |root|
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr
      results = JSON.parse(stdout)
      ids = results.map { |result| result.fetch("check_id") }

      assert_includes ids, "rails.secrets.secret_key_base_missing"
      assert_includes ids, "rails.secrets.required_environment_missing"
      assert_includes ids, "rails.production.force_ssl_disabled"
      refute_includes ids, "health.readiness_route_missing"
    end
  end

  def test_real_rails_command_fail_on_warning_returns_non_zero
    with_integration_app do |root|
      _stdout, stderr, status = run_doctor_command(root, "--environment=production", "--fail-on=warning")

      assert_equal 1, status.exitstatus, stderr
    end
  end

  def test_real_rails_command_reports_weak_session_cookie_flags
    with_integration_app(production_config: <<~RUBY) do |root|
      config.session_store :cookie_store,
        key: "_dummy_doctor_app_session",
        secure: false,
        httponly: false,
        same_site: :lax
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=rails.session.cookie_flags_weak"
      )

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "rails.session.cookie_flags_weak" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal ["secure_not_enabled", "httponly_disabled"], result.dig("evidence", "issues")
      assert_equal false, result.dig("evidence", "secure")
      assert_equal false, result.dig("evidence", "httponly")
      assert_equal false, result.dig("evidence", "force_ssl")
    end
  end

  def test_real_rails_command_only_option_limits_execution
    with_integration_app do |root|
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=rails.secrets.required_environment_missing,rails.production.force_ssl_disabled"
      )

      assert status.success?, stderr
      ids = JSON.parse(stdout).map { |result| result.fetch("check_id") }

      assert_equal %w[rails.production.force_ssl_disabled rails.secrets.required_environment_missing], ids.sort
    end
  end

  def test_real_rails_command_does_not_print_secret_key_base_value
    weak_secret = "super-secret-value"

    with_integration_app do |root|
      application_rb = root.join("config/application.rb")
      application_rb.write(
        application_rb.read.sub('config.secret_key_base = "x" * 64', "config.secret_key_base = #{weak_secret.inspect}")
      )

      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr
      refute_includes stdout, weak_secret
      refute_includes stderr, weak_secret

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "rails.secrets.secret_key_base_missing" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal weak_secret.length, result.dig("evidence", "length")
    end
  end

  def test_real_rails_command_flags_repeated_character_secret_key_base
    with_integration_app do |root|
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=rails.secrets.secret_key_base_missing"
      )

      assert status.success?, stderr
      result = JSON.parse(stdout).first

      assert_equal "rails.secrets.secret_key_base_missing", result.fetch("check_id")
      assert_equal "failed", result.fetch("status")
      assert_includes result.dig("evidence", "issues"), "repeated_character"
      assert_includes result.dig("evidence", "issues"), "low_character_variety"
    end
  end

  def test_real_rails_command_does_not_print_present_required_env_values
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.required_env = %w[API_TOKEN OTHER_KEY]
    RUBY
      env = {"API_TOKEN" => "present-secret-token"}
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json", env: env)

      assert status.success?, stderr
      refute_includes stdout, "present-secret-token"
      refute_includes stderr, "present-secret-token"

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "rails.secrets.required_environment_missing" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal ["OTHER_KEY"], result.dig("evidence", "missing")
    end
  end

  def test_real_rails_command_does_not_print_present_required_credentials_values
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.required_credentials = %w[aws.access_key_id aws.secret_access_key]
      config.after_initialize do
        credentials = ActiveSupport::OrderedOptions.new
        aws = ActiveSupport::OrderedOptions.new
        aws.access_key_id = "present-secret-access-key"
        credentials.aws = aws
        Rails.application.define_singleton_method(:credentials) { credentials }
      end
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=rails.secrets.required_credentials_missing"
      )

      assert status.success?, stderr
      refute_includes stdout, "present-secret-access-key"
      refute_includes stderr, "present-secret-access-key"

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "rails.secrets.required_credentials_missing" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal ["aws.secret_access_key"], result.dig("evidence", "missing")
      assert_equal "config.x.rails_doctor.required_credentials", result.dig("evidence", "configured_key")
    end
  end

  def test_real_rails_command_reads_policy_file_defaults_and_environment_rules
    with_integration_app do |root|
      root.join("config/rails_doctor.yml").write(<<~YAML)
        default:
          exclude_checks:
            - rails.production.force_ssl_disabled
          required_credentials:
            - aws.access_key_id
            - aws.secret_access_key
      YAML

      environment_rb = root.join("config/environments/production.rb")
      environment_rb.write(
        environment_rb.read.sub(
          "config.x.rails_doctor.exclude_checks = %w[health.readiness_route_missing]",
          <<~RUBY.strip
            config.x.rails_doctor.exclude_checks = %w[health.readiness_route_missing]
            config.after_initialize do
              credentials = ActiveSupport::OrderedOptions.new
              aws = ActiveSupport::OrderedOptions.new
              aws.access_key_id = "present-secret-access-key"
              credentials.aws = aws
              Rails.application.define_singleton_method(:credentials) { credentials }
            end
          RUBY
        )
      )

      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr

      results = JSON.parse(stdout)
      ids = results.map { |entry| entry.fetch("check_id") }

      refute_includes ids, "rails.production.force_ssl_disabled"

      result = results.find do |entry|
        entry.fetch("check_id") == "rails.secrets.required_credentials_missing" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal ["aws.secret_access_key"], result.dig("evidence", "missing")
      refute_includes stdout, "present-secret-access-key"
    end
  end

  def test_real_rails_command_reads_auditable_suppressions_from_policy_file
    with_integration_app do |root|
      root.join("config/rails_doctor.yml").write(<<~YAML)
        production:
          suppressions:
            - check_id: rails.production.force_ssl_disabled
              because: HTTPS is enforced by the ingress tier before Rails
              owner: platform@example.com
              expires_on: 2099-12-31
      YAML

      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr
      results = JSON.parse(stdout)
      ids = results.map { |entry| entry.fetch("check_id") }

      suppression = results.find do |entry|
        entry.fetch("check_id") == "rails.production.force_ssl_disabled" &&
          entry.fetch("status") == "suppressed"
      end

      refute_nil suppression
      assert_equal "HTTPS is enforced by the ingress tier before Rails", suppression.dig("evidence", "because")
      assert_equal "platform@example.com", suppression.dig("evidence", "owner")
      assert_equal "2099-12-31", suppression.dig("evidence", "expires_on")
      assert_includes ids, "rails.secrets.required_environment_missing"
    end
  end

  def test_real_rails_command_reports_suppressed_only_selection_without_error
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.suppress(
        "rails.production.force_ssl_disabled",
        because: "HTTPS is enforced by the ingress tier before Rails",
        owner: "platform@example.com",
        expires_on: "2099-12-31"
      )
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=rails.production.force_ssl_disabled"
      )

      assert status.success?, stderr
      results = JSON.parse(stdout)

      assert_equal 1, results.length
      assert_equal "rails.production.force_ssl_disabled", results.first.fetch("check_id")
      assert_equal "suppressed", results.first.fetch("status")
      assert_equal "HTTPS is enforced by the ingress tier before Rails", results.first.dig("evidence", "because")
      assert_equal "platform@example.com", results.first.dig("evidence", "owner")
      assert_equal "2099-12-31", results.first.dig("evidence", "expires_on")
    end
  end

  def test_real_rails_command_reports_expired_suppressions_and_runs_original_check
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.suppress(
        "rails.production.force_ssl_disabled",
        because: "HTTPS is enforced by the ingress tier before Rails",
        owner: "platform@example.com",
        expires_on: "2000-01-01"
      )
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=rails_doctor.suppressions.expired,rails.production.force_ssl_disabled"
      )

      assert status.success?, stderr
      results = JSON.parse(stdout)

      expired_policy = results.find do |entry|
        entry.fetch("check_id") == "rails_doctor.suppressions.expired" &&
          entry.fetch("status") == "failed"
      end
      original_check = results.find do |entry|
        entry.fetch("check_id") == "rails.production.force_ssl_disabled" &&
          entry.fetch("status") == "failed"
      end

      refute_nil expired_policy
      refute_nil original_check
      assert_equal "platform@example.com", expired_policy.dig("evidence", "expired", 0, "owner")
      assert_equal "2000-01-01", expired_policy.dig("evidence", "expired", 0, "expires_on")
    end
  end

  def test_real_rails_command_reports_suppressions_expiring_soon
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.suppress(
        "rails.production.force_ssl_disabled",
        because: "HTTPS is enforced by the ingress tier before Rails",
        owner: "platform@example.com",
        expires_on: #{(Date.today + 5).iso8601.inspect}
      )
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=rails_doctor.suppressions.expiring_soon"
      )

      assert status.success?, stderr
      results = JSON.parse(stdout)

      assert_equal 1, results.length
      assert_equal "rails_doctor.suppressions.expiring_soon", results.first.fetch("check_id")
      assert_equal "failed", results.first.fetch("status")
      assert_equal "platform@example.com", results.first.dig("evidence", "expiring_soon", 0, "owner")
      assert_equal 5, results.first.dig("evidence", "expiring_soon", 0, "days_until_expiry")
    end
  end

  def test_real_rails_command_reports_suppression_inventory_as_json
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.suppress(
        "rails.production.force_ssl_disabled",
        because: "HTTPS is enforced by the ingress tier before Rails",
        owner: "platform@example.com",
        expires_on: "2099-12-31"
      )
      config.x.rails_doctor.suppress(
        "assets.production_build_missing",
        because: "Assets are built in a separate pipeline",
        owner: "release@example.com",
        expires_on: #{(Date.today + 5).iso8601.inspect}
      )
      config.x.rails_doctor.suppress(
        "mailer.default_url_options_missing",
        because: "Mailer is disabled for this deployment",
        owner: "app-team@example.com",
        expires_on: "2000-01-01"
      )
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--report=suppressions"
      )

      assert status.success?, stderr

      report = JSON.parse(stdout)
      assert_equal "production", report.fetch("environment")
      assert_equal 14, report.fetch("window_days")
      assert report.fetch("generated_at")

      suppressions = report.fetch("suppressions")
      assert_equal 3, suppressions.length

      expired = suppressions.find { |entry| entry.fetch("check_id") == "mailer.default_url_options_missing" }
      expiring_soon = suppressions.find { |entry| entry.fetch("check_id") == "assets.production_build_missing" }
      active = suppressions.find { |entry| entry.fetch("check_id") == "rails.production.force_ssl_disabled" }

      assert_equal "expired", expired.fetch("status")
      assert_equal "app-team@example.com", expired.fetch("owner")
      assert_operator expired.fetch("days_until_expiry"), :<, 0

      assert_equal "expiring_soon", expiring_soon.fetch("status")
      assert_equal 5, expiring_soon.fetch("days_until_expiry")

      assert_equal "active", active.fetch("status")
      assert_operator active.fetch("days_until_expiry"), :>, 14
    end
  end

  def test_real_rails_command_reports_github_actions_annotations_for_checks
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.suppress(
        "rails.production.force_ssl_disabled",
        because: "HTTPS is enforced by the ingress tier before Rails",
        owner: "platform@example.com",
        expires_on: "2099-12-31"
      )
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=github-actions",
        "--only=rails.production.force_ssl_disabled,rails.secrets.required_environment_missing"
      )

      assert status.success?, stderr
      assert_includes stdout, "::error title=RailsDoctor rails.secrets.required_environment_missing::"
      assert_includes stdout, "::notice title=RailsDoctor rails.production.force_ssl_disabled suppressed::"
    end
  end

  def test_real_rails_command_reports_suppression_inventory_as_github_actions
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.suppress(
        "rails.production.force_ssl_disabled",
        because: "HTTPS is enforced by the ingress tier before Rails",
        owner: "platform@example.com",
        expires_on: "2099-12-31"
      )
      config.x.rails_doctor.suppress(
        "assets.production_build_missing",
        because: "Assets are built in a separate pipeline",
        owner: "release@example.com",
        expires_on: #{(Date.today + 5).iso8601.inspect}
      )
      config.x.rails_doctor.suppress(
        "mailer.default_url_options_missing",
        because: "Mailer is disabled for this deployment",
        owner: "app-team@example.com",
        expires_on: "2000-01-01"
      )
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=github-actions",
        "--report=suppressions"
      )

      assert status.success?, stderr
      assert_includes stdout, "::error title=RailsDoctor suppression mailer.default_url_options_missing expired::"
      assert_includes stdout, "::warning title=RailsDoctor suppression assets.production_build_missing expiring_soon::"
      refute_includes stdout, "rails.production.force_ssl_disabled active"
    end
  end

  def test_real_rails_command_prints_clean_error_for_invalid_policy_file
    with_integration_app do |root|
      root.join("config/rails_doctor.yml").write(<<~YAML)
        production:
          unsupported_key:
            - rails.production.force_ssl_disabled
      YAML

      stdout, stderr, status = run_doctor_command(root, "--environment=production")

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, "RailsDoctor error: config/rails_doctor.yml:production has unknown keys: unsupported_key"
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_rejects_unsafe_yaml_policy_tags
    with_integration_app do |root|
      root.join("config/rails_doctor.yml").write(<<~YAML)
        production: !ruby/object:ERB
          src: unsafe
      YAML

      stdout, stderr, status = run_doctor_command(root, "--environment=production")

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, "RailsDoctor error: config/rails_doctor.yml could not be parsed: Psych::DisallowedClass"
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_prints_clean_error_for_invalid_suppression_policy
    with_integration_app do |root|
      root.join("config/rails_doctor.yml").write(<<~YAML)
        production:
          suppressions:
            - check_id: rails.production.force_ssl_disabled
      YAML

      stdout, stderr, status = run_doctor_command(root, "--environment=production")

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, "RailsDoctor error: config/rails_doctor.yml:production.suppressions[0] must include because"
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_prints_clean_error_for_invalid_suppression_report_options
    with_integration_app do |root|
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--report=suppressions",
        "--only=rails.production.force_ssl_disabled"
      )

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, "RailsDoctor error: --report=suppressions does not support --fail-on, --only, or --exclude"
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_prints_clean_error_for_empty_only_intersection
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.only_checks = %w[rails.secrets.required_environment_missing]
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--only=rails.production.force_ssl_disabled"
      )

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, "RailsDoctor error: no checks selected after applying filters: only=(empty intersection) exclude=health.readiness_route_missing"
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_prints_clean_error_for_invalid_custom_check_severity
    with_integration_app(production_config: <<~RUBY) do |root|
      RailsDoctor.register "custom.invalid_severity" do |check|
        check.severity = :urgent
        check.run {}
      end
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production")

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, "RailsDoctor error: check custom.invalid_severity has unsupported severity :urgent; use low, warning, medium, high, critical"
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_prints_clean_error_for_invalid_custom_check_id
    with_integration_app(production_config: <<~RUBY) do |root|
      RailsDoctor.register "Custom-Invalid" do |check|
        check.run {}
      end
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production")

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, 'RailsDoctor error: check id "Custom-Invalid" is invalid; use lowercase dot-separated segments with optional underscores'
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_reports_crashing_custom_checks_without_aborting
    with_integration_app(production_config: <<~RUBY) do |root|
      RailsDoctor.register "custom.crashing_check" do |check|
        check.severity = :high
        check.run { raise StandardError, "super-secret boom" }
      end
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=custom.crashing_check"
      )

      assert status.success?, stderr
      refute_includes stdout, "super-secret boom"
      refute_includes stderr, "super-secret boom"

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "custom.crashing_check" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal "check execution crashed", result.fetch("message")
      assert_equal "StandardError", result.dig("evidence", "error_class")
    end
  end

  def test_real_rails_command_redacts_probe_exception_secrets
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.register_probe("redis") do |_context|
        raise StandardError, "redis://user:super-secret@cache.local/0 token=abc123 Authorization: Bearer bearer-secret"
      end
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr
      refute_includes stdout, "super-secret"
      refute_includes stdout, "abc123"
      refute_includes stdout, "bearer-secret"
      refute_includes stderr, "super-secret"
      refute_includes stderr, "abc123"
      refute_includes stderr, "bearer-secret"

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "readiness.configured_probes_failing" &&
          entry.fetch("status") == "failed" &&
          entry.dig("evidence", "probe") == "redis"
      end

      refute_nil result
      assert_equal "StandardError", result.dig("evidence", "error_class")
      assert_includes result.dig("evidence", "error_message"), "[REDACTED]"
    end
  end

  def test_real_rails_command_prints_clean_error_for_unknown_check_ids
    with_integration_app do |root|
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--only=missing.check"
      )

      assert_equal 1, status.exitstatus
      assert_equal "", stdout
      assert_includes stderr, "RailsDoctor error: unknown check ids: missing.check"
      refute_includes stderr, "lib/rails_doctor"
    end
  end

  def test_real_rails_command_applies_contextual_redaction_patterns
    with_integration_app(production_config: <<~RUBY) do |root|
      config.filter_parameters += [:client_secret]
      config.x.rails_doctor.redacted_patterns = ["acct-live-123"]

      RailsDoctor.register "custom.contextual_redaction" do |check|
        check.severity = :high
        check.run do
          check.fail!(
            "vendor token acct-live-123 leaked",
            hint: "Rotate client_secret=super-secret",
            evidence: {
              client_secret: "super-secret",
              note: "acct-live-123"
            }
          )
        end
      end
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=custom.contextual_redaction"
      )

      assert status.success?, stderr
      refute_includes stdout, "super-secret"
      refute_includes stdout, "acct-live-123"
      assert_includes stdout, "[REDACTED]"
    end
  end

  def test_real_rails_command_reads_primary_pool_and_puma_template_defaults
    with_integration_app do |root|
      root.join("config/database.yml").write(<<~YAML)
        production:
          primary:
            adapter: sqlite3
            database: db/production.sqlite3
            pool: 3
          queue:
            adapter: sqlite3
            database: db/queue.sqlite3
            pool: 20
      YAML

      root.join("config/puma.rb").write(<<~RUBY)
        max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
        min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
        threads min_threads_count, max_threads_count
      RUBY

      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=database.pool.too_small"
      )

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "database.pool.too_small" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal 3, result.dig("evidence", "database_pool")
      assert_equal "config/database.yml:production.primary.pool", result.dig("evidence", "database_pool_source")
      assert_equal 5, result.dig("evidence", "puma_threads")
      assert_equal "config/puma.rb", result.dig("evidence", "puma_threads_source")
    end
  end

  def test_real_rails_command_reports_configured_dependency_probe_failures
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.register_probe("cache") do |_context|
        raise RailsDoctor::ProbeFailure.new(
          "cache backend is unreachable",
          hint: "Restore cache connectivity before deploy.",
          evidence: {cache_store: "memory_store"}
        )
      end
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "readiness.configured_probes_failing" && entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal "cache", result.dig("evidence", "probe")
      assert_equal "memory_store", result.dig("evidence", "cache_store")
    end
  end

  def test_real_rails_command_reports_redis_probe_failures
    with_integration_app(production_config: <<~RUBY) do |root|
      class FailingRedisProbeClient
        def ping
          raise StandardError, "connection refused"
        end
      end

      config.x.rails_doctor.register_probe(
        "redis",
        RailsDoctor::Probes.redis(FailingRedisProbeClient.new)
      )
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "readiness.configured_probes_failing" &&
          entry.fetch("status") == "failed" &&
          entry.dig("evidence", "probe") == "redis"
      end

      refute_nil result
      assert_equal "StandardError", result.dig("evidence", "error_class")
      assert_equal "connection refused", result.dig("evidence", "error_message")
    end
  end

  def test_real_rails_command_reports_active_storage_probe_failures
    with_integration_app(production_config: <<~RUBY) do |root|
      class FailingStorageProbeService
        def upload(_key, _io, checksum: nil)
          raise StandardError, "bucket unavailable"
        end
      end

      config.x.rails_doctor.register_probe(
        "storage",
        RailsDoctor::Probes.active_storage(FailingStorageProbeService.new)
      )
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "readiness.configured_probes_failing" &&
          entry.fetch("status") == "failed" &&
          entry.dig("evidence", "probe") == "storage"
      end

      refute_nil result
      assert_equal "FailingStorageProbeService", result.dig("evidence", "service_class")
      assert_equal "StandardError", result.dig("evidence", "error_class")
      assert_equal "bucket unavailable", result.dig("evidence", "error_message")
    end
  end

  def test_real_rails_command_reports_solid_queue_probe_failures
    with_integration_app(production_config: <<~RUBY) do |root|
      class IncompleteQueueConnection
        def data_source_exists?(table_name)
          %w[solid_queue_jobs solid_queue_processes].include?(table_name)
        end
      end

      config.x.rails_doctor.register_probe(
        "queue",
        RailsDoctor::Probes.solid_queue(IncompleteQueueConnection.new)
      )
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "readiness.configured_probes_failing" &&
          entry.fetch("status") == "failed" &&
          entry.dig("evidence", "probe") == "queue"
      end

      refute_nil result
      assert_equal "IncompleteQueueConnection", result.dig("evidence", "connection_class")
      assert_equal %w[solid_queue_ready_executions solid_queue_scheduled_executions], result.dig("evidence", "missing_tables")
    end
  end

  def test_real_rails_command_reports_solid_queue_installer_check_failures
    with_integration_app(production_config: <<~RUBY) do |root|
      config.active_job = ActiveSupport::OrderedOptions.new
      config.active_job.queue_adapter = :solid_queue
      config.solid_queue = ActiveSupport::OrderedOptions.new
      config.solid_queue.connects_to = {database: {writing: :queue}}
    RUBY
      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr
      results = JSON.parse(stdout)

      ids = results.select { |entry| entry.fetch("status") == "failed" }.map { |entry| entry.fetch("check_id") }

      assert_includes ids, "solid_queue.database_role_missing"
      assert_includes ids, "solid_queue.schema_artifacts_missing"
    end
  end

  def test_real_rails_command_reports_active_storage_service_definition_failures
    with_integration_app(production_config: <<~RUBY) do |root|
      config.active_storage = ActiveSupport::OrderedOptions.new
      config.active_storage.service = :amazon
    RUBY
      root.join("config/storage.yml").write("local:\n  service: Disk\n")

      stdout, stderr, status = run_doctor_command(root, "--environment=production", "--format=json")

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "active_storage.service_definition_missing" &&
          entry.fetch("status") == "failed"
      end

      refute_nil result
      assert_equal "amazon", result.dig("evidence", "service")
      assert_equal true, result.dig("evidence", "storage_yml_present")
    end
  end

  def test_server_command_hook_blocks_boot_when_threshold_is_met
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.before_command(
        "server",
        fail_on: :high,
        only: %w[rails.production.force_ssl_disabled]
      )
    RUBY
      application_rb = root.join("config/application.rb")
      application_rb.write(
        application_rb.read.sub(
          'require "rails_doctor"',
          <<~RUBY.strip
            require "rails_doctor"
            require "rackup/handler"

            module FakeRailsDoctorServerHandler
              def self.run(*)
              end
            end

            Rackup::Handler.register("webrick", FakeRailsDoctorServerHandler)
          RUBY
        )
      )

      stdout, stderr, status = run_rails_command(root, "server", "-u", "webrick", env: {"RAILS_ENV" => "production"})

      assert_equal 1, status.exitstatus
      assert_includes stderr, "RailsDoctor before server:"
      assert_includes stderr, "rails.production.force_ssl_disabled"
      refute_includes stderr, "lib/rails_doctor"
      refute_includes stdout, "lib/rails_doctor"
    end
  end

  def test_db_migrate_command_hook_blocks_task_execution
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        task migrate: :environment do
          FileUtils.mkdir_p(Rails.root.join("tmp"))
          File.write(Rails.root.join("tmp/db_migrate_ran.txt"), "ran")
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:migrate",
        fail_on: :high,
        only: %w[rails.production.force_ssl_disabled]
      )
    RUBY
      stdout, stderr, status = run_rails_command(root, "db:migrate", env: {"RAILS_ENV" => "production"})

      assert_equal 1, status.exitstatus
      assert_includes stderr, "RailsDoctor before db:migrate:"
      assert_includes stderr, "rails.production.force_ssl_disabled"
      refute root.join("tmp/db_migrate_ran.txt").exist?
      refute_includes stdout, "lib/rails_doctor"
    end
  end

  def test_db_migrate_command_hook_allows_task_with_hook_specific_only_checks
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        task migrate: :environment do
          FileUtils.mkdir_p(Rails.root.join("tmp"))
          File.write(Rails.root.join("tmp/db_migrate_ran.txt"), "ran")
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:migrate",
        fail_on: :high,
        only: %w[rails.secrets.required_environment_missing]
      )
    RUBY
      stdout, stderr, status = run_rails_command(
        root,
        "db:migrate",
        env: {
          "RAILS_ENV" => "production",
          "API_TOKEN" => "present-token"
        }
      )

      assert status.success?, stderr
      refute_includes stdout, "RailsDoctor before db:migrate:"
      refute_includes stderr, "RailsDoctor before db:migrate:"
      assert_equal "ran", root.join("tmp/db_migrate_ran.txt").read
    end
  end

  def test_db_prepare_command_hook_blocks_task_execution
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        task prepare: :environment do
          FileUtils.mkdir_p(Rails.root.join("tmp"))
          File.write(Rails.root.join("tmp/db_prepare_ran.txt"), "ran")
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:prepare",
        fail_on: :high,
        only: %w[rails.production.force_ssl_disabled]
      )
    RUBY
      stdout, stderr, status = run_rails_command(root, "db:prepare", env: {"RAILS_ENV" => "production"})

      assert_equal 1, status.exitstatus
      assert_includes stderr, "RailsDoctor before db:prepare:"
      assert_includes stderr, "rails.production.force_ssl_disabled"
      refute root.join("tmp/db_prepare_ran.txt").exist?
      refute_includes stdout, "lib/rails_doctor"
    end
  end

  def test_db_prepare_command_hook_allows_task_with_hook_specific_only_checks
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        task prepare: :environment do
          FileUtils.mkdir_p(Rails.root.join("tmp"))
          File.write(Rails.root.join("tmp/db_prepare_ran.txt"), "ran")
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:prepare",
        fail_on: :high,
        only: %w[rails.secrets.required_environment_missing]
      )
    RUBY
      stdout, stderr, status = run_rails_command(
        root,
        "db:prepare",
        env: {
          "RAILS_ENV" => "production",
          "API_TOKEN" => "present-token"
        }
      )

      assert status.success?, stderr
      refute_includes stdout, "RailsDoctor before db:prepare:"
      refute_includes stderr, "RailsDoctor before db:prepare:"
      assert_equal "ran", root.join("tmp/db_prepare_ran.txt").read
    end
  end

  def test_real_rails_command_detects_readiness_routes_from_mounted_route_sets
    with_integration_app(production_config: <<~RUBY) do |root|
      config.x.rails_doctor.exclude_checks = []
    RUBY
      application_rb = root.join("config/application.rb")
      application_rb.write(
        application_rb.read.sub(
          'require "rails_doctor"',
          <<~RUBY.strip
            require "rails_doctor"

            ReadyEngine = ActionDispatch::Routing::RouteSet.new
            ReadyEngine.draw do
              get "/ready", to: ->(_env) { [200, {"Content-Type" => "text/plain"}, ["ok"]] }
            end
          RUBY
        )
      )
      root.join("config/routes.rb").write(<<~RUBY)
        Rails.application.routes.draw do
          get "/up", to: ->(_env) { [200, {"Content-Type" => "text/plain"}, ["ok"]] }
          mount ReadyEngine => "/ops"
        end
      RUBY

      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=health.readiness_route_missing"
      )

      assert status.success?, stderr

      results = JSON.parse(stdout)
      assert_equal 1, results.length
      assert_equal "health.readiness_route_missing", results.first.fetch("check_id")
      assert_equal "passed", results.first.fetch("status")
    end
  end
end
