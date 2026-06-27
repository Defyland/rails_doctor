# frozen_string_literal: true

require "test_helper"

class RailsDoctorReporterTest < Minitest::Test
  def test_text_reporter_prints_failures_only
    results = [
      RailsDoctor::Result.passed(check_id: "ok", severity: :low),
      RailsDoctor::Result.new(
        check_id: "database.pool.too_small",
        severity: :high,
        status: :failed,
        message: "Database pool is smaller than Puma thread count",
        hint: "Set pool >= RAILS_MAX_THREADS",
        evidence: {database_pool: 2, puma_threads: 5}
      )
    ]

    output = RailsDoctor::Reporter.new(results).render(format: "text")

    assert_includes output, "HIGH database.pool.too_small"
    refute_includes output, "ok"
  end

  def test_json_reporter_includes_structured_results
    results = [RailsDoctor::Result.passed(check_id: "ok", severity: :low)]

    output = RailsDoctor::Reporter.new(results).render(format: "json")

    assert_includes output, "\"check_id\": \"ok\""
    assert_includes output, "\"status\": \"passed\""
  end

  def test_text_reporter_prints_suppressions
    results = [
      RailsDoctor::Result.suppressed(
        check_id: "rails.production.force_ssl_disabled",
        severity: :high,
        because: "HTTPS is enforced before Rails",
        owner: "platform@example.com",
        expires_on: "2099-12-31"
      )
    ]

    output = RailsDoctor::Reporter.new(results).render(format: "text")

    assert_includes output, "SUPPRESSED rails.production.force_ssl_disabled"
    assert_includes output, "Hint: HTTPS is enforced before Rails"
    assert_includes output, "platform@example.com"
  end

  def test_text_reporter_can_suppress_empty_state_banner
    results = [RailsDoctor::Result.passed(check_id: "ok", severity: :low)]

    output = RailsDoctor::Reporter.new(results, render_empty_state: false).render(format: "text")

    assert_equal "", output
  end

  def test_reporter_applies_contextual_redaction_patterns
    results = [
      RailsDoctor::Result.new(
        check_id: "custom.failure",
        severity: :high,
        status: :failed,
        message: "vendor token acct-live-123 leaked",
        hint: "Rotate client_secret=super-secret",
        evidence: {
          client_secret: "super-secret",
          note: "acct-live-123"
        }
      )
    ]

    output = RailsDoctor::Reporter.new(
      results,
      redaction_key_patterns: ["client_secret"],
      redaction_value_patterns: ["acct-live-123"]
    ).render(format: "json")

    refute_includes output, "super-secret"
    refute_includes output, "acct-live-123"
    assert_includes output, "[REDACTED]"
  end

  def test_github_actions_reporter_maps_failed_and_suppressed_results_to_annotations
    results = [
      RailsDoctor::Result.new(
        check_id: "database.pool.too_small",
        severity: :high,
        status: :failed,
        message: "Database pool is smaller than Puma thread count",
        hint: "Set pool >= RAILS_MAX_THREADS",
        evidence: {database_pool: 2, puma_threads: 5}
      ),
      RailsDoctor::Result.suppressed(
        check_id: "rails.production.force_ssl_disabled",
        severity: :high,
        because: "HTTPS is enforced before Rails",
        owner: "platform@example.com",
        expires_on: "2099-12-31"
      )
    ]

    output = RailsDoctor::Reporter.new(results).render(format: "github-actions")

    assert_includes output, "::error title=RailsDoctor database.pool.too_small::Database pool is smaller than Puma thread count%0AHint: Set pool >= RAILS_MAX_THREADS"
    assert_includes output, "::notice title=RailsDoctor rails.production.force_ssl_disabled suppressed::check suppressed by policy%0AHint: HTTPS is enforced before Rails"
  end
end
