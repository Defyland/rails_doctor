# frozen_string_literal: true

require_relative "lib/rails_doctor/version"

Gem::Specification.new do |spec|
  spec.name = "rails_doctor"
  spec.version = RailsDoctor::VERSION
  spec.authors = ["Allan Flavio"]
  spec.email = ["Defyland@users.noreply.github.com"]

  spec.summary = "Extensible diagnostic checks for Rails applications."
  spec.description = "RailsDoctor provides a bin/rails doctor command and a registry for framework and gem-specific Rails health checks."
  spec.homepage = "https://github.com/Defyland/rails_doctor"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "#{spec.homepage}#readme"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "README.md",
    "LICENSE.txt",
    "docs/contract-versioning.md",
    "docs/engineering-case-study.md",
    "docs/architecture/overview.md",
    "docs/adr/*.md",
    "lib/**/*.rb"
  ].sort.reject do |file|
    file.start_with?("lib/rails_doctor/package_audit")
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.1", "< 9.0"
end
