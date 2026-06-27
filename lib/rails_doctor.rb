# frozen_string_literal: true

require_relative "rails_doctor/version"

module RailsDoctor
  class Error < StandardError; end
end

require_relative "rails_doctor/redaction"
require_relative "rails_doctor/suppression"
require_relative "rails_doctor/result"
require_relative "rails_doctor/command_hook"
require_relative "rails_doctor/configuration"
require_relative "rails_doctor/check"
require_relative "rails_doctor/registry"
require_relative "rails_doctor/context"
require_relative "rails_doctor/probe_failure"
require_relative "rails_doctor/probes"
require_relative "rails_doctor/github_actions"
require_relative "rails_doctor/reporter"
require_relative "rails_doctor/suppression_report"
require_relative "rails_doctor/suppression_reporter"
require_relative "rails_doctor/runner"
require_relative "rails_doctor/command_hook_runner"

module RailsDoctor
  class << self
    def registry
      @registry ||= Registry.new
    end

    def register(id, &block)
      registry.register(id, &block)
    end

    def reset!
      @registry = Registry.new
    end

    def install_builtin_checks
      require_relative "rails_doctor/checks/secrets"
      require_relative "rails_doctor/checks/production_config"
      require_relative "rails_doctor/checks/jobs"
      require_relative "rails_doctor/checks/database"
      require_relative "rails_doctor/checks/assets"
      require_relative "rails_doctor/checks/storage"
      require_relative "rails_doctor/checks/mailer"
      require_relative "rails_doctor/checks/logging"
      require_relative "rails_doctor/checks/health"
      require_relative "rails_doctor/checks/readiness"
      require_relative "rails_doctor/checks/policy"
    end
  end
end

RailsDoctor.install_builtin_checks

require_relative "rails_doctor/railtie" if defined?(Rails::Railtie)
