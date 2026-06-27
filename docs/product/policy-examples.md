# Policy Examples

These example `config/rails_doctor.yml` files are meant to be copied and
adapted, not applied blindly. Each one uses explicit, time-bounded
`suppressions` instead of opaque `exclude_checks` when a deployment topology
intentionally differs from the default Rails expectation.

## Examples

- [Ingress TLS termination](../examples/policies/ingress-tls.yml)
  Use when HTTPS is enforced before Rails and you still want `server` and
  `db:prepare` hooks in production.

- [External asset pipeline](../examples/policies/external-assets.yml)
  Use when assets are compiled in a separate build pipeline and the Rails app
  should treat a missing local manifest as an intentional exception.

- [API-only service behind a gateway](../examples/policies/api-only-gateway.yml)
  Use when the service does not rely on browser sessions, cookies, or compiled
  frontend assets in production.

## Guidance

- Prefer `suppressions` when a check is intentionally inapplicable for a known
  deployment shape.
- Keep `because`, `owner`, and `expires_on` concrete enough that another team
  can re-evaluate the exception later.
- Use `exclude_checks` only when you truly need a blunt escape hatch and cannot
  yet record a reasoned policy.
