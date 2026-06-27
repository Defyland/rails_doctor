# frozen_string_literal: true

RailsDoctor.register "active_storage.service.missing" do |check|
  check.severity = :medium
  check.description = "Active Storage should have an environment-specific service."

  check.run do |context|
    next unless context.config.respond_to?(:active_storage)

    service = context.config.active_storage.service
    if context.production? && (service.nil? || service == :local || service == "local")
      check.fail!(
        "Active Storage service is missing or local in production",
        hint: "Configure config.active_storage.service to a durable object store service.",
        evidence: {service: service.inspect}
      )
    end
  end
end

RailsDoctor.register "active_storage.service_definition_missing" do |check|
  check.severity = :high
  check.description = "Configured Active Storage services should exist in config/storage.yml."

  check.run do |context|
    next unless context.config.respond_to?(:active_storage)

    service = context.active_storage_service_name
    next if service.nil? || service.empty?

    storage_config = context.yaml_config("config/storage.yml")
    unless storage_config.is_a?(Hash) && storage_config.key?(service)
      check.fail!(
        "Active Storage service is not defined in config/storage.yml",
        hint: "Add a #{service.inspect} entry to config/storage.yml or change config.active_storage.service.",
        evidence: {
          service: service,
          storage_yml_present: context.file?("config/storage.yml")
        }
      )
    end
  rescue => error
    check.fail!(
      "config/storage.yml could not be parsed",
      hint: "Fix config/storage.yml syntax and ERB so RailsDoctor can verify the configured Active Storage service.",
      evidence: {
        error_class: error.class.name,
        error_message: error.message
      }
    )
  end
end
