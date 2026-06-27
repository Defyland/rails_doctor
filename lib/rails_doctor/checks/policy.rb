# frozen_string_literal: true

RailsDoctor.register "rails_doctor.suppressions.expired" do |check|
  check.severity = :high
  check.description = "Expired suppressions should be renewed or removed before deploy."

  check.run do |context|
    expired = context.rails_doctor_config.suppressions.select(&:expired?)
    next if expired.empty?

    check.fail!(
      "RailsDoctor suppressions have expired",
      hint: "Renew or remove expired suppressions so deployment exceptions stay time-bounded and reviewable.",
      evidence: {
        expired: expired.map(&:to_h)
      }
    )
  end
end

RailsDoctor.register "rails_doctor.suppressions.expiring_soon" do |check|
  check.severity = :warning
  check.description = "Suppressions nearing expiry should be reviewed before they become stale."

  check.run do |context|
    window_days = RailsDoctor::Suppression::EXPIRING_SOON_WINDOW_DAYS
    expiring_soon = context.rails_doctor_config.suppressions
      .select { |suppression| suppression.expiring_within?(window_days) }
    next if expiring_soon.empty?

    check.fail!(
      "RailsDoctor suppressions are nearing expiry",
      hint: "Review or renew suppressions that are due to expire within #{window_days} days so deploy policy stays intentional.",
      evidence: {
        window_days: window_days,
        expiring_soon: expiring_soon.map do |suppression|
          suppression.to_h.merge(days_until_expiry: suppression.days_until_expiry)
        end
      }
    )
  end
end
