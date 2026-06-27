# frozen_string_literal: true

RailsDoctor.register "readiness.configured_probes_failing" do |check|
  check.severity = :high
  check.description = "Configured dependency readiness probes should pass before deploys."

  check.run do |context|
    context.dependency_probes.each do |name, probe|
      probe.call(context)
    rescue RailsDoctor::ProbeFailure => error
      check.fail!(
        "dependency readiness probe failed for #{name}",
        hint: error.hint,
        evidence: error.evidence.merge(probe: name)
      )
    rescue => error
      check.fail!(
        "dependency readiness probe crashed for #{name}",
        hint: "Handle the probe exception or remove the probe until it is deterministic.",
        evidence: {
          probe: name,
          error_class: error.class.name,
          error_message: error.message
        }
      )
    end
  end
end
