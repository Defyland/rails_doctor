# ADR 0002: Keep Checks As Ruby DSL

## Status

Accepted.

## Context

The project could model checks as YAML rules, a policy engine, or direct Ruby
objects. Rails configuration is Ruby and many useful diagnostics need Ruby code.

## Decision

Use a small Ruby DSL around `RailsDoctor.register`.

## Consequences

- Third-party gems can register checks without central coordination.
- Checks can inspect Rails configuration, files, environment, and loaded gems.
- The framework must keep results structured so Ruby flexibility does not become
  untestable prose.
