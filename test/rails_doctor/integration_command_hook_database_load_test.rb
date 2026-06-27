# frozen_string_literal: true

require "test_helper"

class RailsDoctorIntegrationCommandHookDatabaseLoadTest < Minitest::Test
  include TestSupport

  def test_db_schema_load_command_hook_blocks_task_execution
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        namespace :schema do
          task load: :environment do
            FileUtils.mkdir_p(Rails.root.join("tmp"))
            File.write(Rails.root.join("tmp/db_schema_load_ran.txt"), "ran")
          end
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:schema:load",
        fail_on: :high,
        only: %w[rails.production.force_ssl_disabled]
      )
    RUBY
      stdout, stderr, status = run_rails_command(root, "db:schema:load", env: {"RAILS_ENV" => "production"})

      assert_equal 1, status.exitstatus
      assert_includes stderr, "RailsDoctor before db:schema:load:"
      assert_includes stderr, "rails.production.force_ssl_disabled"
      refute root.join("tmp/db_schema_load_ran.txt").exist?
      refute_includes stdout, "lib/rails_doctor"
    end
  end

  def test_db_schema_load_command_hook_allows_task_with_hook_specific_only_checks
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        namespace :schema do
          task load: :environment do
            FileUtils.mkdir_p(Rails.root.join("tmp"))
            File.write(Rails.root.join("tmp/db_schema_load_ran.txt"), "ran")
          end
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:schema:load",
        fail_on: :high,
        only: %w[rails.secrets.required_environment_missing]
      )
    RUBY
      stdout, stderr, status = run_rails_command(
        root,
        "db:schema:load",
        env: {
          "RAILS_ENV" => "production",
          "API_TOKEN" => "present-token"
        }
      )

      assert status.success?, stderr
      refute_includes stdout, "RailsDoctor before db:schema:load:"
      refute_includes stderr, "RailsDoctor before db:schema:load:"
      assert_equal "ran", root.join("tmp/db_schema_load_ran.txt").read
    end
  end

  def test_db_structure_load_command_hook_blocks_task_execution
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        namespace :structure do
          task load: :environment do
            FileUtils.mkdir_p(Rails.root.join("tmp"))
            File.write(Rails.root.join("tmp/db_structure_load_ran.txt"), "ran")
          end
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:structure:load",
        fail_on: :high,
        only: %w[rails.production.force_ssl_disabled]
      )
    RUBY
      stdout, stderr, status = run_rails_command(root, "db:structure:load", env: {"RAILS_ENV" => "production"})

      assert_equal 1, status.exitstatus
      assert_includes stderr, "RailsDoctor before db:structure:load:"
      assert_includes stderr, "rails.production.force_ssl_disabled"
      refute root.join("tmp/db_structure_load_ran.txt").exist?
      refute_includes stdout, "lib/rails_doctor"
    end
  end

  def test_db_structure_load_command_hook_allows_task_with_hook_specific_only_checks
    rake_tasks = <<~RUBY
      require "fileutils"

      namespace :db do
        namespace :structure do
          task load: :environment do
            FileUtils.mkdir_p(Rails.root.join("tmp"))
            File.write(Rails.root.join("tmp/db_structure_load_ran.txt"), "ran")
          end
        end
      end
    RUBY

    with_integration_app(production_config: <<~RUBY, rake_tasks: rake_tasks) do |root|
      config.x.rails_doctor.before_command(
        "db:structure:load",
        fail_on: :high,
        only: %w[rails.secrets.required_environment_missing]
      )
    RUBY
      stdout, stderr, status = run_rails_command(
        root,
        "db:structure:load",
        env: {
          "RAILS_ENV" => "production",
          "API_TOKEN" => "present-token"
        }
      )

      assert status.success?, stderr
      refute_includes stdout, "RailsDoctor before db:structure:load:"
      refute_includes stderr, "RailsDoctor before db:structure:load:"
      assert_equal "ran", root.join("tmp/db_structure_load_ran.txt").read
    end
  end
end
