# Scalability

RailsDoctor scales by registration, not by runtime concurrency. Third-party gems
can add checks without changing central framework files.

Hot path risk is command boot time in large Rails applications. The MVP keeps
checks synchronous and local. Expensive dependency probes are deferred until they
can be timed, configured, and skipped explicitly.
