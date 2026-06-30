# ADR 0004: Ship Core Review Docs In Built Gem

## Status

Accepted.

## Context

RailsDoctor already documents its product rationale, architecture overview, and
core framework decisions in the repository. A reviewer or future maintainer who
only inspects the built gem currently loses that material, even though the
package audit already treats public docs as part of release truth.

## Decision

Ship a curated review-doc set inside the built gem:

- `README.md`
- `docs/contract-versioning.md`
- `docs/engineering-case-study.md`
- `docs/architecture/overview.md`
- `docs/adr/*.md`

Keep broader product, domain, and internal study docs in the repository unless
they become part of the public release contract.

## Consequences

- The built gem now teaches the core product and architecture story directly.
- Package verification must fail if those review docs disappear or contain
  local-only links.
- The release artifact stays curated instead of sweeping every repository doc
  into the gem.
