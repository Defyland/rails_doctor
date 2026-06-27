# frozen_string_literal: true

module RailsDoctor
  class ProbeFailure < Error
    attr_reader :hint, :evidence

    def initialize(message, hint:, evidence: {})
      super(Redaction.sanitize_text(message))
      @hint = Redaction.sanitize_text(hint)
      @evidence = Redaction.sanitize_object(evidence)
    end
  end
end
