# Invariants

- Check IDs are unique and use lowercase dot-separated segments with optional underscores.
- Check severity must be one of `low`, `warning`, `medium`, `high`, or `critical`.
- Failed results include a message and hint.
- Result severity must be rankable.
- Checks should not mutate application state.
