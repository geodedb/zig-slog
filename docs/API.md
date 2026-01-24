# API Reference

This document provides an overview of the slog API. For full documentation, generate the autodocs using `zig build docs`.

## Quick Reference

### Main Module: `slog`

```zig
const slog = @import("slog");
```

### Core Types

| Type | Description |
|------|-------------|
| `Logger` | Main logging interface with level methods |
| `Handler` | Interface for log output destinations |
| `Record` | Complete log event with metadata and attributes |
| `Level` | Log severity (trace, debug, info, warn, error, fatal) |
| `Attr` | Key-value attribute for structured data |
| `Value` | Union of supported attribute value types |
| `Clock` | Time source for timestamps |

### Logger API

```zig
// Create a logger with a handler
const logger = slog.Logger.init(handler, .info, slog.Clock.system());

// Create named child logger
const app_logger = logger.named("myapp");

// Add context attributes
const request_logger = logger.with(&.{
    slog.Attr.string("request_id", "abc123"),
});

// Add attribute key prefix (grouping)
const db_logger = logger.withGroup("database");

// Add translation support
const i18n_logger = logger.withTranslator("es", catalog.translator());
```

### Log Methods

| Method | Level | Description |
|--------|-------|-------------|
| `trace(msg_id, attrs)` | -8 | Fine-grained debugging |
| `debug(msg_id, attrs)` | -4 | Development debugging |
| `info(msg_id, attrs)` | 0 | Normal operational messages |
| `warn(msg_id, attrs)` | 4 | Warning conditions |
| `error(msg_id, attrs)` | 8 | Error conditions |
| `fatal(msg_id, attrs)` | 12 | Fatal errors (triggers fatal_hook) |

```zig
try logger.info("Request processed", &.{
    slog.Attr.string("method", "GET"),
    slog.Attr.int("status", 200),
    slog.Attr.float("duration_ms", 12.5),
});
```

### Attribute Types

```zig
const attrs = &.{
    slog.Attr.string("key", "value"),        // String
    slog.Attr.int("count", -42),             // i64
    slog.Attr.uint("size", 1024),            // u64
    slog.Attr.float("ratio", 0.95),          // f64
    slog.Attr.boolean("enabled", true),      // bool
    slog.Attr.bytes("data", &[_]u8{0xDE, 0xAD}), // []const u8 (hex encoded)
    slog.Attr.err("error", error.NotFound),  // anyerror
    slog.Attr.secret("api_key", "sk-xxx"),   // Redacted in output
    slog.Attr.duration("elapsed", 1500000),  // Nanoseconds
};
```

## Handlers

### Text Handler

Human-readable log format:

```zig
var ctx = slog.text.Context.init(
    writer.any(),
    .info,        // Minimum level
    slog.Clock.system(),
);
const handler = slog.text.init(&ctx);
```

Output format:
```
2025-01-02T03:04:05.000000Z INFO myapp Message key=value count=42
```

### JSON Handler

Structured JSON output with stable key order:

```zig
var ctx = slog.json.Context.init(
    writer.any(),
    .info,
    slog.Clock.system(),
);
const handler = slog.json.init(&ctx);
```

Output format:
```json
{"time":"2025-01-02T03:04:05.000000Z","level":"INFO","msg":"Message","logger":"myapp","attrs":{"key":"value","count":42}}
```

### Rotating File Handler

Size-based rotation with backup management:

```zig
var ctx = try slog.rotating_file.Context.init(allocator, .{
    .path = "/var/log/app.log",
    .max_bytes = 10 * 1024 * 1024,  // 10MB
    .max_backups = 5,               // Keep 5 rotated files
    .max_age_days = 30,             // Delete files older than 30 days
}, .info, slog.Clock.system());
defer ctx.deinit();

const handler = slog.rotating_file.init(&ctx);
```

### Async Handler

Background thread delivery with bounded queue:

```zig
var async_ctx = try slog.async_handler.Context.init(allocator, .{
    .inner = inner_handler,
    .queue_size = 1024,         // Buffer capacity
    .drop_oldest = true,        // Drop oldest on overflow (vs block)
    .block_timeout_ms = 0,      // 0 = non-blocking
});
defer async_ctx.deinit();

const handler = slog.async_handler.init(&async_ctx);

// Get dropped count
const dropped = slog.async_handler.getDroppedCount(handler);
```

### Syslog RFC5424 Handler

