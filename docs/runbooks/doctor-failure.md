# Runbook: Doctor Failure

1. Read the failed check ID.
2. Inspect `message`, `hint`, and `evidence`.
3. If the failure came from a command hook before `server`, `db:migrate`, `db:prepare`, `db:schema:load`, `db:structure:load`, or `assets:precompile`,
   re-run `bin/rails doctor` explicitly with the same environment to inspect the
   full result set and any hook-specific filters.
4. Fix the application configuration or document an explicit exception.
5. Re-run `bin/rails doctor --environment=production --fail-on warning`.
6. If the check is a known false positive, prefer a structured suppression with
   a reason in `config.x.rails_doctor.suppress(...)` or
   `config/rails_doctor.yml`. Record `owner` and `expires_on`. Use
   `exclude_checks` only as a short-term escape hatch when you cannot yet
   record the policy cleanly.
7. Verify the command now reports that check as `suppressed` instead of making
   it disappear silently.
8. If `rails_doctor.suppressions.expiring_soon` fails, review the exception
   before it goes stale: either renew it intentionally or remove it and fix the
   underlying application issue. Use
   `bin/rails doctor --environment=production --report=suppressions --format=json`
   when you need the full suppression inventory instead of only failing checks.
9. If `rails_doctor.suppressions.expired` fails, renew or remove the stale
   suppression before suppressing the original check again.
10. If the check still looks wrong, open an issue with evidence and deployment
    topology.
