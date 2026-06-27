# frozen_string_literal: true

RailsDoctor.register "mailer.default_url_options_missing" do |check|
  check.severity = :low
  check.description = "Mailers that generate URLs need a host."

  check.run do |context|
    next unless context.config.respond_to?(:action_mailer)

    options = context.config.action_mailer.default_url_options || {}
    if context.production? && options[:host].to_s.empty?
      check.fail!(
        "Action Mailer default_url_options host is missing",
        hint: "Set config.action_mailer.default_url_options = { host: \"example.com\" }.",
        evidence: {default_url_options: options}
      )
    end
  end
end
