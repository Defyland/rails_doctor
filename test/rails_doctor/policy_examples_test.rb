# frozen_string_literal: true

require "json"
require "test_helper"

class RailsDoctorPolicyExamplesTest < Minitest::Test
  include TestSupport

  EXAMPLE_EXPECTATIONS = {
    "api-only-gateway.yml" => %w[
      assets.production_build_missing
      rails.cookies.same_site_not_strict
      rails.session.cookie_flags_weak
    ],
    "external-assets.yml" => %w[assets.production_build_missing],
    "ingress-tls.yml" => %w[rails.production.force_ssl_disabled]
  }.freeze

  def test_policy_examples_load_through_real_policy_file_path
    examples_dir = Pathname(__dir__).join("../../docs/examples/policies").expand_path

    EXAMPLE_EXPECTATIONS.each do |filename, expected_suppressed_ids|
      with_tmp_app do |application, root|
        FileUtils.cp(examples_dir.join(filename), root.join("config/rails_doctor.yml"))

        exit_code, output = RailsDoctor::Runner.new.call(
          application: application,
          environment: "production",
          format: "json"
        )

        assert_equal 0, exit_code

        results = JSON.parse(output)
        suppressed_ids = results
          .select { |entry| entry.fetch("status") == "suppressed" }
          .map { |entry| entry.fetch("check_id") }

        expected_suppressed_ids.each do |check_id|
          assert_includes suppressed_ids, check_id, "#{filename} should suppress #{check_id}"
        end
      end
    end
  end
end
