# frozen_string_literal: true

module RailsDoctor
  class Check
    attr_reader :id, :severity
    attr_accessor :description

    VALID_SEVERITIES = Result::SEVERITY_RANK.keys.freeze

    def initialize(id)
      @id = String(id)
      self.severity = :medium
      @description = nil
      @run_block = nil
      @results = []
    end

    def run(&block)
      @run_block = block if block
      self
    end

    def severity=(value)
      normalized = value.to_sym
      if VALID_SEVERITIES.include?(normalized)
        @severity = normalized
        return
      end

      raise Error,
        "check #{id} has unsupported severity #{value.inspect}; use #{VALID_SEVERITIES.join(", ")}"
    end

    def execute(context)
      raise Error, "check #{id} has no run block" unless @run_block

      execute_run_block(context)
    end

    def fail!(message, hint:, evidence: {})
      @results << Result.failed(
        check_id: id,
        severity: severity,
        message: message,
        hint: hint,
        evidence: evidence
      )
    end

    private

    def execute_run_block(context)
      @results = []
      if @run_block.arity == 1
        @run_block.call(context)
      else
        instance_exec(&@run_block)
      end
      @results.empty? ? [Result.passed(check_id: id, severity: severity)] : @results
    rescue => error
      @results << crash_result(error: error)
    end

    def crash_result(error:)
      Result.failed(
        check_id: id,
        severity: severity,
        message: "check execution crashed",
        hint: "Handle the exception inside the check or exclude this check until it is deterministic.",
        evidence: {error_class: error.class.name}
      )
    end
  end
end
