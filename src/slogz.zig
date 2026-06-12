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
//! var text_ctx: slogz.text.Context = undefined;
//! const handler = slogz.stderrHandler(&text_ctx, .info);
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

/// otel observability seam. When `-Dwith_otel=false` (the default), every
/// function in this namespace collapses to a comptime no-op and no otel
/// symbols are emitted. When `-Dwith_otel=true`, calls forward into the
/// `otel` package.
///
/// slog itself does NOT call the seam - slog is otel's transitive
/// std.log backend, so emitting a span from inside a log call would
/// create a logging->span->logging feedback loop. The seam is exposed
/// for forward compatibility and so consumers/embedders can wire spans
/// around their own slog usage if useful. See `src/observability.zig`
/// and the README's "Observability" section for details.
pub const observability = @import("observability.zig");

/// otel bootstrap helper. Only resolves to a real namespace when
/// `-Dwith_otel=true`; otherwise it is an empty struct so referencing
/// `slogz.observability_init` from a default-flag build is a no-op.
/// The init helper itself imports `otel`, which is why we gate the
/// `@import` - pulling it in unconditionally would break the
/// disabled-flag build, which has no `otel` module on the import path.
///
/// slog has no `main` of its own, so calling `Otel.init` +
/// `installGlobals` is the embedding application's responsibility.
/// slog itself never calls into the seam.
pub const observability_init = if (@import("build_options").with_otel)
    @import("observability_init.zig")
else
    struct {};

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

/// Shut down the slogz library, releasing the global thread pool
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

test "parallel re-export is reachable" {
    // Smoke test: verify parallel.zig is reachable through the public
    // slogz root module and parallelRecordFormat dispatches end-to-end
    // against a trivial formatter. Use 8 records to cross the parallel
    // threshold and exercise the thread-pool path.
    const N = 8;
    var inputs: [N]parallel.RecordInput = undefined;
    var bufs: [N][64]u8 = undefined;
    var buf_ptrs: [N][]u8 = undefined;
    var results: [N]parallel.FormattedRecord = undefined;

    for (&inputs, 0..) |*in, i| {
        in.* = .{
            .time_utc_us = @as(i128, @intCast(i)),
            .level = 0,
            .message = "msg",
            .logger = "test",
            .attrs_json = "{}",
        };
        buf_ptrs[i] = &bufs[i];
    }

    const fmt = struct {
        fn format(in: parallel.RecordInput, buffer: []u8) parallel.FormattedRecord {
            const msg = in.message;
            const n = @min(msg.len, buffer.len);
            @memcpy(buffer[0..n], msg[0..n]);
            return .{ .data = buffer, .len = n, .success = true };
        }
    }.format;

    parallel.parallelRecordFormat(&inputs, &buf_ptrs, &results, fmt);
    defer deinit();

    for (results) |r| {
        try std.testing.expect(r.success);
        try std.testing.expectEqual(@as(usize, 3), r.len);
    }
}

test {
    // Zig only collects tests from files referenced in a test context.
    // Reference the internal queue and async handler so their in-file
    // tests actually run as part of the unit test suite (PERF-040).
    _ = queue;
    _ = async_handler;
    // Reference the rotating file handler so its in-file tests (including
    // the SEC-0034/SEC-0037 regression tests) run in the unit test suite.
    _ = rotating_file;
}
