# frozen_string_literal: true

require "test_helper"
require "rails_doctor/package_audit"

class RailsDoctorPackagingTest < Minitest::Test
  def test_built_public_docs_do_not_embed_absolute_local_paths
    with_built_package do |gem_path|
      files = RailsDoctor::PackageAudit.package_contents(gem_path)

      RailsDoctor::PackageAudit::PUBLIC_DOCS.each do |path|
        assert_includes files, path
      end

      RailsDoctor::PackageAudit.packaged_public_docs(gem_path) do |docs|
        docs.each_value do |contents|
          refute_match RailsDoctor::PackageAudit::ABSOLUTE_LOCAL_LINK_PATTERN, contents
        end
      end
    end
  end

  private

  def with_built_package(&block)
    RailsDoctor::PackageAudit.with_built_package(root: project_root, &block)
  end

  def project_root
    File.expand_path("../..", __dir__)
  end
end
