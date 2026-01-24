//! Comprehensive unit tests for Record module.

const std = @import("std");
const slogz = @import("slogz");
const Record = slogz.Record;
const Attr = slogz.Attr;
const Level = slogz.Level;

// ============================================================================
// Record Creation Tests
// ============================================================================

test "Record - basic creation" {
    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "test.message",
        .message = "Test message",
        .logger = "test",
        .source_file = "test.zig",
        .source_line = 42,
        .attrs = &.{},
    };

    try std.testing.expectEqual(@as(i128, 1735787045000000), rec.time_utc_us);
    try std.testing.expectEqual(Level.info, rec.level);
    try std.testing.expectEqualStrings("test.message", rec.msg_id);
    try std.testing.expectEqualStrings("Test message", rec.message);
    try std.testing.expectEqualStrings("test", rec.logger);
    try std.testing.expectEqualStrings("test.zig", rec.source_file);
    try std.testing.expectEqual(@as(u32, 42), rec.source_line);
}

test "Record - with attributes" {
    const attrs = [_]Attr{
        Attr.string("user", "alice"),
        Attr.int("count", 5),
    };

    const rec = Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &attrs,
    };

    try std.testing.expectEqual(@as(usize, 2), rec.attrs.len);
    try std.testing.expectEqualStrings("user", rec.attrs[0].key);
    try std.testing.expectEqualStrings("count", rec.attrs[1].key);
}

// ============================================================================
// Record Level Tests
// ============================================================================

test "Record - all levels" {
    const levels = [_]Level{ .trace, .debug, .info, .warn, .@"error", .fatal };

    for (levels) |level| {
        const rec = Record{
            .time_utc_us = 0,
            .level = level,
            .msg_id = "test",
            .message = "test",
            .logger = "",
            .source_file = "",
            .source_line = 0,
            .attrs = &.{},
        };

        try std.testing.expectEqual(level, rec.level);
    }
}

// ============================================================================
// Record Size Limit Tests
// ============================================================================

test "Record.hasTooManyAttrs - under limit" {
    var attrs: [32]Attr = undefined;
    for (&attrs) |*a| {
        a.* = Attr.int("key", 0);
    }

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &attrs,
    };

    try std.testing.expect(!rec.hasTooManyAttrs());
}

test "Record.hasTooManyAttrs - at limit" {
    var attrs: [64]Attr = undefined;
    for (&attrs) |*a| {
        a.* = Attr.int("key", 0);
    }

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &attrs,
    };

    try std.testing.expect(!rec.hasTooManyAttrs());
}

test "Record.hasTooManyAttrs - over limit" {
    var attrs: [65]Attr = undefined;
    for (&attrs) |*a| {
        a.* = Attr.int("key", 0);
    }

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &attrs,
    };

    try std.testing.expect(rec.hasTooManyAttrs());
}

// ============================================================================
// Record Empty Fields Tests
// ============================================================================

test "Record - empty logger" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try std.testing.expectEqualStrings("", rec.logger);
}

test "Record - empty source file" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "app",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try std.testing.expectEqualStrings("", rec.source_file);
}

test "Record - empty message" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "empty",
        .message = "",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try std.testing.expectEqualStrings("", rec.message);
}

// ============================================================================
// Record Timestamp Tests
// ============================================================================

test "Record - zero timestamp" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try std.testing.expectEqual(@as(i128, 0), rec.time_utc_us);
}

test "Record - large timestamp" {
    const ts: i128 = 9999999999999999; // Far future
    const rec = Record{
        .time_utc_us = ts,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try std.testing.expectEqual(ts, rec.time_utc_us);
}

// ============================================================================
// Record Source Location Tests
// ============================================================================

test "Record - with source location" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .@"error",
        .msg_id = "error.occurred",
        .message = "Something went wrong",
        .logger = "myapp",
        .source_file = "/path/to/file.zig",
        .source_line = 123,
        .attrs = &.{},
    };

    try std.testing.expectEqualStrings("/path/to/file.zig", rec.source_file);
    try std.testing.expectEqual(@as(u32, 123), rec.source_line);
}

test "Record - source line zero" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "file.zig",
        .source_line = 0,
        .attrs = &.{},
    };

    try std.testing.expectEqual(@as(u32, 0), rec.source_line);
}

test "Record - max source line" {
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "file.zig",
        .source_line = std.math.maxInt(u32),
        .attrs = &.{},
    };

    try std.testing.expectEqual(std.math.maxInt(u32), rec.source_line);
}

// ============================================================================
// Record with Complex Attributes Tests
// ============================================================================

test "Record - mixed attribute types" {
    const attrs = [_]Attr{
        Attr.string("str", "value"),
        Attr.int("int", -42),
        Attr.uint("uint", 42),
        Attr.float("float", 3.14),
        Attr.boolean("bool", true),
        Attr.err("err", error.Test),
        Attr.secret("secret", "hidden"),
    };

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &attrs,
    };

    try std.testing.expectEqual(@as(usize, 7), rec.attrs.len);
}
