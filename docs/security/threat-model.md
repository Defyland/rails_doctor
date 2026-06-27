# Threat Model

## Assets

- Rails secrets and credentials.
- Deployment configuration.
- CI logs that may contain doctor output.

## Actors

- Application engineers.
- CI systems.
- Attackers with access to logs.

## Trust Boundaries

- RailsDoctor runs inside the application process.
- Output crosses into terminal, CI logs, and deploy systems.

## Controls

- Built-in checks avoid printing raw secret values.
- Evidence should prefer names, booleans, and lengths over sensitive content.
- JSON output allows policy systems to enforce failures without scraping prose.

## Residual Risks

- Third-party checks can accidentally print secrets.
- False positives can cause deploy friction.
- False negatives can create misplaced confidence.
