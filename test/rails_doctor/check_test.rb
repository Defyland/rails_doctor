# frozen_string_literal: true

require "test_helper"

class RailsDoctorCheckTest < Minitest::Test
  include TestSupport

  def test_check_dsl_supports_user_supplied_result
    check = RailsDoctor::Check.new("database.pool.too_small")
    check.severity = :high
    check.run do
      check.fail!("Database pool is smaller than Puma thread count", hint: "Set pool >= RAILS_MAX_THREADS")
    end

    results = check.execute(Object.new)

    assert_equal 1, results.length
    assert_equal :failed, results.first.status
    assert_equal :high, results.first.severity
  end

  def test_check_without_failure_returns_passed_result
    check = RailsDoctor::Check.new("ok")
    check.run {}

    result = check.execute(Object.new).first

    assert_equal :passed, result.status
    assert_equal "ok", result.check_id
  end

  def test_check_rejects_unsupported_severity
    check = RailsDoctor::Check.new("custom.invalid_severity")

    error = assert_raises(RailsDoctor::Error) do
      check.severity = :urgent
    end

    assert_equal "check custom.invalid_severity has unsupported severity :urgent; use low, warning, medium, high, critical", error.message
  end

  def test_check_returns_failed_result_when_execution_crashes
    check = RailsDoctor::Check.new("custom.crashing_check")
    check.severity = :high
    check.run { raise StandardError, "super-secret boom" }

    result = check.execute(Object.new).first

    assert_equal :failed, result.status
    assert_equal "check execution crashed", result.message
    assert_equal "StandardError", result.evidence[:error_class]
    refute_includes result.to_h.to_s, "super-secret boom"
  end

  def test_check_isolates_rails_doctor_errors_raised_inside_run_blocks
    check = RailsDoctor::Check.new("custom.internal_error")
    check.severity = :medium
    check.run { raise RailsDoctor::Error, "boom" }

    result = check.execute(Object.new).first

    assert_equal :failed, result.status
    assert_equal "RailsDoctor::Error", result.evidence[:error_class]
  end
end
