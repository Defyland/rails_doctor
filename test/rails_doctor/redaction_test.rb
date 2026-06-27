# frozen_string_literal: true

require "test_helper"

class RailsDoctorRedactionTest < Minitest::Test
  def test_failed_result_redacts_sensitive_text_and_sensitive_evidence_keys
    result = RailsDoctor::Result.failed(
      check_id: "custom.failure",
      severity: :high,
      message: "redis://user:super-secret@cache.local/0 token=abc123",
      hint: "Authorization: Bearer bearer-secret and password='hunter2'",
      evidence: {
        error_message: "redis://user:super-secret@cache.local/0?token=abc123",
        authorization: "Bearer bearer-secret",
        nested: {
          database_url: "postgres://user:db-secret@db.local/app",
          safe: "connection refused"
        }
      }
    )

    serialized = result.to_h.to_s

    refute_includes serialized, "super-secret"
    refute_includes serialized, "abc123"
    refute_includes serialized, "bearer-secret"
    refute_includes serialized, "hunter2"
    refute_includes serialized, "db-secret"
    assert_includes result.message, "[REDACTED]"
    assert_equal "[REDACTED]", result.evidence[:authorization]
    assert_equal "[REDACTED]", result.evidence[:nested][:database_url]
    assert_equal "connection refused", result.evidence[:nested][:safe]
  end

  def test_probe_failure_redacts_message_hint_and_evidence
    failure = RailsDoctor::ProbeFailure.new(
      "redis auth failed for redis://user:super-secret@cache.local/0",
      hint: "Rotate token=abc123 and Authorization: Bearer bearer-secret",
      evidence: {
        error_message: "password=hunter2",
        redis_url: "redis://user:super-secret@cache.local/0"
      }
    )

    serialized = {message: failure.message, hint: failure.hint, evidence: failure.evidence}.to_s

    refute_includes serialized, "super-secret"
    refute_includes serialized, "abc123"
    refute_includes serialized, "bearer-secret"
    refute_includes serialized, "hunter2"
    assert_equal "[REDACTED]", failure.evidence[:redis_url]
  end
end
