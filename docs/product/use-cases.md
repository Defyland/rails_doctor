# Use Cases

- Run `bin/rails doctor --environment=production` before deploy.
- Gate `bin/rails server`, `bin/rails db:migrate`, `bin/rails db:prepare`, `bin/rails db:schema:load`, `bin/rails db:structure:load`, or `bin/rails assets:precompile` with the same checks when a workflow needs an implicit safety bar.
- Fail CI when warnings or higher are detected.
- Emit JSON for deployment dashboards.
- Let a gem register checks for its own configuration.
- Record intentional exceptions with a stable check ID, explicit reason, owner, and expiry.
- Warn before a time-bounded suppression expires and silently becomes stale.
- Distinguish in automation between failed checks and suppressed policy exceptions.
