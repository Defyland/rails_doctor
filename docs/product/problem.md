# Problem

Rails applications often discover deployment misconfiguration after boot:
database pool mismatch, missing mailer host, weak secrets, unsafe production
defaults, missing assets, local storage, or queue adapters that drop jobs.

`/up` proves the application booted. It does not prove the application is ready.
RailsDoctor fills that gap with explicit, extensible diagnostics.
