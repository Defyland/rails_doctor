# frozen_string_literal: true

require "json"

module RailsDoctor
  module PackageAudit
    module HostAppSmoke
      module_function

      def verify!(gem_path:)
        Dir.mktmpdir("rails-doctor-host-app") do |directory|
          app_root = File.join(directory, "host_app")
          gem_home = File.join(directory, "gems")
          FileUtils.mkdir_p(gem_home)

          installed_spec = PackageAudit.install_built_gem!(gem_path, gem_home)
          bundler_gem_path = unpack_built_gem_for_bundler!(app_root, gem_path, installed_spec)
          write_host_app!(app_root, bundler_gem_path)

          env = host_app_bundle_env(app_root, gem_home)
          run_bundle!(app_root, env, "install", "--local")
          verify_loaded_gem!(app_root, env, installed_spec.version, bundler_gem_path)
          verify_doctor_command!(app_root, env)
        end
      end

      def host_app_bundle_env(app_root, gem_home)
        env = PackageAudit.sanitized_env.merge(
          "BUNDLE_APP_CONFIG" => File.join(app_root, ".bundle"),
          "BUNDLE_GEMFILE" => File.join(app_root, "Gemfile"),
          "GEM_HOME" => gem_home,
          "GEM_PATH" => ([gem_home] + PackageAudit.base_gem_paths).uniq.join(File::PATH_SEPARATOR)
        )
        env["BUNDLE_PATH"] = PackageAudit.bundler_configured_path if PackageAudit.bundler_configured_path
        env
      end

      def write_host_app!(app_root, bundler_gem_path)
        write_file(
          app_root,
          "Gemfile",
          <<~RUBY
            source "https://rubygems.org"

            gem "railties", "= #{host_dependency_version("railties")}"
            gem "actionpack", "= #{host_dependency_version("actionpack")}"
            gem "rails_doctor", path: #{bundler_gem_path.inspect}
          RUBY
        )

        write_file(
          app_root,
          "config/boot.rb",
          <<~RUBY
            ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
            require "bundler/setup"
          RUBY
        )

        write_file(
          app_root,
          "config/application.rb",
          <<~RUBY
            require_relative "boot"
            require "rails"
            require "action_controller/railtie"
            require "rails_doctor"

            module DoctorHostApp
              class Application < Rails::Application
                config.root = File.expand_path("..", __dir__)
                config.eager_load = false
                config.secret_key_base = "x" * 64
                config.consider_all_requests_local = true
                config.filter_parameters += [:password]
              end
            end
          RUBY
        )

        write_file(
          app_root,
          "config/environment.rb",
          <<~RUBY
            require_relative "application"
            DoctorHostApp::Application.initialize!
          RUBY
        )

        write_file(
          app_root,
          "config/environments/production.rb",
          <<~RUBY
            Rails.application.configure do
              config.force_ssl = false
              config.x.rails_doctor.required_env = %w[API_TOKEN]
            end
          RUBY
        )

        write_file(
          app_root,
          "config/routes.rb",
          <<~RUBY
            Rails.application.routes.draw do
              get "/up", to: ->(_env) { [200, {"Content-Type" => "text/plain"}, ["ok"]] }
            end
          RUBY
        )

        write_file(
          app_root,
          "bin/rails",
          <<~RUBY
            #!/usr/bin/env ruby
            APP_PATH = File.expand_path("../config/application", __dir__)
            require_relative "../config/boot"
            require "rails/commands"
          RUBY
        )

        FileUtils.chmod("+x", File.join(app_root, "bin/rails"))
      end

      def verify_loaded_gem!(app_root, env, expected_version, expected_gem_path)
        PackageAudit.run_command!(
          env.merge(
            "EXPECTED_GEM_PATH" => File.realpath(expected_gem_path),
            "EXPECTED_GEM_VERSION" => expected_version.to_s
          ),
          bundle_command("exec", "ruby", "-e", loaded_gem_script),
          failure_message: "Bundler did not resolve rails_doctor from the built gem installation.",
          chdir: app_root
        )
      end

      def verify_doctor_command!(app_root, env)
        stdout = run_bundle!(
          app_root,
          env,
          "exec",
          "bin/rails",
          "doctor",
          "--environment=production",
          "--format=json",
          "--only=rails.secrets.required_environment_missing"
        )

        results = JSON.parse(stdout)
        result = results.find do |entry|
          entry.fetch("check_id") == "rails.secrets.required_environment_missing"
        end

        valid_response = [
          results.length == 1,
          result,
          result&.fetch("status") == "failed",
          result&.dig("evidence", "missing") == ["API_TOKEN"]
        ].all?

        return if valid_response

        raise RailsDoctor::Error, "Disposable Rails host app returned unexpected JSON from `bin/rails doctor`."
      rescue JSON::ParserError => e
        raise RailsDoctor::Error,
          "Disposable Rails host app did not emit valid JSON from `bin/rails doctor`: #{e.message}"
      end

      def host_dependency_version(name)
        spec = Gem.loaded_specs[name] || Gem::Specification.find_by_name(name)
        spec.version.to_s
      end

      def run_bundle!(app_root, env, *arguments)
        PackageAudit.run_command!(
          env,
          bundle_command(*arguments),
          failure_message: "Disposable Rails host app failed to run `bundle #{arguments.join(" ")}`.",
          chdir: app_root
        )
      end

      def bundle_command(*arguments)
        [Gem.ruby, Gem.bin_path("bundler", "bundle"), *arguments]
      end

      def write_file(app_root, relative_path, contents)
        path = File.join(app_root, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, contents)
      end

      def unpack_built_gem_for_bundler!(app_root, gem_path, installed_spec)
        bundler_gem_path = File.join(app_root, "vendor/gems/rails_doctor")
        FileUtils.rm_rf(bundler_gem_path)
        FileUtils.mkdir_p(bundler_gem_path)
        Gem::Package.new(gem_path).extract_files(bundler_gem_path)
        File.write(File.join(bundler_gem_path, "rails_doctor.gemspec"), installed_spec.to_ruby)
        bundler_gem_path
      end

      def loaded_gem_script
        <<~RUBY
          spec = Gem.loaded_specs.fetch("rails_doctor")
          real_path = File.realpath(spec.full_gem_path)
          abort("loaded gem version mismatch") unless spec.version.to_s == ENV.fetch("EXPECTED_GEM_VERSION")
          abort("loaded gem path does not match unpacked built gem") unless real_path == ENV.fetch("EXPECTED_GEM_PATH")
        RUBY
      end
    end
  end
end
