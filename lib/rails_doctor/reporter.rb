# frozen_string_literal: true

require "json"

module RailsDoctor
  class Reporter
    def initialize(results, redaction_key_patterns: [], redaction_value_patterns: [], render_empty_state: true)
      @results = results
      @redaction_key_patterns = redaction_key_patterns
      @redaction_value_patterns = redaction_value_patterns
      @render_empty_state = render_empty_state
    end

    def render(format:)
      case format.to_s
      when "text"
        render_text
      when "json"
        JSON.pretty_generate(rendered_results)
      when "github-actions"
        render_github_actions
      else
        raise Error, "unknown format #{format.inspect}"
      end
    end

    private

    def render_github_actions
      rendered_results
        .filter_map { |result| render_github_actions_result(result) }
        .join("\n")
    end

    def render_text
      failures = rendered_results.select { |result| result[:status] == :failed }
      suppressions = rendered_results.select { |result| result[:status] == :suppressed }
      return "" if failures.empty? && suppressions.empty? && !@render_empty_state
      return "RailsDoctor: no failures\n" if failures.empty? && suppressions.empty?

      sections = []
      if failures.any?
        sections << failures.map { |result| render_text_result(result) }.join("\n\n")
      end
      if suppressions.any?
        sections << suppressions.map { |result| render_text_result(result, label: "SUPPRESSED") }.join("\n\n")
      end

      sections.join("\n\n") + "\n"
    end

    def render_text_result(result, label: nil)
      status_label = label || result[:severity].to_s.upcase
      line = "#{status_label} #{result[:check_id]} - #{result[:message]}"
      [line, detail("Hint", result[:hint]), detail("Evidence", result[:evidence])].compact.join("\n")
    end

    def render_github_actions_result(result)
      case result[:status]
      when :failed
        GitHubActions.command(
          level: github_actions_level_for_severity(result[:severity]),
          title: "RailsDoctor #{result[:check_id]}",
          message: render_github_actions_message(result)
        )
      when :suppressed
        GitHubActions.command(
          level: "notice",
          title: "RailsDoctor #{result[:check_id]} suppressed",
          message: render_github_actions_message(result)
        )
      end
    end

    def render_github_actions_message(result)
      [result[:message], detail("Hint", result[:hint]), detail("Evidence", result[:evidence])].compact.join("\n")
    end

    def github_actions_level_for_severity(severity)
      if Result::SEVERITY_RANK.fetch(severity) >= Result::SEVERITY_RANK.fetch(:medium)
        "error"
      else
        "warning"
      end
    end

    def detail(label, value)
      return if value.nil? || value == {} || value == []

      "#{label}: #{value}"
    end

    def rendered_results
      @rendered_results ||= @results.map do |result|
        Redaction.sanitize_object(
          result.to_h,
          key_patterns: @redaction_key_patterns,
          value_patterns: @redaction_value_patterns
        )
      end
    end
  end
end
