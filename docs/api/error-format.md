# Error Format

JSON output uses this shape:

```json
{
  "check_id": "database.pool.too_small",
  "severity": "high",
  "status": "failed",
  "message": "Database pool is smaller than Puma thread count",
  "hint": "Set pool >= RAILS_MAX_THREADS for each web process.",
  "evidence": {
    "database_pool": 2,
    "database_pool_source": "ENV[DB_POOL]",
    "puma_threads": 5,
    "puma_threads_source": "ENV[RAILS_MAX_THREADS]"
  }
}
```
