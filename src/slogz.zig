// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! slogz - Structured Logging for Zig
//!
//! A high-performance structured logging library inspired by Go's slog.
//!
//! Features:
//! - Multiple output handlers (text, JSON, syslog, file rotation)
//! - Async handler with bounded queue and drop-oldest policy
//! - Network sinks (TCP, UDP, HTTP) with retry/backoff
//! - Platform-specific handlers (journald, Windows Event Log)
//! - Prometheus-style metrics export
//! - i18n catalog for message translation
//! - Zero-allocation for disabled/simple log calls
//!
//! Example usage:
//! ```zig
//! const slogz = @import("slogz");
//!
//! var text_ctx = slogz.text.Context.init(
//!     std.Io.File.stderr().writer().any(),
//!     .info,
//!     slogz.Clock.system(),
//! );
//! const handler = slogz.text.init(&text_ctx);
//!
//! const logger = slogz.Logger.init(handler, .info, slogz.Clock.system()).named("myapp");
//!
//! try logger.info("app.started", &.{
//!     slogz.Attr.string("version", "1.0.0"),
//!     slogz.Attr.int("port", 8080),
//! });
//! ```
//!
//! ## Auto-Redaction
//!
//! Keys matching known sensitive patterns (e.g., "password", "api_key",
//! "token", "ssn", "jwt", "session", etc.) are automatically redacted
//! in all handler output. Use `Attr.secret()` for explicit redaction of
//! values whose keys are not in the built-in list.
//!
//! **Warning:** Log *messages* are NOT scanned for secrets. Sensitive
//! data must be passed as structured attributes using `Attr.secret()`
//! to ensure redaction. Never embed secrets directly in message strings.

const std = @import("std");

// Core types
pub const Level = @import("level.zig").Level;
pub const Value = @import("value.zig").Value;
pub const Attr = @import("value.zig").Attr;
pub const Secret = @import("value.zig").Secret;
pub const Marshaler = @import("value.zig").Marshaler;
pub const Record = @import("record.zig").Record;
pub const Handler = @import("handler.zig").Handler;
pub const HandlerVTable = @import("handler.zig").HandlerVTable;
pub const HandlerError = @import("handler.zig").HandlerError;
pub const Logger = @import("logger.zig").Logger;

// Internal utilities
pub const Clock = @import("internal/clock.zig").Clock;

// Formatting
pub const rfc3339 = @import("fmt/rfc3339.zig");
pub const json_value = @import("fmt/json_value.zig");
pub const json_record = @import("fmt/json_record.zig");
pub const text_value = @import("fmt/text_value.zig");
pub const text_record = @import("fmt/text_record.zig");

// Utilities
pub const redact = @import("util/redact.zig");
pub const sanitize = @import("util/sanitize.zig");

// Internal (exposed for benchmarking)
pub const queue = @import("internal/queue.zig");

// Metrics
pub const metrics = @import("metrics/metrics.zig");

// i18n
pub const i18n = @import("i18n/catalog.zig");

// Handlers
pub const text = @import("handlers/text_handler.zig");
pub const json = @import("handlers/json_handler.zig");
pub const discard = @import("handlers/discard_handler.zig");
pub const async_handler = @import("handlers/async_handler.zig");
pub const rotating_file = @import("handlers/rotating_file.zig");
pub const syslog = @import("handlers/syslog_rfc5424.zig");
pub const journald = @import("handlers/journald.zig");
pub const windows_eventlog = @import("handlers/windows_eventlog.zig");
pub const multi_handler = @import("handlers/multi_handler.zig");

// Parallelism
pub const parallel = @import("parallel.zig");

// Network sinks
pub const tcp_sink = @import("sinks/tcp_sink.zig");
pub const udp_sink = @import("sinks/udp_sink.zig");
pub const http_sink = @import("sinks/http_sink.zig");

// Convenience type aliases
pub const TextHandler = text;
pub const JsonHandler = json;
pub const DiscardHandler = discard;
pub const AsyncHandler = async_handler;
pub const RotatingFileHandler = rotating_file;
pub const SyslogHandler = syslog;
pub const JournaldHandler = journald;
pub const WindowsEventLogHandler = windows_eventlog;
pub const MultiHandler = multi_handler;
pub const TcpSink = tcp_sink;
pub const UdpSink = udp_sink;
pub const HttpSink = http_sink;

// Re-export common types for convenience
pub const Facility = syslog.Facility;
pub const Severity = syslog.Severity;
pub const AsyncOptions = async_handler.AsyncOptions;
pub const RotationOptions = rotating_file.RotationOptions;
pub const SyslogOptions = syslog.SyslogOptions;
pub const TcpOptions = tcp_sink.TcpOptions;
pub const UdpOptions = udp_sink.UdpOptions;
pub const HttpOptions = http_sink.HttpOptions;

