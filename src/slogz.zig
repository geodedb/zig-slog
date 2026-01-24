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
//!     std.fs.File.stderr().deprecatedWriter().any(),
//!     .info,
//!     slogz.Clock.system(),
//! );
//! const handler = slogz.text.init(&text_ctx);
//!
//! var logger = slogz.Logger.init(std.heap.page_allocator, "myapp", handler);
//! defer logger.deinit();
//!
//! logger.info("app.started", "Application started", &.{
//!     slogz.Attr.string("version", "1.0.0"),
//!     slogz.Attr.int("port", 8080),
//! });
//! ```

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
pub const LoggerOptions = @import("logger.zig").LoggerOptions;

// Internal utilities
pub const Clock = @import("internal/clock.zig").Clock;

// Formatting
pub const rfc3339 = @import("fmt/rfc3339.zig");

// Utilities
pub const redact = @import("util/redact.zig");
pub const sanitize = @import("util/sanitize.zig");

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
pub fn stderrHandler(level: Level) struct { ctx: text.Context, handler: Handler } {
    var ctx = text.Context.init(
        std.fs.File.stderr().deprecatedWriter().any(),
        level,
        Clock.system(),
    );
    return .{
        .ctx = ctx,
        .handler = text.init(&ctx),
    };
}

/// Create a JSON handler writing to stderr.
pub fn stderrJsonHandler(level: Level) struct { ctx: json.Context, handler: Handler } {
    var ctx = json.Context.init(
        std.fs.File.stderr().deprecatedWriter().any(),
        level,
        Clock.system(),
    );
    return .{
        .ctx = ctx,
        .handler = json.init(&ctx),
    };
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

test "slogz basic usage" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = text.Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = text.init(&ctx);

    const logger = Logger.init(handler, .info, Clock.system()).named("test");

    try logger.info("Hello, slogz!", &.{
        Attr.string("key", "value"),
        Attr.int("count", 42),
    });

    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "Hello, slogz!") != null);
}

test "slogz JSON handler" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = json.Context.init(fbs.writer().any(), .info, Clock.system());
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
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":\"INFO\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"JSON test\"") != null);
}

test "slogz secret redaction" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = text.Context.init(fbs.writer().any(), .info, Clock.system());
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
    const output = fbs.getWritten();

    // Secret should be redacted
    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "super_secret_key") == null);
}

test "slogz level filtering" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = text.Context.init(fbs.writer().any(), .warn, Clock.system());
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

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Debug message") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Warning message") != null);
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
