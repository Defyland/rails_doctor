# ADR 0001: Use Railties Command Integration

## Status

Accepted.

## Context

The product surface is `bin/rails doctor`, not a standalone executable. Rails
commands are discovered through files under `rails/commands`.

## Decision

Ship `lib/rails/commands/doctor/doctor_command.rb` and use `Rails::Command::Base`
to call `RailsDoctor::Runner`.

## Consequences

- The command lives where Rails expects command extensions.
- The gem can inspect a booted Rails application.
- Integration must be verified with a dummy Rails app before release.
