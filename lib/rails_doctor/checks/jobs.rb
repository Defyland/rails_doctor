# frozen_string_literal: true

RailsDoctor.register "active_job.adapter.async_in_production" do |check|
  check.severity = :medium
  check.description = "Production jobs need a durable backend."

  check.run do |context|
    next unless context.production?

    adapter = context.active_job_queue_adapter_name
    if adapter.empty? || %w[async inline test].include?(adapter)
      check.fail!(
        "Active Job is using a non-durable adapter in production",
        hint: "Configure Solid Queue, Sidekiq, GoodJob, Delayed Job, or another durable backend.",
        evidence: {queue_adapter: adapter}
      )
    end
  end
end

RailsDoctor.register "solid_queue.database_configuration_missing" do |check|
  check.severity = :high
  check.description = "Solid Queue needs explicit database configuration when selected."

  check.run do |context|
    adapter = context.active_job_queue_adapter_name
    next unless adapter == "solid_queue" || context.gem_loaded?("solid_queue")

    unless context.file?("config/queue.yml") || context.file?("config/solid_queue.yml")
      check.fail!(
        "Solid Queue appears enabled but no queue database configuration was found",
        hint: "Add config/queue.yml or config/solid_queue.yml and verify production database roles.",
        evidence: {queue_adapter: adapter}
      )
    end
  end
end

RailsDoctor.register "solid_queue.database_role_missing" do |check|
  check.severity = :high
  check.description = "Solid Queue separate-database installs need a matching database role."

  check.run do |context|
    adapter = context.active_job_queue_adapter_name
    role = context.solid_queue_writing_role
    next unless adapter == "solid_queue" || context.gem_loaded?("solid_queue") || role
    next if role.nil? || role.empty?

    available_roles = context.database_role_names
    next if available_roles.include?(role)

    check.fail!(
      "Solid Queue queue database role is not defined for this environment",
      hint: "Add the #{role.inspect} role to config/database.yml for #{context.environment} or remove the separate Solid Queue connects_to configuration.",
      evidence: {
        configured_role: role,
        available_roles: available_roles,
        environment: context.environment
      }
    )
  end
end

RailsDoctor.register "solid_queue.schema_artifacts_missing" do |check|
  check.severity = :medium
  check.description = "Solid Queue separate-database installs should keep queue schema artifacts in the app."

  check.run do |context|
    role = context.solid_queue_writing_role
    next if role.nil? || role.empty?

    schema_file = context.file?("db/queue_schema.rb")
    migration_dir = context.directory?("db/queue_migrate")
    next if schema_file || migration_dir

    check.fail!(
      "Solid Queue schema artifacts were not found",
      hint: "Keep db/queue_schema.rb or db/queue_migrate in the app so the queue database can be prepared consistently.",
      evidence: {
        configured_role: role,
        checked: ["db/queue_schema.rb", "db/queue_migrate"]
      }
    )
  end
end
