# frozen_string_literal: true

require "test_helper"

class RailsDoctorRegistryTest < Minitest::Test
  def test_registry_rejects_duplicate_check_ids
    registry = RailsDoctor::Registry.new
    registry.register("duplicate") { |check| check.run {} }

    error = assert_raises(RailsDoctor::Error) do
      registry.register("duplicate") { |check| check.run {} }
    end

    assert_match(/already registered/, error.message)
  end

  def test_registry_rejects_invalid_check_ids
    registry = RailsDoctor::Registry.new

    error = assert_raises(RailsDoctor::Error) do
      registry.register("Invalid-Check") { |check| check.run {} }
    end

    assert_equal(
      'check id "Invalid-Check" is invalid; use lowercase dot-separated segments with optional underscores',
      error.message
    )
  end

  def test_registry_runs_registered_checks
    registry = RailsDoctor::Registry.new
    registry.register("one") { |check| check.run {} }
    registry.register("two") { |check| check.run {} }

    assert_equal %w[one two], registry.run(Object.new).map(&:check_id)
  end

  def test_registry_rejects_unknown_filters
    registry = RailsDoctor::Registry.new
    registry.register("one") { |check| check.run {} }

    error = assert_raises(RailsDoctor::Error) do
      registry.run(Object.new, only: "missing")
    end

    assert_match(/unknown check ids/, error.message)
  end

  def test_registry_rejects_empty_selection_after_filters
    registry = RailsDoctor::Registry.new
    registry.register("one") { |check| check.run {} }

    error = assert_raises(RailsDoctor::Error) do
      registry.run(Object.new, only: [], exclude: "one")
    end

    assert_equal "no checks selected after applying filters: only=(empty intersection) exclude=one", error.message
  end

  def test_registry_returns_suppressed_results_for_suppressed_checks
    registry = RailsDoctor::Registry.new
    registry.register("one") do |check|
      check.severity = :high
      check.run {}
    end

    result = registry.run(
      Object.new,
      suppressions: [
        RailsDoctor::Suppression.new(
          check_id: "one",
          because: "handled upstream",
          owner: "platform@example.com",
          expires_on: "2099-12-31"
        )
      ]
    ).first

    assert_equal :suppressed, result.status
    assert_equal :high, result.severity
    assert_equal "handled upstream", result.evidence[:because]
  end

  def test_registry_allows_suppressed_only_selection
    registry = RailsDoctor::Registry.new
    registry.register("one") { |check| check.run {} }

    results = registry.run(
      Object.new,
      only: "one",
      suppressions: [
        RailsDoctor::Suppression.new(
          check_id: "one",
          because: "handled upstream",
          owner: "platform@example.com",
          expires_on: "2099-12-31"
        )
      ]
    )

    assert_equal 1, results.length
    assert_equal :suppressed, results.first.status
  end

  def test_registry_does_not_suppress_expired_suppressions
    registry = RailsDoctor::Registry.new
    registry.register("one") { |check| check.run {} }

    result = registry.run(
      Object.new,
      suppressions: [
        RailsDoctor::Suppression.new(
          check_id: "one",
          because: "handled upstream",
          owner: "platform@example.com",
          expires_on: "2000-01-01"
        )
      ]
    ).first

    assert_equal :passed, result.status
  end

  def test_registry_rejects_running_without_registered_checks
    error = assert_raises(RailsDoctor::Error) do
      RailsDoctor::Registry.new.run(Object.new)
    end

    assert_equal "no checks are registered", error.message
  end
end
