# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

module IntegrationAppHarness
  def with_integration_app(production_config: nil, rake_tasks: nil)
    Dir.mktmpdir("rails-doctor-integration") do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("bin"))
      FileUtils.mkdir_p(root.join("config/environments"))
      FileUtils.mkdir_p(root.join("lib/tasks"))

      root.join("config/boot.rb").write(<<~RUBY)
        ENV["BUNDLE_GEMFILE"] ||= #{File.expand_path("../../Gemfile", __dir__).inspect}
        require "bundler/setup"
      RUBY

      root.join("config/application.rb").write(<<~RUBY)
        require_relative "boot"
        require "rails"
        require "action_controller/railtie"
        require "rails_doctor"

        module DummyDoctorApp
          class Application < Rails::Application
            config.root = File.expand_path("..", __dir__)
            config.eager_load = false
            config.secret_key_base = "x" * 64
            config.consider_all_requests_local = true
            config.filter_parameters += [:password]
          end
        end
      RUBY

      root.join("config/environment.rb").write(<<~RUBY)
        require_relative "application"
        DummyDoctorApp::Application.initialize!
      RUBY
      root.join("Rakefile").write(<<~RUBY)
        require_relative "config/application"

        Rails.application.load_tasks
      RUBY

      root.join("config/environments/production.rb").write(production_environment_config(production_config))
      root.join("config/routes.rb").write(<<~RUBY)
        Rails.application.routes.draw do
          get "/up", to: ->(_env) { [200, {"Content-Type" => "text/plain"}, ["ok"]] }
        end
      RUBY
      root.join("config.ru").write(<<~RUBY)
        require_relative "config/environment"

        run Rails.application
        Rails.application.load_server
      RUBY
      root.join("lib/tasks/test_tasks.rake").write(rake_tasks) if rake_tasks

      root.join("bin/rails").write(<<~RUBY)
        #!/usr/bin/env ruby
        APP_PATH = File.expand_path("../config/application", __dir__)
        require_relative "../config/boot"
        require "rails/commands"
      RUBY
      FileUtils.chmod("+x", root.join("bin/rails"))

      yield root
    end
  end

  def run_rails_command(root, *args, env: {})
    Open3.capture3(env, RbConfig.ruby, "bin/rails", *args, chdir: root.to_s)
  end

  def run_doctor_command(root, *args, env: {})
    run_rails_command(root, "doctor", *args, env: env)
  end

  private

  def production_environment_config(extra_config)
    <<~RUBY
      Rails.application.configure do
        config.force_ssl = false
        config.cache_store = :memory_store
        config.x.rails_doctor.required_env = %w[API_TOKEN]
        config.x.rails_doctor.exclude_checks = %w[health.readiness_route_missing]
      #{extra_config}
      end
    RUBY
  end
end
