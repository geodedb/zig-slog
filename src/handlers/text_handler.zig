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

    // Message
    writer.writeAll(rec.message) catch return error.WriteFailed;

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

    // Write value
    try writeValue(writer, attr.value);
}

fn writeValue(writer: anytype, value: Value) !void {
    switch (value) {
        .str => |s| {
            // Quote if contains spaces
            const needs_quote = std.mem.indexOfScalar(u8, s, ' ') != null or
                std.mem.indexOfScalar(u8, s, '=') != null;
            if (needs_quote) try writer.writeByte('"');
            try writer.writeAll(s);
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
            for (b) |byte| {
                try writer.print("{x:0>2}", .{byte});
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
