# frozen_string_literal: true

require "test_helper"

class RailsDoctorIntegrationProbeHelpersTest < Minitest::Test
  include TestSupport

  def test_real_rails_command_reports_sidekiq_probe_failures_from_sidekiq_module
    with_integration_app(production_config: <<~RUBY) do |root|
      class FailingSidekiqProbeClient
        def ping
          raise StandardError, "sidekiq redis unavailable"
        end
      end

      module Sidekiq
        def self.redis
          yield FailingSidekiqProbeClient.new
        end
      end

      config.x.rails_doctor.register_probe("sidekiq", RailsDoctor::Probes.sidekiq)
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=readiness.configured_probes_failing"
      )

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "readiness.configured_probes_failing" &&
          entry.fetch("status") == "failed" &&
          entry.dig("evidence", "probe") == "sidekiq"
      end

      refute_nil result
      assert_equal "StandardError", result.dig("evidence", "error_class")
      assert_equal "sidekiq redis unavailable", result.dig("evidence", "error_message")
    end
  end

  def test_real_rails_command_reports_good_job_probe_failures_from_good_job_module
    with_integration_app(production_config: <<~RUBY) do |root|
      class IncompleteGoodJobConnection
        def data_source_exists?(table_name)
          false
        end
      end

      class IncompleteGoodJobPool
        def with_connection
          yield IncompleteGoodJobConnection.new
        end
      end

      module GoodJob
        class Job
          def self.connection_pool
            IncompleteGoodJobPool.new
          end
        end
      end

      config.x.rails_doctor.register_probe("good_job", RailsDoctor::Probes.good_job)
    RUBY
      stdout, stderr, status = run_doctor_command(
        root,
        "--environment=production",
        "--format=json",
        "--only=readiness.configured_probes_failing"
      )

      assert status.success?, stderr

      result = JSON.parse(stdout).find do |entry|
        entry.fetch("check_id") == "readiness.configured_probes_failing" &&
          entry.fetch("status") == "failed" &&
          entry.dig("evidence", "probe") == "good_job"
      end

      refute_nil result
      assert_equal %w[good_jobs], result.dig("evidence", "missing_tables")
      assert_equal "IncompleteGoodJobPool", result.dig("evidence", "connection_class")
    end
  end
end
