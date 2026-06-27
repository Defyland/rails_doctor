# frozen_string_literal: true

module RailsDoctor
  class CommandHookRunner
    DEFAULT_EXCLUDE_CHECKS = {
      "db:migrate" => ["database.migrations.pending"],
      "db:prepare" => ["database.migrations.pending"],
      "db:schema:load" => ["database.migrations.pending"],
      "db:structure:load" => ["database.migrations.pending"],
      "assets:precompile" => ["assets.production_build_missing"]
    }.freeze

    def initialize(runner: Runner.new, stdout: $stdout, stderr: $stderr)
      @runner = runner
      @stdout = stdout
      @stderr = stderr
    end

    def call(application:, command:)
      context = Context.new(application: application)
      hook = context.rails_doctor_config.command_hook_for(command)
      return true unless hook

      exit_code, output = @runner.call(
        application: application,
        environment: context.environment,
        format: "text",
        fail_on: hook.fail_on,
        only: hook.only_checks,
        exclude: hook.exclude_checks | default_exclude_checks(command),
        render_empty_state: false
      )

      print_report(command, output, exit_code:)
      exit_code.zero?
    rescue Error => error
      @stderr.puts("RailsDoctor error before #{command}: #{Redaction.sanitize_text(error.message)}")
      false
    end

    private

    def default_exclude_checks(command)
      DEFAULT_EXCLUDE_CHECKS.fetch(command.to_s, [])
    end

    def print_report(command, output, exit_code:)
      return if output.empty?

      stream = exit_code.zero? ? @stdout : @stderr
      stream.puts("RailsDoctor before #{command}:")
      stream.puts(output)
    end
  end
end
