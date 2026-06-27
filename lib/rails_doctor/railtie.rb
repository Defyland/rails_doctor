# frozen_string_literal: true

require "active_support/core_ext/module/delegation"
require "rails/railtie"

module RailsDoctor
  class Railtie < Rails::Railtie
    config.before_configuration do |application|
      next if application.config.x.rails_doctor.is_a?(RailsDoctor::Configuration)

      application.config.x.rails_doctor = RailsDoctor::Configuration.new
    end

    server do |application|
      next if RailsDoctor::CommandHookRunner.new.call(application: application, command: "server")

      exit(1)
    end

    rake_tasks do |application|
      rake_command_hooks = {
        "db:migrate" => :before_db_migrate,
        "db:prepare" => :before_db_prepare,
        "db:schema:load" => :before_db_schema_load,
        "db:structure:load" => :before_db_structure_load,
        "assets:precompile" => :before_assets_precompile
      }

      namespace :rails_doctor do
        rake_command_hooks.each do |command, hook_task|
          task hook_task => :environment do
            next if RailsDoctor::CommandHookRunner.new.call(application: application, command: command)

            exit(1)
          end
        end
      end

      rake_command_hooks.each do |command, hook_task|
        task command => "rails_doctor:#{hook_task}"
      end
    end
  end
end
