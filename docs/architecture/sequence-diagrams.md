# Sequence Diagrams

```text
User -> Rails command: bin/rails doctor --format=json
Rails command -> Runner: call(application, options)
Runner -> Registry: run(context)
Registry -> Check: execute(context)
Check -> Result: failed/passed
Runner -> Reporter: render(results, context redaction policy)
Reporter -> User: text/json
```
