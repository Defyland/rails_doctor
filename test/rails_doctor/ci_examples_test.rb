# frozen_string_literal: true

require "test_helper"
require "yaml"

class RailsDoctorCiExamplesTest < Minitest::Test
  def test_deploy_gate_example_uses_github_actions_format_and_json_artifact_export
    workflow = load_workflow("deploy-gate.yml")
    run_steps = workflow.dig("jobs", "doctor", "steps").filter_map { |step| step["run"] }

    assert_includes run_steps, "bin/rails doctor --environment=production --fail-on warning --format=github-actions"
    assert_includes run_steps, "bin/rails doctor --environment=production --report=suppressions --format=json > tmp/rails_doctor_suppressions.json"
  end

  def test_scheduled_suppression_audit_example_uses_github_actions_annotations
    workflow = load_workflow("suppression-audit.yml")
    run_steps = workflow.dig("jobs", "suppression-audit", "steps").filter_map { |step| step["run"] }

    assert workflow.fetch("on").key?("schedule")
    assert workflow.fetch("on").key?("workflow_dispatch")
    assert_includes run_steps, "bin/rails doctor --environment=production --report=suppressions --format=github-actions"
    assert_includes run_steps, "bin/rails doctor --environment=production --report=suppressions --format=json > tmp/rails_doctor_suppressions.json"
  end

  private

  def load_workflow(name)
    path = Pathname(__dir__).join("../../docs/examples/github-actions/#{name}").expand_path
    YAML.safe_load(path.read)
  end
end
