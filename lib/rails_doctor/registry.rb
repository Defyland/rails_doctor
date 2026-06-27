# frozen_string_literal: true

module RailsDoctor
  class Registry
    include Enumerable

    VALID_ID_SEGMENT_PATTERN = /[a-z0-9]+(?:_[a-z0-9]+)*/
    VALID_ID_PATTERN = /\A#{VALID_ID_SEGMENT_PATTERN}(?:\.#{VALID_ID_SEGMENT_PATTERN})*\z/

    def initialize
      @checks = {}
    end

    def register(id)
      normalized_id = String(id)
      validate_id!(normalized_id)
      raise Error, "check #{normalized_id} is already registered" if @checks.key?(normalized_id)

      check = Check.new(normalized_id)
      yield check
      @checks[normalized_id] = check
    end

    def each(&block)
      @checks.values.each(&block)
    end

    def fetch(id)
      @checks.fetch(String(id))
    end

    def run(context, only: nil, exclude: nil, suppressions: [])
      selection = selected_checks(only: only, exclude: exclude, suppressions: suppressions)
      selection[:runnable_checks].flat_map { |check| check.execute(context) } + selection[:suppressed_results]
    end

    def size
      @checks.size
    end

    private

    def selected_checks(only:, exclude:, suppressions:)
      raise Error, "no checks are registered" if @checks.empty?

      only_ids = only.nil? ? nil : normalize_ids(only)
      exclude_ids = normalize_ids(exclude)
      suppression_map = normalize_suppressions(suppressions)
      active_suppression_map = suppression_map.reject { |_id, suppression| suppression.expired? }
      validate_known_ids!((only_ids || []) + exclude_ids + suppression_map.keys)

      checks = @checks.values
      checks = checks.select { |check| only_ids.include?(check.id) } unless only_ids.nil?
      checks = checks.reject { |check| exclude_ids.include?(check.id) }
      suppressed_checks, runnable_checks = checks.partition { |check| active_suppression_map.key?(check.id) }

      validate_non_empty_selection!(
        runnable_checks,
        suppressed_checks,
        only_ids: only_ids,
        exclude_ids: exclude_ids,
        suppression_ids: suppression_map.keys
      )

      {
        runnable_checks: runnable_checks,
        suppressed_results: suppressed_checks.map do |check|
          Result.suppressed(
            check_id: check.id,
            severity: check.severity,
            because: active_suppression_map.fetch(check.id).because,
            owner: active_suppression_map.fetch(check.id).owner,
            expires_on: active_suppression_map.fetch(check.id).expires_on
          )
        end
      }
    end

    def normalize_ids(value)
      Array(value)
        .flat_map { |entry| entry.to_s.split(",") }
        .map(&:strip)
        .reject(&:empty?)
        .uniq
    end

    def validate_known_ids!(ids)
      unknown_ids = ids.reject { |id| @checks.key?(id) }
      return if unknown_ids.empty?

      raise Error, "unknown check ids: #{unknown_ids.join(", ")}"
    end

    def normalize_suppressions(value)
      Suppression.normalize_list(value).each_with_object({}) do |suppression, suppressions|
        suppressions[suppression.check_id] = suppression
      end
    end

    def validate_id!(id)
      return if id.match?(VALID_ID_PATTERN)

      raise Error,
        "check id #{id.inspect} is invalid; use lowercase dot-separated segments with optional underscores"
    end

    def validate_non_empty_selection!(runnable_checks, suppressed_checks, only_ids:, exclude_ids:, suppression_ids:)
      return if runnable_checks.any? || suppressed_checks.any?

      details = []
      details << if only_ids.nil?
        nil
      elsif only_ids.empty?
        "only=(empty intersection)"
      else
        "only=#{only_ids.join(",")}"
      end
      details << "exclude=#{exclude_ids.join(",")}" unless exclude_ids.empty?
      details << "suppressed=#{suppression_ids.join(",")}" unless suppression_ids.empty?
      suffix = details.compact.empty? ? "" : ": #{details.compact.join(" ")}"

      raise Error, "no checks selected after applying filters#{suffix}"
    end
  end
end
