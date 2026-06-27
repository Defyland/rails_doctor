# frozen_string_literal: true

require "test_helper"

class RailsDoctorSuppressionReporterTest < Minitest::Test
  def test_text_reporter_prints_empty_state_for_missing_suppressions
    report = RailsDoctor::SuppressionReport.build([], environment: "production", today: Date.new(2026, 6, 13))

    output = RailsDoctor::SuppressionReporter.new(report).render(format: "text")

    assert_equal "RailsDoctor: no suppressions configured\n", output
  end

  def test_github_actions_reporter_maps_statuses_to_annotations
    report = RailsDoctor::SuppressionReport.build(
      [
        {
          check_id: "rails.production.force_ssl_disabled",
          because: "HTTPS is enforced before Rails",
          owner: "platform@example.com",
          expires_on: "2099-12-31"
        },
        {
          check_id: "assets.production_build_missing",
          because: "Assets are built in a separate pipeline",
          owner: "release@example.com",
          expires_on: "2026-06-18"
        },
        {
          check_id: "mailer.default_url_options_missing",
          because: "Mailer is disabled for this deployment",
          owner: "app-team@example.com",
          expires_on: "2026-06-01"
        }
      ],
      environment: "production",
      today: Date.new(2026, 6, 13)
    )

    output = RailsDoctor::SuppressionReporter.new(report).render(format: "github-actions")

    assert_includes output, "::error title=RailsDoctor suppression mailer.default_url_options_missing expired::Mailer is disabled for this deployment"
    assert_includes output, "::warning title=RailsDoctor suppression assets.production_build_missing expiring_soon::Assets are built in a separate pipeline"
    refute_includes output, "rails.production.force_ssl_disabled active"
  end
end
