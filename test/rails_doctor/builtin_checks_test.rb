# frozen_string_literal: true

require "test_helper"

class RailsDoctorBuiltinChecksTest < Minitest::Test
  include TestSupport

  def test_detects_weak_secret_key_base
    with_tmp_app(secret_key_base: "secret") do |application|
      results = RailsDoctor.registry.fetch("rails.secrets.secret_key_base_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_match(/secret_key_base/, results.first.message)
      assert_includes results.first.evidence[:issues], "too_short"
      assert_includes results.first.evidence[:issues], "obvious_placeholder"
    end
  end

  def test_detects_repeated_character_secret_key_base
    with_tmp_app(secret_key_base: "x" * 64) do |application|
      result = RailsDoctor.registry.fetch("rails.secrets.secret_key_base_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :failed, result.status
      assert_includes result.evidence[:issues], "repeated_character"
      assert_includes result.evidence[:issues], "low_character_variety"
    end
  end

  def test_detects_repeated_pattern_secret_key_base
    with_tmp_app(secret_key_base: "0123456789abcdef" * 4) do |application|
      result = RailsDoctor.registry.fetch("rails.secrets.secret_key_base_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :failed, result.status
      assert_includes result.evidence[:issues], "repeated_pattern"
    end
  end

  def test_accepts_high_entropy_secret_key_base
    strong_secret = (("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a + %w[! @]).join

    with_tmp_app(secret_key_base: strong_secret) do |application|
      result = RailsDoctor.registry.fetch("rails.secrets.secret_key_base_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :passed, result.status
    end
  end

  def test_secret_key_base_check_does_not_leak_the_secret_value
    weak_secret = "super-secret-value"

    with_tmp_app(secret_key_base: weak_secret) do |application|
      result = RailsDoctor.registry.fetch("rails.secrets.secret_key_base_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      refute_includes result.message, weak_secret
      refute_includes result.hint, weak_secret
      refute_includes result.to_h.to_s, weak_secret
      assert_equal weak_secret.length, result.evidence[:length]
    end
  end

  def test_required_environment_check_passes_when_no_required_env_config_exists
    config = fake_config
    config.rails_doctor = nil

    with_tmp_app(config: config) do |application|
      results = RailsDoctor.registry.fetch("rails.secrets.required_environment_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :passed, results.first.status
    end
  end

  def test_required_environment_check_reads_rails_doctor_configuration
    config = fake_config
    config.rails_doctor.required_env = %w[API_TOKEN OTHER_KEY]

    with_tmp_app(config: config) do |application|
      results = RailsDoctor.registry.fetch("rails.secrets.required_environment_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_equal ["API_TOKEN", "OTHER_KEY"], results.first.evidence[:missing]
    end
  end

  def test_required_environment_check_reports_names_not_present_values
    config = fake_config
    config.rails_doctor.required_env = %w[API_TOKEN OTHER_KEY]

    with_env("API_TOKEN" => "present-secret-token") do
      with_tmp_app(config: config) do |application|
        result = RailsDoctor.registry.fetch("rails.secrets.required_environment_missing")
          .execute(RailsDoctor::Context.new(application: application, environment: "production"))
          .first

        assert_equal ["OTHER_KEY"], result.evidence[:missing]
        refute_includes result.message, "present-secret-token"
        refute_includes result.hint, "present-secret-token"
        refute_includes result.to_h.to_s, "present-secret-token"
      end
    end
  end

  def test_required_credentials_check_reads_rails_doctor_configuration
    config = fake_config
    config.rails_doctor.required_credentials = %w[aws.access_key_id aws.secret_access_key]

    with_tmp_app(config: config) do |application|
      credentials = ActiveSupport::OrderedOptions.new
      aws = ActiveSupport::OrderedOptions.new
      aws.access_key_id = "present-access-key"
      credentials.aws = aws
      application.define_singleton_method(:credentials) { credentials }

      result = RailsDoctor.registry.fetch("rails.secrets.required_credentials_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :failed, result.status
      assert_equal ["aws.secret_access_key"], result.evidence[:missing]
      assert_equal "config.x.rails_doctor.required_credentials", result.evidence[:configured_key]
    end
  end

  def test_required_credentials_check_reports_paths_not_present_values
    config = fake_config
    config.rails_doctor.required_credentials = %w[aws.access_key_id aws.secret_access_key]

    with_tmp_app(config: config) do |application|
      credentials = ActiveSupport::OrderedOptions.new
      aws = ActiveSupport::OrderedOptions.new
      aws.access_key_id = "present-secret-access-key"
      credentials.aws = aws
      application.define_singleton_method(:credentials) { credentials }

      result = RailsDoctor.registry.fetch("rails.secrets.required_credentials_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal ["aws.secret_access_key"], result.evidence[:missing]
      refute_includes result.message, "present-secret-access-key"
      refute_includes result.hint, "present-secret-access-key"
      refute_includes result.to_h.to_s, "present-secret-access-key"
    end
  end

  def test_detects_force_ssl_disabled_in_production
    config = fake_config
    config.force_ssl = false

    with_tmp_app(config: config) do |application|
      results = RailsDoctor.registry.fetch("rails.production.force_ssl_disabled")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
    end
  end

  def test_detects_weak_session_cookie_flags_in_production
    config = fake_config
    config.force_ssl = false
    config.session_options = {secure: false, httponly: false, same_site: :lax}

    with_tmp_app(config: config) do |application|
      result = RailsDoctor.registry.fetch("rails.session.cookie_flags_weak")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :failed, result.status
      assert_equal ["secure_not_enabled", "httponly_disabled"], result.evidence[:issues]
      assert_equal false, result.evidence[:secure]
      assert_equal false, result.evidence[:httponly]
      assert_equal false, result.evidence[:force_ssl]
    end
  end

  def test_force_ssl_satisfies_secure_session_cookie_requirement
    config = fake_config
    config.force_ssl = true
    config.session_options = {httponly: true, same_site: :lax}

    with_tmp_app(config: config) do |application|
      result = RailsDoctor.registry.fetch("rails.session.cookie_flags_weak")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :passed, result.status
    end
  end

  def test_api_only_apps_skip_session_cookie_flag_check
    config = fake_config
    config.api_only = true
    config.force_ssl = false
    config.session_options = {secure: false, httponly: false, same_site: :lax}

    with_tmp_app(config: config) do |application|
      result = RailsDoctor.registry.fetch("rails.session.cookie_flags_weak")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :passed, result.status
    end
  end

  def test_detects_expired_suppressions
    config = fake_config
    config.rails_doctor.suppress(
      "rails.production.force_ssl_disabled",
      because: "HTTPS is enforced before Rails",
      owner: "platform@example.com",
      expires_on: "2000-01-01"
    )

    with_tmp_app(config: config) do |application|
      result = RailsDoctor.registry.fetch("rails_doctor.suppressions.expired")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :failed, result.status
      assert_equal "rails.production.force_ssl_disabled", result.evidence[:expired].first[:check_id]
      assert_equal "platform@example.com", result.evidence[:expired].first[:owner]
      assert_equal "2000-01-01", result.evidence[:expired].first[:expires_on]
    end
  end

  def test_detects_suppressions_expiring_soon
    config = fake_config
    config.rails_doctor.suppress(
      "rails.production.force_ssl_disabled",
      because: "HTTPS is enforced before Rails",
      owner: "platform@example.com",
      expires_on: (Date.today + 5).iso8601
    )

    with_tmp_app(config: config) do |application|
      result = RailsDoctor.registry.fetch("rails_doctor.suppressions.expiring_soon")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))
        .first

      assert_equal :failed, result.status
      assert_equal 14, result.evidence[:window_days]
      assert_equal "rails.production.force_ssl_disabled", result.evidence[:expiring_soon].first[:check_id]
      assert_equal 5, result.evidence[:expiring_soon].first[:days_until_expiry]
    end
  end

  def test_detects_database_pool_smaller_than_threads
    with_env("DB_POOL" => "2", "RAILS_MAX_THREADS" => "5") do
      with_tmp_app do |application|
        results = RailsDoctor.registry.fetch("database.pool.too_small")
          .execute(RailsDoctor::Context.new(application: application, environment: "production"))

        assert_equal :failed, results.first.status
        assert_equal(
          {
            database_pool: 2,
            database_pool_source: "ENV[DB_POOL]",
            puma_threads: 5,
            puma_threads_source: "ENV[RAILS_MAX_THREADS]"
          },
          results.first.evidence
        )
      end
    end
  end

  def test_detects_database_pool_from_rails_database_configuration
    config = fake_config
    config.database_configuration = {"production" => {"pool" => "3"}}

    with_env("RAILS_MAX_THREADS" => "5") do
      with_tmp_app(config: config) do |application|
        results = RailsDoctor.registry.fetch("database.pool.too_small")
          .execute(RailsDoctor::Context.new(application: application, environment: "production"))

        assert_equal :failed, results.first.status
        assert_equal(
          {
            database_pool: 3,
            database_pool_source: "config/database.yml:production.pool",
            puma_threads: 5,
            puma_threads_source: "ENV[RAILS_MAX_THREADS]"
          },
          results.first.evidence
        )
      end
    end
  end

  def test_detects_database_pool_from_primary_role_configuration
    config = fake_config
    config.database_configuration = {
      "production" => {
        "primary" => {"pool" => "3", "database" => "app_production"},
        "queue" => {"pool" => "20", "database" => "queue_production"}
      }
    }

    with_env("RAILS_MAX_THREADS" => "5") do
      with_tmp_app(config: config) do |application|
        results = RailsDoctor.registry.fetch("database.pool.too_small")
          .execute(RailsDoctor::Context.new(application: application, environment: "production"))

        assert_equal :failed, results.first.status
        assert_equal(
          {
            database_pool: 3,
            database_pool_source: "config/database.yml:production.primary.pool",
            puma_threads: 5,
            puma_threads_source: "ENV[RAILS_MAX_THREADS]"
          },
          results.first.evidence
        )
      end
    end
  end

  def test_detects_database_pool_with_puma_template_default_threads
    config = fake_config
    config.database_configuration = {"production" => {"pool" => "3"}}

    with_tmp_app(config: config) do |application, root|
      root.join("config/puma.rb").write(<<~RUBY)
        max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
        min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
        threads min_threads_count, max_threads_count
      RUBY

      results = RailsDoctor.registry.fetch("database.pool.too_small")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_equal(
        {
          database_pool: 3,
          database_pool_source: "config/database.yml:production.pool",
          puma_threads: 5,
          puma_threads_source: "config/puma.rb"
        },
        results.first.evidence
      )
    end
  end

  def test_detects_mailer_host_missing
    config = fake_config
    config.action_mailer.default_url_options = {}

    with_tmp_app(config: config) do |application|
      results = RailsDoctor.registry.fetch("mailer.default_url_options_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
    end
  end

  def test_detects_solid_queue_database_role_missing
    config = fake_config
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = {database: {writing: :queue}}
    config.database_configuration = {"production" => {"primary" => {"database" => "app_production"}}}

    with_tmp_app(config: config) do |application|
      results = RailsDoctor.registry.fetch("solid_queue.database_role_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_equal "queue", results.first.evidence[:configured_role]
      assert_equal ["primary"], results.first.evidence[:available_roles]
    end
  end

  def test_detects_solid_queue_schema_artifacts_missing
    config = fake_config
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = {database: {writing: :queue}}
    config.database_configuration = {"production" => {"primary" => {"database" => "app"}, "queue" => {"database" => "queue"}}}

    with_tmp_app(config: config) do |application|
      results = RailsDoctor.registry.fetch("solid_queue.schema_artifacts_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_equal ["db/queue_schema.rb", "db/queue_migrate"], results.first.evidence[:checked]
    end
  end

  def test_detects_active_storage_service_definition_missing
    with_tmp_app do |application, root|
      root.join("config/storage.yml").write("local:\n  service: Disk\n")

      results = RailsDoctor.registry.fetch("active_storage.service_definition_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_equal "amazon", results.first.evidence[:service]
      assert_equal true, results.first.evidence[:storage_yml_present]
    end
  end

  def test_detects_readiness_route_gap
    with_tmp_app do |application, root|
      root.join("config/routes.rb").write("Rails.application.routes.draw do\n  get \"up\" => \"rails/health#show\"\nend\n")

      results = RailsDoctor.registry.fetch("health.readiness_route_missing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_equal "config/routes.rb", results.first.evidence[:route_source]
    end
  end

  def test_readiness_route_check_accepts_mounted_engine_routes
    with_tmp_app do |application|
      context = RailsDoctor::Context.new(application: application, environment: "production")
      context.define_singleton_method(:route_definitions) do
        [
          {path: "/up", defaults: {}},
          {path: "/ops", defaults: {}},
          {path: "/ops/ready", defaults: {}}
        ]
      end

      result = RailsDoctor.registry.fetch("health.readiness_route_missing")
        .execute(context)
        .first

      assert_equal :passed, result.status
    end
  end

  def test_detects_configured_dependency_probe_failure
    config = fake_config
    config.rails_doctor.register_probe("cache") do |_context|
      raise RailsDoctor::ProbeFailure.new(
        "cache backend is unreachable",
        hint: "Restore cache connectivity before deploy.",
        evidence: {cache_store: "redis_cache_store"}
      )
    end

    with_tmp_app(config: config) do |application|
      results = RailsDoctor.registry.fetch("readiness.configured_probes_failing")
        .execute(RailsDoctor::Context.new(application: application, environment: "production"))

      assert_equal :failed, results.first.status
      assert_equal "cache", results.first.evidence[:probe]
      assert_equal "redis_cache_store", results.first.evidence[:cache_store]
    end
  end

  private

  def with_env(values)
    previous = values.transform_values { |_value| nil }
    values.each do |key, value|
      previous[key] = ENV.fetch(key, nil)
      ENV[key] = value
    end
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
