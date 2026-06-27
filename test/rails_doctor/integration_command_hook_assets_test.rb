# frozen_string_literal: true

require "test_helper"

class RailsDoctorIntegrationCommandHookAssetsTest < Minitest::Test
  include TestSupport

  def test_assets_precompile_command_hook_blocks_task_execution
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :assets do
        task precompile: :environment do
          FileUtils.mkdir_p(Rails.root.join("tmp"))
          File.write(Rails.root.join("tmp/assets_precompile_ran.txt"), "ran")
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "assets:precompile",
        fail_on: :high,
        only: %w[rails.production.force_ssl_disabled]
      )
    RUBY
      stdout, stderr, status = run_rails_command(root, "assets:precompile", env: {"RAILS_ENV" => "production"})

      assert_equal 1, status.exitstatus
      assert_includes stderr, "RailsDoctor before assets:precompile:"
      assert_includes stderr, "rails.production.force_ssl_disabled"
      refute root.join("tmp/assets_precompile_ran.txt").exist?
      refute_includes stdout, "lib/rails_doctor"
    end
  end

  def test_assets_precompile_command_hook_allows_task_when_manifest_check_is_default_excluded
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :assets do
        task precompile: :environment do
          FileUtils.mkdir_p(Rails.root.join("tmp"))
          File.write(Rails.root.join("tmp/assets_precompile_ran.txt"), "ran")
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "assets:precompile",
        fail_on: :medium,
        only: %w[assets.production_build_missing rails.secrets.required_credentials_missing]
      )
    RUBY
      stdout, stderr, status = run_rails_command(root, "assets:precompile", env: {"RAILS_ENV" => "production"})

      assert status.success?, stderr
      refute_includes stdout, "RailsDoctor before assets:precompile:"
      refute_includes stderr, "RailsDoctor before assets:precompile:"
      assert_equal "ran", root.join("tmp/assets_precompile_ran.txt").read
    end
  end
end
