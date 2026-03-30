# Benchmark Results

This directory stores structured benchmark results for regression tracking.

## Files

- **baseline.json** -- Current accepted performance baseline. Updated via `make bench-baseline`.
- **\<commit-sha\>.json** -- Per-commit results saved via `make bench-save`.

## JSON Schema (v1)

```json
{
  "version": 1,
  "timestamp": "2026-03-30T12:00:00Z",
  "git_commit": "abc1234",
  "system": { "os": "linux", "arch": "x86_64" },
  "tiers": [
    {
      "name": "10K",
      "message_count": 10000,
      "attr_count": 2,
      "discard_ops_sec": 100000000,
      "text_ops_sec": 5000000,
      "json_ops_sec": 3000000,
      "discard_ns_op": 10,
      "text_ns_op": 200,
      "json_ns_op": 333,
      "logger_disabled_ns": 2,
      "logger_enabled_ns": 15,
      "multi_handler_ns": 12,
      "multi_handler_ops_sec": 83333333,
      "async_enqueue_ns": 50,
      "async_enqueue_ops_sec": 20000000,
      "rfc3339_ns": 25,
      "queued_record_ns": 100,
      "sensitive_key_ns": 15
    }
  ]
}
```

## Metrics

| Metric | Unit | Direction |
|--------|------|-----------|
| discard_ops_sec | ops/sec | Higher is better |
| text_ops_sec | ops/sec | Higher is better |
| json_ops_sec | ops/sec | Higher is better |
| discard_ns_op | ns/op | Lower is better |
| text_ns_op | ns/op | Lower is better |
| json_ns_op | ns/op | Lower is better |
| logger_disabled_ns | ns/op | Lower is better |
| logger_enabled_ns | ns/op | Lower is better |
| multi_handler_ns | ns/op | Lower is better |
| multi_handler_ops_sec | ops/sec | Higher is better |
| async_enqueue_ns | ns/op | Lower is better |
| async_enqueue_ops_sec | ops/sec | Higher is better |
| rfc3339_ns | ns/op | Lower is better |
| queued_record_ns | ns/op | Lower is better |
| sensitive_key_ns | ns/op | Lower is better |

## Workflow

```bash
make bench-baseline     # Save current as baseline
make bench-save         # Save to <commit-sha>.json
make bench-compare      # Run and compare against baseline (20% threshold)
make scale-bench        # Run and view results (no save)
```
