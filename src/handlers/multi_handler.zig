// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Multi-handler - fans out log records to multiple handlers simultaneously.
//!
//! Delivers each log record to all child handlers. If any handler returns
//! an error, delivery continues to the remaining handlers and the first
//! error encountered is returned after all handlers have been tried.

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const parallel = @import("../parallel.zig");

/// Multi-handler context holding a slice of child handlers.
pub const Context = struct {
    handlers: []const Handler,
    level: std.atomic.Value(i32),

    pub fn init(handlers: []const Handler, level: Level) Context {
        return .{ .handlers = handlers, .level = std.atomic.Value(i32).init(@intFromEnum(level)) };
    }

    pub fn deinit(_: *Context) void {}
};

/// Maximum number of handlers that can be dispatched in parallel
/// without heap allocation (stack-allocated result buffer).
const MAX_PARALLEL_HANDLERS = 16;

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    if (ctx.handlers.len <= MAX_PARALLEL_HANDLERS) {
        var results: [MAX_PARALLEL_HANDLERS]parallel.MultiHandlerResult = undefined;
        parallel.dispatchHandlers(ctx.handlers, rec, results[0..ctx.handlers.len]);

        var first_err: ?HandlerError = null;
        for (results[0..ctx.handlers.len]) |r| {
            if (r.err != null and first_err == null) first_err = r.err;
        }
        if (first_err) |err| return err;
    } else {
        // Fallback for > MAX_PARALLEL_HANDLERS: sequential dispatch
        var first_err: ?HandlerError = null;
        for (ctx.handlers) |h| {
            h.handle(rec) catch |err| {
                if (first_err == null) first_err = err;
            };
        }
        if (first_err) |err| return err;
    }
}

fn withAttrs(ctx_ptr: *anyopaque, _: []const Attr) Handler {
    return .{
        .ctx = ctx_ptr,
        .vtable = &vtable,
    };
}

fn withGroup(ctx_ptr: *anyopaque, _: []const u8) Handler {
    return .{
        .ctx = ctx_ptr,
        .vtable = &vtable,
    };
}

fn setLevel(ctx_ptr: *anyopaque, level: Level) void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    ctx.level.store(@intFromEnum(level), .release);

    for (ctx.handlers) |h| {
        h.setLevel(level);
    }
}

fn flush(ctx_ptr: *anyopaque, timeout_ms: u32) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (ctx.handlers.len <= MAX_PARALLEL_HANDLERS) {
        var results: [MAX_PARALLEL_HANDLERS]parallel.MultiFlushResult = undefined;
        parallel.flushHandlers(ctx.handlers, timeout_ms, results[0..ctx.handlers.len]);

        var first_err: ?HandlerError = null;
        for (results[0..ctx.handlers.len]) |r| {
            if (r.err != null and first_err == null) first_err = r.err;
        }
        if (first_err) |err| return err;
    } else {
        var first_err: ?HandlerError = null;
        for (ctx.handlers) |h| {
            h.flush(timeout_ms) catch |err| {
                if (first_err == null) first_err = err;
            };
        }
        if (first_err) |err| return err;
    }
}

fn getLevel(ctx_ptr: *anyopaque) Level {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    return @enumFromInt(ctx.level.load(.acquire));
}

fn close(ctx_ptr: *anyopaque) void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    for (ctx.handlers) |h| {
        h.close();
    }
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
    .getLevel = getLevel,
    .close = close,
};

/// Initialize a multi-handler that fans out to all provided child handlers.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const Clock = @import("../internal/clock.zig").Clock;
const text_handler = @import("text_handler.zig");

