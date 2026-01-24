# slog

A high-performance structured logging library for Zig, inspired by Go's slog.

## Status

| Aspect | Info |
|--------|------|
| API Stability | Beta |
| Zig Version | 0.14.0+ |
| Platforms | Linux, macOS, Windows |

## Features

- **Multiple Output Handlers**
  - Text handler (human-readable format)
  - JSON handler (structured JSON output)
  - Syslog RFC5424 handler
  - Rotating file handler with size-based rotation
  - Discard handler (for benchmarking)

- **Async Handler**
  - Background thread delivery
  - Bounded queue with configurable size
  - Drop-oldest policy with metrics tracking
  - Optional blocking mode with timeout

- **Network Sinks**
  - TCP with automatic reconnection and retry/backoff
  - UDP (fire-and-forget)
  - HTTP POST with configurable retry

- **Platform-Specific Handlers** (feature-gated)
  - Journald (Linux, requires libsystemd)
  - Windows Event Log

- **Additional Features**
  - Prometheus-style metrics export
  - i18n catalog for message translation
  - Secret redaction (sensitive values never logged)
  - Key sanitization for structured output
  - Zero-allocation for disabled/simple log calls
  - Stable key order in output

## Installation

Add slog to your `build.zig.zon`:

```zig
.dependencies = .{
    .slog = .{
        .url = "https://gitlab.com/devnw/zig/slog/-/archive/main/slog-main.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const slog_dep = b.dependency("slog", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("slog", slog_dep.module("slog"));
```

## Quick Start

```zig
const std = @import("std");
const slog = @import("slog");

pub fn main() !void {
    // Create a text handler writing to stderr
    var ctx = slog.text.Context.init(
        std.io.getStdErr().writer().any(),
        .info,
        slog.Clock.system(),
    );
    const handler = slog.text.init(&ctx);

    // Create a logger
    const logger = slog.Logger.init(handler, .info, slog.Clock.system())
        .named("myapp");

    // Log messages
    try logger.info("app.started", &.{
        slog.Attr.string("version", "1.0.0"),
        slog.Attr.int("port", 8080),
    });
}
```

Output:
```
2025-01-02T03:04:05.000000Z INFO myapp app.started version=1.0.0 port=8080
```

## Handlers

### Text Handler

Human-readable log format:

```zig
var ctx = slog.text.Context.init(writer.any(), .info, slog.Clock.system());
const handler = slog.text.init(&ctx);
```

### JSON Handler

Structured JSON output with stable key order:

```zig
var ctx = slog.json.Context.init(writer.any(), .info, slog.Clock.system());
const handler = slog.json.init(&ctx);
```

Output:
```json
{"time":"2025-01-02T03:04:05.000000Z","level":"INFO","msg":"app.started","logger":"myapp","attrs":{"port":8080}}
```

### Rotating File Handler

Size-based rotation with backup management:

```zig
var ctx = try slog.rotating_file.Context.init(allocator, .{
    .path = "/var/log/myapp.log",
    .max_bytes = 10 * 1024 * 1024,  // 10MB
    .max_backups = 5,
    .max_age_days = 30,
}, .info, slog.Clock.system());
defer ctx.deinit();

const handler = slog.rotating_file.init(&ctx);
```

### Async Handler

Background thread delivery with bounded queue:

```zig
var async_ctx = try slog.async_handler.Context.init(allocator, .{
    .inner = inner_handler,
    .queue_size = 1024,
    .drop_oldest = true,
    .block_timeout_ms = 0,
});
defer async_ctx.deinit();

const handler = slog.async_handler.init(&async_ctx);
```

### Syslog RFC5424

```zig
var ctx = slog.syslog.Context.init(writer.any(), .info, slog.Clock.system(), .{
    .facility = .local0,
    .hostname = "myhost",
    .app_name = "myapp",
    .procid = 1234,
});
const handler = slog.syslog.init(&ctx);
```

Output:
```
<134>1 2025-01-02T03:04:05.000000Z myhost myapp 1234 app.started [attrs@32473 port="8080"] Application started
```

## Attribute Types

```zig
const attrs = &.{
    slog.Attr.string("user", "alice"),
    slog.Attr.int("count", 42),
    slog.Attr.uint("size", 1024),
    slog.Attr.float("ratio", 0.95),
    slog.Attr.boolean("enabled", true),
    slog.Attr.err("error", error.NotFound),
    slog.Attr.secret("api_key", "sk-xxx"),  // Redacted in output
};
```

## Secret Redaction

Sensitive values marked with `Attr.secret()` are automatically redacted:

```zig
try logger.info("auth", &.{
    slog.Attr.string("user", "alice"),
    slog.Attr.secret("password", "hunter2"),  // Outputs: password=[REDACTED]
});
```

## Log Levels

| Level | Value | Description |
|-------|-------|-------------|
| trace | -8    | Fine-grained debugging |
| debug | -4    | Debugging information |
| info  | 0     | Normal operational messages |
| warn  | 4     | Warning conditions |
| error | 8     | Error conditions |
| fatal | 12    | Fatal errors (triggers fatal_hook) |

## Metrics

Export Prometheus-style metrics:

```zig
var buf: [4096]u8 = undefined;
const output = slog.exportPrometheusMetrics(&buf);
std.debug.print("{s}", .{output});
```

Output:
```
# HELP slogz_logs_emitted_total Total number of log records emitted.
# TYPE slogz_logs_emitted_total counter
slogz_logs_emitted_total 1234
# HELP slogz_logs_dropped_total Total number of log records dropped.
# TYPE slogz_logs_dropped_total counter
slogz_logs_dropped_total 0
...
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

## Feature Flags

### Journald (Linux)

```bash
zig build -Dfeature_journald=true
```

### Windows Event Log

```bash
zig build -Dfeature_windows_eventlog=true
```

## Building

```bash
# Build
zig build

# Run tests
zig build test

# Format code
zig build fmt

# Check for errors
zig build check
```

## Performance

- Zero allocations for disabled log levels
- Lock-free metrics counters
- Bounded async queue with configurable drop policy
- Minimal overhead for simple log calls

## Roadmap

Development is tracked via [GitLab Issues](https://gitlab.com/devnw/zig/slog/-/issues).

### Current Milestones

| Phase | Focus | Status |
|-------|-------|--------|
| [Phase 1](https://gitlab.com/devnw/zig/slog/-/milestones/1) | Foundation - code quality, deprecated API removal | Active |
| [Phase 2](https://gitlab.com/devnw/zig/slog/-/milestones/2) | Platform Handlers - Windows Event Log, journald | Planned |
| [Phase 3](https://gitlab.com/devnw/zig/slog/-/milestones/3) | Network Sinks - TLS/HTTPS, DNS, attributes | Planned |
| [Phase 4](https://gitlab.com/devnw/zig/slog/-/milestones/4) | Advanced Features - multi-handler, sampling | Planned |
| [Phase 5](https://gitlab.com/devnw/zig/slog/-/milestones/5) | Testing & Documentation | Planned |

### Key Upcoming Features

- [TLS/HTTPS support for HTTP sink](https://gitlab.com/devnw/zig/slog/-/issues/5)
- [DNS hostname resolution](https://gitlab.com/devnw/zig/slog/-/issues/6)
- [Multi-handler fan-out](https://gitlab.com/devnw/zig/slog/-/issues/9)
- [Log sampling and rate limiting](https://gitlab.com/devnw/zig/slog/-/issues/10)

## License

Apache-2.0 License - see [LICENSE](LICENSE) for details.
