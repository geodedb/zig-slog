# Architecture

This document describes the architecture of the slog structured logging library.

## Module Structure

```
src/
├── slogz.zig           # Main entry point and public API
├── logger.zig          # Logger type with log methods
├── handler.zig         # Handler interface (vtable pattern)
├── record.zig          # Log record structure
├── level.zig           # Log level enum
├── value.zig           # Attribute values (Attr, Value, Secret)
├── handlers/
│   ├── text_handler.zig      # Human-readable output
│   ├── json_handler.zig      # Structured JSON output
│   ├── async_handler.zig     # Background thread delivery
│   ├── rotating_file.zig     # Size-based file rotation
│   ├── syslog_rfc5424.zig    # Syslog protocol handler
│   ├── discard_handler.zig   # No-op handler (benchmarking)
│   ├── journald.zig          # Linux systemd journal
│   └── windows_eventlog.zig  # Windows Event Log
├── sinks/
│   ├── tcp_sink.zig          # TCP with reconnection
│   ├── udp_sink.zig          # UDP fire-and-forget
│   └── http_sink.zig         # HTTP POST with retry
├── metrics/
│   └── metrics.zig           # Prometheus-style counters
├── i18n/
│   └── catalog.zig           # Translation catalog
├── internal/
│   ├── clock.zig             # Time source abstraction
│   └── queue.zig             # Bounded queue for async
├── fmt/
│   └── rfc3339.zig           # Timestamp formatting
└── util/
    ├── redact.zig            # Secret redaction
    └── sanitize.zig          # Key sanitization
```

## Core Concepts

### Logger (`logger.zig`)

The `Logger` is the primary user-facing type. It wraps a `Handler` and provides level-specific methods (`info()`, `warn()`, etc.).

```zig
pub const Logger = struct {
    handler: Handler,
    level: Level,
    clock: Clock,
    name: []const u8,
    context_attrs: []const Attr,
    translator: ?Translator,
    locale: []const u8,
};
```

Key features:
- **Level filtering**: Log calls below the threshold return immediately
- **Named loggers**: Create hierarchical logger names via `named()`
- **Context attributes**: Add attributes to all logs via `with()`
- **Attribute grouping**: Prefix attribute keys via `withGroup()`
- **Translation**: i18n support via `withTranslator()`
- **Fatal hook**: Configurable behavior on fatal logs (default: panic)

### Handler Interface (`handler.zig`)

Handlers use a vtable pattern for runtime polymorphism without allocations:

```zig
pub const Handler = struct {
    ctx: *anyopaque,
    vtable: *const HandlerVTable,
};

pub const HandlerVTable = struct {
    handle: *const fn (ctx: *anyopaque, rec: *const Record) HandlerError!void,
    withAttrs: *const fn (ctx: *anyopaque, addl: []const Attr) Handler,
    withGroup: *const fn (ctx: *anyopaque, prefix: []const u8) Handler,
    setLevel: *const fn (ctx: *anyopaque, level: Level) void,
    flush: *const fn (ctx: *anyopaque, timeout_ms: u32) HandlerError!void,
    close: ?*const fn (ctx: *anyopaque) void = null,
};
```

This design allows:
- Zero-allocation handler composition
- Handler wrapping (e.g., async wrapper around any handler)
- Clean separation of concerns

### Record (`record.zig`)

A `Record` contains all information about a single log event:

```zig
pub const Record = struct {
    time_utc_us: i128,          // Microseconds since Unix epoch
    level: Level,
    msg_id: []const u8,          // For i18n lookup
    message: []const u8,         // Translated or original
    logger: []const u8,          // Logger name
    source_file: []const u8,     // Optional source location
    source_line: u32,
    attrs: []const Attr,         // Structured attributes
};
```

Records are stack-allocated and passed by pointer to handlers.

### Level (`level.zig`)

Log levels use signed integers to allow custom intermediate levels:

| Level | Value | Description |
|-------|-------|-------------|
| trace | -8 | Fine-grained debugging |
| debug | -4 | Development debugging |
| info | 0 | Normal operational messages |
| warn | 4 | Warning conditions |
| error | 8 | Error conditions |
| fatal | 12 | Fatal errors |

### Value Types (`value.zig`)

Attributes are key-value pairs where values support multiple types:

```zig
pub const Value = union(enum) {
    i64: i64,
    u64: u64,
    f64: f64,
    bool: bool,
    str: []const u8,
    bytes: []const u8,
    err: anyerror,
    secret: Secret,
    marshaler: *const Marshaler,
};
```

The `Secret` type enables automatic redaction of sensitive values.

## Data Flow