test "MultiHandler delivers records to all children" {
    var buf1: [4096]u8 = undefined;
    var fbs1 = std.io.fixedBufferStream(&buf1);
    var buf2: [4096]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);

    var text_ctx1 = text_handler.Context.init(fbs1.writer().any(), .info, Clock.system());
    var text_ctx2 = text_handler.Context.init(fbs2.writer().any(), .info, Clock.system());

    const children = [_]Handler{
        text_handler.init(&text_ctx1),
        text_handler.init(&text_ctx2),
    };

    var ctx = Context.init(&children, .info);
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 1735787045000000,
        .level = .info,
        .msg_id = "multi.test",
        .message = "hello multi",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);

    const out1 = fbs1.getWritten();
    const out2 = fbs2.getWritten();

    try std.testing.expect(out1.len > 0);
    try std.testing.expect(out2.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out1, "hello multi") != null);
    try std.testing.expect(std.mem.indexOf(u8, out2, "hello multi") != null);
}

test "MultiHandler level filtering" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var text_ctx = text_handler.Context.init(fbs.writer().any(), .trace, Clock.system());

    const children = [_]Handler{
        text_handler.init(&text_ctx),
    };

    // Multi-handler set to warn -- should filter out info records even though
    // the child text handler would accept them.
    var ctx = Context.init(&children, .warn);
    const handler = init(&ctx);

    const debug_rec = Record{
        .time_utc_us = 0,
        .level = .debug,
        .msg_id = "dbg",
        .message = "debug message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&debug_rec);
    try std.testing.expectEqual(@as(usize, 0), fbs.getWritten().len);

    const warn_rec = Record{
        .time_utc_us = 0,
        .level = .warn,
        .msg_id = "wrn",
        .message = "warning message",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&warn_rec);
    try std.testing.expect(fbs.getWritten().len > 0);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "warning message") != null);
}

test "MultiHandler flush propagates to all children" {
    var buf1: [4096]u8 = undefined;
    var fbs1 = std.io.fixedBufferStream(&buf1);
    var buf2: [4096]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);

    var text_ctx1 = text_handler.Context.init(fbs1.writer().any(), .info, Clock.system());
    var text_ctx2 = text_handler.Context.init(fbs2.writer().any(), .info, Clock.system());

    const children = [_]Handler{
        text_handler.init(&text_ctx1),
        text_handler.init(&text_ctx2),
    };

    var ctx = Context.init(&children, .info);
    const handler = init(&ctx);

    // flush should succeed without error for text handlers
    try handler.flush(1000);
}

// A small helper handler whose handle function always returns an error.
const failing_vtable = HandlerVTable{
    .handle = struct {
        fn f(_: *anyopaque, _: *const Record) HandlerError!void {
            return error.WriteFailed;
        }
    }.f,
    .withAttrs = struct {
        fn f(c: *anyopaque, _: []const Attr) Handler {
            return .{ .ctx = c, .vtable = &failing_vtable };
        }
    }.f,
    .withGroup = struct {
        fn f(c: *anyopaque, _: []const u8) Handler {
            return .{ .ctx = c, .vtable = &failing_vtable };
        }
    }.f,
    .setLevel = struct {
        fn f(_: *anyopaque, _: Level) void {}
    }.f,
    .flush = struct {
        fn f(_: *anyopaque, _: u32) HandlerError!void {}
    }.f,
};

var failing_ctx_storage: u8 = 0;

test "MultiHandler one handler error does not prevent delivery to others" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var text_ctx = text_handler.Context.init(fbs.writer().any(), .info, Clock.system());

    const failing_handler = Handler{
        .ctx = @ptrCast(&failing_ctx_storage),
        .vtable = &failing_vtable,
    };

    // Failing handler first, text handler second -- text handler should still
    // receive the record even though the first handler errors.
    const children = [_]Handler{
        failing_handler,
        text_handler.init(&text_ctx),
    };

    var ctx = Context.init(&children, .info);
    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "err.test",
        .message = "should still arrive",
        .logger = "",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    // Should return the first error (WriteFailed) ...
    const result = handler.handle(&rec);
    try std.testing.expectError(error.WriteFailed, result);

    // ... but the text handler should have still received the record.
    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "should still arrive") != null);
}
