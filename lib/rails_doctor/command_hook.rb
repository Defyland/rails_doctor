# frozen_string_literal: true

module RailsDoctor
  class CommandHook < Data.define(:command, :fail_on, :only_checks, :exclude_checks)
    DEFAULT_FAIL_ON = "high"
    SUPPORTED_COMMANDS = %w[
      server
      db:migrate
      db:prepare
      db:schema:load
      db:structure:load
      assets:precompile
    ].freeze

    def self.from(source, source_label: "command_hook")
      return source if source.is_a?(self)

      hash = if source.is_a?(Hash)
        source
      elsif source.respond_to?(:to_h)
        source.to_h
      else
        raise Error, "#{source_label} must be a hash"
      end

      build(
        command: hash["command"] || hash[:command],
        fail_on: hash["fail_on"] || hash[:fail_on],
        only_checks: hash["only_checks"] || hash[:only_checks],
        exclude_checks: hash["exclude_checks"] || hash[:exclude_checks],
        source_label: source_label
      )
    end

    def self.build(command:, fail_on: DEFAULT_FAIL_ON, only_checks: nil, exclude_checks: nil, source_label: "command_hook")
      normalized_command = command.to_s.strip
      normalized_fail_on = fail_on.nil? ? DEFAULT_FAIL_ON : fail_on.to_s.strip

      raise Error, "#{source_label} must include command" if normalized_command.empty?
      raise Error, "#{source_label} must include fail_on" if normalized_fail_on.empty?

      unless SUPPORTED_COMMANDS.include?(normalized_command)
        raise Error, "#{source_label} command #{normalized_command.inspect} is unsupported; use #{SUPPORTED_COMMANDS.join(", ")}"
      end

      unless Result::SEVERITY_RANK.key?(normalized_fail_on.to_sym)
        supported = Result::SEVERITY_RANK.keys.join(", ")
        raise Error, "#{source_label} fail_on #{normalized_fail_on.inspect} is unsupported; use #{supported}"
      end

      new(
        command: normalized_command,
        fail_on: normalized_fail_on,
        only_checks: normalize_check_list(only_checks),
        exclude_checks: normalize_check_list(exclude_checks)
      )
    end

    def self.normalize_list(source, source_label: "command_hooks")
      Array(source).each_with_index.each_with_object({}) do |(entry, index), hooks|
        hook = from(entry, source_label: "#{source_label}[#{index}]")
        hooks[hook.command] = hook
      end.values
    end

    def to_h
      {
        command: command,
        fail_on: fail_on,
        only_checks: only_checks,
        exclude_checks: exclude_checks
      }
    end

    def self.normalize_check_list(value)
      Array(value)
        .flat_map { |entry| entry.to_s.split(",") }
        .map(&:strip)
        .reject(&:empty?)
        .uniq
    end

    private_class_method :normalize_check_list
  end
end
