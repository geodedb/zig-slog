// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Discard handler - drops all log records.
//!
//! Useful for benchmarking or disabling logging entirely.

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;

const Context = struct {
    level: std.atomic.Value(i32),
};

var global_context = Context{ .level = std.atomic.Value(i32).init(@intFromEnum(Level.info)) };

fn handle(_: *anyopaque, _: *const Record) HandlerError!void {
    // Discard
}

fn withAttrs(_: *anyopaque, _: []const Attr) Handler {
    return init();
}

fn withGroup(_: *anyopaque, _: []const u8) Handler {
    return init();
}

fn setLevel(ctx: *anyopaque, level: Level) void {
    const c: *Context = @ptrCast(@alignCast(ctx));
    c.level.store(@intFromEnum(level), .release);
}

fn flush(_: *anyopaque, _: u32) HandlerError!void {
    // Nothing to flush
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
};

/// Initialize a discard handler.
pub fn init() Handler {
    return .{
        .ctx = @ptrCast(&global_context),
        .vtable = &vtable,
    };
}

test "DiscardHandler basic" {
    const handler = init();
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
    try handler.handle(&rec);
    try handler.flush(0);
}
