// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Text handler - human-readable log output.
//!
//! Format: YYYY-MM-DDTHH:MM:SS.ffffffZ LEVEL logger msg key=value ...

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Value = @import("../value.zig").Value;
const Secret = @import("../value.zig").Secret;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const rfc3339 = @import("../fmt/rfc3339.zig");
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");
const metrics = @import("../metrics/metrics.zig");

/// Text handler context.
pub const Context = struct {
    writer: std.io.AnyWriter,
    level: Level,
    clock: Clock,
    prefix: []const u8,
    context_attrs: []const Attr,
    mutex: std.Thread.Mutex,

    pub fn init(writer: std.io.AnyWriter, level: Level, clock: Clock) Context {
        return .{
            .writer = writer,
            .level = level,
            .clock = clock,
            .prefix = "",
            .context_attrs = &.{},
            .mutex = .{},
        };
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (!rec.level.atLeast(ctx.level)) return;

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Timestamp
    var ts_buf: [27]u8 = undefined;
    rfc3339.formatTimestamp(&ts_buf, rec.time_utc_us);
    writer.writeAll(&ts_buf) catch return error.WriteFailed;
    writer.writeByte(' ') catch return error.WriteFailed;

    // Level
    writer.writeAll(rec.level.asText()) catch return error.WriteFailed;
    writer.writeByte(' ') catch return error.WriteFailed;

    // Logger name
    if (rec.logger.len > 0) {
        writer.writeAll(rec.logger) catch return error.WriteFailed;
        writer.writeByte(' ') catch return error.WriteFailed;
    }

    // Message (sanitize to prevent log injection)
    sanitize.sanitizeOutput(writer, rec.message) catch return error.WriteFailed;

    // Context attributes
    for (ctx.context_attrs) |attr| {
        writer.writeByte(' ') catch return error.WriteFailed;
        writeAttr(writer, attr, ctx.prefix) catch return error.WriteFailed;
    }

    // Record attributes
    for (rec.attrs) |attr| {
        writer.writeByte(' ') catch return error.WriteFailed;
        writeAttr(writer, attr, ctx.prefix) catch return error.WriteFailed;
    }

    writer.writeByte('\n') catch return error.WriteFailed;

    const output = fbs.getWritten();
    ctx.writer.writeAll(output) catch return error.WriteFailed;
    metrics.global.addBytesWritten(output.len);
}

fn writeAttr(writer: anytype, attr: Attr, prefix: []const u8) !void {
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
        try writeValue(writer, attr.value);
    }
}

fn writeValue(writer: anytype, value: Value) !void {
    switch (value) {
        .str => |s| {
            // Quote if contains spaces
            const needs_quote = std.mem.indexOfScalar(u8, s, ' ') != null or
                std.mem.indexOfScalar(u8, s, '=') != null;
            if (needs_quote) try writer.writeByte('"');
            try sanitize.sanitizeOutput(writer, s);
            if (needs_quote) try writer.writeByte('"');
        },
        .i64 => |i| try writer.print("{d}", .{i}),
        .u64 => |u| try writer.print("{d}", .{u}),
        .f64 => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                try writer.writeAll("null");
            } else {
                try writer.print("{d:.6}", .{f});
            }
        },
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .bytes => |b| {
            try writer.writeAll("0x");
            const hex_chars = "0123456789abcdef";
            for (b) |byte| {
                try writer.writeAll(&[2]u8{ hex_chars[byte >> 4], hex_chars[byte & 0x0f] });
            }
        },
        .err => |e| {
            // Eagerly resolve error name; guard against corrupt error values
            // that could cause @errorName to access an invalid table index.
            const raw: u16 = @intFromError(e);
            if (raw == 0) {
                try writer.writeAll("error(0)");
            } else {
                try writer.writeAll(@errorName(e));
            }
        },
        .secret => try writer.writeAll(redact.REDACTED),
        .marshaler => try writer.writeAll("<marshaler>"),
    }
}

