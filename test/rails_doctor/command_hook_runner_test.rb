# frozen_string_literal: true

require "stringio"
require "test_helper"

class RailsDoctorCommandHookRunnerTest < Minitest::Test
  include TestSupport

  def test_runner_blocks_command_when_hook_threshold_is_met
    registry = RailsDoctor::Registry.new
    registry.register("hook.failure") do |check|
      check.severity = :high
      check.run { check.fail!("hook failed", hint: "fix hook") }
    end

    config = fake_config
    config.rails_doctor.before_command("server", only: ["hook.failure"])
    stdout = StringIO.new
    stderr = StringIO.new

    with_tmp_app(config: config) do |application|
      allowed = RailsDoctor::CommandHookRunner.new(
        runner: RailsDoctor::Runner.new(registry: registry),
        stdout: stdout,
        stderr: stderr
      ).call(application: application, command: "server")

      refute allowed
      assert_includes stderr.string, "RailsDoctor before server:"
      assert_includes stderr.string, "hook.failure"
      assert_equal "", stdout.string
    end
  end

  def test_runner_excludes_pending_migration_check_before_db_migrate
    registry = RailsDoctor::Registry.new
    registry.register("database.migrations.pending") do |check|
      check.severity = :high
      check.run { check.fail!("pending migrations", hint: "run migrations") }
    end
    registry.register("custom.passing") do |check|
      check.severity = :low
      check.run {}
    end

    config = fake_config
    config.rails_doctor.before_command("db:migrate")
    stdout = StringIO.new
    stderr = StringIO.new

    with_tmp_app(config: config) do |application|
      allowed = RailsDoctor::CommandHookRunner.new(
        runner: RailsDoctor::Runner.new(registry: registry),
        stdout: stdout,
        stderr: stderr
      ).call(application: application, command: "db:migrate")

      assert allowed
      assert_equal "", stdout.string
      assert_equal "", stderr.string
    end
  end

  def test_runner_excludes_pending_migration_check_before_db_prepare
    registry = RailsDoctor::Registry.new
    registry.register("database.migrations.pending") do |check|
      check.severity = :high
      check.run { check.fail!("pending migrations", hint: "run migrations") }
    end
    registry.register("custom.passing") do |check|
      check.severity = :low
      check.run {}
    end

    config = fake_config
    config.rails_doctor.before_command("db:prepare")
    stdout = StringIO.new
    stderr = StringIO.new

    with_tmp_app(config: config) do |application|
      allowed = RailsDoctor::CommandHookRunner.new(
        runner: RailsDoctor::Runner.new(registry: registry),
        stdout: stdout,
        stderr: stderr
      ).call(application: application, command: "db:prepare")

      assert allowed
      assert_equal "", stdout.string
      assert_equal "", stderr.string
    end
  end

  def test_runner_excludes_asset_manifest_check_before_assets_precompile
    registry = RailsDoctor::Registry.new
    registry.register("assets.production_build_missing") do |check|
      check.severity = :medium
      check.run { check.fail!("asset manifest missing", hint: "build assets") }
    end
    registry.register("custom.passing") do |check|
      check.severity = :low
      check.run {}
    end

    config = fake_config
    config.rails_doctor.before_command("assets:precompile")
    stdout = StringIO.new
    stderr = StringIO.new

    with_tmp_app(config: config) do |application|
      allowed = RailsDoctor::CommandHookRunner.new(
        runner: RailsDoctor::Runner.new(registry: registry),
        stdout: stdout,
        stderr: stderr
      ).call(application: application, command: "assets:precompile")

      assert allowed
      assert_equal "", stdout.string
      assert_equal "", stderr.string
    end
  end

  def test_runner_excludes_pending_migration_check_before_db_schema_load
    registry = RailsDoctor::Registry.new
    registry.register("database.migrations.pending") do |check|
      check.severity = :high
      check.run { check.fail!("pending migrations", hint: "load schema") }
    end
    registry.register("custom.passing") do |check|
      check.severity = :low
      check.run {}
    end

    config = fake_config
    config.rails_doctor.before_command("db:schema:load")
    stdout = StringIO.new
    stderr = StringIO.new

    with_tmp_app(config: config) do |application|
      allowed = RailsDoctor::CommandHookRunner.new(
        runner: RailsDoctor::Runner.new(registry: registry),
        stdout: stdout,
        stderr: stderr
      ).call(application: application, command: "db:schema:load")

      assert allowed
      assert_equal "", stdout.string
      assert_equal "", stderr.string
    end
  end

  def test_runner_excludes_pending_migration_check_before_db_structure_load
    registry = RailsDoctor::Registry.new
    registry.register("database.migrations.pending") do |check|
      check.severity = :high
      check.run { check.fail!("pending migrations", hint: "load structure") }
    end
    registry.register("custom.passing") do |check|
      check.severity = :low
      check.run {}
    end

    config = fake_config
    config.rails_doctor.before_command("db:structure:load")
    stdout = StringIO.new
    stderr = StringIO.new

    with_tmp_app(config: config) do |application|
      allowed = RailsDoctor::CommandHookRunner.new(
        runner: RailsDoctor::Runner.new(registry: registry),
        stdout: stdout,
        stderr: stderr
      ).call(application: application, command: "db:structure:load")

      assert allowed
      assert_equal "", stdout.string
      assert_equal "", stderr.string
    end
  end
end