/// Create a text handler writing to stderr.
///
/// The caller provides a pointer to a `text.Context` which is initialized
/// in place, avoiding dangling pointers. The returned `Handler` references
/// the caller-owned context, so `ctx` must outlive the handler.
/// Static stderr writer buffer and file writer instance.
var stderr_writer_buf: [4096]u8 = undefined;
var stderr_file_writer: std.Io.File.Writer = std.Io.File.stderr().writer(
    std.Io.Threaded.global_single_threaded.io(),
    &stderr_writer_buf,
);

pub fn stderrHandler(ctx: *text.Context, level: Level) Handler {
    ctx.* = text.Context.init(
        &stderr_file_writer.interface,
        level,
        Clock.system(),
    );
    return text.init(ctx);
}

/// Create a JSON handler writing to stderr.
///
/// The caller provides a pointer to a `json.Context` which is initialized
/// in place, avoiding dangling pointers. The returned `Handler` references
/// the caller-owned context, so `ctx` must outlive the handler.
pub fn stderrJsonHandler(ctx: *json.Context, level: Level) Handler {
    ctx.* = json.Context.init(
        &stderr_file_writer.interface,
        level,
        Clock.system(),
    );
    return json.init(ctx);
}

/// Create a discard handler (for benchmarking or disabling logging).
pub fn discardHandler() Handler {
    return discard.init();
}

/// Get global metrics snapshot.
pub fn getMetrics() struct { bytes_written: u64, records_emitted: u64 } {
    const snap = metrics.global.snapshot();
    return .{
        .bytes_written = snap.bytes_written_total,
        .records_emitted = snap.logs_emitted_total,
    };
}

/// Export metrics in Prometheus format.
pub fn exportPrometheusMetrics(buf: []u8) []const u8 {
    return metrics.global.renderPrometheus(buf);
}

/// Shut down the slogz library, releasing the global spice thread pool
/// (if enabled and initialized). Call this during application shutdown
/// after all loggers and handlers have been closed.
pub fn deinit() void {
    parallel.deinitPool();
}

test "slogz basic usage" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = text.Context.init(&fbs, .info, Clock.system());
    const handler = text.init(&ctx);

    const logger = Logger.init(handler, .info, Clock.system()).named("test");

    try logger.info("Hello, slogz!", &.{
        Attr.string("key", "value"),
        Attr.int("count", 42),
    });

    const output = fbs.buffered();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "Hello, slogz!") != null);
}

test "slogz JSON handler" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = json.Context.init(&fbs, .info, Clock.system());
    const handler = json.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "test",
        .message = "JSON test",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("format", "json"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":\"INFO\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"JSON test\"") != null);
}

test "slogz secret redaction" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = text.Context.init(&fbs, .info, Clock.system());
    const handler = text.init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "Secret test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.secret("api_key", "super_secret_key"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    // Secret should be redacted
    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "super_secret_key") == null);
}

test "slogz level filtering" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = text.Context.init(&fbs, .warn, Clock.system());
    const handler = text.init(&ctx);

    // Debug message should be filtered
    const debug_rec = Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "debug",
        .message = "Debug message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };
    try handler.handle(&debug_rec);

    // Warning message should pass
    const warn_rec = Record{
        .time_utc_us = 0,
        .level = .warn,
        .msg_id = "warn",
        .message = "Warning message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };
    try handler.handle(&warn_rec);

    const output = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Debug message") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Warning message") != null);
}

test "stderrHandler caller-owned context avoids dangling pointer" {
    // The new API takes a *text.Context out-parameter, so the handler's
    // internal ctx pointer points to caller-owned memory, not a dead stack frame.
    var ctx: text.Context = undefined;
    const handler = stderrHandler(&ctx, .fatal);

    // Log at a level below .fatal so it is filtered out (no stderr noise in tests),
    // but the handler.handle call exercises the vtable pointer indirection through
    // the caller-owned context, proving no dangling pointer.
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "filtered",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };
    try handler.handle(&rec);
}

test "stderrJsonHandler caller-owned context avoids dangling pointer" {
    var ctx: json.Context = undefined;
    const handler = stderrJsonHandler(&ctx, .fatal);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "filtered",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };
    try handler.handle(&rec);
}

test "slogz discard handler" {
    const handler = discardHandler();

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "Discarded",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    // Should not error
    try handler.handle(&rec);
    try handler.flush(0);
}