fn withAttrs(ctx_ptr: *anyopaque, _: []const Attr) Handler {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    // Return same handler (simplified - real impl would copy context)
    return .{
        .ctx = ctx,
        .vtable = &vtable,
    };
}

fn withGroup(ctx_ptr: *anyopaque, _: []const u8) Handler {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    return .{
        .ctx = ctx,
        .vtable = &vtable,
    };
}

fn setLevel(ctx_ptr: *anyopaque, level: Level) void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    ctx.level = level;
}

fn flush(_: *anyopaque, _: u32) HandlerError!void {
    // Text handler writes immediately, nothing to flush
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
};

/// Initialize a text handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

/// Create text handler with a writer.
pub fn initWithWriter(writer: std.io.AnyWriter, level: Level, clock: Clock) Context {
    return Context.init(writer, level, clock);
}

test "TextHandler basic output" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "test.message",
        .message = "test.message",
        .logger = "web",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("key", "value"),
            Attr.int("count", 42),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "INFO") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "web") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "key=value") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "count=42") != null);
}

test "TextHandler secret redaction" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.secret("password", "super_secret"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "super_secret") == null);
}

test "TextHandler error attribute" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "error test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.err("err", error.OutOfMemory),
            Attr.string("ctx", "test"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "err=OutOfMemory") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ctx=test") != null);
}

test "TextHandler auto-redacts sensitive keys" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("api_key", "sk-12345"),
            Attr.string("user", "alice"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // api_key should be redacted
    try std.testing.expect(std.mem.indexOf(u8, output, "api_key=" ++ redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sk-12345") == null);
    // non-sensitive key should pass through
    try std.testing.expect(std.mem.indexOf(u8, output, "user=alice") != null);
}

test "TextHandler sanitizes message newlines" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "line1\nline2\rline3",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // Newlines should be escaped
    try std.testing.expect(std.mem.indexOf(u8, output, "line1\\nline2\\rline3") != null);
    // Should not contain raw newline in the message part (note: ends with \n for line termination)
    // Count newlines - should be exactly 1 (the final line terminator)
    var newlines: usize = 0;
    for (output) |c| {
        if (c == '\n') newlines += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), newlines);
}

test "TextHandler sanitizes string value control chars" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("data", "value\twith\ttabs"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // Tabs should be escaped
    try std.testing.expect(std.mem.indexOf(u8, output, "value\\twith\\ttabs") != null);
}

test "TextHandler key sanitization with control characters" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .trace, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "sanitize test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("bad\nkey", "value1"),
            Attr.string("bad\rkey", "value2"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // Control characters in keys should be replaced with '_' by sanitizeKey
    try std.testing.expect(std.mem.indexOf(u8, output, "bad_key=value1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bad_key=value2") != null);
    // Original control characters should not appear in the key portion
    try std.testing.expect(std.mem.indexOf(u8, output, "bad\nkey") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bad\rkey") == null);
}

test "TextHandler all value types" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .trace, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "value types",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("str_key", "hello"),
            Attr.int("i64_key", -42),
            Attr.uint("u64_key", 999),
            Attr.float("f64_key", 3.140000),
            Attr.boolean("bool_true", true),
            Attr.boolean("bool_false", false),
            Attr.bytes("bytes_key", &[_]u8{ 0xDE, 0xAD }),
            Attr.err("err_key", error.OutOfMemory),
            Attr.secret("secret_key", "my_secret"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "str_key=hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "i64_key=-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "u64_key=999") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "f64_key=3.14") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bool_true=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bool_false=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bytes_key=0xdead") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "err_key=OutOfMemory") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "secret_key=[REDACTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "my_secret") == null);
}

test "TextHandler f64 NaN and Inf render as null" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .trace, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "nan test",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.float("nan_val", std.math.nan(f64)),
            Attr.float("inf_val", std.math.inf(f64)),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "nan_val=null") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "inf_val=null") != null);
}

test "TextHandler level filtering" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .warn, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "test",
        .message = "should not appear",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expectEqual(@as(usize, 0), output.len);
}
