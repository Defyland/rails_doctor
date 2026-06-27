# frozen_string_literal: true

module RailsDoctor
  class Runner
    VALID_FORMATS = %w[text json github-actions].freeze
    VALID_REPORTS = %w[checks suppressions].freeze

    def initialize(registry: RailsDoctor.registry)
      @registry = registry
    end

    def call(
      application:,
      environment: nil,
      format: "text",
      fail_on: nil,
      only: nil,
      exclude: nil,
      render_empty_state: true,
      report: "checks"
    )
      raise Error, "unsupported format #{format.inspect}" unless VALID_FORMATS.include?(format.to_s)
      raise Error, "unsupported report #{report.inspect}" unless VALID_REPORTS.include?(report.to_s)

      context = Context.new(application: application, environment: environment)
      return suppression_report(context, format: format, fail_on: fail_on, only: only, exclude: exclude) if report.to_s == "suppressions"

      filters = context.rails_doctor_config.filters(only: only, exclude: exclude)
      results = @registry.run(context, **filters)
      output = Reporter.new(
        results,
        redaction_key_patterns: context.redaction_key_patterns,
        redaction_value_patterns: context.redaction_value_patterns,
        render_empty_state: render_empty_state
      ).render(format: format)
      [exit_code(results, fail_on), output]
    end

    private

    def suppression_report(context, format:, fail_on:, only:, exclude:)
      validate_suppression_report_options!(fail_on: fail_on, only: only, exclude: exclude)

      report = SuppressionReport.build(
        context.rails_doctor_config.suppressions,
        environment: context.environment
      )
      output = SuppressionReporter.new(
        report,
        redaction_key_patterns: context.redaction_key_patterns,
        redaction_value_patterns: context.redaction_value_patterns
      ).render(format: format)

      [0, output]
    end

    def exit_code(results, fail_on)
      threshold = severity_rank(fail_on)
      return 0 unless threshold

      (results.any? { |result| result.failure? && result.severity_rank >= threshold }) ? 1 : 0
    end

    def validate_suppression_report_options!(fail_on:, only:, exclude:)
      return unless option_present?(fail_on) || option_present?(only) || option_present?(exclude)

      raise Error, "--report=suppressions does not support --fail-on, --only, or --exclude"
    end

    def option_present?(value)
      !(value.nil? || (value.respond_to?(:empty?) && value.empty?))
    end

    def severity_rank(value)
      return nil if value.nil?

      Result::SEVERITY_RANK.fetch(value.to_sym)
    rescue KeyError
      raise Error, "unknown fail-on severity #{value.inspect}"
    end
  end
end
