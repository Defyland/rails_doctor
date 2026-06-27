# frozen_string_literal: true

require "rails/command"
require "rails/command/environment_argument"
require "rails"
require "rails_doctor"

module Rails
  module Command
    class DoctorCommand < Base
      include EnvironmentArgument

      desc "doctor", "Run RailsDoctor diagnostic checks"
      option :fail_on, type: :string, desc: "Exit non-zero when this severity or above is found"
      option :format, type: :string, default: "text", desc: "Output format: text, json, or github-actions"
      option :report, type: :string, default: "checks", desc: "Output surface: checks or suppressions"
      option :only, type: :string, desc: "Comma-separated check ids to run"
      option :exclude, type: :string, desc: "Comma-separated check ids to skip"

      def perform
        boot_application!

        exit_code, output = RailsDoctor::Runner.new.call(
          application: Rails.application,
          environment: options[:environment],
          format: options[:format],
          fail_on: options[:fail_on],
          report: options[:report],
          only: options[:only],
          exclude: options[:exclude]
        )
        say(output, :white)
        exit(exit_code)
      rescue RailsDoctor::Error => error
        warn("RailsDoctor error: #{RailsDoctor::Redaction.sanitize_text(error.message)}")
        exit(1)
      end
    end
  end
end
