# Contract Versioning

RailsDoctor is a diagnostic gem, but its public surface is broader than Ruby
constants alone. CI gates, deployment hooks, and cheap-model tooling depend on
stable command behavior and stable result identifiers.

## Stable Public Surfaces

These surfaces are treated as intentional product contract:

- check IDs such as `database.pool.too_small`;
- severity and status vocabulary such as `high`, `critical`, `failed`, and
  `suppressed`;
- JSON result shape emitted by `--format=json`;
- GitHub Actions reporter intent for `--format=github-actions`;
- the `bin/rails doctor` command family, including
  `--report=suppressions`, `--only`, `--exclude`, and `--fail-on`;
- documented configuration keys under `config.x.rails_doctor` and
  `config/rails_doctor.yml`.

## Release Rules

Patch releases may:

- fix incorrect findings, hints, or redaction;
- improve docs, examples, and package verification;
- add internal refactors that do not rename or remove public fields;
- tighten secret redaction, even if rendered output becomes more masked.

Minor releases may:

- add new built-in checks;
- add new optional evidence keys or report metadata;
- add new probe helpers, CLI options, or documented configuration keys.

Minor releases can surface new findings in existing apps. Release notes should
call out every new check ID and any new default severity that can affect CI or
deploy hooks.

Major releases are required for:

- renaming or removing a released check ID;
- changing severity or status vocabulary incompatibly;
- removing or incompatibly reshaping JSON or suppression-report fields;
- removing documented CLI flags or configuration keys;
- dropping supported Ruby or Rails ranges.

## Packaging Rule

The built gem must ship the README and this contract note. Release verification
must prove the packaged artifact, not only the checkout:

1. build the gem in isolation;
2. validate packaged public docs;
3. boot a disposable Rails app against the built gem;
4. run `bin/rails doctor` successfully from that app.
