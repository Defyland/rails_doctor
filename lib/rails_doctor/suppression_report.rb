# frozen_string_literal: true

require "time"

module RailsDoctor
  class SuppressionReport
    STATUS_RANK = {
      expired: 0,
      expiring_soon: 1,
      active: 2
    }.freeze

    Entry = Data.define(:check_id, :because, :owner, :expires_on, :days_until_expiry, :status) do
      def to_h
        {
          check_id: check_id,
          because: because,
          owner: owner,
          expires_on: expires_on,
          days_until_expiry: days_until_expiry,
          status: status
        }
      end
    end

    attr_reader :environment, :generated_at, :suppressions, :window_days

    def self.build(
      suppressions,
      environment:,
      today: Date.today,
      generated_at: Time.now.utc,
      window_days: Suppression::EXPIRING_SOON_WINDOW_DAYS
    )
      normalized_suppressions = Suppression.normalize_list(suppressions)
      entries = normalized_suppressions.map do |suppression|
        Entry.new(
          check_id: suppression.check_id,
          because: suppression.because,
          owner: suppression.owner,
          expires_on: suppression.expires_on,
          days_until_expiry: suppression.days_until_expiry(today: today),
          status: status_for(suppression, today: today, window_days: window_days)
        )
      end.sort_by { |entry| [STATUS_RANK.fetch(entry.status), entry.days_until_expiry, entry.check_id] }

      new(
        environment: environment,
        generated_at: generated_at.utc.iso8601,
        window_days: window_days,
        suppressions: entries
      )
    end

    def self.status_for(suppression, today:, window_days:)
      return :expired if suppression.expired?(today: today)
      return :expiring_soon if suppression.expiring_within?(window_days, today: today)

      :active
    end

    def initialize(environment:, generated_at:, window_days:, suppressions:)
      @environment = environment.to_s
      @generated_at = generated_at
      @window_days = window_days
      @suppressions = suppressions
    end

    def to_h
      {
        environment: environment,
        generated_at: generated_at,
        window_days: window_days,
        suppressions: suppressions.map(&:to_h)
      }
    end
  end
end