```
┌─────────────────┐
│  Application    │
│  logger.info()  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Logger      │
│  - Level check  │
│  - Translation  │
│  - Create Record│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Handler     │
│  (via vtable)   │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐ ┌───────┐
│ Text  │ │ JSON  │
│Handler│ │Handler│
└───┬───┘ └───┬───┘
    │         │
    ▼         ▼
┌─────────────────┐
│   std.io.Writer │
│  (stderr, file) │
└─────────────────┘
```

## Handler Architecture

### Synchronous Handlers

Text, JSON, and Syslog handlers write directly to their underlying writer:

```
Logger.info() → Handler.handle() → Writer.writeAll()
                                        │
                                        ▼
                                    Output
```

### Async Handler

The async handler decouples logging from I/O:

```
┌──────────┐    ┌──────────────┐    ┌──────────────┐
│  Logger  │───▶│ BoundedQueue │───▶│ Worker Thread│
│ (caller) │    │  (1024 slots)│    │  (background)│
└──────────┘    └──────────────┘    └──────────────┘
     │                                     │
     │ returns                             ▼
     │ immediately               ┌──────────────┐
     ▼                           │ Inner Handler│
                                 └──────────────┘
```

Features:
- Lock-free queue with configurable size
- Drop-oldest policy prevents blocking
- Optional blocking mode with timeout
- Graceful shutdown drains queue

### Network Sinks

Network sinks add reliability features:

```
┌──────────┐    ┌──────────────┐    ┌──────────────┐
│  Logger  │───▶│   TCP Sink   │───▶│ Log Collector│
└──────────┘    │  - Reconnect │    │ (Logstash,   │
                │  - Retry     │    │  Fluentd)    │
                │  - Backoff   │    └──────────────┘
                └──────────────┘
```

### Handler Composition

Handlers can be composed for complex setups:

```
┌──────────┐
│  Logger  │
└────┬─────┘
     │
     ▼
┌────────────────┐
│  Async Handler │ (non-blocking)
└────────┬───────┘
         │
         ▼
┌────────────────┐
│ Rotating File  │ (size-based rotation)
│    Handler     │
└────────────────┘
```

## Metrics System

Global atomic counters track logging activity:

```zig
pub const Metrics = struct {
    logs_emitted_total: std.atomic.Value(u64),
    logs_dropped_total: std.atomic.Value(u64),
    handler_errors_total: std.atomic.Value(u64),
    bytes_written_total: std.atomic.Value(u64),
    queue_size: std.atomic.Value(u64),
    rotations_total: std.atomic.Value(u64),
    reconnections_total: std.atomic.Value(u64),
};
```

Metrics are lock-free using atomic operations. Export via `renderPrometheus()`.

## i18n System

Translation uses a two-level map:

```
locale → message_id → translated_string

Catalog {
    translations: HashMap(locale, HashMap(msg_id, translation))
}
```

Loaded from JSON:
```json
{
  "es": { "app.started": "aplicacion iniciada" },
  "de": { "app.started": "Anwendung gestartet" }
}
```

## Thread Safety

| Component | Thread Safety |
|-----------|---------------|
| Logger | Immutable, safe to share |
| Text Handler | Mutex-protected writes |
| JSON Handler | Mutex-protected writes |
| Async Handler | Lock-free queue |
| Rotating File | Mutex-protected rotation |
| Metrics | Atomic counters |

## Performance Characteristics

| Operation | Allocation | Notes |
|-----------|------------|-------|
| Log at disabled level | None | Immediate return |
| Log with text handler | None | Stack buffer formatting |
| Log with JSON handler | None | Stack buffer formatting |
| Log with async handler | Possible | Queue entry copy |
| i18n translation | None | Hash map lookup |
| Metrics update | None | Atomic increment |

Design goals:
- Zero allocations for common paths
- Minimal overhead for disabled levels
- Lock-free metrics
- Bounded memory usage

## Dependencies

Internal Zig libraries:
- `std` - Standard library (io, mem, Thread)
- `json` - JSON encoding for handlers

External dependencies:
- `libsystemd` (optional) - For journald handler
- Windows API (optional) - For Event Log handler

## Feature Flags

Build-time options in `build.zig`:

| Flag | Description |
|------|-------------|
| `feature_journald` | Enable Linux journald handler |
| `feature_windows_eventlog` | Enable Windows Event Log handler |

## Future Enhancements

See [GitLab Issues](https://gitlab.com/devnw/zig/slog/-/issues) for tracking:

- [Multi-handler fan-out](https://gitlab.com/devnw/zig/slog/-/issues/9)
- [Log sampling and rate limiting](https://gitlab.com/devnw/zig/slog/-/issues/10)
- [TLS/HTTPS support for HTTP sink](https://gitlab.com/devnw/zig/slog/-/issues/5)
- [DNS hostname resolution](https://gitlab.com/devnw/zig/slog/-/issues/6)
