//! Acceptance tests for slogz
//!
//! These tests verify the public API and expected behavior of the slogz library.

const std = @import("std");
const slogz = @import("slogz");

const Level = slogz.Level;
const Attr = slogz.Attr;
const Record = slogz.Record;
const Handler = slogz.Handler;
const Logger = slogz.Logger;
const Clock = slogz.Clock;

// ============================================================================
// Text Handler Tests
// ============================================================================

test "TextHandler output format" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.text.Context.init(&fbs, .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000, // 2025-01-02T03:04:05.000000Z
        .level = .info,
        .msg_id = "app.started",
        .message = "app started",
        .logger = "web",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.int("port", 8080),
            Attr.string("commit", "abc123"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    // Verify format: TIMESTAMP LEVEL logger message key=value ...
    try std.testing.expect(std.mem.indexOf(u8, output, "2025-01-02T03:04:05.000000Z") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "INFO") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "web") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "app started") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "port=8080") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "commit=abc123") != null);
}

test "TextHandler level filtering" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.text.Context.init(&fbs, .warn, Clock.system());
    const handler = slogz.text.init(&ctx);

    // Debug should be filtered
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "debug",
        .message = "debug message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    // Info should be filtered
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "info",
        .message = "info message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    // Warn should pass
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .warn,
        .msg_id = "warn",
        .message = "warn message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    const output = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "debug message") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "info message") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "warn message") != null);
}

// ============================================================================
// JSON Handler Tests
// ============================================================================

test "JSONHandler output format" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.json.Context.init(&fbs, .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000, // 2025-01-02T03:04:05.000000Z
        .level = .info,
        .msg_id = "app.started",
        .message = "app started",
        .logger = "web",
        .source_file = "main.zig",
        .source_line = 42,
        .attrs = &.{
            Attr.int("port", 8080),
            Attr.string("commit", "abc123"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    // Verify JSON structure
    try std.testing.expect(std.mem.indexOf(u8, output, "\"time\":\"2025-01-02T03:04:05.000000Z\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":\"INFO\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"app started\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"logger\":\"web\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source_file\":\"main.zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source_line\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"port\":8080") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"commit\":\"abc123\"") != null);
}

test "JSONHandler escaping" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.json.Context.init(&fbs, .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test \"quoted\" and\nnewline",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    const output = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\"quoted\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\n") != null);
}

// ============================================================================
// Secret Redaction Tests
// ============================================================================

test "Secret redaction in TextHandler" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.text.Context.init(&fbs, .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "auth",
        .message = "user logged in",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("user", "alice"),
            Attr.secret("password", "super_secret_password"),
        },
    });

    const output = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, slogz.redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "super_secret_password") == null);
}

test "Secret redaction in JSONHandler" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.json.Context.init(&fbs, .info, Clock.system());
    const handler = slogz.json.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "auth",
        .message = "API call",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.secret("api_key", "sk-1234567890abcdef"),
        },
    });

    const output = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, slogz.redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sk-1234567890abcdef") == null);
}

// ============================================================================
// Syslog RFC5424 Tests
// ============================================================================

test "SyslogHandler RFC5424 format" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.syslog.Context.init(&fbs, .info, Clock.system(), .{
        .facility = .local0,
        .hostname = "localhost",
        .app_name = "myapp",
        .procid = 1234,
    });
    const handler = slogz.syslog.init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000, // 2025-01-02T03:04:05.000000Z
        .level = .info,
        .msg_id = "app.started",
        .message = "iniciado en 12ms",
        .logger = "web",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.int("duration_ms", 12),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    // PRI for local0.info = 16*8 + 6 = 134
    try std.testing.expect(std.mem.startsWith(u8, output, "<134>1 "));
    try std.testing.expect(std.mem.indexOf(u8, output, "2025-01-02T03:04:05.000000Z") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "localhost") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "web") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1234") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "app.started") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[attrs@32473") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "duration_ms=\"12\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "iniciado en 12ms") != null);
}

test "SyslogHandler severity mapping" {
    try std.testing.expectEqual(slogz.syslog.Severity.debug, @as(slogz.syslog.Severity, @enumFromInt(slogz.Level.debug.toSyslogSeverity())));
    try std.testing.expectEqual(slogz.syslog.Severity.info, @as(slogz.syslog.Severity, @enumFromInt(slogz.Level.info.toSyslogSeverity())));
    try std.testing.expectEqual(slogz.syslog.Severity.warning, @as(slogz.syslog.Severity, @enumFromInt(slogz.Level.warn.toSyslogSeverity())));
    try std.testing.expectEqual(slogz.syslog.Severity.@"error", @as(slogz.syslog.Severity, @enumFromInt(slogz.Level.@"error".toSyslogSeverity())));
}

// ============================================================================
// Logger Tests
// ============================================================================

test "Logger with text handler" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.text.Context.init(&fbs, .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    var logger = Logger.init(handler, .info, Clock.system()).named("myapp");

    try logger.info("request.handled", &.{
        Attr.string("method", "GET"),
        Attr.string("path", "/api/users"),
        Attr.int("status", 200),
        Attr.int("duration_ms", 42),
    });

    const output = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "myapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "request.handled") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "method=GET") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "status=200") != null);
}

// ============================================================================
// Discard Handler Tests
// ============================================================================

test "DiscardHandler drops all records" {
    const handler = slogz.discardHandler();

    // Should not error
    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "discarded message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    try handler.flush(0);
}

// ============================================================================
// Metrics Tests
// ============================================================================

test "Metrics tracking" {
    // Get initial state
    const initial = slogz.getMetrics();

    // Handle a record
    var buf: [1024]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = slogz.text.Context.init(&fbs, .info, Clock.system());
    const handler = slogz.text.init(&ctx);

    try handler.handle(&Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    });

    // Verify bytes written increased
    const after = slogz.getMetrics();
    try std.testing.expect(after.bytes_written > initial.bytes_written);
}

