# frozen_string_literal: true

require "test_helper"

class RailsDoctorGemspecTest < Minitest::Test
  def test_gemspec_metadata_and_package_files_are_release_ready
    spec = Gem::Specification.load("rails_doctor.gemspec")

    assert_equal RailsDoctor::VERSION, spec.version.to_s
    assert_equal "https://github.com/Defyland/rails_doctor", spec.homepage
    refute_includes spec.email.join(","), "example.com"
    assert_equal "true", spec.metadata.fetch("rubygems_mfa_required")
    assert_equal "https://rubygems.org", spec.metadata.fetch("allowed_push_host")
    assert_equal "#{spec.homepage}/issues", spec.metadata.fetch("bug_tracker_uri")
    assert_equal "#{spec.homepage}#readme", spec.metadata.fetch("documentation_uri")

    assert_includes spec.files, "README.md"
    assert_includes spec.files, "LICENSE.txt"
    assert_includes spec.files, "docs/contract-versioning.md"
    assert_includes spec.files, "lib/rails_doctor.rb"
    assert_includes spec.files, "lib/rails/commands/doctor/doctor_command.rb"
    refute_includes spec.files, "Gemfile.lock"
    refute spec.files.any? { |file| file.start_with?("lib/rails_doctor/package_audit") }
    refute spec.files.any? { |file| file.start_with?(".github/", "gemfiles/", "pkg/", "test/") }
  end
end
