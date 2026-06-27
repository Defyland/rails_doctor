# frozen_string_literal: true

module RailsDoctor
  module SecretKeyBaseAssessment
    MINIMUM_LENGTH = 64
    PLACEHOLDER_VALUES = %w[changeme changeit development dummy insecure placeholder secret test].freeze
    LOW_VARIETY_UNIQUE_CHARACTER_THRESHOLD = 4
    MAX_REPEATED_PATTERN_LENGTH = 16

    module_function

    def issues(secret)
      normalized_secret = secret.to_s
      compact_secret = normalized_secret.downcase.gsub(/[^a-z0-9]/, "")
      compact_secret = normalized_secret.downcase if compact_secret.empty?

      issues = []
      issues << "missing" if normalized_secret.empty?
      issues << "too_short" if normalized_secret.length < MINIMUM_LENGTH
      issues << "obvious_placeholder" if PLACEHOLDER_VALUES.include?(compact_secret)
      issues << "repeated_character" if repeated_character_secret?(normalized_secret)
      issues << "repeated_pattern" if repeated_pattern_secret?(normalized_secret)
      issues << "low_character_variety" if low_character_variety_secret?(normalized_secret)
      issues
    end

    def repeated_character_secret?(secret)
      return false if secret.empty?

      secret.chars.uniq.one?
    end

    def low_character_variety_secret?(secret)
      return false if secret.length < MINIMUM_LENGTH

      secret.chars.uniq.length <= LOW_VARIETY_UNIQUE_CHARACTER_THRESHOLD
    end

    def repeated_pattern_secret?(secret)
      return false if secret.length < MINIMUM_LENGTH

      max_pattern_length = [secret.length / 2, MAX_REPEATED_PATTERN_LENGTH].min
      2.upto(max_pattern_length).any? do |pattern_length|
        next false unless (secret.length % pattern_length).zero?

        pattern = secret[0, pattern_length]
        pattern * (secret.length / pattern_length) == secret
      end
    end
  end
end

RailsDoctor.register "rails.secrets.secret_key_base_missing" do |check|
  check.severity = :high
  check.description = "Detects missing or obviously unsafe secret_key_base."

  check.run do |context|
    secret = context.secret_key_base.to_s
    issues = RailsDoctor::SecretKeyBaseAssessment.issues(secret)
    if issues.any?
      check.fail!(
        "secret_key_base is missing or too weak",
        hint: "Set a high-entropy secret_key_base through credentials or SECRET_KEY_BASE.",
        evidence: {
          length: secret.length,
          environment: context.environment,
          issues: issues
        }
      )
    end
  end
end

RailsDoctor.register "rails.secrets.required_environment_missing" do |check|
  check.severity = :medium
  check.description = "Checks required environment variables declared for RailsDoctor."

  check.run do |context|
    required = context.rails_doctor_config.required_env
    missing = required.reject { |name| context.env(name).to_s != "" }
    next if missing.empty?

    check.fail!(
      "required environment variables are missing",
      hint: "Set #{missing.join(", ")} before booting this environment.",
      evidence: {missing: missing, configured_key: "config.x.rails_doctor.required_env"}
    )
  end
end

RailsDoctor.register "rails.secrets.required_credentials_missing" do |check|
  check.severity = :medium
  check.description = "Checks required Rails credentials declared for RailsDoctor."

  check.run do |context|
    required = context.rails_doctor_config.required_credentials
    missing = required.reject { |path| context.credential_present?(path) }
    next if missing.empty?

    check.fail!(
      "required Rails credentials are missing",
      hint: "Set #{missing.join(", ")} in Rails credentials for #{context.environment}.",
      evidence: {missing: missing, configured_key: "config.x.rails_doctor.required_credentials"}
    )
  end
end
