# frozen_string_literal: true

module RailsDoctor
  class Configuration
    POLICY_KEYS = %w[
      command_hooks
      exclude_checks
      only_checks
      redacted_patterns
      required_credentials
      required_env
      suppressions
    ].freeze

    attr_writer :command_hooks, :dependency_probes, :exclude_checks, :only_checks, :redacted_patterns,
      :required_credentials, :required_env, :suppressions

    def self.from(source)
      return source if source.is_a?(self)

      configuration = new
      return configuration if source.nil?

      configuration.command_hooks = source.command_hooks if source.respond_to?(:command_hooks)
      configuration.required_env = source.required_env if source.respond_to?(:required_env)
      configuration.required_credentials = source.required_credentials if source.respond_to?(:required_credentials)
      configuration.only_checks = source.only_checks if source.respond_to?(:only_checks)
      configuration.exclude_checks = source.exclude_checks if source.respond_to?(:exclude_checks)
      configuration.redacted_patterns = source.redacted_patterns if source.respond_to?(:redacted_patterns)
      configuration.dependency_probes = source.dependency_probes if source.respond_to?(:dependency_probes)
      configuration.suppressions = source.suppressions if source.respond_to?(:suppressions)
      configuration
    end

    def self.from_hash(source, source_label: "configuration")
      configuration = new
      return configuration if source.nil?

      normalized = if source.is_a?(Hash)
        source
      elsif source.respond_to?(:to_h)
        source.to_h
      else
        raise Error, "#{source_label} must be a hash"
      end

      unknown_keys = normalized.keys.map(&:to_s) - POLICY_KEYS
      if unknown_keys.any?
        raise Error, "#{source_label} has unknown keys: #{unknown_keys.sort.join(", ")}"
      end

      POLICY_KEYS.each do |key|
        next unless normalized.key?(key) || normalized.key?(key.to_sym)

        value = normalized[key] || normalized[key.to_sym]
        if key == "command_hooks"
          configuration.command_hooks = CommandHook.normalize_list(value, source_label: "#{source_label}.command_hooks")
        elsif key == "suppressions"
          configuration.suppressions = Suppression.normalize_list(value, source_label: "#{source_label}.suppressions")
        else
          configuration.public_send("#{key}=", value)
        end
      end

      configuration
    end

    def initialize
      @command_hooks = []
      @dependency_probes = {}
      @exclude_checks = []
      @only_checks = []
      @redacted_patterns = []
      @required_credentials = []
      @required_env = []
      @suppressions = []
    end

    def register_probe(name, probe = nil, &block)
      normalized_name = name.to_s.strip
      implementation = block || probe

      raise Error, "probe name cannot be blank" if normalized_name.empty?
      raise Error, "probe #{normalized_name} must be callable" unless implementation.respond_to?(:call)

      @dependency_probes = dependency_probes.merge(normalized_name => implementation)
    end

    def before_command(command, fail_on: CommandHook::DEFAULT_FAIL_ON, only: nil, exclude: nil)
      hook = CommandHook.build(
        command: command,
        fail_on: fail_on,
        only_checks: only,
        exclude_checks: exclude
      )
      @command_hooks = merge_command_hooks(command_hooks, [hook])
    end

    def suppress(check_id, because:, owner:, expires_on:)
      suppression = Suppression.build(
        check_id: check_id,
        because: because,
        owner: owner,
        expires_on: expires_on
      )
      @suppressions = merge_suppressions(suppressions, [suppression])
    end

    def dependency_probes
      normalize_probe_map(@dependency_probes)
    end

    def command_hooks
      CommandHook.normalize_list(@command_hooks)
    end

    def command_hook_for(command)
      normalized_command = command.to_s.strip
      command_hooks.find { |hook| hook.command == normalized_command }
    end

    def exclude_checks
      normalize_list(@exclude_checks)
    end

    def only_checks
      normalize_list(@only_checks)
    end

    def required_env
      normalize_list(@required_env)
    end

    def required_credentials
      normalize_list(@required_credentials)
    end

    def redacted_patterns
      normalize_patterns(@redacted_patterns)
    end

    def suppressions
      Suppression.normalize_list(@suppressions)
    end

    def filters(only: nil, exclude: nil)
      configured_only = only_checks
      runtime_only = normalize_list(only)

      {
        only: effective_only(configured_only, runtime_only),
        exclude: exclude_checks | normalize_list(exclude),
        suppressions: suppressions
      }
    end

    def merge(other)
      other_configuration = self.class.from(other)

      self.class.new.tap do |configuration|
        configuration.command_hooks = merge_command_hooks(command_hooks, other_configuration.command_hooks)
        configuration.dependency_probes = dependency_probes.merge(other_configuration.dependency_probes)
        configuration.exclude_checks = exclude_checks | other_configuration.exclude_checks
        configuration.only_checks = effective_only(only_checks, other_configuration.only_checks)
        configuration.redacted_patterns = redacted_patterns | other_configuration.redacted_patterns
        configuration.required_credentials = required_credentials | other_configuration.required_credentials
        configuration.required_env = required_env | other_configuration.required_env
        configuration.suppressions = merge_suppressions(suppressions, other_configuration.suppressions)
      end
    end

    private

    def effective_only(configured_only, runtime_only)
      return nil if configured_only.empty? && runtime_only.empty?
      return configured_only if runtime_only.empty?
      return runtime_only if configured_only.empty?

      configured_only & runtime_only
    end

    def normalize_list(value)
      Array(value)
        .flat_map { |entry| entry.to_s.split(",") }
        .map(&:strip)
        .reject(&:empty?)
        .uniq
    end

    def normalize_patterns(value)
      Array(value).filter_map do |entry|
        if entry.is_a?(Regexp)
          entry
        else
          normalized = entry.to_s.strip
          normalized unless normalized.empty?
        end
      end.uniq
    end

    def normalize_probe_map(value)
      return {} if value.nil?

      value.to_h.each_with_object({}) do |(name, probe), probes|
        normalized_name = name.to_s.strip
        raise Error, "probe name cannot be blank" if normalized_name.empty?
        raise Error, "probe #{normalized_name} must be callable" unless probe.respond_to?(:call)

        probes[normalized_name] = probe
      end
    end

    def merge_suppressions(left, right)
      (Array(left) + Array(right)).each_with_object({}) do |entry, suppressions|
        suppression = entry.is_a?(Suppression) ? entry : Suppression.from(entry)
        suppressions[suppression.check_id] = suppression
      end.values
    end

    def merge_command_hooks(left, right)
      (Array(left) + Array(right)).each_with_object({}) do |entry, hooks|
        hook = entry.is_a?(CommandHook) ? entry : CommandHook.from(entry)
        hooks[hook.command] = hook
      end.values
    end
  end
end
