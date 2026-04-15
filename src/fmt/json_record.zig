// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Shared JSON record formatting for all JSON-emitting handlers and sinks.
//!
//! Provides a canonical `writeJsonRecord` function that serializes a `Record`
//! into a JSON-lines object using the flat schema:
//!
//!   {"time":"...","level":"...","msg":"...","msg_id":"...",
//!    "logger":"...","source_file":"...","source_line":N,...attrs}
//!
//! Used by json_handler, tcp_sink, udp_sink, and http_sink.

const std = @import("std");
const json = @import("json");
const Record = @import("../record.zig").Record;
const Attr = @import("../value.zig").Attr;
const rfc3339 = @import("rfc3339.zig");
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");
const writeJsonValue = @import("json_value.zig").writeJsonValue;

/// Write a complete JSON-lines record to the given fixed-buffer stream writer.
///
/// The caller is responsible for:
/// - Providing a sufficiently large buffer (16KB recommended)
/// - Writing the result to the final destination (file, network, etc.)
/// - Mutex locking around the final write if needed
///
/// The `prefix` parameter is for group-prefix support on attribute keys.
pub fn writeJsonRecord(writer: anytype, rec: *const Record, prefix: []const u8) !void {
    // Use a fixed buffer allocator for the encoder's state stack (max depth 1)
    var stack_buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&stack_buf);

    var enc = json.streamingEncoder(fba.allocator(), writer, .{});
    defer enc.deinit();

    try enc.beginObject();

    // time (first, stable order)
    var ts_buf: [27]u8 = undefined;
    rfc3339.formatTimestamp(&ts_buf, rec.time_utc_us);
    try enc.writeKey("time");
    try enc.writeString(&ts_buf);

    // level
    try enc.writeKey("level");
    try enc.writeString(rec.level.asText());

    // msg
    try enc.writeKey("msg");
    try enc.writeString(rec.message);

    // msg_id (if present and differs from message)
    if (rec.msg_id.len > 0 and !std.mem.eql(u8, rec.msg_id, rec.message)) {
        try enc.writeKey("msg_id");
        try enc.writeString(rec.msg_id);
    }

    // logger (if present)
    if (rec.logger.len > 0) {
        try enc.writeKey("logger");
        try enc.writeString(rec.logger);
    }

    // source (flat keys, if present)
    if (rec.source_file.len > 0) {
        try enc.writeKey("source_file");
        try enc.writeString(rec.source_file);
        try enc.writeKey("source_line");
        try enc.writeInt(rec.source_line);
    }

    // attrs (flat, at top level)
    for (rec.attrs) |attr| {
        try writeJsonAttr(&enc, attr, prefix);
    }

    try enc.endObject();
    try writer.writeByte('\n');
}

/// Write a single JSON attribute (key + value) with optional prefix,
/// sanitization, and auto-redaction.
fn writeJsonAttr(enc: anytype, attr: Attr, prefix: []const u8) !void {
    // Build the key with optional prefix
    var key_buf: [sanitize.MAX_KEY_LENGTH + 64]u8 = undefined;
    var key_len: usize = 0;

    if (prefix.len > 0) {
        @memcpy(key_buf[0..prefix.len], prefix);
        key_len = prefix.len;
        key_buf[key_len] = '.';
        key_len += 1;
    }

    var sanitized_buf: [sanitize.MAX_KEY_LENGTH]u8 = undefined;
    const sanitized_key = sanitize.sanitizeKey(&sanitized_buf, attr.key);
    @memcpy(key_buf[key_len..][0..sanitized_key.len], sanitized_key);
    key_len += sanitized_key.len;

    enc.writeKey(key_buf[0..key_len]) catch return error.WriteFailed;

    // Auto-redact sensitive keys
    if (redact.isSensitiveKey(attr.key)) {
        enc.writeString(redact.REDACTED) catch return error.WriteFailed;
    } else {
        try writeJsonValue(enc, attr.value);
    }
}

// --- Tests ---

test "writeJsonRecord basic" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "app.started",
        .message = "app.started",
        .logger = "web",
        .source_file = "main.zig",
        .source_line = 42,
        .attrs = &.{
            Attr.int("port", 8080),
            Attr.string("commit", "abc123"),
        },
    };

    try writeJsonRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"time\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":\"INFO\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"app.started\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"logger\":\"web\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source_file\":\"main.zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source_line\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"port\":8080") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"commit\":\"abc123\"") != null);
    // msg_id should NOT appear when same as message
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg_id\"") == null);
    // Should end with newline
    try std.testing.expect(output[output.len - 1] == '\n');
}

test "writeJsonRecord with msg_id" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 0,
        .level = .warn,
        .msg_id = "error.timeout",
        .message = "Connection timed out after 30s",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try writeJsonRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg_id\":\"error.timeout\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"Connection timed out after 30s\"") != null);
}

test "writeJsonRecord redacts sensitive keys" {
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

    try writeJsonRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "hunter2") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"user\":\"alice\"") != null);
}

test "writeJsonRecord with prefix" {
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

    try writeJsonRecord(fbs.writer(), &rec, "http");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"http.key\":\"value\"") != null);
}

test "writeJsonRecord no source when empty" {
    var buf: [4096]u8 = undefined;
    var fbs = std.Io.fixedBufferStream(&buf);

    const rec = Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try writeJsonRecord(fbs.writer(), &rec, "");
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "source_file") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "source_line") == null);
}
