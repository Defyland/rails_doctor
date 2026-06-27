# frozen_string_literal: true

module RailsDoctor
  Result = Data.define(:check_id, :severity, :status, :message, :hint, :evidence) do
    def self.failed(check_id:, severity:, message:, hint:, evidence: {})
      new(
        check_id: check_id,
        severity: severity.to_sym,
        status: :failed,
        message: Redaction.sanitize_text(message),
        hint: Redaction.sanitize_text(hint),
        evidence: Redaction.sanitize_object(evidence)
      )
    end

    def self.passed(check_id:, severity:)
      new(
        check_id: check_id,
        severity: severity.to_sym,
        status: :passed,
        message: "OK",
        hint: nil,
        evidence: {}
      )
    end

    def self.suppressed(check_id:, severity:, because:, owner:, expires_on:)
      new(
        check_id: check_id,
        severity: severity.to_sym,
        status: :suppressed,
        message: "check suppressed by policy",
        hint: Redaction.sanitize_text(because),
        evidence: Redaction.sanitize_object(
          {
            because: because,
            owner: owner,
            expires_on: expires_on
          }
        )
      )
    end

    def failure?
      status == :failed
    end

    def suppressed?
      status == :suppressed
    end

    def severity_rank
      self.class::SEVERITY_RANK.fetch(severity)
    end

    def to_h
      {
        check_id: check_id,
        severity: severity,
        status: status,
        message: message,
        hint: hint,
        evidence: evidence
      }.compact
    end
  end

  Result::SEVERITY_RANK = {
    low: 1,
    warning: 1,
    medium: 2,
    high: 3,
    critical: 4
  }.freeze
end
