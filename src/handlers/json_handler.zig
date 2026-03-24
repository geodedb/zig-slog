// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! JSON handler - structured JSON log output.
//!
//! Format: {"time":"...","level":"...","msg":"...","logger":"...","source":{...},"attrs":{...}}
//! Key order is stable: time, level, msg, logger, source, attrs

const std = @import("std");
const json = @import("json");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Value = @import("../value.zig").Value;
const Secret = @import("../value.zig").Secret;
const Record = @import("../record.zig").Record;
const RecordError = @import("../record.zig").RecordError;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const rfc3339 = @import("../fmt/rfc3339.zig");
const redact = @import("../util/redact.zig");
const sanitize = @import("../util/sanitize.zig");
const metrics = @import("../metrics/metrics.zig");

/// JSON handler context.
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

    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Use a fixed buffer allocator for the encoder's state stack (max depth 3)
    var stack_buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&stack_buf);

    var enc = json.streamingEncoder(fba.allocator(), writer, .{});
    defer enc.deinit();

    enc.beginObject() catch return error.WriteFailed;

    // time (first, stable order)
    var ts_buf: [27]u8 = undefined;
    rfc3339.formatTimestamp(&ts_buf, rec.time_utc_us);
    enc.writeKey("time") catch return error.WriteFailed;
    enc.writeString(&ts_buf) catch return error.WriteFailed;

    // level
    enc.writeKey("level") catch return error.WriteFailed;
    enc.writeString(rec.level.asText()) catch return error.WriteFailed;

    // msg
    enc.writeKey("msg") catch return error.WriteFailed;
    enc.writeString(rec.message) catch return error.WriteFailed;

    // logger (if present)
    if (rec.logger.len > 0) {
        enc.writeKey("logger") catch return error.WriteFailed;
        enc.writeString(rec.logger) catch return error.WriteFailed;
    }

    // source (if present)
    if (rec.source_file.len > 0) {
        enc.writeKey("source") catch return error.WriteFailed;
        enc.beginObject() catch return error.WriteFailed;
        enc.writeKey("file") catch return error.WriteFailed;
        enc.writeString(rec.source_file) catch return error.WriteFailed;
        enc.writeKey("line") catch return error.WriteFailed;
        enc.writeInt(rec.source_line) catch return error.WriteFailed;
        enc.endObject() catch return error.WriteFailed;
    }

    // attrs object (context + record attrs)
    if (ctx.context_attrs.len > 0 or rec.attrs.len > 0) {
        enc.writeKey("attrs") catch return error.WriteFailed;
        enc.beginObject() catch return error.WriteFailed;

        // Context attrs
        for (ctx.context_attrs) |attr| {
            writeJsonAttr(&enc, attr, ctx.prefix) catch return error.WriteFailed;
        }

        // Record attrs
        for (rec.attrs) |attr| {
            writeJsonAttr(&enc, attr, ctx.prefix) catch return error.WriteFailed;
        }

        enc.endObject() catch return error.WriteFailed;
    }

    enc.endObject() catch return error.WriteFailed;
    writer.writeByte('\n') catch return error.WriteFailed;

    const output = fbs.getWritten();
    ctx.writer.writeAll(output) catch return error.WriteFailed;
    metrics.global.addBytesWritten(output.len);
}

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

fn writeJsonValue(enc: anytype, value: Value) !void {
    switch (value) {
        .str => |s| enc.writeString(s) catch return error.WriteFailed,
        .i64 => |i| enc.writeInt(i) catch return error.WriteFailed,
        .u64 => |u| enc.writeInt(u) catch return error.WriteFailed,
        .f64 => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                enc.writeNull() catch return error.WriteFailed;
            } else {
                enc.writeFloat(f) catch return error.WriteFailed;
            }
        },
        .bool => |b| enc.writeBool(b) catch return error.WriteFailed,
        .bytes => |b| {
            // Encode bytes as hex string
            var hex_buf: [512]u8 = undefined;
            var hex_len: usize = 0;
            for (b) |byte| {
                if (hex_len + 2 > hex_buf.len) break;
                const hex_chars = "0123456789abcdef";
                hex_buf[hex_len] = hex_chars[byte >> 4];
                hex_buf[hex_len + 1] = hex_chars[byte & 0x0f];
                hex_len += 2;
            }
            enc.writeString(hex_buf[0..hex_len]) catch return error.WriteFailed;
        },
        .err => |e| {
            const raw: u16 = @intFromError(e);
            if (raw == 0) {
                enc.writeString("error(0)") catch return error.WriteFailed;
            } else {
                enc.writeString(@errorName(e)) catch return error.WriteFailed;
            }
        },
        .secret => enc.writeString(redact.REDACTED) catch return error.WriteFailed,
        .marshaler => enc.writeNull() catch return error.WriteFailed,
    }
}

fn withAttrs(ctx_ptr: *anyopaque, _: []const Attr) Handler {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
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
    // JSON handler writes immediately
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
};

/// Initialize a JSON handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

/// Create JSON handler context with a writer.
pub fn initWithWriter(writer: std.io.AnyWriter, level: Level, clock: Clock) Context {
    return Context.init(writer, level, clock);
}

test "JSONHandler basic output" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

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

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // Verify JSON structure
    try std.testing.expect(std.mem.indexOf(u8, output, "\"time\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":\"INFO\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"app.started\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"logger\":\"web\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source\":{\"file\":\"main.zig\",\"line\":42}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"port\":8080") != null);
}

test "JSONHandler escaping" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var ctx = Context.init(fbs.writer().any(), .info, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test \"quoted\" and\nnewline",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "\\\"quoted\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\n") != null);
}

test "JSONHandler secret redaction" {
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
            Attr.secret("api_key", "secret123"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "secret123") == null);
}

test "JSONHandler auto-redacts sensitive keys" {
    var buf: [2048]u8 = undefined;
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
            Attr.string("password", "hunter2"),
            Attr.string("user", "alice"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.getWritten();

    // password should be redacted
    try std.testing.expect(std.mem.indexOf(u8, output, "hunter2") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    // user should pass through
    try std.testing.expect(std.mem.indexOf(u8, output, "\"user\":\"alice\"") != null);
}

test "JSONHandler NaN/Inf written as null" {
    var buf: [2048]u8 = undefined;
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
            Attr.float("nan_val", std.math.nan(f64)),
            Attr.float("inf_val", std.math.inf(f64)),
        },
    };

    // Should succeed (previously would return InvalidRecord)
    try handler.handle(&rec);
    const output = fbs.getWritten();

    // NaN and Inf should be written as null
    try std.testing.expect(std.mem.indexOf(u8, output, "\"nan_val\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"inf_val\":null") != null);
}
