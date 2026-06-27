# frozen_string_literal: true

require "date"

module RailsDoctor
  Suppression = Data.define(:check_id, :because, :owner, :expires_on) do
    def self.from(source, source_label: "suppression")
      return source if source.is_a?(self)

      hash = if source.is_a?(Hash)
        source
      elsif source.respond_to?(:to_h)
        source.to_h
      else
        raise Error, "#{source_label} must be a hash"
      end

      check_id = hash["check_id"] || hash[:check_id]
      because = hash["because"] || hash[:because]
      owner = hash["owner"] || hash[:owner]
      expires_on = hash["expires_on"] || hash[:expires_on]

      build(
        check_id: check_id,
        because: because,
        owner: owner,
        expires_on: expires_on,
        source_label: source_label
      )
    end

    def self.build(check_id:, because:, owner:, expires_on:, source_label: "suppression")
      normalized_check_id = check_id.to_s.strip
      normalized_because = because.to_s.strip
      normalized_owner = owner.to_s.strip
      normalized_expires_on = expires_on.to_s.strip

      raise Error, "#{source_label} must include check_id" if normalized_check_id.empty?
      raise Error, "#{source_label} must include because" if normalized_because.empty?
      raise Error, "#{source_label} must include owner" if normalized_owner.empty?
      raise Error, "#{source_label} must include expires_on" if normalized_expires_on.empty?

      parsed_expires_on = Date.iso8601(normalized_expires_on)

      new(
        check_id: normalized_check_id,
        because: normalized_because,
        owner: normalized_owner,
        expires_on: parsed_expires_on.iso8601
      )
    rescue Date::Error
      raise Error, "#{source_label} expires_on must use YYYY-MM-DD"
    end

    def self.normalize_list(source, source_label: "suppressions")
      Array(source).each_with_index.each_with_object({}) do |(entry, index), suppressions|
        suppression = from(entry, source_label: "#{source_label}[#{index}]")
        suppressions[suppression.check_id] = suppression
      end.values
    end

    def expired?(today: Date.today)
      expires_on_date < today
    end

    def active?(today: Date.today)
      !expired?(today: today)
    end

    def expires_on_date
      Date.iso8601(expires_on)
    end

    def days_until_expiry(today: Date.today)
      (expires_on_date - today).to_i
    end

    def expiring_within?(days, today: Date.today)
      active?(today: today) && days_until_expiry(today: today) <= days
    end

    def to_h
      {
        check_id: check_id,
        because: because,
        owner: owner,
        expires_on: expires_on
      }
    end
  end

  Suppression::EXPIRING_SOON_WINDOW_DAYS = 14
end
