# ADR 0003: Use Context As Inspection Boundary

## Status

Accepted.

## Context

Built-in checks need access to Rails app state, but direct constant access makes
tests brittle and couples optional frameworks.

## Decision

Expose application, config, root files, environment, loaded gems, and constants
through `RailsDoctor::Context`.

## Consequences

- Checks are easier to test with fake applications.
- Optional Rails components can be skipped when absent.
- Context can later become the policy point for redaction and suppression.