```zig
var ctx = slog.syslog.Context.init(writer.any(), .info, slog.Clock.system(), .{
    .facility = .local0,
    .hostname = "myhost",
    .app_name = "myapp",
    .procid = 1234,
});
const handler = slog.syslog.init(&ctx);
```

### Discard Handler

For benchmarking or disabling logging:

```zig
const handler = slog.discardHandler();
```

## Network Sinks

### TCP Sink

```zig
var tcp_ctx = slog.tcp_sink.Context.init(allocator, .{
    .host = "127.0.0.1",
    .port = 5514,
    .connect_timeout_ms = 5000,
    .max_retries = 3,
    .initial_backoff_ms = 100,
    .max_backoff_ms = 5000,
}, .info, slog.Clock.system());
defer tcp_ctx.deinit();

const handler = slog.tcp_sink.init(&tcp_ctx);
```

### UDP Sink

```zig
var udp_ctx = slog.udp_sink.Context.init(allocator, .{
    .host = "127.0.0.1",
    .port = 5514,
}, .info, slog.Clock.system());
defer udp_ctx.deinit();

const handler = slog.udp_sink.init(&udp_ctx);
```

### HTTP Sink

```zig
var http_ctx = slog.http_sink.Context.init(allocator, .{
    .url = "http://localhost:8080/logs",
    .method = .POST,
    .headers = &.{
        .{ .name = "Content-Type", .value = "application/json" },
    },
    .timeout_ms = 5000,
    .max_retries = 3,
}, .info, slog.Clock.system());
defer http_ctx.deinit();

const handler = slog.http_sink.init(&http_ctx);
```

## Metrics

### Simple Metrics

```zig
const m = slog.getMetrics();
std.debug.print("Bytes: {d}, Records: {d}\n", .{
    m.bytes_written,
    m.records_emitted,
});
```

### Full Metrics Snapshot

```zig
const snap = slog.metrics.global.snapshot();
// snap.logs_emitted_total
// snap.logs_dropped_total
// snap.handler_errors_total
// snap.bytes_written_total
// snap.queue_size
// snap.rotations_total
// snap.reconnections_total
```

### Prometheus Export

```zig
var buf: [4096]u8 = undefined;
const output = slog.exportPrometheusMetrics(&buf);
// Returns Prometheus text format metrics
```

## i18n Support

```zig
const json =
    \\{
    \\  "es": { "app.started": "aplicacion iniciada" },
    \\  "de": { "app.started": "Anwendung gestartet" }
    \\}
;

var catalog = try slog.i18n.Catalog.fromJson(allocator, json);
defer catalog.deinit();

const logger = base_logger.withTranslator("es", catalog.translator());
try logger.info("app.started", &.{});  // Logs "aplicacion iniciada"
```

## Handler Interface

To implement a custom handler:

```zig
const HandlerVTable = struct {
    handle: *const fn (ctx: *anyopaque, rec: *const Record) HandlerError!void,
    withAttrs: *const fn (ctx: *anyopaque, addl: []const Attr) Handler,
    withGroup: *const fn (ctx: *anyopaque, prefix: []const u8) Handler,
    setLevel: *const fn (ctx: *anyopaque, level: Level) void,
    flush: *const fn (ctx: *anyopaque, timeout_ms: u32) HandlerError!void,
    getLevel: ?*const fn (ctx: *anyopaque) Level = null,
    close: ?*const fn (ctx: *anyopaque) void = null,
};
```

## Error Types

### HandlerError

```zig
pub const HandlerError = error{
    WriteFailed,
    FlushFailed,
    ConnectionFailed,
    Timeout,
    BufferFull,
    InvalidRecord,
    FeatureDisabled,
    OutOfMemory,
};
```

### RecordError

```zig
pub const RecordError = error{
    RecordTooLarge,    // Exceeds MAX_RECORD_SIZE (64KB)
    TooManyAttrs,      // Exceeds MAX_ATTRS (64)
    InvalidNumber,
    InvalidUtf8,
    OutputFull,
};
```

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_ATTRS` | 64 | Maximum attributes per record |
| `MAX_RECORD_SIZE` | 64KB | Maximum serialized record size |

## Convenience Functions

```zig
// Stderr text handler
const result = slog.stderrHandler(.info);
// result.ctx, result.handler

// Stderr JSON handler
const result = slog.stderrJsonHandler(.info);

// Discard handler
const handler = slog.discardHandler();
```

## Generating Full Documentation

```bash
# Generate HTML documentation
zig build docs

# View documentation
open zig-out/docs/index.html
```

The generated documentation includes full API details from doc comments in the source code.
