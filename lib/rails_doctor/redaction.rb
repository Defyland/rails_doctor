# frozen_string_literal: true

module RailsDoctor
  module Redaction
    REDACTED = "[REDACTED]"
    SENSITIVE_KEY_PATTERN = /
      password|
      passwd|
      secret|
      token|
      authorization|
      cookie|
      session|
      api(?:_|-)?key|
      access(?:_|-)?key|
      secret(?:_|-)?key|
      credential(?:s)?|
      database_url|
      redis_url|
      dsn
    /ix
    BEARER_PATTERN = /\bBearer\s+[A-Za-z0-9._~+\/=-]+\b/i
    QUOTED_ASSIGNMENT_PATTERN = /
      \b(#{SENSITIVE_KEY_PATTERN})\b
      (\s*[:=]\s*)
      (["'])
      (.*?)
      \3
    /ix
    UNQUOTED_ASSIGNMENT_PATTERN = /
      \b(#{SENSITIVE_KEY_PATTERN})\b
      (\s*[:=]\s*)
      ((?:Bearer\s+)?[^\s,;&]+)
    /ix
    URL_USERINFO_PATTERN = %r{\b([a-z][a-z0-9+\-.]*://)([^/\s@]+)@}i

    module_function

    def sanitize_text(value, key_patterns: [], value_patterns: [])
      return value if value.nil?

      text = value.to_s.dup
      text.gsub!(URL_USERINFO_PATTERN, '\1[REDACTED]@')
      text.gsub!(QUOTED_ASSIGNMENT_PATTERN) do
        "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{Regexp.last_match(3)}#{REDACTED}#{Regexp.last_match(3)}"
      end
      text.gsub!(UNQUOTED_ASSIGNMENT_PATTERN) do
        "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{REDACTED}"
      end
      sanitize_assignments!(text, key_patterns)
      text.gsub!(BEARER_PATTERN, "Bearer #{REDACTED}")
      sanitize_values!(text, value_patterns)
      text
    end

    def sanitize_object(value, key: nil, key_patterns: [], value_patterns: [])
      return REDACTED if sensitive_key?(key, key_patterns: key_patterns)

      case value
      when Hash
        value.each_with_object({}) do |(nested_key, nested_value), sanitized|
          sanitized[nested_key] = sanitize_object(
            nested_value,
            key: nested_key,
            key_patterns: key_patterns,
            value_patterns: value_patterns
          )
        end
      when Array
        value.map { |entry| sanitize_object(entry, key_patterns: key_patterns, value_patterns: value_patterns) }
      when String
        sanitize_text(value, key_patterns: key_patterns, value_patterns: value_patterns)
      when Symbol
        sanitized = sanitize_text(value.to_s, key_patterns: key_patterns, value_patterns: value_patterns)
        if sanitized == value.to_s
          value
        else
          sanitized
        end
      else
        value
      end
    end

    def sensitive_key?(key, key_patterns: [])
      return false if key.nil?

      key_text = key.to_s
      return true if key_text.match?(SENSITIVE_KEY_PATTERN)

      key_patterns.any? do |pattern|
        case pattern
        when Regexp
          pattern.match?(key_text)
        else
          key_text.downcase.include?(pattern.to_s.downcase)
        end
      end
    end

    def sanitize_assignments!(text, patterns)
      patterns.each do |pattern|
        quoted_assignment_regex(pattern)&.tap do |regex|
          text.gsub!(regex) do
            "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{Regexp.last_match(3)}#{REDACTED}#{Regexp.last_match(3)}"
          end
        end

        unquoted_assignment_regex(pattern)&.tap do |regex|
          text.gsub!(regex) do
            "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{REDACTED}"
          end
        end
      end
    end

    def sanitize_values!(text, patterns)
      patterns.each do |pattern|
        regex = case pattern
        when Regexp
          pattern
        else
          Regexp.new(Regexp.escape(pattern.to_s))
        end
        text.gsub!(regex, REDACTED)
      end
    end

    def quoted_assignment_regex(pattern)
      source, options = pattern_source_and_options(pattern)
      Regexp.new("(#{source})(\\s*[:=]\\s*)([\"'])(.*?)(\\3)", options)
    end

    def unquoted_assignment_regex(pattern)
      source, options = pattern_source_and_options(pattern)
      Regexp.new("(#{source})(\\s*[:=]\\s*)((?:Bearer\\s+)?[^\\s,;&]+)", options)
    end

    def pattern_source_and_options(pattern)
      case pattern
      when Regexp
        [pattern.source, pattern.options | Regexp::IGNORECASE]
      else
        ["\\b#{Regexp.escape(pattern.to_s)}\\b", Regexp::IGNORECASE]
      end
    end
  end
end
