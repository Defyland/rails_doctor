# frozen_string_literal: true

require "erb"
require "date"
require "pathname"
require "yaml"

module RailsDoctor
  class Context
    attr_reader :application, :environment

    def initialize(application:, environment: nil)
      @application = application
      @environment = (environment || rails_env || "development").to_s
    end

    def production?
      environment == "production"
    end

    def root
      application.respond_to?(:root) ? application.root : Pathname.pwd
    end

    def config
      application.config
    end

    def credentials
      application.respond_to?(:credentials) ? application.credentials : nil
    end

    def cache
      return application.cache if application.respond_to?(:cache)

      Rails.cache if defined?(Rails) && Rails.respond_to?(:cache)
    end

    def cache_store_name
      store = config.respond_to?(:cache_store) ? config.cache_store : nil
      store = store.first if store.is_a?(Array)
      store&.to_s&.delete_prefix(":")
    end

    def active_storage_service
      return unless defined?(ActiveStorage::Blob)
      return unless ActiveStorage::Blob.respond_to?(:service)

      ActiveStorage::Blob.service
    end

    def active_storage_service_name
      return unless config.respond_to?(:active_storage)

      config.active_storage.service&.to_s
    end

    def solid_queue_connection_pool
      return unless defined?(SolidQueue::Record)
      return unless SolidQueue::Record.respond_to?(:connection_pool)

      SolidQueue::Record.connection_pool
    end

    def good_job_connection_pool
      if constant_defined?("GoodJob::BaseRecord") && GoodJob::BaseRecord.respond_to?(:connection_pool)
        GoodJob::BaseRecord.connection_pool
      elsif constant_defined?("GoodJob::Job") && GoodJob::Job.respond_to?(:connection_pool)
        GoodJob::Job.connection_pool
      end
    end

    def sidekiq_redis_target
      return unless constant_defined?("Sidekiq")

      if Sidekiq.respond_to?(:redis_pool)
        Sidekiq.redis_pool
      elsif Sidekiq.respond_to?(:redis)
        Sidekiq
      end
    end

    def solid_queue_writing_role
      return unless config.respond_to?(:solid_queue)
      return unless config.solid_queue.respond_to?(:connects_to)

      connects_to = normalize_hash(config.solid_queue.connects_to)
      database = lookup_hash_value(connects_to, :database)
      normalize_hash(database).yield_self { |hash| lookup_hash_value(hash, :writing) }&.to_s
    end

    def database_configuration_for_environment
      return {} unless config.respond_to?(:database_configuration)

      configuration = config.database_configuration
      environment_config = configuration[environment] || configuration[environment.to_sym]
      normalize_hash(environment_config)
    rescue RuntimeError
      {}
    end

    def database_role_names
      database_configuration_for_environment.each_with_object([]) do |(name, value), roles|
        roles << name.to_s if hash_like?(value)
      end
    end

    def yaml_config(relative_path)
      path = root.join(relative_path)
      return unless path.file?

      contents = ERB.new(path.read).result
      raw = YAML.safe_load(contents, permitted_classes: [Date], aliases: true)

      normalize_hash(raw)
    end

    def secret_key_base
      if application.respond_to?(:secret_key_base)
        application.secret_key_base
      elsif credentials&.respond_to?(:secret_key_base)
        credentials.secret_key_base
      end
    end

    def credential_present?(path)
      value_present?(credential_value(path))
    end

    def env(name)
      ENV.fetch(name, nil)
    end

    def file?(relative_path)
      root.join(relative_path).file?
    end

    def directory?(relative_path)
      root.join(relative_path).directory?
    end

    def read(relative_path)
      path = root.join(relative_path)
      path.read if path.file?
    end

    def route_definitions
      @route_definitions ||= begin
        route_set = application_route_set
        route_set ? extract_route_definitions(route_set) : []
      end
    end

    def gem_loaded?(name)
      Gem.loaded_specs.key?(name)
    end

    def rails_doctor_config
      @rails_doctor_config ||= begin
        configured = if config.respond_to?(:rails_doctor)
          config.rails_doctor
        elsif config.respond_to?(:x) && config.x.respond_to?(:rails_doctor)
          config.x.rails_doctor
        end

        Configuration.from(configured).merge(rails_doctor_policy_config)
      end
    end

    def dependency_probes
      rails_doctor_config.dependency_probes
    end

    def redaction_key_patterns
      Array(config.filter_parameters).filter_map do |entry|
        case entry
        when Regexp
          entry
        when String, Symbol
          normalized = entry.to_s.strip
          normalized unless normalized.empty?
        end
      end.uniq
    end

    def redaction_value_patterns
      rails_doctor_config.redacted_patterns
    end

    def active_job_queue_adapter_name
      adapter = if defined?(ActiveJob::Base) && ActiveJob::Base.respond_to?(:queue_adapter_name)
        ActiveJob::Base.queue_adapter_name
      elsif config.respond_to?(:active_job)
        config.active_job.queue_adapter
      end

      adapter.to_s.delete_prefix(":")
    end

    def database_pool_size
      integer_or_nil(database_pool_details[:value])
    end

    def database_pool_source
      database_pool_details[:source]
    end

    def database_pool_raw_value
      database_pool_details[:value]
    end

    def puma_max_threads
      integer_or_nil(puma_max_threads_details[:value])
    end

    def puma_max_threads_source
      puma_max_threads_details[:source]
    end

    def puma_max_threads_raw_value
      puma_max_threads_details[:value]
    end

    def constant_defined?(name)
      name.split("::").inject(Object) do |namespace, constant_name|
        return false unless namespace.const_defined?(constant_name, false)

        namespace.const_get(constant_name, false)
      end
      true
    rescue NameError
      false
    end

    private

    def rails_env
      Rails.env if defined?(Rails) && Rails.respond_to?(:env)
    end

    def application_route_set
      if application.respond_to?(:routes) && route_set_like?(application.routes)
        application.routes
      elsif defined?(Rails) && Rails.respond_to?(:application) && Rails.application&.respond_to?(:routes) && route_set_like?(Rails.application.routes)
        Rails.application.routes
      end
    end

    def extract_route_definitions(route_set, mount_path: nil, visited: {})
      return [] unless route_set_like?(route_set)
      return [] if visited[route_set.object_id]

      visited[route_set.object_id] = true

      route_set.routes.flat_map do |route|
        path = join_route_paths(mount_path, normalize_route_path(route.path.spec.to_s))
        nested_route_set = nested_route_set_for(route.app)

        definitions = [{path: path, defaults: normalize_hash(route.defaults || {})}]
        if nested_route_set
          definitions.concat(extract_route_definitions(nested_route_set, mount_path: path, visited: visited))
        end
        definitions
      end
    end

    def route_set_like?(value)
      value.respond_to?(:routes)
    end

    def nested_route_set_for(app)
      current = app

      8.times do
        return current if route_set_like?(current)
        return unless current.respond_to?(:app)

        current = current.app
      end

      nil
    end

    def normalize_route_path(path)
      normalized = path.to_s.sub(/\(\.:format\)\z/, "")
      return "/" if normalized.empty?

      normalized.start_with?("/") ? normalized : "/#{normalized}"
    end

    def join_route_paths(prefix, path)
      return normalize_route_path(path) if prefix.nil? || prefix.empty? || prefix == "/"

      normalized_prefix = normalize_route_path(prefix).sub(%r{/\z}, "")
      normalized_path = normalize_route_path(path)
      return normalized_prefix if normalized_path == "/"

      "#{normalized_prefix}/#{normalized_path.sub(%r{\A/}, "")}"
    end

    def active_record_connection_pool_size
      return unless defined?(ActiveRecord::Base)
      return unless ActiveRecord::Base.respond_to?(:connection_pool)

      ActiveRecord::Base.connection_pool.size
    end

    def configured_database_pool
      environment_config = database_configuration_for_environment
      return unless environment_config.respond_to?(:[])

      lookup_hash_value(environment_config, :pool)
    end

    def database_pool_details
      @database_pool_details ||= begin
        active_pool = active_record_connection_pool_size
        configured_pool = configured_database_pool
        primary_pool = configured_primary_database_pool
        sole_role_pool = configured_single_role_database_pool
        rails_max_db_pool = env("RAILS_MAX_DB_POOL")
        db_pool = env("DB_POOL")

        if active_pool
          {value: active_pool, source: "active_record.connection_pool.size"}
        elsif configured_pool
          {value: configured_pool, source: "config/database.yml:#{environment}.pool"}
        elsif primary_pool
          primary_pool
        elsif sole_role_pool
          sole_role_pool
        elsif rails_max_db_pool
          {value: rails_max_db_pool, source: "ENV[RAILS_MAX_DB_POOL]"}
        elsif db_pool
          {value: db_pool, source: "ENV[DB_POOL]"}
        else
          {value: nil, source: nil}
        end
      end
    end

    def puma_max_threads_details
      @puma_max_threads_details ||= begin
        rails_max_threads = env("RAILS_MAX_THREADS")
        configured_threads = configured_puma_max_threads

        if rails_max_threads
          {value: rails_max_threads, source: "ENV[RAILS_MAX_THREADS]"}
        elsif configured_threads
          configured_threads
        else
          {value: nil, source: nil}
        end
      end
    end

    def integer_or_nil(value)
      return if value.nil? || value.to_s.empty?

      Integer(value)
    end

    def hash_like?(value)
      value.is_a?(Hash) || value.respond_to?(:to_h)
    end

    def lookup_hash_value(hash, key)
      hash[key.to_s] || hash[key.to_sym]
    end

    def configured_primary_database_pool
      environment_config = database_configuration_for_environment
      primary_config = lookup_hash_value(environment_config, :primary)
      return unless hash_like?(primary_config)

      pool = lookup_hash_value(normalize_hash(primary_config), :pool)
      return unless pool

      {value: pool, source: "config/database.yml:#{environment}.primary.pool"}
    end

    def configured_single_role_database_pool
      environment_config = database_configuration_for_environment
      role_configs = environment_config.each_with_object({}) do |(name, value), roles|
        roles[name.to_s] = normalize_hash(value) if hash_like?(value)
      end
      return unless role_configs.one?

      role_name, role_config = role_configs.first
      pool = lookup_hash_value(role_config, :pool)
      return unless pool

      {value: pool, source: "config/database.yml:#{environment}.#{role_name}.pool"}
    end

    def configured_puma_max_threads
      puma_config = read("config/puma.rb").to_s
      return if puma_config.empty?

      variable_defaults = {}

      puma_config.each_line do |line|
        variable_assignment = line.match(/^\s*(\w+)\s*=\s*(.+?)\s*$/)
        if variable_assignment
          default = extract_rails_max_threads_default(variable_assignment[2])
          variable_defaults[variable_assignment[1]] = default if default
        end

        threads_call = line.match(/^\s*threads\s+(.+?),\s*(.+?)\s*$/)
        next unless threads_call

        value = resolve_thread_expression(threads_call[2], variable_defaults)
        next unless value

        return {value: value, source: "config/puma.rb"}
      end

      nil
    end

    def resolve_thread_expression(expression, variable_defaults)
      normalized_expression = expression.sub(/\s*#.*\z/, "").strip
      return normalized_expression if normalized_expression.match?(/\A\d+\z/)
      return variable_defaults[normalized_expression] if variable_defaults.key?(normalized_expression)

      extract_rails_max_threads_default(normalized_expression)
    end

    def extract_rails_max_threads_default(expression)
      normalized_expression = expression.strip
      normalized_expression = normalized_expression.delete_prefix("Integer(").delete_suffix(")")

      match = normalized_expression.match(/ENV\.fetch\(["']RAILS_MAX_THREADS["']\s*,\s*(\d+)\)/)
      return match[1] if match

      match = normalized_expression.match(/ENV\.fetch\(["']RAILS_MAX_THREADS["']\)\s*\{\s*(\d+)\s*\}/)
      return match[1] if match

      nil
    end

    def normalize_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), normalized|
          normalized[key.to_s] = normalize_hash(nested_value)
        end
      when Array
        value.map { |entry| normalize_hash(entry) }
      else
        return normalize_hash(value.to_h) if hash_like?(value)

        value
      end
    end

    def credential_value(path)
      keys = String(path).split(".").map(&:strip).reject(&:empty?)
      return if keys.empty?

      fetch_nested_value(credentials, keys)
    end

    def fetch_nested_value(object, keys)
      return object if keys.empty?
      return if object.nil?

      current = nested_value(object, keys.first)
      return current if keys.one?

      fetch_nested_value(current, keys.drop(1))
    end

    def nested_value(object, key)
      if hash_like?(object)
        return lookup_hash_value(normalize_hash(object), key)
      end

      if object.respond_to?(:[])
        value = fetch_indexed_value(object, key)
        return value unless value.nil?
      end

      object.public_send(key) if object.respond_to?(key)
    end

    def fetch_indexed_value(object, key)
      value = object[key]
      return value unless value.nil?

      object[key.to_sym]
    rescue ArgumentError, KeyError, NameError, TypeError
      nil
    end

    def value_present?(value)
      return false if value.nil?
      return !value.strip.empty? if value.is_a?(String)
      return !value.empty? if value.respond_to?(:empty?)

      true
    end

    def rails_doctor_policy_config
      policy = load_rails_doctor_policy
      return Configuration.new unless policy

      direct_keys = policy.keys & Configuration::POLICY_KEYS
      if direct_keys.any?
        raise Error,
          "config/rails_doctor.yml must scope policy keys under default or environment sections: #{direct_keys.sort.join(", ")}"
      end

      Configuration.from_hash(
        lookup_hash_value(policy, :default),
        source_label: "config/rails_doctor.yml:default"
      ).merge(
        Configuration.from_hash(
          lookup_hash_value(policy, environment),
          source_label: "config/rails_doctor.yml:#{environment}"
        )
      )
    end

    def load_rails_doctor_policy
      policy = yaml_config("config/rails_doctor.yml")
      return if policy.nil?

      raise Error, "config/rails_doctor.yml must contain a hash" unless hash_like?(policy)

      normalize_hash(policy)
    rescue Error
      raise
    rescue => error
      raise Error, "config/rails_doctor.yml could not be parsed: #{error.class}: #{error.message}"
    end
  end
end
