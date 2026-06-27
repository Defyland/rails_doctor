# frozen_string_literal: true

require "digest/md5"
require "securerandom"
require "stringio"

module RailsDoctor
  module Probes
    GOOD_JOB_REQUIRED_TABLES = %w[good_jobs].freeze
    SOLID_QUEUE_REQUIRED_TABLES = %w[
      solid_queue_jobs
      solid_queue_ready_executions
      solid_queue_scheduled_executions
      solid_queue_processes
    ].freeze

    module_function

    def active_record
      lambda do |_context|
        unless defined?(ActiveRecord::Base)
          raise ProbeFailure.new(
            "Active Record is not loaded",
            hint: "Load Active Record before enabling the active_record readiness probe."
          )
        end

        ActiveRecord::Base.connection_pool.with_connection do |connection|
          active = connection.respond_to?(:active?) ? connection.active? : true
          connection.verify! if !active && connection.respond_to?(:verify!)
          active = connection.respond_to?(:active?) ? connection.active? : true

          unless active
            raise ProbeFailure.new(
              "database connection is not active",
              hint: "Restore database connectivity and verify the adapter can establish a connection during boot."
            )
          end
        end

        true
      rescue ProbeFailure
        raise
      rescue => error
        raise ProbeFailure.new(
          "database readiness probe failed",
          hint: "Restore database connectivity and verify the configured adapter can establish a connection during boot.",
          evidence: {
            error_class: error.class.name,
            error_message: error.message
          }
        )
      end
    end

    def cache
      lambda do |context|
        store = context.cache
        unless store
          raise ProbeFailure.new(
            "cache store is not available",
            hint: "Configure Rails.cache or remove the cache readiness probe.",
            evidence: {cache_store: context.cache_store_name}
          )
        end

        key = "rails_doctor:probe:#{SecureRandom.hex(12)}"
        value = SecureRandom.hex(8)

        store.write(key, value, expires_in: 60)
        observed = store.read(key)

        unless observed == value
          raise ProbeFailure.new(
            "cache store returned an unexpected value",
            hint: "Verify the configured cache backend accepts writes and reads from this process.",
            evidence: {
              cache_store: context.cache_store_name,
              observed_value_class: observed.class.name
            }
          )
        end

        true
      rescue ProbeFailure
        raise
      rescue => error
        raise ProbeFailure.new(
          "cache readiness probe failed",
          hint: "Restore cache connectivity and confirm the backend is writable from the Rails process.",
          evidence: {
            cache_store: context.cache_store_name,
            error_class: error.class.name,
            error_message: error.message
          }
        )
      ensure
        store&.delete(key) if defined?(store) && defined?(key)
      end
    end

    def redis(client = nil, &client_factory)
      builder = client_factory || ->(_context) { client }

      lambda do |context|
        resolved_client = resolve_probe_target(builder, context)

        unless resolved_client
          raise ProbeFailure.new(
            "redis client is not configured for readiness probing",
            hint: "Pass a Redis client, RedisClient client, or connection pool to RailsDoctor::Probes.redis.",
            evidence: {}
          )
        end

        response = with_redis_client(resolved_client) do |redis_client|
          ping_redis_client(redis_client)
        end

        unless response.to_s.upcase == "PONG"
          raise ProbeFailure.new(
            "redis ping returned an unexpected response",
            hint: "Verify the Redis endpoint is healthy and that the client can complete a PING round-trip.",
            evidence: {
              client_class: resolved_client.class.name,
              response: response.inspect
            }
          )
        end

        true
      rescue ProbeFailure
        raise
      rescue => error
        raise ProbeFailure.new(
          "redis readiness probe failed",
          hint: "Restore Redis connectivity and verify the configured client can issue a PING from the Rails process.",
          evidence: {
            client_class: resolved_client&.class&.name,
            error_class: error.class.name,
            error_message: error.message
          }.compact
        )
      end
    end

    def sidekiq(target = nil, &target_factory)
      builder = target_factory || ->(context) { target || context.sidekiq_redis_target }

      lambda do |context|
        resolved_target = resolve_probe_target(builder, context)

        unless resolved_target
          raise ProbeFailure.new(
            "Sidekiq Redis connection is not configured for readiness probing",
            hint: "Load Sidekiq and use its configured Redis connection, or pass a Sidekiq-compatible target to RailsDoctor::Probes.sidekiq.",
            evidence: {}
          )
        end

        response = with_redis_client(resolved_target, allow_redis_method: true) do |redis_client|
          ping_redis_client(redis_client)
        end

        unless response.to_s.upcase == "PONG"
          raise ProbeFailure.new(
            "Sidekiq Redis ping returned an unexpected response",
            hint: "Verify the Sidekiq Redis endpoint is healthy and that the configured client can complete a PING round-trip.",
            evidence: {
              target_class: probe_target_name(resolved_target),
              response: response.inspect
            }
          )
        end

        true
      rescue ProbeFailure
        raise
      rescue => error
        raise ProbeFailure.new(
          "sidekiq readiness probe failed",
          hint: "Restore Sidekiq Redis connectivity and verify the configured Sidekiq client can issue a PING from the Rails process.",
          evidence: {
            target_class: probe_target_name(resolved_target),
            error_class: error.class.name,
            error_message: error.message
          }.compact
        )
      end
    end

    def active_storage(service = nil, key_prefix: "rails_doctor/probe", &service_factory)
      builder = service_factory || ->(context) { service || context.active_storage_service }

      lambda do |context|
        resolved_service = if builder.arity == 1
          builder.call(context)
        else
          builder.call
        end

        unless resolved_service
          raise ProbeFailure.new(
            "Active Storage service is not configured for readiness probing",
            hint: "Load Active Storage and configure ActiveStorage::Blob.service, or pass a service instance to RailsDoctor::Probes.active_storage.",
            evidence: {service: context.active_storage_service_name}
          )
        end

        key = "#{key_prefix}/#{SecureRandom.hex(12)}"
        payload = SecureRandom.hex(16)
        checksum = Digest::MD5.base64digest(payload)
        uploaded = false
        failure = nil

        resolved_service.upload(key, StringIO.new(payload), checksum: checksum)
        uploaded = true
        observed = resolved_service.download(key)

        unless observed == payload
          raise ProbeFailure.new(
            "Active Storage service returned an unexpected payload",
            hint: "Verify the configured storage backend can round-trip uploaded objects without corruption.",
            evidence: {
              service: context.active_storage_service_name,
              service_class: resolved_service.class.name,
              observed_value_class: observed.class.name
            }
          )
        end

        true
      rescue ProbeFailure => error
        failure = error
        raise
      rescue => error
        failure = ProbeFailure.new(
          "active storage readiness probe failed",
          hint: "Restore object storage connectivity and verify the configured service can upload and download probe objects from the Rails process.",
          evidence: {
            service: context.active_storage_service_name,
            service_class: resolved_service&.class&.name,
            error_class: error.class.name,
            error_message: error.message
          }.compact
        )
        raise failure
      ensure
        if uploaded && defined?(resolved_service) && resolved_service.respond_to?(:delete)
          begin
            resolved_service.delete(key)
          rescue => error
            unless failure
              raise ProbeFailure.new(
                "active storage readiness probe cleanup failed",
                hint: "Verify the configured storage service permits deleting probe objects or pass a dedicated probe prefix.",
                evidence: {
                  service: context.active_storage_service_name,
                  service_class: resolved_service.class.name,
                  key: key,
                  error_class: error.class.name,
                  error_message: error.message
                }.compact
              )
            end
          end
        end
      end
    end

    def good_job(connection_or_pool = nil, required_tables: GOOD_JOB_REQUIRED_TABLES, &connection_factory)
      builder = connection_factory || ->(context) { connection_or_pool || context.good_job_connection_pool }

      lambda do |context|
        resolved_target = resolve_probe_target(builder, context)

        unless resolved_target
          raise ProbeFailure.new(
            "GoodJob connection is not configured for readiness probing",
            hint: "Pass a GoodJob connection or connection pool to RailsDoctor::Probes.good_job, or load GoodJob::Job before running the probe.",
            evidence: {}
          )
        end

        missing_tables = with_data_source_connection(resolved_target) do |connection|
          required_tables.reject { |table_name| connection.data_source_exists?(table_name) }
        end

        unless missing_tables.empty?
          raise ProbeFailure.new(
            "GoodJob required tables are missing",
            hint: "Run db:prepare or install the GoodJob migrations before deploy.",
            evidence: {
              connection_class: probe_target_name(resolved_target),
              missing_tables: missing_tables
            }
          )
        end

        true
      rescue ProbeFailure
        raise
      rescue => error
        raise ProbeFailure.new(
          "good_job readiness probe failed",
          hint: "Restore GoodJob database connectivity and verify the GoodJob schema is loaded for the selected connection.",
          evidence: {
            connection_class: probe_target_name(resolved_target),
            error_class: error.class.name,
            error_message: error.message
          }.compact
        )
      end
    end

    def solid_queue(connection_or_pool = nil, required_tables: SOLID_QUEUE_REQUIRED_TABLES, &connection_factory)
      builder = connection_factory || ->(context) { connection_or_pool || context.solid_queue_connection_pool }

      lambda do |context|
        resolved_target = if builder.arity == 1
          builder.call(context)
        else
          builder.call
        end

        unless resolved_target
          raise ProbeFailure.new(
            "Solid Queue connection is not configured for readiness probing",
            hint: "Pass a Solid Queue connection or connection pool to RailsDoctor::Probes.solid_queue, or load SolidQueue::Record before running the probe.",
            evidence: {}
          )
        end

        missing_tables = with_data_source_connection(resolved_target) do |connection|
          required_tables.reject { |table_name| connection.data_source_exists?(table_name) }
        end

        unless missing_tables.empty?
          raise ProbeFailure.new(
            "Solid Queue required tables are missing",
            hint: "Run db:prepare for the queue database or load the Solid Queue schema before deploy.",
            evidence: {
              connection_class: resolved_target.class.name,
              missing_tables: missing_tables
            }
          )
        end

        true
      rescue ProbeFailure
        raise
      rescue => error
        raise ProbeFailure.new(
          "solid queue readiness probe failed",
          hint: "Restore queue database connectivity and verify the Solid Queue schema is loaded for the selected connection.",
          evidence: {
            connection_class: resolved_target&.class&.name,
            error_class: error.class.name,
            error_message: error.message
          }.compact
        )
      end
    end

    def with_data_source_connection(target)
      if target.respond_to?(:with_connection)
        target.with_connection { |connection| yield connection }
      elsif target.respond_to?(:data_source_exists?)
        yield target
      elsif target.respond_to?(:connection) && target.connection.respond_to?(:data_source_exists?)
        yield target.connection
      else
        raise ProbeFailure.new(
          "queue probe target does not expose a connection",
          hint: "Pass an Active Record connection, connection pool, or model class that exposes #connection.",
          evidence: {target_class: target.class.name}
        )
      end
    end

    def resolve_probe_target(builder, context)
      (builder.arity == 1) ? builder.call(context) : builder.call
    end

    def ping_redis_client(redis_client)
      if redis_client.respond_to?(:ping)
        redis_client.ping
      elsif redis_client.respond_to?(:call)
        redis_client.call("PING")
      else
        raise ProbeFailure.new(
          "redis client does not support PING",
          hint: "Pass a Redis-compatible client that responds to #ping or #call(\"PING\").",
          evidence: {client_class: redis_client.class.name}
        )
      end
    end

    def with_redis_client(target, allow_redis_method: false)
      if allow_redis_method && target.respond_to?(:redis)
        yielded = false
        response = target.redis do |redis_client|
          yielded = true
          yield redis_client
        end

        if yielded
          response
        else
          raise ProbeFailure.new(
            "redis client does not support PING",
            hint: "Pass a Redis-compatible client that responds to #ping or #call(\"PING\").",
            evidence: {client_class: probe_target_name(target)}
          )
        end
      elsif target.respond_to?(:ping) || target.respond_to?(:call)
        yield target
      elsif target.respond_to?(:with)
        target.with { |redis_client| yield redis_client }
      else
        raise ProbeFailure.new(
          "redis client does not support PING",
          hint: "Pass a Redis-compatible client that responds to #ping or #call(\"PING\").",
          evidence: {client_class: probe_target_name(target)}
        )
      end
    end

    def probe_target_name(target)
      return if target.nil?

      named_target = target.respond_to?(:name) ? target.name.to_s : ""
      return named_target unless named_target.empty?

      target.class.name
    end
  end
end
