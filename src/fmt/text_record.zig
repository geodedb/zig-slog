// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Shared text record formatting for all text-mode handlers.
//!
//! Provides a canonical `writeTextRecord` function that serializes a `Record`
//! into a human-readable log line:
//!
//!   YYYY-MM-DDTHH:MM:SS.ffffffZ LEVEL logger msg [msg_id=...] key=value ...
//!
//! Used by text_handler and rotating_file.

const std = @import("std");
const Attr = @import("../value.zig").Attr;
const Value = @import("../value.zig").Value;
const Record = @import("../record.zig").Record;
const rfc3339 = @import("rfc3339.zig");
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");
const writeTextValue = @import("text_value.zig").writeTextValue;

/// Write a complete text log line to the given writer.
///
/// The `prefix` parameter is for group-prefix support on attribute keys.
pub fn writeTextRecord(writer: anytype, rec: *const Record, prefix: []const u8) !void {
    // Timestamp
    var ts_buf: [27]u8 = undefined;
    rfc3339.formatTimestamp(&ts_buf, rec.time_utc_us);
    try writer.writeAll(&ts_buf);
    try writer.writeByte(' ');

    // Level
    try writer.writeAll(rec.level.asText());
    try writer.writeByte(' ');

    // Logger name (sanitize to prevent log injection)
    if (rec.logger.len > 0) {
        try sanitize.sanitizeOutput(writer, rec.logger);
        try writer.writeByte(' ');
    }

    // Message (sanitize to prevent log injection)
    try sanitize.sanitizeOutput(writer, rec.message);

    // msg_id (if present and differs from message)
    if (rec.msg_id.len > 0 and !std.mem.eql(u8, rec.msg_id, rec.message)) {
        try writer.writeAll(" msg_id=");
        try sanitize.sanitizeOutput(writer, rec.msg_id);
    }

    // Record attributes
    for (rec.attrs) |attr| {
        try writer.writeByte(' ');
        try writeTextAttr(writer, attr, prefix);
    }

    try writer.writeByte('\n');
}

/// Write a single text attribute (key=value) with optional prefix,
/// sanitization, and auto-redaction.
fn writeTextAttr(writer: anytype, attr: Attr, prefix: []const u8) !void {
    // Write key with optional prefix
    if (prefix.len > 0) {
        try writer.writeAll(prefix);
        try writer.writeByte('.');
    }

    // Sanitize and write key
    var key_buf: [sanitize.MAX_KEY_LENGTH]u8 = undefined;
    const key = sanitize.sanitizeKey(&key_buf, attr.key);
    try writer.writeAll(key);
    try writer.writeByte('=');

    // Auto-redact sensitive keys
    if (redact.isSensitiveKey(attr.key)) {
        try writer.writeAll(redact.REDACTED);
    } else {
        try writeTextAttrValue(writer, attr.value);
    }
}

/// Write a value for text output. Delegates to the shared writeTextValue for
/// all variants except `.str`, which gets quoting when the string contains
/// spaces or '=' (specific to the key=value text line format).
fn writeTextAttrValue(writer: anytype, value: Value) !void {
    switch (value) {
        .str => |s| {
            // Quote if contains spaces or '=' to preserve key=value parsing
            const needs_quote = std.mem.indexOfScalar(u8, s, ' ') != null or
                std.mem.indexOfScalar(u8, s, '=') != null;
            if (needs_quote) try writer.writeByte('"');
            try sanitize.sanitizeOutput(writer, s);
            if (needs_quote) try writer.writeByte('"');
        },
        else => try writeTextValue(writer, value),
    }
}

// --- Tests ---

test "writeTextRecord basic" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "app.started",
        .message = "app.started",
        .logger = "web",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("key", "value"),
            Attr.int("count", 42),
        },
    };

    try writeTextRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "INFO") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "web") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "app.started") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "key=value") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "count=42") != null);
    // msg_id should NOT appear when same as message
    try std.testing.expect(std.mem.indexOf(u8, output, "msg_id=") == null);
    // Should end with newline
    try std.testing.expect(output[output.len - 1] == '\n');
}

test "writeTextRecord with msg_id" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 0,
        .level = .warn,
        .msg_id = "error.timeout",
        .message = "Connection timed out",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try writeTextRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "msg_id=error.timeout") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Connection timed out") != null);
}

test "writeTextRecord redacts sensitive keys" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("password", "hunter2"),
            Attr.string("user", "alice"),
        },
    };

    try writeTextRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "hunter2") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "user=alice") != null);
}

test "writeTextRecord with prefix" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("key", "value"),
        },
    };

    try writeTextRecord(fbs.writer(), &rec, "http");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "http.key=value") != null);
}

test "writeTextRecord sanitizes newlines in message" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "line1\nline2",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try writeTextRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "line1\\nline2") != null);
    // Only 1 raw newline (the line terminator)
    var newlines: usize = 0;
    for (output) |c| {
        if (c == '\n') newlines += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), newlines);
}
