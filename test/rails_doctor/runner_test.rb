# frozen_string_literal: true

require "test_helper"

class RailsDoctorRunnerTest < Minitest::Test
  include TestSupport

  def test_runner_returns_non_zero_when_fail_on_threshold_matches
    registry = RailsDoctor::Registry.new
    registry.register("high.failure") do |check|
      check.severity = :high
      check.run { check.fail!("bad", hint: "fix") }
    end

    with_tmp_app do |application|
      exit_code, = RailsDoctor::Runner.new(registry: registry).call(
        application: application,
        format: "text",
        fail_on: "warning"
      )

      assert_equal 1, exit_code
    end
  end

  def test_runner_keeps_zero_when_failures_are_below_threshold
    registry = RailsDoctor::Registry.new
    registry.register("low.failure") do |check|
      check.severity = :low
      check.run { check.fail!("minor", hint: "fix") }
    end

    with_tmp_app do |application|
      exit_code, = RailsDoctor::Runner.new(registry: registry).call(
        application: application,
        format: "text",
        fail_on: "medium"
      )

      assert_equal 0, exit_code
    end
  end

  def test_runner_applies_rails_doctor_configuration_filters
    registry = RailsDoctor::Registry.new
    registry.register("included") do |check|
      check.severity = :high
      check.run { check.fail!("included", hint: "fix") }
    end
    registry.register("excluded") do |check|
      check.severity = :high
      check.run { check.fail!("excluded", hint: "fix") }
    end

    config = fake_config
    config.rails_doctor.only_checks = ["included", "excluded"]
    config.rails_doctor.exclude_checks = ["excluded"]

    with_tmp_app(config: config) do |application|
      _exit_code, output = RailsDoctor::Runner.new(registry: registry).call(
        application: application,
        format: "text"
      )

      assert_includes output, "included"
      refute_includes output, "excluded"
    end
  end

  def test_runner_applies_auditable_suppressions
    registry = RailsDoctor::Registry.new
    registry.register("suppressed") do |check|
      check.severity = :high
      check.run { check.fail!("suppressed", hint: "fix") }
    end
    registry.register("kept") do |check|
      check.severity = :high
      check.run { check.fail!("kept", hint: "fix") }
    end

    config = fake_config
    config.rails_doctor.suppress(
      "suppressed",
      because: "covered by an upstream control",
      owner: "platform@example.com",
      expires_on: "2099-12-31"
    )

    with_tmp_app(config: config) do |application|
      _exit_code, output = RailsDoctor::Runner.new(registry: registry).call(
        application: application,
        format: "text"
      )

      assert_includes output, "kept"
      assert_includes output, "SUPPRESSED suppressed"
      assert_includes output, "platform@example.com"
    end
  end

  def test_runner_can_render_suppression_inventory_as_json
    registry = RailsDoctor::Registry.new
    registry.register("should.not.run") do |check|
      check.severity = :high
      check.run { flunk("suppression inventory should not execute regular checks") }
    end

    config = fake_config
    config.rails_doctor.suppress(
      "rails.production.force_ssl_disabled",
      because: "HTTPS is enforced by the ingress tier before Rails",
      owner: "platform@example.com",
      expires_on: "2099-12-31"
    )

    with_tmp_app(config: config) do |application|
      exit_code, output = RailsDoctor::Runner.new(registry: registry).call(
        application: application,
        format: "json",
        report: "suppressions"
      )

      assert_equal 0, exit_code

      report = JSON.parse(output)
      assert_equal "development", report.fetch("environment")
      assert_equal 14, report.fetch("window_days")
      assert_equal 1, report.fetch("suppressions").length
      assert_equal "rails.production.force_ssl_disabled", report.dig("suppressions", 0, "check_id")
      assert_equal "active", report.dig("suppressions", 0, "status")
    end
  end

  def test_runner_rejects_execution_filters_for_suppression_inventory
    with_tmp_app do |application|
      error = assert_raises(RailsDoctor::Error) do
        RailsDoctor::Runner.new.call(
          application: application,
          format: "json",
          report: "suppressions",
          fail_on: "warning"
        )
      end

      assert_equal "--report=suppressions does not support --fail-on, --only, or --exclude", error.message
    end
  end

  def test_runner_rejects_unknown_format
    with_tmp_app do |application|
      error = assert_raises(RailsDoctor::Error) do
        RailsDoctor::Runner.new.call(application: application, format: "yaml")
      end

      assert_match(/unsupported format/, error.message)
    end
  end

  def test_runner_rejects_unknown_fail_on_severity
    with_tmp_app do |application|
      error = assert_raises(RailsDoctor::Error) do
        RailsDoctor::Runner.new.call(application: application, fail_on: "fatal")
      end

      assert_match(/unknown fail-on severity/, error.message)
    end
  end

  def test_runner_applies_contextual_redaction_from_filter_parameters_and_config
    registry = RailsDoctor::Registry.new
    registry.register("custom.failure") do |check|
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

    config = fake_config
    config.filter_parameters += [:client_secret]
    config.rails_doctor.redacted_patterns = ["acct-live-123"]

    with_tmp_app(config: config) do |application|
      _exit_code, output = RailsDoctor::Runner.new(registry: registry).call(
        application: application,
        format: "json"
      )

      refute_includes output, "super-secret"
      refute_includes output, "acct-live-123"
      assert_includes output, "[REDACTED]"
    end
  end
end
