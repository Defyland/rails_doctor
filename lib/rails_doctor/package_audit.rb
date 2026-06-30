# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "rubygems/installer"
require "rubygems/package"
require "rubygems/user_interaction"
require "shellwords"
require "tmpdir"
require_relative "package_audit/host_app_smoke"

module RailsDoctor
  module PackageAudit
    PUBLIC_DOCS = %w[
      README.md
      docs/contract-versioning.md
      docs/engineering-case-study.md
      docs/architecture/overview.md
      docs/adr/0001-use-railties-command-integration.md
      docs/adr/0002-keep-checks-as-ruby-dsl.md
      docs/adr/0003-use-context-as-inspection-boundary.md
      docs/adr/0004-ship-core-review-docs-in-built-gem.md
    ].freeze
    ABSOLUTE_LOCAL_LINK_PATTERN = %r{\(/Users/}

    module_function

    def verify!(root:)
      with_built_package(root: root) do |gem_path|
        verify_built_package_artifacts!(gem_path)
        HostAppSmoke.verify!(gem_path: gem_path)
      end
    end

    def with_built_package(root:)
      Dir.mktmpdir("rails-doctor-package") do |directory|
        yield build_package(root: root, build_directory: directory)
      end
    end

    def build_package(root:, build_directory:)
      spec_path = File.join(root, "rails_doctor.gemspec")
      spec = Gem::Specification.load(spec_path)
      raise RailsDoctor::Error, "Could not load gemspec at #{spec_path}." unless spec

      isolated_gem_path = File.join(build_directory, "#{spec.full_name}.gem")
      Dir.chdir(root) do
        Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
          Gem::Package.build(spec, false, false, isolated_gem_path)
        end
      end

      isolated_gem_path
    end

    def package_contents(gem_path)
      Gem::Package.new(gem_path).contents
    end

    def packaged_public_docs(gem_path)
      Dir.mktmpdir("rails-doctor-public-docs") do |directory|
        Gem::Package.new(gem_path).extract_files(directory)
        yield PUBLIC_DOCS.to_h { |path| [path, File.read(File.join(directory, path))] }
      end
    end

    def verify_built_package_artifacts!(gem_path)
      contents = package_contents(gem_path)
      missing = PUBLIC_DOCS - contents
      raise RailsDoctor::Error, "Built gem is missing public docs: #{missing.join(", ")}." unless missing.empty?

      packaged_public_docs(gem_path) do |docs|
        offenders = docs.filter_map do |path, contents|
          path if contents.match?(ABSOLUTE_LOCAL_LINK_PATTERN)
        end

        next if offenders.empty?

        raise RailsDoctor::Error, "Built gem contains absolute local links in public docs: #{offenders.join(", ")}."
      end
    end

    def install_built_gem!(gem_path, gem_home)
      Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
        Gem::Installer.at(gem_path, install_dir: gem_home, ignore_dependencies: true, wrappers: false).install
      end
    rescue Gem::InstallError, Gem::Package::FormatError => e
      raise RailsDoctor::Error, "Failed to install built gem into isolated GEM_HOME: #{e.message}"
    end

    def run_command!(env, command, failure_message:, chdir:, allowed_exit_codes: [0])
      stdout, stderr, status = Open3.capture3(execution_env(env, chdir), *command, chdir: chdir)
      return stdout if allowed_exit_codes.include?(status.exitstatus)

      raise RailsDoctor::Error,
        [
          failure_message,
          "Command: #{command.shelljoin}",
          "stdout:\n#{stdout}",
          "stderr:\n#{stderr}"
        ].join("\n\n")
    end

    def sanitized_env
      ENV.to_h.reject { |key, _value| bundler_environment_key?(key) }
    end

    def base_gem_paths
      ([bundler_bundle_path] + Gem.path + [Gem.user_dir] + Gem.default_path).compact.uniq
    end

    def bundler_bundle_path
      return unless defined?(Bundler) && Bundler.respond_to?(:bundle_path)

      Bundler.bundle_path.to_s
    rescue Bundler::BundlerError
      nil
    end

    def bundler_configured_path
      return expanded_bundler_path(ENV.fetch("BUNDLE_PATH")) if ENV["BUNDLE_PATH"]
      return unless defined?(Bundler) && Bundler.respond_to?(:settings)

      path = Bundler.settings[:path]
      expanded_bundler_path(path.to_s) unless path.to_s.empty?
    rescue Bundler::BundlerError
      nil
    end

    def execution_env(env, chdir)
      bundler_unbundled_env.merge(unset_bundler_environment).merge(env).merge("PWD" => chdir)
    end

    def bundler_unbundled_env
      return Bundler.unbundled_env if defined?(Bundler) && Bundler.respond_to?(:unbundled_env)

      ENV.to_h
    end

    def bundler_environment_key?(key)
      key.start_with?("BUNDLE_", "BUNDLER_") || %w[RUBYLIB RUBYOPT].include?(key)
    end

    def unset_bundler_environment
      ENV.keys.select { |key| bundler_environment_key?(key) }.to_h { |key| [key, nil] }
    end

    def expanded_bundler_path(path)
      return path if Pathname(path).absolute?
      return File.expand_path(path, Bundler.root) if defined?(Bundler) && Bundler.respond_to?(:root)

      File.expand_path(path)
    end
  end
end
