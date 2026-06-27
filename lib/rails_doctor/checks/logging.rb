# frozen_string_literal: true

RailsDoctor.register "logging.filter_parameters_missing_pii" do |check|
  check.severity = :high
  check.description = "Known sensitive fields should be filtered from logs."

  check.run do |context|
    filters = Array(context.config.filter_parameters).map(&:to_s)
    required = %w[password token secret authorization cookie ssn cpf credit_card]
    missing = required.reject { |field| filters.any? { |filter| filter.include?(field) } }
    next if missing.empty?

    check.fail!(
      "known sensitive parameters are not filtered",
      hint: "Add missing names to config.filter_parameters.",
      evidence: {missing: missing}
    )
  end
end
