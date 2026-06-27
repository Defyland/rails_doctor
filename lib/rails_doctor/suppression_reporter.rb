# frozen_string_literal: true

require "json"

module RailsDoctor
  class SuppressionReporter
    def initialize(report, redaction_key_patterns: [], redaction_value_patterns: [])
      @report = report
      @redaction_key_patterns = redaction_key_patterns
      @redaction_value_patterns = redaction_value_patterns
    end

    def render(format:)
      case format.to_s
      when "text"
        render_text
      when "json"
        JSON.pretty_generate(rendered_report)
      when "github-actions"
        render_github_actions
      else
        raise Error, "unknown format #{format.inspect}"
      end
    end

    private

    def render_github_actions
      rendered_report
        .fetch(:suppressions)
        .filter_map do |suppression|
          render_github_actions_suppression(suppression)
        end
        .join("\n")
    end

    def render_text
      suppressions = rendered_report.fetch(:suppressions)
      return "RailsDoctor: no suppressions configured\n" if suppressions.empty?

      suppressions.map { |suppression| render_text_suppression(suppression) }.join("\n\n") + "\n"
    end

    def render_text_suppression(suppression)
      line = "#{suppression.fetch(:status).to_s.upcase} #{suppression.fetch(:check_id)} - #{suppression.fetch(:because)}"
      [
        line,
        detail("Owner", suppression[:owner]),
        detail("Expires On", suppression[:expires_on]),
        detail("Days Until Expiry", suppression[:days_until_expiry])
      ].compact.join("\n")
    end

    def render_github_actions_suppression(suppression)
      return unless actionable_status?(suppression.fetch(:status))

      GitHubActions.command(
        level: github_actions_level_for_status(suppression.fetch(:status)),
        title: "RailsDoctor suppression #{suppression.fetch(:check_id)} #{suppression.fetch(:status)}",
        message: [
          suppression.fetch(:because),
          detail("Owner", suppression[:owner]),
          detail("Expires On", suppression[:expires_on]),
          detail("Days Until Expiry", suppression[:days_until_expiry])
        ].compact.join("\n")
      )
    end

    def actionable_status?(status)
      %i[expired expiring_soon].include?(status)
    end

    def github_actions_level_for_status(status)
      case status
      when :expired
        "error"
      when :expiring_soon
        "warning"
      end
    end

    def detail(label, value)
      return if value.nil? || value == {} || value == []

      "#{label}: #{value}"
    end

    def rendered_report
      @rendered_report ||= Redaction.sanitize_object(
        @report.to_h,
        key_patterns: @redaction_key_patterns,
        value_patterns: @redaction_value_patterns
      )
    end
  end
end
