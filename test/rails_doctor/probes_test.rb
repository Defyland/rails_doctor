# frozen_string_literal: true

require "test_helper"
require "active_support/cache"

class RailsDoctorProbesTest < Minitest::Test
  include TestSupport

  class FakeStorageService
    attr_reader :deleted_keys

    def initialize(download_value: nil, upload_error: nil, delete_error: nil)
      @delete_error = delete_error
      @download_value = download_value
      @upload_error = upload_error
      @deleted_keys = []
      @objects = {}
    end

    def upload(key, io, checksum: nil)
      raise @upload_error if @upload_error

      @objects[key] = io.read
      @last_checksum = checksum
    end

    def download(key)
      @download_value.nil? ? @objects.fetch(key) : @download_value
    end

    def delete(key)
      raise @delete_error if @delete_error

      @deleted_keys << key
      @objects.delete(key)
    end
  end

  class FakeRedisClient
    def initialize(response: "PONG", error: nil)
      @response = response
      @error = error
    end

    def ping
      raise @error if @error

      @response
    end
  end

  class FakeRedisCaller
    def call(command)
      raise "unexpected command #{command}" unless command == "PING"

      "PONG"
    end
  end

  class FakeRedisPool
    def initialize(client)
      @client = client
    end

    def with
      yield @client
    end
  end

  class FakeQueueConnection
    def initialize(existing_tables: [], error: nil)
      @error = error
      @existing_tables = existing_tables
    end

    def data_source_exists?(table_name)
      raise @error if @error

      @existing_tables.include?(table_name)
    end
  end

  class FakeQueuePool
    def initialize(connection)
      @connection = connection
    end

    def with_connection
      yield @connection
    end
  end

  def test_cache_probe_passes_with_working_cache_store
    cache = ActiveSupport::Cache::MemoryStore.new

    with_tmp_app(cache: cache) do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      assert RailsDoctor::Probes.cache.call(context)
    end
  end

  def test_cache_probe_fails_when_cache_store_is_missing
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.cache.call(context)
      end

      assert_match(/cache store is not available/, error.message)
      assert_equal "redis_cache_store", error.evidence[:cache_store]
    end
  end

  def test_redis_probe_passes_with_direct_client
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      assert RailsDoctor::Probes.redis(FakeRedisClient.new).call(context)
    end
  end

  def test_redis_probe_passes_with_pooled_client
    pool = FakeRedisPool.new(FakeRedisCaller.new)

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      assert RailsDoctor::Probes.redis(pool).call(context)
    end
  end

  def test_redis_probe_fails_without_client
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.redis.call(context)
      end

      assert_match(/redis client is not configured/, error.message)
    end
  end

  def test_redis_probe_wraps_client_errors
    failing_client = FakeRedisClient.new(
      error: StandardError.new("redis://user:super-secret@cache.local/0 token=abc123")
    )

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.redis(failing_client).call(context)
      end

      assert_match(/redis readiness probe failed/, error.message)
      assert_equal "StandardError", error.evidence[:error_class]
      refute_includes error.evidence[:error_message], "super-secret"
      refute_includes error.evidence[:error_message], "abc123"
      assert_includes error.evidence[:error_message], "[REDACTED]"
    end
  end

  def test_sidekiq_probe_reads_redis_connection_from_sidekiq_module
    with_sidekiq_redis_client(FakeRedisClient.new) do
      with_tmp_app do |application|
        context = RailsDoctor::Context.new(application: application, environment: "production")

        assert RailsDoctor::Probes.sidekiq.call(context)
      end
    end
  end

  def test_sidekiq_probe_fails_when_sidekiq_is_missing
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.sidekiq.call(context)
      end

      assert_match(/Sidekiq Redis connection is not configured/, error.message)
    end
  end

  def test_sidekiq_probe_wraps_redis_errors
    with_sidekiq_redis_client(FakeRedisClient.new(error: StandardError.new("redis connection refused"))) do
      with_tmp_app do |application|
        context = RailsDoctor::Context.new(application: application, environment: "production")

        error = assert_raises(RailsDoctor::ProbeFailure) do
          RailsDoctor::Probes.sidekiq.call(context)
        end

        assert_match(/sidekiq readiness probe failed/, error.message)
        assert_equal "StandardError", error.evidence[:error_class]
        assert_equal "redis connection refused", error.evidence[:error_message]
      end
    end
  end

  def test_active_storage_probe_passes_with_explicit_service
    service = FakeStorageService.new

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      assert RailsDoctor::Probes.active_storage(service).call(context)
      assert_equal 1, service.deleted_keys.size
    end
  end

  def test_active_storage_probe_reads_service_from_context_when_available
    service = FakeStorageService.new

    with_active_storage_blob_service(service) do
      with_tmp_app do |application|
        context = RailsDoctor::Context.new(application: application, environment: "production")

        assert RailsDoctor::Probes.active_storage.call(context)
        assert_equal 1, service.deleted_keys.size
      end
    end
  end

  def test_active_storage_probe_fails_when_service_is_missing
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.active_storage.call(context)
      end

      assert_match(/Active Storage service is not configured/, error.message)
      assert_equal "amazon", error.evidence[:service]
    end
  end

  def test_active_storage_probe_wraps_service_errors
    service = FakeStorageService.new(upload_error: StandardError.new("bucket unavailable"))

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.active_storage(service).call(context)
      end

      assert_match(/active storage readiness probe failed/, error.message)
      assert_equal "RailsDoctorProbesTest::FakeStorageService", error.evidence[:service_class]
      assert_equal "StandardError", error.evidence[:error_class]
      assert_equal "bucket unavailable", error.evidence[:error_message]
    end
  end

  def test_active_storage_probe_fails_when_cleanup_fails_after_successful_round_trip
    service = FakeStorageService.new(delete_error: StandardError.new("permission denied"))

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.active_storage(service).call(context)
      end

      assert_match(/cleanup failed/, error.message)
      assert_equal "StandardError", error.evidence[:error_class]
      assert_equal "permission denied", error.evidence[:error_message]
    end
  end

  def test_good_job_probe_reads_connection_pool_from_context_when_available
    connection = FakeQueueConnection.new(existing_tables: RailsDoctor::Probes::GOOD_JOB_REQUIRED_TABLES)
    pool = FakeQueuePool.new(connection)

    with_good_job_connection_pool(pool) do
      with_tmp_app do |application|
        context = RailsDoctor::Context.new(application: application, environment: "production")

        assert RailsDoctor::Probes.good_job.call(context)
      end
    end
  end

  def test_good_job_probe_fails_when_connection_is_missing
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.good_job.call(context)
      end

      assert_match(/GoodJob connection is not configured/, error.message)
    end
  end

  def test_good_job_probe_fails_when_required_tables_are_missing
    connection = FakeQueueConnection.new(existing_tables: [])

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.good_job(connection).call(context)
      end

      assert_match(/GoodJob required tables are missing/, error.message)
      assert_equal %w[good_jobs], error.evidence[:missing_tables]
    end
  end

  def test_good_job_probe_wraps_connection_errors
    connection = FakeQueueConnection.new(error: StandardError.new("connection refused"))

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.good_job(connection).call(context)
      end

      assert_match(/good_job readiness probe failed/, error.message)
      assert_equal "RailsDoctorProbesTest::FakeQueueConnection", error.evidence[:connection_class]
      assert_equal "StandardError", error.evidence[:error_class]
      assert_equal "connection refused", error.evidence[:error_message]
    end
  end

  def test_solid_queue_probe_passes_with_explicit_connection_pool
    connection = FakeQueueConnection.new(existing_tables: RailsDoctor::Probes::SOLID_QUEUE_REQUIRED_TABLES)
    pool = FakeQueuePool.new(connection)

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      assert RailsDoctor::Probes.solid_queue(pool).call(context)
    end
  end

  def test_solid_queue_probe_reads_connection_pool_from_context_when_available
    connection = FakeQueueConnection.new(existing_tables: RailsDoctor::Probes::SOLID_QUEUE_REQUIRED_TABLES)
    pool = FakeQueuePool.new(connection)

    with_solid_queue_record_pool(pool) do
      with_tmp_app do |application|
        context = RailsDoctor::Context.new(application: application, environment: "production")

        assert RailsDoctor::Probes.solid_queue.call(context)
      end
    end
  end

  def test_solid_queue_probe_fails_when_connection_is_missing
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.solid_queue.call(context)
      end

      assert_match(/Solid Queue connection is not configured/, error.message)
    end
  end

  def test_solid_queue_probe_fails_when_required_tables_are_missing
    connection = FakeQueueConnection.new(existing_tables: %w[solid_queue_jobs solid_queue_processes])

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.solid_queue(connection).call(context)
      end

      assert_match(/required tables are missing/, error.message)
      assert_equal %w[solid_queue_ready_executions solid_queue_scheduled_executions], error.evidence[:missing_tables]
    end
  end

  def test_solid_queue_probe_wraps_connection_errors
    connection = FakeQueueConnection.new(error: StandardError.new("connection refused"))

    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")

      error = assert_raises(RailsDoctor::ProbeFailure) do
        RailsDoctor::Probes.solid_queue(connection).call(context)
      end

      assert_match(/solid queue readiness probe failed/, error.message)
      assert_equal "RailsDoctorProbesTest::FakeQueueConnection", error.evidence[:connection_class]
      assert_equal "StandardError", error.evidence[:error_class]
      assert_equal "connection refused", error.evidence[:error_message]
    end
  end

  private

  def with_active_storage_blob_service(service)
    original_active_storage = Object.const_get(:ActiveStorage) if Object.const_defined?(:ActiveStorage)
    Object.send(:remove_const, :ActiveStorage) if Object.const_defined?(:ActiveStorage)

    active_storage = Module.new
    blob = Class.new do
      singleton_class.attr_accessor :service
    end
    blob.service = service
    active_storage.const_set(:Blob, blob)
    Object.const_set(:ActiveStorage, active_storage)

    yield
  ensure
    Object.send(:remove_const, :ActiveStorage) if Object.const_defined?(:ActiveStorage)
    Object.const_set(:ActiveStorage, original_active_storage) if original_active_storage
  end

  def with_solid_queue_record_pool(pool)
    original_solid_queue = Object.const_get(:SolidQueue) if Object.const_defined?(:SolidQueue)
    Object.send(:remove_const, :SolidQueue) if Object.const_defined?(:SolidQueue)

    solid_queue = Module.new
    record = Class.new do
      singleton_class.attr_accessor :connection_pool
    end
    record.connection_pool = pool
    solid_queue.const_set(:Record, record)
    Object.const_set(:SolidQueue, solid_queue)

    yield
  ensure
    Object.send(:remove_const, :SolidQueue) if Object.const_defined?(:SolidQueue)
    Object.const_set(:SolidQueue, original_solid_queue) if original_solid_queue
  end

  def with_sidekiq_redis_client(client)
    original_sidekiq = Object.const_get(:Sidekiq) if Object.const_defined?(:Sidekiq)
    Object.send(:remove_const, :Sidekiq) if Object.const_defined?(:Sidekiq)
    redis_client = client

    sidekiq = Module.new do
      define_singleton_method(:redis) do |&block|
        block.call(redis_client)
      end
    end
    Object.const_set(:Sidekiq, sidekiq)

    yield
  ensure
    Object.send(:remove_const, :Sidekiq) if Object.const_defined?(:Sidekiq)
    Object.const_set(:Sidekiq, original_sidekiq) if original_sidekiq
  end

  def with_good_job_connection_pool(pool)
    original_good_job = Object.const_get(:GoodJob) if Object.const_defined?(:GoodJob)
    Object.send(:remove_const, :GoodJob) if Object.const_defined?(:GoodJob)

    good_job = Module.new
    job = Class.new do
      singleton_class.attr_accessor :connection_pool
    end
    job.connection_pool = pool
    good_job.const_set(:Job, job)
    Object.const_set(:GoodJob, good_job)

    yield
  ensure
    Object.send(:remove_const, :GoodJob) if Object.const_defined?(:GoodJob)
    Object.const_set(:GoodJob, original_good_job) if original_good_job
  end
end
