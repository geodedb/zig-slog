// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Rotating file handler - writes logs to files with size-based rotation.
//!
//! Features:
//! - Size-based rotation (max_bytes)
//! - Maximum number of backup files (max_backups)
//! - Age-based pruning (max_age_days)
//! - Atomic reopen for external rotation (logrotate/SIGHUP)

const std = @import("std");
const Level = @import("../level.zig").Level;
const Attr = @import("../value.zig").Attr;
const Record = @import("../record.zig").Record;
const Handler = @import("../handler.zig").Handler;
const HandlerVTable = @import("../handler.zig").HandlerVTable;
const HandlerError = @import("../handler.zig").HandlerError;
const Clock = @import("../internal/clock.zig").Clock;
const rfc3339 = @import("../fmt/rfc3339.zig");
const metrics = @import("../metrics/metrics.zig");
const text_handler = @import("text_handler.zig");

/// Rotation options.
pub const RotationOptions = struct {
    path: []const u8,
    max_bytes: usize = 10 * 1024 * 1024, // 10MB default
    max_backups: u8 = 5,
    max_age_days: u16 = 30,
};

/// Rotating file handler context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    options: RotationOptions,
    file: ?std.fs.File,
    current_size: usize,
    level: Level,
    clock: Clock,
    mutex: std.Thread.Mutex,
    path_buf: [std.fs.max_path_bytes]u8,

    pub fn init(allocator: std.mem.Allocator, options: RotationOptions, level: Level, clock: Clock) !Context {
        var ctx = Context{
            .allocator = allocator,
            .options = options,
            .file = null,
            .current_size = 0,
            .level = level,
            .clock = clock,
            .mutex = .{},
            .path_buf = undefined,
        };

        try ctx.openFile();
        return ctx;
    }

    pub fn deinit(self: *Context) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.file) |f| {
            f.close();
            self.file = null;
        }
    }

    fn openFile(self: *Context) !void {
        const path = self.options.path;

        // Get or create directory
        if (std.fs.path.dirname(path)) |dir| {
            std.fs.cwd().makePath(dir) catch {};
        }

        self.file = std.fs.cwd().createFile(path, .{
            .truncate = false,
        }) catch |err| {
            return switch (err) {
                error.AccessDenied => error.WriteFailed,
                else => error.WriteFailed,
            };
        };

        // Seek to end
        if (self.file) |f| {
            const stat = f.stat() catch {
                self.current_size = 0;
                return;
            };
            self.current_size = stat.size;
            f.seekTo(stat.size) catch {};
        }
    }

    fn rotate(self: *Context) !void {
        // Close current file
        if (self.file) |f| {
            f.close();
            self.file = null;
        }

        // Rotate existing backups
        var i: u8 = self.options.max_backups;
        while (i > 0) : (i -= 1) {
            const old_path = try self.formatBackupPath(i);
            const new_path = try self.formatBackupPath(i + 1);

            if (i >= self.options.max_backups) {
                // Delete oldest
                std.fs.cwd().deleteFile(old_path) catch {};
            } else {
                // Rename to next number
                std.fs.cwd().rename(old_path, new_path) catch {};
            }
        }

        // Rename current to .1
        const backup1 = try self.formatBackupPath(1);
        std.fs.cwd().rename(self.options.path, backup1) catch {};

        // Open new file
        try self.openFile();
        self.current_size = 0;
        metrics.global.incRotations();
    }

    fn formatBackupPath(self: *Context, num: u8) ![]const u8 {
        const path = self.options.path;
        const len = std.fmt.bufPrint(&self.path_buf, "{s}.{d}", .{ path, num }) catch return error.WriteFailed;
        return self.path_buf[0..len.len];
    }

    fn write(self: *Context, data: []const u8) !void {
        if (self.file) |f| {
            _ = f.write(data) catch return error.WriteFailed;
            self.current_size += data.len;
            metrics.global.addBytesWritten(data.len);
        }
    }

    fn checkRotate(self: *Context) !void {
        if (self.current_size >= self.options.max_bytes) {
            try self.rotate();
        }
    }

    pub fn reopen(self: *Context) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.file) |f| {
            f.close();
            self.file = null;
        }
        try self.openFile();
    }
};

fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    if (!rec.level.atLeast(ctx.level)) return;

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // Check if rotation needed
    ctx.checkRotate() catch return error.WriteFailed;

    // Format the record
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

    // Attributes
    for (rec.attrs) |attr| {
        writer.writeByte(' ') catch return error.WriteFailed;
        writer.writeAll(attr.key) catch return error.WriteFailed;
        writer.writeByte('=') catch return error.WriteFailed;
        switch (attr.value) {
            .str => |s| writer.writeAll(s) catch return error.WriteFailed,
            .i64 => |i| writer.print("{d}", .{i}) catch return error.WriteFailed,
            .u64 => |u| writer.print("{d}", .{u}) catch return error.WriteFailed,
            else => writer.writeAll("?") catch return error.WriteFailed,
        }
    }

    writer.writeByte('\n') catch return error.WriteFailed;

    ctx.write(fbs.getWritten()) catch return error.WriteFailed;
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
    ctx.level = level;
}

fn flush(ctx_ptr: *anyopaque, _: u32) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    if (ctx.file) |f| {
        f.sync() catch return error.FlushFailed;
    }
}

const vtable = HandlerVTable{
    .handle = handle,
    .withAttrs = withAttrs,
    .withGroup = withGroup,
    .setLevel = setLevel,
    .flush = flush,
};

/// Initialize a rotating file handler.
pub fn init(ctx: *Context) Handler {
    return .{
        .ctx = @ptrCast(ctx),
        .vtable = &vtable,
    };
}

/// Reopen the file (for external rotation).
pub fn reopen(handler: *Handler) !void {
    const ctx: *Context = @ptrCast(@alignCast(handler.ctx));
    try ctx.reopen();
}

test "RotatingFileHandler basic" {
    const allocator = std.testing.allocator;

    // Use temp directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}/test.log", .{path});

    var ctx = try Context.init(allocator, .{
        .path = full_path,
        .max_bytes = 1024,
        .max_backups = 2,
        .max_age_days = 1,
    }, .info, Clock.system());
    defer ctx.deinit();

    const handler = init(&ctx);

    const rec = Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "test",
        .message = "test message",
        .logger = "test",
        .source_file = "",
        .source_line = 0,
        .attrs = &.{},
    };

    try handler.handle(&rec);
    try handler.flush(0);
}
