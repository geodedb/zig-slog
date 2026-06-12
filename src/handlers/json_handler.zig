// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! JSON handler - structured JSON log output.
//!
//! Format: {"time":"...","level":"...","msg":"...","logger":"...","source_file":"...","source_line":N,...attrs}
//! Key order is stable: time, level, msg, msg_id (if differs), logger, source_file, source_line, attrs (flat)

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const redact = @import("../util/redact.zig");
const metrics = @import("../metrics/metrics.zig");
const writeJsonRecord = @import("../fmt/json_record.zig").writeJsonRecord;

/// JSON handler context.
pub const Context = struct {
    writer: *std.Io.Writer,
    level: std.atomic.Value(i32),
    clock: Clock,
    prefix: []const u8,
    context_attrs: []const Attr,
    mutex: std.Io.Mutex,

    pub fn init(writer: *std.Io.Writer, level: Level, clock: Clock) Context {
        return .{
            .writer = writer,
            .level = std.atomic.Value(i32).init(@intFromEnum(level)),
            .clock = clock,
            .prefix = "",
            .context_attrs = &.{},
            .mutex = std.Io.Mutex.init,
        };
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    ctx.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
    defer ctx.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

    var buf: [16384]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    // Known SEC-0039 residual: a record whose JSON rendering exceeds 16KB
    // (possible within the 64KB record budget, especially with escaping
    // expansion) is dropped whole rather than truncated -- truncating JSON
    // mid-document would emit invalid JSON to downstream parsers. Tracked
    // as a follow-up; text/rotating handlers truncate with a marker.
    writeJsonRecord(&fbs, rec, ctx.prefix) catch return error.WriteFailed;

    const output = fbs.buffered();
    ctx.writer.writeAll(output) catch return error.WriteFailed;
    metrics.global.addBytesWritten(output.len);
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
    ctx.level.store(@intFromEnum(level), .release);
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
pub fn initWithWriter(writer: *std.Io.Writer, level: Level, clock: Clock) Context {
    return Context.init(writer, level, clock);
}

test "JSONHandler basic output" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, Clock.system());
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
    const output = fbs.buffered();

    // Verify JSON structure
    try std.testing.expect(std.mem.indexOf(u8, output, "\"time\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":\"INFO\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"app.started\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"logger\":\"web\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source_file\":\"main.zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source_line\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"port\":8080") != null);
}

test "JSONHandler escaping" {
    var buf: [1024]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, Clock.system());
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
    const output = fbs.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, "\\\"quoted\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\n") != null);
}

test "JSONHandler secret redaction" {
    var buf: [1024]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, Clock.system());
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
    const output = fbs.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "secret123") == null);
}

test "JSONHandler auto-redacts sensitive keys" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, Clock.system());
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
    const output = fbs.buffered();

    // password should be redacted
    try std.testing.expect(std.mem.indexOf(u8, output, "hunter2") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, redact.REDACTED) != null);
    // user should pass through
    try std.testing.expect(std.mem.indexOf(u8, output, "\"user\":\"alice\"") != null);
}

test "JSONHandler NaN/Inf written as null" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, Clock.system());
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
    const output = fbs.buffered();

    // NaN and Inf should be written as null
    try std.testing.expect(std.mem.indexOf(u8, output, "\"nan_val\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"inf_val\":null") != null);
}

test "JSONHandler all value types" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .trace, Clock.system());
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
            Attr.float("f64_key", 2.5),
            Attr.boolean("bool_true", true),
            Attr.boolean("bool_false", false),
            Attr.bytes("bytes_key", &[_]u8{ 0xCA, 0xFE }),
            Attr.err("err_key", error.OutOfMemory),
            Attr.secret("secret_key", "top_secret"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"str_key\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"i64_key\":-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"u64_key\":999") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"f64_key\":2.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"bool_true\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"bool_false\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"bytes_key\":\"cafe\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"err_key\":\"OutOfMemory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"secret_key\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "top_secret") == null);
}

test "JSONHandler level filtering" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .@"error", Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "should be filtered",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    try std.testing.expectEqual(@as(usize, 0), output.len);
}

test "JSONHandler key sanitization" {
    var buf: [4096]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .trace, Clock.system());
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "key sanitize",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{
            Attr.string("valid_key", "ok"),
            Attr.string("bad key!", "sanitized"),
        },
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"valid_key\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"bad_key_\":\"sanitized\"") != null);
}

test "JSONHandler msg_id when different from message" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, Clock.system());
    const handler = init(&ctx);

    // msg_id differs from message (e.g., after i18n translation)
    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "app.started",
        .message = "Application started successfully",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"Application started successfully\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg_id\":\"app.started\"") != null);
}

test "JSONHandler msg_id omitted when same as message" {
    var buf: [2048]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var ctx = Context.init(&fbs, .info, Clock.system());
    const handler = init(&ctx);

    // msg_id same as message (common case, no translation)
    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "same.message",
        .message = "same.message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    const output = fbs.buffered();

    // msg_id should NOT appear when it equals message
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg_id\"") == null);
}