test "Prometheus metrics export" {
    slogz.metrics.reset();
    slogz.metrics.global.incEmitted();
    slogz.metrics.global.addBytesWritten(1024);

    var buf: [4096]u8 = undefined;
    const output = slogz.exportPrometheusMetrics(&buf);

    try std.testing.expect(std.mem.indexOf(u8, output, "slogz_logs_emitted_total") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "slogz_bytes_written_total") != null);
}

// ============================================================================
// Value Type Tests
// ============================================================================

test "Value types" {
    // String
    const str_val = slogz.Value{ .str = "hello" };
    try std.testing.expect(str_val == .str);

    // Integer
    const int_val = slogz.Value{ .i64 = -42 };
    try std.testing.expect(int_val == .i64);

    // Unsigned
    const uint_val = slogz.Value{ .u64 = 42 };
    try std.testing.expect(uint_val == .u64);

    // Float
    const float_val = slogz.Value{ .f64 = 3.14 };
    try std.testing.expect(float_val == .f64);

    // Boolean
    const bool_val = slogz.Value{ .bool = true };
    try std.testing.expect(bool_val == .bool);

    // Error
    const err_val = slogz.Value{ .err = error.TestError };
    try std.testing.expect(err_val == .err);
}

test "Attr constructors" {
    const str_attr = Attr.string("key", "value");
    try std.testing.expectEqualStrings("key", str_attr.key);
    try std.testing.expect(str_attr.value == .str);

    const int_attr = Attr.int("count", 42);
    try std.testing.expectEqualStrings("count", int_attr.key);
    try std.testing.expect(int_attr.value == .i64);

    const float_attr = Attr.float("ratio", 0.5);
    try std.testing.expectEqualStrings("ratio", float_attr.key);
    try std.testing.expect(float_attr.value == .f64);

    const bool_attr = Attr.boolean("enabled", true);
    try std.testing.expectEqualStrings("enabled", bool_attr.key);
    try std.testing.expect(bool_attr.value == .bool);

    const secret_attr = Attr.secret("password", "hunter2");
    try std.testing.expectEqualStrings("password", secret_attr.key);
    try std.testing.expect(secret_attr.value == .secret);
}

// ============================================================================
// Level Tests
// ============================================================================

test "Level ordering" {
    // trace < debug < info < warn < error < fatal
    try std.testing.expect(!Level.trace.atLeast(.debug));
    try std.testing.expect(Level.debug.atLeast(.trace));
    try std.testing.expect(Level.info.atLeast(.debug));
    try std.testing.expect(Level.warn.atLeast(.info));
    try std.testing.expect(Level.@"error".atLeast(.warn));
    try std.testing.expect(Level.fatal.atLeast(.@"error"));
}

test "Level text representation" {
    try std.testing.expectEqualStrings("TRACE", Level.trace.asText());
    try std.testing.expectEqualStrings("DEBUG", Level.debug.asText());
    try std.testing.expectEqualStrings("INFO", Level.info.asText());
    try std.testing.expectEqualStrings("WARN", Level.warn.asText());
    try std.testing.expectEqualStrings("ERROR", Level.@"error".asText());
    try std.testing.expectEqualStrings("FATAL", Level.fatal.asText());
}

// ============================================================================
// RFC3339 Timestamp Tests
// ============================================================================

test "RFC3339 timestamp formatting" {
    var buf: [27]u8 = undefined;
    slogz.rfc3339.formatTimestamp(&buf, 1735787045000000);
    try std.testing.expectEqualStrings("2025-01-02T03:04:05.000000Z", &buf);
}

test "RFC3339 epoch" {
    var buf: [27]u8 = undefined;
    slogz.rfc3339.formatTimestamp(&buf, 0);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.000000Z", &buf);
}

// ============================================================================
// Key Sanitization Tests
// ============================================================================

test "Key sanitization" {
    var buf: [slogz.sanitize.MAX_KEY_LENGTH]u8 = undefined;

    // Valid key passes through
    try std.testing.expectEqualStrings("valid_key", slogz.sanitize.sanitizeKey(&buf, "valid_key"));

    // Spaces replaced with underscores
    try std.testing.expectEqualStrings("key_with_spaces", slogz.sanitize.sanitizeKey(&buf, "key with spaces"));

    // Invalid chars replaced
    try std.testing.expectEqualStrings("key_value", slogz.sanitize.sanitizeKey(&buf, "key=value"));
}

// ============================================================================
// Rotating File Handler Tests (basic)
// ============================================================================

test "RotatingFileHandler options" {
    const opts = slogz.RotationOptions{
        .path = "/tmp/test.log",
        .max_bytes = 10 * 1024 * 1024,
        .max_backups = 5,
        .max_age_days = 30,
    };

    try std.testing.expectEqualStrings("/tmp/test.log", opts.path);
    try std.testing.expectEqual(@as(usize, 10 * 1024 * 1024), opts.max_bytes);
    try std.testing.expectEqual(@as(u8, 5), opts.max_backups);
    try std.testing.expectEqual(@as(u16, 30), opts.max_age_days);
}

// ============================================================================
// Async Handler Tests (basic)
// ============================================================================

test "AsyncHandler options" {
    const opts = slogz.AsyncOptions{
        .inner = slogz.discardHandler(),
        .queue_size = 1024,
        .drop_oldest = true,
        .block_timeout_ms = 0,
    };

    try std.testing.expectEqual(@as(usize, 1024), opts.queue_size);
    try std.testing.expect(opts.drop_oldest);
    try std.testing.expectEqual(@as(u32, 0), opts.block_timeout_ms);
}
